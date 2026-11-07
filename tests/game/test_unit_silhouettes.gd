extends GutTest
## Заступники юнітів мають реальні розміри (1 тайл = 8 м): ширина × висота × довжина корпусу.

const UnitModelFixture := preload("res://tests/fixtures/unit_model_fixture.gd")

const _METRES := {
	2: Vector3(2.6, 2.4, 6.0), 3: Vector3(3.0, 2.6, 7.0), 4: Vector3(2.4, 2.0, 5.0),
	5: Vector3(3.6, 1.6, 7.0), 6: Vector3(3.5, 1.5, 7.5), 7: Vector3(3.3, 1.5, 6.5),
	8: Vector3(3.8, 2.0, 7.2), 11: Vector3(3.4, 2.8, 7.0),
}


func before_each() -> void:
	# Коробки, хай що лежить в assets/units: тести моделей підставляють свою сітку самі.
	UnitSilhouettes.use_models({})


func after_each() -> void:
	UnitSilhouettes.reset_models()


func test_hull_sizes_are_real_world_metres() -> void:
	for id: int in _METRES:
		assert_almost_eq((UnitSilhouettes.spec(id).hull as Vector3) * 8.0, _METRES[id], Vector3.ONE * 0.0001, "тип %d" % id)


func test_tank_is_hull_plus_08m_turret_and_gun_overhangs() -> void:
	var root: Node3D = UnitSilhouettes.build(5, Color.WHITE)
	var turret := root.get_node("Turret") as MeshInstance3D
	assert_almost_eq((turret.mesh as BoxMesh).size.y * 8.0, 0.8, 0.0001)
	assert_almost_eq(turret.position.y + (turret.mesh as BoxMesh).size.y * 0.5, 0.3, 0.0001)  # 2,4 м
	var barrel := root.get_node("Barrel") as MeshInstance3D
	assert_almost_eq(barrel.position.z - (barrel.mesh as BoxMesh).size.z * 0.5, -0.69, 0.0001)  # 5,5 м від центру башти
	root.free()


## Бюджет кадру (§8): тіло юніта — одна сітка, тобто один виклик малювання й один у тіні, а не
## по одному на корпус, башту, ствол, ходову й фігури відділення.
func test_merged_body_is_one_mesh_with_the_same_geometry() -> void:
	for id in UnitTypes.count():
		var parts: Node3D = UnitSilhouettes.build(id, Color.RED)
		var body: Node3D = UnitSilhouettes.build_merged(id, Color.RED)
		assert_eq(body.get_child_count(), 1, "тип %d: одна сітка тіла, без фігур окремо" % id)
		var hull := body.get_node("Hull") as MeshInstance3D
		assert_eq(hull.mesh.get_surface_count(), 1, "тип %d: одна поверхня" % id)
		var verts: int = 0
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		for p: Node in parts.get_children():
			if p is MeshInstance3D:
				var mi := p as MeshInstance3D
				verts += mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
				var box: AABB = mi.transform * mi.mesh.get_aabb()
				lo = lo.min(box.position)
				hi = hi.max(box.end)
			elif p is MultiMeshInstance3D:
				var mm: MultiMesh = (p as MultiMeshInstance3D).multimesh
				for i in mm.instance_count:
					verts += mm.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
					# Під headless MultiMesh назад не читається: місця фігур — з figure_transform.
					var box: AABB = UnitSilhouettes.figure_transform(i, true) * mm.mesh.get_aabb()
					lo = lo.min(box.position)
					hi = hi.max(box.end)
		assert_eq(hull.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size(), verts, "тип %d: ті самі вершини" % id)
		var merged: AABB = hull.mesh.get_aabb()
		assert_almost_eq(merged.position, lo, Vector3.ONE * 0.0001, "тип %d: низ" % id)
		assert_almost_eq(merged.end, hi, Vector3.ONE * 0.0001, "тип %d: верх" % id)
		assert_eq(hull.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "тип %d: тіло кидає тінь" % id)
		parts.free()
		body.free()


