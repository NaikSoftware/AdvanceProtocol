// Річка. Похмура вода згори здебільшого відбиває небо: зблизька темний
// сіро-бірюзовий тон, здалеку — сріблястий блиск, найсвітліша смуга
// краєвиду; темна смуга відбитого берега вздовж обох берегів. Від трави її
// відділяє блиск, гладкість і мокра смуга берега, а не темрява.
//
// Відбиття — не екранний прохід (без SSR, §8): радіанс зонда BoardView приходить
// звичайним шляхом освітлення, а основне відбиття — небо WeatherRig, яке вода бере
// напряму з тієї самої функції overcast_sky_at під глобальним sky_reflection_gain.
// Зонд не бачить шару юнітів, тож у воді не буває прихованого ворога.
shader_type spatial;
// specular_disabled: під похмурим небом сонячного відблиску немає, а на дрібній
// брижі він давав окремі яскраві пікселі. Відбиття (зонд і небо) лишаються.
render_mode blend_mix, cull_back, depth_draw_never, specular_disabled;

global uniform float weather_wetness;
// Сила власного відбиття неба. Вбудоване відбиття Godot для діелектрика не
// перевищує ~16 % (SPECULAR = 1), і з ним річка темна; тому небо відбиваємо самі.
// Типово 1.
global uniform float sky_reflection_gain;
// Каламутність води під ясним небом (`BattleLook.water_murk`): 0 — вода як є; більше — відбите
// небо сіріше й тьмяніше, товща оливково-темна. Сільський став згори на сонці темний, а не
// блакитний: синє небо віддзеркалюється в ньому лише сірувато.
global uniform float water_murk;
// Вітер над водою (`BattleLook.water_wind`): 1 — брижа Річки, менше — тихіше повітря, і брижа
// водночас дрібніша й повільніша.
global uniform float water_wind;

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

// Очерет у воді (VegetationLayer.reed_mask): L8 з міпмапами над клітинками дошки, (0, 0) — кут
// клітинки (0, 0). Біля куртини вода відбиває темні стебла, а не небо.
uniform bool use_reeds = false;
uniform sampler2D reed_mask : hint_default_black, filter_linear_mipmap, repeat_disable;
uniform vec2 reed_size = vec2(1.0);
// Висота густої частини стебел (одиниці світу, клітинка = 8 м): з неї довжина відбиття.
uniform float reed_height = 0.25;

varying vec3 world_pos;

#include "res://game/battle/shaders/surroundings.gdshaderinc"

#include "res://game/battle/shaders/terrain_noise.gdshaderinc"

float water_at(ivec2 px, ivec2 size) {
	int kind = int(texelFetch(kind_map, clamp(px, ivec2(0), size - 1), 0).r * 255.0 + 0.5);
	return (kind == water_kind || kind == bridge_kind || kind == broken_bridge_kind) ? 1.0 : 0.0;
}

float reed_at(vec2 p, float lod) {
	vec2 uv = (p + 0.5) / reed_size;
	if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) {
		return 0.0;
	}
	return textureLod(reed_mask, uv, lod).r;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Висота дна кубічним B-сплайном із чотирьох білінійних відліків: функція гладка (C2), тож її рівень
// води — плавна крива без зламів на межах текселів.
float height_bspline(vec2 uv, vec2 size) {
	vec2 st = uv * size - 0.5;
	vec2 i = floor(st);
	vec2 f = st - i;
	vec2 f2 = f * f;
	vec2 f3 = f2 * f;
	vec2 w0 = (1.0 - 3.0 * f + 3.0 * f2 - f3) / 6.0;
	vec2 w1 = (4.0 - 6.0 * f2 + 3.0 * f3) / 6.0;
	vec2 w2 = (1.0 + 3.0 * f + 3.0 * f2 - 3.0 * f3) / 6.0;
	vec2 w3 = f3 / 6.0;
	vec2 g0 = w0 + w1;
	vec2 g1 = w2 + w3;
	vec2 c0 = (i - 0.5 + w1 / g0) / size;
	vec2 c1 = (i + 1.5 + w3 / g1) / size;
	return g0.y * (g0.x * textureLod(height_map, vec2(c0.x, c0.y), 0.0).r + g1.x * textureLod(height_map, vec2(c1.x, c0.y), 0.0).r)
			+ g1.y * (g0.x * textureLod(height_map, vec2(c0.x, c1.y), 0.0).r + g1.x * textureLod(height_map, vec2(c1.x, c1.y), 0.0).r);
}

