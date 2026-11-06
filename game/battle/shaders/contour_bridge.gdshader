shader_type spatial;
// Лінія зони на клітинці мосту: глибина зсунута до камери на висоту поручнів, тож поручні й
// бордюри її не ховають, а юніт, вищий за них, ховає. Точка лишається на тому ж промені камери,
// тож на екрані лінія стоїть там, де й без зсуву.
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

uniform float pull = 0.3;

void vertex() {
	vec3 v = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v -= normalize(v) * pull;
	POSITION = PROJECTION_MATRIX * vec4(v, 1.0);
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a;
}
