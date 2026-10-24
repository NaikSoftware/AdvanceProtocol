extends GutTest

## Ім'я -> [ліміт трикутників, footprint_tiles X, Z (0 — об'єкт не стоїть на клітинках BUILDING), найбільший горизонтальний
## габарит у тайлах для таких об'єктів]. Будівля стоїть лише на своїх клітинках: тайл — 8 м,
## на край лишається запас на карнизи.
const PROPS: Dictionary = {
	"house_h1": [5000, 2, 1, 0.0],
	"house_h2": [5000, 2, 1, 0.0],
	"house_h3": [5000, 2, 2, 0.0],
	"house_h4": [5000, 1, 2, 0.0],
	"house_h1_hit": [5000, 2, 2, 0.0],
	"ruin_h1": [5000, 2, 2, 0.0],
	"ruin_h3": [5000, 3, 3, 0.0],
	"wall_field": [800, 0, 0, 1.1],
	"rock_moss_01": [600, 0, 0, 0.5],
	"rock_moss_02": [600, 0, 0, 0.5],
	"rock_moss_03": [600, 0, 0, 0.5],
	"rock_moss_04": [600, 0, 0, 0.5],
	"boulder_01": [600, 0, 0, 0.5],
	"tree_stump_01": [600, 0, 0, 0.5],
	"dead_tree_trunk_02": [600, 0, 0, 0.6],
}
const GROUND_TOLERANCE: float = 0.02
## 7.6 м з 8 — будівля не заходить у сусідню клітинку.
const TILE_FILL: float = 0.95

func _glb_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	f.seek(12)
	var size: int = f.get_32()
	f.get_32()
	return JSON.parse_string(f.get_buffer(size).get_string_from_utf8())

func test_every_prop_exists_is_grounded_and_within_budget(p = use_parameters(PROPS.keys())) -> void:
	var path := "res://assets/props/%s.glb" % p
	var scene: PackedScene = load(path) as PackedScene
	assert_not_null(scene, "нема %s" % path)
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

	var tiles := Vector2i(spec[1], spec[2])
	if tiles == Vector2i.ZERO:
		assert_lte(maxf(box.size.x, box.size.z), spec[3] as float, "%s: горизонтальний габарит" % p)
		return
	# footprint_tiles у extras вузла — те, що PropLayer читає для клітинок BUILDING.
	var found: Array = []
	for n: Dictionary in _glb_json(ProjectSettings.globalize_path(path))["nodes"]:
		if n.has("extras") and (n["extras"] as Dictionary).has("footprint_tiles"):
			found = n["extras"]["footprint_tiles"]
	assert_eq(found.size(), 2, "%s: нема footprint_tiles" % p)
	if found.size() == 2:
		assert_eq(Vector2i(int(found[0]), int(found[1])), tiles, "%s: footprint_tiles" % p)
	assert_lte(box.size.x, tiles.x * TILE_FILL + 0.001, "%s: ширина в тайлах" % p)
	assert_lte(box.size.z, tiles.y * TILE_FILL + 0.001, "%s: глибина в тайлах" % p)
