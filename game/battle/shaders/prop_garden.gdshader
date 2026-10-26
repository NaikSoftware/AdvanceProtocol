// Городні грядки двору (PropLayer): темні борозни землі з рядами посадок, лежать на рельєфі.
// Ряди — від UV, не від текстури: два трикутники на клітинку, ряд ~0.8 м (клітинка — 8 м).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

// Наскільки ряди зелені: 1 — літо, 0.5 — рання осінь (жовтіють), ~0.15 — пізня (гола рілля).
uniform float green = 0.2;
// Мокрість карти: мокра рілля темніша й блищить.
global uniform float weather_wetness;

const vec3 SOIL = vec3(0.17, 0.12, 0.085);
const vec3 SOIL_DRY = vec3(0.26, 0.2, 0.14);
const vec3 LEAF = vec3(0.16, 0.24, 0.07);
const vec3 LEAF_YELLOW = vec3(0.3, 0.26, 0.09);
const float ROWS = 8.0;

void fragment() {
	// М'який край грядки: город не обрізаний квадратом, а сходить у траву.
	vec2 e = min(UV, 1.0 - UV);
	float edge = smoothstep(0.0, 0.08, min(e.x, e.y));
	float row = 0.5 + 0.5 * sin(UV.x * ROWS * 6.2832);
	float ridge = smoothstep(0.35, 0.75, row);
	float wet = smoothstep(0.0, 0.5, weather_wetness);
	vec3 soil = mix(SOIL_DRY, SOIL, max(wet, 0.4)) * (0.8 + 0.25 * (1.0 - ridge));
	vec3 leaf = mix(LEAF_YELLOW, LEAF, clamp(green * 2.0 - 1.0, 0.0, 1.0));
	vec3 c = mix(soil, leaf, ridge * smoothstep(0.05, 0.4, green));
	ALBEDO = c;
	ROUGHNESS = mix(0.95, 0.55, wet);
	ALPHA = edge;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
