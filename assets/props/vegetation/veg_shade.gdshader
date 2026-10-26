shader_type spatial;
// Пляма затінення під кущем чи купою (поверхня 1 рослини): чорне з альфою = R кольору вершини
// (0,35–0,45) × маска атласу — м'який край, неправильна форма, у центрі ґрунт темніший щонайбільше
// на R. Не blend_mul: його результат іде через тонмапінг, і «1» поза плямою вже не нейтральне —
// видно прямокутник картки. Тіні не кидає й не пише глибину.
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_disable;

void fragment() {
	if (PROJECTION_MATRIX[3][3] > 0.5) {
		discard;  // прохід тіні напрямленого світла
	}
	ALBEDO = vec3(0.0);
	ALPHA = COLOR.r * texture(albedo_tex, UV).a;
}