void fragment() {
	vec2 p = world_pos.xz;
	// Усе, що бере похідні (ширина лінії, міп брижі, видимість дощу), — до discard і до гілки
	// суцільної імли: у сусідніх пікселях, що пішли іншою гілкою, похідні не визначені.
	vec2 dpx = dFdx(p);
	vec2 dpy = dFdy(p);
	float px_m = length(abs(dpx) + abs(dpy));
	float rv = ripple_visibility(p);
	vec4 haze = vec4(0.0);
	vec4 sfog = vec4(0.0);
	if (surround) {
		haze = fog_bank(world_pos, CAMERA_POSITION_WORLD, normalize(-INV_VIEW_MATRIX[2].xz));
		float line_a = surround_line(world_pos, CAMERA_POSITION_WORLD, 0.0, VIEWPORT_SIZE);
		sfog = surround_fog(haze, line_a);
	}
	float shallow_fade = 1.0;
	float depth_m = 4.0;
	float bank_m = 4.0;
	if (use_height) {
		ivec2 hs = textureSize(height_map, 0);
		vec2 huv = ((p - height_origin) * height_samples + 0.5) / vec2(hs);
		// Глибина в метрах (1 м = 0.125 одиниці світу). Річка — висота кубічним B-сплайном (4 білінійні
		// відліки): нуль білінійної висоти ламається на межах текселів (~2 м), і чіткий уріз мав би зубці.
		float hbed = water_murk <= 0.0 ? height_bspline(huv, vec2(hs)) : textureLod(height_map, huv, 0.0).r;
		depth_m = (water_level - hbed) / 0.125;
		if (depth_m <= 0.0) {
			discard;
		}
		// Коса плавно йде під воду: непрозорість росте на перших ~0.3 м глибини (дно глибше
		// за 0.3 м не просвічує, TerrainHeight тримає його там), без різкої межі урізу.
		// Каламутний ставок — 0.15 м: на 0.3 м край ставав темним розмитим ореолом, на 0.08 — сходинками.
		shallow_fade = smoothstep(0.0, mix(0.3, 0.15, clamp(water_murk, 0.0, 1.0)), depth_m);
		// Річка над пологою мілиною: 0.3 м глибини там тягнуться на багато метрів, тож непрозорість росте
		// ще й за відстанню від урізу по горизонталі: глибина / нахил дна (центральні різниці висоти).
		// Перехід ~0.6 м (не вужчий за 2 px): з висотою B-сплайном зубців обрису нема, а ширший
		// лягав на берег розмитою сірою тінню замість урізу. Каламутний ставок — лише за
		// глибиною: чіткий край там показав би трикутники сітки рельєфу на урізі.
		if (water_murk <= 0.0) {
			// Нахил дна — центральні різниці білінійної висоти за ±1 тексель: неперервний по площині, тоді
			// як похідні екрана рахуються блоками 2×2 пікселі й давали гребінчастий край.
			vec2 tx = vec2(1.0 / float(hs.x), 0.0);
			vec2 tz = vec2(0.0, 1.0 / float(hs.y));
			float texel_m = 8.0 / height_samples; // клітинка = 8 м
			vec2 grad = vec2(textureLod(height_map, huv + tx, 0.0).r - textureLod(height_map, huv - tx, 0.0).r,
					textureLod(height_map, huv + tz, 0.0).r - textureLod(height_map, huv - tz, 0.0).r) / (2.0 * texel_m * 0.125);
			float run_m = depth_m / max(length(grad), 0.02);
			float px_edge = max(length(dpx), length(dpy)) * 8.0; // піксель у метрах, клітинка = 8 м
			shallow_fade = max(shallow_fade, smoothstep(0.0, max(0.6, 2.0 * px_edge), run_m));
		}
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
	// Під суцільною імлою (після discard: вода не мусить лягти на сушу) — лише її колір.
	if (sfog.a >= 0.999) {
		ALBEDO = vec3(0.0);
		FOG = sfog;
		ALPHA = 1.0;
	} else {
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
		// Час брижі йде з вітром: у тихе повітря вона й дрібніша, і повільніша.
		float wt = TIME * water_wind;
		vec2 wob = 0.01 * vec2(sin(fp.y * 3.0 + wt * 0.7), cos(fp.x * 2.3 + wt * 0.5));
		// Похідні UV брижі — з похідних p (кадр течії — поворот), ×1.5: міп на ~0.6 рівня
		// грубший, і далекі гребені зливаються в тон, а не в смуги.
		mat2 frame = mat2(vec2(fdir.x, fperp.x), vec2(fdir.y, fperp.y));
		vec2 fdx = frame * dpx * 1.5;
		vec2 fdy = frame * dpy * 1.5;
		vec2 ka = vec2(1.0, 0.67);
		vec2 ta = textureGrad(wave_a, fp * ka + wob + vec2(wt * 0.1, 0.0), fdx * ka, fdy * ka).rg
				* 2.0 - 1.0;
		mat2 rot = mat2(vec2(0.985, 0.174), vec2(-0.174, 0.985));
		vec2 kb = vec2(2.0, 1.5);
		vec2 tb = textureGrad(wave_b, rot * fp * kb - wob + vec2(wt * 0.15, 0.0), rot * (fdx * kb),
				rot * (fdy * kb)).rg * 2.0 - 1.0;
		// Розтяг упоперек течії зменшує нахил уздовж неї в 1.5 раза — повертаємо.
		// Третя октава (0.25) під ~60°, що дрейфує в інший бік: брижа не рухається одним напрямком.
		mat2 rot60 = mat2(vec2(0.5, 0.866), vec2(-0.866, 0.5));
		vec2 kc = vec2(1.3, 1.0);
		vec2 tc = textureGrad(wave_a, rot60 * fp * kc + wob.yx + vec2(-wt * 0.07, wt * 0.06),
				rot60 * (fdx * kc), rot60 * (fdy * kc)).rg * 2.0 - 1.0;
		vec2 sf = (ta * 0.55 + tb * 0.2 + transpose(rot60) * tc * 0.25) * vec2(0.4, 0.27)
				* water_wind;
		// Тихий ставок під ясним небом: рівна цятка брижі читалась візерунком — друга октава
		// в ~3 рази більша, що повільно дрейфує, ламає її. Похмурий вигляд (sky_clear = 0, River)
		// не змінюється.
		if (sky_clear > 0.0) {
			// Під сонцем дрібні ямки брижі читались кованим металом: брижа втричі більша, плюс широка
			// повільна хвиля ~10× більша, і вся вдвічі слабша.
			vec2 kd = kb / 3.0;
			vec2 td = textureGrad(wave_b, rot60 * fp * kd + vec2(wt * 0.03, -wt * 0.02), rot60 * (fdx * kd),
					rot60 * (fdy * kd)).rg * 2.0 - 1.0;
			vec2 kl = ka / 10.0;
			vec2 tl = textureGrad(wave_a, fp * kl + vec2(wt * 0.01, wt * 0.008), fdx * kl, fdy * kl).rg * 2.0 - 1.0;
			vec2 big = (transpose(rot60) * td * 0.6 + tl * 0.4) * vec2(0.4, 0.27) * water_wind;
			sf = mix(sf, big, sky_clear) * mix(1.0, 0.5, sky_clear);
		}
		// Нахил гребенів слабшає зі слідом пікселя вздовж погляду (розмір пікселя / sin кута до
		// води): коли слід ширший за ~0.15 м, гребені під пологим кутом складаються в
		// горизонтальне штрихування, і рівна поверхня з відбитим небом читається краще.
		vec3 vdir = normalize(CAMERA_POSITION_WORLD - world_pos);
		sf *= mix(1.0, 0.08, smoothstep(0.018, 0.032, px_m / max(vdir.y, 0.2)));
		vec2 slope = fdir * sf.x + fperp * sf.y;
		float wet = clamp(weather_wetness, 0.0, 1.0);
		// Нахил кіл дощу ×4 (з ×1.5 у самій rain_ripples — ×6): менші й рідші кола інакше губились
		// на брижі.
		slope += rain_ripples(p, TIME) * 4.0 * wet * rv;

		vec3 n = slope_to_world(slope);
		vec3 v = normalize(CAMERA_POSITION_WORLD - world_pos);
		float f = mix(reflect_top, reflect_grazing, pow(1.0 - clamp(dot(n, v), 0.0, 1.0), 5.0));
		// Ледь помітна довга мінливість (~5–15 м), що повільно пливе: вода не рівна,
		// але без видимих гребенів — лише ±18 % відбиття.
		float slow = vnoise(fp * vec2(0.6, 0.9) - vec2(TIME * 0.05, 0.0));
		f *= 0.82 + 0.36 * slow;
		// Під ясним небом — ще ледь помітний градієнт неба на ~10–20 м (±8 %).
		f *= 1.0 + 0.16 * sky_clear * (vnoise(fp * 0.12 + 3.0) - 0.5);
		// Біля берега у воді відбивається сам берег, а не небо: темна смуга ~1–2 м.
		f *= 1.0 - 0.7 * exp(-1.2 * bank_m);
		// Очерет: стебла в точці q + fh·s видно у відбитті з q, поки промінь не вищий за них
		// (s · tg кута погляду < висоти), тож темне відбиття лягає від куртини до камери, коротке й
		// поламане брижею, смугами окремих стебел уздовж погляду. Плюс м'яка темна облямівка під
		// самою куртиною з грубшого міпу: вода там відбиває стебла й тінь, а не світле небо.
		float reed = 0.0;
		float reed_refl = 0.0;
		if (use_reeds) {
			vec2 rfh = normalize(-INV_VIEW_MATRIX[2].xz);
			float reach = reed_height * length(v.xz) / max(v.y, 0.2);
			vec2 q = p + slope * 0.6;
			for (int i = 0; i < 4; i++) {
				float t = (float(i) + 0.5) / 4.0;
				reed_refl = max(reed_refl, reed_at(q + rfh * reach * t, 0.0) * (1.0 - 0.6 * t));
			}
			// Смуги стебел ~0.3 м упоперек погляду, що тремтять разом із брижею.
			vec2 rq = vec2(dot(q, vec2(-rfh.y, rfh.x)), dot(q, rfh));
			reed_refl *= 0.55 + 0.45 * vnoise(rq * vec2(26.0, 3.0));
			reed_refl = clamp(3.0 * reed_refl, 0.0, 1.0);
			reed = max(reed_refl, clamp(1.4 * reed_at(p, 2.0), 0.0, 1.0));
			f *= 1.0 - 0.9 * reed;
		}
		// Піксель ~0.08 м (MIN zoom) -> 0, ~0.3 м (MAX zoom) -> 1.
		float far = smoothstep(0.012, 0.04, px_m);
		float murk_k = clamp(water_murk, 0.0, 1.0);
		// Під ясним небом край дрібної хмари, відбитий крізь брижу, малює звивисті кола-контури.
		// Каламутна вода відбиває небо ближче до рівної поверхні: дзеркало великих хмар, без кіл.
		// На Річці (murk 0) нормаль та сама до біта.
		vec3 n_sky = murk_k > 0.0 ? normalize(mix(n, vec3(0.0, 1.0, 0.0), 0.6 * murk_k)) : n;
		vec3 sky = overcast_sky_at(reflect(-v, n_sky), TIME, sky_clear) * (1.0 + far_sheen * far);
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
		sky = mix(sky, vec3(dot(sky, vec3(0.2126, 0.7152, 0.0722))) * vec3(0.92, 0.98, 1.02),
				murk_k) * (1.0 - 0.8 * murk_k);
		vec3 e = sky * reflection_tint * f * sky_reflection_gain * shallow_fade;
		// Сухі стебла у відбитті — тьмяно-бурі, а не чорні.
		e += vec3(0.028, 0.02, 0.01) * reed_refl * shallow_fade;
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
		body = mix(body, vec3(0.032, 0.036, 0.02), 0.7 * murk_k);
		ALBEDO = body * (1.0 - f) * (1.0 - 0.5 * reed);
		if (surround) {
			ALBEDO = surround_grade(ALBEDO, haze.a);
			e = surround_grade(e, haze.a);
		}
		FOG = sfog;
		// Нижня межа шорсткості 0.1, а не 0.04: так радіанс зонда не дає окремих яскравих пікселів.
		// Здалеку дощ — дрібне мерехтіння: шорсткість замість рябі.
		// Низькочастотна мінливість шорсткості (~12 клітинок, ~100 м), без зміни напрямку брижі.
		ROUGHNESS = 0.1 + 0.1 * wet * (1.0 - rv) + 0.04 * vnoise(p * 0.08 + 9.0);
		// Зонд знімає те саме синє небо: каламутна вода віддзеркалює його слабше.
		SPECULAR = 0.5 * (1.0 - 0.8 * murk_k) * (1.0 - reed);
		NORMAL_MAP = slope_to_normal_map(slope);
		EMISSION = e;
		// Мілководдя прозоріше: крізь воду видно мул берега.
		// Каламутна вода непрозора: крізь неї не просвічує освітлене сонцем дно.
		ALPHA = shallow_fade * (0.96 - 0.3 * exp(-depth_m * 4.0) * (1.0 - murk_k));
	}
}
