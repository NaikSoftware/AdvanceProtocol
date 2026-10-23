// Суцільна земля (Phase 5a, Task 5). Вид клітинки — з kind_map; текстура виду —
// шар Texture2DArray (GroundSurface.TEX_LAYERS). Межі видів м'які й нерівні:
// позицію збурено шумом, а вага сусідніх клітинок — білінійна з вузьким переходом.
// Повтор текстури ламає «техніка 3» Іньїго Квілеса: два зсунуті й повернуті
// семпли, змішані за низькочастотним шумом.
shader_type spatial;
render_mode blend_mix, cull_back;

global uniform float weather_wetness;
global uniform float cloud_shadow_strength;
// Сила власного відбиття неба в калюжах і на мокрому березі (див. water.gdshader).
global uniform float sky_reflection_gain;

uniform sampler2D kind_map : filter_nearest, repeat_disable;
// Косметичний підтип клітинки (MapData.surface), той самий розмір, що й kind_map.
uniform sampler2D surface_map : filter_nearest, repeat_disable;
// Клітинка, що відповідає пікселю (0, 0) kind_map (від'ємна при відступі).
uniform vec2 map_origin = vec2(0.0);
// Шар текстури за (вид, підтип): індекс вид * 4 + підтип; невідомий підтип -> 0 (GroundSurface).
uniform int layer_for_surface[40];
// Властивості шарів macro_array (до 16; перші 8 — шари деталі, далі — підтипи):
// базовий шар (для правил: дорога, поле), шар деталі, тип зносу (0 нема, 1 асфальт,
// 2 ґрунтівка, 3 бруківка) вирівнювання макро (1 — за віссю дороги, 2 — без повороту, лише 0/180°: борозни стерні).
uniform int layer_base[16];
uniform int layer_detail[16];
uniform int layer_wear[16];
uniform int layer_aligned[16];
uniform sampler2DArray albedo_array : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray normal_array : filter_linear_mipmap_anisotropic, repeat_enable;
// Макро: вид зверху, один повтор = 1.5 клітинки (12 м), вміст намальовано в реальному
// розмірі (колії 0.3-0.5 м, калюжі 1-3 м). Альфа = висота. Деталь (albedo_array) —
// фото-текстури в реальному масштабі REPEAT_M: лише модуляція яскравості й нормаль
// біля камери поверх макро, колір не замінює.
uniform sampler2DArray macro_array : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
// Варіантів макро на шар: індекс шару в macro_array = layer * macro_variants + variant.
uniform int macro_variants = 1;
uniform float mud_amount = 0.0;

// Шари з GroundSurface.TEX_LAYERS.
const int ROAD = 0;
const int FIELD = 1;
const int HILL = 3;
const int FOREST = 2;
const int MUD = 5;
// Шар берега (русла) — під WATER, BRIDGE і BRIDGE_DESTROYED (GroundSurface.TEX_LAYER_FOR_KIND).
const int BANK = 7;
// Колір піску коси.
const vec3 SAND_TINT = vec3(3.1, 2.6, 1.8);

// Підсилення альбедо шару: лісова підстилка з Task 4 майже чорна (середнє 55
// проти 75 у поля), а під деревами вона мусить читатись як бура листва.
vec3 layer_gain(int layer) {
	return layer == FOREST ? vec3(1.45, 1.35, 1.2) : vec3(1.0);
}

// Реальний розмір, який покриває ОДИН повтор ДЕТАЛЬНОЇ текстури, у метрах (клітинка
// = 8 м) — за шарами GroundSurface.TEX_LAYERS: road, field, forest, hill, marsh, mud,
// rubble, bank. Міряно по самих текстурах (1024 px): камінь бану ~25 px -> 3 см => 1.5 м;
// цеглина щебню ~40-100 px -> 20-40 см => 3.5 м; колія багна ~80 px => 3.5 м;
// трава/підстилка 4-8 см => 1.5-2 м; асфальт 2.5 м. Значення — GroundSurface.REPEAT_M.
uniform float repeat_m[8];
// Глибина рельєфу шару, метри (альфа макро = висота 0..1): трава кілька см,
// колії й щебінь ~10 см. relief_scale > 1 — лише для огляду, у грі 1.
// Значення — GroundSurface.RELIEF_M.
uniform float relief_m[16];
uniform float relief_scale = 1.0;
// Паралакс лише біля камери (відстань у клітинках до фрагмента): на MIN zoom
// (камера далі ~26) гілка не виконується зовсім.
uniform float pom_fade_start = 12.0;
uniform float pom_fade_end = 20.0;
// Деталь (яскравість, нормаль) повна ближче 10 клітинок і зникає до 16.
uniform float detail_fade_start = 10.0;
uniform float detail_fade_end = 16.0;
// Сила модуляції яскравості деталлю навколо середнього (1 = на повну амплітуду текстури).
uniform float detail_gain = 0.8;
const int POM_STEPS = 8;
const float METRES_PER_TILE = 8.0;
// Клітинок на один повтор макро-текстури (512 px = 12 м).
const float MACRO_TILES = 1.5;

