// Дощ (`WeatherRig`): один меш із N квадів; вершина несе випадкову точку в одиничній коробці
// (VERTEX) і свій кут квада (UV). Крапля нерухома у світі (пан дає правильний паралакс), а коробка
// загортається довкола фокуса камери, тож після пана чи зуму кадр одразу повний дощу.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, shadows_disabled, depth_draw_never;

// Світ: фокус камери на землі, розмір коробки (клітинки), її зсув до камери.
uniform vec3 focus;
uniform vec3 box_size = vec3(40.0, 14.0, 40.0);
uniform vec2 toward_camera = vec2(0.7071, 0.7071);
// Падіння, клітинок/с: 1.0 — 8 м/с. Вітер — горизонтальний знос тією ж мірою.
uniform float fall_speed = 1.0;
uniform vec2 wind = vec2(-0.1, 0.06);
// Смуга — розмитий рухом слід краплі: 8 м/с за витримку ~1/16 с — ~0.5 м. Камера дивиться
// згори, і такий слід стискається до 2–5 px, а кінці гасне — тоді смуга не коротша за 10 px,
// інакше дощ читається крапками-градом, а не тонкими лініями.
uniform float streak_length = 0.0625;
uniform float min_streak_px = 10.0;
// Справжня ширина сліду ~1 см — тонша за піксель; смуга малюється в 1.5 px (вужча похила смуга
// без згладжування рветься на окремі пікселі), а прозорість падає, тож лінія лишається ледь
// помітною, а не жирною.
uniform float streak_width = 0.0015;
// Трохи світліше за мокру землю під похмурим небом, не біле.
uniform vec4 tint : source_color = vec4(0.62, 0.65, 0.68, 0.25);

varying float v_along;
varying float v_fade;

void vertex() {
	vec3 seed = VERTEX;
	vec3 vel = vec3(wind.x, -fall_speed, wind.y);
	// Мінімальний кут коробки: на землі, трохи зсунутий до камери — там у кадрі ближча земля
	// й вища частина шару.
	vec3 lo = vec3(focus.x, 0.0, focus.z) - vec3(box_size.x, 0.0, box_size.z) * 0.5
			+ vec3(toward_camera.x, 0.0, toward_camera.y) * box_size.x * 0.15;
	vec3 c = lo + mod(seed * box_size + vel * TIME - lo, box_size);
	vec3 axis = normalize(vel);
	vec3 view = CAMERA_POSITION_WORLD - c;
	float dist = length(view);
	vec3 side = cross(axis, view / dist);
	// Частка довжини смуги, видима з камери (синус кута між смугою й променем зору).
	float seen = max(length(side), 0.2);
	side /= seen;
	// Розмір пікселя на цій відстані. abs: у Vulkan вісь Y проєкції перевернута, [1][1] < 0, і
	// без нього кожен max(…, px) мовчки брав світовий розмір.
	float px = 2.0 * dist / (abs(PROJECTION_MATRIX[1][1]) * VIEWPORT_SIZE.y);
	float w = max(streak_width, 1.5 * px);
	float len = max(streak_length, min_streak_px * px / seen);
	vec3 p = c + side * (UV.x - 0.5) * w + axis * (UV.y - 0.5) * len;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(p, 1.0);
	v_along = UV.y;
	// Ширина понад справжню гасне прозорістю (не нижче 0.6: далі лінія зникла б зовсім), а
	// краплі впритул до камери — зникають.
	v_fade = max(sqrt(streak_width / w), 0.6) * smoothstep(1.5, 4.0, dist);
}

void fragment() {
	// Слід розмитий з обох кінців, без яскравої «голови»: голова й хвіст читалися як град.
	float taper = sqrt(sin(3.14159 * v_along));
	ALBEDO = tint.rgb;
	ALPHA = tint.a * taper * v_fade;
}
