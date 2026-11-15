shader_type spatial;
// Кільце дальності на ґрунті (BoardView.draw_circles): узор цілком з fire_ring.gdshaderinc, той самий,
// що малює крона лісу над кільцем. Прозоре й без запису глибини, як лінії зон: юніти, будинки й
// огорожі його закривають, а два кола одного загону змішуються, а не б'ються за глибину.
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

#include "res://game/battle/shaders/fire_ring.gdshaderinc"

uniform vec4 ring_color : source_color = vec4(1.0);
uniform float radius = 1.0;
uniform float grad_gain = 1.0;

// Вершини сітки — відносно центру тайла юніта (вузол стоїть у ньому), тож це вже точка ґрунту.
varying vec2 ground;

void vertex() {
	ground = VERTEX.xz;
}

void fragment() {
	// Слід пікселя на ґрунті однаковий в усіх напрямках — так само рахує й крона.
	float px = max(0.7071 * length(vec2(length(dFdx(ground)), length(dFdy(ground)))), 1e-4);
	ALBEDO = ring_color.rgb;
	ALPHA = ring_color.a * fire_ring(ground, radius, grad_gain, px);
}
