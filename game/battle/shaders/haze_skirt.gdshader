// Заслін за кільцем (`Surroundings.skirt`): суцільний верх серпанку без світла — щоб за краєм
// світу не проступав ні колір очищення, ні край меша на будь-якому віддаленні й зсуві камери. Той
// самий `fog_bank`, що й на землі кільця: з `haze_closed` серпанок суцільний, і шва нема.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

varying vec3 world_pos;

#include "res://game/battle/shaders/surroundings.gdshaderinc"

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Ближче заслін лежить під землею кільця й не видний: шум там не рахуємо.
	ALBEDO = haze_color;
	if (board_distance(world_pos.xz) >= haze_closed - 1.0) {
		ALBEDO = fog_bank(world_pos, CAMERA_POSITION_WORLD, normalize(-INV_VIEW_MATRIX[2].xz)).rgb;
	}
}
