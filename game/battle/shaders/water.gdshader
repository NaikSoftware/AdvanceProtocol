// Річка. Похмура вода згори здебільшого відбиває небо: зблизька темний
// сіро-бірюзовий тон, здалеку — сріблястий блиск, найсвітліша смуга
// краєвиду; темна смуга відбитого берега вздовж обох берегів. Від трави її
// відділяє блиск, гладкість і мокра смуга берега, а не темрява.
//
// Відбиття — не екранний прохід (без SSR, §8): радіанс зонда BoardView приходить
// звичайним шляхом освітлення, а основне відбиття — небо SkyRig, яке вода бере
// напряму з тієї самої функції overcast_sky_at під глобальним sky_reflection_gain.
// Зонд не бачить шару юнітів, тож у воді не буває прихованого ворога.
shader_type spatial;
// specular_disabled: під похмурим небом сонячного відблиску немає, а на дрібній
// брижі він давав окремі яскраві пікселі. Відбиття (зонд і небо) лишаються.
render_mode blend_mix, cull_back, depth_draw_never, specular_disabled;

global uniform float weather_wetness;
// Сила власного відбиття неба. Вбудоване відбиття Godot для діелектрика не
// перевищує ~16 % (SPECULAR = 1), і з ним річка темна; тому небо відбиваємо самі.
// Погода (Task 10) може приглушити, типово 1.
global uniform float sky_reflection_gain;

uniform sampler2D kind_map : filter_nearest, repeat_disable;
// Клітинка, що відповідає пікселю (0, 0) kind_map (від'ємна при відступі).
uniform vec2 map_origin = vec2(0.0);
uniform int water_kind = 5;
uniform int broken_bridge_kind = 9;
// Річка тече й під цілим мостом; настил над нею — окремий меш.
uniform int bridge_kind = 8;
// Рельєф (TerrainHeight): вода є там, де земля нижча за її рівень. Без карти висот —
// за видом клітинки.
uniform bool use_height = false;
uniform sampler2D height_map : filter_linear, repeat_disable;
uniform float height_samples = 4.0;
uniform vec2 height_origin = vec2(-0.5);
uniform float water_level = -0.05;
// Вісь течії (одна на карту, WaterSurface.build).
uniform vec2 flow_dir = vec2(1.0, 0.0);
// Дві карти нормалей брижі (tools/water_normals.py); масштаб задає fragment():
// A — брижа ~0.6–1 м, B — ~0.25–0.4 м.
uniform sampler2D wave_a : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wave_b : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
// Тіло води (лінійні кольори): темна оливково-буро-сіра смуга біля берега — там у
// воді відбивається сам берег — і темна сіро-бірюзова глибина.
uniform vec3 shallow_color : source_color = vec3(0.05, 0.048, 0.036);
uniform vec3 deep_color : source_color = vec3(0.06, 0.068, 0.066);
// Відбите небо в річці — приглушене сіро-бірюзове, не бузкове.
uniform vec3 reflection_tint : source_color = vec3(0.95, 1.0, 0.96);
// Частка неба у відбитті згори й під пологим кутом. Справжня вода згори відбиває
// ~3 %, але справжнє похмуре небо в рази яскравіше за землю; небо тут
// приглушене, тож частка завищена, щоб вода, як справжня, читалась відбитим небом.
uniform float reflect_top = 0.26;
uniform float reflect_grazing = 0.7;
// Здалеку річка під похмурим небом блищить — найсвітліша смуга краєвиду; зблизька
// лишається темною. Підсилення відбиття на віддаленні (MAX zoom).
uniform float far_sheen = 1.2;
// Один широкий м'який відблиск світлої частини неба: висота над обрієм і сила.
uniform float glint_elevation_deg = 42.0;
uniform float glint_strength = 0.9;

varying vec3 world_pos;

