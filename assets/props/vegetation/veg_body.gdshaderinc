// Тіло шейдера рослинності (очерет, кущі, дерева біля води, у садибах і на луках).
// Те саме, що крона лісу (forest_crown.gdshader): пучки-картки розгортаються до камери, UV2
// несе зсув кута; UV2 = 0 — кора; alpha-to-coverage на краю пучка (потрібне MSAA).
// Додано нерухомі картки (UV2 = (1e-4, 0)): вертикальні снопи очерету й рогозу та картки, що
// лежать на землі в поваленому варіанті.
// Альфа кольору екземпляра — розчинення над юнітом: у veg.gdshader цілими пучками (як у
// лісі), у veg_fade.gdshader — справжньою прозорістю (VEG_FADE), без растру.
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

varying float is_card;
// 1 — нерухома вертикальна картка (очерет, рогіз) або картка, що лежить (повалений кущ):
// UV2 = (1e-4, 0), як у ярусів ялини. Решта карток розгортається до камери.
varying float is_fixed;
// Наскільки нерухома картка дивиться на камеру: 0 — ребром.
varying float facing;
varying flat float card_half;
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
	is_fixed = (is_card > 0.5 && length(UV2) < 1e-3) ? 1.0 : 0.0;
	facing = abs(normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz).z);
	// Півдіагональ картки (усі 4 кути однаково далекі від центру) — для градієнта пучка.
	card_half = length(UV2);
	if (is_card > 0.5 && is_fixed < 0.5) {
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
	float lod = textureQueryLod(albedo_tex, UV).x;
	float cut = shadow_pass ? alpha_cutoff : alpha_cutoff * mix(1.0, 0.3, clamp((lod - 2.5) / 2.0, 0.0, 1.0));
	// Нерухома картка ребром до камери — смуга з розмитого стебла: вона тоншає й гасне.
	cut = mix(cut, min(cut + 0.45, 0.97), is_fixed * (1.0 - smoothstep(0.12, 0.4, facing)) * float(!shadow_pass));
	// Силует — з різкого рівня: обрис пучка — дрібне листя. Розмитіший mip для порогу
	// робив із пучка кілька великих лопатей — «листки» по метру на ближньому зумі.
#ifdef VEG_FADE
	// Напівпрозора крона над юнітом: альфа екземпляра — справжня прозорість, без растру.
	if (t.a < cut || COLOR.a < (shadow_pass ? 0.5 : 0.001)) {
		discard;
	}
#else
	if ((shadow_pass && t.a < cut) || COLOR.a < (shadow_pass ? 0.5 : 0.001) || (!shadow_pass && piece_hash > COLOR.a)) {
		discard;
	}
#endif
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
	// Край пучка — alpha-to-coverage (MSAA): м'який перехід на 1–2 пікселі без растру й без
	// окремого прозорого проходу. Без MSAA це звичайний alpha-cut за тим самим порогом.
#ifdef VEG_FADE
	ALPHA = COLOR.a;
#else
	ALPHA = t.a; ALPHA_SCISSOR_THRESHOLD = cut; ALPHA_ANTIALIASING_EDGE = a2c_edge; ALPHA_TEXTURE_COORDINATE = UV * vec2(textureSize(albedo_tex, 0));
#endif
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
