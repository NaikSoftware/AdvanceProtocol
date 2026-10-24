// Тимчасовий настил і руїни мосту (BoardView._add_placeholder_multimesh): матовий колір, як
// StandardMaterial3D, плюс імла й лінія межі — міст кільця не мусить світитись крізь імлу.
shader_type spatial;
render_mode blend_mix, cull_back;

uniform vec3 albedo : source_color = vec3(0.42, 0.42, 0.4);

varying vec3 world_pos;

#include "res://game/battle/shaders/surroundings.gdshaderinc"

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	ALBEDO = albedo;
	ROUGHNESS = 0.95;
	FOG = vec4(0.0);
	if (surround) {
		vec4 haze = fog_bank(world_pos, CAMERA_POSITION_WORLD, normalize(-INV_VIEW_MATRIX[2].xz));
		ALBEDO = surround_grade(albedo, haze.a);
		// Настил рівний: площина лінії — він сам.
		float line_a = surround_line(world_pos, CAMERA_POSITION_WORLD, world_pos.y, VIEWPORT_SIZE);
		FOG = surround_fog(haze, line_a);
	}
}
