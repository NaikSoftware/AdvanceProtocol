// Підлога руїни (PropLayer): битий камінь, цегла й пил замість трави в межах обрису руїни. Шар
// землі під клітинкою RUBBLE лишає між купками траву, і крізь пролом у стіні її було видно.
// Кольори лінійні; візерунок — шум від світових координат, тож сусідні руїни не однакові.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;

// Темні: світлий пил читався пласкою плитою на тлі стін.
const vec3 DUST = vec3(0.055, 0.048, 0.04);
const vec3 BRICK = vec3(0.09, 0.04, 0.026);
const vec3 STONE = vec3(0.07, 0.068, 0.062);
const vec3 SOOT = vec3(0.015, 0.013, 0.012);

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
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Рваний м'який край: без жорсткої межі плити.
	vec2 q = UV - 0.5;
	float edge = max(abs(q.x), abs(q.y)) + 0.06 * (vnoise(world_pos.xz * 9.0) - 0.5);
	float alpha = 1.0 - smoothstep(0.38, 0.5, edge);
	if (alpha <= 0.01) {
		discard;
	}
	vec2 p = world_pos.xz * 8.0; // метри
	float chunks = vnoise(p * 2.2);
	float bricks = vnoise(p * 3.7 + 11.0);
	float soot = vnoise(p * 0.8 + 5.0);
	vec3 c = mix(DUST, STONE, smoothstep(0.45, 0.7, chunks));
	c = mix(c, BRICK, smoothstep(0.62, 0.8, bricks) * 0.8);
	c = mix(c, SOOT, smoothstep(0.55, 0.85, soot) * 0.5);
	ALBEDO = c;
	ROUGHNESS = 0.95;
	ALPHA = alpha;
	NORMAL_MAP = normalize(vec3((chunks - 0.5) * 0.8, (bricks - 0.5) * 0.8, 1.0)) * 0.5 + 0.5;
}
