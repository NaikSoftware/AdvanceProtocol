shader_type spatial;
// Рослинність над видимим юнітом: альфа екземпляра (COLOR.a) — напівпрозорість, окремий
// прозорий прохід; матеріал міняється на цей лише для таких екземплярів.
render_mode cull_disabled, skip_vertex_transform;
#define VEG_FADE
#include "res://assets/props/vegetation/veg_body.gdshaderinc"
