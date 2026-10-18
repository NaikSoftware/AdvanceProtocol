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
// Клітинка, що відповідає пікселю (0, 0) kind_map (від'ємна при відступі).
uniform vec2 map_origin = vec2(0.0);
uniform int layer_for_kind[10];
uniform sampler2DArray albedo_array : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray normal_array : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float mud_amount = 0.0;

// Шари з GroundSurface.TEX_LAYERS.
const int ROAD = 0;
const int FIELD = 1;
const int HILL = 3;
const int FOREST = 2;
const int MUD = 5;
// Шар берега (русла) — під WATER, BRIDGE і BRIDGE_DESTROYED (GroundSurface.TEX_LAYER_FOR_KIND).
const int BANK = 7;

// Підсилення альбедо шару: лісова підстилка з Task 4 майже чорна (середнє 55
// проти 75 у поля), а під деревами вона мусить читатись як бура листва.
vec3 layer_gain(int layer) {
	return layer == FOREST ? vec3(1.45, 1.35, 1.2) : vec3(1.0);
}

// Один повтор текстури на стільки клітинок.
uniform float tiles_per_repeat = 3.0;

varying vec3 world_pos;

#include "res://game/battle/shaders/terrain_noise.gdshaderinc"

int layer_at(ivec2 px, ivec2 size) {
	ivec2 c = clamp(px, ivec2(0), size - 1);
	int kind = int(texelFetch(kind_map, c, 0).r * 255.0 + 0.5);
	return layer_for_kind[clamp(kind, 0, 9)];
}

// Семпл шару без видимого повтору: регіони з різним зсувом і поворотом UV,
// межа між ними — плавна, керована шумом і контрастом самої текстури.
void sample_layer(int layer, vec2 uv, vec2 dx, vec2 dy, float k, out vec3 alb, out vec2 nxy) {
	// Багно семплюємо вдвічі крупніше: його колії — найпомітніший повтор.
	float s = layer == MUD ? 0.5 : 1.0;
	uv *= s;
	dx *= s;
	dy *= s;
	float l = k * 14.0;
	float ia = floor(l);
	float f = fract(l);
	vec3 ab[2];
	vec2 nb[2];
	for (int j = 0; j < 2; j++) {
		float idx = ia + float(j);
		vec2 off = sin(vec2(3.0, 7.0) * idx);
		float a = idx * 2.399;
		mat2 r = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a)));
		vec3 c = vec3(r * uv + off, float(layer));
		ab[j] = textureGrad(albedo_array, c, r * dx, r * dy).rgb;
		vec2 n = textureGrad(normal_array, c, r * dx, r * dy).rg * 2.0 - 1.0;
		// Повернули UV — повертаємо й нормаль назад у простір меша. Не transpose(r):
		// бінормаль PlaneMesh дивиться в −Z, а v росте в +Z, тож F·rᵀ·F = r.
		nb[j] = r * n;
	}
	float t = smoothstep(0.2, 0.8, f - 0.1 * dot(ab[0] - ab[1], vec3(1.0)));
	alb = mix(ab[0], ab[1], t) * layer_gain(layer);
	nxy = mix(nb[0], nb[1], t);
}

