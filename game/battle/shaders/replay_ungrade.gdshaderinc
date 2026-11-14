// Обернений грейд повтору («запис із дрона», ReplayOverlay). Грейд — коригування Environment, тож лягає
// на весь 3D-кадр, і смуга HP пригасла б разом із ним, а сторону юніта показує саме вона. Godot робить
// коригування після тонмапу в sRGB: яскравість, контраст, насиченість (середнє каналів), потім
// 1D-рампа кожного каналу окремо; рампа тут — пряма lo..hi. Неосвітлена смуга заздалегідь проходить
// усе це навпаки й після грейду виходить у своєму кольорі. Без повтору глобалі — тотожність.
global uniform vec3 replay_grade_bcs;
global uniform vec3 replay_grade_lo;
global uniform vec3 replay_grade_hi;

vec3 replay_ungrade(vec3 linear_rgb) {
	vec3 c = mix(12.92 * linear_rgb, 1.055 * pow(linear_rgb, vec3(1.0 / 2.4)) - 0.055,
			step(vec3(0.0031308), linear_rgb));
	c = (c - replay_grade_lo) / (replay_grade_hi - replay_grade_lo);
	c = mix(vec3(dot(c, vec3(1.0 / 3.0))), c, 1.0 / replay_grade_bcs.z);
	c = mix(vec3(0.5), c, 1.0 / replay_grade_bcs.y);
	c = clamp(c / replay_grade_bcs.x, 0.0, 1.0);
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}
