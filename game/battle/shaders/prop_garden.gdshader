// Городи дворів (PropLayer): зорана темна земля з грядками, лежить на рельєфі. Ряди — від UV (ряд
// ~0.9 м; скільки їх на ділянці, каже INSTANCE_CUSTOM.r), не текстура: два трикутники на ділянку.
// Кольори лінійні (ALBEDO не перетворює sRGB): у sRGB-числах рілля виходила світло-бежевою плиткою.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

// Наскільки ряди зелені: 1 — літо, 0.5 — рання осінь (жовтіють), ~0.15 — пізня (гола рілля).
uniform float green = 0.2;
// Мокрість карти: мокра рілля темніша й блищить.
global uniform float weather_wetness;

const vec3 SOIL_WET = vec3(0.028, 0.019, 0.012);
const vec3 SOIL_DRY = vec3(0.070, 0.048, 0.030);
const vec3 LEAF = vec3(0.030, 0.065, 0.012);
const vec3 LEAF_YELLOW = vec3(0.085, 0.068, 0.014);

varying flat float v_rows;
varying flat float v_seed;

void vertex() {
	v_rows = max(INSTANCE_CUSTOM.r, 4.0);
	v_seed = INSTANCE_CUSTOM.g * 37.0;
}

void fragment() {
	// Рваний край: межа гуляє синусами, ділянка не читається плиткою.
	vec2 q = UV - 0.5;
	float wob = 0.025 * sin(UV.y * 19.0 + v_seed) + 0.02 * sin(UV.x * 27.0 - UV.y * 9.0 + v_seed * 1.7);
	if (max(abs(q.x), abs(q.y)) + wob > 0.47) {
		discard;
	}
	// Гребінь грядки світліший і, якщо сезон, зелений; борозна темна.
	float row = 0.5 + 0.5 * sin(UV.x * v_rows * 6.2832);
	float ridge = smoothstep(0.35, 0.8, row);
	float wet = smoothstep(0.0, 0.5, weather_wetness);
	vec3 soil = mix(SOIL_DRY, SOIL_WET, wet) * (0.55 + 0.75 * ridge);
	vec3 leaf = mix(LEAF_YELLOW, LEAF, clamp(green * 2.0 - 1.0, 0.0, 1.0));
	ALBEDO = mix(soil, leaf, ridge * smoothstep(0.05, 0.4, green) * 0.85);
	ROUGHNESS = mix(0.95, 0.6, wet);
	// Гребені трохи рельєфні: світло лягає смугами.
	NORMAL_MAP = normalize(vec3(cos(UV.x * v_rows * 6.2832) * 0.35, 0.0, 1.0)) * 0.5 + 0.5;
}
