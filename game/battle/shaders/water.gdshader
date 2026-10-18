// Річка (Phase 5a, Task 6). Темна вода під дощем; відбиття — не екранний прохід
// (без SSR, §8), а звичайний шлях освітлення Godot: низька шорсткість, і френель
// сам підмішує радіанс зонда BoardView. Зонд не бачить шару юнітів, тож у воді
// не буває прихованого ворога.
shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_never;

global uniform float weather_wetness;

uniform sampler2D kind_map : filter_nearest, repeat_disable;
// Клітинка, що відповідає пікселю (0, 0) kind_map (від'ємна при відступі).
uniform vec2 map_origin = vec2(0.0);
uniform int water_kind = 5;
uniform int broken_bridge_kind = 9;
// Спільна карта нормалей, яку семплюємо двічі в різних масштабах і напрямках.
uniform sampler2D wave_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 deep_color : source_color = vec3(0.025, 0.032, 0.034);
uniform vec3 shallow_color : source_color = vec3(0.07, 0.065, 0.05);

varying vec3 world_pos;

#include "res://game/battle/shaders/terrain_noise.gdshaderinc"

float water_at(ivec2 px, ivec2 size) {
	int kind = int(texelFetch(kind_map, clamp(px, ivec2(0), size - 1), 0).r * 255.0 + 0.5);
	return (kind == water_kind || kind == broken_bridge_kind) ? 1.0 : 0.0;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	// Та сама рвана межа, що й у землі: вода стоїть усередині берегової смуги.
	vec2 g = border_warp(p) - map_origin;
	vec2 fw = border_weights(fract(g));
	ivec2 b = ivec2(floor(g));
	ivec2 size = textureSize(kind_map, 0);
	float w = mix(mix(water_at(b, size), water_at(b + ivec2(1, 0), size), fw.x),
			mix(water_at(b + ivec2(0, 1), size), water_at(b + ivec2(1, 1), size), fw.x), fw.y);
	if (w < 0.5) {
		discard;
	}
	// 0 на лінії урізу, 1 — за чверть смуги від неї.
	float depth = smoothstep(0.5, 0.85, w);

	// Масштаб: клітинка = 8 м; карта шуму має ~5 плям на повтор.
	// Течія й повільна хвиля: повтор 5 клітинок, пляма ~1 клітинка (8 м), 0.5 м/с.
	vec2 n1 = texture(wave_normal, p * 0.2 + TIME * vec2(0.012, 0.004)).rg * 2.0 - 1.0;
	// Дрібна брижа від вітру й дощу: повтор 0.3 клітинки, пляма ~0.06 (0.5 м), 0.3 м/с.
	vec2 n2 = texture(wave_normal, p * 3.3 + TIME * vec2(-0.05, 0.12)).rg * 2.0 - 1.0;
	float wet = clamp(weather_wetness, 0.0, 1.0);
	float rv = ripple_visibility(p);
	vec2 nxy = n1 * 0.45 + n2 * (0.25 + 0.2 * wet) + rain_ripples(p, TIME) * 2.0 * wet * rv;

	ALBEDO = mix(shallow_color, deep_color, depth);
	// Здалеку дощ на воді — дрібне мерехтіння, не кола: шорсткість замість рябі.
	ROUGHNESS = 0.04 + 0.12 * wet * (1.0 - rv);
	// F0 0.08 замість водяних 0.02: зверху під 40–55° справжня вода майже не
	// відбиває, а ціль (river_target.jpg) читається саме відбитим небом.
	SPECULAR = 1.0;
	NORMAL_MAP = vec3(nxy * 0.5 + 0.5, 1.0);
	// М'який уріз: біля берега крізь мілину проступає текстура берега.
	ALPHA = mix(0.55, 0.96, depth);
}
