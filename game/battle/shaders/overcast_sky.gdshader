// Похмуре небо з хмарами (Phase 5a). Без TIME: радіанс і зонд рахуються один
// раз; дрейф хмар видно у воді, яка відбиває ту саму функцію з часом.
shader_type sky;

#include "res://game/battle/shaders/overcast_sky.gdshaderinc"

void sky() {
	COLOR = overcast_sky_at(EYEDIR, 0.0);
}
