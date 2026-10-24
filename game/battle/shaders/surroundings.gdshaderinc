// Світ довкола дошки (`Surroundings`, docs/art/surroundings-research.md): тонка червона лінія на
// краю дошки, а далі — імла: густа низька пелена, що клубами й пасмами закриває край світу, і
// легке затемнення лише під нею. Значення ставить `Surroundings.apply()`, тож типових тут нема;
// лише формули, щоб земля, вода, настили й заслін рахували одне й те саме.
uniform bool surround = false;
// Розмір дошки в клітинках; її межа — краї клітинок -0.5 і `size - 0.5`.
uniform vec2 board_size;
uniform vec3 haze_color;
// Обвідна імли (клітинки від дошки): x — з якої відстані з'являються клуби, y — де вони
// зливаються; з `haze_closed` верх суцільний.
uniform vec2 haze_range;
uniform float haze_closed;
uniform vec2 grade_params;
uniform vec4 line_color;
uniform float line_frac;
uniform float line_gap_px;
// Безшовний fBm 512² (`Surroundings.fog_noise`) на 256 м і межі 5–95 % його значень.
uniform sampler2D fog_noise : filter_linear_mipmap, repeat_enable;
uniform vec2 fog_noise_range;
// Час імли, секунд. Не `TIME`: матеріал з `TIME` змушує Mobile малювати кожен кадр, а
// `fog_time` росте кроком 0.1 с (`BoardView`), тож дошка без руху малює 10 кадрів на секунду.
global uniform float fog_time;

// Евклідова відстань від прямокутника дошки (імла й затемнення): заокруглені кути, без
// діагонального шва; усередині 0.
float board_distance(vec2 p) {
	vec2 q = abs(p - (board_size * 0.5 - 0.5)) - board_size * 0.5;
	return length(max(q, vec2(0.0)));
}

// Відстань Чебишова зі знаком (< 0 усередині): лінія межі з прямими кутами.
float board_cheb(vec2 p) {
	vec2 q = abs(p - (board_size * 0.5 - 0.5)) - board_size * 0.5;
	return max(q.x, q.y);
}

// Затемнення й зменшення насиченості в лінійному світлі, до освітлення (альбедо, власне
// світіння): з нейтральним похмурим світлом це те саме, що й після нього. Іде за непрозорістю
// імли (a), а не за відстанню: земля темніє під клубом і лишається такою, як на дошці, у
// просвіті, тож жоден тон не стає в лінію з краєм дошки.
vec3 surround_grade(vec3 c, float a) {
	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	return mix(vec3(l), c, mix(1.0, grade_params.y, a)) * mix(1.0, grade_params.x, a);
}

// Точка площини y = plane_y на промені з камери крізь pos.
vec2 surround_on_plane(vec3 pos, vec3 cam, float plane_y) {
	vec3 r = pos - cam;
	return cam.xz + r.xz * ((plane_y - cam.y) / min(r.y, -1e-4));
}

// Значення шуму в точці q (метри) з міпа lod, розтягнуте на 0..1 за межами 5–95 %. Міп 3 (4 м на
// тексель) лишає дві крупні октави, 48 і 24 м; міп 0 — усі чотири.
float fog_sample(vec2 q, float lod) {
	float n = textureLod(fog_noise, q / 256.0, lod).r;
	return clamp((n - fog_noise_range.x) / (fog_noise_range.y - fog_noise_range.x), 0.0, 1.0);
}

