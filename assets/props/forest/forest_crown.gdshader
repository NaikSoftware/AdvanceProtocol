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
// ні крони, ні її тіні; проміжне значення переходить у впорядкований растр 4×4. Фрагменти
// відкидаються, а не змішуються: без сортування прозорих, крона лишається в буфері глибини.
// Той самий растр згладжує alpha-cut край пучка на ширину пікселя (MSAA у проєкті немає,
// тож alpha-to-coverage не діє).
// RGB кольору вершини — затінення пучка в глибині крони (1 на корі).
render_mode cull_disabled, depth_draw_opaque, skip_vertex_transform;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.5;
// Тон листя під світло карти (BattleLook.foliage_tint): похмуре синювате розсіяне світло
// робить буре фіолетовим, і цей множник його повертає.
uniform vec3 foliage_tint = vec3(1.0);
// М'яке огортання світлом і просвічування: тіньовий бік пучка не чорніє, як у листя.
uniform float wrap = 0.5;
uniform float translucency = 0.35;

varying float is_card;

float bayer4(vec2 p) {
	ivec2 i = ivec2(mod(p, 4.0));
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[i.y * 4 + i.x]) + 0.5) / 16.0;
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
	vec4 t = texture(albedo_tex, UV);
	float edge = clamp((t.a - alpha_cutoff) / max(fwidth(t.a), 1e-4) + 0.5, 0.0, 1.0);
	if (COLOR.a <= 0.001 || edge * COLOR.a < bayer4(FRAGCOORD.xy)) {
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
	DIFFUSE_LIGHT += d * ATTENUATION * LIGHT_COLOR / PI;
}
