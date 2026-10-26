shader_type spatial;
// Рослинність, звичайний вигляд: непрозора, край пучка — alpha-to-coverage.
render_mode cull_disabled, depth_draw_opaque, skip_vertex_transform;
#include "res://assets/props/vegetation/veg_body.gdshaderinc"