void vertex() {
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
		road_w += L[i] == ROAD ? W[i] : 0.0;
		bank_w += L[i] == BANK ? W[i] : 0.0;
		soil_w += (L[i] == FIELD || L[i] == HILL) ? W[i] : 0.0;
	}
	// Плями, а не напівпрозорий шар: півпрозоре багно поверх трави читається як
	// «привид» текстури, а не як розкисла земля.
	// mud_amount — частка поля під багном далеко від доріг; біля дороги — на 0.2
	// більше. Поріг — квантиль fbm (0.45 ≈ 30 %, 0.537 ≈ 55 %), виміряний на карті.
	float near = 0.0;
	near += layer_at(ivec2(floor(g + vec2(1.5, 0.0) + 0.5)), size) == ROAD ? 0.25 : 0.0;
	near += layer_at(ivec2(floor(g - vec2(1.5, 0.0) + 0.5)), size) == ROAD ? 0.25 : 0.0;
	near += layer_at(ivec2(floor(g + vec2(0.0, 1.5) + 0.5)), size) == ROAD ? 0.25 : 0.0;
	near += layer_at(ivec2(floor(g - vec2(0.0, 1.5) + 0.5)), size) == ROAD ? 0.25 : 0.0;
	near = max(near, road_w);
	float cover = mud_amount + 0.2 * near;
	float thr = 0.45 + (cover - 0.3) * 0.35;
	float mud_soil = mud_amount > 0.0
			? 1.0 - smoothstep(thr - 0.02, thr + 0.02, fbm(p * 0.35 + 3.1))
			: 0.0;
	float verge = 4.0 * road_w * (1.0 - road_w) * 0.7;
	for (int i = 0; i < 4; i++) {
		if (L[i] == FIELD || L[i] == HILL) {
			W[i] *= 1.0 - mud_soil;
		}
		if (L[i] != ROAD) {
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

	vec2 uv = p / tiles_per_repeat;
	vec2 dx = dFdx(uv);
	vec2 dy = dFdy(uv);
	float k = fbm(p * 0.13);
	vec3 A[5];
	vec2 N[5];
	float H[5];
	float hmax = -1.0;
	for (int i = 0; i < 5; i++) {
		H[i] = -1.0;
		if (W[i] > 0.002) {
			sample_layer(L[i], uv, dx, dy, k + float(L[i]) * 0.37, A[i], N[i]);
			// Висотне змішування: на межі першим проступає світліше (камінь,
			// пучок трави), тож перехід рваний за самою текстурою, а не розмитий.
			H[i] = W[i] + dot(A[i], vec3(0.333)) * 0.6;
			hmax = max(hmax, H[i]);
		}
	}
	vec3 alb = vec3(0.0);
	vec2 nxy = vec2(0.0);
	float rough = 0.0;
	float wsum = 0.0;
	for (int i = 0; i < 5; i++) {
		float w = max(H[i] - (hmax - 0.18), 0.0);
		if (w > 0.0) {
			alb += A[i] * w;
			nxy += N[i] * w;
			rough += (L[i] == ROAD ? 0.75 : 0.92) * w;
			wsum += w;
		}
	}
	alb /= wsum;
	nxy /= wsum;
	rough /= wsum;

	// Мокрість: темніше й глянцевіше. Калюжі — у низинах дороги й багна,
	// низина — темна ділянка текстури, тож край калюжі йде за рельєфом.
	float wet = clamp(weather_wetness, 0.0, 1.0);
	float lum = dot(alb, vec3(0.299, 0.587, 0.114));
	alb *= mix(1.0, 0.75, wet);
	rough = mix(rough, 0.4, wet);
	float puddle_ground = clamp((road_w + W[4]) * 1.5, 0.0, 1.0);
	float pn = fbm(p * 0.35 + 11.0) + (lum - 0.25) * 0.35;
	float pthr = wet * 0.42;
	float puddle = (1.0 - smoothstep(pthr - 0.03, pthr + 0.02, pn)) * puddle_ground;
	alb *= mix(1.0, 0.55, puddle);
	// Мокра смуга берега: вага води росте ~3.4 на клітинку біля урізу (0.5), тож
	// 0.1 -> 0.5 — це ~1 м суші перед водою; найтемніша й найглянцевіша при воді.
	float shore = smoothstep(0.1, 0.45, bank_w);
	alb *= mix(1.0, 0.6, shore);
	rough = mix(rough, 0.15, shore);
	// Гладка калюжа відбиває зонд BoardView звичайним шляхом освітлення — без SSR.
	// Дощ на ній — ті самі кола, що й на річці. Підлога шорсткості 0.12: на 0.05
	// сонце на брижі давало однопіксельні іскри.
	float rv = puddle > 0.0 ? ripple_visibility(p) : 0.0;
	vec2 ripple = puddle > 0.0 ? rain_ripples(p, TIME) * 1.2 * wet * rv : vec2(0.0);
	rough = mix(rough, 0.12 + 0.1 * wet * (1.0 - rv), puddle);
	nxy = mix(nxy, ripple, puddle);
	float mirror = max(puddle, shore * 0.5);
	vec3 refl = mirror > 0.0 && sky_reflection_gain > 0.0
			? overcast_reflection(slope_to_world(ripple), normalize(CAMERA_POSITION_WORLD - world_pos), 0.03, 3.0, TIME)
			: vec3(0.0);

	if (cloud_shadow_strength > 0.0) {
		float cloud = smoothstep(0.45, 0.7, fbm(p * 0.04 + TIME * vec2(0.02, 0.008)));
		alb *= 1.0 - cloud_shadow_strength * cloud;
	}

	ALBEDO = alb;
	EMISSION = refl * mirror * sky_reflection_gain;
	ROUGHNESS = rough;
	NORMAL_MAP = vec3(nxy * 0.5 + 0.5, 1.0);
}
