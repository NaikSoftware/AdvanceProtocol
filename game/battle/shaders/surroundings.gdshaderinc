// Світ довкола дошки (`Surroundings`, docs/art/surroundings-research.md): тонка червона лінія на
// краю дошки, а далі — серпанок: густа низька пелена, що лобами й пасмами закриває край світу, і
// легке затемнення лише під ним. Значення ставить `Surroundings.apply()`, тож типових тут нема;
// лише формули, щоб земля, вода, настили й заслін рахували одне й те саме.
uniform bool surround = false;
// Розмір дошки в клітинках; її межа — краї клітинок -0.5 і `size - 0.5`.
uniform vec2 board_size;
uniform vec3 haze_color;
// Обвідна серпанку (клітинки від дошки): x — з якої відстані з'являються лоби, y — де вони
// зливаються; з `haze_closed` верх суцільний.
uniform vec2 haze_range;
uniform float haze_closed;
uniform vec2 grade_params;
uniform vec4 line_color;
uniform float line_frac;
uniform float line_gap_px;
// Безшовний fBm 512² (`Surroundings.fog_noise`) на 256 м і межі 5–95 % його значень.
uniform sampler2D fog_noise : filter_linear, repeat_enable;
uniform vec2 fog_noise_range;
// Час серпанку, секунд. Не `TIME`: матеріал з `TIME` змушує Mobile малювати кожен кадр, а
// `fog_time` росте кроком 0.1 с (`BoardView`), тож дошка без руху малює 10 кадрів на секунду.
global uniform float fog_time;

// Евклідова відстань від прямокутника дошки (серпанок і затемнення): заокруглені кути, без
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
// серпанку (a), а не за відстанню: земля темніє під лобом і лишається такою, як на дошці, у
// просвіті, тож жоден тон не стає в лінію з краєм дошки.
vec3 surround_grade(vec3 c, float a) {
	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	return mix(vec3(l), c, mix(1.0, grade_params.y, a)) * mix(1.0, grade_params.x, a);
}

// Площину лінії межі задають 9 точок уздовж найближчого краю дошки, через 0.5 клітинки
// (`edge_plane_y` у землі й воді), з вагою-трикутником: висота площини міняється плавно, коли
// крайні точки переходять берег, і лінія не гнеться над водою.
const int SURROUND_TAPS = 9;

float surround_tap_weight(int i) {
	return (5.0 - abs(float(i - 4))) / 25.0;
}

vec2 surround_edge_tap(vec2 p, int i) {
	vec2 lo = vec2(-0.5);
	vec2 hi = board_size - 0.5;
	vec2 e = clamp(p, lo, hi);
	float t = 0.5 * float(i - 4);
	float dx = min(abs(p.x - lo.x), abs(p.x - hi.x));
	float dz = min(abs(p.y - lo.y), abs(p.y - hi.y));
	if (dx < dz) {
		return vec2(abs(p.x - lo.x) < abs(p.x - hi.x) ? lo.x : hi.x, e.y + t);
	}
	return vec2(e.x + t, abs(p.y - lo.y) < abs(p.y - hi.y) ? lo.y : hi.y);
}

// Точка площини y = plane_y на промені з камери крізь pos.
vec2 surround_on_plane(vec3 pos, vec3 cam, float plane_y) {
	vec3 r = pos - cam;
	return cam.xz + r.xz * ((plane_y - cam.y) / min(r.y, -1e-4));
}

// Значення шуму в точці q (метри), розтягнуте на 0..1 за межами 5–95 %.
float fog_sample(vec2 q) {
	float n = textureLod(fog_noise, q / 256.0, 0.0).r;
	return clamp((n - fog_noise_range.x) / (fog_noise_range.y - fog_noise_range.x), 0.0, 1.0);
}

