// Дощ (`WeatherRig`): один меш із N квадів; вершина несе випадкову точку в одиничній коробці
// (VERTEX) і свій кут квада (UV). Крапля нерухома у світі (пан дає правильний паралакс), а коробка
// загортається довкола фокуса камери, тож після пана чи зуму кадр одразу повний дощу.
//
// Смуга будується на екрані, в пікселях: розмитий рухом слід завдовжки `streak_px` уздовж
// проєкції падіння й рівна лінія зі згладженим краєм. Коротка смуга, що повзе між пікселями,
// мерехтить блискітками, а не читається дощем.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, shadows_disabled, depth_draw_never;

// Світ: фокус камери на землі, розмір коробки (клітинки), її зсув до камери.
uniform vec3 focus;
uniform vec3 box_size = vec3(40.0, 14.0, 40.0);
uniform vec2 toward_camera = vec2(0.7071, 0.7071);
// Падіння, клітинок/с: 1.0 — 8 м/с. Вітер — уздовж правої осі кадру (камера не обертається),
// тож усі смуги нахилені в один бік, на екрані на ~18–24° від вертикалі.
uniform float fall_speed = 1.0;
uniform vec2 wind = vec2(0.177, -0.177);
// Довжина смуги на екрані для краплі на відстані фокуса, пікселів; ставить `WeatherRig.follow`
// за віддаленням камери. Ближчі краплі довші, дальші коротші.
uniform float streak_px = 30.0;
// Ширина квада, пікселів: лінія ~1 px і по 1.5 px м'якого краю з кожного боку.
uniform float quad_px = 4.0;
// Ледь світліше за мокру землю під похмурим небом; прозорість стала по всій смузі й однакова
// для всіх крапель — інакше вони спалахують по одній.
uniform vec4 tint : source_color = vec4(0.62, 0.65, 0.68, 0.09);

varying float v_x;
varying float v_l;
varying float v_len;
varying float v_fade;

void vertex() {
	vec3 seed = VERTEX;
	vec3 vel = vec3(wind.x, -fall_speed, wind.y);
	// Мінімальний кут коробки: на землі, трохи зсунутий до камери — там у кадрі ближча земля
	// й вища частина шару.
	vec3 lo = vec3(focus.x, 0.0, focus.z) - vec3(box_size.x, 0.0, box_size.z) * 0.5
			+ vec3(toward_camera.x, 0.0, toward_camera.y) * box_size.x * 0.15;
	vec3 c = lo + mod(seed * box_size + vel * TIME - lo, box_size);
	mat4 pv = PROJECTION_MATRIX * VIEW_MATRIX;
	vec4 c0 = pv * vec4(c, 1.0);
	vec4 c1 = pv * vec4(c + normalize(vel) * 0.05, 1.0);
	vec2 half_vp = 0.5 * VIEWPORT_SIZE;
	vec2 s0 = c0.xy / c0.w * half_vp;
	vec2 s1 = c1.xy / c1.w * half_vp;
	vec2 dir = normalize(s1 - s0 + vec2(1e-6));
	vec2 perp = vec2(-dir.y, dir.x);
	float dist = length(CAMERA_POSITION_WORLD - c);
	float ref = length(CAMERA_POSITION_WORLD - focus);
	float len = streak_px * clamp(ref / max(dist, 1e-3), 0.7, 1.6);
	vec2 sp = s0 + dir * (UV.y - 0.5) * len + perp * (UV.x - 0.5) * quad_px;
	POSITION = vec4(sp / half_vp * c0.w, c0.z, c0.w);
	v_x = (UV.x - 0.5) * quad_px;
	v_l = UV.y * len;
	v_len = len;
	// Краплі впритул до камери зникають, а не пролітають через увесь кадр.
	v_fade = smoothstep(1.5, 4.0, dist);
}

void fragment() {
	float across = 1.0 - smoothstep(0.25, 1.75, abs(v_x));
	float ends = smoothstep(0.0, 5.0, v_l) * smoothstep(0.0, 5.0, v_len - v_l);
	ALBEDO = tint.rgb;
	ALPHA = tint.a * across * ends * v_fade;
}
