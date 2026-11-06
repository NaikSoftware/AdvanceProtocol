// Стовпи й шафи ЛЕП (PropLayer._hazed) на карті з кільцем: той самий вигляд, що й імпортований
// StandardMaterial3D (альбедо, нормалі, шорсткість, метал, спекуляр), плюс імла кільця, як у
// будинків (prop_fade.gdshader). Стандартний матеріал імли не знає: лінія в кільці лишалась темною
// й чіткою поверх пелени, у якій тонуть хати поруч.
shader_type spatial;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool use_normal_tex = false;
uniform float normal_scale = 1.0;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float roughness = 1.0;
uniform float metallic = 0.0;
uniform float specular = 0.5;

varying vec3 world_pos;

#include "res://game/battle/shaders/surroundings.gdshaderinc"

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 albedo = texture(albedo_tex, UV).rgb * albedo_color.rgb;
	ALBEDO = albedo;
	if (use_normal_tex) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}
	ROUGHNESS = roughness;
	METALLIC = metallic;
	SPECULAR = specular;
	FOG = vec4(0.0);
	if (surround) {
		vec4 haze = fog_bank(world_pos, CAMERA_POSITION_WORLD, normalize(-INV_VIEW_MATRIX[2].xz));
		ALBEDO = surround_grade(albedo, haze.a);
		FOG = surround_fog(haze, 0.0);
	}
}
