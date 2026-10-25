// Будівлі й руїни (PropLayer): матеріал GLB (альбедо, нормалі, шорсткість) плюс розчинення
// растром над юнітом і імла кільця. Лише для будівель: дах — єдине, що може сховати юніта, а
// дрібні пропси й мости лишаються зі своїм імпортованим матеріалом.
shader_type spatial;
render_mode blend_mix, cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float roughness = 0.9;
uniform float metallic = 0.0;

varying vec3 world_pos;
// Частка викинутих пікселів (INSTANCE_CUSTOM.a): 0 — суцільна, 0.7 — крізь дах видно юніта.
varying flat float v_fade;

#include "res://game/battle/shaders/surroundings.gdshaderinc"

// Поріг матриці Баєра 4×4: розчинення растром лишає матеріал непрозорим (без сортування й
// без другого проходу), а дірки на 1 піксель на телефоні зливаються в напівпрозорість.
float bayer4(vec2 frag) {
	ivec2 p = ivec2(mod(frag, 4.0));
	int i = p.x + p.y * 4;
	float m[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[i] + 0.5) / 16.0;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_fade = INSTANCE_CUSTOM.a;
}

void fragment() {
	if (v_fade > bayer4(FRAGCOORD.xy)) {
		discard;
	}
	vec3 albedo = texture(albedo_tex, UV).rgb * albedo_color.rgb;
	ALBEDO = albedo;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	FOG = vec4(0.0);
	if (surround) {
		vec4 haze = fog_bank(world_pos, CAMERA_POSITION_WORLD, normalize(-INV_VIEW_MATRIX[2].xz));
		ALBEDO = surround_grade(albedo, haze.a);
		// Без лінії межі: на стіні вона лягла б зламом, а будинки кільця за межею й так стоять.
		FOG = surround_fog(haze, 0.0);
	}
}
