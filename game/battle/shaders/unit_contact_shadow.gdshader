// Тінь-контакт під юнітом (`UnitView`): м'яка темна пляма під корпусом, незалежна від сонця. На
// сонячних картах тінь від сонця світла й м'яка, і під юнітом вона ховається; пляма тримає юніта
// на землі. Сила — з вигляду карти (`BattleLook.unit_contact_shadow`); 0 — плями нема.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

global uniform float unit_contact_shadow;

void fragment() {
	// Еліпс по сліду корпусу: найтемніше під серединою, до краю квада гасне до нуля.
	float r = length((UV - 0.5) * 2.0);
	ALBEDO = vec3(0.0);
	ALPHA = clamp(unit_contact_shadow, 0.0, 1.0) * (1.0 - smoothstep(0.3, 1.0, r));
}
