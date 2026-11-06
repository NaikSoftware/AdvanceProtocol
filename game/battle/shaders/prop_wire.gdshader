// Дроти ЛЕП (PropLayer): лінія в один піксель без світла, колір — albedo_color × колір вершини (прозорість
// трійки 10 кВ). У кільці дріт тоне в імлі так само, як стовпи й земля під ним: колір іде до кольору
// імли, а не лишається темною рискою поверх пелени.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, fog_disabled;

uniform vec4 albedo_color : source_color = vec4(1.0);

varying vec3 world_pos;

#include "res://game/battle/shaders/surroundings.gdshaderinc"

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 c = albedo_color * COLOR;
	ALBEDO = c.rgb;
	ALPHA = c.a;
	if (surround) {
		vec4 haze = fog_bank(world_pos, CAMERA_POSITION_WORLD, normalize(-INV_VIEW_MATRIX[2].xz));
		ALBEDO = mix(c.rgb, haze.rgb, haze.a);
	}
}
