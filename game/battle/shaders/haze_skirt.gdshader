// Заслін за кільцем (Surroundings.skirt): рівно колір серпанку, без світла, — щоб за краєм світу
// не проступав ні колір очищення, ні край меша на будь-якому віддаленні й зсуві камери.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

uniform vec3 color = vec3(0.10, 0.135, 0.155);

void fragment() {
	ALBEDO = color;
}
