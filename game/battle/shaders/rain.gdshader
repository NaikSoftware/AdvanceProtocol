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
// Смуга: довжина в клітинках (0.5 м розмиття руху), але на екрані не коротша за 7 px — камера
// дивиться згори, і смуга 0.5 м на найбільшому віддаленні стискається в крапку 2–3 px.
// Ширина — не тонша за 1 px.
uniform float streak_length = 0.0625;
uniform float min_streak_px = 7.0;
uniform float streak_width = 0.005;
uniform vec4 tint : source_color = vec4(0.75, 0.79, 0.84, 0.45);

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
	// Розмір пікселя на цій відстані: смуга вужча за піксель мерехтіла б.
	float px = 2.0 * dist / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	float w = max(streak_width, 1.1 * px);
	float len = max(streak_length, min_streak_px * px / seen);
	vec3 p = c + side * (UV.x - 0.5) * w + axis * (UV.y - 0.5) * len;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(p, 1.0);
	v_along = UV.y;
	// Ширина понад справжню гасне прозорістю, а краплі впритул до камери — зникають.
	v_fade = max(sqrt(streak_width / w), 0.75) * smoothstep(1.5, 4.0, dist);
}

void fragment() {
	// Голова краплі (низ смуги) яскравіша за слід.
	ALBEDO = tint.rgb;
	ALPHA = tint.a * v_along * v_fade;
}
