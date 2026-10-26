shader_type spatial;
// Рослинність над видимим юнітом, перший прохід: пише глибину найближчих карток і нічого не
// малює. Другий прохід (next_pass) — veg_fade.gdshader: він проходить тест глибини лише на
// найближчому шарі, тож прозорість крони однорідна, а не «дим» із накладених карток.
render_mode cull_disabled, skip_vertex_transform, depth_draw_always;
#define VEG_FADE_DEPTH
#include "res://assets/props/vegetation/veg_body.gdshaderinc"
