shader_type spatial;
// Покриття настилу мосту: те саме, що StandardMaterial3D ассета (альбедо × колір, нормаль, шорсткість
// з каналу G), а на кінцях — перехід до тону дороги на березі. Дорога на кожному в'їзді своя (асфальт
// південного й північного в'їздів різниться на чверть), тож один тон настилу не збігається з обома, і
// на стику лишалась сходинка яскравості. Кінець настилу (локальна вісь Z моделі) множиться на
// end_lo / end_hi, і за `fade` від стику множник плавно повертається до 1.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_roughness_g, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 albedo : source_color = vec4(1.0);
uniform float roughness = 1.0;
uniform float specular = 0.5;
uniform bool use_rough_tex = true;
// Множники лінійного альбедо на кінці −Z і +Z моделі.
uniform vec3 end_lo = vec3(1.0);
uniform vec3 end_hi = vec3(1.0);
// Половина довжини моделі вздовж Z і відстань від її кінця до стику з насипом (клітинки).
uniform float half_len = 1.0;
uniform float joint = 0.16;
uniform float fade = 0.06;
// Половина ширини цього покриття: до бортів перехід згасає, тож світлий кінець не лягає прямокутником
// із прямими боками вздовж бортів.
uniform float edge_x = 0.35;

varying float local_z;
varying float local_x;

void vertex() {
	local_z = VERTEX.z;
	local_x = VERTEX.x;
}

void fragment() {
	float t = smoothstep(half_len - joint - fade, half_len - joint, abs(local_z))
			* (1.0 - smoothstep(0.45 * edge_x, edge_x, abs(local_x)));
	vec3 tint = mix(vec3(1.0), local_z < 0.0 ? end_lo : end_hi, t);
	ALBEDO = albedo.rgb * texture(albedo_tex, UV).rgb * tint;
	ROUGHNESS = use_rough_tex ? texture(rough_tex, UV).g * roughness : roughness;
	METALLIC = 0.0;
	SPECULAR = specular;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
}
