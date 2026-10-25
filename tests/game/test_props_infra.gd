extends GutTest
## Інфраструктурні пропси (опори, огорожі, тюки, блок, труба, причіп): файл є, стоїть на землі
## (y_min = 0), габарит у метрах з довідника (1 тайл = 8 м), трикутників не більше бюджету,
## а в опор є точки кріплення дротів — порожні вузли wire_N, бо дроти геометрією не будуються.

const DIR: String = "res://assets/props/"
const M: float = 8.0   # метрів у тайлі
const GROUND_TOL: float = 0.02

## ім'я: [габарит X, Y, Z в метрах (±допуск), допуск, максимум трикутників, кількість wire_N]
const SPEC: Dictionary = {
	"infra_pole_concrete_10kv": [Vector3(1.9, 10.9, 0.3), 0.15, 400, 3],
	"infra_pole_concrete_04kv": [Vector3(0.9, 9.5, 0.3), 0.15, 400, 4],
	"infra_pole_wood": [Vector3(1.8, 9.2, 0.5), 0.2, 500, 3],
	"infra_tower_lattice": [Vector3(9.4, 33.5, 5.5), 1.5, 1500, 7],
	"infra_tower_lattice_lod": [Vector3(9.4, 33.5, 5.5), 1.5, 400, 7],
	"infra_fence_sheet_green": [Vector3(8.0, 2.0, 0.1), 0.2, 500, 0],
	"infra_fence_sheet_green_corner": [Vector3(4.1, 2.0, 4.1), 0.2, 500, 0],
	"infra_fence_sheet_brown": [Vector3(8.0, 2.0, 0.1), 0.2, 500, 0],
	"infra_fence_sheet_brown_corner": [Vector3(4.1, 2.0, 4.1), 0.2, 500, 0],
	"infra_fence_euro": [Vector3(8.0, 1.95, 0.25), 0.2, 500, 0],
	"infra_fence_euro_corner": [Vector3(4.1, 1.95, 4.1), 0.2, 500, 0],
	"infra_fence_po2": [Vector3(8.0, 2.5, 0.25), 0.2, 500, 0],
	"infra_fence_po2_corner": [Vector3(4.2, 2.5, 4.2), 0.2, 500, 0],
	"infra_fence_picket": [Vector3(8.0, 1.45, 0.1), 0.2, 500, 0],
	"infra_fence_picket_corner": [Vector3(4.1, 1.45, 4.1), 0.2, 500, 0],
	"infra_hay_round": [Vector3(1.2, 1.31, 1.35), 0.1, 300, 0],
	"infra_hay_wrapped": [Vector3(1.2, 1.31, 1.35), 0.1, 300, 0],
	"infra_hay_stack": [Vector3(1.2, 2.46, 2.75), 0.15, 800, 0],
	"infra_jersey_block": [Vector3(2.0, 0.8, 0.6), 0.1, 100, 0],
	"infra_culvert": [Vector3(3.1, 1.57, 10.4), 0.4, 800, 0],
	"infra_trailer_green": [Vector3(2.5, 2.37, 7.5), 0.25, 1200, 0],
	"infra_trailer_rust": [Vector3(2.5, 2.37, 7.5), 0.25, 1200, 0],
}


func _meshes(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_meshes(c, out)


func _measure(root: Node3D) -> Dictionary:
	var meshes: Array = []
	_meshes(root, meshes)
	var box: AABB
	var first: bool = true
	var tris: int = 0
	for mi: MeshInstance3D in meshes:
		var b: AABB = mi.transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
		for s in mi.mesh.get_surface_count():
			var arr: Array = mi.mesh.surface_get_arrays(s)
			tris += (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return {"box": box, "tris": tris}


func test_infra_props_fit_the_spec() -> void:
	for name: String in SPEC:
		var spec: Array = SPEC[name]
		var path: String = DIR + name + ".glb"
		assert_true(ResourceLoader.exists(path), "%s: файлу немає" % name)
		var scene: PackedScene = load(path)
		var root: Node3D = scene.instantiate()
		add_child_autofree(root)
		var m: Dictionary = _measure(root)
		var box: AABB = m["box"]
		assert_almost_eq(box.position.y, 0.0, GROUND_TOL, "%s: не стоїть на землі" % name)
		var want: Vector3 = spec[0]
		var tol: float = spec[1]
		var got: Vector3 = box.size * M
		assert_almost_eq(got.x, want.x, want.x * tol + 0.1, "%s: ширина, м" % name)
		assert_almost_eq(got.y, want.y, want.y * tol + 0.1, "%s: висота, м" % name)
		assert_almost_eq(got.z, want.z, want.z * tol + 0.1, "%s: довжина, м" % name)
		assert_lte(int(m["tris"]), int(spec[2]), "%s: більше трикутників, ніж бюджет" % name)
		assert_almost_eq(box.get_center().x, 0.0, 0.02, "%s: початок не в центрі по X" % name)
		assert_almost_eq(box.get_center().z, 0.0, 0.02, "%s: початок не в центрі по Z" % name)
		var wires: int = 0
		for c in root.get_children():
			if str(c.name).begins_with("wire_"):
				wires += 1
				assert_lte((c as Node3D).position.y, box.end.y + 0.01, "%s: wire поза габаритом" % name)
		assert_eq(wires, int(spec[3]), "%s: кількість точок кріплення дротів" % name)
