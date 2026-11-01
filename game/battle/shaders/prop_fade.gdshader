// Будівлі й руїни (PropLayer): матеріал GLB (альбедо, нормалі, шорсткість) плюс напівпрозорість
// над юнітом, мокрість за погодою і імла кільця. Лише для будівель: дах — єдине, що може сховати
// юніта, а дрібні пропси й мости лишаються зі своїм матеріалом.
// Розчинення над юнітом — звичайна альфа, не растр (сіточка читалась шаховою решіткою), у два
// проходи (PropLayer._fade_material): FADE_DEPTH пише лише глибину, FADE_ALPHA (next_pass) малює
// колір без запису глибини — тест глибини пропускає тільки передню грань, тож будівля не
// просвічує сама крізь себе (вбудований depth_prepass_alpha при альфі 0.35 глибини не пише).
shader_type spatial;
#ifdef FADE_DEPTH
render_mode blend_mix, cull_disabled, depth_draw_always, unshaded;
#else
#ifdef FADE_ALPHA
render_mode blend_mix, cull_disabled, depth_draw_never;
#else
render_mode blend_mix, cull_disabled;
#endif
#endif

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
// Шорсткість і металічність: число множиться на карту (glTF ORM: G — шорсткість, B — метал), як у
// StandardMaterial3D. Одне число на весь дім давало рівний блік — «пластик».
uniform float roughness = 0.9;
uniform float metallic = 0.0;
uniform sampler2D roughness_tex : hint_roughness_g, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 roughness_channel = vec4(0.0, 1.0, 0.0, 0.0);
uniform bool use_roughness_tex = false;
uniform sampler2D metallic_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 metallic_channel = vec4(0.0, 0.0, 1.0, 0.0);
uniform bool use_metallic_tex = false;
// Затінення (AO) з атласу: шви, кути, піддашшя.
uniform sampler2D ao_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 ao_channel = vec4(1.0, 0.0, 0.0, 0.0);
uniform bool use_ao_tex = false;
uniform float ao_light_affect = 0.0;
uniform float normal_scale = 1.0;
// Спекуляр мінеральних поверхонь (тиньк, цегла, шифер) ≤ 0.3; типові 0.5 блищать, як пластик.
uniform float specular = 0.3;

// Мокрість карти (WeatherRig, BattleLook.wetness): ті самі ассети стоять і на сухих сонячних
// картах, тож вологу не запечено в альбедо — вона тут, за погодою.
global uniform float weather_wetness;
// Повна відповідь уже на мокрості River (0.55); 0 — суха карта без змін.
const float WET_FULL = 0.5;
// Мокрий дах темніє не менше за стіну: дощ б'є в нього прямо. Коли стіна темніла вдвічі сильніше
// (0.36 проти 0.75), дах на Річці ставав світлішим за стіни.
const float WET_WALL = 0.5;
const float WET_ROOF = 0.45;
// Мокрий дах: листовий метал — шорсткість 0.35 і ледь помітний спекуляр неба; черепиця й шифер —
// 0.45 зі спекуляром мінералу: темнішають, але не блищать. Штукатурка шорсткості не міняє.
const float WET_ROOF_ROUGHNESS_METAL = 0.35;
const float WET_ROOF_ROUGHNESS = 0.45;
const float WET_SPECULAR_METAL = 0.5;
// Мокрий низ стіни (~0.5 м, клітинка — 8 м) — на ~28 % темніший; і темніший стик із землею (~0.15 м).
const float GRIME_H = 0.0625;
const float GRIME = 0.8;
const float CONTACT_H = 0.02;
const float CONTACT = 0.8;   // 0.6 давало чорну лінію на землі
const vec3 WALL_WARM = vec3(1.08, 1.0, 0.86);
const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);
// Рівень мипу, що усереднює ділянку даху в атласі.
const float ROOF_AVG_LOD = 5.0;
// Відтінки стін за кольором даху: світліша, сірувата, тепла рожевувата штукатурка; найтемніший не нижче WALL_TINT_MIN
// у prop_layer.gd (з ним дах теж лишається не світлішим за ROOF_WALL_MAX стіни) — різниця 6–10 % яскравості, без пастелі й насиченості.
const vec3 WALL_TINTS[4] = vec3[4](vec3(1.0), vec3(1.07, 1.06, 1.02), vec3(0.93, 0.94, 0.96), vec3(1.0, 0.95, 0.9));

