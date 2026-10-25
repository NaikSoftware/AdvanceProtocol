shader_type spatial;
// Крона, кущ або стовбур із бібліотеки лісу (forest_conifer.glb, forest_broadleaf_*.glb).
//
// Картки пучків розгортаються до камери у вершинному шейдері: усі чотири вершини картки
// лежать у її центрі, а UV2 несе зсув кута в одиницях гри. Так картку ніколи не видно
// ребром — у нерухомій картці з довільним поворотом екземпляра частина пучків стояла б до
// камери боком і читалась смугою. У проході тіні «камера» — світло, тож тінь пучка теж повна.
// Стовбури й гілки (UV2 = 0) лишаються звичайною геометрією.
//
// Альфа кольору екземпляра `MultiMesh` — розчинення над юнітом: 1 — ціла крона, 0 — немає
// ні крони, ні її тіні; проміжне значення переходить у шумовий растр. Фрагменти
// відкидаються, а не змішуються: без сортування прозорих, крона лишається в буфері глибини.
// Той самий растр згладжує alpha-cut край пучка на ширину пікселя (MSAA у проєкті немає,
// тож alpha-to-coverage не діє). Растр — переплетений градієнтний шум, а не матриця Баєра:
// упорядкована матриця на 1:1 читається сіткою напівтону.
// Тінь не раструється: крона з альфою екземпляра < 0,5 тіні не кидає, решта кидає повну.
// RGB кольору вершини — затінення пучка в глибині крони (1 на корі).
render_mode cull_disabled, depth_draw_opaque, skip_vertex_transform;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.5;
// Тон листя під світло карти (BattleLook.foliage_tint, ставить WeatherRig): похмуре
// синювате розсіяне світло робить буре фіолетовим, і цей множник його повертає.
global uniform vec3 foliage_tint;
// М'яке огортання світлом і просвічування: тіньовий бік пучка не чорніє, як у листя.
uniform float wrap = 0.5;
uniform float translucency = 0.35;

varying float is_card;

float ign(vec2 p) {
	return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

void vertex() {
	vec3 v = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	is_card = dot(UV2, UV2) > 0.0 ? 1.0 : 0.0;
	if (is_card > 0.5) {
		// Масштаб екземпляра по горизонталі: картка росте разом із кроною.
		float s = length(MODEL_MATRIX[0].xyz);
		v.xy += UV2 * s;
	}
	VERTEX = v;
	NORMAL = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// Зміщення mip на −0,5: ближні крони на мінімальному зумі інакше розмиті.
	vec4 t = texture(albedo_tex, UV, -0.5);
	// Ширину згладження обмежено: на далекому зумі fwidth(alpha) великий, і без межі
	// растром укрилась би вся картка — крона розсипалась би рябими крапками.
	// На далеких mip-рівнях тонкі гілки усереднюються з прозорим тлом і тануть під порогом:
	// голе дерево здаля лишилось би самим стовбуром. Тож поріг знижується з рівнем mip.
	float lod = textureQueryLod(albedo_tex, UV).x;
	float cut = alpha_cutoff * mix(1.0, 0.45, clamp((lod - 1.0) / 3.0, 0.0, 1.0));
	float edge = clamp((t.a - cut) / clamp(fwidth(t.a), 1e-4, 0.12) + 0.5, 0.0, 1.0);
	// Тінь напрямленого світла рендериться ортографічно, а камера гри — у перспективі.
	bool shadow_pass = PROJECTION_MATRIX[3][3] > 0.5;
	if (shadow_pass) {
		if (COLOR.a < 0.5 || edge < 0.5) {
			discard;
		}
	} else if (COLOR.a <= 0.001 || edge * COLOR.a < ign(FRAGCOORD.xy)) {
		discard;
	}
	vec3 tint = mix(vec3(1.0), foliage_tint, is_card);
	ALBEDO = t.rgb * COLOR.rgb * tint;
	ROUGHNESS = 1.0;
	SPECULAR = 0.15;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float w = wrap * is_card;
	float d = max((ndl + w) / (1.0 + w), 0.0) + is_card * translucency * max(-ndl, 0.0);
	// Тінь сусідніх пучків на картці — лише наполовину: у справжній кроні світло проходить
	// крізь листя, а повна тінь із різким краєм малює на кроні плями камуфляжу.
	float att = mix(ATTENUATION, mix(0.5, 1.0, ATTENUATION), is_card);
	DIFFUSE_LIGHT += d * att * LIGHT_COLOR / PI;
}
