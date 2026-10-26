// Суцільна земля. Вигляд не знає про сітку: покриття — класи з карт класів (згладжена
// білінійна інтерполяція + повернутий шум зсуву у двох масштабах), дорога — власна
// геометрія з поля RoadCourse (відстань, вісь, уздовж), колії й край — у координатах дороги.
// Повтор текстури ламає гекс-тайлінг: у кожної комірки свій зсув і поворот.
shader_type spatial;
render_mode blend_mix, cull_back;

global uniform float weather_wetness;
global uniform float cloud_shadow_strength;
// Сила власного відбиття неба в калюжах і на мокрому березі (див. water.gdshader).
global uniform float sky_reflection_gain;
// Тон трави й листя за порою року (`BattleLook.foliage_tint`); дорогу не зачіпає.
global uniform vec3 foliage_tint;
// Каламутність стоячої води під ясним небом (як у water.gdshader): вікна болота не блакитні.
global uniform float water_murk;

// Карти класів покриття (GroundSurface._set_classes): піксель — клітинка (з відступом), канал —
// слот класу; class_layer — шар macro_array кожного слоту.
uniform sampler2D class_map0 : filter_linear, repeat_disable;
uniform sampler2D class_map1 : filter_linear, repeat_disable;
uniform int class_layer[8];
// Рілля — прямокутні поля (GroundSurface.plough_fields): у карті класів клітинки поля — лука,
// а рілля лягає поверх клітинок поля з прямим краєм. plough_map — номер поля + 1 у кожній
// клітинці (0 — не рілля), plough_axis — 1, коли довгий бік поля вздовж z (борозни
// повертаються на 90°).
uniform sampler2D plough_map : filter_nearest, repeat_disable;
uniform int plough_axis[64];
// Додатковий відступ кожного боку поля (клітинки: -x, -y, +x, +y) від дороги, що підходить до
// нього (GroundSurface: між краєм поля й дорогою — 1–2 м трави). Бік лишається прямим.
uniform vec4 plough_inset[64];
// Де стоячої води бути не може: r — смуга біля річки (GroundSurface.bank_mask: клітинка води
// й сусідні), g — клітинка пагорба (GroundSurface.hill_mask).
uniform sampler2D bank_map : filter_linear, repeat_disable;
uniform int plough_layer = -1;
// Суха пора (GroundSurface.season — `summer` чи `early`): без моху й пучків трави в лісі, тінь
// купок щебеню від сонця.
uniform bool dry_season = false;

// Номер поля ріллі в клітинці карти класів; поза картою й не рілля — -1.
int plough_id(ivec2 c) {
	ivec2 sz = textureSize(plough_map, 0);
	if (c.x < 0 || c.y < 0 || c.x >= sz.x || c.y >= sz.y) {
		return -1;
	}
	return int(round(texelFetch(plough_map, c, 0).r * 255.0)) - 1;
}
// Слот класу двору (`YARD`, клітинки будівель): поле з плямами втоптаного ґрунту 2–6 м;
// -1 — двору нема.
uniform int yard_slot = -1;
// Клітинка, що відповідає пікселю (0, 0) карт класів (від'ємна при відступі).
uniform vec2 map_origin = vec2(0.0);
// Властивості шарів macro_array (до 16; перші 8 — шари деталі, далі — підтипи):
// базовий шар (дорога, поле, ліс), шар деталі, вирівнювання макро (2 — поворот лише 0/180°).
uniform int layer_base[16];
uniform int layer_detail[16];
uniform int layer_aligned[16];
// Метрів на повтор макро шару (CC0-скани мають власний фізичний розмір: 20 м, 25 м тощо).
uniform float macro_m[16];
// Дорога (RoadCourse.rasterise): R — знакова відстань до краю (м), G — бокове v (м),
// B — (u mod 64) / 16, A — floor(u / 64); типи: асфальт, ґрунтівка, бруківка,
// A — близькість розвилки.
uniform bool has_roads = false;
uniform sampler2D road_field : filter_nearest, repeat_disable;
uniform sampler2D road_type : filter_linear, repeat_disable;
uniform float road_px = 8.0;
// Шари macro_array для асфальту, ґрунтівки, бруківки.
uniform int road_layer[3];
uniform sampler2DArray albedo_array : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray normal_array : filter_linear_mipmap_anisotropic, repeat_enable;
// Макро: вид зверху, один повтор — macro_m метрів свого шару, вміст намальовано в реальному
// розмірі (колії 0.3-0.5 м, калюжі 1-3 м). Альфа = висота. Деталь (albedo_array) —
// фото-текстури в реальному масштабі REPEAT_M: лише модуляція яскравості й нормаль
// біля камери поверх макро, колір не замінює.
uniform sampler2DArray macro_array : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
// Варіантів макро на шар: індекс шару в macro_array = layer * macro_variants + variant.
uniform int macro_variants = 1;
uniform float mud_amount = 0.0;
// Шрами бою (ScarMap): R — випалене, A — попіл; 32 текселі на тайл дошки. Маска — розвідане
// (`seen`) глядача, тексель на тайл: шрам на нерозвіданому був би доносом про бій (§3.5).
uniform bool has_scars = false;
uniform sampler2D scar_map : filter_linear, repeat_disable;
uniform sampler2D scar_seen : filter_linear, repeat_disable;
uniform vec2 scar_size = vec2(1.0);

// Шари з GroundSurface.TEX_LAYERS.
const int ROAD = 0;
const int FIELD = 1;
const int HILL = 3;
const int FOREST = 2;
const int MARSH = 4;
const int MUD = 5;
// Шар берега (русла) — під WATER, BRIDGE і BRIDGE_DESTROYED (GroundSurface.TEX_LAYER_FOR_KIND).
const int BANK = 7;
// Колір піску коси.
const vec3 SAND_TINT = vec3(3.1, 2.6, 1.8);

// Підсилення альбедо шару: текстура лісової підстилки майже чорна (середнє 55
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
// Лише для вимірів на скріншотах: 1 — клас-переможець пласким кольором, 2 — покриття дороги,
// 3 — камінь (rock_k). Колір — у EMISSION при чорному альбедо, тож світло його не міняє.
uniform int debug_view = 0;
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

varying vec3 world_pos;

#include "res://game/battle/shaders/surroundings.gdshaderinc"

#include "res://game/battle/shaders/terrain_noise.gdshaderinc"

// Зсув межі класів — три октави шуму, повернуті відносно осей сітки, у клітинках: велика
// (хвиля ~16 м, ±2–3 м), середня (у class_warp) і дрібна (хвиля 1–3 м). Довша велика хвиля
// лишає межу прямою на 2+ клітинки.
const mat2 ROT_A = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
const mat2 ROT_B = mat2(vec2(0.28, 0.96), vec2(-0.96, 0.28));
// fbm має std ~0.13: ×2.0 разом із середньою октавою дає std зсуву ~0.3 клітинки (~2.5 м,
// ціль 0.8–2.5 м); дрібна vnoise (std 0.21) ×0.32 — std ~0.54 м. Менші множники тримають
// межу біля лінії сітки (40 % довжини в ±0.1 клітинки) і прямою на 1.5–2 клітинки.
const float CLASS_LOBE = 2.0;
const float CLASS_BITE = 0.32;
// Смуга змішування класів в одиницях індикатора: схил згладженої білінійної на межі —
// 1.5 / клітинку, тож 0.05 дає перехід ~0.3 м.
const float CLASS_BAND = 0.05;
// Біля центру клітинки зсув межі слабшає до цієї частки: інакше одиночна клітинка (болото
// в 1 клітинку на River) показує свій вид лише на 22 % площі, а з 0.5 — ≥ 31 % на всіх картах
// (tests/game/test_ground_surface.gd). Вид міняє число руху, тож гравець мусить його бачити.
const float CLASS_CORE = 0.5;
// Межа двох покриттів класів (лука, болото, ліс, пагорб, берег, щебінь) — ~0.3 клітинки (~2.5 м),
// рвана висотною сумішшю: не обривається лінією, щебінь розсипається в траву. Ширша смуга дорожча
// (більше пікселів із двома шарами) майже без видимої різниці. Рілля — рукотворна — у класи не
// входить: її поле малюється окремо з прямим краєм (plough_map).
const float NATURAL_BAND = 0.45;
const int RUBBLE = 6;
// Рілля всередині поля відступає від краю клітинки на ~1.2 м — смуга трави (узбіччя
// поля), а прямий край лишається в межах 0.1–0.3 клітинки від межі клітинок.
const float PLOUGH_HEADLAND = 0.15;
// Калюжі в коліях: комірка вздовж колії, у ній щонайбільше одна калюжа 0.3–2.5 м, що не виходить
// за комірку. Імовірність 0.65 у дощ дає ~35 % довжини колії, проміжки з CV ~0.95; при MUD — ×0.7.
const float RUT_CELL_M = 2.6;
const float RUT_PUDDLE_P = 0.65;
// Стеля відбиття неба в калюжі — трохи нижче за воду річки (reflect_top 0.26 у water.gdshader):
// калюжа має ще й власне альбедо, тож не світліша за річку. Вікна болота — POOL_SKY_MAX нижче.
const float PUDDLE_SKY_MAX = 0.2;
// Множник яскравості асфальту й бруківки після стиснення рельєфу: сухий і мокрий.
const float PAVED_DRY_K = 0.75;
const float PAVED_WET_K = 0.45;
// Схил (tan), на якому калюжа вже не стоїть: 5° -> 7.5°. Схили пагорбів і берегів — сухі.
const float PUDDLE_SLOPE_LO = 0.087;
const float PUDDLE_SLOPE_HI = 0.13;
// Частка неба на краю вікна болота: вода оливково-бура, небо лише зверху; на 0.18–0.3 по всьому
// вікну воно ставало рівною сірою плитою.
const float POOL_SKY_MAX = 0.07;
// Середина вікна болота відбиває більше неба (~40 % сірого), край лишається оливковим.
const float POOL_SKY_CENTRE = 0.28;
// Калюжа на асфальті — у центрі до 0.5: на ~15–25 рівнів світліша за мокрий асфальт.
const float PAVED_PUDDLE_SKY = 0.5;
// Болото: оливково-бурий тон замість сірого скану (множник до яскравості, сума з вагами L ≈ 1).
const vec3 MARSH_TINT = vec3(1.26, 1.01, 0.6);
// Тон ґрунту ґрунтівки (множник до сірого). Кольорова корекція сцени знижує насиченість на
// ~2/3: на екрані тіло дороги має a* ~2, b* ~8 проти b* 3–5 у поля, тобто лишається бурим.
const vec3 SOIL_TINT = vec3(1.42, 1.0, 0.58);
// Множник тону каменю на схилах (шар HILL): медіана L* 36 -> ~31–32, як у поля поруч.
const float ROCK_GAIN = 0.62;
// Вага висоти фото каменя у виборі «камінь чи трава»: більша — різкіший поділ на окремі камені.
const float STONE_H = 3.0;

