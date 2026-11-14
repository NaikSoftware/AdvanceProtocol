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
// Колір лінійний, як колір вершин стрічки, тож без source_color.
uniform bool contour_on = false;
uniform sampler2D contour_edges : filter_nearest, repeat_disable;
uniform float contour_half = 0.01;
uniform float contour_lift = 0.04;
// Кільця: xy — центр, z — радіус (тайли); колір уже лінійний.
uniform int ring_count = 0;
uniform vec4 rings[4];
uniform vec4 ring_colors[4];
uniform float ring_half = 0.06;
// Рельєф (`TerrainHeight.texture()`, як у UnitContacts): точка землі під пікселем уточнюється за
// висотою в ній самій. Площина на висоті стовбура на схилі зсувала лінію на кроні від лінії на
// землі на кілька пікселів.
uniform bool use_height = false;
uniform sampler2D height_map : filter_linear, repeat_disable;
uniform float height_samples = 4.0;
uniform float height_origin = -0.5;
// Маска шару накладок (BoardView.OVERLAY_LAYER): лінія — лише для камери, що бачить накладки.
// Зонд відбиттів знімає крони (шар 1), але не накладки: у його знімку лінії активного гравця
// лишились би для наступного.
uniform int overlay_layers = 0;

#include "res://game/battle/shaders/surroundings.gdshaderinc"

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

// Вигляд кільця під кроною: колір і покриття точки землі на відстані dist від центру під кутом angle;
// fw — розмір пікселя на землі (fwidth(dist), рахує fragment). Одна функція, щоб інший вигляд
// кільця замінив лише її. Поки що — рівна лінія, як стрічка на землі.
vec4 canopy_ring(float dist, float angle, float radius, float fw, vec4 col) {
	return vec4(col.rgb, col.a * clamp((ring_half - abs(dist - radius)) / max(fw, 1e-5) + 0.5, 0.0, 1.0));
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
	if (!shadow_pass && (contour_on || ring_count > 0) && (CAMERA_VISIBLE_LAYERS & uint(overlay_layers)) != 0u) {
		vec3 eye = CAMERA_POSITION_WORLD;
		float k_ray = 1.0 / max(eye.y - world_pos.y, 1e-4);
		float gy = base_y;
		vec2 g = mix(eye.xz, world_pos.xz, (eye.y - gy - contour_lift) * k_ray);
		if (use_height) {
			// Дві ітерації: на пологому схилі похибка падає в (схил / tg нахилу камери)² раза за крок.
			vec2 hs = vec2(textureSize(height_map, 0));
			for (int it = 0; it < 2; it++) {
				gy = textureLod(height_map, ((g - height_origin) * height_samples + 0.5) / hs, 0.0).r;
				g = mix(eye.xz, world_pos.xz, (eye.y - gy - contour_lift) * k_ray);
			}
		}
		vec2 gw = max(fwidth(g), vec2(1e-5));
		// Колір із домноженою альфою: кільце під лінією зон, як на землі.
		vec3 pre = vec3(0.0);
		float cov = 0.0;
		// Кільце — лише над дошкою: ліс кільця за краєм лишається без нього.
		// Множником, а не умовою циклу: fwidth у неоднорідному розгалуженні не визначений.
		float on_board = all(greaterThanEqual(g, vec2(-0.5))) && all(lessThan(g, board_size - 0.5)) ? 1.0 : 0.0;
		for (int i = 0; i < ring_count && i < 4; i++) {
			vec2 d = g - rings[i].xy;
			float r = length(d);
			vec4 rc = canopy_ring(r, atan(d.y, d.x), rings[i].z, fwidth(r), ring_colors[i]);
			float a = on_board * rc.a;
			pre = mix(pre, rc.rgb, a);
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
		// Колода чи хмиз нижче за стрічку її не ховають: лінія на них лягла б удруге, темніша.
		float above = step(gy + contour_lift, world_pos.y);
		ALBEDO *= 1.0 - cov * above;
		SPECULAR *= 1.0 - cov * above;
		EMISSION = pre * above;
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
