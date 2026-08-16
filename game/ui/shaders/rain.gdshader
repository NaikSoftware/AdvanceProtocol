shader_type canvas_item;
// Процедурний дощ для головного меню (Background/Rain). Ніякої текстури —
// смуги малюються з TIME напряму, тож коштує один ColorRect на весь екран.
// Значення за замовчуванням підібрані так, щоб дощ читався як рух, але не
// забивав заголовок зліва (alpha низька, ~0.12-0.2 — див. бриф).

uniform float density : hint_range(10.0, 300.0) = 110.0;
uniform float fall_speed : hint_range(0.05, 3.0) = 0.9;
uniform float angle : hint_range(-0.6, 0.6) = 0.14;
uniform float streak_length : hint_range(0.02, 0.6) = 0.18;
uniform float opacity : hint_range(0.0, 1.0) = 0.16;
uniform float wind : hint_range(-1.0, 1.0) = 0.08;

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

void fragment() {
	vec2 uv = UV;
	// Легкий нахил від вітру: зсуваємо X пропорційно Y (діагональні смуги) і
	// повільно зносимо весь візерунок вбік за TIME.
	float sheared_x = uv.x - uv.y * angle + TIME * wind * 0.03;
	float col = floor(sheared_x * density);
	float col_seed = hash11(col + 0.5);

	float local_x = fract(sheared_x * density) - 0.5;
	float col_width = 0.05 + col_seed * 0.03;
	float streak_mask = smoothstep(col_width, 0.0, abs(local_x));

	// Кожна колонка падає з власною фазою й трохи іншою швидкістю — інакше
	// весь дощ виглядає як одна пластина, що з'їжджає вниз.
	float speed = fall_speed * (0.5 + col_seed);
	float phase = hash11(col + 91.7);
	float y = fract(uv.y - TIME * speed - phase);
	float head_fade = smoothstep(streak_length, 0.0, y);

	// Не кожна колонка активна одночасно — керує густотою.
	float visible = step(0.45, hash11(col + 3.7));

	float alpha = streak_mask * head_fade * visible * opacity;
	COLOR = vec4(0.66, 0.70, 0.74, alpha);
}
