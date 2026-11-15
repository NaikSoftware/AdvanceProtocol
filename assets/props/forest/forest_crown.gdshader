shader_type spatial;
// Крона, кущ або стовбур із бібліотеки лісу (forest_conifer.glb, forest_broadleaf_*.glb).
//
// Картки пучків розгортаються до камери у вершинному шейдері: усі чотири вершини картки
// лежать у її центрі, а UV2 несе зсув кута в одиницях гри. Так картку ніколи не видно
// ребром — у нерухомій картці з довільним поворотом екземпляра частина пучків стояла б до
// камери боком і читалась смугою. У проході тіні «камера» — світло, тож тінь пучка теж повна.
// Стовбури й гілки (UV2 = 0) лишаються звичайною геометрією.
//
// Альфа кольору екземпляра `MultiMesh` — розчинення над юнітом: 1 — ціла крона, 0 — немає
// ні крони, ні її тіні. Проміжне значення гасить цілі пучки за порогом із хешу їхнього
// центру: крона в перехідному кільці рідшає пучками. Піксельний растр (матриця Баєра чи
// градієнтний шум) на 1:1 читався діагональною сіткою, а напівпрозора крона — привидом.
// Фрагменти відкидаються, а не змішуються: без сортування прозорих.
// Тінь не раструється: крона з альфою екземпляра < 0,5 тіні не кидає, решта кидає повну.
// RGB кольору вершини — місце пучка в кроні: 0,55 низ і глибина … 1 верх (1 на корі).
// Тон екземпляра (розкид, осіннє забарвлення цілої крони) — у custom data `MultiMesh`, а не
// в кольорі: Godot множить колір екземпляра на колір вершини ще до коду шейдера, і тон
// змішався б із місцем пучка.
// alpha_to_coverage вмикає покриття MSAA: без нього ALPHA_ANTIALIASING_EDGE нічого не дає.
render_mode cull_disabled, depth_draw_opaque, skip_vertex_transform, alpha_to_coverage;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.5;
// Тон листя під світло карти (BattleLook.foliage_tint, ставить WeatherRig): похмуре
// синювате розсіяне світло робить буре фіолетовим, і цей множник його повертає.
global uniform vec3 foliage_tint;
// М'яке огортання світлом і просвічування: тіньовий бік пучка не чорніє, як у листя.
uniform float wrap = 0.65;
uniform float translucency = 0.1;
// Затінення множить колір (AO рендерер тут не застосовує). Два рівні:
// - пучок: світлий верх → темний низ у межах картки (~±8 L*), тож кожна грудка кругла;
// - крона: низ і край крони темніші на crown_depth, де крони перекриваються.
// Різниця між пучками навмисне мала: світлі грудки поверх темних читались камуфляжем.
uniform float lobe_depth = 0.35;
uniform float crown_depth = 0.1;
// Ширина краю alpha-to-coverage (у частках альфи).
uniform float a2c_edge = 0.3;
// Кора й стовбури темніші: стовбур стоїть у тіні крони, а розсіяне світло неба на нього
// падає повне — без цього стовбури світилися світліше за ґрунт.
uniform float bark_dark = 0.45;
// Темний обідок пучка: м'який край замість різкої вирізаної лінії наліпки.
uniform float rim = 0.15;
uniform float card_round = 0.7;
uniform float card_up = 1.2;
// Контури зон і кільця дальності (BoardView) лежать на землі, і крона їх закрила б: тож крона
// малює ту саму лінію сама (ForestLayer.set_contour_edges, set_contour_rings). Типово вимкнено:
// розчинена крона й стенди лісу лінії не малюють.
// Картка ребер: у (2k, j) — ребро x = k − 0,5 у ряді j, у (2i + 1, k) — ребро z = k − 0,5 у стовпці i.
// Колір у sRGB, як у вершин стрічки: source_color переводить його так само, як рендерер — стрічку.
uniform bool contour_on = false;
uniform sampler2D contour_edges : source_color, filter_nearest, repeat_disable;
uniform float contour_half = 0.01;
uniform float contour_lift = 0.04;
// Кільця: xy — центр, z — радіус (тайли), w — поступ імпульсу (BoardView). Колір — sRGB, source_color,
// як ring_color кільця на землі: кожен рендерер переводить його так само, і кольори збігаються.
uniform int ring_count = 0;
uniform vec4 rings[4];
uniform vec4 ring_colors[4] : source_color;
// 1 — кільце несе хвилю імпульсу (найбільше коло огляду), 0 — лише межу (fire_ring, band).
uniform float ring_bands[4];
// Рельєф (`TerrainHeight.texture()`, як у UnitContacts): точка землі під пікселем уточнюється за
// висотою в ній самій. Площина на висоті стовбура на схилі зсувала лінію на кроні від лінії на
// землі на кілька пікселів.
uniform bool use_height = false;
uniform sampler2D height_map : filter_linear, repeat_disable;
uniform float height_samples = 4.0;
uniform float height_origin = -0.5;
// Стрічка контуру й сітка кільця над річкою лежать на воді, а не на дні: земля під кроною — так само.
// shortcut: на мосту стрічка лежить на настилі, а тут — на воді; ліс біля мостів на картах не росте.
uniform float water_level = -0.15625;
// Маска шару накладок (BoardView.OVERLAY_LAYER): лінія — лише для камери, що бачить накладки.
// Зонд відбиттів знімає крони (шар 1), але не накладки: у його знімку лінії активного гравця
// лишились би для наступного.
uniform int overlay_layers = 0;
// Рамка всіх ліній на землі (xy — мінімум, zw — максимум, XZ світу; BoardView.line_rect): крона, чий
// промінь до землі її не перетинає, лінії не несе й землі під собою не шукає. Типово порожня.
uniform vec4 line_rect = vec4(1.0, 1.0, 0.0, 0.0);
// Клітинки показаних юнітів (ForestLayer.set_reveal_cells): лінію за юнітом ховає сам юніт, тож крона,
// чий промінь до землі проходить крізь юніта, лінії не малює — інакше пучки перед ним несли б її уривки.
uniform bool units_on = false;
uniform sampler2D unit_cells : filter_nearest, repeat_disable;
// Висота юніта, крізь яку промінь не проходить, і радіус його сліду в клітинці, тайли.
const float UNIT_TOP = 0.3;
const float UNIT_REACH = 0.45;

