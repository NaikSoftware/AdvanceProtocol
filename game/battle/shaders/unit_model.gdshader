// Модель юніта з GLB: одна сітка й один матеріал на тип, спільні для всіх власників, тож колір
// власника і пройдений шлях — instance uniform, а не окремий матеріал (один виклик малювання).
// COLOR: R — 0 (без кольору власника), G — траки, B — колеса, що крутяться; альфа коліс —
// половина швидкості обертання відносно опорних котків: менші ведуче й напрямне колеса крутяться
// швидше, інакше їхні зуби ковзали б відносно гусениці.
// UV2: на траках x — довжина по контуру гусениці в одиницях моделі, y — 0..1 поперек; на
// колесах — (y, z) осі цього колеса.
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
// Смуга траку в атласі: верхня 1/16 текстури на всю ширину, рівно один період малюнка — 0,25
// одиниці моделі (2 м гусениці). Трак бере текстуру звідти за UV2, а не за UV, тож малюнок
// біжить по контуру разом із пройденим шляхом.
const float TREAD_PERIOD = 0.25;
const float TREAD_STRIP = 0.0625;
// Загиблий лише темніший за живого й трохи брудніший — та сама тканина, не інша форма й не мох: стоячі
// фігури — це HP відділення, тож лежачі не сміють із ними зливатися. Тьмяніє (FALLEN_DARK, лінійний
// множник), насиченість — як у живого до потемніння (FALLEN_SAT), і лягає ледь тепліший відтінок грязюки
// (FALLEN_MUD: сильніший зсував тон на 9–10° від живого, і тіла читались іншою формою). Грані, звернені
// до неба, приглушені (FALLEN_TOP): під сонцем вони світлішали за ріллю. Слабке власне світло
// (FALLEN_FILL) підіймає тіньовий бік: без нього затінена половина тіла сідала в чорне.
// Під похмурим небом (River) світло рівне, а мокра рілля темна й сіра: тіло з тими самими множниками
// читалось сірою грудкою (насиченість ~4, тон зсунутий у зелень, перепад усередині тіла 7 L*). Там свої
// значення (`_OVERCAST`, змішуються за sky_clear): темніє менше, тепліший хакі, верх не приглушений, а
// грані, звернені вбік і вниз, темнішають (FALLEN_SIDE_OVERCAST) — перепад тримають складки, не підсвітка.
const float FALLEN_DARK = 0.25;
const float FALLEN_DARK_OVERCAST = 0.22;
const float FALLEN_SAT = 1.0;
const float FALLEN_SAT_OVERCAST = 0.7;
const vec3 FALLEN_MUD = vec3(1.03, 1.0, 0.96);
const vec3 FALLEN_MUD_OVERCAST = vec3(1.07, 1.0, 0.88);
const float FALLEN_TOP = 0.8;
const float FALLEN_TOP_OVERCAST = 1.15;
const float FALLEN_SIDE_OVERCAST = 1.0;
const float FALLEN_FILL = 0.45;
// Найтемніше на тілі (гвинтівка) — темно-сіре, не чорна діра: власне світло пропорційне кольору її не підіймає.
const float FALLEN_FLOOR = 0.004;
// Матеріал загиблих (UnitSilhouettes.fallen_material()): один на набір, тож шар тіл — один виклик.
uniform bool fallen = false;
global uniform float sky_clear;

instance uniform float travel = 0.0;

void vertex() {
	if (COLOR.b > 0.5) {
		// Їдучи вперед (-Z), верх колеса йде вперед: поворот довкола X на -шлях/радіус.
		float a = -travel / wheel_radius * 2.0 * COLOR.a;
		mat2 r = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a)));
		VERTEX.yz = UV2 + r * (VERTEX.yz - UV2);
		NORMAL.yz = r * NORMAL.yz;
		TANGENT.yz = r * TANGENT.yz;
		BINORMAL.yz = r * BINORMAL.yz;
	}
}

void fragment() {
	vec2 uv = UV;
	vec2 ddx = dFdx(UV);
	vec2 ddy = dFdy(UV);
	if (COLOR.g > 0.5) {
		// Похідні — від неперервної координати: fract() інакше дає шов mip-рівнів на стику періодів.
		vec2 t = vec2((UV2.x + travel) / TREAD_PERIOD, UV2.y * TREAD_STRIP);
		uv = vec2(fract(t.x), t.y);
		ddx = dFdx(t);
		ddy = dFdy(t);
	}
	vec3 col = (textureGrad(albedo_tex, uv, ddx, ddy) * albedo_color).rgb;
	if (fallen) {
		float y = dot(col, vec3(0.2126, 0.7152, 0.0722));
		float sky = clamp((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y, 0.0, 1.0);
		float sun = smoothstep(0.3, 0.7, sky_clear);
		float sat = mix(FALLEN_SAT_OVERCAST, FALLEN_SAT, sun);
		vec3 mud = mix(FALLEN_MUD_OVERCAST, FALLEN_MUD, sun);
		float dark = mix(FALLEN_DARK_OVERCAST, FALLEN_DARK, sun);
		float top = mix(FALLEN_TOP_OVERCAST, FALLEN_TOP, sun);
		float side = mix(mix(FALLEN_SIDE_OVERCAST, 1.0, sky), 1.0, sun);
		col = max(mix(vec3(y), col, sat), vec3(0.0)) * mud * dark * mix(1.0, top, sky) * side;
		// Лише під ясним небом: там сонце лишає тіньовий бік у чорному. Під похмурим (River) світло й так
		// рівне, а ґрунт темний — підсвічене тіло читалось би світлішим за ріллю й зсувало тон.
		EMISSION = (col * FALLEN_FILL + vec3(FALLEN_FLOOR)) * sun;
	}
	ALBEDO = col;
	vec4 orm = textureGrad(orm_tex, uv, ddx, ddy);
	ROUGHNESS = roughness * dot(orm, roughness_channel);
	METALLIC = metallic * dot(orm, metallic_channel);
	// R атласу — запечене затінення: у швах і западинах небо не відбивається, тож шов лишається
	// темним, а не вкривається тим самим молочним полиском, що й панель довкола.
	SPECULAR = specular * orm.r;
	NORMAL_MAP = textureGrad(normal_tex, uv, ddx, ddy).rgb;
	NORMAL_MAP_DEPTH = normal_scale;
}