#include "res://game/battle/shaders/surroundings.gdshaderinc"

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
	// До discard: похідні відстані для ширини лінії мусять рахуватись у всіх сусідніх пікселях.
	vec2 sd = surround_distance(p);
	vec4 sfog = surround ? surround_fog(p, sd, VIEWPORT_SIZE) : vec4(0.0);
	float shallow_fade = 1.0;
	float depth_m = 4.0;
	float bank_m = 4.0;
	if (use_height) {
		ivec2 hs = textureSize(height_map, 0);
		vec2 huv = ((p - height_origin) * height_samples + 0.5) / vec2(hs);
		// Глибина в метрах (1 м = 0.125 одиниці світу).
		depth_m = (water_level - texture(height_map, huv).r) / 0.125;
		if (depth_m <= 0.0) {
			discard;
		}
		// Коса плавно йде під воду: непрозорість росте на перших ~0.3 м глибини (дно глибше
		// за 0.3 м не просвічує, TerrainHeight тримає його там), без різкої межі урізу.
		shallow_fade = smoothstep(0.0, 0.3, depth_m);
		// Схил берега ~0.4 м на метр: глибина 1 м — ~2.5 м від урізу.
		bank_m = depth_m * 2.5;
	} else {
		// Та сама викривлена шумом межа, що й у землі: вода лежить усередині берегової смуги.
		vec2 g = border_warp(p) - map_origin;
		vec2 fw = border_weights(fract(g));
		ivec2 b = ivec2(floor(g));
		ivec2 size = textureSize(kind_map, 0);
		float w = mix(mix(water_at(b, size), water_at(b + ivec2(1, 0), size), fw.x),
				mix(water_at(b + ivec2(0, 1), size), water_at(b + ivec2(1, 1), size), fw.x), fw.y);
		if (w < 0.5) {
			discard;
		}
		shallow_fade = smoothstep(0.5, 0.72, w);
		bank_m = max(w - 0.5, 0.0) * 2.35;
	}
	float murk = exp(-2.0 * bank_m);

	// Кадр течії: x — уздовж, y — упоперек річки. Масштаб: клітинка = 8 м.
	vec2 fdir = normalize(flow_dir);
	vec2 fperp = vec2(-fdir.y, fdir.x);
	vec2 fp = vec2(dot(p, fdir), dot(p, fperp));
	// Дрібна брижа від вітру, не хвилі: річка 16 м завширшки при слабкому вітрі.
	// Два шари однієї природи, 0.55 і 0.2: A — повтор 1 клітинка вздовж і 1.5 упоперек
	// (гребені в 1.5 раза довші впоперек течії, ~0.5–0.8 м між ними), 0.8 м/с; B — ~0.25–0.4 м
	// (0.5 x 0.67 клітинки), трохи повернутий і повільніший, щоб шари не збігалися.
	// Легке хитання UV (0.01) прибирає рівномірне ковзання текстури одним цілим.
	vec2 wob = 0.01 * vec2(sin(fp.y * 3.0 + TIME * 0.7), cos(fp.x * 2.3 + TIME * 0.5));
	vec2 ta = texture(wave_a, fp * vec2(1.0, 0.67) + wob + vec2(TIME * 0.1, 0.0)).rg * 2.0 - 1.0;
	mat2 rot = mat2(vec2(0.985, 0.174), vec2(-0.174, 0.985));
	vec2 tb = texture(wave_b, rot * fp * vec2(2.0, 1.5) - wob + vec2(TIME * 0.15, 0.0)).rg * 2.0 - 1.0;
	// Розтяг упоперек течії зменшує нахил уздовж неї в 1.5 раза — повертаємо.
	// Третя октава (0.25) під ~60°, що дрейфує в інший бік: брижа не рухається одним напрямком.
	mat2 rot60 = mat2(vec2(0.5, 0.866), vec2(-0.866, 0.5));
	vec2 tc = texture(wave_a, rot60 * fp * vec2(1.3, 1.0) + wob.yx + vec2(-TIME * 0.07, TIME * 0.06)).rg * 2.0 - 1.0;
	vec2 sf = (ta * 0.55 + tb * 0.2 + transpose(rot60) * tc * 0.25) * vec2(0.4, 0.27);
	// Здалеку (піксель ~0.18–0.36 м) нахил гребенів слабшає: інакше на віддаленні вони
	// складаються в регулярний смугастий муар.
	sf *= mix(1.0, 0.35, smoothstep(0.022, 0.045, length(fwidth(p))));
	vec2 slope = fdir * sf.x + fperp * sf.y;
	float wet = clamp(weather_wetness, 0.0, 1.0);
	float rv = ripple_visibility(p);
	slope += rain_ripples(p, TIME) * 2.0 * wet * rv;

	vec3 n = slope_to_world(slope);
	vec3 v = normalize(CAMERA_POSITION_WORLD - world_pos);
	float f = mix(reflect_top, reflect_grazing, pow(1.0 - clamp(dot(n, v), 0.0, 1.0), 5.0));
	// Ледь помітна довга мінливість (~5–15 м), що повільно пливе: вода не рівна,
	// але без видимих гребенів — лише ±18 % відбиття.
	float slow = vnoise(fp * vec2(0.6, 0.9) - vec2(TIME * 0.05, 0.0));
	f *= 0.82 + 0.36 * slow;
	// Біля берега у воді відбивається сам берег, а не небо: темна смуга ~1–2 м.
	f *= 1.0 - 0.7 * exp(-1.2 * bank_m);
	// Піксель ~0.08 м (MIN zoom) -> 0, ~0.3 м (MAX zoom) -> 1.
	float far = smoothstep(0.012, 0.04, length(fwidth(p)));
	vec3 sky = overcast_sky_at(reflect(-v, n), TIME) * (1.0 + far_sheen * far);
	// Відблиск: світліша частина неба перед камерою. Напрямок — від осі камери
	// (поворот камери сталий), тож пляма стоїть на екрані, а вода пливе під нею, як
	// справжній відблиск при панорамуванні. Широка пляма з пригладженої нормалі —
	// без окремих яскравих пікселів.
	vec3 fwd = -INV_VIEW_MATRIX[2].xyz;
	vec2 fh = normalize(fwd.xz);
	float el = radians(glint_elevation_deg);
	vec3 gdir = vec3(fh.x * cos(el), sin(el), fh.y * cos(el));
	vec3 r_soft = reflect(-v, slope_to_world(slope * 0.3));
	float lobe = pow(max(dot(r_soft, gdir), 0.0), 4.0);
	sky += vec3(0.24, 0.25, 0.26) * glint_strength * lobe;
	vec3 e = sky * reflection_tint * f * sky_reflection_gain * shallow_fade;
	// Оливково-бура товща мілководдя (згасає за ~0.2 м глибини).
	e += vec3(0.045, 0.04, 0.02) * exp(-depth_m * 5.0) * shallow_fade;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	// Виміряно: gl_compatibility виводить EMISSION без лінійного -> sRGB (0.5 дає
	// 128, а не 188), тож тут кодуємо самі, інакше вода там чорна.
	e = pow(e, vec3(1.0 / 2.2));
