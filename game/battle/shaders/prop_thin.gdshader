// Огорожі (PropLayer): тонкі панелі, видимі з обох боків. Нормаль імпортованої панелі лежить
// горизонтально, тож на сонці освітлено лише один бік, а другий бере тільки синє небо й чорніє.
// Нормаль нахилено до неба: обидва боки освітлені майже як дерево на сонці, тіньовий — ~0.83.
shader_type spatial;
render_mode blend_mix, cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform bool use_vertex_color = false;
uniform float alpha_cut = 0.0;
uniform float roughness = 0.9;
uniform float metallic = 0.0;
// Частка неба в нормалі: 0 — нормаль ассета, 1 — освітлення як у горизонтальної площини.
uniform float sky_bend = 0.65;

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
// Тепліше за нейтраль: під сірим небом Річки нейтральне дерево виходило холодним (B ≥ R).
const vec3 WEATHERED = vec3(1.14, 0.98, 0.78);

varying float base_h;

void vertex() {
	base_h = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y - MODEL_MATRIX[3].y;
}

void fragment() {
	vec4 tex = texture(albedo_tex, UV) * albedo_color;
	if (use_vertex_color) {
		tex *= COLOR;
	}
	// Здалеку міпмапи усереднюють альфу тонких штакетин нижче порогу, і бік кільця зникав: поріг
	// знижується з рівнем міпмапи, щоб покриття лишалось.
	float cut = alpha_cut * clamp(1.0 - 0.3 * textureQueryLod(albedo_tex, UV).y, 0.15, 1.0);
	if (alpha_cut > 0.0 && tex.a < cut) {
		discard;
	}
	vec3 albedo = tex.rgb;
	// Яскравість не вища за VALUE_CAP: світлі шапки стовпчиків і свіжа фарба на зумі 14 читались
	// білими лініями інтерфейсу; вивітрене дерево й оцинковка — не світліші.
	float value = max(albedo.r, max(albedo.g, albedo.b));
	albedo *= min(1.0, VALUE_CAP / max(value, 1e-4));
	// Сіро-бурий вивітреного дерева: рожеві й бузкові відтінки фарби ассета на кадрі читались чужими.
	albedo = mix(albedo, dot(albedo, vec3(0.2126, 0.7152, 0.0722)) * WEATHERED, 0.6);
	float wet = smoothstep(0.0, WET_FULL, weather_wetness);
	if (wet > 0.0) {
		float luma = dot(albedo, vec3(0.2126, 0.7152, 0.0722));
		// Лише на чверть до сіро-бежевого: знебарвлений штакетник читався бетонною панеллю.
		albedo = mix(albedo, luma * WET_TONE, wet * 0.25) * mix(1.0, WET_DARK, wet);
		albedo *= mix(1.0, DIRT, wet * (1.0 - smoothstep(0.0, DIRT_H, base_h)));
	}
	ALBEDO = albedo;
	// Мокра фарбована бляха — м'який полиск, не матова картка.
	ROUGHNESS = mix(roughness, WET_ROUGHNESS, wet);
	METALLIC = metallic;
	vec3 up = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	// Тильний бік рушій сам перевертає (cull_disabled); нахил до неба вирівнює обидва.
	NORMAL = normalize(mix(NORMAL, up, sky_bend));
}
