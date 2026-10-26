extends GutTest
## Будівлі з Blender: стоять на землі, лежать усередині цілого сліду в тайлах (виступ не більше 0.1 тайла)
## і вкладаються в бюджет трикутників.

const _DIR: String = "res://assets/props/"
## імʼя -> [слід X, слід Z у тайлах, ліміт трикутників]
const _PROPS: Dictionary = {
	"h5_panel_block": [4, 2, 2500],
	"h5_panel_block_damaged": [5, 2, 4600],
	"f1_farm_barn": [2, 1, 400],
	"f2_livestock_barn": [2, 8, 400],
	"f3_hangar": [3, 5, 1000],
	"f3_hangar_damaged": [3, 5, 3000],
	"f4_grain_bins": [4, 2, 2000],
	"f5_silo_battery": [5, 2, 1200],
	"f6_fuel_station": [4, 2, 1200],
	"f7_water_tower": [1, 1, 700],
	"f7b_brick_tower": [1, 1, 900],
	"house_h1": [2, 1, 2200],
	"house_h1_hit": [2, 1, 2600],
	"house_h2": [2, 2, 2200],
	"house_h3": [2, 2, 2400],
	"house_h4": [2, 1, 1800],
	"ruin_h1": [1, 1, 4800],
	"ruin_h3": [1, 1, 4800],
	"house_h5": [1, 1, 2200],
	"house_h6": [1, 1, 2600],
	"f8_shed": [1, 1, 1600],
	"ruin_half_house1": [1, 1, 4600],
	"ruin_half_house2": [1, 1, 4800],
	"ruin_half_shed": [1, 1, 4600],
}
## Стоять лише на клітинках кільця навколо поля, а не на ігровому полі.
const RING_ONLY: Array[String] = ["f2_livestock_barn"]
const _OVERHANG: float = 0.1


func _bounds(root: Node) -> Array:
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	var tris: int = 0
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var box: AABB = mi.global_transform * mi.mesh.get_aabb()
		lo = lo.min(box.position)
		hi = hi.max(box.end)
		for s in mi.mesh.get_surface_count():
			tris += (mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return [lo, hi, tris]


func _has_normal_map(root: Node) -> bool:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s) as BaseMaterial3D
			if m == null or m.normal_texture == null:
				return false
	return true


func _footprint_meta(root: Node) -> Array:
	for n in [root] + root.find_children("*", "", true, false):
		if n.has_meta("extras"):
			var ex: Variant = n.get_meta("extras")
			if ex is Dictionary and (ex as Dictionary).has("footprint_tiles"):
				return (ex as Dictionary)["footprint_tiles"]
	return []


func test_every_building_rests_on_the_ground_inside_its_footprint() -> void:
	for id in _PROPS:
		var scene := load(_DIR + id + ".glb") as PackedScene
		assert_not_null(scene, "%s: GLB не завантажився" % id)
		if scene == null:
			continue
		var inst: Node3D = scene.instantiate()
		add_child_autofree(inst)
		var b: Array = _bounds(inst)
		var lo: Vector3 = b[0]
		var hi: Vector3 = b[1]
		var spec: Array = _PROPS[id]
		var hx: float = float(spec[0]) / 2.0 + _OVERHANG
		var hz: float = float(spec[1]) / 2.0 + _OVERHANG
		assert_almost_eq(lo.y, 0.0, 0.02, "%s: низ на землі" % id)
		assert_true(lo.x >= -hx and hi.x <= hx, "%s: X поза слідом %s" % [id, spec])
		assert_true(lo.z >= -hz and hi.z <= hz, "%s: Z поза слідом %s" % [id, spec])
		assert_lte(b[2] as int, spec[2] as int, "%s: трикутники" % id)
		assert_true(_has_normal_map(inst), "%s: нема карти нормалей" % id)
		var meta: Array = _footprint_meta(inst)
		assert_eq(meta.size(), 2, "%s: нема footprint_tiles у метаданих" % id)
		if meta.size() == 2:
			assert_eq([int(meta[0]), int(meta[1])], [spec[0], spec[1]], "%s: footprint_tiles" % id)


func test_ring_only_buildings_are_listed_in_the_props() -> void:
	for id in RING_ONLY:
		assert_true(_PROPS.has(id), id)
