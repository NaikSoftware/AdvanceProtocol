// Кільце дальності (BoardView.RingStyle) як чиста функція точки ґрунту: ні UV, ні сітки,
// ні часу кадру. Тож ту саму функцію може порахувати будь-який шейдер, що знає точку ґрунту під
// своїм пікселем (крона лісу, що закриває землю), і кільце там не обірветься.
//
// p      — точка ґрунту відносно центру тайла юніта, у тайлах (1 тайл = 1.0 світу);
// radius — радіус правила в тайлах, рівно той, що дав core/;
// style  — BoardView.RingStyle: 1 світіння, 2 засічки, 3 диск, 4 імпульс;
// dashed — кільце дрона: штрихи (у засічках — крапки) замість суцільної лінії, щоб гармату
//          й дрон розрізняв не лише колір;
// pulse  — поступ одноразового імпульсу 0..1, 1 — кільце стоїть (інші стилі його не читають);
// px     — розмір пікселя на ґрунті в тайлах (рахує викликач: fwidth тут не мав би сенсу
//          для чужої геометрії).
// Повертає непрозорість; колір дає викликач.

const float FR_TAU = 6.2831853;
const float FR_LINE_W = 0.12;
// Крок штриха дрона вздовж дуги й частка штриха в ньому, тайлів.
const float FR_DASH = 0.42;
const float FR_DASH_ON = 0.26;
const float FR_GLOW_W = 0.45;
const float FR_GLOW_A = 0.38;
const float FR_TICKS = 24.0;
const float FR_TICK_L = 0.24;
const float FR_TICK_W = 0.05;
const float FR_DOT_STEP = 0.32;
const float FR_DOT_R = 0.075;
// Заливка диска ледь помітна: під нею мають читатися ґрунт і сліди бою.
const float FR_DISK_A = 0.05;
const float FR_PULSE_W = 0.9;
const float FR_PULSE_A = 0.32;

// Покриття пікселя для відстані до краю (додатна — всередині): лінійне згладжування на один
// піксель, визначене й тоді, коли фігура тонша за піксель.
float fr_cov(float inside, float px) {
	return clamp(inside / px + 0.5, 0.0, 1.0);
}

// Ціле число кроків на коло: фаза неперервна й на шві atan.
float fr_steps(float radius, float step_len) {
	return max(round(FR_TAU * radius / step_len), 4.0);
}

// Штрихи вздовж кола радіуса radius. Коли крок штриха — кілька пікселів, візерунок
// мерехтів би при русі камери, тож тоді він зливається в рівну тьмянішу лінію.
float fr_dashes(vec2 p, float radius, float px) {
	float n = fr_steps(radius, FR_DASH);
	float step_len = FR_TAU * radius / n;
	float e = abs(fract(atan(p.y, p.x) / FR_TAU * n) - 0.5) * step_len;
	float m = fr_cov(FR_DASH_ON * 0.5 - e, px);
	return mix(m, FR_DASH_ON / step_len, smoothstep(0.15, 0.35, px / step_len));
}

float fr_line(vec2 p, float radius, bool dashed, float px) {
	// Не тонша за півтора пікселя: на найдальшому зумі лінія інакше розсипається.
	float hw = max(FR_LINE_W * 0.5, 0.75 * px);
	float a = fr_cov(hw - abs(length(p) - radius), px);
	return dashed ? a * fr_dashes(p, radius, px) : a;
}

// Засічки всередину для гармати: кожні 360/FR_TICKS градусів, як на безелі годинника.
float fr_ticks(vec2 p, float radius, float px) {
	float d = length(p);
	float e = abs(fract(atan(p.y, p.x) / FR_TAU * FR_TICKS + 0.5) - 0.5) * FR_TAU / FR_TICKS * d;
	float radial = min(d - (radius - FR_TICK_L), radius - d);
	return fr_cov(FR_TICK_W * 0.5 - e, px) * fr_cov(radial, px);
}

// Крапки по колу для дрона: найближча крапка рахується з тієї ж цілої фази, що й штрихи.
float fr_dots(vec2 p, float radius, float px) {
	float n = fr_steps(radius, FR_DOT_STEP);
	float k = floor(atan(p.y, p.x) / FR_TAU * n) + 0.5;
	float ang = k * FR_TAU / n;
	vec2 c = radius * vec2(cos(ang), sin(ang));
	float r = max(FR_DOT_R, 0.75 * px);
	return fr_cov(r - length(p - c), px);
}

float fire_ring(vec2 p, float radius, int style, bool dashed, float pulse, float px) {
	float d = length(p);
	float inside = fr_cov(radius - d, px);
	if (style == 1) {
		// Смуга, що гасне всередину: «всередині — досяжне» читається одразу.
		float t = clamp((radius - d) / FR_GLOW_W, 0.0, 1.0);
		float glow = (1.0 - t) * (1.0 - t) * FR_GLOW_A * inside;
		return max(fr_line(p, radius, dashed, px), glow);
	}
	if (style == 2) {
		if (dashed) {
			return fr_dots(p, radius, px);
		}
		float thin = fr_cov(max(0.03, 0.6 * px) - abs(d - radius), px);
		return max(thin, fr_ticks(p, radius, px));
	}
	if (style == 3) {
		return max(fr_line(p, radius, dashed, px), FR_DISK_A * inside);
	}
	if (style == 4) {
		// Фронт іде від юніта до краю й за край, тож при pulse = 1 хвилі в колі вже немає;
		// лінія з'являється, коли фронт її досягає, і далі стоїть.
		float f = pulse * (radius + FR_PULSE_W);
		float s = (f - d) / FR_PULSE_W;
		float wave = s >= 0.0 && s <= 1.0 ? (1.0 - s) * (1.0 - s) * fr_cov(f - d, px) : 0.0;
		float line = fr_line(p, radius, dashed, px) * clamp((f - radius) / 0.25 + 0.5, 0.0, 1.0);
		return max(line, wave * FR_PULSE_A * inside);
	}
	return fr_line(p, radius, dashed, px);
}
