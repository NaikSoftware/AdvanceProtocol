// Стежка двору (PropLayer): втоптана земля від воріт до дверей хати, ~1 м завширшки. М'які краї в
// траву й на кінцях, щоб смуга не читалась накладеною стрічкою. Кольори лінійні.
// Квад: UV.x — уздовж стежки, UV.y — поперек.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;

global uniform float weather_wetness;

const vec3 DIRT_DRY = vec3(0.075, 0.06, 0.045);
const vec3 DIRT_WET = vec3(0.04, 0.03, 0.022);

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
	float n = vnoise(world_pos.xz * 24.0);
	float across = abs(UV.y - 0.5) * 2.0 + 0.35 * (n - 0.5);
	float along = abs(UV.x - 0.5) * 2.0;
	float alpha = (1.0 - smoothstep(0.45, 1.0, across)) * (1.0 - smoothstep(0.8, 1.0, along)) * 0.85;
	if (alpha <= 0.01) {
		discard;
	}
	float wet = smoothstep(0.0, 0.5, weather_wetness);
	ALBEDO = mix(DIRT_DRY, DIRT_WET, wet) * (0.85 + 0.3 * vnoise(world_pos.xz * 60.0));
	ROUGHNESS = mix(0.95, 0.7, wet);
	ALPHA = alpha;
}