#include "res://game/battle/shaders/surroundings.gdshaderinc"
#include "res://game/battle/shaders/fire_ring.gdshaderinc"

// Точка у світі після розгортання картки: для імли кільця (fog_bank), як у пропсів.
varying vec3 world_pos;
varying float is_card;
varying flat float card_half;
varying vec3 inst_tone;
varying flat float piece_hash;
// Висота землі під деревом: на ній шукаються лінії під кроною.
varying flat float base_y;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

// Тексель картки ребер; за її межами ребра немає.
vec4 edge_texel(ivec2 p, ivec2 ts) {
	return (p.x < 0 || p.y < 0 || p.x >= ts.x || p.y >= ts.y) ? vec4(0.0) : texelFetch(contour_edges, p, 0);
}

// Висота землі під лініями в точці g: та сама, на яку BoardView кладе стрічку й кільце.
float line_ground(vec2 g) {
	vec2 hs = vec2(textureSize(height_map, 0));
	return max(textureLod(height_map, ((g - height_origin) * height_samples + 0.5) / hs, 0.0).r, water_level);
}

// Чи стоїть у точці землі p показаний юніт (у межах його сліду в клітинці).
bool unit_at(vec2 p) {
	ivec2 c = ivec2(floor(p + 0.5));
	ivec2 ts = textureSize(unit_cells, 0);
	if (c.x < 0 || c.y < 0 || c.x >= ts.x || c.y >= ts.y) {
		return false;
	}
	return texelFetch(unit_cells, c, 0).r > 0.5 && length(p - vec2(c)) < UNIT_REACH;
}

// Точка землі, яку закриває точка крони p: перший перетин променя камери за p з поверхнею ліній
// (земля + lift) — кроками вниз від p до рівня води, далі січна. Проста ітерація g = F(g) не
// збігається на схилі, крутішому за нахил камери (дальній бік пагорба), і лінія на кроні там
// розпливалась плямою.
vec2 line_hit(vec3 eye, vec3 p, float lift) {
	float k = 1.0 / max(eye.y - p.y, 1e-4);
	float ya = p.y;
	float fa = ya - line_ground(p.xz) - lift;
	float y_lo = water_level + lift;
	for (int i = 1; i <= 6 && fa > 0.0; i++) {
		float yb = mix(p.y, y_lo, float(i) / 6.0);
		float fb = yb - line_ground(mix(eye.xz, p.xz, (eye.y - yb) * k)) - lift;
		if (fb <= 0.0) {
			for (int j = 0; j < 2; j++) {
				float yc = mix(ya, yb, fa / max(fa - fb, 1e-6));
				float fc = yc - line_ground(mix(eye.xz, p.xz, (eye.y - yc) * k)) - lift;
				if (fc > 0.0) {
					ya = yc;
					fa = fc;
				} else {
					yb = yc;
					fb = fc;
				}
			}
			// fa > 0 ≥ fb, але денормалізоване fa на GPU обнуляється: ділення без захисту дало б NaN.
			return mix(eye.xz, p.xz, (eye.y - mix(ya, yb, fa / max(fa - fb, 1e-6))) * k);
		}
		ya = yb;
		fa = fb;
	}
	return mix(eye.xz, p.xz, (eye.y - ya) * k);
}

