extends GutTest
## Зламані версії опор і парканів (assets/props/broken): діти сцени — лише piece_NN, зібрані шматки збігаються
## габаритом із вихідною моделлю, а трикутників не більше max(1.5 x вихідник, FLOOR). Контракт для анімації:
## початок кожного шматка в його центрі мас, тож по позиціях шматків і їхніх AABB відновлюється вся модель.

const DIR: String = "res://assets/props/"
const BROKEN: String = "res://assets/props/broken/"
const M: float = 8.0
## Допуск габариту — 2 см у метрах гри.
const AABB_TOL: float = 0.02 / M
## Вихідні опори мають 72-120 трикутників, а кожен різ додає ~15-35: пропорція 1.5 x не вміщує й пеньок із
## сегментами. Стеля для таких мікромоделей; див. tools/blender/infra/broken_props.py.
const TRI_FLOOR: int = 520
const MIN_PIECES: int = 6
## Менші за це шматки — справа частинок, а не моделі.
const MIN_PIECE_M: float = 0.1
## Верх кожного виду парканів двору, м (tools/blender/infra/yard_fences.py, HEIGHT).
const YARD_TOP: Dictionary = {"picket": 1.3, "sheet": 1.8, "chainlink": 1.52, "brickbars": 1.66, "slat": 1.5}
const YARD_SRC_TRIS: int = 2   # одна картка виду


func _models() -> Array[String]:
	var out: Array[String] = ["infra_pole_concrete_10kv", "infra_pole_concrete_04kv", "infra_pole_wood", "infra_fence_picket",
			"infra_fence_sheet_green", "infra_fence_sheet_brown", "infra_fence_euro"]
	for k: String in YARD_TOP:
		out.append("infra_fence_yard_" + k)
	return out


func _source_name(model: String) -> String:
	return "infra_fence_yard" if model.begins_with("infra_fence_yard_") else model


func _peak(v: Vector3) -> float:
	return maxf(maxf(absf(v.x), absf(v.y)), absf(v.z))


func _tris(mi: MeshInstance3D) -> int:
	var t: int = 0
	for s in mi.mesh.get_surface_count():
		t += (mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return t


func _collect(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			out.append(n)
		stack.append_array(n.get_children())
	return out


func _union(meshes: Array[MeshInstance3D], root: Node3D) -> AABB:
	var box := AABB()
	var first: bool = true
	for mi in meshes:
		var b: AABB = root.global_transform.affine_inverse() * mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func test_every_broken_model_matches_contract() -> void:
	for model in _models():
		var scene: PackedScene = load(BROKEN + model + "_broken.glb")
		assert_not_null(scene, model + ": нема зламаної моделі")
		if scene == null:
			continue
		var broken: Node3D = scene.instantiate()
		add_child_autofree(broken)
		var pieces: Array[MeshInstance3D] = []
		var idx: int = 0
		for c in broken.get_children():
			assert_true(c is MeshInstance3D, "%s: дитина %s не MeshInstance3D" % [model, c.name])
			assert_eq(String(c.name), "piece_%02d" % idx, model + ": нумерація шматків")
			idx += 1
			pieces.append(c as MeshInstance3D)
		for mi in pieces:
			var sz: Vector3 = mi.get_aabb().size
			assert_true(maxf(maxf(sz.x, sz.y), sz.z) >= MIN_PIECE_M / M - 1e-4, "%s: %s завбільшки %s замалий" % [model, mi.name, sz])
		assert_true(pieces.size() >= MIN_PIECES, "%s: лише %d шматків" % [model, pieces.size()])

		var src_scene: PackedScene = load(DIR + _source_name(model) + ".glb")
		var src: Node3D = src_scene.instantiate()
		add_child_autofree(src)
		var src_meshes := _collect(src)
		var got := _union(pieces, broken)
		var want := _union(src_meshes, src)
		var src_tris: int = 0
		for mi in src_meshes:
			src_tris += _tris(mi)
		if model.begins_with("infra_fence_yard_"):
			var kind: String = model.trim_prefix("infra_fence_yard_")
			want = AABB(Vector3(-0.5, 0.0, 0.0), Vector3(1.0, YARD_TOP[kind] / M, 0.0))
			src_tris = YARD_SRC_TRIS
		var d: float = maxf(_peak(got.position - want.position), _peak(got.end - want.end))
		assert_true(d <= AABB_TOL, "%s: габарит шматків %s, вихідника %s" % [model, got, want])
		var tris: int = 0
		for mi in pieces:
			tris += _tris(mi)
		var limit: int = maxi(int(src_tris * 1.5), TRI_FLOOR)
		assert_true(tris <= limit, "%s: %d трикутників при ліміті %d" % [model, tris, limit])
