// Світ довкола дошки (Surroundings, docs/art/surroundings-research.md): легке затемнення поза
// дошкою, серпанок далі й тонка червона лінія на її краю. Числа ставить Surroundings.apply() —
// тут лише формули, щоб земля й вода рахували одне й те саме.
uniform bool surround = false;
// Розмір дошки в клітинках; її межа — краї клітинок -0.5 і size - 0.5.
uniform vec2 board_size = vec2(0.0);
uniform vec3 haze_color = vec3(0.10, 0.135, 0.155);
uniform vec2 haze_range = vec2(3.0, 11.0);
uniform vec3 grade_params = vec3(0.5, 0.8, 0.65);
uniform vec4 line_color = vec4(0.38, 0.015, 0.012, 0.9);
uniform float line_frac = 0.0028;

// x — евклідова відстань від прямокутника дошки (серпанок і затемнення: заокруглені кути, без
// діагонального шва); y — відстань Чебишова зі знаком (лінія: прямі кути, < 0 усередині).
vec2 surround_distance(vec2 p) {
	vec2 q = abs(p - (board_size * 0.5 - 0.5)) - board_size * 0.5;
	return vec2(length(max(q, vec2(0.0))), max(q.x, q.y));
}

// Затемнення й зменшення насиченості в лінійному світлі, до освітлення (альбедо, власне
// світіння): з нейтральним похмурим світлом це те саме, що й після нього.
vec3 surround_grade(vec3 c, float d) {
	float g = smoothstep(0.0, grade_params.x, d);
	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	return mix(vec3(l), c, mix(1.0, grade_params.z, g)) * mix(1.0, grade_params.y, g);
}

// FOG змішується з уже освітленим кольором: серпанок не залежить від світла, а лінія не
// освітлюється й не затемнюється. Ширина лінії — у пікселях кадру (довжина градієнта
// відстані), тож на будь-якому віддаленні вона та сама; внутрішній край — рівно на межі дошки.
vec4 surround_fog(vec2 dist, vec2 viewport) {
	float h = smoothstep(haze_range.x, haze_range.y, dist.x);
	float px = dist.y / max(length(vec2(dFdx(dist.y), dFdy(dist.y))), 1e-6);
	float w = clamp(line_frac * viewport.y, 2.0, 4.0);
	float a = line_color.a * clamp(px * 2.0, 0.0, 1.0) * clamp(w + 0.5 - px, 0.0, 1.0);
	float total = a + h * (1.0 - a);
	vec3 rgb = (line_color.rgb * a + haze_color * h * (1.0 - a)) / max(total, 1e-4);
	return vec4(rgb, total);
}
