shader_type spatial;
// Пляма затінення під рослиною (поверхня 1): чорне з альфою = R кольору вершини (0,25–0,3) × маска
// атласу — м'який край, неправильна форма. Не blend_mul: його результат іде через тонмапінг, і «1»
// поза плямою вже не нейтральне — видно прямокутник картки. На сонячній карті пляма витягується від
// сонця на довжину тіні рослини, як пляма дотику пропсів (prop_contact.gdshader): справжньої тіні
// сонця земля бою не показує. Сама тіні не кидає й не пише глибину.
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, world_vertex_coords;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_disable;
// 1 — карта з чіткою тінню сонця (PropLayer.structure_shadows), 0 — похмура: пляма лише під рослиною.
uniform float cast = 0.0;
// Напрям на сонце (WeatherRig): тінь лягає в протилежний бік.
global uniform vec3 sun_dir;

void vertex() {
	// B кольору вершини — висота крони над землею, у двох тайлах (0…1 → 0…2 тайли).
	vec3 centre = MODEL_MATRIX[3].xyz;
	vec2 away = VERTEX.xz - centre.xz;
	vec2 shadow = -sun_dir.xz / max(sun_dir.y, 0.35) * COLOR.b * 2.0 * cast;
	if (dot(shadow, shadow) > 1e-8 && dot(away, away) > 1e-8) {
		float far = 0.5 + 0.5 * dot(normalize(away), normalize(shadow));
		VERTEX.xz += shadow * far;
	}
}

void fragment() {
	ALBEDO = vec3(0.0);
	ALPHA = COLOR.r * texture(albedo_tex, UV).a;
}