varying vec3 world_pos;

#include "res://game/battle/shaders/terrain_noise.gdshaderinc"

int layer_at(ivec2 px, ivec2 size) {
	ivec2 c = clamp(px, ivec2(0), size - 1);
	int kind = int(texelFetch(kind_map, c, 0).r * 255.0 + 0.5);
	int surf = int(texelFetch(surface_map, c, 0).r * 255.0 + 0.5);
	return layer_for_surface[clamp(kind, 0, 9) * 4 + clamp(surf, 0, 3)];
}

// 1 — клітинка пікселя kind_map є дорогою (будь-який підтип).
float road_cell(ivec2 px, ivec2 size) {
	return layer_base[layer_at(px, size)] == ROAD ? 1.0 : 0.0;
}

// 1 — клітинка дорога з сусідами ROAD лише по одній осі (не кут, не розвилка, не глухий кут).
float straight_cell(ivec2 px, ivec2 size) {
	if (road_cell(px, size) < 0.5) {
		return 0.0;
	}
	float h = road_cell(px + ivec2(1, 0), size) + road_cell(px - ivec2(1, 0), size);
	float v = road_cell(px + ivec2(0, 1), size) + road_cell(px - ivec2(0, 1), size);
	return ((h >= 1.0 && v == 0.0) || (v >= 1.0 && h == 0.0)) ? 1.0 : 0.0;
}

// Гекс-тайлінг (Мікельсен / Хейц-Нейрі): три вершини трикутної сітки з барицентричними
// вагами; у кожної вершини свій випадковий зсув і поворот UV. Ґратку повтору ламає
// кожна комірка, а не лише повільний шум.
void hex_grid(vec2 uv, out vec2 id[3], out vec3 w) {
	vec2 sk = vec2(uv.x - 0.57735027 * uv.y, 1.15470054 * uv.y) * 3.4641016;
	vec2 base = floor(sk);
	vec3 t = vec3(fract(sk), 0.0);
	t.z = 1.0 - t.x - t.y;
	if (t.z > 0.0) {
		w = vec3(t.z, t.y, t.x);
		id[0] = base;
		id[1] = base + vec2(0.0, 1.0);
		id[2] = base + vec2(1.0, 0.0);
	} else {
		w = vec3(-t.z, 1.0 - t.y, 1.0 - t.x);
		id[0] = base + vec2(1.0, 1.0);
		id[1] = base + vec2(1.0, 0.0);
		id[2] = base + vec2(0.0, 1.0);
	}
}

// quarter — поворот лише кратний 90° (напрямні колії/тріщини не мають розвертатись довільно).
// forced >= 0 — кут осі дороги: поворот лише 0/180° від нього (baked колії йдуть за дорогою).
void hex_rand(vec2 id, float salt, bool quarter, float forced, out vec2 off, out mat2 r) {
	off = vec2(hash12(id + salt * 13.1), hash12(id + 7.7 + salt * 5.3)) * 8.0;
	float a = hash12(id + 3.3 + salt * 2.9) * 6.2831853;
	if (forced >= 0.0) {
		a = forced + floor(a / 3.1415927) * 3.1415927;
	} else if (quarter) {
		a = floor(a / 1.5707963) * 1.5707963;
	}
	r = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a)));
}

