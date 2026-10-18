// Спільний шум землі й води (Phase 5a): берег річки мусить лягти рівно на ту
// саму рвану межу видів, що й текстура берега в ground.gdshader.

// Амплітуда збурення межі видів, у клітинках.
const float BORDER_JITTER = 0.45;
// Напівширина переходу між видами, у частках клітинки.
const float BORDER_SOFTNESS = 0.22;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
			mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	return 0.5 * vnoise(p) + 0.3 * vnoise(p * 2.03 + 17.1) + 0.2 * vnoise(p * 4.01 + 31.7);
}

// Межа видів: великі хвилі плюс дрібна рваність.
vec2 border_warp(vec2 p) {
	return p + (vec2(fbm(p * 0.8), fbm(p * 0.8 + vec2(5.2, 1.3))) - 0.5) * 2.0 * BORDER_JITTER
			+ (vec2(vnoise(p * 4.1), vnoise(p * 4.1 + 9.7)) - 0.5) * 0.12;
}

// Білінійні ваги сусідніх клітинок, звужені до смуги переходу.
vec2 border_weights(vec2 f) {
	return smoothstep(vec2(0.5 - BORDER_SOFTNESS), vec2(0.5 + BORDER_SOFTNESS), f);
}

// Кола від крапель дощу. Масштаб світу: клітинка = 8 м. Комірка — 0.08 клітинки
// (0.64 м), у кожній одна крапля; коло росте до радіуса 0.019 клітинки (0.15 м,
// тобто 0.3 м у діаметрі) за пів секунди, гребінь — 0.0064 клітинки (5 см).
// Два зсунуті шари комірок.
// Повертає нахил нормалі в площині xz; коло не виходить за свою комірку.
const float RIPPLE_CELLS_PER_TILE = 12.5;

vec2 rain_ripples(vec2 p, float t) {
	vec2 n = vec2(0.0);
	for (int l = 0; l < 2; l++) {
		vec2 q = p * RIPPLE_CELLS_PER_TILE + float(l) * vec2(0.37, 0.71);
		vec2 c = floor(q);
		float h = hash12(c + float(l) * 19.0);
		vec2 d = q - (c + 0.25 + 0.5 * vec2(h, hash12(c + 7.3)));
		float r = length(d);
		float age = fract(t * 2.0 + h);
		float x = (r - age * 0.24) / 0.08;
		float s = abs(x) < 1.0 ? sin(x * PI) : 0.0;
		n += d / max(r, 1e-4) * s * (1.0 - age) * (1.0 - age);
	}
	return n;
}

// Скільки рябі видно: 1 — кола розрізнені (близько), 0 — гребінь тонший за
// піксель, і кола лише мерехтіли б аліасингом; тоді рябь іде в шорсткість.
float ripple_visibility(vec2 p) {
	float px = length(fwidth(p * RIPPLE_CELLS_PER_TILE));
	return 1.0 - smoothstep(0.1, 0.3, px);
}

#include "res://game/battle/shaders/overcast_sky.gdshaderinc"

// Відбиття похмурого неба з френелем Шліка; n і v — світові й нормалізовані,
// t — секунди (дрейф хмар).
vec3 overcast_reflection(vec3 n, vec3 v, float f0, float power, float t) {
	float f = f0 + (1.0 - f0) * pow(1.0 - clamp(dot(n, v), 0.0, 1.0), power);
	return overcast_sky_at(reflect(-v, n), t) * f;
}

// Нахил нормалі у світовому xz -> NORMAL_MAP площини (дотична +X, бінормаль −Z).
vec3 slope_to_normal_map(vec2 s) {
	return vec3(s.x * 0.5 + 0.5, -s.y * 0.5 + 0.5, 1.0);
}

// Нахил у світовому xz -> світова нормаль (довжину нахилу обмежено, як і в Godot,
// що відновлює z з xy карти нормалей).
vec3 slope_to_world(vec2 s) {
	s *= min(1.0, 0.9 / max(length(s), 1e-4));
	return vec3(s.x, sqrt(1.0 - dot(s, s)), s.y);
}