// Серпанок у пікселі поверхні pos: rgb — його колір, a — непрозорість. Шум береться там, де промінь
// камери перетинає площину y = 0: серпанок — один шар над землею, а не фарба на ній, тож земля,
// вода й нижчий заслін, що лежать під тим самим пікселем, бачать той самий візерунок і на стику
// кільця із заслоном шва нема.
// Обвідна (`haze_range`) прив'язана до дошки, усередині неї рухається лише візерунок: шум
// зносить вітром на 0.8 м/с, а зсув координат (теж шум, утричі крупніший) пливе повільніше й
// міняє форму лобів — справжня пелена радше перетікає, ніж їде. Попереду обвідної — рідкі лоби
// й пасма, позаду вони зливаються; з `haze_closed` верх суцільний, і зсув там уже не потрібен,
// тож заслін за кільцем бере лише два відліки шуму й стикується з кільцем без шва. view — напрям
// погляду камери на землі: різниця шуму на 6 м уздовж нього дає світлий верх і тінь лоба.
vec4 fog_bank(vec3 pos, vec3 cam, vec2 view) {
	vec2 p = surround_on_plane(pos, cam, 0.0);
	float d = board_distance(p);
	const vec2 WIND = vec2(0.8, 0.6);
	const mat2 ROT = mat2(vec2(0.799, 0.602), vec2(-0.602, 0.799));
	vec2 pm = p * 8.0;
	float closed = smoothstep(haze_closed - 1.5, haze_closed, d);
	vec2 q = pm - WIND * 0.8 * fog_time;
	if (closed < 1.0) {
		vec2 wq = ROT * (pm / 3.0) + WIND * 0.12 * fog_time;
		vec2 w = vec2(fog_sample(wq), fog_sample(wq + vec2(97.0, 41.0))) - 0.5;
		q += w * 24.0 * (1.0 - closed);
	}
	float n = fog_sample(q);
	float relief = clamp((n - fog_sample(q - view * 6.0)) / 0.25, -1.0, 1.0);
	float c = smoothstep(haze_range.x, haze_range.y, d);
	float puff = smoothstep(0.75 - c, 1.25 - c, n);
	float a = max(puff * (0.25 + 0.75 * c), 0.45 * c * c);
	a = max(a, closed) * smoothstep(2.0, 2.5, d);
	vec3 rgb = haze_color * (1.0 + 0.10 * relief + 0.08 * (n - 0.5)) * (0.94 + 0.08 * puff);
	return vec4(rgb, a);
}

// Непрозорість лінії межі в пікселі pos. Відстань береться не на самій поверхні, а там, де
// промінь камери перетинає площину plane_y (висота землі на краю, згладжена вздовж нього): лінія
// на поверхні повторювала б кожен берег і горбок зламом, а її копія на дні проступала б крізь воду
// нижче за копію на воді. Земля й вода беруть ту саму площину, тож обидві копії збігаються.
// Ширина — у пікселях кадру з похідних тієї ж відстані на площині y = 0 (гладкої, без граней
// рельєфу), тож на будь-якому віддаленні вона та сама. Внутрішній край відступає від межі на
// `line_gap_px`: між лінією й контуром зони на крайній клітинці лишається чиста смужка землі.
float surround_line(vec3 pos, vec3 cam, float plane_y, vec2 viewport) {
	float c0 = board_cheb(surround_on_plane(pos, cam, 0.0));
	float scale = max(length(vec2(dFdx(c0), dFdy(c0))), 1e-6);
	float px = board_cheb(surround_on_plane(pos, cam, plane_y)) / scale - line_gap_px;
	float w = clamp(line_frac * viewport.y, 2.0, 4.0);
	return line_color.a * clamp(px * 2.0, 0.0, 1.0) * clamp(w + 0.5 - px, 0.0, 1.0);
}

// FOG змішується з уже освітленим кольором: серпанок (`fog_bank`) не залежить від світла, а лінія
// не освітлюється й не затемнюється.
vec4 surround_fog(vec4 fog, float line_a) {
	float total = line_a + fog.a * (1.0 - line_a);
	vec3 rgb = (line_color.rgb * line_a + fog.rgb * fog.a * (1.0 - line_a)) / max(total, 1e-4);
	return vec4(rgb, total);
}