#endif

	// Оливково-бурий край: глибина до 0.1–0.9 м (до ~2 м від урізу) — тепліша каламуть.
	float margin_t = 1.0 - smoothstep(0.1, 0.9, depth_m);
	vec3 body = mix(deep_color, shallow_color, murk);
	body = mix(body, vec3(0.06, 0.045, 0.022), 0.5 * margin_t);
	ALBEDO = body * (1.0 - f);
	if (surround) {
		ALBEDO = surround_grade(ALBEDO, sd.x);
		e = surround_grade(e, sd.x);
	}
	FOG = sfog;
	// Нижня межа шорсткості 0.1, а не 0.04: так радіанс зонда не дає окремих яскравих пікселів.
	// Здалеку дощ — дрібне мерехтіння: шорсткість замість рябі.
	// Низькочастотна мінливість шорсткості (~12 клітинок, ~100 м), без зміни напрямку брижі.
	ROUGHNESS = 0.1 + 0.1 * wet * (1.0 - rv) + 0.04 * vnoise(p * 0.08 + 9.0);
	SPECULAR = 0.5;
	NORMAL_MAP = slope_to_normal_map(slope);
	EMISSION = e;
	// Мілководдя прозоріше: крізь воду видно мул берега.
	ALPHA = shallow_fade * (0.96 - 0.3 * exp(-depth_m * 4.0));
}