// Один шар: макро (гекс, 3 семпли, паралакс по висоті макро) + деталь біля камери.
// pom_w — зсув у світі на повну глибину (0 — паралаксу нема). Виходи: колір, нахил
// нормалі, висота (відносно середньої шару, 0.5 = середня) і каверна (1 = відкрито).
void sample_layer(int layer, vec2 p, vec2 dpx, vec2 dpy, vec2 pom_w, float dfade, float axis_a, out vec3 alb, out vec2 nxy, out float hgt, out float cav) {
	float fl = float(layer);
	vec2 muv = p / MACRO_TILES;
	vec2 mdx = dpx / MACRO_TILES;
	vec2 mdy = dpy / MACRO_TILES;
	vec2 id[3];
	vec3 w;
	hex_grid(muv, id, w);
	vec2 off[3];
	mat2 rot[3];
	float mlay[3];
	vec4 mmv[3];
	for (int i = 0; i < 3; i++) {
		hex_rand(id[i], fl, layer_base[layer] == ROAD || layer_base[layer] == FIELD, layer_aligned[layer] == 1 ? axis_a : (layer_aligned[layer] == 2 ? 0.0 : -1.0), off[i], rot[i]);
		// Варіант текстури шару — з хешу комірки; середнє кожного варіанта окреме,
		// бо контраст-зберігаюче змішування віднімає власне середнє семпла.
		float var_f = min(floor(hash12(id[i] + fl * 3.7 + 91.3) * float(macro_variants)), float(macro_variants - 1));
		mlay[i] = fl * float(macro_variants) + var_f;
		mmv[i] = textureLod(macro_array, vec3(0.5, 0.5, mlay[i]), 14.0);
	}
	vec4 mm = w.x * mmv[0] + w.y * mmv[1] + w.z * mmv[2];
	// Змішування зі збереженням контрасту: відхили від середнього, ділені на sqrt(sum w^2).
	float inv_n = inversesqrt(dot(w, w));
	float hit = 0.0;
	vec2 mshift = pom_w / MACRO_TILES;
	if (dot(pom_w, pom_w) > 0.0) {
		// Лінійний пошук променя вниз крізь висоту макро + одне лінійне уточнення.
		float prev_h = 1.0;
		float prev_t = 0.0;
		hit = 1.0;
		for (int s = 1; s <= POM_STEPS; s++) {
			float tt = float(s) / float(POM_STEPS);
			float dh = 0.0;
			for (int i = 0; i < 3; i++) {
				dh += w[i] * (textureGrad(macro_array, vec3(rot[i] * (muv + mshift * tt) + off[i], mlay[i]), rot[i] * mdx, rot[i] * mdy).a - mmv[i].a);
			}
			float hh = clamp(mm.a + dh * inv_n, 0.0, 1.0);
			if (hh >= 1.0 - tt) {
				// Обидві різниці <= 0 (промінь ще над поверхнею / вже під нею).
				float d0 = (1.0 - prev_t) - prev_h;
				float d1 = hh - (1.0 - tt);
				hit = mix(prev_t, tt, d0 / max(d0 + d1, 1e-4));
				break;
			}
			prev_h = hh;
			prev_t = tt;
		}
	}
	vec2 shift = pom_w * hit;
	vec2 sp = muv + shift / MACRO_TILES;
	vec4 acc = vec4(0.0);
	for (int i = 0; i < 3; i++) {
		acc += w[i] * (textureGrad(macro_array, vec3(rot[i] * sp + off[i], mlay[i]), rot[i] * mdx, rot[i] * mdy) - mmv[i]);
	}
	vec4 m4 = clamp(mm + acc * inv_n, 0.0, 1.0);
	alb = m4.rgb * layer_gain(layer_base[layer]);
	float h = m4.a;
	nxy = vec2(0.0);

	// Деталь: тільки поки піксель досить великий для повтору й камера близько.
	int dl = layer_detail[layer];
	float dfl = float(dl);
	float tpr = repeat_m[dl] / METRES_PER_TILE;
	float px_m = max(length(dpx), length(dpy));
	float keep = smoothstep(6.0, 40.0, tpr / max(px_m, 1e-5)) * dfade;
	if (keep > 0.01) {
		vec4 dm = textureLod(albedo_array, vec3(0.5, 0.5, dfl), 14.0);
		vec2 duv = (p + shift) / tpr;
		vec2 ddx = dpx / tpr;
		vec2 ddy = dpy / tpr;
		vec2 did[3];
		vec3 dw;
		hex_grid(duv, did, dw);
		float dinv = inversesqrt(dot(dw, dw));
		vec4 dacc = vec4(0.0);
		vec2 nacc = vec2(0.0);
		for (int i = 0; i < 3; i++) {
			vec2 o;
			mat2 r;
			hex_rand(did[i], dfl + 17.0, false, -1.0, o, r);
			vec3 c = vec3(r * duv + o, dfl);
			dacc += dw[i] * (textureGrad(albedo_array, c, r * ddx, r * ddy) - dm);
			// Нормаль повертаємо назад у простір меша (r, не transpose(r): бінормаль
			// PlaneMesh дивиться в −Z, а v росте в +Z).
			nacc += dw[i] * (r * (textureGrad(normal_array, c, r * ddx, r * ddy).rg * 2.0 - 1.0));
		}
		vec4 d4 = dm + dacc * dinv;
		float lm = max(dot(dm.rgb, vec3(0.299, 0.587, 0.114)), 0.05);
		float ld = dot(d4.rgb, vec3(0.299, 0.587, 0.114));
		alb *= clamp(1.0 + detail_gain * keep * (ld - lm) / lm, 0.3, 2.0);
		h += (d4.a - dm.a) * 0.35 * keep;
		nxy = nacc * dinv * keep;
	}
	// Висота відносно середньої шару: шари з різною середньою висотою змагаються чесно,
	// а каверна темнить лише те, що нижче середнього (інакше багно чорніє).
	float dev = h - mm.a;
	hgt = 0.5 + dev;
	cav = 1.0 - 0.45 * clamp(-dev * 2.5, 0.0, 1.0);
}

