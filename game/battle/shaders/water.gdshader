// Річка (Phase 5a, Task 6). Темна вода під дощем; відбиття — не екранний прохід
// (без SSR, §8): радіанс зонда BoardView приходить звичайним шляхом освітлення
// (низька шорсткість), а поки сцена без неба, власне похмуре небо додає
// overcast_reflection під глобальним sky_fallback. Зонд не бачить шару юнітів,
// тож у воді не буває прихованого ворога.
shader_type spatial;
// specular_disabled: під похмурим небом сонячного відблиску немає, а на дрібній
// брижі він запалював однопіксельні іскри. Відбиття (зонд і запасне небо) лишаються.
render_mode blend_mix, cull_back, depth_draw_never, specular_disabled;

global uniform float weather_wetness;
// 1 — запасне небо у відбитті; погода (Task 10) гасить його, коли дасть справжнє.
global uniform float sky_fallback;

uniform sampler2D kind_map : filter_nearest, repeat_disable;
// Клітинка, що відповідає пікселю (0, 0) kind_map (від'ємна при відступі).
uniform vec2 map_origin = vec2(0.0);
uniform int water_kind = 5;
uniform int broken_bridge_kind = 9;
// Річка тече й під цілим мостом; настил над нею — окремий меш.
uniform int bridge_kind = 8;
// Вісь течії (одна на карту, WaterSurface.build).
uniform vec2 flow_dir = vec2(1.0, 0.0);
// Спільна карта нормалей, яку семплюємо двічі в різних масштабах і напрямках.
uniform sampler2D wave_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 deep_color : source_color = vec3(0.05, 0.056, 0.058);
uniform vec3 shallow_color : source_color = vec3(0.09, 0.08, 0.06);
// Френель сильніший за водяний (F0 0.02, степінь 5): зверху під 40–55° справжня
// вода майже не відбиває, а ціль читається саме відбитим небом удалині.
uniform float fresnel_f0 = 0.03;
uniform float fresnel_power = 3.0;
uniform float reflection_gain = 1.6;

varying vec3 world_pos;

#include "res://game/battle/shaders/terrain_noise.gdshaderinc"

float water_at(ivec2 px, ivec2 size) {
	int kind = int(texelFetch(kind_map, clamp(px, ivec2(0), size - 1), 0).r * 255.0 + 0.5);
	return (kind == water_kind || kind == bridge_kind || kind == broken_bridge_kind) ? 1.0 : 0.0;
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
	// Біля урізу вага росте ~3.4 на клітинку: 0.5 -> 0.72 — це зовнішні ~0.5 м
	// мілини, де вода тоншає до нуля; глибина темніє до ~1 м від берега.
	float shallow_fade = smoothstep(0.5, 0.72, w);
	float depth = smoothstep(0.55, 0.85, w);

	// Масштаб: клітинка = 8 м; карта шуму має ~5 плям на повтор.
	// Кадр течії: a — уздовж, c — упоперек річки.
	vec2 fdir = normalize(flow_dir);
	vec2 fperp = vec2(-fdir.y, fdir.x);
	vec2 fp = vec2(dot(p, fdir), dot(p, fperp));
	// Смуги течії: повтор 6.7 клітинки уздовж і 1.25 упоперек — плями ~11 x 2 м
	// витягнуті за течією; 0.5 м/с.
	vec2 s1 = texture(wave_normal, fp * vec2(0.15, 0.8) + vec2(TIME * 0.009, 0.0)).rg * 2.0 - 1.0;
	// Дрібна брижа: повтор 0.3 клітинки, пляма ~0.06 (0.5 м), зносить течією 0.3 м/с.
	vec2 s2 = texture(wave_normal, fp * 3.3 + vec2(TIME * 0.13, TIME * 0.02)).rg * 2.0 - 1.0;
	// Назад із кадру течії у світовий xz.
	vec2 n1 = fdir * s1.x + fperp * s1.y;
	vec2 n2 = fdir * s2.x + fperp * s2.y;
	float wet = clamp(weather_wetness, 0.0, 1.0);
	float rv = ripple_visibility(p);
	vec2 slope = n1 * 0.45 + n2 * (0.25 + 0.2 * wet) + rain_ripples(p, TIME) * 1.2 * wet * rv;

	vec3 v = normalize(CAMERA_POSITION_WORLD - world_pos);
	vec3 refl = overcast_reflection(slope_to_world(slope), v, fresnel_f0, fresnel_power);

	ALBEDO = mix(shallow_color, deep_color, depth);
	// Підлога 0.1, а не 0.04: так радіанс зонда не дрібниться на іскри.
	// Здалеку дощ — дрібне мерехтіння: шорсткість замість рябі.
	ROUGHNESS = 0.1 + 0.1 * wet * (1.0 - rv);
	SPECULAR = 0.5;
	NORMAL_MAP = slope_to_normal_map(slope);
	vec3 e = refl * reflection_gain * sky_fallback * shallow_fade;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	// Виміряно: gl_compatibility виводить EMISSION без лінійного -> sRGB (0.5 дає
	// 128, а не 188), тож тут кодуємо самі, інакше вода там чорна.
	e = pow(e, vec3(1.0 / 2.2));
#endif
	EMISSION = e;
	ALPHA = shallow_fade * 0.96;
}
