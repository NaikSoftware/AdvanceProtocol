// Огорожі (PropLayer): тонкі панелі, видимі з обох боків. Нормаль імпортованої панелі лежить
// горизонтально, тож на сонці освітлено лише один бік, а другий бере тільки синє небо й чорніє.
// Нормаль нахилено до неба: обидва боки освітлені майже як дерево на сонці, тіньовий — ~0.83.
shader_type spatial;
// alpha_to_coverage: край штакетини на зумі розмивається покриттям MSAA, а не відсікається ступінчасто (цятки).
render_mode cull_disabled, depth_draw_opaque, alpha_to_coverage;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform bool use_vertex_color = false;
uniform float alpha_cut = 0.0;
uniform float roughness = 0.9;
uniform float metallic = 0.0;
// Частка неба в нормалі: 0 — нормаль ассета, 1 — освітлення як у горизонтальної площини.
uniform float sky_bend = 0.65;
// Висота верху секції в моделі (множиться на масштаб екземпляра): верхні ~0.02 затемнені, щоб шапки не читались білим пунктиром.
uniform float top_local = 1000.0;
// Картка з кількома видами паркану (смуги атласу згори вниз, вид — floor(UV.y · kinds)): лишається вид екземпляра
// (INSTANCE_CUSTOM.r), решта вершин стягується в точку. 0 — звичайна модель.
uniform int kinds = 0;
// Крок повтору текстури вздовж секції, м (клітинка — 8 м): від початку секції, хоч би яка вона завдовжки.
uniform float tile_m = 2.5;
uniform float kind_top[8];

// Мокрість карти (WeatherRig): на мокрій River панель темніша, трохи приглушена й з брудом унизу —
// яскрава огорожа світилась би, як пофарбована щойно.
global uniform float weather_wetness;
const float WET_FULL = 0.5;
const float WET_DARK = 0.75;
const vec3 WET_TONE = vec3(1.06, 0.97, 0.85);
// Бруд біля землі: ~0.5 м (клітинка — 8 м).
const float DIRT_H = 0.06;
const float DIRT = 0.6;
const float WET_ROUGHNESS = 0.4;
// ~0.30 у sRGB (≈ 76 із 255) — ~0.072 лінійно: паркан трохи світліший за ґрунт, не біла лінія.
const float VALUE_CAP = 0.072;
// Уся огорожа на чверть темніша за дерево ассета: штакетини над темним ґрунтом не світліші за нього, без блідої сітки цяток.
const float FENCE_DARK = 0.75;
// Здалеку (міпмапа ≥ FAR_MIP) рисунок штакетин і шапок стовпчиків — рівний темніший тон, без пунктиру.
const float FAR_MIP = 3.0;
const float FAR_DARK = 0.8;
// Нижній брус (до BASE_H, ~0.3 м) темніший: лінія паркану тримається на темному ґрунті й тоді, коли штакетини
// здалеку тоншають.
const float BASE_H = 0.04;
const float BASE_DARK = 0.6;
// Здалеку покриття тонких штакетин росте з рівнем міпмапи: alpha-to-coverage інакше розріджує лінію до невидимої.
const float FAR_ALPHA = 0.12;
// Паркани дворів (kinds > 0): вид читається кольором так само, як формою — іржава бляха, кора, оцинковка, цегла.
// Їм — вища межа яскравості (оцинкована сітка світліша за дерево) і лише легке знебарвлення; затемнення й тон здалеку
// зберігають відтінок, а не зводять усе до сіро-бурого.
const float GAIN_PICKET = 2.4;
const float GAIN_SHEET = 1.6;
const float GAIN_SLAT = 1.6;
const float YARD_VALUE_CAP = 0.35;
const float YARD_DESAT = 0.05;
// Тепліше за нейтраль: під сірим небом Річки нейтральне дерево виходило холодним (B ≥ R).
const vec3 WEATHERED = vec3(1.14, 0.98, 0.78);

varying float base_h;
varying float top_h;
varying float kind_v;

void vertex() {
	float top = top_local;
	if (kinds > 0) {
		int kind = int(floor(UV.y * float(kinds)));
		kind_v = float(kind);
		top = kind_top[clamp(kind, 0, 7)];
		UV.x = (VERTEX.x + 0.5) * length(MODEL_MATRIX[0].xyz) * 8.0 / tile_m;
		if (abs(float(kind) - INSTANCE_CUSTOM.r) > 0.5) {
			VERTEX = vec3(0.0);
		}
	}
	base_h = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y - MODEL_MATRIX[3].y;
	top_h = top * length(MODEL_MATRIX[1].xyz);
}