vec2 class_warp(vec2 p) {
	vec2 a = ROT_A * p * 0.5;
	vec2 lobe = vec2(fbm(a + 3.1), fbm(a + vec2(17.3, 5.9))) - 0.5;
	vec2 b = ROT_B * p * 4.0;
	vec2 bite = vec2(vnoise(b), vnoise(b + 9.7)) - 0.5;
	// Середня октава, хвиля ~6 м (std ~0.21 клітинки, 1.7 м): гне межу там, де велика октава
	// пласка; без неї межа на таких ділянках пряма на 1.5–2 клітинки.
	vec2 c = ROT_A * ROT_B * p * 1.4;
	vec2 mid = vec2(vnoise(c + 4.4), vnoise(c + 23.1)) - 0.5;
	return lobe * CLASS_LOBE + mid * 1.0 + bite * CLASS_BITE;
}

// Поле дороги в точці: білінійно вручну, бо u зберігається частинами (B, A) — так воно неперервне
// через перенос 64 м. x — d (м), y — v (м), z — u (м).
vec3 road_sample(vec2 p) {
	ivec2 sz = textureSize(road_field, 0);
	vec2 t = (p - map_origin + 0.5) * road_px - 0.5;
	vec2 i0 = floor(t);
	vec2 f = t - i0;
	ivec2 a = ivec2(i0);
	vec4 s00 = texelFetch(road_field, clamp(a, ivec2(0), sz - 1), 0);
	vec4 s10 = texelFetch(road_field, clamp(a + ivec2(1, 0), ivec2(0), sz - 1), 0);
	vec4 s01 = texelFetch(road_field, clamp(a + ivec2(0, 1), ivec2(0), sz - 1), 0);
	vec4 s11 = texelFetch(road_field, clamp(a + ivec2(1, 1), ivec2(0), sz - 1), 0);
	vec3 r00 = vec3(s00.xy, s00.w * 64.0 + s00.z * 16.0);
	vec3 r10 = vec3(s10.xy, s10.w * 64.0 + s10.z * 16.0);
	vec3 r01 = vec3(s01.xy, s01.w * 64.0 + s01.z * 16.0);
	vec3 r11 = vec3(s11.xy, s11.w * 64.0 + s11.z * 16.0);
	return mix(mix(r00, r10, f.x), mix(r01, r11, f.x), f.y);
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

// forced >= 0 — поворот лише 0/180° від цього кута (борозни); інакше кут довільний: поворот,
// кратний 90°, клав би лінії текстури вздовж осей сітки.
void hex_rand(vec2 id, float salt, float forced, out vec2 off, out mat2 r) {
	off = vec2(hash12(id + salt * 13.1), hash12(id + 7.7 + salt * 5.3)) * 8.0;
	float a = hash12(id + 3.3 + salt * 2.9) * 6.2831853;
	if (forced >= 0.0) {
		a = forced + floor(a / 3.1415927) * 3.1415927;
	}
	r = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a)));
}

// Камінці на схилі: фото пагорба з шару деталі (повтор repeat_m, ~2 м — камені 10–40 см на
// траві), гекс-тайлінг із поворотом. Колір, нахил нормалі (освітлений і тіньовий бік) і висота.
// Макро пагорба (скан узбережжя на 20 м) тут не годиться: його брили — 1–2.5 м плитами.
// full = false — лише висота (альфа альбедо): для другого відліку в бік сонця нормаль не потрібна, мінус 3 вибірки.
void stone_sample(vec2 p, vec2 dpx, vec2 dpy, bool full, out vec3 col, out vec2 nrm, out float hgt) {
	float dfl = float(HILL);
	// Фото в 1.6 раза більше за свій масштаб: камінці 15–60 см, на z6 — 5–15 px, щоб мали світлий і тіньовий бік.
	float tpr = 1.6 * repeat_m[HILL] / METRES_PER_TILE;
	vec2 uv = p / tpr;
	vec2 ddx = dpx / tpr;
	vec2 ddy = dpy / tpr;
	vec2 id[3];
	vec3 w;
	hex_grid(uv, id, w);
	float inv = inversesqrt(dot(w, w));
	vec4 dm = textureLod(albedo_array, vec3(0.5, 0.5, dfl), 14.0);
	vec4 acc = vec4(0.0);
	vec2 nacc = vec2(0.0);
	for (int i = 0; i < 3; i++) {
		vec2 o;
		mat2 r;
		hex_rand(id[i], dfl + 31.0, -1.0, o, r);
		vec3 c = vec3(r * uv + o, dfl);
		acc += w[i] * (textureGrad(albedo_array, c, r * ddx, r * ddy) - dm);
		if (full) {
			nacc += w[i] * (r * (textureGrad(normal_array, c, r * ddx, r * ddy).rg * 2.0 - 1.0));
		}
	}
	vec4 s = dm + acc * inv;
	col = s.rgb;
	nrm = nacc * inv;
	hgt = s.a;
}

