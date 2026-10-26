shader_type spatial;
// Рослинність над видимим юнітом: альфа екземпляра (COLOR.a) — напівпрозорість, окремий
// прозорий прохід. Ставиться як next_pass матеріалу veg_fade_depth.gdshader (той пише
// глибину найближчих карток), і обидва — лише для таких екземплярів.
render_mode cull_disabled, skip_vertex_transform;
#define VEG_FADE
#include "res://assets/props/vegetation/veg_body.gdshaderinc"
