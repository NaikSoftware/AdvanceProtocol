extends GutTest

## Контракт вершинних даних бібліотек рослинності (tools/blender/vegetation/veg_build.py), на який
## спирається veg_body.gdshaderinc:
## - G — ідентифікатор пучка: дерева в нижній половині [0; 0,5) (їх тримає fade_floor), решта —
##   у верхній [0,5; 1);
## - поверхня 1 (пляма затінення) — у всіх, крім снопів очерету й рогозу;
## - бюджет трикутників: дерево 800 (гола крона пізньої пори — 1500: щільна мережа гілочок), кущ біля хати 400, інший кущ 600, сніп 300.

const LIBS: Array[String] = [
	"bank_veg_late", "bank_veg_summer", "bank_veg_early",
	"yard_veg_late", "yard_veg_summer", "yard_veg_early",
	"meadow_veg_late", "meadow_veg_summer", "meadow_veg_early",
]
const TREES: Array[String] = ["yard_apple", "yard_cherry", "yard_walnut", "meadow_pear", "meadow_oak", "meadow_willow"]
const SHEAVES: Array[String] = ["bank_reed", "bank_cattail"]


static func _starts(name: String, prefixes: Array[String]) -> bool:
	for p in prefixes:
		if name.begins_with(p):
			return true
	return false


func test_vertex_contract(p = use_parameters(LIBS)) -> void:
	var path := "res://assets/props/vegetation/%s.glb" % p
	var scene: PackedScene = load(path) as PackedScene
	assert_not_null(scene, "нема %s" % path)
	if scene == null:
		return
	var root: Node3D = scene.instantiate()
	add_child_autofree(root)
	var nodes: int = 0
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		nodes += 1
		var name := String(mi.name)
		var fallen: bool = name.ends_with("_fallen")
		var tree: bool = _starts(name, TREES)
		var sheaf: bool = _starts(name, SHEAVES)
		# G перевіряється на поверхні 0: її шейдери (veg, veg_fade*) читають G; пляма затінення
		# (поверхня 1, veg_shade.gdshader) G не читає — лише R (сила) й B (висота крони).
		var a: Array = mi.mesh.surface_get_arrays(0)
		var col: PackedColorArray = a[Mesh.ARRAY_COLOR]
		var bad_g: int = 0
		for i in col.size():
			if (col[i].g < 0.5) != tree:
				bad_g += 1
		assert_eq(bad_g, 0, "%s/%s: G (дерево/решта) не за контрактом у %d вершин" % [p, name, bad_g])
		var want_surfaces: int = 1 if sheaf else 2
		assert_eq(mi.mesh.get_surface_count(), want_surfaces, "%s/%s: поверхонь" % [p, name])
		var tris: int = 0
		for s in mi.mesh.get_surface_count():
			tris += (mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		var limit: int = (1500 if p.ends_with("_late") else 800) if tree else (300 if sheaf else (400 if p.begins_with("yard") else 600))
		assert_lte(tris, limit, "%s/%s: трикутників %d" % [p, name, tris])
	assert_gt(nodes, 0, "%s: нема вузлів" % p)
