// Небо бою. Без TIME: радіанс і зонд рахуються один раз; дрейф хмар видно у воді, яка відбиває
// ту саму функцію з часом. `clear_amount` ставить `WeatherRig` — зміна параметра матеріалу перераховує
// радіанс, а глобальний uniform цього не гарантує.
shader_type sky;

uniform float clear_amount = 0.0;

#include "res://game/battle/shaders/overcast_sky.gdshaderinc"

void sky() {
	COLOR = overcast_sky_at(EYEDIR, 0.0, clear_amount);
}
