extends GutTest

## Довжина — рівно переправа на карті River (клітинок); зруйнований стан не довший за неї.
const BRIDGES: Dictionary = {
	"bridge_river_centre": 3, "bridge_river_west": 2, "bridge_river_east": 2,
}
const TRIS_MAX: int = 1500
const GROUND_TOLERANCE: float = 0.02
## Уламки можуть зсунутись за течією за клітинку мосту, але не далі за сусідню.
const HALF_WIDTH_MAX: float = 0.75
## Понтон плаває за 0.075 над дном, тож рештки відсіку можуть сидіти нижче нуля моделі, не пробиваючи русла.
const BROKEN_BELOW_GROUND: Dictionary = {"bridge_river_east": 0.1}

func _bounds(name: String) -> Dictionary:
	var scene: PackedScene = load("res://assets/props/%s.glb" % name) as PackedScene
	assert_not_null(scene, "нема assets/props/%s.glb" % name)
	var root: Node3D = scene.instantiate()
	add_child_autofree(root)
	var box := AABB()
	var first := true
	var tris: int = 0
	for m: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = m.global_transform * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
		for s in m.mesh.get_surface_count():
			tris += (m.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return {"box": box, "tris": tris}

func test_intact_bridge_has_exact_length_and_sits_on_ground(p = use_parameters(BRIDGES.keys())) -> void:
	var r: Dictionary = _bounds(p)
	var box: AABB = r["box"]
	assert_almost_eq(box.position.y, 0.0, GROUND_TOLERANCE, "%s: має стояти на y = 0" % p)
	assert_almost_eq(box.size.z, float(BRIDGES[p]), 0.02, "%s: довжина" % p)
	assert_lte(box.size.x, 1.0, "%s: ширина" % p)
	assert_lte(r["tris"], TRIS_MAX, "%s: трикутників %d" % [p, r["tris"]])

func test_broken_bridge_stays_in_footprint(p = use_parameters(BRIDGES.keys())) -> void:
	var r: Dictionary = _bounds(p + "_broken")
	var box: AABB = r["box"]
	assert_gte(box.position.y, -float(BROKEN_BELOW_GROUND.get(p, GROUND_TOLERANCE)), "%s: руїна нижче дна" % p)
	assert_lte(box.size.z, float(BRIDGES[p]) + 0.02, "%s: руїна довша за переправу" % p)
	assert_lte(maxf(absf(box.position.x), absf(box.end.x)), HALF_WIDTH_MAX, "%s: уламки далеко вбік" % p)
	assert_lte(r["tris"], TRIS_MAX, "%s: трикутників %d" % [p, r["tris"]])
