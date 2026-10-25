shader_type spatial;
// Крона або кущ із бібліотеки лісу: alpha-cut по атласу плюс розчинення екземпляра.
// Альфа кольору екземпляра `MultiMesh` (1 — ціла крона, 0,3 — над юнітом) переходить у
// впорядкований растр 4×4: фрагменти відкидаються, а не змішуються, тож немає сортування
// прозорих і крона лишається в буфері глибини. `ALPHA_HASH` стандартного матеріалу
// відкинуто: він дробить і саму alpha-cut межу листя, і крона «кипить» шумом.
// RGB кольору вершини — затінення пучка в глибині крони (1 на корі).
render_mode cull_disabled, depth_draw_opaque;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.5;

float bayer4(vec2 p) {
	ivec2 i = ivec2(mod(p, 4.0));
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[i.y * 4 + i.x]) + 0.5) / 16.0;
}

void fragment() {
	vec4 t = texture(albedo_tex, UV);
	// Картку, повернуту до камери ребром, видно смугою-мазком; поріг alpha росте до 1,
	// коли лице грані відвертається, і така картка тане. Нормаль грані — з похідних
	// позиції, бо нормалі вершин навмисно сферичні (м'яке світло крони).
	vec3 face = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	float facing = abs(dot(face, normalize(-VERTEX)));
	float cut = mix(1.0, alpha_cutoff, smoothstep(0.2, 0.55, facing));
	if (t.a < cut) {
		discard;
	}
	if (COLOR.a < 0.999 && bayer4(FRAGCOORD.xy) >= COLOR.a) {
		discard;
	}
	ALBEDO = t.rgb * COLOR.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.2;
}
