// Похмуре небо з хмарами (Phase 5a). Одна функція на двох: шейдер неба малює ним
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

// r — світовий напрям; t — секунди (дрейф хмар; шейдер неба передає 0, щоб
// радіанс рахувався один раз). Лінійні кольори, мала насиченість, без сонця.
vec3 overcast_sky_at(vec3 r, float t) {
	if (r.y < 0.0) {
		return vec3(0.07, 0.07, 0.065);
	}
	float up = r.y;
	vec2 h = normalize(r.xz + vec2(1e-5));
	float side = 0.5 + 0.5 * dot(h, SKY_BRIGHT_XZ);
	vec3 horizon = vec3(0.2, 0.21, 0.22) * (0.85 + 0.35 * side);
	vec3 c = mix(horizon, vec3(0.11, 0.12, 0.13), pow(up, 0.6));
	// Хмарні маси на площині неба: великі м'які плями, що повільно пливуть.
	vec2 cp = r.xz / (up + 0.12) * 2.0 + vec2(t * 0.02, t * 0.008);
	float mass = smoothstep(0.35, 0.75, sky_fbm(cp));
	return c * mix(1.15, 0.72, mass);
}
