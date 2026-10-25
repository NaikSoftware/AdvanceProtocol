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
render_mode cull_disabled, depth_draw_opaque, skip_vertex_transform;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.5;
// Тон листя під світло карти (BattleLook.foliage_tint, ставить WeatherRig): похмуре
// синювате розсіяне світло робить буре фіолетовим, і цей множник його повертає.
global uniform vec3 foliage_tint;
// М'яке огортання світлом і просвічування: тіньовий бік пучка не чорніє, як у листя.
uniform float wrap = 0.35;
uniform float translucency = 0.15;
// Об'єм крони: місце пучка розтягується до [occlusion, 1] і йде і в колір, і в розсіяне
// світло неба (AO). Під рівним небом крона інакше — плоска аплікація одного кольору; так
// у неї світлий верх, темний низ і темні щілини між кронами, де видно нижні пучки.
uniform float occlusion = 0.45;
// Темний обідок пучка: м'який край замість різкої вирізаної лінії наліпки.
uniform float rim = 0.45;
uniform float card_round = 0.7;

varying float is_card;
varying vec3 inst_tone;
varying flat float piece_hash;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

void vertex() {
	// Чотири вершини картки лежать в одній точці, тож хеш однаковий для всього пучка.
	piece_hash = hash13(VERTEX * 97.0 + 0.5);
	// Без custom data (поодинокий MeshInstance3D) INSTANCE_CUSTOM — нулі: тон 1.
	inst_tone = dot(INSTANCE_CUSTOM.rgb, INSTANCE_CUSTOM.rgb) > 0.0 ? INSTANCE_CUSTOM.rgb : vec3(1.0);
	vec3 v = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	is_card = dot(UV2, UV2) > 0.0 ? 1.0 : 0.0;
	if (is_card > 0.5) {
		// Масштаб екземпляра по горизонталі: картка росте разом із кроною.
		float s = length(MODEL_MATRIX[0].xyz);
		v.xy += UV2 * s;
	}
	VERTEX = v;
	NORMAL = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	if (is_card > 0.5) {
		// Кути картки нахилені назовні: світло котиться по пучку, як по кулі, і крона
		// світлішає до сонця плавно, а не ступенями світлий/темний пучок.
		NORMAL = normalize(NORMAL + card_round * vec3(normalize(UV2), 0.0));
	}
}

void fragment() {
	// Зміщення mip на −0,5: ближні крони на мінімальному зумі інакше розмиті.
	vec4 t = texture(albedo_tex, UV, -0.5);
	// Тінь напрямленого світла рендериться ортографічно, а камера гри — у перспективі.
	bool shadow_pass = PROJECTION_MATRIX[3][3] > 0.5;
	// На далеких mip-рівнях тонкі гілки усереднюються з прозорим тлом і тануть під порогом:
	// голе дерево здаля лишилось би самим стовбуром. Тож поріг знижується з рівнем mip —
	// але не в тіні: там низькі mip зливали голу крону в суцільну пляму тіні.
	float lod = textureQueryLod(albedo_tex, UV).x;
	float cut = shadow_pass ? alpha_cutoff : alpha_cutoff * mix(1.0, 0.3, clamp((lod - 1.0) / 3.0, 0.0, 1.0));
	if (t.a < cut || COLOR.a < (shadow_pass ? 0.5 : 0.001) || (!shadow_pass && piece_hash > COLOR.a)) {
		discard;
	}
	vec3 tint = mix(vec3(1.0), foliage_tint, is_card);
	// Здаля дрібний малюнок пучка (листки, світлі й темні гілочки) — це шум на кілька
	// пікселів: колір плавно йде до середнього з ширшої ділянки, і крона читається масою.
	vec3 coarse = textureLod(albedo_tex, UV, lod + 2.0).rgb;
	vec3 rgb = mix(t.rgb, coarse, is_card * 0.85 * smoothstep(0.8, 2.5, lod));
	// Місце пучка в кроні (стале на картці) плюс положення точки на самій картці (UV2 —
	// зсув від центру, тайли): затінення тече по кроні плавно, а не сходинками пучків.
	float hf = clamp((COLOR.r - 0.55) / 0.45 + UV2.y * 1.3, 0.0, 1.0);
	float occ = mix(1.0, mix(occlusion, 1.0, hf), is_card);
	// Альфа сусіднього mip падає біля краю силуету пучка — там він і темніє. Здаля mip уже
	// усереднений скрізь, і обідок затемнив би всю крону, тож там він гасне.
	float edge = textureLod(albedo_tex, UV, lod + 1.0).a;
	float r = mix(1.0, mix(1.0 - rim, 1.0, smoothstep(0.35, 0.85, edge)), is_card * (1.0 - smoothstep(2.0, 3.0, lod)));
	ALBEDO = rgb * mix(COLOR.rgb, vec3(1.0), is_card) * inst_tone * tint * r;
	AO = occ;
	AO_LIGHT_AFFECT = 0.5;
	ROUGHNESS = 1.0;
	SPECULAR = 0.15;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float w = wrap * is_card;
	float d = max((ndl + w) / (1.0 + w), 0.0) + is_card * translucency * max(-ndl, 0.0);
	// Тінь сусідніх пучків на картці — лише на чверть: у справжній кроні світло проходить
	// крізь листя, а повна тінь із різким краєм малює на кроні двоколірний камуфляж.
	float att = mix(ATTENUATION, mix(0.75, 1.0, ATTENUATION), is_card);
	DIFFUSE_LIGHT += d * att * LIGHT_COLOR / PI;
}
