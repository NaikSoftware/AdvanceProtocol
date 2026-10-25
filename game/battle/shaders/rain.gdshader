// Дощ (`WeatherRig`): один меш із квадів, що стоять сіткою `grid`; вершина несе центр своєї
// клітинки сітки в одиничній коробці (VERTEX) і кут квада (UV).
//
// Краплі прив'язані до світу. Світ поділено на клітинки `cell`; у кожної своя крапля, і де вона
// з'являється в кожному циклі, вирішує лише світовий номер клітинки й номер циклу. Сітка квадів
// стоїть над клітинками довкола камери: `cell_origin` — світовий номер кутової клітинки, `stride`
// — крок (1, 2 чи 4 клітинки) на віддаленні камери. Пан зсуває сітку на цілі клітинки, тож та
// сама крапля лишається на тому самому місці світу й дає правильний паралакс; зум бере кожну
// другу чи четверту клітинку тієї самої решітки, тож видимі краплі не зсуваються.
//
// Кожна крапля видима лише `life` секунд циклу: око бачить швидкий штрих, а не предмет. Довжина
// штриха — розмиття руху за витримку: швидкість × `exposure`, у світі, як і падіння, тож на
// будь-якому зумі штрих пролітає свою довжину за ту саму частку секунди. Довжина в пікселях при
// швидкості у світі дає «палиці», що прискорюються з наближенням.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, shadows_disabled, depth_draw_never;

// Решітка: розмір клітинки (клітинки дошки), кількість квадів по осях, номер кутової клітинки й
// крок; ставить `WeatherRig.follow`.
uniform vec3 cell = vec3(0.56, 0.64, 0.56);
uniform vec3 grid = vec3(28.0, 8.0, 28.0);
uniform vec3 cell_origin;
uniform float stride = 1.0;
// Падіння й вітер, клітинок/с; цикл і видиме життя краплі, витримка — секунд. Значення ставить
// `WeatherRig` зі своїх сталих.
uniform float fall_speed = 3.5;
uniform vec2 wind = vec2(0.62, -0.62);
uniform float exposure = 0.045;
uniform float cycle = 0.6;
uniform float life = 0.2;
// Ширина квада впоперек штриха, пікселів: м'яка лінія завширшки ~1 px, що гасне до країв.
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
	vec3 gi = floor(VERTEX * grid);
	// Світовий номер клітинки цієї краплі: від нього залежить усе, що крапля робить.
	vec3 wc = cell_origin + gi * stride;
	float ph = TIME / cycle + rain_hash(wc.xz * 0.731 + wc.y * 17.13);
	float k = floor(ph);
	float age = fract(ph) * cycle;
	vec3 r = vec3(rain_hash(wc.xz * 1.31 + wc.y * 7.7 + k),
			rain_hash(wc.zx * 1.73 + wc.y * 3.1 + k * 1.7),
			rain_hash(wc.xy * 1.51 + wc.z * 5.3 + k * 2.3));
	vec3 vel = vec3(wind.x, -fall_speed, wind.y);
	vec3 head = (wc + r) * cell + vel * age;
	vec3 tail = head - vel * exposure;
	mat4 pv = PROJECTION_MATRIX * VIEW_MATRIX;
	vec4 h = pv * vec4(head, 1.0);
	vec4 t = pv * vec4(tail, 1.0);
	v_x = 0.0;
	v_l = 0.0;
	v_vis = 0.0;
	// Крапля на площині камери чи позаду неї (коробка сягає камери на найбільшому віддаленні) —
	// ділення на w там вибухає, тож її не малюємо.
	if (h.w < 0.05 || t.w < 0.05) {
		POSITION = vec4(2.0, 2.0, 2.0, 1.0);
	} else {
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
}

void fragment() {
	// М'яка лінія: найщільніша по осі й гасне за ~1.25 px від неї.
	float across = 1.0 - smoothstep(0.0, 1.25, abs(v_x));
	// Обидва кінці гаснуть, суцільного тіла й голови нема.
	float along = sin(3.14159 * v_l);
	ALBEDO = tint.rgb;
	ALPHA = tint.a * across * along * v_vis;
}
