// Тимчасовий настил і руїни мосту (BoardView._add_placeholder_multimesh): матовий колір, як
// StandardMaterial3D, плюс серпанок і лінія межі — міст кільця не мусить світитись крізь серпанок.
shader_type spatial;
render_mode blend_mix, cull_back;

uniform vec3 albedo : source_color = vec3(0.42, 0.42, 0.4);

varying vec3 world_pos;

#include "res://game/battle/shaders/surroundings.gdshaderinc"

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 sd = surround_distance(world_pos.xz);
	ALBEDO = surround ? surround_grade(albedo, sd.x) : albedo;
	ROUGHNESS = 0.95;
	FOG = surround ? surround_fog(sd, VIEWPORT_SIZE) : vec4(0.0);
}
