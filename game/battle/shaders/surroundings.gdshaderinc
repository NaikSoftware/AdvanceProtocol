// Світ довкола дошки (`Surroundings`, docs/art/surroundings-research.md): легке затемнення поза
// дошкою, серпанок далі й тонка червона лінія на її краю. Значення ставить `Surroundings.apply()`,
// тож типових тут нема; лише формули, щоб земля, вода й настили рахували одне й те саме.
uniform bool surround = false;
// Розмір дошки в клітинках; її межа — краї клітинок -0.5 і `size - 0.5`.
uniform vec2 board_size;
uniform vec3 haze_color;
uniform vec2 haze_range;
uniform vec2 grade_params;
uniform vec4 line_color;
uniform float line_frac;
uniform float line_gap_px;

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

// Серпанок: густина 0..1 за відстанню від дошки (клітинки) і його колір. Лише ці дві функції
// знають, який він.
float haze_density(float d) {
	return smoothstep(haze_range.x, haze_range.y, d);
}

vec3 haze_rgb(vec2 p) {
	return haze_color;
}

// Затемнення й зменшення насиченості в лінійному світлі, до освітлення (альбедо, власне
// світіння): з нейтральним похмурим світлом це те саме, що й після нього. Тією самою кривою, що й
// серпанок: біля дошки земля така сама, як на дошці, і жоден тон не стає в лінію з її краєм.
vec3 surround_grade(vec3 c, float d) {
	float g = haze_density(d);
	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	return mix(vec3(l), c, mix(1.0, grade_params.y, g)) * mix(1.0, grade_params.x, g);
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

// FOG змішується з уже освітленим кольором: серпанок не залежить від світла, а лінія не
// освітлюється й не затемнюється.
vec4 surround_fog(vec2 p, float d, float line_a) {
	float h = haze_density(d);
	float total = line_a + h * (1.0 - line_a);
	vec3 rgb = (line_color.rgb * line_a + haze_rgb(p) * h * (1.0 - line_a)) / max(total, 1e-4);
	return vec4(rgb, total);
}
