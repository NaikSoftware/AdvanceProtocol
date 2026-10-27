shader_type spatial;
// Рослинність над видимим юнітом, перший прохід: пише глибину найближчих карток і нічого не
// малює. Другий прохід (next_pass) — veg_fade.gdshader: він проходить тест глибини лише на
// найближчому шарі, тож прозорість крони однорідна, а не «дим» із накладених карток.
// depth_prepass_alpha кладе прохід і в тіньовий: там ALPHA = 1, тож крона над юнітом кидає ту
// саму тінь, що й непрозора (без цього тінь зникала стрибком, щойно вмикалась прозорість).
render_mode unshaded, cull_disabled, skip_vertex_transform, depth_draw_always, depth_prepass_alpha;
#define VEG_FADE_DEPTH
#include "res://assets/props/vegetation/veg_body.gdshaderinc"
