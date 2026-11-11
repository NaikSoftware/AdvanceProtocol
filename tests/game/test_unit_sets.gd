extends GutTest
## Набори техніки: набір — це місце гравця, тип без власної моделі в наборі бере модель і рядок набору 0.

const UnitModelFixture := preload("res://tests/fixtures/unit_model_fixture.gd")
const UnitViewScene := preload("res://game/battle/unit_view.tscn")

var _row:Dictionary = {"hull": Vector3(0.5, 0.2, 0.9), "barrel": 0.7, "wheel": 0.05, "extras": [&"turret"]}


func before_each() -> void:
	UnitSilhouettes.use_models({})


func after_each() -> void:
	UnitSilhouettes.reset_models()


func test_set_follows_owner_slot() -> void:
	var sets: Array = []
	for o in 7:
		sets.append(UnitSilhouettes.set_of(o))
	assert_eq(sets, [0, 1, 2, 0, 1, 2, 0])


func test_model_paths_per_set() -> void:
	assert_eq(UnitSilhouettes.model_path(5), "res://assets/units/medium_tank.glb")
	assert_eq(UnitSilhouettes.model_path(5, 1), "res://assets/units/set1/medium_tank.glb")
	assert_eq(UnitSilhouettes.model_path(8, 2), "res://assets/units/set2/heavy_tank.glb")


func test_set_without_model_falls_back_to_set_zero_model_and_spec() -> void:
	var m0: ArrayMesh = UnitModelFixture.vehicle(5)
	UnitSilhouettes.use_models({5: m0})
	UnitSilhouettes.use_set_specs({1: {5: _row}})
	assert_same(UnitSilhouettes.model_mesh(5, 1), m0)
	assert_same(UnitSilhouettes.merged_mesh(5, -1, 1), m0)
	assert_eq(UnitSilhouettes.spec(5, 1), UnitSilhouettes.spec(5, 0), "рядок набору без моделі не діє")
	assert_eq(UnitSilhouettes.muzzle(5, 1), UnitSilhouettes.muzzle(5, 0))
	assert_same(UnitSilhouettes.model_material(5, 1), UnitSilhouettes.model_material(5, 0))


## Модель набору без виміру не діє: тип повністю береться з набору 0 (і модель, і рядок).
func test_set_model_without_a_spec_row_falls_back_fully() -> void:
	var m0: ArrayMesh = UnitModelFixture.vehicle(5)
	UnitSilhouettes.use_models({5: m0, Vector2i(1, 5): UnitModelFixture.mesh(_row.hull)})
	assert_same(UnitSilhouettes.model_mesh(5, 1), m0)
	assert_eq(UnitSilhouettes.spec(5, 1), UnitSilhouettes.spec(5, 0))
	assert_same(UnitSilhouettes.model_material(5, 1), UnitSilhouettes.model_material(5, 0))


## Модель, що лягла без вимірів, — помилка гучно, а не тихий відкат на набір 0.
func test_every_set_model_file_has_a_spec_row() -> void:
	for set_id in range(1, UnitSilhouettes.SET_COUNT):
		for id in UnitTypes.count():
			if ResourceLoader.exists(UnitSilhouettes.model_path(id, set_id)):
				assert_true((UnitSilhouettes._SET_SPECS.get(set_id, {}) as Dictionary).has(id), "набір %d тип %d: є модель, нема рядка в _SET_SPECS" % [set_id, id])
	pass_test("перевірено")


func test_owner_four_gets_set_one_model_and_spec() -> void:
	var m0: ArrayMesh = UnitModelFixture.vehicle(5)
	var m1: ArrayMesh = UnitModelFixture.mesh(_row.hull)
	UnitSilhouettes.use_models({5: m0, Vector2i(1, 5): m1})
	UnitSilhouettes.use_set_specs({1: {5: _row}})
	var owner_set: int = UnitSilhouettes.set_of(4)
	assert_eq(owner_set, 1)
	var body := UnitSilhouettes.build_merged(5, -1, owner_set)
	assert_same((body.get_node("Hull") as MeshInstance3D).mesh, m1)
	body.free()
	var zero := UnitSilhouettes.build_merged(5, -1, UnitSilhouettes.set_of(3))
	assert_same((zero.get_node("Hull") as MeshInstance3D).mesh, m0)
	zero.free()
	assert_eq(UnitSilhouettes.spec(5, owner_set), _row)
	assert_eq(UnitSilhouettes.muzzle(5, owner_set), Vector3(0.0, 0.2 + UnitSilhouettes.TURRET_HEIGHT * 0.5, -0.7))
	assert_eq(float(UnitSilhouettes.model_material(5, 1).get_shader_parameter("wheel_radius")), 0.05)
	assert_eq(float(UnitSilhouettes.model_material(5, 0).get_shader_parameter("wheel_radius")), float(UnitSilhouettes.spec(5).wheel))
	assert_ne(UnitSilhouettes.model_material(5, 1), UnitSilhouettes.model_material(5, 0), "матеріал — на набір")


func test_unit_view_uses_its_owners_set() -> void:
	var m1: ArrayMesh = UnitModelFixture.mesh(_row.hull)
	UnitSilhouettes.use_models({5: UnitModelFixture.vehicle(5), Vector2i(1, 5): m1})
	UnitSilhouettes.use_set_specs({1: {5: _row}})
	var view: UnitView = UnitViewScene.instantiate()
	add_child_autofree(view)
	view.bind(Unit.create(1, 5, 4, Vector2i(1, 1), 0))
	assert_same((view._silhouette.get_node("Hull") as MeshInstance3D).mesh, m1)
	assert_eq(view._hull_size, Vector3(_row.hull))


func test_wheel_radius_matches_every_existing_model() -> void:
	UnitSilhouettes.reset_models()
	var checked: int = 0
	for set_id in UnitSilhouettes.SET_COUNT:
		for id in UnitTypes.count():
			if not ResourceLoader.exists(UnitSilhouettes.model_path(id, set_id)):
				continue
			var r: float = _road_wheel_radius(UnitSilhouettes._own_model(id, set_id))
			if r < 0.0:
				continue
			checked += 1
			assert_almost_eq(float(UnitSilhouettes.spec(id, set_id).wheel), r, 0.002, "набір %d тип %d" % [set_id, id])
	assert_gt(checked, 0)


## Радіус опорного котка: найдальша від осі (UV2) вершина з маскою колеса й швидкістю 0,5 (ведуче й напрямне крутяться інакше); -1 — коліс нема.
func _road_wheel_radius(mesh: ArrayMesh) -> float:
	var a: Array = mesh.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var c: PackedColorArray = a[Mesh.ARRAY_COLOR]
	var uv2: PackedVector2Array = a[Mesh.ARRAY_TEX_UV2]
	var r: float = -1.0
	for i in v.size():
		if c[i].b > 0.5 and absf(c[i].a - 0.5) < 0.005:
			r = maxf(r, Vector2(v[i].y, v[i].z).distance_to(uv2[i]))
	return r
