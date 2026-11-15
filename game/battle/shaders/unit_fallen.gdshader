// Тіла загиблих (UnitSilhouettes.fallen_material()): колір і темніння — як у unit_model.gdshader (`fallen`), але
// світло власне: у unit_model підсвітка тіньового боку йшла в EMISSION і не гасла в тіні, кинутій уламком, тож
// тіло в тіні світліло за ґрунт навколо. Тут підсвітка лишається лише там, куди сонце не заступлене
// (ATTENUATION напрямного світла), а в тіні тіло темніє так само, як земля.
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
// Збігається з unit_model: у unit_model `fallen` вмикав гілку, тут вона єдина, але параметр лишається, щоб матеріал
// набору ставився однаково.
uniform bool fallen = true;

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
	vec4 orm = texture(orm_tex, UV);
	ROUGHNESS = roughness * dot(orm, roughness_channel);
	METALLIC = metallic * dot(orm, metallic_channel);
	SPECULAR = specular * orm.r;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = normal_scale;
}

// Власне світло: ламберт від сонця плюс підсвітка тіньового боку, обидва — крізь ATTENUATION (тінь).
void light() {
	if (LIGHT_IS_DIRECTIONAL) {
		float sun = smoothstep(0.3, 0.7, sky_clear);
		float lit = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
		DIFFUSE_LIGHT += (lit + FALLEN_FILL * sun) * ATTENUATION * LIGHT_COLOR / PI;
	}
}