varying vec3 world_pos;
varying vec3 world_normal;
// Висота над підошвою будівлі (початок екземпляра стоїть на найнижчій точці під слідом).
varying float base_h;
// Прозорість (INSTANCE_CUSTOM.a): 0 — суцільна; у варіанті FADE_ALPHA альфа = 1 − v_fade.
varying flat float v_fade;
// Колір даху екземпляра (INSTANCE_CUSTOM.rgb, лінійний); нулі — дах лишається з текстури моделі.
varying flat vec3 v_roof_tint;
varying flat float v_recolour;

#include "res://game/battle/shaders/surroundings.gdshaderinc"

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	base_h = world_pos.y - MODEL_MATRIX[3].y;
	v_fade = INSTANCE_CUSTOM.a;
	v_roof_tint = INSTANCE_CUSTOM.rgb;
	v_recolour = dot(INSTANCE_CUSTOM.rgb, INSTANCE_CUSTOM.rgb) < 1e-4 ? 0.0 : 1.0;
}

void fragment() {
	vec3 albedo = texture(albedo_tex, UV).rgb * albedo_color.rgb;
	float roof_k = smoothstep(0.3, 0.55, world_normal.y);
	// Стіни тепліші: під блакитним небом сонячних карт сіра штукатурка ставала синюватою.
	albedo *= mix(WALL_WARM, vec3(1.0), roof_k);
	if (v_recolour > 0.5) {
		// Дах — колір екземпляра, а рельєф дошок і швів — відношення яскравості текстури до її середньої довкола.
		float lum = dot(albedo, LUMA);
		float avg = max(dot(textureLod(albedo_tex, UV, ROOF_AVG_LOD).rgb * albedo_color.rgb, LUMA), 0.01);
		vec3 roof = v_roof_tint * clamp(lum / avg, 0.75, 1.3);
		// Колір ставиться лише на скати: справжня (не згладжена) нормаль грані; плоскі грані вгору — цоколь, підвіконня, шапка димаря,
		// підлога крізь розчинений дах — лишаються з текстури. Скати хат стоять між 0.3 і 0.93 за y нормалі.
		vec3 face_n = normalize(cross(dFdx(world_pos), dFdy(world_pos)));
		float roof_only = smoothstep(0.3, 0.55, abs(face_n.y)) * (1.0 - smoothstep(0.93, 0.97, abs(face_n.y)));
		// Стіни трохи різняться за тим самим кольором даху: чотири ледь помітні відтінки штукатурки.
		int wk = int(fract(sin(dot(v_roof_tint, vec3(12.9898, 78.233, 37.719))) * 43758.5453) * 4.0);
		albedo = mix(albedo * WALL_TINTS[wk], roof, roof_only);
	}
	float rough = roughness;
	if (use_roughness_tex) {
		rough *= dot(texture(roughness_tex, UV), roughness_channel);
	}
	float metal = metallic;
	if (use_metallic_tex) {
		metal *= dot(texture(metallic_tex, UV), metallic_channel);
	}
	float spec = specular;
	float wet = smoothstep(0.0, WET_FULL, weather_wetness);
	if (wet > 0.0) {
		float roof = smoothstep(0.4, 0.7, world_normal.y);
		albedo *= mix(1.0, mix(WET_WALL, WET_ROOF, roof), wet);
		float sheet = smoothstep(0.3, 0.6, metal);
		rough = mix(rough, mix(WET_ROOF_ROUGHNESS, WET_ROOF_ROUGHNESS_METAL, sheet), wet * roof);
		spec = mix(spec, WET_SPECULAR_METAL, wet * roof * sheet);
		float grime = 1.0 - smoothstep(0.0, GRIME_H, base_h);
		float contact = 1.0 - smoothstep(0.0, CONTACT_H, base_h);
		albedo *= mix(1.0, GRIME, wet * grime) * mix(1.0, CONTACT, wet * contact);
	}
	ALBEDO = albedo;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = normal_scale;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = spec;
	if (use_ao_tex) {
		AO = dot(texture(ao_tex, UV), ao_channel);
		AO_LIGHT_AFFECT = ao_light_affect;
	}
	FOG = vec4(0.0);
	if (surround) {
		vec4 haze = fog_bank(world_pos, CAMERA_POSITION_WORLD, normalize(-INV_VIEW_MATRIX[2].xz));
		ALBEDO = surround_grade(albedo, haze.a);
		// Без лінії межі: на стіні вона лягла б зламом, а будинки кільця за межею й так стоять.
		FOG = surround_fog(haze, 0.0);
	}
#ifdef FADE_DEPTH
	ALPHA = 0.0;
#endif
#ifdef FADE_ALPHA
	ALPHA = 1.0 - v_fade;
#endif
}
