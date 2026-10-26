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
## Висота — верхній центр пучка (видима верхівка ще на ~1 м вища). Дерева нижчі за справжні
## заради читання з камери гри: сосна й ялина 12–14 м, листяні 10–12 м, береза 9–11 м.
const LIMITS: Dictionary = {
	"Pine": [10.0, 15.0, 0.7, 40, 150],
	"Spruce": [10.0, 15.0, 0.6, 40, 150],
	# Пізня осінь — голе гілля трьох порядків замість пучків, тому межа вища.
	"Birch": [8.0, 12.0, 0.55, 40, 260],
	"Oak": [9.0, 13.0, 0.8, 40, 260],
	"Shrub": [1.5, 5.0, 0.4, 10, 100],
	"Log": [0.2, 1.5, 0.5, 10, 60],
	# Смуга узлісся завдовжки з тайл; гілля проламаної клітинки лежить на землі.
	"Hedge": [2.0, 4.5, 0.62, 60, 200],
	"Litter": [0.0, 0.5, 0.66, 10, 60],
	# Поодинокі восени голі (лишається 8–18 % пучків), влітку — 1500–2000 трикутників.
	"Hero": [9.0, 15.0, 1.3, 200, 3000],
}

const CONIFER: PackedStringArray = ["Pine_A", "Pine_B", "Pine_C", "Spruce_A", "Spruce_B", "Hedge_Spruce"]
const BROADLEAF: PackedStringArray = [
	"Birch_A", "Birch_B", "Oak_A", "Oak_B", "Shrub_Hazel", "Shrub_Thorn", "Hedge_Shrub", "Log_A", "Log_B", "Litter_A",
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


## Пучки — групи вершин з однаковою позицією й ненульовим UV2 (чотири кути картки в центрі).
func _cards(mesh: Mesh) -> int:
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	var seen: Dictionary = {}
	for i in verts.size():
		if uv2[i].length() >= 1e-3:
			seen[verts[i]] = true
	return seen.size()


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
	# У смуги узлісся немає стовбура: нижня точка меша — центр нижнього пучка, а сам пучок
	# сягає землі (картка розгортається на ±0,1 тайла).
	var ground_tol: float = 0.1 if node.begins_with("Hedge") else GROUND_TOL
	assert_almost_eq(box.position.y, 0.0, ground_tol, "%s: земля на y = 0" % label)
	var h_m: float = box.end.y * TILE_M
	assert_between(h_m, float(lim[0]), float(lim[1]), "%s: висота %.1f м" % [label, h_m])
	var half: float = maxf(maxf(absf(box.position.x), absf(box.end.x)), maxf(absf(box.position.z), absf(box.end.z)))
	assert_lte(half, float(lim[2]), "%s: півширина %.2f тайла" % [label, half])
	var tris: int = _tris(mi.mesh)
	assert_between(tris, int(lim[3]), int(lim[4]), "%s: %d трикутників" % [label, tris])
	# Картки пучків несуть зсув кута в UV2, а всі чотири вершини стоять у центрі; генерація
	# LOD чи сіток тіні при імпорті злила б такі вершини, і крона зникла б.
	assert_null((mi.mesh as ArrayMesh).shadow_mesh, "%s: сітку тіні вимкнено в .import" % label)
	if not label.contains("Log_") and not label.contains("Litter_"):
		var uv2: PackedVector2Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV2]
		var cards: int = 0
		for v in uv2:
			if v != Vector2.ZERO:
				cards += 1
		assert_gt(cards, 0, "%s: картки пучків мають UV2" % label)
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
		if node.begins_with("Hedge"):
			continue  # у смуги узлісся немає стовбура
		var mi: MeshInstance3D = root.find_child(node, true, false) as MeshInstance3D
		var verts: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for v in verts:
			if v.y < 0.05:
				lo = lo.min(Vector2(v.x, v.z))
				hi = hi.max(Vector2(v.x, v.z))
		assert_lt(((lo + hi) * 0.5).length(), 0.02, "%s: комель у початку координат" % node)


