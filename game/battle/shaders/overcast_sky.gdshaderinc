// Небо з хмарами, від похмурого до ясного. Одна функція на двох: шейдер неба малює ним
// небо (і з нього радіанс/зонд), а вода й калюжі відбивають той самий купол напряму
// — тож хмари у воді збігаються з небом, а не вигадані окремо.

// Світліший бік обрію — перед камерою (поворот рига 45°), щоб далека вода блищала.
const vec2 SKY_BRIGHT_XZ = vec2(-0.7071, -0.7071);

float sky_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float sky_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(sky_hash(i), sky_hash(i + vec2(1.0, 0.0)), u.x),
			mix(sky_hash(i + vec2(0.0, 1.0)), sky_hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float sky_fbm(vec2 p) {
	return 0.5 * sky_noise(p) + 0.27 * sky_noise(p * 2.07 + 5.3)
			+ 0.15 * sky_noise(p * 4.13 + 11.9) + 0.08 * sky_noise(p * 8.31 + 23.1);
}

// r — світовий напрям; t — секунди (дрейф хмар; шейдер неба передає 0, щоб радіанс рахувався
// один раз); clear — 0 похмуре небо, 1 ясне (`BattleLook.sky_clear`). Лінійні кольори, без
// диска сонця: його світло дає `DirectionalLight3D`.
vec3 overcast_sky_at(vec3 r, float t, float clear) {
	if (r.y < 0.0) {
		return vec3(0.07, 0.07, 0.065);
	}
	float up = r.y;
	vec2 h = normalize(r.xz + vec2(1e-5));
	float side = 0.5 + 0.5 * dot(h, SKY_BRIGHT_XZ);
	vec3 horizon = vec3(0.2, 0.21, 0.22) * (0.85 + 0.35 * side);
	vec3 c = mix(horizon, vec3(0.11, 0.12, 0.13), pow(up, 0.6));
	// Ясне небо: блідий обрій і синій зеніт — від нього й синюватий відбитий та розсіяний світ.
	vec3 c_clear = mix(vec3(0.42, 0.52, 0.66) * (0.9 + 0.2 * side), vec3(0.1, 0.22, 0.52), pow(up, 0.5));
	// Хмарні маси на площині неба: великі м'які плями, що повільно пливуть. У ясному небі
	// лишаються рідкі білі купчасті хмари.
	vec2 cp = r.xz / (up + 0.12) * 2.0 + vec2(t * 0.02, t * 0.008);
	float n = sky_fbm(cp);
	float mass = smoothstep(0.35, 0.75, n);
	float puff = smoothstep(0.62, 0.78, n);
	vec3 grey = c * mix(1.15, 0.72, mass);
	vec3 fair = mix(c_clear, vec3(0.75, 0.76, 0.78), puff * 0.8);
	return mix(grey, fair, clamp(clear, 0.0, 1.0));
}
