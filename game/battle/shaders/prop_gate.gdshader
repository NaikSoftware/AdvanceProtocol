// Дрібні коробки PropLayer (один MultiMesh): полотно й стовпи воріт (INSTANCE_CUSTOM.r = 1) світяться й темніють під дощем так само, як паркан
// (prop_thin). Паркан — картка з нормаллю, нахиленою до неба, і мокрістю WET_DARK; тому й коробка воріт бере нормаль,
// нахилену до неба, і ту саму мокрість: вертикальні грані з нормаллю вбік на похмурому небі були б вдвічі темніші за паркан.
shader_type spatial;

global uniform float weather_wetness;

// Ті самі межі, що в prop_thin: частка неба в нормалі, мокрість, затемнення, шорсткість.
uniform float sky_bend = 0.65;
const float WET_FULL = 0.5;
const float WET_DARK = 0.75;
const float TOP_DARK = 0.28;
// Мокрий підйом за кодом воріт (INSTANCE_CUSTOM.r): 2 — slat, 3 — wood, 4 — sheet; ті самі числа в prop_thin.
const float GAIN_SLAT = 1.6;
const float GAIN_WOOD = 2.4;
const float GAIN_SHEET = 1.6;

varying flat float gate_v;
varying float up_v;

void vertex() {
	gate_v = INSTANCE_CUSTOM.r;
	// Чи дивиться грань коробки вгору (до сили масштабу коробки нормаль лишається осьовою).
	up_v = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz).y;
}

vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, vec3(lessThan(c, vec3(0.04045))));
}

void fragment() {
	// Колір коробки — sRGB у кольорі екземпляра (vertex_color_is_srgb у звичайного матеріалу).
	vec3 albedo = srgb_to_linear(COLOR.rgb);
	// Уламки руїни — звичайна матова коробка (шорсткість 0.95, без мокрості й нахилу нормалі).
	float gate = step(0.5, gate_v);
	float wet = smoothstep(0.0, WET_FULL, weather_wetness) * gate;
	// Верхні грані й шапки стовпів ловили все небо й світились білими плямами: удвічі-втричі темніші, як верх секції паркану.
	albedo *= mix(1.0, TOP_DARK, gate * smoothstep(0.5, 0.9, up_v));
	// Мокрий підйом за родом воріт: паркан того ж виду підсвічено так само (prop_thin, GAIN_*).
	float gain = gate_v > 3.5 ? GAIN_SHEET : (gate_v > 2.5 ? GAIN_WOOD : (gate_v > 1.5 ? GAIN_SLAT : 1.0));
	albedo *= mix(1.0, gain, wet);
	ALBEDO = albedo * mix(1.0, WET_DARK, wet);
	// Ворота завжди матові: блискуча (мокра) поверхня дає на гранях дрібних коробок білі іскри відблиску.
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	vec3 up = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	NORMAL = normalize(mix(NORMAL, up, sky_bend * gate));
}
