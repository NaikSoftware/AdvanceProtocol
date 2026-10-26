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

void fragment() {
	vec4 tex = texture(albedo_tex, UV) * albedo_color;
	if (use_vertex_color) {
		tex *= COLOR;
	}
	if (alpha_cut > 0.0 && tex.a < alpha_cut) {
		discard;
	}
	ALBEDO = tex.rgb;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	vec3 up = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	// Тильний бік рушій сам перевертає (cull_disabled); нахил до неба вирівнює обидва.
	NORMAL = normalize(mix(NORMAL, up, sky_bend));
}
