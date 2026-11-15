// Тіла загиблих (UnitSilhouettes.fallen_material()): та сама модель бійця, але темніша й брудніша, а підсвітка
// тіньового боку — у власному світлі, а не у випромінюванні: випромінювання додається після освітлення, і тінь
// його не гасила б, тож тіло в тіні будівлі чи уламка світилось би на темній землі. Тут підсвітка йде крізь
// ATTENUATION сонця, як і саме світло. Дифузне світло — те саме, що за замовчуванням (Ламберт, ділене на PI);
// блиск у світлі не відтворюється: F0 діелектрика при `specular` 0,1 — 0,0016.
shader_type spatial;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float normal_scale = 1.0;
// glTF кладе шорсткість і металевість в одну текстуру: канали задає імпортований матеріал.
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 roughness_channel = vec4(0.0, 1.0, 0.0, 0.0);
uniform vec4 metallic_channel = vec4(0.0, 0.0, 1.0, 0.0);
uniform float roughness = 1.0;
uniform float metallic = 0.0;
// Типові 0,5 власного шейдера світлішають модель проти імпортованого матеріалу: беремо його.
uniform float specular = 0.5;
uniform float wheel_radius = 0.06;
// Загиблий лише темніший за живого й трохи брудніший — та сама тканина, не інша форма й не мох: стоячі
// фігури — це HP відділення, тож лежачі не сміють із ними зливатися. Тьмяніє (FALLEN_DARK, лінійний
// множник), насиченість — як у живого до потемніння (FALLEN_SAT), і лягає ледь тепліший відтінок грязюки
// (FALLEN_MUD: сильніший зсував тон на 9–10° від живого, і тіла читались іншою формою). Грані, звернені
// до неба, приглушені (FALLEN_TOP): під сонцем вони світлішали за ріллю. Слабке власне світло
// (FALLEN_FILL) підіймає тіньовий бік: без нього затінена половина тіла сідала в чорне.
// Під похмурим небом (River) світло рівне, а мокра рілля темна й сіра: тіло з тими самими множниками
// читалось сірою грудкою (насиченість ~4, тон зсунутий у зелень, перепад усередині тіла 7 L*). Там свої
// значення (`_OVERCAST`, змішуються за sky_clear): насиченість 0,7, тепліший хакі
// (FALLEN_MUD_OVERCAST), а грані до неба не приглушені, а підняті (FALLEN_TOP_OVERCAST 1,15) — перепад
// усередині тіла тримають вони. Множник потемніння трохи нижчий за сонячний (0,22), щоб із піднятим верхом
// середина тіла не світлішала за ріллю.
const float FALLEN_DARK = 0.25;
const float FALLEN_DARK_OVERCAST = 0.22;
const float FALLEN_SAT = 1.0;
const float FALLEN_SAT_OVERCAST = 0.7;
const vec3 FALLEN_MUD = vec3(1.03, 1.0, 0.96);
const vec3 FALLEN_MUD_OVERCAST = vec3(1.07, 1.0, 0.88);
const float FALLEN_TOP = 0.8;
const float FALLEN_TOP_OVERCAST = 1.15;
const float FALLEN_FILL = 0.45;
// Найтемніше на тілі (гвинтівка) — темно-сіре, не чорна діра: власне світло пропорційне кольору її не підіймає.
const float FALLEN_FLOOR = 0.004;
global uniform float sky_clear;

void fragment() {
	vec3 col = (texture(albedo_tex, UV) * albedo_color).rgb;
	float y = dot(col, vec3(0.2126, 0.7152, 0.0722));
	float sky = clamp((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y, 0.0, 1.0);
	float sun = smoothstep(0.3, 0.7, sky_clear);
	float sat = mix(FALLEN_SAT_OVERCAST, FALLEN_SAT, sun);
	vec3 mud = mix(FALLEN_MUD_OVERCAST, FALLEN_MUD, sun);
	float dark = mix(FALLEN_DARK_OVERCAST, FALLEN_DARK, sun);
	float top = mix(FALLEN_TOP_OVERCAST, FALLEN_TOP, sun);
	col = max(mix(vec3(y), col, sat), vec3(0.0)) * mud * dark * mix(1.0, top, sky);
	ALBEDO = col;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	// gl_compatibility: власне світло (light()) там не підключено, бо воно виходило вдвічі темнішим за стандартне, а SPECULAR,
	// відмінний від 0,5, чорнить поверхню. Лишається стандартне світло й рівна підсвітка у випромінюванні, без затінення.
	EMISSION = col * FALLEN_FILL * sun + vec3(FALLEN_FLOOR * sun);
#else
	EMISSION = vec3(FALLEN_FLOOR * sun);
#endif
	vec4 orm = texture(orm_tex, UV);
	ROUGHNESS = roughness * dot(orm, roughness_channel);
	METALLIC = metallic * dot(orm, metallic_channel);
#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
	SPECULAR = specular * orm.r;
#endif
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = normal_scale;
}

#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
void light() {
	float n_l = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * (n_l / PI);
	// Блиск за замовчуванням (GGX, F0 з `specular`): при шорсткості 1 і низькому сонці дає помітну частку.
	float n_v = clamp(dot(NORMAL, VIEW), 0.0001, 1.0);
	vec3 h = normalize(VIEW + LIGHT);
	float n_h = clamp(dot(NORMAL, h), 0.0, 1.0);
	float v_h = clamp(dot(VIEW, h), 0.0, 1.0);
	float a2 = pow(max(ROUGHNESS, 0.045), 4.0);
	float d = a2 / (PI * pow(n_h * n_h * (a2 - 1.0) + 1.0, 2.0));
	float vis = 0.5 / (n_l * sqrt(n_v * n_v * (1.0 - a2) + a2) + n_v * sqrt(n_l * n_l * (1.0 - a2) + a2) + 0.0001);
	float f0 = 0.16 * specular * specular;
	float f = f0 + (1.0 - f0) * pow(1.0 - v_h, 5.0);
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * (n_l * d * vis * f);
	if (LIGHT_IS_DIRECTIONAL) {
		// Рівна підсвітка без кольору й сили сонця (не LIGHT_COLOR); тінь гасить її так само, як саме сонце.
		float sun = smoothstep(0.3, 0.7, sky_clear);
		DIFFUSE_LIGHT += vec3(FALLEN_FILL * sun) * ATTENUATION;
	}
}
#endif
