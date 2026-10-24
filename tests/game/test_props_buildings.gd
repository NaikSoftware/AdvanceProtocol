extends GutTest
## Будівлі з Blender: кожна лежить на землі, має очікуваний слід у тайлах і вкладається в бюджет трикутників.

const _DIR: String = "res://assets/props/"
## імʼя -> [ширина X, глибина Z у тайлах, ліміт трикутників]
const _PROPS: Dictionary = {
	"h5_panel_block": [3.75, 1.65, 600],
	"h5_panel_block_damaged": [4.37, 2.70, 1300],
	"f2_livestock_barn": [2.06, 7.63, 400],
	"f3_hangar": [2.33, 4.58, 150],
	"f3_hangar_damaged": [3.87, 4.56, 900],
	"f4_grain_bins": [4.0, 1.48, 1000],
	"f5_silo_battery": [4.5, 1.63, 700],
	"f6_fuel_station": [3.63, 1.33, 300],
	"f7_water_tower": [0.43, 0.38, 300],
	"f7b_brick_tower": [0.8, 0.8, 400],
}
const _EPS: float = 0.03


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


func test_every_building_rests_on_the_ground_with_its_footprint_and_budget() -> void:
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
		assert_almost_eq(lo.y, 0.0, 0.02, "%s: низ на землі" % id)
		assert_almost_eq(hi.x - lo.x, spec[0], _EPS, "%s: ширина" % id)
		assert_almost_eq(hi.z - lo.z, spec[1], _EPS, "%s: глибина" % id)
		assert_almost_eq(lo.x + hi.x, 0.0, 0.02, "%s: центр по X" % id)
		assert_almost_eq(lo.z + hi.z, 0.0, 0.02, "%s: центр по Z" % id)
		assert_lte(b[2] as int, spec[2] as int, "%s: трикутники" % id)
