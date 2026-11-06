// Пляма дотику під брилою чи бетонним блоком (PropLayer): м'яке затемнення землі довкола підошви.
// На сонячній карті пляма витягується від сонця на довжину тіні предмета — запечена тінь замість
// проходу тіней по всіх брилах, що коштував би десятки тисяч трикутників.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled, world_vertex_coords;

uniform float strength = 0.6;
// 1 — карта з чіткою тінню сонця (PropLayer.structure_shadows), 0 — похмура: лише кругла пляма.
uniform float cast = 0.0;
// Напрям на сонце (WeatherRig): тінь лягає в протилежний бік.
global uniform vec3 sun_dir;

varying vec3 world_pos;

#include "res://game/battle/shaders/surroundings.gdshaderinc"

void vertex() {
	// INSTANCE_CUSTOM.r — висота предмета, клітинки: від неї довжина тіні.
	vec3 centre = MODEL_MATRIX[3].xyz;
	vec2 away = VERTEX.xz - centre.xz;
	vec2 shadow = -sun_dir.xz / max(sun_dir.y, 0.35) * INSTANCE_CUSTOM.r * cast;
	if (dot(shadow, shadow) > 1e-8 && dot(away, away) > 1e-8) {
		float far = 0.5 + 0.5 * dot(normalize(away), normalize(shadow));
		VERTEX.xz += shadow * far;
	}
	world_pos = VERTEX;
}

void fragment() {
	// UV площини 0..1: кругла пляма з м'яким краєм, найтемніша під самим каменем.
	float r = length(UV - vec2(0.5)) * 2.0;
	ALBEDO = vec3(0.0);
	ALPHA = strength * (1.0 - smoothstep(0.35, 1.0, r));
	// Під руїною кільця пляма слабне з імлою, що вкриває землю під нею: інакше вона чорніє поверх пелени.
	if (surround) {
		ALPHA *= 1.0 - fog_bank(world_pos, CAMERA_POSITION_WORLD, normalize(-INV_VIEW_MATRIX[2].xz)).a;
	}
}
