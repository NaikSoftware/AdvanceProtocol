shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D flame_tex : source_color, filter_linear_mipmap;
uniform vec2 grid = vec2(16.0, 4.0);
uniform float frames = 64.0;
// Той самий крок таймера, що й у диму. Цикл 64 кадри; кожен екземпляр — свій темп ±20 % і свій стартовий кадр, тож двох у такт нема.
// fx_time — лише для віку (поява полум'я); кадри й тремтіння — з loop_time, згорнутого за loop_sec
// (WreckLayer.fire_loop_sec): за великого fx_time кадр атласу губив точність, і вогонь ішов смугами.
uniform float fx_time = 0.0;
uniform float loop_time = 0.0;
uniform float loop_sec = 34.133333;
uniform float tempo_steps = 16.0;
uniform float play_fps = 30.0;
// Понад 1: ядро світиться майже білим, краї й верх — помаранчеві з атласу.
uniform float gain = 1.6;
// Де в клітинці основа полум'я (v згори), яку частку ширини воно займає, висота клітинки до ширини.
uniform float base_v = 0.8;
uniform float fill = 0.6;
uniform float cell_aspect = 1.0;
// На далекому зумі стовп не вужчий за 6 px: інакше вогонь зникає, а дим без нього бреше.
uniform float min_px = 6.0;
// Висота кадру в пікселях: VIEWPORT_SIZE у вершинному шейдері тут нульовий, тож її дає WreckLayer.
uniform float viewport_h = 1080.0;
// Полум'я проступає під темним хвостом кулі (INSTANCE_CUSTOM.z — народження уламків).
uniform float fade_in_at = 0.6;
uniform float fade_in_sec = 0.5;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
// Основа тоне в металі м'яко, а не обрізається рівною лінією по даху.
uniform float soft_fade = 0.08;
// Найвищий язик над основою, одиниці світу: вище полум'я м'яко гасне — не накриває сусідню клітинку.
uniform float max_h = 100.0;

varying float v_frame;
varying float v_h;
varying float v_in;

// Хеш без sin: sin великого аргументу у float32 губить точність, а fx_time росте весь матч.
float h1(float x) { float p = fract(x * 0.1031); p *= p + 33.33; p *= p + p; return fract(p); }
// Шум значень із періодом n: на стику згортки годинника без стрибка.
float vnoise(float x, float n) { float i = floor(x); float f = x - i; return mix(h1(mod(i, n)), h1(mod(i + 1.0, n)), f * f * (3.0 - 2.0 * f)); }

void vertex() {
	// INSTANCE_CUSTOM: x — ширина полум'я (одиниці світу), y — випадковість, z — народження.
	float w = INSTANCE_CUSTOM.x;
	float sd = INSTANCE_CUSTOM.y;
	vec3 root = MODEL_MATRIX[3].xyz;
	// Стовп стоїть вертикально у світі й повернутий до камери лише довкола вертикалі.
	vec3 right = normalize(vec3(INV_VIEW_MATRIX[0].x, 0.0, INV_VIEW_MATRIX[0].z));
	vec4 p0 = PROJECTION_MATRIX * VIEW_MATRIX * vec4(root, 1.0);
	vec4 p1 = PROJECTION_MATRIX * VIEW_MATRIX * vec4(root + right * w, 1.0);
	float px = length(p1.xy / p1.w - p0.xy / p0.w) * viewport_h * 0.5;
	w *= clamp(min_px / max(px, 0.001), 1.0, 8.0);
	// Темп тремтіння — ціле число клітинок шуму за період годинника.
	float wob = max(round((4.1 + 2.7 * sd) * loop_sec), 1.0);
	w *= 0.9 + 0.2 * vnoise(mod(loop_time / loop_sec * wob + sd * 61.0, wob), wob);
	float qw = w / fill;
	float qh = qw * cell_aspect;
	// Основа полум'я (v = base_v) — у точці отвору, на 1 см у металі.
	float base_y = 0.5 - base_v;
	v_h = (VERTEX.y - base_y) * qh;
	vec3 world = root + right * VERTEX.x * qw + vec3(0.0, v_h - 0.01, 0.0);
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
	// Темп кратний 1/tempo_steps: за loop_sec кожен проходить цілу кількість циклів атласу.
	float tempo = round((0.8 + 0.4 * h1(sd * 17.0)) * tempo_steps) / tempo_steps;
	v_frame = mod(loop_time * play_fps * tempo + sd * frames, frames);
	v_in = clamp((fx_time - INSTANCE_CUSTOM.z - fade_in_at) / fade_in_sec, 0.0, 1.0);
}

vec4 frame_at(float f, vec2 uv) {
	float n = mod(floor(f), frames);
	return texture(flame_tex, (clamp(uv, vec2(0.002), vec2(0.998)) + vec2(mod(n, grid.x), floor(n / grid.x))) / grid);
}

void fragment() {
	vec4 tex = mix(frame_at(v_frame, UV), frame_at(v_frame + 1.0, UV), fract(v_frame));
	// Біля отвору — майже біле розжарене серце, вище — колір атласу. Лише посередині основи: по краях
	// кваду біле лягало пересвіченою плямою на кути корпусу.
	float core = 1.0 - smoothstep(0.12, 0.3, abs(UV.x - 0.5));
	vec3 col = mix(tex.rgb, vec3(1.0, 0.94, 0.80), smoothstep(base_v - 0.35, base_v, UV.y) * 0.6 * core);
	ALBEDO = col * gain;
	ALPHA = tex.a * v_in * (1.0 - smoothstep(max_h * 0.7, max_h, v_h));
	// shortcut: глибина в NDC як у Vulkan (Forward+/Mobile); Compatibility дає z*2-1, краї там будуть жорсткіші.
	vec4 sv = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, texture(depth_tex, SCREEN_UV).r, 1.0);
	ALPHA *= clamp((VERTEX.z - sv.z / sv.w) / soft_fade, 0.0, 1.0);
}
