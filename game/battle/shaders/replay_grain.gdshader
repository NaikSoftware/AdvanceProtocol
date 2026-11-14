// Зерно й віньєтка запису з дрона (ReplayOverlay) — квад на весь екран, що екрана не читає: копія
// кадру (hint_screen_texture) коштувала б телефону бекбуфер щокадру. Premul-змішування: кадр під квадом
// множиться на 1 - alpha (віньєтка й темне зерно), а rgb додається (світле зерно).
shader_type canvas_item;
render_mode blend_premul_alpha;

uniform float grain = 0.035;
uniform float vignette = 0.3;
// Новий візерунок зерна ставить скрипт за годинником стіни: TIME біжить з Engine.time_scale, і на
// прискореному повторі зерно мерехтіло б у 2,5–20 разів частіше.
uniform float seed = 0.0;
// Зернина — частка екрана, а не піксель: на екрані телефона з високою щільністю піксельне зерно зникло б.
uniform vec2 cells = vec2(640.0, 360.0);

// Хеш без sin(): sin на великих аргументах на мобільних GPU втрачає точність і дає смуги.
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	float n = (hash(floor(UV * cells) + seed * vec2(17.0, 59.0)) * 2.0 - 1.0) * grain;
	vec2 d = (UV - 0.5) * vec2(cells.x / cells.y, 1.0);
	float v = vignette * smoothstep(0.45, 1.0, length(d));
	COLOR = vec4(vec3(max(n, 0.0)), v + max(-n, 0.0));
}
