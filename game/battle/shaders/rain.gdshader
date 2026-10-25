// Дощ (`WeatherRig`): один меш із N квадів; вершина несе випадкову точку одиничної коробки
// (VERTEX) і кут свого квада (UV). Кожна крапля живе циклами: на початку циклу з'являється в
// новому випадковому місці коробки довкола фокуса камери, падає й видима лише `life` секунд — око
// бачить швидкий штрих, а не предмет, що повільно летить через кадр.
//
// Довжина штриха — розмиття руху за витримку: швидкість × `exposure`, у світі, як і саме падіння.
// Довжина й швидкість на екрані проєктуються однаково, тож штрих на будь-якому зумі пролітає
// свою довжину за ту саму частку секунди. Довжина в пікселях при швидкості у світі дає «палиці»,
// що прискорюються з наближенням.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, shadows_disabled, depth_draw_never;

// Світ: фокус камери на землі, розмір коробки (клітинки), її зсув до камери.
uniform vec3 focus;
uniform vec3 box_size = vec3(40.0, 14.0, 40.0);
uniform vec2 toward_camera = vec2(0.7071, 0.7071);
// Падіння й вітер, клітинок/с; цикл і видиме життя краплі, витримка — секунд. Значення ставить
// `WeatherRig` зі своїх сталих.
uniform float fall_speed = 3.5;
uniform vec2 wind = vec2(0.62, -0.62);
uniform float exposure = 0.045;
uniform float cycle = 1.0;
uniform float life = 0.2;
// Ширина квада, пікселів: лінія тонша за піксель, що гасне прозорістю, і м'який край.
uniform float quad_px = 3.0;
// Ледь світліше за мокру землю під похмурим небом.
uniform vec4 tint : source_color = vec4(0.66, 0.69, 0.72, 0.12);

varying float v_x;
varying float v_l;
varying float v_vis;

float rain_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	vec3 seed = VERTEX;
	// Свій зсув фази в кожної краплі, тож вони спалахують не разом.
	float ph = TIME / cycle + rain_hash(seed.xy * 97.0 + seed.z * 13.0);
	float k = floor(ph);
	float age = fract(ph) * cycle;
	vec3 r = vec3(rain_hash(seed.xy * 131.0 + k), rain_hash(seed.yz * 173.0 + k * 1.7),
			rain_hash(seed.zx * 151.0 + k * 2.3));
	vec3 lo = vec3(focus.x, 0.0, focus.z) - vec3(box_size.x, 0.0, box_size.z) * 0.5
			+ vec3(toward_camera.x, 0.0, toward_camera.y) * box_size.x * 0.15;
	vec3 vel = vec3(wind.x, -fall_speed, wind.y);
	vec3 head = lo + r * box_size + vel * age;
	vec3 tail = head - vel * exposure;
	mat4 pv = PROJECTION_MATRIX * VIEW_MATRIX;
	vec4 h = pv * vec4(head, 1.0);
	vec4 t = pv * vec4(tail, 1.0);
	vec2 half_vp = 0.5 * VIEWPORT_SIZE;
	vec2 sh = h.xy / h.w * half_vp;
	vec2 st = t.xy / t.w * half_vp;
	vec2 along = sh - st;
	vec2 dir = along / max(length(along), 1e-4);
	vec2 perp = vec2(-dir.y, dir.x);
	// UV.y 0 — хвіст, 1 — голова; збоку квад на `quad_px`.
	vec2 sp = mix(st, sh, UV.y) + perp * (UV.x - 0.5) * quad_px;
	float w = mix(t.w, h.w, UV.y);
	POSITION = vec4(sp / half_vp * w, mix(t.z, h.z, UV.y), w);
	v_x = (UV.x - 0.5) * quad_px;
	v_l = UV.y;
	float dist = length(CAMERA_POSITION_WORLD - head);
	v_vis = (age < life ? sin(3.14159 * age / life) : 0.0) * smoothstep(1.5, 4.0, dist);
	if (v_vis <= 0.0) {
		// Невидима зараз крапля: квад стягується в точку поза кадром і нічого не малює.
		POSITION = vec4(2.0, 2.0, 2.0, 1.0);
	}
}

void fragment() {
	// Покриття лінії тоншої за піксель: ядро ~1 px, далі м'який спад.
	float across = 1.0 - smoothstep(0.0, 1.25, abs(v_x));
	// Обидва кінці гаснуть, суцільного тіла й голови нема.
	float along = sin(3.14159 * v_l);
	ALBEDO = tint.rgb;
	ALPHA = tint.a * across * along * v_vis;
}