// Імла в пікселі поверхні pos: rgb — її колір, a — непрозорість. Шум береться там, де промінь
// камери перетинає площину y = 0: імла — один шар над землею, а не фарба на ній, тож земля,
// вода й нижчий заслін, що лежать під тим самим пікселем, бачать той самий візерунок і на стику
// кільця із заслоном шва нема.
// Обвідна (`haze_range`) прив'язана до дошки, усередині неї рухається лише візерунок: шум
// зносить вітром на 0.8 м/с, а клуби (дві крупні октави) ще й повільно зсуває шум, утричі
// крупніший, на ±5 м — справжня пелена радше перетікає, ніж їде. Дрібні октави (12 і 6 м) не
// зсуваються: зсунуті, вони скручуються в тонкі мармурові прожилки. Обрис клуба — лише з крупних
// октав, тож його край м'який (3–7 м), а дрібні лягають на тон. Попереду обвідної — рідкі пасма
// (непрозорість ≤ 0.3), позаду клуби зливаються; з `haze_closed` верх суцільний, і зсув там не
// потрібен. view — напрям погляду камери на землі: різниця крупних октав на 6 м уздовж нього дає
// світлий верх клуба й легку тінь (тінь — не глибша за −0.3: темні прожилки читалися б брудом).
vec4 fog_bank(vec3 pos, vec3 cam, vec2 view) {
	vec2 p = surround_on_plane(pos, cam, 0.0);
	float d = board_distance(p);
	const vec2 WIND = vec2(0.8, 0.6);
	const mat2 ROT = mat2(vec2(0.799, 0.602), vec2(-0.602, 0.799));
	vec2 pm = p * 8.0;
	float closed = smoothstep(haze_closed - 1.5, haze_closed, d);
	vec2 q0 = pm - WIND * 0.8 * fog_time;
	vec2 q = q0;
	if (closed < 1.0) {
		vec2 wq = ROT * (pm / 3.0) + WIND * 0.12 * fog_time;
		vec2 w = vec2(fog_sample(wq, 3.0), fog_sample(wq + vec2(97.0, 41.0), 3.0)) - 0.5;
		q += w * 10.0 * (1.0 - closed);
	}
	float lobe = fog_sample(q, 3.0);
	float fine = fog_sample(q0, 0.0) - fog_sample(q0, 3.0);
	float n = clamp(lobe + fine, 0.0, 1.0);
	float relief = clamp((lobe - fog_sample(q - view * 6.0, 3.0)) / 0.12, -0.3, 1.0);
	float c = smoothstep(haze_range.x, haze_range.y, d);
	float puff = smoothstep(0.7 - c, 1.3 - c, lobe);
	float a = max(puff * (0.12 + 0.88 * c * c), 0.45 * c * c);
	a = max(a, closed) * smoothstep(2.0, 2.5, d);
	vec3 rgb = haze_color * (1.0 + 0.12 * relief + 0.16 * (n - 0.5)) * (0.86 + 0.07 * puff);
	return vec4(rgb, a);
}

// Непрозорість лінії межі в пікселі pos. Відстань береться не на самій поверхні, а там, де
// промінь камери перетинає площину plane_y: на поверхні лінія повторювала б кожен берег і горбок
// зламом. Земля й вода передають 0 — висоту, до якої запікання вирівнює косметичний рельєф
// уздовж краю (`TerrainHeight._EDGE_FLAT`), тож кожна сторона — пряма в 3D, а отже й на екрані,
// і кути сходяться. Ширина — у пікселях кадру з похідних відстані на площині y = 0, тож на
// будь-якому віддаленні вона та сама. Внутрішній край відступає від межі на `line_gap_px`: між
// лінією й контуром зони на крайній клітинці лишається чиста смужка землі.
float surround_line(vec3 pos, vec3 cam, float plane_y, vec2 viewport) {
	float c0 = board_cheb(surround_on_plane(pos, cam, 0.0));
	float scale = max(length(vec2(dFdx(c0), dFdy(c0))), 1e-6);
	float px = board_cheb(surround_on_plane(pos, cam, plane_y)) / scale - line_gap_px;
	float w = clamp(line_frac * viewport.y, 2.0, 4.0);
	return line_color.a * clamp(px * 2.0, 0.0, 1.0) * clamp(w + 0.5 - px, 0.0, 1.0);
}

// FOG змішується з уже освітленим кольором: імла (`fog_bank`) не залежить від світла, а лінія
// не освітлюється й не затемнюється.
vec4 surround_fog(vec4 fog, float line_a) {
	float total = line_a + fog.a * (1.0 - line_a);
	vec3 rgb = (line_color.rgb * line_a + fog.rgb * fog.a * (1.0 - line_a)) / max(total, 1e-4);
	return vec4(rgb, total);
}
