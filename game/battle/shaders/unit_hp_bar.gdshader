// Смуги HP усіх юнітів одним MultiMesh (`UnitHpBars`): білборд-квад на юніта, малюнок — шар масиву
// текстур за шириною заливки. Те саме, що Sprite3D із білбордом, без перевірки глибини й поверх
// ефектів: смуга читається завжди, але вузол юніта більше не коштує окремого виклику малювання.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled;

uniform sampler2DArray bars : source_color, filter_linear, repeat_disable;
// Розмір смуги у світі: ширина × висота квада (ставить UnitHpBars з розміру текстури).
uniform vec2 bar_size;

varying flat float layer;

void vertex() {
	layer = INSTANCE_CUSTOM.x;
	// Схований екземпляр (INSTANCE_CUSTOM.y = 1) — за межею кадру.
	vec3 centre = MODEL_MATRIX[3].xyz;
	vec3 world = centre + INV_VIEW_MATRIX[0].xyz * VERTEX.x * bar_size.x + INV_VIEW_MATRIX[1].xyz * VERTEX.y * bar_size.y;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
	if (INSTANCE_CUSTOM.y > 0.5) {
		POSITION = vec4(2.0, 2.0, 2.0, 1.0);
	}
}

void fragment() {
	vec4 c = texture(bars, vec3(UV, layer));
	ALBEDO = c.rgb;
	ALPHA = c.a;
}
