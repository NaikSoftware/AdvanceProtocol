extends GutTest
## Ліс: плитки-маси крон, краєві клумпи й кущі. Кожен GLB — набір вузлів `Canopy_0..2`,
## `Edge_0..3` або `Shrub_0..2` з одним матеріалом (атлас у GLB). Перевіряємо розміщення
## (земля на y = 0, відбиток у вікні 10 м), бюджет трикутників і те, що матеріал
## alpha-cut з текстурою — на ньому тримається покомірне затемнення крони.

const DIR: String = "res://assets/props/forest"
const TILE_M: float = 8.0
## Вікно крони 10 м у тайлах плюс запас на округлення вершин.
const FOOTPRINT_MAX: float = 10.0 / TILE_M * 0.5 + 0.02
## Краєві клумпи: крони крайніх дерев звисають за вікно ще на 2–3 м у сусідню клітинку.
const EDGE_FOOTPRINT_MAX: float = 0.95
const GROUND_TOL: float = 0.02
const CANOPY_MAX_TRIS: int = 300
const EDGE_MIN_TRIS: int = 800
const EDGE_MAX_TRIS: int = 1200
const SHRUB_MAX_TRIS: int = 16

const WOODS: PackedStringArray = [
	"forest_pine",
	"forest_mixed_late", "forest_mixed_summer", "forest_mixed_early",
	"forest_deciduous_late", "forest_deciduous_summer", "forest_deciduous_early",
]
const SHRUBS: PackedStringArray = [
	"forest_shrub_late", "forest_shrub_summer", "forest_shrub_early", "forest_shrub_conifer",
]


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


func _check_piece(name: String, mi: MeshInstance3D, max_tris: int, min_tris: int = 1, foot: float = FOOTPRINT_MAX) -> void:
	var label: String = "%s/%s" % [name, mi.name]
	var box: AABB = mi.mesh.get_aabb()
	assert_almost_eq(box.position.y, 0.0, GROUND_TOL, "%s: земля на y = 0" % label)
	assert_lte(absf(box.position.x), foot, "%s: відбиток по x" % label)
	assert_lte(absf(box.end.x), foot, "%s: відбиток по x" % label)
	assert_lte(absf(box.position.z), foot, "%s: відбиток по z" % label)
	assert_lte(absf(box.end.z), foot, "%s: відбиток по z" % label)
	var tris: int = _tris(mi.mesh)
	assert_lte(tris, max_tris, "%s: %d трикутників понад бюджет %d" % [label, tris, max_tris])
	assert_gte(tris, min_tris, "%s: %d трикутників менше за мінімум %d" % [label, tris, min_tris])
	var mat: StandardMaterial3D = mi.mesh.surface_get_material(0) as StandardMaterial3D
	assert_not_null(mat, "%s: потрібен StandardMaterial3D" % label)
	if mat != null:
		assert_eq(mat.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR, "%s: alpha-cut" % label)
		assert_not_null(mat.albedo_texture, "%s: атлас у матеріалі" % label)


func test_woods_have_canopy_tiles_and_edge_clumps() -> void:
	for name in WOODS:
		var root: Node3D = _load(name)
		if root == null:
			continue
		for i in 3:
			var mi: MeshInstance3D = root.get_node_or_null("Canopy_%d" % i) as MeshInstance3D
			assert_not_null(mi, "%s: нема Canopy_%d" % [name, i])
			if mi != null:
				_check_piece(name, mi, CANOPY_MAX_TRIS, 100)
		for i in 4:
			var mi: MeshInstance3D = root.get_node_or_null("Edge_%d" % i) as MeshInstance3D
			assert_not_null(mi, "%s: нема Edge_%d" % [name, i])
			if mi != null:
				_check_piece(name, mi, EDGE_MAX_TRIS, EDGE_MIN_TRIS, EDGE_FOOTPRINT_MAX)


func test_shrub_cards() -> void:
	for name in SHRUBS:
		var root: Node3D = _load(name)
		if root == null:
			continue
		for i in 3:
			var mi: MeshInstance3D = root.get_node_or_null("Shrub_%d" % i) as MeshInstance3D
			assert_not_null(mi, "%s: нема Shrub_%d" % [name, i])
			if mi != null:
				_check_piece(name, mi, SHRUB_MAX_TRIS, 4)


func test_edge_clump_is_open_on_negative_z() -> void:
	# Відкритий бік клумпа — -Z: там пояс кущів, тож відбиток сильніше сягає в -Z, ніж
	# дерева в +Z; board обертає клумп кроками по 90° до поля.
	var root: Node3D = _load("forest_mixed_late")
	if root == null:
		return
	var mi: MeshInstance3D = root.get_node("Edge_0") as MeshInstance3D
	var box: AABB = mi.mesh.get_aabb()
	assert_lt(box.position.z, -0.45, "кущі виходять до -Z")
