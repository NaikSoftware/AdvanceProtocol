shader_type spatial;
// Рослинність, звичайний вигляд: непрозора, край пучка — alpha-to-coverage. Режим
// alpha_to_coverage обов'язковий: сам ALPHA_ANTIALIASING_EDGE лише змінює альфу, і без режиму
// MSAA на край не впливає (перевірено знімком: однакові пікселі з MSAA і без).
render_mode cull_disabled, depth_draw_opaque, skip_vertex_transform, alpha_to_coverage;
#include "res://assets/props/vegetation/veg_body.gdshaderinc"
