// Дрібні коробки PropLayer (один MultiMesh): полотно й стовпи воріт (INSTANCE_CUSTOM.r = 1) світяться й темніють під дощем так само, як паркан
// (prop_thin). Паркан — картка з нормаллю, нахиленою до неба, і мокрістю WET_DARK; вертикальні грані стандартної
// коробки з нормаллю вбік на похмурому небі лишались удвічі темнішими за ту саму фарбу на парканi.
shader_type spatial;

global uniform float weather_wetness;

// Ті самі межі, що в prop_thin: частка неба в нормалі, мокрість, затемнення, шорсткість.
uniform float sky_bend = 0.65;
const float WET_FULL = 0.5;
const float WET_DARK = 0.75;
const float ROUGHNESS_DRY = 0.92;
const float ROUGHNESS_WET = 0.4;

varying flat float gate_v;

void vertex() {
	gate_v = INSTANCE_CUSTOM.r;
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
	ALBEDO = albedo * mix(1.0, WET_DARK, wet);
	ROUGHNESS = mix(0.95, mix(ROUGHNESS_DRY, ROUGHNESS_WET, wet), gate);
	METALLIC = 0.0;
	vec3 up = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	NORMAL = normalize(mix(NORMAL, up, sky_bend * gate));
}