// Рівень міпмапи з похідних UV: textureQueryLod не компілюється в gl_compatibility.
float mip_level(sampler2D t, vec2 uv) {
	vec2 d = uv * vec2(textureSize(t, 0));
	return max(0.5 * log2(max(max(dot(dFdx(d), dFdx(d)), dot(dFdy(d), dFdy(d))), 1e-8)), 0.0);
}

void fragment() {
	vec4 tex = texture(albedo_tex, UV) * albedo_color;
	if (use_vertex_color) {
		tex *= COLOR;
	}
	// Здалеку міпмапи усереднюють альфу тонких штакетин нижче порогу, і бік кільця зникав: поріг
	// знижується з рівнем міпмапи, щоб покриття лишалось.
	float mip = mip_level(albedo_tex, UV);
	float cut = alpha_cut * clamp(1.0 - 0.3 * mip, 0.15, 1.0);
	if (alpha_cut > 0.0 && tex.a < cut) {
		discard;
	}
	vec3 albedo = tex.rgb;
	bool yard = kinds > 0;
	// Яскравість не вища за VALUE_CAP: світлі шапки стовпчиків і свіжа фарба на зумі 14 читались
	// білими лініями інтерфейсу; вивітрене дерево й оцинковка — не світліші.
	float value = max(albedo.r, max(albedo.g, albedo.b));
	albedo *= min(1.0, (yard ? YARD_VALUE_CAP : VALUE_CAP) / max(value, 1e-4));
	// Рабиця (вид 2 атласу): суцільні частини (стовпи, труба зверху: покриття ~1) світяться білим на тлі напівпрозорого дроту
	// й темного асфальту, хоч альбедо в них не світліше за дріт, — вдвічі темніше; дріт, чиє покриття розмите міпмапою, не чіпаємо.
	if (yard && abs(kind_v - 2.0) < 0.5) {
		albedo *= mix(1.0, 0.5, smoothstep(0.85, 1.0, tex.a));
	}
	float cap = smoothstep(top_h - 0.03, top_h - 0.01, base_h);
	albedo *= mix(1.0, 0.45, cap);
	// Сіро-бурий вивітреного дерева: рожеві й бузкові відтінки фарби ассета на кадрі читались чужими.
	albedo = mix(albedo, dot(albedo, vec3(0.2126, 0.7152, 0.0722)) * WEATHERED, yard ? YARD_DESAT : 0.6);
	albedo *= (yard ? 1.0 : FENCE_DARK) * mix(BASE_DARK, 1.0, smoothstep(BASE_H * 0.5, BASE_H, base_h));
	float far = smoothstep(1.0, FAR_MIP, mip);
	vec3 far_tone = yard ? albedo * FAR_DARK : vec3(dot(albedo, vec3(0.2126, 0.7152, 0.0722))) * WEATHERED * FAR_DARK;
	albedo = mix(albedo, far_tone, far);
	float wet = smoothstep(0.0, WET_FULL, weather_wetness);
	// Штахетник (вид 0), профнастил (1) і дошки (4) на мокрій карті читались майже чорними (L 24–47 при ґрунті 71): мокрий підйом;
	// ті самі числа в prop_gate (GAIN_*), щоб ворота лишались у тоні.
	if (yard) {
		float gain = abs(kind_v - 0.0) < 0.5 ? GAIN_PICKET : (abs(kind_v - 1.0) < 0.5 ? GAIN_SHEET : (abs(kind_v - 4.0) < 0.5 ? GAIN_SLAT : 1.0));
		albedo *= mix(1.0, gain, wet);
	}
	if (wet > 0.0) {
		float luma = dot(albedo, vec3(0.2126, 0.7152, 0.0722));
		// Лише на чверть до сіро-бежевого: знебарвлений штакетник читався бетонною панеллю.
		albedo = mix(albedo, luma * WET_TONE, wet * (yard ? 0.08 : 0.25)) * mix(1.0, WET_DARK, wet);
		albedo *= mix(1.0, DIRT, wet * (1.0 - smoothstep(0.0, DIRT_H, base_h)));
	}
	ALBEDO = albedo;
	ALPHA = mix(1.0, clamp(tex.a * (1.0 + FAR_ALPHA * mip), 0.0, 1.0), step(0.0001, alpha_cut));
	// Мокра фарбована бляха — м'який полиск, не матова картка.
	// Шапка секції матова: мокрий полиск горішніх граней блищав білими цятками вздовж огорожі.
	ROUGHNESS = mix(mix(roughness, WET_ROUGHNESS, wet), 1.0, cap);
	METALLIC = metallic;
	vec3 up = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	// Тильний бік рушій сам перевертає (cull_disabled); нахил до неба вирівнює обидва.
	NORMAL = normalize(mix(NORMAL, up, sky_bend));
}
