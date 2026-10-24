extends GutTest

## Ім'я -> [ліміт трикутників, розмір X, Y (висота), Z у тайлах]. Розмір — реальні метри / 8,
## бо 1 тайл = 8 м; Tripo метрів не тримає, тож габарит підганяється при нормалізації.
const PROPS: Dictionary = {
	"house_h1": [5000, 1.25, 0.75, 1.0],
	"house_h2": [5000, 1.375, 0.875, 1.125],
	"house_h3": [5000, 1.25, 1.1875, 1.25],
	"house_h4": [5000, 1.125, 0.6875, 0.75],
	"ruin_h1": [5000, 1.75, 0.625, 1.5],
	"ruin_h2": [5000, 1.75, 0.625, 1.75],
	"ruin_h5": [5000, 4.25, 1.0, 2.0],
	"barn_f1": [2500, 1.875, 0.8125, 0.875],
	"wall_field": [800, 1.0, 0.1125, 0.075],
	"tree_oak_late": [3000, 1.75, 2.5, 1.75],
	"tree_oak_summer": [3000, 1.75, 2.5, 1.75],
	"tree_oak_early": [3000, 1.75, 2.5, 1.75],
	"tree_birch_late": [3000, 0.625, 2.25, 0.625],
	"tree_birch_summer": [3000, 0.625, 2.25, 0.625],
	"tree_birch_early": [3000, 0.625, 2.25, 0.625],
	"rock_moss_01": [600, 0.281, 0.185, 0.42],
	"rock_moss_02": [600, 0.226, 0.153, 0.377],
	"rock_moss_03": [600, 0.246, 0.162, 0.192],
	"rock_moss_04": [600, 0.275, 0.095, 0.194],
	"boulder_01": [600, 0.16, 0.124, 0.224],
	"tree_stump_01": [600, 0.178, 0.072, 0.199],
	"dead_tree_trunk_02": [600, 0.502, 0.129, 0.111],
}
const GROUND_TOLERANCE: float = 0.02
const SIZE_TOLERANCE: float = 0.05

func test_every_prop_exists_is_grounded_and_within_budget(p = use_parameters(PROPS.keys())) -> void:
	var scene: PackedScene = load("res://assets/props/%s.glb" % p) as PackedScene
	assert_not_null(scene, "нема assets/props/%s.glb" % p)
	if scene == null:
		return
	var root: Node3D = scene.instantiate()
	add_child_autofree(root)
	var spec: Array = PROPS[p]

	var box := AABB()
	var first := true
	var tris: int = 0
	for m: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = m.global_transform * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
		for s in m.mesh.get_surface_count():
			var arrays: Array = m.mesh.surface_get_arrays(s)
			tris += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	assert_false(first, "%s: у сцені нема меша" % p)

	assert_almost_eq(box.position.y, 0.0, GROUND_TOLERANCE, "%s: має стояти на y = 0" % p)
	assert_lte(tris, spec[0] as int, "%s: трикутників %d" % [p, tris])
	var want := Vector3(spec[1], spec[2], spec[3])
	for axis in 3:
		assert_almost_eq(box.size[axis], want[axis], want[axis] * SIZE_TOLERANCE + 0.005,
			"%s: габарит по осі %d" % [p, axis])
