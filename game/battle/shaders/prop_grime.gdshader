// Пояс бруду довкола хати (PropLayer): смуга ~0.5 м уздовж стін, на 35 % темніша за ґрунт. Земля
// біля стіни витоптана й забризкана — без неї хата стоїть на траві «як вставлена».
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;

// Ширина смуги в частках квадрата (квадрат — слід хати разом із поясом, PropLayer).
uniform float band = 0.1;
uniform float strength = 0.35;

void fragment() {
	// Відстань від краю квадрата: 0 — зовнішній край поясу, band — стіна хати.
	vec2 e = min(UV, 1.0 - UV);
	float d = min(e.x, e.y);
	ALBEDO = vec3(0.0);
	ALPHA = strength * smoothstep(0.0, band, d);
}
