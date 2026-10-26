// Будівлі й руїни (PropLayer): матеріал GLB (альбедо, нормалі, шорсткість) плюс розчинення
// растром над юнітом, мокрість за погодою і імла кільця. Лише для будівель: дах — єдине, що може
// сховати юніта, а дрібні пропси й мости лишаються зі своїм матеріалом.
shader_type spatial;
render_mode blend_mix, cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float roughness = 0.9;
uniform float metallic = 0.0;

// Мокрість карти (WeatherRig, BattleLook.wetness): ті самі ассети стоять і на сухих сонячних
// картах, тож вологу не запечено в альбедо — вона тут, за погодою.
global uniform float weather_wetness;
// Повна відповідь уже на мокрості River (0.55); 0 — суха карта без змін.
const float WET_FULL = 0.5;
// Мокра стіна темніє до 0.36 альбедо: світла штукатурка на 0.55 лишалась у 1.4 раза яскравішою за
// мокру землю, найяскравішою річчю похмурого кадру.
const float WET_WALL = 0.36;
const float WET_ROOF = 0.75;
// Мокрий дах — м'який полиск: на 0.3 блік лягав на гофр рівними білими смугами.
const float WET_ROOF_ROUGHNESS = 0.5;
// Смуга бруду внизу стіни (~0.65 м, клітинка — 8 м) і темніший стик із землею (~0.15 м).
const float GRIME_H = 0.08;
const float GRIME = 0.6;
const float CONTACT_H = 0.02;
const float CONTACT = 0.6;
const vec3 WALL_WARM = vec3(1.08, 1.0, 0.86);

varying vec3 world_pos;
varying vec3 world_normal;
// Висота над підошвою будівлі (початок екземпляра стоїть на найнижчій точці під слідом).
varying float base_h;
// Частка викинутих пікселів (INSTANCE_CUSTOM.a): 0 — суцільна, 0.7 — крізь дах видно юніта.
varying flat float v_fade;
// Відтінок даху екземпляра (INSTANCE_CUSTOM.rgb); нулі — поза MultiMesh, без відтінку.
varying flat vec3 v_roof_tint;

#include "res://game/battle/shaders/surroundings.gdshaderinc"

// Поріг матриці Баєра 4×4: розчинення растром лишає матеріал непрозорим (без сортування й
// без другого проходу), а дірки на 1 піксель на телефоні зливаються в напівпрозорість.
float bayer4(vec2 frag) {
	ivec2 p = ivec2(mod(frag, 4.0));
	int i = p.x + p.y * 4;
	float m[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[i] + 0.5) / 16.0;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	base_h = world_pos.y - MODEL_MATRIX[3].y;
	v_fade = INSTANCE_CUSTOM.a;
	v_roof_tint = dot(INSTANCE_CUSTOM.rgb, INSTANCE_CUSTOM.rgb) < 1e-4 ? vec3(1.0) : INSTANCE_CUSTOM.rgb;
}

void fragment() {
	if (v_fade > bayer4(FRAGCOORD.xy)) {
		discard;
	}
	vec3 albedo = texture(albedo_tex, UV).rgb * albedo_color.rgb;
	float roof_k = smoothstep(0.4, 0.7, world_normal.y);
	albedo *= mix(vec3(1.0), v_roof_tint, roof_k);
	// Стіни тепліші: під блакитним небом сонячних карт сіра штукатурка ставала синюватою.
	albedo *= mix(WALL_WARM, vec3(1.0), roof_k);
	float rough = roughness;
	float wet = smoothstep(0.0, WET_FULL, weather_wetness);
	if (wet > 0.0) {
		float roof = smoothstep(0.4, 0.7, world_normal.y);
		albedo *= mix(1.0, mix(WET_WALL, WET_ROOF, roof), wet);
		rough = mix(rough, WET_ROOF_ROUGHNESS, wet * roof);
		float grime = 1.0 - smoothstep(0.0, GRIME_H, base_h);
		float contact = 1.0 - smoothstep(0.0, CONTACT_H, base_h);
		albedo *= mix(1.0, GRIME, wet * grime) * mix(1.0, CONTACT, wet * contact);
	}
	ALBEDO = albedo;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	ROUGHNESS = rough;
	METALLIC = metallic;
	FOG = vec4(0.0);
	if (surround) {
		vec4 haze = fog_bank(world_pos, CAMERA_POSITION_WORLD, normalize(-INV_VIEW_MATRIX[2].xz));
		ALBEDO = surround_grade(albedo, haze.a);
		// Без лінії межі: на стіні вона лягла б зламом, а будинки кільця за межею й так стоять.
		FOG = surround_fog(haze, 0.0);
	}
}
