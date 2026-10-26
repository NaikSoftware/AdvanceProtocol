// Пляма дотику під брилою чи бетонним блоком (PropLayer): м'яке затемнення землі довкола підошви.
// Не тінь сонця — та лише юнітам і будівлям; пляма лише прибирає «наклеєність» каменя на траві.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;

uniform float strength = 0.45;

void fragment() {
	// UV площини 0..1: кругла пляма з м'яким краєм, найтемніша під самим каменем.
	float r = length(UV - vec2(0.5)) * 2.0;
	ALBEDO = vec3(0.0);
	ALPHA = strength * (1.0 - smoothstep(0.35, 1.0, r));
}
