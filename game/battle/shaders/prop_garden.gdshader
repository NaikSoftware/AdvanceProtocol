// Городні грядки двору (PropLayer): темні борозни землі з рядами посадок, лежать на рельєфі.
// Ряди — від UV, не від текстури: два трикутники на клітинку, ряд ~0.6 м (клітинка — 8 м). Кольори
// лінійні (ALBEDO не перетворює sRGB): у sRGB-числах рілля виходила світло-бежевою плиткою.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

// Наскільки ряди зелені: 1 — літо, 0.5 — рання осінь (жовтіють), ~0.15 — пізня (гола рілля).
uniform float green = 0.2;
// Мокрість карти: мокра рілля темніша й блищить.
global uniform float weather_wetness;

const vec3 SOIL_WET = vec3(0.030, 0.020, 0.013);
const vec3 SOIL_DRY = vec3(0.075, 0.052, 0.033);
const vec3 LEAF = vec3(0.028, 0.060, 0.012);
const vec3 LEAF_YELLOW = vec3(0.085, 0.068, 0.014);
const float ROWS = 10.0;

void fragment() {
	// Рваний край городу: межа гуляє синусами, тож ділянка не читається квадратною плиткою.
	vec2 q = UV - 0.5;
	float wob = 0.03 * sin(UV.y * 23.0 + UV.x * 7.0) + 0.025 * sin(UV.x * 31.0 - UV.y * 11.0);
	float box = max(abs(q.x), abs(q.y)) + wob;
	if (box > 0.47) {
		discard;
	}
	float row = 0.5 + 0.5 * sin(UV.x * ROWS * 6.2832);
	float ridge = smoothstep(0.4, 0.8, row);
	float wet = smoothstep(0.0, 0.5, weather_wetness);
	vec3 soil = mix(SOIL_DRY, SOIL_WET, wet) * (0.7 + 0.45 * ridge);
	vec3 leaf = mix(LEAF_YELLOW, LEAF, clamp(green * 2.0 - 1.0, 0.0, 1.0));
	ALBEDO = mix(soil, leaf, ridge * smoothstep(0.05, 0.4, green));
	ROUGHNESS = mix(0.95, 0.6, wet);
}