func test_ground_pieces() -> void:
	# Земля просіки й тінь під лісом — плоскі напівпрозорі квадрати над травою: по 2
	# трикутники, нижче за 2 см над землею, з прозорістю (а не alpha-cut — край м'який).
	var root: Node3D = _load("forest_ground")
	if root == null:
		return
	for node in ["Soil_Lane"]:
		var mi: MeshInstance3D = root.find_child(node, true, false) as MeshInstance3D
		assert_not_null(mi, "forest_ground: нема вузла %s" % node)
		if mi == null:
			continue
		var box: AABB = mi.mesh.get_aabb()
		assert_between(box.position.y, 0.0, 0.02, "%s: на землі" % node)
		assert_eq(_tris(mi.mesh), 2, "%s: 2 трикутники" % node)
		var mat: StandardMaterial3D = mi.mesh.surface_get_material(0) as StandardMaterial3D
		# glTF BLEND Godot імпортує як ALPHA_DEPTH_PRE_PASS; головне — справжня прозорість.
		assert_true(mat.transparency in [BaseMaterial3D.TRANSPARENCY_ALPHA, BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS],
				"%s: напівпрозорий" % node)


func test_tree_shadow_proxies() -> void:
	# Кожне дерево й кущ мають сітку лише для тіні: дешевий тіньовий прохід без зміни форми тіні.
	var sets: Dictionary = {"forest_conifer": CONIFER}
	for season in SEASONS:
		sets["forest_broadleaf_%s" % season] = BROADLEAF
	for glb: String in sets:
		var root: Node3D = _load(glb)
		if root == null:
			continue
		for node: String in sets[glb]:
			if not node.begins_with("Pine") and not node.begins_with("Spruce") and not node.begins_with("Birch") \
					and not node.begins_with("Oak") and not node.begins_with("Hero") and not node.begins_with("Shrub"):
				continue
			var mi: MeshInstance3D = root.find_child(node + "_Shadow", true, false) as MeshInstance3D
			assert_not_null(mi, "%s: нема %s_Shadow" % [glb, node])
			if mi != null:
				assert_lte(_tris(mi.mesh), 40, "%s/%s_Shadow: трикутників" % [glb, node])
				# Порожній проксі — дерево без тіні: пучки проксі беруться з уже відібраних.
				assert_gte(_cards(mi.mesh), 4, "%s/%s_Shadow: пучків у проксі" % [glb, node])


func test_card_offsets_centred_bark_zero() -> void:
	# Експортер glTF у Blender перевертає V кожної UV-карти: незкомпенсований UV2 доходить як
	# (x, 1 − y), і шейдер крони зсуває кожну вершину — і кору — на клітинку вгору екрана.
	# Крона тоді висить над стовбуром і своєю тінню. Чотири кути картки стоять в одній точці,
	# тож середнє їхнього UV2 — центр пучка, і він мусить бути в нулі; решта вершин
	# (кора, колоди, підстилка, яруси ялини з позначкою 1e-4) — у нулі самі.
	for glb: String in ["forest_conifer", "forest_broadleaf_late", "forest_broadleaf_summer", "forest_broadleaf_early"]:
		var root: Node3D = _load(glb)
		if root == null:
			continue
		for mi: Node in root.find_children("*", "MeshInstance3D", true, false):
			var arrays: Array = (mi as MeshInstance3D).mesh.surface_get_arrays(0)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
			var groups: Dictionary = {}
			for i in verts.size():
				groups.get_or_add(verts[i], []).append(uv2[i])
			var worst_card: float = 0.0
			var worst_rest: float = 0.0
			for g: Array in groups.values():
				var sum := Vector2.ZERO
				var far: float = 0.0
				for v: Vector2 in g:
					sum += v
					far = maxf(far, v.length())
				if far >= 1e-3:
					worst_card = maxf(worst_card, (sum / g.size()).length())
				else:
					worst_rest = maxf(worst_rest, far)
			var label: String = "%s/%s" % [glb, mi.name]
			assert_lt(worst_card, 0.01, "%s: центр картки в UV2 зсунутий на %.3f" % [label, worst_card])
			assert_lt(worst_rest, 1e-3, "%s: кора, колоди й підстилка мають UV2 = (0,0)" % label)