// З двох текселів одного ребра — той, де лінія є.
vec4 edge_pick(ivec2 a, ivec2 b, ivec2 ts) {
	vec4 ea = edge_texel(a, ts);
	return ea.a > 0.0 ? ea : edge_texel(b, ts);
}

void vertex() {
	// Чотири вершини картки лежать в одній точці, тож хеш однаковий для всього пучка.
	piece_hash = hash13(VERTEX * 97.0 + 0.5);
	base_y = MODEL_MATRIX[3].y;
	// Без custom data (поодинокий MeshInstance3D) INSTANCE_CUSTOM — нулі: тон 1.
	inst_tone = dot(INSTANCE_CUSTOM.rgb, INSTANCE_CUSTOM.rgb) > 0.0 ? INSTANCE_CUSTOM.rgb : vec3(1.0);
	vec3 v = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	is_card = dot(UV2, UV2) > 0.0 ? 1.0 : 0.0;
	// Півдіагональ картки (усі 4 кути однаково далекі від центру) — для градієнта пучка.
	card_half = length(UV2);
	if (is_card > 0.5) {
		// Масштаб екземпляра по горизонталі: картка росте разом із кроною.
		float s = length(MODEL_MATRIX[0].xyz);
		v.xy += UV2 * s;
	}
	VERTEX = v;
	world_pos = (INV_VIEW_MATRIX * vec4(v, 1.0)).xyz;
	NORMAL = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	if (is_card > 0.5) {
		// Кути картки нахилені назовні: світло котиться по пучку, як по кулі, і крона
		// світлішає до сонця плавно, а не ступенями світлий/темний пучок.
		NORMAL = normalize(NORMAL + card_round * vec3(normalize(UV2), 0.0));
		// Нормаль пучка нахилена вгору: задні пучки крони, що проглядають між передніми,
		// інакше стоять до сонця спиною й темніють — крона рябіє світлими й темними
		// грудками. Так уся крона світиться як один купол згори; низ темнить occ.
		NORMAL = normalize(NORMAL + card_up * (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	}
}

void fragment() {
	// Зміщення mip на −0,5: ближні крони на мінімальному зумі інакше розмиті.
	vec4 t = texture(albedo_tex, UV, -0.5);
	// Тінь напрямленого світла рендериться ортографічно, а камера гри — у перспективі.
	bool shadow_pass = PROJECTION_MATRIX[3][3] > 0.5;
	// На далеких mip-рівнях тонкі гілки усереднюються з прозорим тлом і тануть під порогом:
	// голе дерево здаля лишилось би самим стовбуром. Тож поріг знижується з рівнем mip, але лише
	// здаля (від mip 2,5): на ближньому зумі знижений поріг на розмитому mip роздував обрис
	// пучка в кілька гладких лопатей. І не в тіні: там гола крона зливалась у пляму.
	// Рівень mip із похідних UV: textureQueryLod немає в gl_compatibility (GLES3).
	vec2 texel = UV * vec2(textureSize(albedo_tex, 0));
	float lod = max(0.5 * log2(max(dot(dFdx(texel), dFdx(texel)), dot(dFdy(texel), dFdy(texel)))), 0.0);
	float cut = shadow_pass ? alpha_cutoff : alpha_cutoff * mix(1.0, 0.3, clamp((lod - 2.5) / 2.0, 0.0, 1.0));
	// Силует — з різкого рівня: обрис пучка — дрібне листя. Розмитіший mip для порогу
	// робив із пучка кілька великих лопатей — «листки» по метру на ближньому зумі.
	if ((shadow_pass && t.a < cut) || COLOR.a < (shadow_pass ? 0.5 : 0.001) || (!shadow_pass && piece_hash > COLOR.a)) {
		discard;
	}
	vec3 tint = mix(vec3(1.0), foliage_tint, is_card);
	// Здаля дрібний малюнок пучка (листки, світлі й темні гілочки) — це шум на кілька
	// пікселів: колір плавно йде до середнього з ширшої ділянки, і крона читається масою.
	vec3 coarse = textureLod(albedo_tex, UV, lod + 2.0).rgb;
	// Зблизька — трохи ширшого mip: світлі й темні листки всередині пучка спокійніші, але
	// дрібне листя лишається; більше — і пучок стає пласкою лопатевою плямою.
	vec3 rgb = mix(t.rgb, coarse, is_card * mix(0.15, 0.85, smoothstep(2.0, 3.5, lod)));
	float crown = clamp((COLOR.r - 0.55) / 0.45, 0.0, 1.0);
	float lobe = clamp(0.5 + 0.5 * UV2.y / max(card_half * 0.7071, 1e-4), 0.0, 1.0);
	float occ = mix(1.0, mix(1.0 - lobe_depth, 1.0, lobe) * mix(1.0 - crown_depth, 1.0, crown), is_card);
	// Альфа сусіднього mip падає біля краю силуету пучка — там він і темніє. Здаля mip уже
	// усереднений скрізь, і обідок затемнив би всю крону, тож там він гасне.
	float edge = textureLod(albedo_tex, UV, lod + 1.0).a;
	float r = mix(1.0, mix(1.0 - rim, 1.0, smoothstep(0.35, 0.85, edge)), is_card * (1.0 - smoothstep(2.0, 3.0, lod)));
	// Затінення крони — у колір: AO рендерер тут не застосовує (розсіяне світло неба
	// від нього не змінюється), і без цього крона лишалась пласкою.
	ALBEDO = rgb * mix(COLOR.rgb, vec3(1.0), is_card) * inst_tone * tint * r * occ * mix(bark_dark, 1.0, is_card);
	ROUGHNESS = 1.0;
	SPECULAR = 0.15;
	// Імла кільця, як у землі й будинків: крона за краєм дошки тоне в ній, а не висить над нею.
	FOG = vec4(0.0);
	if (surround) {
		vec4 haze = fog_bank(world_pos, CAMERA_POSITION_WORLD, normalize(-INV_VIEW_MATRIX[2].xz));
		ALBEDO = surround_grade(ALBEDO, haze.a);
		FOG = surround_fog(haze, 0.0);
	}
	// Промінь камери крізь піксель до площини лінії (земля під деревом) — точка землі, яку піксель
	// закриває; лінія там — і тут той самий колір і ширина, неосвітлені, як стрічка на землі.
	// Крона, що рідшає над показаним юнітом (альфа екземпляра < 1), ліній не малює, як і розчинена:
	// промінь крізь її пучки до землі йде через юніта, і лінія лягла б уривками перед ним.
	if (!shadow_pass && COLOR.a > 0.999 && (contour_on || ring_count > 0) && (CAMERA_VISIBLE_LAYERS & uint(overlay_layers)) != 0u) {
		vec3 eye = CAMERA_POSITION_WORLD;
		float k_ray = 1.0 / max(eye.y - world_pos.y, 1e-4);
		float gy = max(base_y, water_level);
		vec2 g = mix(eye.xz, world_pos.xz, (eye.y - gy - contour_lift) * k_ray);
		// Слід пікселя на землі — з перетину променя з площиною під деревом: він залежить лише від
		// променя, тож гладкий по всій картці. Похідні уточненої точки на кроні стрибають, і лінія
		// там розпливалась на кілька своїх ширин.
		vec2 gw = max(fwidth(g), vec2(1e-5));
		float px = max(0.7071 * length(vec2(length(dFdx(g)), length(dFdy(g)))), 1e-4);
		// Відрізок променя від точки крони до рівня води: лише на ньому може лежати земля під пікселем.
		// Не зачепив рамки ліній — лінії тут немає, і крок променем не потрібен.
		vec2 g_lo = mix(eye.xz, world_pos.xz, (eye.y - water_level - contour_lift) * k_ray);
		vec2 seg_lo = min(world_pos.xz, g_lo);
		vec2 seg_hi = max(world_pos.xz, g_lo);
		if (all(lessThanEqual(seg_lo, line_rect.zw)) && all(greaterThanEqual(seg_hi, line_rect.xy))) {
			// Чи ця точка крони над стрічкою: тоді промінь до стрічки йде крізь неї, і лінію малює вона.
			// Колода нижче за стрічку лінію не малює — стрічка лягає поверх неї й так. Висота — під самою
			// точкою, а не в g: біля висоти стрічки g ще не збігся, і колода малювала б лінію вдруге.
			float here = base_y;
			if (use_height) {
				here = line_ground(world_pos.xz);
				g = line_hit(eye, world_pos, contour_lift);
			}
			float above = step(here + contour_lift, world_pos.y);
			if (units_on && above > 0.0) {
				// Останній відрізок променя, нижчий за юніта: від висоти його верху (чи від самої точки крони,
				// коли вона нижча) до землі. Юніт на ньому — і лінії тут не видно.
				float gyh = use_height ? line_ground(g) : max(base_y, water_level);
				vec2 top = world_pos.y > gyh + UNIT_TOP ? mix(eye.xz, world_pos.xz, (eye.y - gyh - UNIT_TOP) * k_ray) : world_pos.xz;
				if (unit_at(g) || unit_at(mix(g, top, 0.5)) || unit_at(top)) {
					above = 0.0;
				}
			}
			// Колір із домноженою альфою: кільце під лінією зон, як на землі.
			vec3 pre = vec3(0.0);
			float cov = 0.0;
			// Кільце не обрізане краєм дошки: на землі воно йде й за край, і розрив на кронах кільця читався б помилкою.
			for (int i = 0; i < ring_count && i < 4; i++) {
				float a = ring_colors[i].a * fire_ring(g - rings[i].xy, rings[i].z, rings[i].w, ring_bands[i], px);
				pre = mix(pre, ring_colors[i].rgb, a);
				cov = a + cov * (1.0 - a);
			}
			if (contour_on) {
				ivec2 ts = textureSize(contour_edges, 0);
				// Ряд (стовпець) береться з обох боків на півширини: лінія заходить за кут, як і стрічка.
				int k = int(floor(g.x + 1.0));
				vec4 ev = edge_pick(ivec2(2 * k, int(floor(g.y + 0.5 - contour_half))), ivec2(2 * k, int(floor(g.y + 0.5 + contour_half))), ts);
				float av = ev.a * clamp((contour_half - abs(g.x - float(k) + 0.5)) / gw.x + 0.5, 0.0, 1.0);
				int m = int(floor(g.y + 1.0));
				vec4 eh = edge_pick(ivec2(2 * int(floor(g.x + 0.5 - contour_half)) + 1, m), ivec2(2 * int(floor(g.x + 0.5 + contour_half)) + 1, m), ts);
				float ah = eh.a * clamp((contour_half - abs(g.y - float(m) + 0.5)) / gw.y + 0.5, 0.0, 1.0);
				vec4 e = av >= ah ? vec4(ev.rgb, av) : vec4(eh.rgb, ah);
				pre = mix(pre, e.rgb, e.a);
				cov = e.a + cov * (1.0 - e.a);
			}
			ALBEDO *= 1.0 - cov * above;
			SPECULAR *= 1.0 - cov * above;
			EMISSION = pre * above;
			// Лінія за краєм дошки не тоне в імлі кільця: на землі її теж ніщо не туманить.
			FOG.a *= 1.0 - cov * above;
		}
	}
	// Край пучка — alpha-to-coverage (MSAA): м'який перехід на 1–2 пікселі без растру й без
	// окремого прозорого проходу. Без MSAA це звичайний alpha-cut за тим самим порогом.
	ALPHA = t.a; ALPHA_SCISSOR_THRESHOLD = cut; ALPHA_ANTIALIASING_EDGE = a2c_edge; ALPHA_TEXTURE_COORDINATE = UV * vec2(textureSize(albedo_tex, 0));
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float w = wrap * is_card;
	float d = max((ndl + w) / (1.0 + w), 0.0) + is_card * translucency * max(-ndl, 0.0);
	// Тінь сусідніх пучків на картці — лише на чверть: у справжній кроні світло проходить
	// крізь листя, а повна тінь із різким краєм малює на кроні двоколірний камуфляж.
	float att = mix(ATTENUATION, mix(0.85, 1.0, ATTENUATION), is_card);
	DIFFUSE_LIGHT += d * att * LIGHT_COLOR / PI;
}
