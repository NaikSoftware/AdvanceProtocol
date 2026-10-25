extends GutTest
## Бібліотека крон лісу: окремі дерева, кущі й повалені стовбури, які дошка розкидає
## `MultiMesh`-ами. GLB хвойних спільний для всіх сезонів, листяні — по одному на сезон.
## Кожен вузол — один меш з одним матеріалом (атлас у GLB): один виклик малювання на
## варіант. Перевіряємо розміщення (земля на y = 0, вісь стовбура в початку координат),
## розмір, бюджет трикутників і alpha-cut матеріал — на ньому тримається розчинення крони
## над юнітом (`forest_crown.gdshader`).

const DIR: String = "res://assets/props/forest"
const TILE_M: float = 8.0
const GROUND_TOL: float = 0.02

## Префікс вузла -> [мін. висота (м), макс. висота (м), макс. півширина (тайли), мін. трикутників, макс. трикутників].
const LIMITS: Dictionary = {
	"Pine": [13.0, 22.0, 0.7, 40, 150],
	"Spruce": [12.0, 21.0, 0.6, 40, 150],
	"Birch": [14.0, 20.0, 0.55, 40, 150],
	"Oak": [17.0, 22.0, 0.8, 40, 150],
	"Shrub": [2.0, 5.0, 0.4, 10, 100],
	"Log": [0.2, 1.5, 0.5, 10, 60],
	"Hero": [15.0, 27.0, 1.15, 100, 400],
}

const CONIFER: PackedStringArray = ["Pine_A", "Pine_B", "Pine_C", "Spruce_A", "Spruce_B"]
const BROADLEAF: PackedStringArray = [
	"Birch_A", "Birch_B", "Oak_A", "Oak_B", "Shrub_Hazel", "Shrub_Thorn", "Log_A", "Log_B",
	"Hero_Oak", "Hero_Lime", "Hero_Birch", "Hero_Poplar",
]
const SEASONS: PackedStringArray = ["late", "summer", "early"]


func _load(name: String) -> Node3D:
	var scene: PackedScene = load("%s/%s.glb" % [DIR, name]) as PackedScene
	assert_not_null(scene, "%s: GLB не завантажився" % name)
	if scene == null:
		return null
	var root: Node3D = scene.instantiate() as Node3D
	add_child_autofree(root)
	return root


func _tris(mesh: Mesh) -> int:
	var t: int = 0
	for s in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(s)
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		t += (idx.size() if not idx.is_empty() else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return t


func _check(glb: String, root: Node3D, node: String) -> void:
	var mi: MeshInstance3D = root.find_child(node, true, false) as MeshInstance3D
	assert_not_null(mi, "%s: нема вузла %s" % [glb, node])
	if mi == null:
		return
	var label: String = "%s/%s" % [glb, node]
	var lim: Array = LIMITS[node.get_slice("_", 0)]
	assert_eq(mi.transform, Transform3D.IDENTITY, "%s: перетворення вузла запечене в меш" % label)
	assert_eq(mi.mesh.get_surface_count(), 1, "%s: одна поверхня — один виклик малювання" % label)
	var box: AABB = mi.mesh.get_aabb()
	assert_almost_eq(box.position.y, 0.0, GROUND_TOL, "%s: земля на y = 0" % label)
	var h_m: float = box.end.y * TILE_M
	assert_between(h_m, float(lim[0]), float(lim[1]), "%s: висота %.1f м" % [label, h_m])
	var half: float = maxf(maxf(absf(box.position.x), absf(box.end.x)), maxf(absf(box.position.z), absf(box.end.z)))
	assert_lte(half, float(lim[2]), "%s: півширина %.2f тайла" % [label, half])
	var tris: int = _tris(mi.mesh)
	assert_between(tris, int(lim[3]), int(lim[4]), "%s: %d трикутників" % [label, tris])
	var mat: StandardMaterial3D = mi.mesh.surface_get_material(0) as StandardMaterial3D
	assert_not_null(mat, "%s: потрібен StandardMaterial3D" % label)
	if mat != null:
		assert_eq(mat.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR, "%s: alpha-cut" % label)
		assert_not_null(mat.albedo_texture, "%s: атлас у матеріалі" % label)


func test_conifers() -> void:
	var root: Node3D = _load("forest_conifer")
	if root == null:
		return
	for node in CONIFER:
		_check("forest_conifer", root, node)


func test_broadleaf_every_season() -> void:
	for season in SEASONS:
		var glb: String = "forest_broadleaf_%s" % season
		var root: Node3D = _load(glb)
		if root == null:
			continue
		for node in BROADLEAF:
			_check(glb, root, node)


func test_trunk_stands_on_origin() -> void:
	# Дошка ставить екземпляр точкою на землі; вісь стовбура мусить бути в цій точці,
	# інакше дерево на краю лісу стоїть у полі, а не там, де його поклала розкидка.
	var root: Node3D = _load("forest_conifer")
	if root == null:
		return
	for node in CONIFER:
		var mi: MeshInstance3D = root.find_child(node, true, false) as MeshInstance3D
		var verts: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for v in verts:
			if v.y < 0.05:
				lo = lo.min(Vector2(v.x, v.z))
				hi = hi.max(Vector2(v.x, v.z))
		assert_lt(((lo + hi) * 0.5).length(), 0.02, "%s: комель у початку координат" % node)
