// Огорожі (PropLayer): тонкі панелі, видимі з обох боків. Нормаль імпортованої панелі лежить
// горизонтально, тож на сонці освітлено лише один бік, а другий бере тільки синє небо й чорніє.
// Нормаль нахилено до неба: обидва боки освітлені майже як дерево на сонці, тіньовий — ~0.83.
shader_type spatial;
render_mode blend_mix, cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform bool use_vertex_color = false;
uniform float alpha_cut = 0.0;
uniform float roughness = 0.9;
uniform float metallic = 0.0;
// Частка неба в нормалі: 0 — нормаль ассета, 1 — освітлення як у горизонтальної площини.
uniform float sky_bend = 0.65;

// Мокрість карти (WeatherRig): на мокрій River панель темніша, сіро-бежева (насиченість ≤ 0.1) і
// з брудом унизу — кольорова огорожа світилась би, як пофарбована щойно.
global uniform float weather_wetness;
const float WET_FULL = 0.5;
const float WET_DARK = 0.75;
const vec3 WET_TONE = vec3(1.0, 0.96, 0.9);
// Бруд біля землі: ~0.5 м (клітинка — 8 м).
const float DIRT_H = 0.06;
const float DIRT = 0.6;

varying float base_h;

void vertex() {
	base_h = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y - MODEL_MATRIX[3].y;
}

void fragment() {
	vec4 tex = texture(albedo_tex, UV) * albedo_color;
	if (use_vertex_color) {
		tex *= COLOR;
	}
	if (alpha_cut > 0.0 && tex.a < alpha_cut) {
		discard;
	}
	vec3 albedo = tex.rgb;
	float wet = smoothstep(0.0, WET_FULL, weather_wetness);
	if (wet > 0.0) {
		float luma = dot(albedo, vec3(0.2126, 0.7152, 0.0722));
		albedo = mix(albedo, luma * WET_TONE, wet) * mix(1.0, WET_DARK, wet);
		albedo *= mix(1.0, DIRT, wet * (1.0 - smoothstep(0.0, DIRT_H, base_h)));
	}
	ALBEDO = albedo;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	vec3 up = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	// Тильний бік рушій сам перевертає (cull_disabled); нахил до неба вирівнює обидва.
	NORMAL = normalize(mix(NORMAL, up, sky_bend));
}
