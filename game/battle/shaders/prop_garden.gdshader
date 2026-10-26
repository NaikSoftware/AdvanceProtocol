// Город садиби (PropLayer): частина ґрунту двору за хатою — темна оброблена земля, рядки ледь
// помітні (крок ~0.7 м, контраст у межах ~4 одиниць L*, бо інакше рябить), м'який рваний край у
// траву. На частині городу ростуть кущі (картопля, капуста), решта — голий ґрунт. Кольори лінійні.
// INSTANCE_CUSTOM: r — кількість рядків уздовж ділянки, g — зерно краю, b — частка зеленого.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;

// Сезон: 1 — літо (зелена ботва), 0.5 — рання осінь (жовтіє), ~0.15 — пізня (майже голий ґрунт).
uniform float green = 0.2;
global uniform float weather_wetness;

const vec3 SOIL_DRY = vec3(0.052, 0.038, 0.026);
// Мокра — темніша й тепліша: під сірим небом нейтральна рілля читалась сірою плитою.
const vec3 SOIL_WET = vec3(0.034, 0.020, 0.010);
const vec3 LEAF = vec3(0.040, 0.070, 0.020);
const vec3 LEAF_YELLOW = vec3(0.080, 0.066, 0.022);

varying flat vec3 v_custom;
varying vec3 world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void vertex() {
	v_custom = INSTANCE_CUSTOM.rgb;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 q = UV - 0.5;
	// Межа з травою: шум по світу, тож край нерівний і м'який (обмежка з трави).
	float wob = 0.08 * (vnoise(world_pos.xz * 6.0 + v_custom.g * 13.0) - 0.5);
	float d = max(abs(q.x), abs(q.y)) + wob;
	float edge = 1.0 - smoothstep(0.36, 0.47, d);
	if (edge <= 0.01) {
		discard;
	}
	float rows = max(v_custom.r, 4.0);
	float row = 0.5 + 0.5 * sin(UV.x * rows * 6.2832);
	float wet = smoothstep(0.0, 0.5, weather_wetness);
	// Рядки — ±3 % яскравості: видно зблизька, не рябить здалеку.
	vec3 soil = mix(SOIL_DRY, SOIL_WET, wet) * (0.97 + 0.06 * row) * (0.9 + 0.2 * vnoise(world_pos.xz * 20.0));
	// Зелена частина — з одного кінця ділянки; на ній кущі по гребенях, між ними земля.
	float green_part = step(UV.y, v_custom.b);
	float bush = smoothstep(0.45, 0.75, vnoise(vec2(UV.x * rows * 2.0, UV.y * 9.0) + v_custom.g * 7.0)) * smoothstep(0.3, 0.8, row);
	vec3 leaf = mix(LEAF_YELLOW, LEAF, clamp(green * 2.0 - 1.0, 0.0, 1.0));
	float leaf_k = green_part * bush * smoothstep(0.05, 0.4, green);
	ALBEDO = mix(soil, leaf, leaf_k);
	// Мокра рілля — матова: блиск неба робив її сірою плитою.
	ROUGHNESS = mix(0.95, 0.85, wet);
	ALPHA = edge;
}
