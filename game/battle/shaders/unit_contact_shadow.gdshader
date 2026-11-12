// Тінь-контакт під юнітом (`UnitView`): м'яка темна пляма під корпусом, незалежна від сонця. На
// сонячних картах тінь від сонця світла й м'яка, і під юнітом вона ховається; пляма тримає юніта
// на землі. Сила — з вигляду карти (`BattleLook.unit_contact_shadow`); 0 — плями нема.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, world_vertex_coords;

global uniform float unit_contact_shadow;
// Рельєф (`TerrainHeight.texture()`), відлік (i, j) — у світі `height_origin + (i, j) / height_samples`.
uniform bool use_height = false;
uniform sampler2D height_map : filter_linear, repeat_disable;
uniform float height_samples = 4.0;
uniform float height_origin = -0.5;
// Над ґрунтом, щоб не мерехтіти з ним в одній глибині.
const float LIFT = 0.015;
// Частка сили плями на асфальті.
const float ROAD_K = 0.5;

varying float road;

void vertex() {
	road = INSTANCE_CUSTOM.r;
	// Квад рівний, а пагорб під ним — ні: вершина, що пішла б у ґрунт, лягає на нього. Над ґрунтом
	// (настил мосту, нахилений корпус над западиною) лишається площина юніта.
	if (use_height) {
		vec2 hs = vec2(textureSize(height_map, 0));
		vec2 uv = ((VERTEX.xz - height_origin) * height_samples + 0.5) / hs;
		VERTEX.y = max(VERTEX.y, textureLod(height_map, uv, 0.0).r + LIFT);
	}
}

void fragment() {
	// Еліпс по сліду корпусу: найтемніше під серединою, до краю квада гасне до нуля.
	float r = length((UV - 0.5) * 2.0);
	ALBEDO = vec3(0.0);
	ALPHA = clamp(unit_contact_shadow, 0.0, 1.0) * mix(1.0, ROAD_K, road) * (1.0 - smoothstep(0.3, 1.0, r));
}