## Колір власника лежить у вершинах: нейтральні ствол і ходова лишаються нейтральними, а один
## спільний матеріал не мусить знати власника.
func test_merged_body_keeps_owner_colour_on_hull_and_neutral_barrel() -> void:
	var red: Node3D = UnitSilhouettes.build_merged(5, Color.RED)
	var blue: Node3D = UnitSilhouettes.build_merged(5, Color.BLUE)
	var a := (red.get_node("Hull") as MeshInstance3D).mesh
	var b := (blue.get_node("Hull") as MeshInstance3D).mesh
	var ca: PackedColorArray = a.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var cb: PackedColorArray = b.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	assert_true(ca.has(Color.RED), "корпус — кольором власника")
	assert_false(ca.has(Color.BLUE))
	assert_true(cb.has(Color.BLUE))
	assert_true(ca.has(UnitSilhouettes._BARREL_COLOR), "ствол — нейтральний")
	assert_same(UnitSilhouettes.build_merged(5, Color.RED).get_node("Hull").mesh, a, "та сама сітка для того самого власника")
	assert_same((red.get_node("Hull") as MeshInstance3D).material_override, (blue.get_node("Hull") as MeshInstance3D).material_override, "матеріал спільний")
	red.free()
	blue.free()


## Фігури відділення — у тій самій сітці: стоячі в кольорі власника, загиблі темні. Сітка на
## кількість стоячих окрема й кешується, тож падіння фігури — підміна сітки, а не нова.
func test_squad_figures_live_in_the_merged_mesh_by_standing_count() -> void:
	for standing in range(0, UnitView.SQUAD_FIGURES + 1):
		var body: Node3D = UnitSilhouettes.build_merged(0, Color.RED, standing)
		var colors: PackedColorArray = (body.get_node("Hull") as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		var box_verts: int = 24
		var fallen: int = colors.count(UnitSilhouettes.FALLEN_COLOR)
		assert_eq(fallen, (UnitView.SQUAD_FIGURES - standing) * box_verts, "лежачих при %d стоячих" % standing)
		# Корпус (плита) — теж Color.RED, тож стоячі + плита.
		assert_eq(colors.count(Color.RED), (standing + 1) * box_verts, "стоячих при %d" % standing)
		body.free()
	assert_same(UnitSilhouettes.build_merged(0, Color.RED, 2).get_node("Hull").mesh, UnitSilhouettes.build_merged(0, Color.RED, 2).get_node("Hull").mesh)


## Модель береться, коли файл є, і коробки — коли нема: без асету гра не ламається.
func test_model_is_used_only_when_its_file_exists() -> void:
	UnitSilhouettes.reset_models()
	for id in UnitTypes.count():
		assert_eq(UnitSilhouettes.has_model(id), ResourceLoader.exists(UnitSilhouettes.model_path(id)), "тип %d" % id)
	assert_eq(UnitSilhouettes.model_path(5), "res://assets/units/medium_tank.glb")
	var model: ArrayMesh = UnitModelFixture.vehicle(5)
	UnitSilhouettes.use_models({5: model})
	var tank := UnitSilhouettes.build_merged(5, Color.RED).get_node("Hull") as MeshInstance3D
	assert_same(tank.mesh, model, "тіло — сітка моделі")
	assert_true(tank.material_override is ShaderMaterial)
	var car := UnitSilhouettes.build_merged(2, Color.RED).get_node("Hull") as MeshInstance3D
	assert_true(car.material_override is StandardMaterial3D, "без моделі — коробки")
	tank.get_parent().free()
	car.get_parent().free()


## Один матеріал на тип для всіх власників: колір — instance uniform вузла, а specular —
## імпортованого матеріалу (типові 0,5 власного шейдера світлішали б модель).
func test_model_owners_share_mesh_and_material() -> void:
	UnitSilhouettes.use_models({5: UnitModelFixture.vehicle(5)})
	var red := UnitSilhouettes.build_merged(5, Color.RED).get_node("Hull") as MeshInstance3D
	var blue := UnitSilhouettes.build_merged(5, Color.BLUE).get_node("Hull") as MeshInstance3D
	assert_same(red.mesh, blue.mesh)
	assert_same(red.material_override, blue.material_override)
	assert_eq(red.get_instance_shader_parameter("owner_color"), Color.RED)
	assert_eq(blue.get_instance_shader_parameter("owner_color"), Color.BLUE)
	var mat := red.material_override as ShaderMaterial
	assert_almost_eq(float(mat.get_shader_parameter("specular")), UnitModelFixture.SPECULAR, 0.0001)
	assert_not_null(mat.get_shader_parameter("albedo_tex"))
	assert_almost_eq(float(mat.get_shader_parameter("wheel_radius")), 0.06, 0.0001)
	red.get_parent().free()
	blue.get_parent().free()


## Відділення — четверо бійців в одній сітці; стоять перші `standing` ступнями на основі,
## загиблі лежать і не несуть знаку власника. Сітка на кількість стоячих кешується.
func test_model_squad_is_four_soldiers_by_standing_count() -> void:
	var soldier: ArrayMesh = UnitModelFixture.soldier()
	UnitSilhouettes.use_models({0: soldier})
	var verts: int = soldier.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
	var marks: int = UnitModelFixture.marked_vertices(soldier)
	var meshes: Array[Mesh] = []
	for standing in range(0, UnitView.SQUAD_FIGURES + 1):
		var m: Mesh = UnitSilhouettes.merged_mesh(0, Color.RED, standing)
		assert_eq(m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size(), 4 * verts, "4 бійці при %d" % standing)
		assert_eq(UnitModelFixture.marked_vertices(m), standing * marks, "знак лише на стоячих при %d" % standing)
		assert_false(meshes.has(m), "інша сітка при %d" % standing)
		meshes.append(m)
	assert_same(UnitSilhouettes.merged_mesh(0, Color.BLUE, 2), meshes[2], "сітка не залежить від власника")
	var full: AABB = meshes[4].get_aabb()
	assert_almost_eq(full.position.y, 0.05, 0.0001, "ступні на основі")
	assert_almost_eq(full.end.y, 0.05 + UnitSilhouettes.FIGURE_SIZE.y, 0.0001, "1,8 м заввишки")
	assert_lt(meshes[0].get_aabb().end.y, 0.05 + UnitSilhouettes.FIGURE_SIZE.y * 0.5, "загиблі лежать")


## Перетворення вузла GLB впікається в сітку, а вісь колеса в UV2 їде разом із ним.
func test_model_merge_bakes_node_transform_into_vertices_and_axles() -> void:
	var src: ArrayMesh = UnitModelFixture.vehicle(5)
	var xfs: Array[Transform3D] = [Transform3D(Basis(), Vector3(0.0, 0.1, 0.2))]
	var marked: Array[bool] = [true]
	var out: ArrayMesh = UnitSilhouettes._merge_model(src, xfs, marked)
	assert_almost_eq(out.get_aabb().position, src.get_aabb().position + Vector3(0.0, 0.1, 0.2), Vector3.ONE * 0.0001)
	var c: PackedColorArray = out.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var uv2: PackedVector2Array = out.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV2]
	var src_uv2: PackedVector2Array = src.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV2]
	for i in c.size():
		if c[i].b > 0.5:
			assert_almost_eq(uv2[i], src_uv2[i] + Vector2(0.1, 0.2), Vector2.ONE * 0.0001)
			return
	fail_test("у сітці нема коліс")


## Імпорт моделей: без стиснення (точність UV2), без LOD і тіньових сіток (злиття їх однаково
## губить), UV2 не перегенеровується під lightmap (light_baking 2 стер би траки й колеса).
func test_unit_model_imports_keep_uv2_exact() -> void:
	var dir := DirAccess.open(UnitSilhouettes.MODEL_DIR)
	if dir == null:
		pass_test("моделей ще нема")
		return
	for f: String in dir.get_files():
		if not f.ends_with(".glb.import"):
			continue
		var cfg := ConfigFile.new()
		assert_eq(cfg.load(UnitSilhouettes.MODEL_DIR + f), OK, f)
		assert_eq(cfg.get_value("params", "meshes/force_disable_compression"), true, f)
		assert_eq(cfg.get_value("params", "meshes/generate_lods"), false, f)
		assert_eq(cfg.get_value("params", "meshes/create_shadow_meshes"), false, f)
		assert_ne(cfg.get_value("params", "meshes/light_baking"), 2, f)
	pass_test("перевірено")