// Рельєф (TerrainHeight): R — висота землі у світі, G — маска води (для мокрого берега), B — кривизна.
// Піксель (i, j) лежить у вершині сітки меша: PlaneMesh підрозділено рівно під відліки,
// тож висота — texelFetch без фільтрації, а нормаль — скінченні різниці сусідніх відліків.
uniform bool use_height = false;
uniform sampler2D height_map : filter_linear, repeat_disable;
uniform float height_samples = 4.0;
// Рівень води (TerrainHeight.WATER_LEVEL) для мокрого берега.
uniform float water_level = -0.05;
varying float shore_mask;
varying float curvature;
varying float bar_mask;
varying float hill_shade;
varying float slope_tan;
// Напрямок НА сонце (DirectionalLight3D сцени бою): запечене світло-тінь рельєфу, §8.
const vec3 SUN_DIR = vec3(0.5, 0.7, 0.5);

float height_px(ivec2 px, ivec2 hs) {
	return texelFetch(height_map, clamp(px, ivec2(0), hs - 1), 0).r;
}

void vertex() {
	if (use_height) {
		ivec2 hs = textureSize(height_map, 0);
		vec2 half_size = vec2(hs - 1) / (2.0 * height_samples);
		ivec2 px = ivec2(floor((VERTEX.xz + half_size) * height_samples + 0.5));
		float e = 1.0 / height_samples;
		VERTEX.y = height_px(px, hs);
		vec3 n = normalize(vec3(
				height_px(px - ivec2(1, 0), hs) - height_px(px + ivec2(1, 0), hs),
				2.0 * e,
				height_px(px - ivec2(0, 1), hs) - height_px(px + ivec2(0, 1), hs)));
		NORMAL = n;
		// Та сама умовність, що в PlaneMesh: тангент уздовж +X, бінормаль = n x t (дивиться в -Z).
		vec3 t = normalize(vec3(1.0, (height_px(px + ivec2(1, 0), hs) - height_px(px - ivec2(1, 0), hs)) / (2.0 * e), 0.0));
		TANGENT = t;
		BINORMAL = normalize(cross(n, t));
		vec4 hm = texelFetch(height_map, clamp(px, ivec2(0), hs - 1), 0);
		shore_mask = hm.g;
		curvature = hm.b;
		bar_mask = hm.a;
		hill_shade = dot(n, normalize(SUN_DIR)) - normalize(SUN_DIR).y;
		slope_tan = length(n.xz) / max(n.y, 0.01);
	} else {
		shore_mask = 0.0;
		curvature = 0.0;
		bar_mask = 0.0;
		hill_shade = 0.0;
		slope_tan = 0.0;
	}
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	vec2 q = border_warp(p);
	vec2 g = q - map_origin;
	vec2 base = floor(g);
	vec2 fw = border_weights(fract(g));
	ivec2 size = textureSize(kind_map, 0);
	ivec2 b = ivec2(base);

	int L[5];
	float W[5];
	L[0] = layer_at(b, size);
	L[1] = layer_at(b + ivec2(1, 0), size);
	L[2] = layer_at(b + ivec2(0, 1), size);
	L[3] = layer_at(b + ivec2(1, 1), size);
	// З рельєфом берег малює висота, а не клітинка: клітинки води лишаються полем, інакше
	// межі клітинок проступали б прямокутними плямами берега.
	if (use_height) {
		for (int i = 0; i < 4; i++) {
			L[i] = layer_base[L[i]] == BANK ? FIELD : L[i];
		}
	}
	W[0] = (1.0 - fw.x) * (1.0 - fw.y);
	W[1] = fw.x * (1.0 - fw.y);
	W[2] = (1.0 - fw.x) * fw.y;
	W[3] = fw.x * fw.y;

	// Багно: поле й пагорб під станом MUD (плямами, не суцільно) і узбіччя доріг.
	float road_w = 0.0;
	float soil_w = 0.0;
	// Вага води — та сама, що в масці water.gdshader (уріз на 0.5).
	float bank_w = 0.0;
	for (int i = 0; i < 4; i++) {
		int bl = layer_base[L[i]];
		road_w += bl == ROAD ? W[i] : 0.0;
		bank_w += bl == BANK ? W[i] : 0.0;
		soil_w += (bl == FIELD || bl == HILL) ? W[i] : 0.0;
	}
	// Плями, а не напівпрозорий шар: півпрозоре багно поверх трави читається як
	// «привид» текстури, а не як розкисла земля.
	// mud_amount — частка поля під багном далеко від доріг; біля дороги — на 0.2
	// більше. Поріг — квантиль fbm (0.45 ≈ 30 %, 0.537 ≈ 55 %), виміряний на карті.
	float near = 0.0;
	near += layer_base[layer_at(ivec2(floor(g + vec2(1.5, 0.0) + 0.5)), size)] == ROAD ? 0.25 : 0.0;
	near += layer_base[layer_at(ivec2(floor(g - vec2(1.5, 0.0) + 0.5)), size)] == ROAD ? 0.25 : 0.0;
	near += layer_base[layer_at(ivec2(floor(g + vec2(0.0, 1.5) + 0.5)), size)] == ROAD ? 0.25 : 0.0;
	near += layer_base[layer_at(ivec2(floor(g - vec2(0.0, 1.5) + 0.5)), size)] == ROAD ? 0.25 : 0.0;
	near = max(near, road_w);
	float cover = mud_amount + 0.2 * near;
	float thr = 0.45 + (cover - 0.3) * 0.35;
	float mud_soil = mud_amount > 0.0
			? 1.0 - smoothstep(thr - 0.02, thr + 0.02, fbm(p * 0.35 + 3.1))
			: 0.0;
	float verge = 4.0 * road_w * (1.0 - road_w) * 0.7;
	for (int i = 0; i < 4; i++) {
		if (layer_base[L[i]] == FIELD || layer_base[L[i]] == HILL) {
			W[i] *= 1.0 - mud_soil;
		}
		if (layer_base[L[i]] != ROAD) {
			W[i] *= 1.0 - verge;
		}
	}
	L[4] = MUD;
	W[4] = soil_w * mud_soil + verge * (1.0 - road_w);

	// Однакові шари сусідів семплюємо один раз.
	for (int i = 1; i < 5; i++) {
		for (int j = 0; j < i; j++) {
			if (L[i] == L[j] && W[j] > 0.0) {
				W[j] += W[i];
				W[i] = 0.0;
			}
		}
	}

	vec2 dpx = dFdx(p);
	vec2 dpy = dFdy(p);
	// Паралакс: промінь від камери; глибина згасає з відстанню до нуля.
	vec3 view = CAMERA_POSITION_WORLD - world_pos;
	float cam_dist = length(view);
	float pom_fade = 1.0 - smoothstep(pom_fade_start, pom_fade_end, cam_dist);
	vec2 pom_dir = -view.xz / max(view.y, 0.2);
	float detail_fade = 1.0 - smoothstep(detail_fade_start, detail_fade_end, cam_dist);
	// Вісь дороги в клітинці (центри клітинок — цілі p): за сусідами ROAD по X й по Y.
	vec2 pc = floor(p + 0.5);
	ivec2 ci = ivec2(pc - map_origin);
	float he = road_cell(ci + ivec2(1, 0), size) + road_cell(ci - ivec2(1, 0), size);
	float ve = road_cell(ci + ivec2(0, 1), size) + road_cell(ci - ivec2(0, 1), size);
	bool along_x = he >= ve;
	// Кут, що кладе вертикальні (вздовж v) baked колії вздовж осі дороги.
	float axis_a = along_x ? 1.5707963 : 0.0;
	vec3 A[5];
	vec2 N[5];
	float H[5];
	float Hgt[5];
	float Cav[5];
	float hmax = -1.0;
	for (int i = 0; i < 5; i++) {
		H[i] = -1.0;
		if (W[i] > 0.002) {
			// Глибина в одиницях світу (1 м = 0.125), потім у UV шару.
			vec2 pom = pom_fade > 0.01
					? pom_dir * (relief_m[L[i]] * relief_scale * pom_fade / METRES_PER_TILE)
					: vec2(0.0);
			sample_layer(L[i], p, dpx, dpy, pom, detail_fade, axis_a, A[i], N[i], Hgt[i], Cav[i]);
			// Висотне змішування: на межі першим проступає те, що вище в самій
			// карті висот (камінь, кому, пучок), тож перехід рваний, а не розмитий.
			H[i] = W[i] + Hgt[i] * 0.45;
			hmax = max(hmax, H[i]);
		}
	}
	vec3 alb = vec3(0.0);
	vec2 nxy = vec2(0.0);
	float rough = 0.0;
	float cav = 0.0;
	float wsum = 0.0;
	vec3 wk = vec3(0.0);
	for (int i = 0; i < 5; i++) {
		float w = max(H[i] - (hmax - 0.18), 0.0);
		if (w > 0.0) {
			alb += A[i] * w;
			nxy += N[i] * w;
			rough += (layer_base[L[i]] == ROAD ? 0.75 : 0.92) * w;
			int wt = layer_wear[L[i]];
			wk += (wt == 1 ? vec3(w, 0.0, 0.0) : (wt == 2 ? vec3(0.0, w, 0.0) : (wt == 3 ? vec3(0.0, 0.0, w) : vec3(0.0))));
			// Каверна: низини карти висот темніші (щілини між каменями, дно колії).
			cav += Cav[i] * w;
			wsum += w;
		}
	}
	alb /= wsum;
	nxy /= wsum;
	rough /= wsum;
	cav /= wsum;
	wk /= wsum;
	alb *= cav;
	// Запечене затінення рельєфу (TerrainHeight, B): низини й русло темніші, горби світліші.
	alb *= 1.0 + (curvature > 0.0 ? 0.2 : 0.2) * curvature;
	// Запечене світло-тінь: 10° схил міняє яскравість на ~15 рівнів, на далекій відстані слабшає.
	alb *= 1.0 + clamp(9.0 * hill_shade, -0.4, 0.55) * (1.0 - 0.4 * smoothstep(25.0, 45.0, cam_dist));
	// Макро-варіація 20-50 м (fbm ~ 1/0.2 клітинки = 40 м): ламає повтор тону,
	// не міняючи масштаб дрібниць.
	float macro = fbm(p * 0.2 + 41.0) - 0.5;
	alb *= vec3(1.0 + 0.16 * macro, 1.0 + 0.13 * macro, 1.0 + 0.06 * macro);
	// З рельєфом пляма альбедо не перекриває хвилі землі: розкид яскравості стиснуто на ~45 %.
	if (use_height) {
		float l0 = max(dot(alb, vec3(0.299, 0.587, 0.114)), 0.004);
		alb *= pow(l0 / 0.05, -0.45);
	}

	// Рельєф: стрімкий схил — голий ґрунт і камінь (шар HILL), а не трава; берег між урізом і
	// верхом — мокрий мул і галька (шар BANK), темніший за траву над ним. Змішування за
	// схилом і висотою, а не за клітинкою.
	vec3 alb_field = alb;
	float bar_w = 0.0;
	float bank_amt = 0.0;
	if (use_height) {
		// Крутий схил: справжній трипланар на нерухомих світових площинах XY і ZY, вага |n.x|^4
		// і |n.z|^4, без повороту (проєкція вздовж схилу давала «відбитки пальців» на обривах).
		vec3 wn = normalize(mat3(INV_VIEW_MATRIX) * NORMAL);
		// bar_mask = 0.5 + 0.5 * bend: -1 коса (внутрішній), +1 підмитий берег (зовнішній).
		float bend_s = bar_mask * 2.0 - 1.0;
		float steep = smoothstep(0.5, 0.8, slope_tan);
		float tx = pow(abs(wn.x), 4.0);
		float tz = pow(abs(wn.z), 4.0);
		float tn = max(tx + tz, 1e-4);
		vec2 pxy = world_pos.xy;
		vec2 pzy = world_pos.zy;
		vec2 dxy_x = dFdx(pxy);
		vec2 dxy_y = dFdy(pxy);
		vec2 dzy_x = dFdx(pzy);
		vec2 dzy_y = dFdy(pzy);
		float slope_amt = smoothstep(0.30, 0.46, slope_tan + 0.08 * (fbm(p * 1.3) - 0.5)) * (1.0 - road_w);
		// Річковий берег не тягне щебінь пагорба: його тип дає вигин русла (нижче).
		slope_amt *= 1.0 - smoothstep(0.02, 0.25, shore_mask);
		bank_amt = smoothstep(0.08, 0.55, shore_mask + 0.2 * (fbm(p * 2.1 + 7.0) - 0.5));
		if (slope_amt > 0.01) {
			vec3 ra; vec2 rn; float rh; float rc;
			sample_layer(HILL, p, dpx, dpy, vec2(0.0), detail_fade, axis_a, ra, rn, rh, rc);
			if (steep > 0.01) {
				vec3 sa; vec2 sn; float sh; float sc;
				vec3 sb; float sd;
				sample_layer(HILL, pxy, dxy_x, dxy_y, vec2(0.0), detail_fade, axis_a, sa, sn, sh, sc);
				sample_layer(HILL, pzy, dzy_x, dzy_y, vec2(0.0), detail_fade, axis_a, sb, sn, sh, sd);
				ra = mix(ra, (sa * tz + sb * tx) / tn, steep);
				rc = mix(rc, (sc * tz + sd * tx) / tn, steep);
			}
			alb = mix(alb, ra * rc, slope_amt);
		}
		if (bank_amt > 0.01) {
			vec3 ba; vec2 bn; float bh; float bc;
			sample_layer(BANK, p, dpx, dpy, vec2(0.0), detail_fade, axis_a, ba, bn, bh, bc);
			if (steep > 0.01) {
				vec3 sa; vec2 sn; float sh; float sc;
				vec3 sb; float sd;
				sample_layer(BANK, pxy, dxy_x, dxy_y, vec2(0.0), detail_fade, axis_a, sa, sn, sh, sc);
				sample_layer(BANK, pzy, dzy_x, dzy_y, vec2(0.0), detail_fade, axis_a, sb, sn, sh, sd);
				ba = mix(ba, (sa * tz + sb * tx) / tn, steep);
				bc = mix(bc, (sc * tz + sd * tx) / tn, steep);
			}
			float above_b = (world_pos.y - water_level) / 0.125;
			float contact = 1.0 - smoothstep(0.0, 0.7, above_b);
			vec3 lw = vec3(0.299, 0.587, 0.114);
			float fl = max(dot(alb, lw), 0.004);
			// Тип берега — з вигину русла: ґрунт лише на зовнішній стороні повороту (підмив), смугою,
			// що гуляє 0-2 м із хвилею ~20 м; на плесах і косах — низька трава й солома до води.
			float outer = max(bend_s, 0.0);
			float band = smoothstep(0.25, 0.75, fbm(p * 0.35 + 13.0));
			float cut_amt = smoothstep(0.2, 0.7, outer) * band;
			// Ґрунт грані: L* 22-32, тепло-бурий; текстура лише дає дрібну пістрявість.
			float bl = max(dot(ba * bc, lw), 0.004);
			// Не бежева глина: темніше й зеленіше (у тон воротника), із дрібною пістрявістю.
			vec3 soil = fl * 0.7 * vec3(1.3, 1.0, 0.7) * clamp(bl / 0.05, 0.75, 1.2) * bc * (0.8 + 0.4 * vnoise(p * 14.0));
			alb = mix(alb, soil * (1.0 - 0.3 * contact), bank_amt * cut_amt);
			// Воротнік із соломи: ширина 0.05-0.4 клітинки, гуляє шумом, росте на внутрішніх
			// вигинах і зникає на підмитих берегах.
			float thr = mix(0.1, 0.85, smoothstep(0.2, 0.8, fbm(p * 0.45 + 3.0))) - 0.3 * max(-bend_s, 0.0) + 0.4 * outer;
			// Маска 0.2-0.4 клітинки рве воротник, щоб він не йшов рівною стрічкою.
			float collar_break = smoothstep(0.25, 0.6, fbm(p * 3.0 + 21.0));
			float straw = smoothstep(thr, thr + 0.35, shore_mask) * (1.0 - cut_amt) * collar_break;
			alb = mix(alb, alb * vec3(1.12, 1.05, 0.8), straw * 0.6);
			// Біле на березі читається як відблиск: стеля ~L* 55 (Y ~ 0.1).
			float lc = dot(alb, lw);
			alb *= mix(1.0, min(1.0, 0.1 / max(lc, 1e-4)), bank_amt);
			// Земля, мул і мокрий ґрунт шорсткі: сухим не нижче 0.75, мокра смуга — не глянець.
			rough = mix(rough, mix(0.9, 0.75, contact), bank_amt);
		}
		// Коса — півмісяць: верхній край гуляє шумом, до води — перехід від сухого до мокрого.
		bar_w = clamp(max(-bend_s, 0.0) * 3.0, 0.0, 1.0) * smoothstep(0.05 + 0.35 * fbm(p * 1.1 + 31.0), 0.5 + 0.2 * fbm(p * 1.1 + 31.0), shore_mask);
		// Дрібна нормаль не лягає на обриви: проєкція текстури плоска, а не вздовж схилу.
		nxy *= 1.0 - 0.8 * max(slope_amt, bank_amt);
	}

	// Знос дороги: дві колії вздовж осі (лише ROAD), у центрі смуга. Кути й розвилки
	// гасять колії, інтенсивність гуляє вздовж дороги низькочастотним шумом.
	float wear = 0.0;
	float wear_fade = 1.0 - smoothstep(14.0, 24.0, cam_dist);
	float road_mask = smoothstep(0.6, 0.95, road_w);
	if (road_mask > 0.0 && wear_fade > 0.0 && (wk.x + wk.y + wk.z) > 0.0) {
		vec2 u = p - pc;
		float cross_t = along_x ? u.y : u.x;
		float along_t = along_x ? u.x : u.y;
		float a_pos = along_x ? p.x : p.y;
		// Колії ~0.7 м завширшки на 1.8 м одна від одної (клітинка = 8 м).
		float dpath = abs(abs(cross_t) - 0.1125);
		float paths = 1.0 - smoothstep(0.034, 0.056, dpath);
		float strip = 1.0 - smoothstep(0.03, 0.05, abs(cross_t));
		// Пряма клітинка: сусіди ROAD лише вздовж осі. Біля межі з кутом знос гасне.
		ivec2 step_a = along_x ? ivec2(1, 0) : ivec2(0, 1);
		ivec2 nci = ci + step_a * (along_t >= 0.0 ? 1 : -1);
		float fc = straight_cell(ci, size);
		float fn = straight_cell(nci, size);
		float straight = mix(fc, min(fc, fn), smoothstep(0.1, 0.5, abs(along_t)));
		float inten = mix(0.25, 1.0, smoothstep(0.35, 0.65, fbm(vec2(a_pos * 0.22, dot(pc, vec2(0.37, 0.91)) * 0.5 + 9.0))));
		float k = road_mask * wear_fade * straight * inten;
		wear = paths * k;
		strip *= k;
		alb *= 1.0 - wear * (0.22 * wk.x + 0.34 * wk.y + 0.2 * wk.z);
		rough -= wear * (0.12 * wk.x + 0.05 * wk.y + 0.12 * wk.z);
		// Ґрунтівка: піднятий травʼяно-жвавий центр між коліями.
		float speck = hash12(floor(p * 90.0));
		vec3 grass = vec3(0.045, 0.055, 0.022) * (0.75 + 0.5 * vnoise(p * 6.0));
		alb = mix(alb, grass * (0.8 + 0.5 * speck), 0.55 * strip * wk.y);
	}

	// Мокрість: темніше й глянцевіше. Калюжі — у низинах дороги й багна,
	// низина — темна ділянка текстури, тож край калюжі йде за рельєфом.
	float wet = clamp(weather_wetness, 0.0, 1.0);
	float lum = dot(alb, vec3(0.299, 0.587, 0.114));
	alb *= mix(1.0, 0.75, wet);
	// Мокрий асфальт глянцевіший за мокру землю: чим більше дороги під пікселем, тим нижче шорсткість.
	rough = mix(rough, mix(0.4, 0.22, road_w), wet);
	float puddle_ground = clamp((road_w + W[4]) * 1.5, 0.0, 1.0);
	float pn = fbm(p * 0.35 + 11.0) + (lum - 0.25) * 0.35;
	float pthr = wet * 0.42;
	float puddle = (1.0 - smoothstep(pthr - 0.03, pthr + 0.02, pn)) * puddle_ground;
	// Калюжі в коліях ґрунтівки, коли мокро (плямами, не суцільною смугою).
	puddle = max(puddle, wet * wear * wk.y * (1.0 - smoothstep(0.3, 0.55, fbm(p * 1.3 + 5.0))));
	alb *= mix(1.0, 0.55, puddle);
	// Мокра смуга берега: вага води росте ~3.4 на клітинку біля урізу (0.5), тож
	// 0.1 -> 0.5 — це ~1 м суші перед водою; найтемніша й найглянцевіша при воді.
	// З рельєфом смуга йде за ґрунтом, а не за клітинкою: мокре там, де земля в межах 0.4 м
	// над рівнем води й поруч є вода (маска води з карти висот).
	float shore = smoothstep(0.1, 0.45, bank_w);
	if (use_height) {
		float above_m = (world_pos.y - water_level) / 0.125;
		// Смуга — за горизонталлю (висота / тангенс схилу): 0.2-0.5 м упоперек і на косі, і на обриві.
		float run_m = above_m / max(slope_tan, 0.05);
		shore = (1.0 - smoothstep(0.2, 0.5, run_m)) * smoothstep(0.03, 0.12, shore_mask);
	}
	alb *= mix(1.0, 0.6, shore);
	// Темна мокра лінія просто в урізі (2-4 px на близькому зумі), а не лише розмита смуга.
	if (use_height) {
		float edge_m = (world_pos.y - water_level) / 0.125 / max(slope_tan, 0.05);
		alb *= mix(1.0, 0.65, (1.0 - smoothstep(0.04, 0.14, edge_m)) * smoothstep(0.03, 0.12, shore_mask));
	}
	// Мокрий берег не дзеркало: шорсткість лише до 0.5.
	rough = mix(rough, 0.5, shore);
	// Гладка калюжа відбиває зонд BoardView звичайним шляхом освітлення — без SSR.
	// Дощ на ній — ті самі кола, що й на річці. Підлога шорсткості 0.12: на 0.05
	// сонце на брижі давало однопіксельні іскри.
	float rv = puddle > 0.0 ? ripple_visibility(p) : 0.0;
	vec2 ripple = puddle > 0.0 ? rain_ripples(p, TIME) * 1.2 * wet * rv : vec2(0.0);
	rough = mix(rough, 0.12 + 0.1 * wet * (1.0 - rv), puddle);
	nxy = mix(nxy, ripple, puddle);
	float mirror = max(puddle, shore * 0.12);
	vec3 refl = mirror > 0.0 && sky_reflection_gain > 0.0
			? overcast_reflection(slope_to_world(ripple), normalize(CAMERA_POSITION_WORLD - world_pos), 0.03, 3.0, TIME)
			: vec3(0.0);

	// Коса (внутрішній берег повороту) — останнім, від яскравості поля поруч (з тією ж мокрістю):
	// світліша й тепліша за поле, а не лише менш темна, ніж берег.
	if (bar_w > 0.0) {
		// Тон ближчий до воротника (менш бежевий), із пістрявістю: рівна пляма читалась глиною.
		vec3 sand = dot(alb_field, vec3(0.299, 0.587, 0.114)) * mix(1.0, 0.75, wet) * mix(SAND_TINT, vec3(1.12, 1.05, 0.8), 0.5) * (1.0 - 0.2 * shore_mask);
		sand *= 0.78 + 0.44 * vnoise(p * 13.0) + 0.1 * (vnoise(p * 41.0) - 0.5);
		alb = mix(alb, sand, bar_w * 0.85);
	}

	if (cloud_shadow_strength > 0.0) {
		float cloud = smoothstep(0.45, 0.7, fbm(p * 0.04 + TIME * vec2(0.02, 0.008)));
		alb *= 1.0 - cloud_shadow_strength * cloud;
	}

	ALBEDO = alb;
	EMISSION = refl * mirror * sky_reflection_gain;
	ROUGHNESS = rough;
	SPECULAR = mix(0.5, 0.2, bank_amt);
	NORMAL_MAP = vec3(nxy * 0.5 + 0.5, 1.0);
}