// Один шар: макро (гекс, 3 семпли, паралакс по висоті макро) + деталь біля камери.
// pom_w — зсув у світі на повну глибину (0 — паралаксу нема). Виходи: колір, нахил
// нормалі, висота (відносно середньої шару, 0.5 = середня) і каверна (1 = відкрито).
void sample_layer(int layer, vec2 p, vec2 dpx, vec2 dpy, vec2 pom_w, float dfade, out vec3 alb, out vec2 nxy, out float hgt, out float cav) {
	float fl = float(layer);
	float mt = macro_m[layer] / METRES_PER_TILE;
	vec2 muv = p / mt;
	vec2 mdx = dpx / mt;
	vec2 mdy = dpy / mt;
	vec2 id[3];
	vec3 w;
	hex_grid(muv, id, w);
	vec2 off[3];
	mat2 rot[3];
	float mlay[3];
	vec4 mmv[3];
	for (int i = 0; i < 3; i++) {
		hex_rand(id[i], fl, layer_aligned[layer] == 2 ? 0.0 : -1.0, off[i], rot[i]);
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
	vec2 mshift = pom_w / mt;
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
	vec2 sp = muv + shift / mt;
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
			hex_rand(did[i], dfl + 17.0, -1.0, o, r);
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
	if (layer_base[layer] == FOREST) {
		// Лісова підстилка: рівномірні темні цятки 15–25 см на пласкому бурому тоні дають
		// високочастотний шум. Темні відхили від середнього стиснуто на 65 %; плями моху й листя
		// 5–10 м; підстилка вкриває ~60 % площі (поріг fbm), між плямами трава, а пучки трави
		// 0.5–1 м проступають крізь неї.
		vec3 lw = vec3(0.299, 0.587, 0.114);
		float lm = max(dot(mm.rgb * layer_gain(FOREST), lw), 1e-3);
		float l = max(dot(alb, lw), 1e-4);
		// Темні проміжки між листям і хвоєю — і є фактура опаду, тож стиснення слабке (лишається
		// 70–75 % контрасту); сильніше розмазувало підстилку в рівну повсть.
		float keep_dark = dry_season ? 0.75 : 0.7;
		alb *= l < lm ? (lm - keep_dark * (lm - l)) / l : 1.0;
		if (dry_season) {
			// Сухий опад — бурий, не сажа: білі цятки (світлі відхили понад 1.5 середнього) стиснуто,
			// а вся підстилка світліша на ~30 % (~15 рівнів) і тепліша, як листя.
			float lh = max(dot(alb, lw), 1e-4);
			alb *= lh > 1.5 * lm ? (1.5 * lm + 0.25 * (lh - 1.5 * lm)) / lh : 1.0;
			alb *= 1.3 * vec3(1.08, 1.0, 0.84);
		}
		// Суха пора — сухий опад без зелених плям моху.
		float moss = dry_season ? 0.0 : smoothstep(0.5, 0.64, fbm(p * 1.1 + 61.0));
		float leaf = smoothstep(0.52, 0.66, fbm(p * 0.8 + 83.0)) * (1.0 - moss);
		alb = mix(alb, alb * vec3(0.82, 0.98, 0.7), moss * 0.7);
		// Суха пора: опад уже бурий у самій текстурі, рудий відтінок плям лише слабкий — інакше
		// підстилка розмазується іржею.
		alb = mix(alb, alb * vec3(1.18, 1.0, 0.78), leaf * (dry_season ? 0.15 : 0.6));
		// Трава між плямами підстилки — справжня текстура луки, а не її середній колір: рівна
		// пляма одного кольору 1–2.5 м на оливковому тлі читалась як камуфляж.
		float gmt = macro_m[FIELD] / METRES_PER_TILE;
		vec3 grass = textureGrad(macro_array, vec3(p / gmt, float(FIELD * macro_variants)), dpx / gmt, dpy / gmt).rgb;
		grass *= clamp(dot(alb, lw) / lm, 0.6, 1.4);
		float floor_k = smoothstep(0.43, 0.5, fbm(p * 0.7 + 19.0));
		// Пучки трави крізь підстилку — лише в пізню осінь: у суху пору світло-зелені пучки на
		// бурому опаді читались як штамп круглих цяток.
		float clump = dry_season ? 0.0 : smoothstep(0.62, 0.76, vnoise(p * 12.0 + 3.0));
		alb = mix(alb, grass, max(1.0 - floor_k, clump * 0.8));
	}
	if (layer_base[layer] == MUD && dry_season) {
		// Сухий ґрунт двору світліший за щебінь і траву довкола, тож там, де його вага велика, лягав
		// блідими овалами: темніший і тепліший, у тон двору.
		alb *= 0.85 * vec3(1.02, 1.0, 0.94);
	}
	if (layer_base[layer] == MARSH) {
		// Купини 0.4–0.8 м: світліші солом'яні верхи й темні проміжки; плями очерету 2–4 м.
		vec3 lw = vec3(0.299, 0.587, 0.114);
		alb = vec3(dot(alb, lw)) * MARSH_TINT;
		float tus = smoothstep(0.35, 0.75, vnoise(p * 14.0 + 7.0));
		alb *= mix(0.78, 1.15, tus);
		alb = mix(alb, alb * vec3(1.12, 1.06, 0.78), tus * tus * 0.6);
		float reed = smoothstep(0.5, 0.65, fbm(p * 2.5 + 91.0));
		alb = mix(alb, alb * vec3(0.82, 0.95, 0.66), reed * 0.6);
	}
	// Висота відносно середньої шару: шари з різною середньою висотою змагаються чесно,
	// а каверна темнить лише те, що нижче середнього (інакше багно чорніє).
	float dev = h - mm.a;
	hgt = 0.5 + dev;
	// Повна каверна (cavity) темнить западини до ×0.55; у лісовій підстилці западини — цятки
	// 15–25 см, і така глибина дає дрібні контрастні темні плями, тож для лісу множник 0.1, а не
	// 0.45 (контраст цяток на екрані — ~вдвічі менший).
	cav = 1.0 - (layer_base[layer] == FOREST ? 0.1 : 0.45) * clamp(-dev * 2.5, 0.0, 1.0);
}

// Рельєф (TerrainHeight): R — висота землі у світі, G — маска води (для мокрого берега), B — кривизна.
// Висота — білінійно за позицією вершини, як TerrainHeight.at(): на дошці вершини лежать рівно у
// відліках (те саме, що texelFetch), а грубіші вершини кільця — між ними. Нормаль — скінченні
// різниці на кроці одного відліку.
uniform bool use_height = false;
// Меш кільця (Surroundings.ground_mesh): вершина дрібної клітинки на ребрі з грубшою лягає на
// пряму грубого ребра — кінці в UV і UV2, позначка COLOR.a = 1. Без цього між смугами різної
// густоти були б щілини.
uniform bool snap_edges = false;
uniform sampler2D height_map : filter_linear, repeat_disable;
uniform float height_samples = 4.0;
// Рівень води (TerrainHeight.WATER_LEVEL) для мокрого берега.
uniform float water_level = -0.05;
varying float shore_mask;
varying float curvature;
varying float bar_mask;
varying float hill_shade;
varying float slope_tan;
// Напрямок НА сонце (`WeatherRig.sun`): запечене світло-тінь рельєфу збігається з тінями юнітів.
global uniform vec3 sun_dir;

// Відлік карти висот у локальній точці вузла землі (центр вузла — центр карти).
vec4 height_at(vec2 local) {
	vec2 hs = vec2(textureSize(height_map, 0));
	vec2 half_size = (hs - 1.0) / (2.0 * height_samples);
	return textureLod(height_map, ((local + half_size) * height_samples + 0.5) / hs, 0.0);
}

void vertex() {
	if (use_height) {
		vec2 q = VERTEX.xz;
		float e = 1.0 / height_samples;
		vec4 hm = height_at(q);
		VERTEX.y = hm.r;
		if (snap_edges && COLOR.a > 0.5) {
			// Частка — з позиції, а не з `COLOR`: колір вершини 8-бітний, і частка 1/255 зсунула б
			// точку з ребра.
			vec2 ab = UV2 - UV;
			VERTEX.y = mix(height_at(UV).r, height_at(UV2).r, clamp(dot(q - UV, ab) / dot(ab, ab), 0.0, 1.0));
		}
		float hl = height_at(q - vec2(e, 0.0)).r;
		float hr = height_at(q + vec2(e, 0.0)).r;
		vec3 n = normalize(vec3(hl - hr, 2.0 * e, height_at(q - vec2(0.0, e)).r - height_at(q + vec2(0.0, e)).r));
		NORMAL = n;
		// Та сама умовність, що в PlaneMesh: тангент уздовж +X, бінормаль = n x t (дивиться в -Z).
		vec3 t = normalize(vec3(1.0, (hr - hl) / (2.0 * e), 0.0));
		TANGENT = t;
		BINORMAL = normalize(cross(n, t));
		shore_mask = hm.g;
		curvature = hm.b;
		bar_mask = hm.a;
		hill_shade = dot(n, normalize(sun_dir)) - normalize(sun_dir).y;
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
	// Похідні — до гілки суцільної імли: у сусідніх пікселях, що пішли іншою гілкою, вони не
	// визначені. Текстури в гілці беруть їх звідси (textureGrad) або явний міп. У гілці лишається
	// одна похідна — `dFdx(rs)` для тіні каменю на схилі: маска схилу залежить від покриття дороги
	// всередині гілки, а на межі суцільної імли камінь однаково не видно.
	vec2 dpx = dFdx(p);
	vec2 dpy = dFdy(p);
	vec3 rf = has_roads ? road_sample(p) : vec3(1e3, 0.0, 0.0);
	float fwv = fwidth(rf.y);
	float rv_all = ripple_visibility(p);
	vec2 dxy_x = dFdx(world_pos.xy);
	vec2 dxy_y = dFdy(world_pos.xy);
	vec2 dzy_x = dFdx(world_pos.zy);
	vec2 dzy_y = dFdy(world_pos.zy);
	vec4 haze = vec4(0.0);
	float line_a = 0.0;
	if (surround) {
		haze = fog_bank(world_pos, CAMERA_POSITION_WORLD, normalize(-INV_VIEW_MATRIX[2].xz));
		line_a = surround_line(world_pos, CAMERA_POSITION_WORLD, 0.0, VIEWPORT_SIZE);
	}
	// Під суцільною імлою видно лише її колір: решту матеріалу не рахуємо.
	if (haze.a >= 0.999) {
		ALBEDO = vec3(0.0);
		ROUGHNESS = 1.0;
		SPECULAR = 0.0;
		FOG = vec4(haze.rgb, 1.0);
	} else {
		// Паралакс: промінь від камери; глибина згасає з відстанню до нуля.
		vec3 view = CAMERA_POSITION_WORLD - world_pos;
		float cam_dist = length(view);
		float pom_fade = 1.0 - smoothstep(pom_fade_start, pom_fade_end, cam_dist);
		vec2 pom_dir = -view.xz / max(view.y, 0.2);
		float detail_fade = 1.0 - smoothstep(detail_fade_start, detail_fade_end, cam_dist);
		float above_m = (world_pos.y - water_level) / 0.125;

		// Класи покриття: згладжена білінійна (вага Ерміта — опуклий кут клітинки стає овалом, а не
		// ромбом) у точці, зсунутій повернутим шумом. Три найсильніші класи, смуга CLASS_BAND.
		float core_r = length(p - round(p));
		vec2 g = p + class_warp(p) * mix(CLASS_CORE, 1.0, smoothstep(0.0, 0.5, core_r))
				- map_origin;
		vec2 csz = vec2(textureSize(class_map0, 0));
		vec2 ci0 = floor(g);
		vec2 cf = g - ci0;
		cf = cf * cf * (3.0 - 2.0 * cf);
		vec2 cuv = (ci0 + cf + 0.5) / csz;
		vec4 c0 = textureLod(class_map0, cuv, 0.0);
		vec4 c1 = textureLod(class_map1, cuv, 0.0);
		float S[8] = float[8](c0.r, c0.g, c0.b, c0.a, c1.r, c1.g, c1.b, c1.a);
		int top[3] = int[3](0, 0, 0);
		float tops[3] = float[3](-1.0, -1.0, -1.0);
		for (int i = 0; i < 8; i++) {
			float v = S[i];
			if (v > tops[0]) {
				tops[2] = tops[1]; top[2] = top[1];
				tops[1] = tops[0]; top[1] = top[0];
				tops[0] = v; top[0] = i;
			} else if (v > tops[1]) {
				tops[2] = tops[1]; top[2] = top[1];
				tops[1] = v; top[1] = i;
			} else if (v > tops[2]) {
				tops[2] = v; top[2] = i;
			}
		}
		int L[4];
		float W[4];
		for (int i = 0; i < 3; i++) {
			L[i] = class_layer[top[i]];
		}
		// Слот другого класу є завжди, навіть з нульовим індикатором: природна межа — лише коли
		// він справді в смузі.
		bool soft = L[0] != L[1] && tops[1] > tops[0] - NATURAL_BAND;
		// Ваги нормовано на CLASS_BAND: від їхньої величини залежать багно й калюжі нижче.
		float band = soft ? NATURAL_BAND : CLASS_BAND;
		for (int i = 0; i < 3; i++) {
			W[i] = max(tops[i] - (tops[0] - band), 0.0) * (CLASS_BAND / band);
		}
		// Природна межа — два шари: третій у широкій смузі майже не видно, а семпл повний.
		if (soft) {
			W[2] = 0.0;
		}
		// Слоти з однаковим шаром (запасні) — один семпл.
		for (int i = 1; i < 3; i++) {
			for (int j = 0; j < i; j++) {
				if (L[i] == L[j] && W[j] > 0.0) {
					W[j] += W[i];
					W[i] = 0.0;
				}
			}
		}

		// Дорога: поле RoadCourse. de — відстань до нерівного краю (м, мінус на дорозі).
		float road_cov = 0.0;
		float verge = 0.0;
		float de = 1e3;
		vec4 rt = vec4(1.0, 0.0, 0.0, 0.0);
		if (has_roads) {
			if (rf.x < 4.0) {
				vec2 tsz = vec2(textureSize(road_type, 0));
				rt = textureLod(road_type, ((p - map_origin + 0.5) * road_px) / tsz, 0.0);
				float side = rf.y >= 0.0 ? 1.0 : 0.0;
				// Край у координатах дороги (u і бік): ґрунтівка ±0.3 м із виступами трави 0.3–0.8
				// м кожні 1–3 м, бруківка ±0.15 м, асфальт ±0.08 м. На розвилці (два u сходяться) —
				// шум у світі.
				float e_lo = (fbm(vec2(rf.z * 0.35, side * 31.0 + 2.0)) - 0.5) * 2.0;
				float e_w = (fbm(p * 2.2 + 5.0) - 0.5) * 2.0;
				float e_bite = smoothstep(0.55, 0.85, vnoise(vec2(rf.z * 0.55, side * 53.0 + 7.0)));
				float amp = 0.08 * rt.r + 0.3 * rt.g + 0.15 * rt.b;
				de = rf.x + mix(e_lo, e_w, rt.a) * amp + e_bite * (0.6 * rt.g + 0.12 * rt.b) * (1.0 - rt.a);
				// Край 10–90 %: асфальт ~0.18 м, ґрунтівка ~0.45 м (smoothstep: 0.61 повної ширини)
				// — ґрунтівка плавно переходить у траву, без різкої межі.
				float soft = mix(0.15, 0.37, rt.g);
				road_cov = 1.0 - smoothstep(-soft, soft, de);
				// Узбіччя 0.6–1.4 м: витоптана рідка трава з розсипаним ґрунтом.
				float vw = mix(0.6, 1.4, vnoise(vec2(rf.z * 0.2, side * 17.0)));
				verge = (1.0 - smoothstep(0.0, vw, de)) * step(0.0, de);
				if (use_height) {
					// Під водою (міст, брід) дороги не видно.
					float dry = smoothstep(-0.05, 0.25, above_m);
					road_cov *= dry;
					verge *= dry;
				}
			}
		}

		// Багно: плями поля й пагорба під станом MUD; біля дороги (до 4 м від краю) — на 0.2
		// більше. Поріг — квантиль fbm (0.45 ≈ 30 %, 0.537 ≈ 55 %), виміряний на карті.
		float near = has_roads ? 1.0 - smoothstep(0.0, 4.0, rf.x) : 0.0;
		float cover = mud_amount + 0.2 * near;
		float thr = 0.45 + (cover - 0.3) * 0.35;
		float mud_soil = mud_amount > 0.0
				? 1.0 - smoothstep(thr - 0.02, thr + 0.02, fbm(p * 0.35 + 3.1))
				: 0.0;
		// Двір: ґрунт плямами 2–6 м, трава між ними. Межа широка й рвана (друга октава ~4 м), а
		// вага ґрунту — 0.25..0.75, не 0..1: трава й ґрунт перемішуються висотою, контраст плям
		// удвічі м'якший, без рівних країв.
		if (yard_slot >= 0) {
			float yard = smoothstep(0.35, 0.65, S[yard_slot]);
			float patch = 1.0 - smoothstep(0.4, 0.6, fbm(p * 1.4 + 57.0) + 0.25 * (fbm(p * 2.0 + 11.0) - 0.5));
			// Стеля 0.5, не 0.75: суцільний ґрунт двору лягав рівними блідими плямами.
			mud_soil = max(mud_soil, yard * mix(0.2, 0.5, patch));
		}
		float soil_w = 0.0;
		for (int i = 0; i < 3; i++) {
			if (layer_base[L[i]] == FIELD || layer_base[L[i]] == HILL) {
				soil_w += W[i];
				W[i] *= 1.0 - mud_soil;
			}
		}
		L[3] = MUD;
		W[3] = soil_w * mud_soil;
		// Щебінь — розсип купок 0.3–0.5 клітинки (~40 % площі) по ґрунту (сухому чи мокрому за
		// порою), а не суцільна плита. Край купки широкий: усередині смуги вага щебеню нижча за ґрунт,
		// тож висотна суміш лишає з нього лише верхи каменів — без світлого «блюдця» під купкою.
		// Край темніший (камінь лежить у землі), а на сонці — ще й тінь, зсунута від сонця.
		float rubble_contact = 0.0;
		vec2 sun_off = sun_dir.xz / max(sun_dir.y, 0.25) * 0.04 * (dry_season ? 1.0 : 0.0);
		float pile_f = fbm(p * 2.4 + 17.0) + 0.3 * (vnoise(p * 7.0) - 0.5);
		float pile = smoothstep(0.46, 0.62, pile_f);
		float pile_sh = smoothstep(0.46, 0.62, fbm((p + sun_off) * 2.4 + 17.0) + 0.3 * (vnoise((p + sun_off) * 7.0) - 0.5));
		for (int i = 0; i < 3; i++) {
			if (layer_base[L[i]] == RUBBLE && W[i] > 0.0) {
				float wr = W[i] / CLASS_BAND;
				rubble_contact = max(rubble_contact, wr * max(smoothstep(0.36, 0.5, pile_f) * (1.0 - pile), pile_sh * (1.0 - pile)));
				W[3] += W[i] * (1.0 - 0.6 * pile);
				W[i] *= 0.6 * pile;
			}
		}
		// Двір: на ґрунті між будинками теж купки каменю (рідші), інакше пляма ґрунту читається
		// рівною плитою. Третій слот у дворі порожній — беремо його під щебінь.
		if (yard_slot >= 0 && W[2] < 0.002) {
			float yard_k = smoothstep(0.35, 0.65, S[yard_slot]);
			float yr = yard_k * pile * 0.9;
			if (yr > 0.01) {
				L[2] = RUBBLE;
				W[2] = CLASS_BAND * yr;
				rubble_contact = max(rubble_contact, yard_k * max(smoothstep(0.36, 0.5, pile_f) * (1.0 - pile), pile_sh * (1.0 - pile)));
			}
		}

		vec3 A[4];
		vec2 N[4];
		float H[4];
		float Hgt[4];
		float Cav[4];
		float hmax = -1.0;
		// Під суцільним асфальтом чи бруківкою покриття класів не видно: його не семплуємо зовсім
		// (до 4 шарів × макро, паралакс і деталь). Ґрунтівку — семплуємо: вона просвічує траву.
		// Рілля: частка покриття з відстані до краю поля, згладжена на один піксель. Ширина
		// згладжування — з dpx/dpy поза розгалуженням (fwidth у неоднорідній гілці невизначений).
		float plough_a = 0.0;
		int pf = -1;
		float plough_aa = max(max(length(dpx), length(dpy)), 0.004);
		if (plough_layer >= 0) {
			ivec2 pc = ivec2(round(p - map_origin));
			pf = plough_id(pc);
			if (pf >= 0) {
				// Відстань до краю — від справжніх клітинок поля: сторони, де сусід не з цього поля,
				// і кути, де не з поля діагональний сусід. Тож і неправильна група має узбіччя на
				// кожному зовнішньому краї, а не сходинки по межах клітинок.
				vec2 f = p - map_origin - vec2(pc);
				vec4 ins = plough_inset[pf];
				float d = 1.0;
				for (int dy = -1; dy <= 1; dy++) {
					for (int dx = -1; dx <= 1; dx++) {
						if ((dx == 0 && dy == 0) || plough_id(pc + ivec2(dx, dy)) == pf) {
							continue;
						}
						float ix = dx > 0 ? ins.z : ins.x;
						float iy = dy > 0 ? ins.w : ins.y;
						vec2 e = vec2(dx == 0 ? 1.0 : 0.5 - f.x * float(dx) - ix, dy == 0 ? 1.0 : 0.5 - f.y * float(dy) - iy);
						d = min(d, dx != 0 && dy != 0 ? length(e) : min(e.x, e.y));
					}
				}
				// Край не по лінійці: ±0.025 клітинки (±0.2 м) із хвилею ~2–3 м — плуг іде нерівно.
				d -= PLOUGH_HEADLAND + 0.025 * (vnoise(p * 3.0 + 29.0) * 2.0 - 1.0);
				plough_a = smoothstep(-plough_aa, plough_aa, d);
			}
		}
		bool skip_cls = (road_cov > 0.995 && rt.g < 0.005) || plough_a > 0.999;
		for (int i = 0; i < 4; i++) {
			H[i] = -10.0;
			if (W[i] > 0.002 && !skip_cls) {
				// Глибина в одиницях світу (1 м = 0.125), потім у UV шару.
				// На природній межі паралакс і деталь — лише в головного шару: другий у смузі
				// змішується висотою, і його власний рельєф там не видно, а коштує він ~вдвічі.
				bool lean = soft && i > 0;
				vec2 pom = pom_fade > 0.01 && !lean
						? pom_dir * (relief_m[L[i]] * relief_scale * pom_fade / METRES_PER_TILE)
						: vec2(0.0);
				// Ліс бере деталь (фото підстилки, гекс-тайлінг) і там, де звичайна вже згасла, — до ~9–14
				// клітинок (кадр z6): без неї макро лісу на 2 м розмивається в повсть. Далі її не видно.
				float dfl = lean ? 0.0 : (layer_base[L[i]] == FOREST ? 1.0 - smoothstep(9.0, 14.0, cam_dist) : detail_fade);
				sample_layer(L[i], p, dpx, dpy, pom, dfl, A[i], N[i], Hgt[i], Cav[i]);
				// Висотне змішування: на межі першим проступає те, що вище в самій
				// карті висот (камінь, кому, пучок), тож перехід рваний, а не розмитий.
				float wn = W[i] / max(W[0] + W[1] + W[2] + W[3], 1e-4);
				// На природній межі вага класу слабша: висота перемішує покриття на всю ширину
				// смуги (~4 м), а не стягує перехід назад до ~1 м.
				H[i] = wn * (soft ? 0.35 : 1.0) + Hgt[i] * 0.45;
				hmax = max(hmax, H[i]);
			}
		}
		vec3 alb = vec3(0.0);
		vec2 nxy = vec2(0.0);
		float rough = 0.0;
		float cav = 0.0;
		float wsum = 0.0;
		float marsh_w = 0.0;
		float rub_h = -10.0;
		float rub_w = 0.0;
		for (int i = 0; i < 4; i++) {
			// H = -10 — шар не семплувався (вага 0 або skip_cls): його A/N не ініціалізовані.
			float w = H[i] < -5.0 ? 0.0 : max(H[i] - (hmax - 0.18), 0.0);
			if (H[i] > -5.0 && layer_base[L[i]] == RUBBLE) {
				rub_h = max(rub_h, H[i]);
				rub_w += w;
			}
			if (w > 0.0) {
				// Під хмарами мокрий щебінь і підстилка лісу — тепло-сіро-бурі, як ґрунт довкола: фото дають
				// нейтральний сірий, і ліс на Річці лягав холодною сірою плямою поруч із теплим лугом.
				vec3 late_k = dry_season ? vec3(1.0) : (layer_base[L[i]] == RUBBLE ? vec3(1.1, 0.96, 0.84) : (layer_base[L[i]] == FOREST ? vec3(1.08, 1.02, 0.9) : vec3(1.0)));
				alb += A[i] * late_k * w;
				nxy += N[i] * w;
				rough += 0.92 * w;
				// Каверна: низини карти висот темніші (щілини між каменями, дно колії).
				cav += Cav[i] * w;
				marsh_w += layer_base[L[i]] == MARSH ? w : 0.0;
				wsum += w;
			}
		}
		if (wsum > 0.0) {
			marsh_w /= wsum;
			alb /= wsum;
			nxy /= wsum;
			rough /= wsum;
			cav /= wsum;
		} else {
			// Під дорогою (skip_cls): значення лише заглушка, дорога нижче перекриває її повністю.
			alb = vec3(0.05);
			rough = 0.9;
			cav = 1.0;
		}
		// Підніжжя каменів щебеню: там, де висота щебеню трохи не дотягла до переможця (камінь
		// поруч), ґрунт темніший на ~30 % — кільце ~0.2–0.4 м, а не пляма під усією купкою.
		float rub_ring = rub_h > -5.0 ? smoothstep(hmax - 0.42, hmax - 0.2, rub_h) * (1.0 - rub_w / max(wsum, 1e-4)) : 0.0;
		alb *= cav * foliage_tint * (1.0 - 0.3 * clamp(max(rubble_contact, rub_ring), 0.0, 1.0));
		if (plough_a > 0.001) {
			// Поле вздовж z: семплуємо в повернутих на -90° координатах, щоб борозни (вісь x
			// текстури) йшли вздовж довгого боку; нахил нормалі повертаємо назад.
			bool vert = plough_axis[pf] == 1;
			vec2 q = vert ? vec2(p.y, -p.x) : p;
			vec2 qdx = vert ? vec2(dpx.y, -dpx.x) : dpx;
			vec2 qdy = vert ? vec2(dpy.y, -dpy.x) : dpy;
			vec2 pd = vert ? vec2(pom_dir.y, -pom_dir.x) : pom_dir;
			vec2 ppom = pom_fade > 0.01
					? pd * (relief_m[plough_layer] * relief_scale * pom_fade / METRES_PER_TILE)
					: vec2(0.0);
			vec3 pa;
			vec2 pn;
			float ph;
			float pcav;
			sample_layer(plough_layer, q, qdx, qdy, ppom, detail_fade, pa, pn, ph, pcav);
			if (vert) {
				pn = vec2(-pn.y, pn.x);
			}
			alb = mix(alb, pa * pcav * foliage_tint, plough_a);
			nxy = mix(nxy, pn, plough_a);
			rough = mix(rough, 0.92, plough_a);
			marsh_w *= 1.0 - plough_a;
		}

		// Дорога поверх покриття. Ґрунт — ізотропна текстура типу у світі; усе спрямоване (колії,
		// центральна трава, калюжі) — у координатах дороги (u, v), тож іде крізь кути без розривів.
		float rut = 0.0;
		float rut_pud = 0.0;
		float rut_rim = 0.0;
		float paved_sheen = 0.0;
		float paved_rim = 0.0;
		float wheel = 0.0;
		float road_mul = 1.0;
		if (road_cov > 0.001 || verge > 0.001) {
			int t1 = rt.r >= rt.g && rt.r >= rt.b ? 0 : (rt.g >= rt.b ? 1 : 2);
			vec3 ra; vec2 rn; float rh; float rc;
			vec2 rpom = pom_fade > 0.01 ? pom_dir * (relief_m[road_layer[t1]] * relief_scale * pom_fade / METRES_PER_TILE) : vec2(0.0);
			sample_layer(road_layer[t1], p, dpx, dpy, rpom, detail_fade, ra, rn, rh, rc);
			ra *= rc;
			// Перехід типів (асфальт -> бруківка) — нерівний і розтягнутий на 1–2 м. Вага рахується
			// від типу з більшим номером, а не від переможця: на лінії зміни переможця шум мав би
			// протилежний знак і давав поперечний шов.
			float tw1 = rt[t1];
			if (tw1 < 0.95) {
				int t2 = t1 == 0 ? (rt.g >= rt.b ? 1 : 2) : (t1 == 1 ? (rt.r >= rt.b ? 0 : 2) : (rt.r >= rt.g ? 0 : 1));
				vec3 sa; vec2 sn; float sh; float sc;
				sample_layer(road_layer[t2], p, dpx, dpy, vec2(0.0), detail_fade, sa, sn, sh, sc);
				int hi = max(t1, t2);
				float h_hi = hi == t2 ? sh : rh;
				float h_lo = hi == t2 ? rh : sh;
				float khi = smoothstep(0.3, 0.7, rt[hi] + 0.35 * (fbm(p * 1.7 + 13.0) - 0.5) + 0.12 * (vnoise(p * 5.0 + 3.0) - 0.5) + 0.2 * (h_hi - h_lo));
				float k = hi == t2 ? khi : 1.0 - khi;
				ra = mix(ra, sa * sc, k);
				rn = mix(rn, sn, k);
			}
			float av = abs(rf.y);
			float side = rf.y >= 0.0 ? 1.0 : 0.0;
			float u = rf.z;
			// Колії йдуть крізь розвилку майже до її середини (гаснуть лише в глибині
			// заокруглення). Глухий кінець лінії RoadCourse позначає тією ж вагою.
			float straight = 1.0 - smoothstep(0.6, 0.95, rt.a);
			// Колії ґрунтівки: колія 1.5–1.8 м (|v| ≈ 0.83 м), хитання ±6 см; глибина змінюється
			// вздовж дороги.
			float wob = 0.12 * (vnoise(vec2(u * 0.25, 3.0 + side)) - 0.5);
			float track = abs(av - 0.83 - wob);
			// Смуга колії 0.12–0.38 м між рівнями 90 % і 10 % (~0.4 м завширшки; 0.7 м читалось
			// борозною); на далекому зумі край розширюється на піксель (fwidth), тож колія не
			// вироджується в однопіксельну чорну лінію.
			rut = (1.0 - smoothstep(0.06 - fwv, 0.19 + fwv, track)) * straight;
			// Темнота колії змінюється на ±30 % з періодом 3–8 м.
			float rut_k = mix(0.7, 1.3, smoothstep(0.25, 0.75, fbm(vec2(u * 0.18, 1.0 + side))));
			// Асфальт і бруківка: сухими — без смуг коліс, бо їх не відрізнити від колій ґрунтівки.
			// Мокрими лише смуги коліс трохи темніші й глянцевіші (×0.9, шорсткість 0.18).
			float hw = max(av - rf.x, 0.5);
			float lc = hw > 2.75 ? 0.5 * hw : 0.0;
			float wv = av - lc + 0.2 * (vnoise(vec2(u * 0.05, 7.0 + side)) - 0.5);
			float paved = (rt.r + 0.25 * rt.b) * straight;
			wheel = (1.0 - smoothstep(0.12 - fwv, 0.48 + fwv, abs(abs(wv) - 0.85))) * paved;
			float wet_now = clamp(weather_wetness, 0.0, 1.0);
			float wear_k = 1.0 - 0.1 * wheel * wet_now;
			// Колії й знос множаться після стиснення яскравості (нижче): до нього ΔL* вдвічі
			// менший. Колія темніша за тіло дороги на ΔL* ~6–13 (×0.58–0.78), але не чорна.
			// Суха колія темнішає слабше (0.22): на 0.32 сухий ґрунт ставав буряково-темним (~35).
			road_mul = (1.0 - rut * rut_k * (dry_season ? 0.22 : 0.32) * rt.g) * wear_k;
			// Асфальт і бруківка темніші за траву: сухі ~0.8, мокрі ~0.7 її яскравості. Множиться тут, після
			// стиснення яскравості рельєфу (нижче), — темніше альбедо воно з'їдало майже повністю.
			road_mul *= mix(1.0, mix(PAVED_DRY_K, PAVED_WET_K, wet_now), rt.r + rt.b);
			// Мокра ґрунтівка темніша: поза коліями, особливо на розвилці, суха світла пляма ґрунту в дощ
			// читалась серпанком біля кінця асфальту.
			road_mul *= mix(1.0, 0.78, wet_now * rt.g);
			vec3 lw = vec3(0.299, 0.587, 0.114);
			// Ґрунтівка: бурий ґрунт ~70 % поверх трави (тіло 0.45–0.9 плямами), смуги коліс —
			// голий ґрунт, посередині — трав'яна смужка 0.4–0.6 м із розривами на ~25 % довжини.
			vec3 soil = vec3(dot(ra, lw)) * SOIL_TINT;
			float bare = 1.0 - smoothstep(0.25, 0.45, track);
			// На розвилці u, v перемикаються між лініями, і плями тіла в координатах дороги розмазувались
			// сірим серпанком: там шум у світових координатах.
			float body_n = mix(fbm(p * 2.4 + 5.0), fbm(vec2(u * 0.3, rf.y * 0.9) + 5.0), straight);
			float body = clamp(0.68 + 0.5 * (body_n - 0.5),
					0.45, 0.9);
			// На кінці лінії й розвилці (straight → 0) колій нема, і рівний ґрунт тіла лягав сірою плямою без
			// фактури: там ґрунту лише ~40 %, решта — трава.
			body = max(body * mix(0.4, 1.0, straight), 0.95 * bare * straight);
			vec3 dirt_alb = mix(alb, soil, body);
			float cg = (1.0 - smoothstep(0.2, 0.3, av + 0.1 * (vnoise(vec2(u * 0.7, 5.0)) - 0.5)))
					* smoothstep(0.2, 0.45, vnoise(vec2(u * 0.3, 9.0))) * straight;
			dirt_alb = mix(dirt_alb, alb * vec3(1.05, 1.0, 0.85), cg * 0.85);
			// Дно колії — мокрий темно-бурий ґрунт, але лише в дощ чи в багно: на сухій карті
			// калюж і мокрого нема ніде.
			dirt_alb = mix(dirt_alb, dirt_alb * vec3(1.0, 0.9, 0.78),
					rut * 0.7 * (mud_amount > 0.0 ? 1.0 : clamp(weather_wetness, 0.0, 1.0)));
			// Суха колія — сіро-бура утоптана пилюка, не бурякова: насиченість дна наполовину.
			if (dry_season) {
				dirt_alb = mix(dirt_alb, vec3(dot(dirt_alb, lw)) * vec3(1.04, 1.0, 0.9), rut * 0.5);
			}
			// Асфальт: темний і рівний (тон текстури дає лише дрібну варіацію), латки ремонту 1–4 м
			// (свіжі темніші, старі світліші), тріщини низького контрасту; край переходить у гравій
			// до 0.4 м усередину.
			float la = dot(ra, lw);
			vec3 asph = vec3(la * 0.8) * vec3(0.97, 0.99, 1.02);
			asph *= mix(1.0, 0.8, smoothstep(0.6, 0.64, fbm(vec2(u * 0.3, rf.y * 0.3) + 31.0)));
			asph *= mix(1.0, 1.1, smoothstep(0.58, 0.62, fbm(vec2(u * 0.2, rf.y * 0.25) + 47.0)));
			float crack = 1.0 - smoothstep(0.0, 0.025 + (abs(dpx.x) + abs(dpy.x)) * 3.0, abs(vnoise(p * 3.0 + 5.0) - 0.5));
			asph *= 1.0 - 0.18 * crack;
			vec3 gravel = vec3(la * 1.3) * vec3(1.02, 1.0, 0.95) * (0.75 + 0.5 * vnoise(p * 45.0));
			// Мокрий гравій темніший і тепліший: сухо-світлий у дощ лягав сірим серпанком біля кінця асфальту.
			gravel *= mix(vec3(1.0), vec3(0.56, 0.54, 0.5), clamp(weather_wetness, 0.0, 1.0));
			float crumble = smoothstep(-0.45, -0.05, de + 0.35 * (vnoise(vec2(u * 1.4, side * 7.0 + 3.0)) - 0.5));
			// Кінець асфальту (перехід у ґрунтівку): замість прямого зрізу — гравійна смуга
			// завдовжки ~ширину дороги, у яку асфальт переходить плямами.
			float apron = 1.0 - smoothstep(0.45, 0.9, rt.r + 0.35 * (vnoise(p * 2.5 + 17.0) - 0.5));
			asph = mix(asph, gravel, max(crumble, apron * step(0.05, rt.g)));
			// Бруківка: бордюр — трохи темніша смуга ~0.15 м по краю вулиці з розривами: суцільна темна
			// лінія 0.3 м (×0.68) читалась намальованою обвідкою кожної дороги.
			float kerb = smoothstep(-0.4, -0.33, de) * rt.b * smoothstep(0.3, 0.6, vnoise(vec2(u * 0.6, side * 13.0 + 1.0)));
			// Асфальт -> бруківка: той самий шум, що й у текстурі вище, тож тон і текстура
			// міняються разом.
			float kp = smoothstep(0.25, 0.75, rt.r / max(rt.r + rt.b, 1e-4) + 0.35 * (fbm(p * 1.7 + 13.0) - 0.5));
			vec3 paved_alb = mix(ra, asph, kp);
			// Межа типів нерівна, ~1 м за шумом: дрібна октава ламає пряму лінію зміни переможця
			// в растрі.
			float g_k = smoothstep(0.3, 0.7, rt.g + 0.3 * (vnoise(p * 2.0 + 29.0) - 0.5) + 0.15 * (vnoise(p * 7.0 + 41.0) - 0.5));
			// Бордюр множиться після стиснення яскравості (як колії), інакше воно вдвічі зменшує
			// ΔL*.
			road_mul *= mix(1.0, 0.84, kerb * (1.0 - g_k));
			vec3 road_alb = mix(paved_alb, dirt_alb, g_k);
			// Калюжі в коліях — у дощ і при ґрунті MUD, на кожній колії свої (хеш комірки й боку),
			// тож не стають у ряд пунктиром. Сухо без MUD — жодної. На всю ширину в низинах — лише
			// в дощ.
			float wetr = clamp(weather_wetness, 0.0, 1.0);
			float rut_wet = max(wetr, mud_amount > 0.0 ? 0.7 : 0.0);
			float kc = floor(u / RUT_CELL_M);
			vec2 cid = vec2(kc, side * 7.0 + 3.0);
			float hl = mix(0.15, 1.25, hash12(cid + 23.0));
			float pc = (kc + 0.5) * RUT_CELL_M + (RUT_CELL_M * 0.5 - hl) * (hash12(cid + 11.0) * 2.0 - 1.0);
			// Півширина 0.18–0.28 м: калюжа ширша за дно колії (0.3 м); кінці круглі, край
			// нерівний.
			float pw = mix(0.18, 0.28, hash12(cid + 37.0));
			float pd = length(vec2(max(abs(u - pc) - max(hl - pw, 0.0), 0.0), track)) - pw
					+ 0.08 * (vnoise(vec2(u * 6.0, side * 5.0 + 2.0)) - 0.5);
			float present = step(hash12(cid), RUT_PUDDLE_P * rut_wet) * rt.g * straight;
			// Калюжа вужча за ~3 px на екрані (далекий зум) читається світлою рискою розмітки: гасимо.
			float px_mr = max(length(dpx), length(dpy)) * METRES_PER_TILE;
			float wide_k = smoothstep(1.5, 3.0, 2.0 * pw / max(px_mr, 1e-4));
			rut_pud = present * wide_k * (1.0 - smoothstep(-0.05 - fwv, fwv, pd));
			// Каламутний обідок ~0.3 м: мокрий темний ґрунт довкола води, край калюжі тоне в багні.
			rut_rim = present * (1.0 - smoothstep(0.0, 0.3 + fwv, pd)) * (1.0 - rut_pud);
			rut_pud = max(rut_pud, rt.g * wetr * smoothstep(0.7, 0.76, fbm(vec2(u * 0.12, rf.y * 0.15) + 21.0))
					* (1.0 - smoothstep(0.0, 0.3, rf.x + 0.3)));
			// Калюжі на мокрому асфальті й бруківці — у западинах і смугах коліс, де вода тягнеться
			// вздовж колії; групами з довгими сухими відрізками між ними (шум ~27 м), ~8–10 % дороги.
			// Обрис рве друга октава, край — м'який перехід ~0.3 м, а не вирізана пляма: круглі плями з
			// рівною заливкою й чітким краєм читались наліпками. Світові координати: смуги в (u, v)
			// розтягувались уздовж дороги в довгі хвилясті світлі розводи.
			// Лише в дощ і на твердому покритті: суха карта шуму калюж не рахує.
			if (wetr > 0.0 && rt.r + rt.b > 0.0) {
				float pcl = smoothstep(0.45, 0.62, fbm(p * 0.3 + 17.0));
				float pf = fbm(p * 2.0 + 61.0) + 0.15 * (fbm(p * 6.0 + 3.0) - 0.5) + 0.05 * (vnoise(p * 14.0) - 0.5)
						+ 0.18 * wheel - 0.15 * (1.0 - pcl);
				// fwidth у розгалуженні не визначений: крок fbm ~3 на клітинку × розмір пікселя.
				float pfw = 3.0 * max(length(dpx), length(dpy)) + 0.004;
				paved_sheen = wetr * (rt.r + rt.b) * smoothstep(0.70, 0.79 + pfw, pf);
				// Мокрий обідок: асфальт довкола калюжі темніший, сходить нанівець за ~0.3 м.
				paved_rim = wetr * (rt.r + rt.b) * smoothstep(0.63, 0.70, pf) * (1.0 - paved_sheen);
			}
			// Узбіччя: трава світліша й сіріша, з дрібними плямами ґрунту дороги.
			// На кінці лінії (вага розвилки, straight → 0) узбіччя гасне: обвиваючи глухий кінець ґрунтівки,
			// воно лягало круглою світло-сірою плямою без фактури.
			float vg = verge * (0.45 + 0.55 * vnoise(p * 9.0)) * straight;
			float speck = smoothstep(0.55, 0.75, vnoise(p * 23.0 + 4.0));
			// Під дощем узбіччя сіріє ледь і не світлішає: на розвилці узбіччя обох доріг накладались сірим серпанком.
			vec3 trampled = mix(alb, vec3(dot(alb, lw)) * mix(1.1, 1.0, wetr), mix(0.35, 0.15, wetr));
			alb = mix(alb, mix(trampled, ra, speck * 0.6), vg * 0.6);
			alb = mix(alb, road_alb, road_cov);
			// Узбіччя — вузький (~0.3 м) суцільний гравій із зерном ~0.4 м і чітким зовнішнім краєм: напівпрозора
			// смуга читалась асфальтом, крізь який видно траву, а широка гладка — бежевою стрічкою.
			float shoulder = rt.r * step(0.0, de) * (1.0 - smoothstep(0.09, 0.12, de + 0.04 * (vnoise(vec2(u * 0.9, side * 11.0)) - 0.5)));
			alb = mix(alb, gravel * vec3(1.05, 1.0, 0.9) * (0.7 + 0.6 * vnoise(p * 20.0)) * (0.85 + 0.3 * vnoise(p * 90.0)), shoulder * (1.0 - road_cov) * (0.85 + 0.15 * vnoise(p * 17.0)));
			nxy = mix(nxy, rn, road_cov);
			rough = mix(rough, mix(0.9, 0.72, rt.r + rt.b), road_cov);
		}
		// Запечене затінення рельєфу (TerrainHeight, B): низини й русло темніші, горби світліші.
		// Кривизна ізотропна, тож пологі хвилі рельєфу на полі видно саме через неї.
		// Улоговина темніша слабше (0.11) і тепліша — вологий бурий ґрунт: на 0.35 і навіть 0.22
		// голова яру й складки схилу лягали темною димною смугою.
		float concave = clamp(-curvature, 0.0, 1.0);
		alb *= (1.0 + 0.35 * max(curvature, 0.0) - 0.11 * concave) * mix(vec3(1.0), vec3(1.06, 0.98, 0.84), min(concave * 2.0, 1.0) * 0.6);
		// Запечене світло-тінь: 10° схил міняє яскравість на ~15 рівнів, на далекій відстані
		// слабшає. Світло-тінь — похідна висоти вздовж сонця, тобто спрямована: з повним
		// підсиленням на дрібних пологих хвилях вона дає паралельні діагональні смуги через усю
		// дошку (узгодженість орієнтації по вікнах 0.87). Тож повна сила — лише на схилах круче
		// ~10–22° (пагорб, берег), на пологому полі — ×1.
		float shade_k = mix(1.0, 9.0, smoothstep(0.18, 0.4, slope_tan));
		// Біля води тінь схилу не темніша за 0.8: круті береги улоговини ставка давали темну пляму ~4 м
		// за урізом, удвічі темнішу за траву. bank_map.r — клітинка води й ~1 клітинка довкола; улоговина
		// ширша, тож маска розширена ще на ~1.5 клітинки чотирма відліками (0.8 від повної).
		vec2 bsz = vec2(textureSize(bank_map, 0));
		vec2 buv = (p - map_origin + 0.5) / bsz;
		vec2 bank_s = texture(bank_map, buv).rg;
		vec2 bo = 1.5 / bsz;
		// Чотири додаткові відліки — лише там, де маска щось змінює: на сонці (корекція освітлення берега)
		// чи де тінь схилу глибша за -0.2 (межа біля води).
		float near_w = bank_s.r;
		if (dry_season || shade_k * hill_shade < -0.2) {
			near_w = max(near_w, 0.8 * max(max(texture(bank_map, buv + vec2(bo.x, 0.0)).r, texture(bank_map, buv - vec2(bo.x, 0.0)).r),
					max(texture(bank_map, buv + vec2(0.0, bo.y)).r, texture(bank_map, buv - vec2(0.0, bo.y)).r)));
		}
		alb *= 1.0 + clamp(shade_k * hill_shade, mix(-0.4, -0.2, near_w), 0.55) * (1.0 - 0.4 * smoothstep(25.0, 45.0, cam_dist));
		// Під сонцем берег улоговини ставка, повернутий від сонця, сам темнішає за Ламбертом до ~0.6 від
		// трави: біля води альбедо підняте на відношення освітлення рівного ґрунту до берега (до ×2.2).
		if (dry_season) {
			float lambert_fix = clamp(sun_dir.y / max(hill_shade + sun_dir.y, 0.05), 1.0, 2.2);
			alb *= mix(1.0, lambert_fix, near_w);
			// Світлий пісок чи дорога біля води після підсилення не вилітають у біле: альбедо не вище 0.6.
			alb = min(alb, vec3(0.6));
		}
		// Макро-варіація 20-50 м (fbm ~ 1/0.2 клітинки = 40 м): ламає повтор тону,
		// не міняючи масштаб дрібниць.
		float macro = fbm(p * 0.2 + 41.0) - 0.5;
		alb *= vec3(1.0 + 0.16 * macro, 1.0 + 0.13 * macro, 1.0 + 0.06 * macro);
		// З рельєфом пляма альбедо не перекриває хвилі землі: розкид яскравості стиснуто на ~45 %.
		if (use_height) {
			float l0 = max(dot(alb, vec3(0.299, 0.587, 0.114)), 0.004);
			alb *= pow(l0 / 0.05, -0.45);
		}
		alb *= mix(1.0, road_mul, road_cov);

		// Рельєф: стрімкий схил — голий ґрунт і камінь (шар HILL), а не трава; берег між урізом і
		// верхом — мокрий мул і галька (шар BANK), темніший за траву над ним. Змішування за
		// схилом і висотою, а не за клітинкою.
		vec3 alb_field = alb;
		float rock_dbg = 0.0;
		float rock_k = 0.0;
		float bar_w = 0.0;
		float bank_amt = 0.0;
		if (use_height) {
			// Крутий схил (камінь пагорба й берег): трипланарна проєкція на нерухомі світові
			// площини — XZ з вагою |n.y|^4, XY для граней уздовж Z (|n.z|^4), ZY — уздовж X
			// (|n.x|^4). Без повороту: проєкція вздовж схилу дає на обривах концентричні смуги
			// розтягнення.
			vec3 wn = normalize(mat3(INV_VIEW_MATRIX) * NORMAL);
			// bar_mask = 0.5 + 0.5 * bend: -1 коса (внутрішній), +1 підмитий берег (зовнішній).
			float bend_s = bar_mask * 2.0 - 1.0;
			float tx = pow(abs(wn.x), 4.0);
			float tz = pow(abs(wn.z), 4.0);
			float ty = pow(abs(wn.y), 4.0);
			float tsum = max(tx + ty + tz, 1e-4);
			vec2 pxy = world_pos.xy;
			vec2 pzy = world_pos.zy;
			// Камінь лише на схилах круче ~25° (tan 0.47): пологі верхи пагорба — трава, як у полі.
			float slope_amt = smoothstep(0.47, 0.62, slope_tan + 0.08 * (fbm(p * 1.3) - 0.5)) * (1.0 - road_cov);
			// Річковий берег не тягне щебінь пагорба: його тип дає вигин русла (нижче).
			slope_amt *= 1.0 - smoothstep(0.02, 0.25, shore_mask);
			bank_amt = smoothstep(0.08, 0.55, shore_mask + 0.2 * (fbm(p * 2.1 + 7.0) - 0.5));
			// Береговий шар (пласка нормаль, стеля яскравості) — лише в ~0.3 клітинки від урізу: далі за ним
			// широка маска близькості води робила траву й болото розмитим «аерографом».
			float run_b = max(world_pos.y - water_level, 0.0) / 0.125 / max(slope_tan, 0.05);
			bank_amt *= 1.0 - smoothstep(1.0, 2.4, run_b);
			if (slope_amt > 0.01) {
				// Камінці 10–40 см, а не плити: висота фото пагорба (stone_sample) вирішує, де камінь
				// визирає з трави, повільне поле rs лише густішає їх на крутішому схилі. Брили й
				// виходи скелі більші за ~0.4 м — 3D-пропи, не текстура.
				vec3 ra; vec2 rn; float rh;
				stone_sample(p, dpx, dpy, true, ra, rn, rh);
				float grass_bite = smoothstep(0.5, 0.8, vnoise(p * 14.0 + 5.3));
				float rs = slope_amt * 0.35 + 0.5 * (fbm(p * 1.6 + 71.0) - 0.5);
				float rx = rs + (rh - 0.5) * STONE_H - 0.3 * grass_bite;
				rock_k = smoothstep(0.45, 0.58, rx);
				// Камінь лежить у землі: кільце ~0.2–0.3 м на 30 % темніше там, де висота трохи нижча
				// за поріг (підніжжя), а на сонці ще й тінь — той самий камінь, зсунутий від сонця.
				float ring = smoothstep(0.3, 0.45, rx) * (1.0 - rock_k) * (1.0 - 0.6 * grass_bite);
				// Мокрий камінь: темна вузька кромка 1–2 px, де камінь входить у ґрунт.
				float rim_w = dry_season ? 0.0 : smoothstep(0.4, 0.45, rx) * (1.0 - rock_k);
				float shadow = 0.0;
				float h2;
				// Висота каменя ~0.1 м (2–3 px на z6) у бік сонця: дає світлий і тіньовий бік, а на сонці —
				// ще й тінь (точка в тіні, якщо камінь між нею й сонцем).
				vec2 so = normalize(sun_dir.xz + vec2(1e-4)) * (0.1 / METRES_PER_TILE);
				vec3 a2; vec2 n2;
				stone_sample(p + so, dpx, dpy, false, a2, n2, h2);
				if (dry_season) {
					shadow = 1.5 * smoothstep(0.45, 0.58, rs + (h2 - 0.5) * STONE_H) * (1.0 - rock_k);
				}
				// Тон каменю — відтінок ґрунту під ним (не синювато-сірий фото): камінь із того ж
				// схилу, лише трохи світліший. Усередині каменя яскравість гуляє ±20 % за власним
				// світлотінням фото, а нормаль фото проти сонця дає освітлений і тіньовий бік (±30 %);
				// на сонці освітлений бік тепліший, тіньовий — холодніший.
				vec3 lw3 = vec3(0.299, 0.587, 0.114);
				float pm = max(dot(textureLod(albedo_array, vec3(0.5, 0.5, float(HILL)), 14.0).rgb, lw3), 1e-3);
				float gl = max(dot(alb, lw3), 1e-3);
				float shade_in = clamp(dot(ra, lw3) / pm, 0.8, 1.2);
				vec3 sn = slope_to_world(rn * 2.0);
				float ndl = clamp((dot(sn, sun_dir) - sun_dir.y) * 3.0, -1.0, 1.0);
				// Бік каменя — з висоти: нижче до сонця — бік до сонця. Нормаль фото на 2–3 px каменя вже
				// розмита мипами й світлотіні не дає.
				ndl = clamp(ndl + (rh - h2) * STONE_H * 8.0, -1.0, 1.0);
				// Відтінок ґрунту приглушений (на траві камінь інакше став би зеленим); під хмарами — менше:
				// холодне небо робить нейтральний сірий синюватим поряд із теплим ґрунтом. Мокрий камінь:
				// освітлений бік ~1.3 ґрунту, тіньовий ~0.65, буруватий — темні рівні цятки читались синіми.
				vec3 sc = mix(vec3(gl), alb, dry_season ? 0.45 : 0.6) * (dry_season ? 1.12 : 1.0) * shade_in
						* (1.0 + 0.4 * ndl);
				sc *= dry_season ? mix(vec3(0.93, 0.96, 1.05), vec3(1.06, 1.0, 0.9), 0.5 + 0.5 * ndl) : vec3(1.03, 1.0, 0.93);
				alb = mix(alb * (1.0 - 0.3 * max(ring, shadow)) * (1.0 - 0.5 * rim_w), sc, rock_k);
				// Нормаль каменю з фото (×2): освітлений і тіньовий бік кожного каменя.
				nxy = mix(nxy, rn * (dry_season ? 2.0 : 1.6), rock_k);
			}
			if (bank_amt > 0.01) {
				vec3 ba; vec2 bn; float bh; float bc;
				sample_layer(BANK, p, dpx, dpy, vec2(0.0), detail_fade, ba, bn, bh, bc);
				if ((tx + tz) / tsum > 0.05) {
					vec3 sa; vec2 sn; float sh; float sc;
					vec3 sb; float sd;
					sample_layer(BANK, pxy, dxy_x, dxy_y, vec2(0.0), detail_fade, sa, sn, sh, sc);
					sample_layer(BANK, pzy, dzy_x, dzy_y, vec2(0.0), detail_fade, sb, sn, sh, sd);
					ba = (ba * ty + sa * tz + sb * tx) / tsum;
					bc = (bc * ty + sc * tz + sd * tx) / tsum;
				}
				float above_b = (world_pos.y - water_level) / 0.125;
				float contact = 1.0 - smoothstep(0.0, 0.7, above_b);
				vec3 lw = vec3(0.299, 0.587, 0.114);
				float fl = max(dot(alb, lw), 0.004);
				// Тип берега — з вигину русла: ґрунт лише на зовнішній стороні повороту (підмив),
				// смугою, що гуляє 0-2 м із хвилею ~20 м; на плесах і косах — низька трава й солома
				// до води.
				float outer = max(bend_s, 0.0);
				float band = smoothstep(0.25, 0.75, fbm(p * 0.35 + 13.0));
				float cut_amt = smoothstep(0.2, 0.7, outer) * band;
				// Ґрунт грані: L* 22-32, тепло-бурий; текстура лише дає дрібну пістрявість.
				float bl = max(dot(ba * bc, lw), 0.004);
				// Темніше й зеленіше за пісок (у тон прибережної трави), з дрібною варіацією тону.
				vec3 soil = fl * 0.7 * vec3(1.3, 1.0, 0.7) * clamp(bl / 0.05, 0.75, 1.2) * bc * (0.8 + 0.4 * vnoise(p * 14.0));
				alb = mix(alb, soil * (1.0 - 0.3 * contact), bank_amt * cut_amt);
				// Смуга сухої трави вздовж урізу: 0.05–0.4 клітинки за шумом; ширшає на внутрішніх
				// вигинах і зникає на підмитих берегах.
				float thr = mix(0.1, 0.85, smoothstep(0.2, 0.8, fbm(p * 0.45 + 3.0))) - 0.3 * max(-bend_s, 0.0) + 0.4 * outer;
				// Маска 0.2–0.4 клітинки розриває смугу, щоб вона не мала сталої ширини.
				float collar_break = smoothstep(0.25, 0.6, fbm(p * 3.0 + 21.0));
				float straw = smoothstep(thr, thr + 0.35, shore_mask) * (1.0 - cut_amt)
						* collar_break;
				alb = mix(alb, alb * vec3(1.12, 1.05, 0.8), straw * 0.6);
				// Біле на мокрому березі читається як відблиск: стеля ~L* 55 (Y ~ 0.1). На сухій карті — без стелі:
				// трава біля ставка, піднята проти Ламбертової тіні берега, під нею ставала рівною плямою.
				float lc = dot(alb, lw);
				alb *= mix(1.0, min(1.0, 0.1 / max(lc, 1e-4)), bank_amt * (dry_season ? 0.0 : 1.0));
				// Земля, мул і мокрий ґрунт шорсткі: сухим не нижче 0.75, мокра смуга — не глянець.
				rough = mix(rough, mix(0.9, 0.75, contact), bank_amt);
			}
			// Коса — півмісяць: верхній край гуляє шумом, до води — перехід від сухого до мокрого.
			bar_w = clamp(max(-bend_s, 0.0) * 3.0, 0.0, 1.0) * smoothstep(0.05 + 0.35 * fbm(p * 1.1 + 31.0), 0.5 + 0.2 * fbm(p * 1.1 + 31.0), shore_mask);
			// Дрібна нормаль не лягає на обриви: проєкція текстури плоска, а не вздовж схилу.
			nxy *= 1.0 - 0.8 * max(slope_amt * (1.0 - rock_k), bank_amt);
			rock_dbg = rock_k;
		}

		// Мокрість: темніше й глянцевіше. Калюжі — лише в коліях дороги й вікнах болота.
		float wet = clamp(weather_wetness, 0.0, 1.0);
		// Мокре темніше й насиченіше: земля ×0.66, ґрунтівка ×0.8, асфальт і бруківка ×0.75.
		alb *= mix(1.0, 0.66 + 0.14 * road_cov - 0.05 * road_cov * (rt.r + rt.b), wet);
		vec3 wl = vec3(dot(alb, vec3(0.299, 0.587, 0.114)));
		alb = max(mix(wl, alb, 1.0 + 0.25 * wet * (1.0 - road_cov)), vec3(0.0));
		// Мокра земля майже не глянцевіша (шорсткість 0.85): з нижчою зонд і небо додавали в
		// дифузне стільки ж, скільки забирало затемнення, і мокре виходило таким самим, як сухе.
		// Асфальт — до 0.5, не нижче: на 0.22 сонце проти камери робило з дороги хром.
		// Бруківка — до 0.75: її крупний рельєф на 0.45 ловив небо, і мокра бруківка світилась
		// синюватою смугою на ~25 рівнів яскравіше за траву поруч.
		float wet_paved_r = mix(0.75, 0.5, rt.r / max(rt.r + rt.b, 1e-4));
		rough = mix(rough, mix(0.85, wet_paved_r, road_cov * (rt.r + rt.b)), wet);
		// Мокрі смуги коліс — ледь глянцевіші (0.55): на 0.4 вони світились довгими світлими лініями.
		rough = mix(rough, 0.55, wet * wheel * road_cov);
		// Вода стоїть лише на рівному й у низинах: схил крутіший за ~5–7.5°, гребінь (кривизна > 0)
		// і клітинка пагорба (bank_map.g) — без калюж і вікон. Мокре затемнення там лишається.
		// Та сама формула — GroundSurface.puddle_gate (тест).
		vec2 water_mask = bank_s;
		float pud_gate = (1.0 - smoothstep(PUDDLE_SLOPE_LO, PUDDLE_SLOPE_HI, slope_tan))
				* (1.0 - smoothstep(0.0, 0.08, curvature)) * (1.0 - smoothstep(0.2, 0.6, water_mask.g));
		// Калюжі ґрунтівки: у коліях і на всю ширину в низинах (координати дороги, див. вище).
		// У колії вода збігає вже з 2–4°: ґрунтівка вниз по схилу пагорба мала світлі смужки калюж.
		float puddle = rut_pud * road_cov * pud_gate * (1.0 - smoothstep(0.035, 0.07, slope_tan));
		// Калюжі в западинах асфальту й бруківки (paved_sheen — їхня маска).
		puddle = max(puddle, paved_sheen * road_cov * pud_gate);
		// Вікна стоячої води в болоті 0.5–2 м (~10 % площі): темні, з відблиском неба. Лише в
		// мокрому вигляді: на сухій карті на їхньому місці — висохлий торф (сезонне макро болота),
		// а стояча вода під сонцем читалась би як калюжа без дощу.
		// Друга октава (~1.5 м) рве обрис: одне велике вікно з fbm на 5 м мало гілки, як силует птаха.
		float pool_f = fbm(p * 1.6 + 43.0) + 0.16 * (fbm(p * 5.0 + 7.0) - 0.5) + 0.08 * (vnoise(p * 9.0) - 0.5);
		// Біля річки (bank_map.r: клітинка води й ~1 клітинка довкола) — жодної стоячої води:
		// вікна там читались калюжами на березі.
		float bank_k = water_mask.r;
		// Вода лише там, де болото переважає: у суміші з лісом чи кущами пів-вага вікна давала сіру
		// плівку поверх крон.
		float pool_wet = smoothstep(0.6, 0.9, marsh_w) * smoothstep(0.1, 0.35, weather_wetness) * (1.0 - smoothstep(0.2, 0.6, bank_k)) * pud_gate;
		float pool = pool_wet * (1.0 - smoothstep(0.27, 0.33, pool_f));
		// Середина вікна відбиває більше неба (до ~40 % сірого), край — оливковий: рівна пляма читалась
		// плямою на ґрунті, а небо на всю ширину давало сірий обідок на переході.
		float pool_ctr = 1.0 - smoothstep(0.12, 0.27, pool_f);
		// Обідок ~0.3–0.5 м: темний мокрий мул (~0.35 від трави поруч), у який вода м'яко переходить.
		float pool_rim = pool_wet * (1.0 - smoothstep(0.31, 0.45, pool_f)) * (1.0 - pool);
		alb *= mix(1.0, 0.35, pool_rim) * mix(vec3(1.0), vec3(0.95, 0.97, 0.85), pool_rim);
		puddle = max(puddle, pool);
		alb *= mix(1.0, 0.55, puddle) * mix(1.0, 0.6, max(rut_rim * road_cov, pool * 0.5)) * (1.0 - 0.25 * paved_rim * road_cov);
		// Вікно болота — непрозора оливково-бура торф'яна вода (~40 на екрані) під відблиском неба, а не
		// затемнена трава: крізь множник під водою проступали купини, і вікно читалось сірою плівкою.
		alb = mix(alb, vec3(0.075, 0.058, 0.028), pool);
		// Мокра смуга берега: вага води росте ~3.4 на клітинку біля урізу (0.5), тож
		// 0.1 -> 0.5 — це ~1 м суші перед водою; найтемніша й найглянцевіша при воді.
		// З рельєфом смуга йде за ґрунтом, а не за клітинкою: мокре там, де земля в межах 0.4 м
		// над рівнем води й поруч є вода (маска води з карти висот).
		float shore = 0.0;
		if (use_height) {
			float above_m = (world_pos.y - water_level) / 0.125;
			// Смуга — за горизонталлю (висота / тангенс схилу): 0.2-0.5 м упоперек і на косі, і на
			// обриві; у каламутного ставка — 0.08–0.2 м, бо ширша лягала темним розмитим ореолом.
			float run_m = above_m / max(slope_tan, 0.05);
			shore = (1.0 - smoothstep(mix(0.2, 0.08, clamp(water_murk, 0.0, 1.0)), mix(0.5, 0.2, clamp(water_murk, 0.0, 1.0)), run_m)) * smoothstep(0.03, 0.12, shore_mask);
		}
		alb *= mix(1.0, 0.6, shore);
		// Темна мокра лінія просто в урізі (2-4 px на близькому зумі), а не лише розмита смуга.
		if (use_height) {
			float edge_m = (world_pos.y - water_level) / 0.125 / max(slope_tan, 0.05);
			alb *= mix(1.0, 0.65, (1.0 - smoothstep(0.04, 0.14, edge_m)) * smoothstep(0.03, 0.12, shore_mask));
		}
		// Мокрий берег не дзеркало: шорсткість лише до 0.5.
		// На сухій карті смуга урізу не блищить: відблиск сонця там читався мокрим.
		rough = mix(rough, dry_season ? 0.9 : 0.5, shore);
		// Дощ на воді — ті самі кола, що й на річці, плюс повільна брижа від вітру: небо у воді
		// тоді не рівна пляма, а йде градієнтом і ворушиться.
		float rv = puddle > 0.0 ? rv_all : 0.0;
		vec2 wind = vec2(vnoise(p * 6.0 + vec2(TIME * 0.35, 0.0)), vnoise(p * 6.0 + vec2(17.0, TIME * 0.3))) - 0.5;
		vec2 ripple = puddle > 0.0 ? rain_ripples(p, TIME) * (1.2 + 1.5 * pool) * wet * rv + wind * 0.7 * pool : vec2(0.0);
		// Калюжа й вікно болота матові для світла: небо в них — лише EMISSION з обмеженою часткою
		// нижче. Глянець через звичайне освітлення додавав зонд і сонце — біле дзеркало, світлий
		// обвід по краю й білі цятки на колах дощу.
		rough = mix(rough, 1.0, puddle);
		nxy = mix(nxy, ripple, puddle);
		// Бризки від крапель на землі й дорозі: у клітинці 0.5 м раз на 2.5 с на ~0.12 с світлішає
		// пляма ~10 см (у 40 % клітинок). Лише в дощ; здалеку, коли клітинка менша за ~4 px,
		// гаснуть — інакше мерехтіли б окремими пікселями.
		if (wet > 0.0) {
			vec2 sq = p * 16.0;
			vec2 sc = floor(sq);
			float sh = hash12(sc + 3.0);
			float st = fract(TIME * 0.4 + sh);
			vec2 so = vec2(hash12(sc + 7.0), hash12(sc + 13.0)) * 0.6 + 0.2;
			float splash = step(0.6, hash12(sc + 19.0)) * (1.0 - smoothstep(0.0, 0.05, st))
					* (1.0 - smoothstep(0.1, 0.22, length(fract(sq) - so)))
					* (1.0 - smoothstep(0.12, 0.25, length(16.0 * (abs(dpx) + abs(dpy)))));
			// На воді — кола, не бризки: світла цятка на темному вікні читалась білою крапкою.
			alb = mix(alb, alb * 1.6 + 0.015, splash * wet * (1.0 - puddle));
		}
		// Мокрий асфальт відбиває ~3 % неба: шорсткість 0.5 під похмурим небом сама відблиску майже
		// не дає; небо видно в калюжах (puddle).
		float mirror = max(max(max(puddle * mix(2.5, 5.0, paved_sheen * road_cov), pool * 6.0), shore * 0.12),
				wet * road_cov * (rt.r + 0.5 * rt.b) * 0.03);
		vec3 refl = vec3(0.0);
		if (mirror > 0.0 && sky_reflection_gain > 0.0) {
			// Як overcast_reflection (F0 0.1), але частку неба обмежено PUDDLE_SKY_MAX: на скісному
			// куті вага 2.5 інакше дає майже біле дзеркало.
			vec3 nw = slope_to_world(ripple);
			vec3 vw = normalize(CAMERA_POSITION_WORLD - world_pos);
			float fr = 0.1 + 0.9 * pow(1.0 - clamp(dot(nw, vw), 0.0, 1.0), 3.0);
			float sky_cap = mix(mix(PUDDLE_SKY_MAX, PAVED_PUDDLE_SKY, paved_sheen * road_cov), mix(POOL_SKY_MAX, POOL_SKY_CENTRE, pool_ctr), pool);
			refl = overcast_sky_at(reflect(-vw, nw), TIME, sky_clear) * min(fr * mirror, sky_cap);
			float murk_k = clamp(water_murk, 0.0, 1.0);
			refl = mix(refl, vec3(dot(refl, vec3(0.2126, 0.7152, 0.0722))) * vec3(0.92, 0.98, 1.02),
					murk_k) * (1.0 - 0.8 * murk_k) * (1.0 - 0.35 * pool);
			// Калюжа на дорозі відбиває нейтральне сіре небо, без синього відтінку.
			refl = mix(refl, vec3(dot(refl, vec3(0.2126, 0.7152, 0.0722))), 0.85 * paved_sheen * road_cov);
		}

		// Коса (внутрішній берег повороту) — останнім, від яскравості поля поруч (з тією ж
		// мокрістю): світліша й тепліша за поле, а не лише менш темна, ніж берег.
		if (bar_w > 0.0) {
			// Тон ближчий до прибережної трави, з дрібною варіацією яскравості: рівний тон
			// читається як глина.
			// Яскравість — з поточного альбедо (фото з деталлю), а не з рівного поля: інакше коса без фактури
			// під дощем лягала блідими сіро-білими плямами, як іній. Мокра — темніша (×0.6) і буріша.
			vec3 sand = dot(alb, vec3(0.299, 0.587, 0.114)) * mix(1.0, 0.6, wet) * mix(mix(SAND_TINT, vec3(1.12, 1.05, 0.8), 0.5), vec3(1.15, 0.98, 0.74), wet) * (1.0 - 0.2 * shore_mask);
			sand *= 0.78 + 0.44 * vnoise(p * 13.0) + 0.1 * (vnoise(p * 41.0) - 0.5);
			alb = mix(alb, sand, bar_w * 0.85);
		}

		float scar_dark = 0.0;
		if (has_scars) {
			vec2 suv = (p + 0.5) / scar_size;
			// За дошкою — нуль: інакше край текстури тягнеться смугою через усе кільце.
			float inside = step(0.0, suv.x) * step(0.0, suv.y) * step(suv.x, 1.0) * step(suv.y, 1.0);
			vec4 sc = texture(scar_map, suv) * texture(scar_seen, suv).r * inside;
			// Ядро плями L* 10–15 на екрані: альбедо майже чорне, бо імла й відблиск неба
			// поверх нього самі піднімають його на 6–8 L*. Попіл — сірі цятки L* 45–55.
			scar_dark = sc.r;
			alb = mix(alb, vec3(0.004, 0.0037, 0.0034), sc.r * 0.95);
			alb = mix(alb, vec3(0.16, 0.155, 0.15), sc.a * 0.6);
			rough = mix(rough, 1.0, sc.r);
			refl *= 1.0 - sc.r;
		}
		// Тінь хмари: плями ~10 клітинок, пливуть ~0.5 клітинки/с (4 м/с), тож пляма минає точку
		// за 15–20 с. Край вузький (0.52–0.64), щоб тінь читалась плямою, а не загальною рябизною.
		if (cloud_shadow_strength > 0.0) {
			float cloud = smoothstep(0.52, 0.64, fbm(p * 0.04 + TIME * vec2(0.02, 0.008)));
			alb *= 1.0 - cloud_shadow_strength * cloud;
		}

		FOG = vec4(0.0);
		if (surround) {
			alb = surround_grade(alb, haze.a);
			refl = surround_grade(refl, haze.a);
			FOG = surround_fog(haze, line_a);
		}
		ALBEDO = alb;
		EMISSION = refl * sky_reflection_gain;
		if (debug_view > 0) {
			int c = top[0] + 1;
			vec3 dc = vec3(float(c & 1), float((c >> 1) & 1), float((c >> 2) & 1));
			ALBEDO = vec3(0.0);
			EMISSION = debug_view == 1 ? dc : vec3(debug_view == 2 ? road_cov : rock_dbg);
			rough = 1.0;
		}
		// Камінь матовий: мокрий відблиск сірого неба на крутих нормалях фарбував його в синій, а на
		// низькій шорсткості давав білі іскри в 1 px.
		ROUGHNESS = mix(rough, 1.0, rock_dbg);
		// Колії й смуги коліс темніші й у відбитті: інакше постійний відблиск неба (F0 0.04 при
		// альбедо ~0.06) вдвічі зменшує їхній ΔL* на екрані.
		// Вікна болота під ясним небом віддзеркалювали б синє небо зонда; каламутна стояча вода —
		// темна, тож її дзеркало слабшає з `water_murk` (на Річці 0, множник рівно 1).
		// Мокрий асфальт поза калюжами — 0.4 дзеркала: зонд на шорсткості 0.5 освітлював його до сухого тону.
		SPECULAR = mix(0.5, 0.2, bank_amt) * mix(1.0, road_mul, road_cov) * (1.0 - puddle) * mix(1.0, 0.4, wet * road_cov * (rt.r + rt.b))
				* (1.0 - 0.8 * pool * clamp(water_murk, 0.0, 1.0)) * (1.0 - 0.8 * rock_dbg) * (1.0 - 0.8 * scar_dark);
		NORMAL_MAP = vec3(nxy * 0.5 + 0.5, 1.0);
	}
}
