extends GutTest
## Заступники юнітів мають реальні розміри (1 тайл = 8 м): ширина × висота × довжина корпусу.

const UnitModelFixture := preload("res://tests/fixtures/unit_model_fixture.gd")

const _METRES := {
	2: Vector3(2.7, 2.4, 6.6), 3: Vector3(2.7, 2.6, 7.6), 4: Vector3(2.2, 2.0, 4.9),
	5: Vector3(3.44, 1.6, 6.72), 6: Vector3(3.5, 1.5, 7.5), 7: Vector3(2.94, 1.5, 5.6),
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
	var root: Node3D = UnitSilhouettes.build(5)
	var turret := root.get_node("Turret") as MeshInstance3D
	assert_almost_eq((turret.mesh as BoxMesh).size.y * 8.0, 0.8, 0.0001)
	assert_almost_eq(turret.position.y + (turret.mesh as BoxMesh).size.y * 0.5, 0.3, 0.0001)  # 2,4 м
	var barrel := root.get_node("Barrel") as MeshInstance3D
	assert_almost_eq(barrel.position.z - (barrel.mesh as BoxMesh).size.z * 0.5, -0.625, 0.0001)  # 5,0 м від центру тайла
	root.free()


## Бюджет кадру (§8): тіло юніта — одна сітка, тобто один виклик малювання й один у тіні, а не
## по одному на корпус, башту, ствол, ходову й фігури відділення.
func test_merged_body_is_one_mesh_with_the_same_geometry() -> void:
	for id in UnitTypes.count():
		var parts: Node3D = UnitSilhouettes.build(id)
		var body: Node3D = UnitSilhouettes.build_merged(id)
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


## Тіло не несе кольору гравця: корпус один нейтральний колір, ствол інший нейтральний, а сітка
## й матеріал — ті самі для всіх юнітів типу.
func test_merged_body_is_one_neutral_colour_for_everyone() -> void:
	var a_body: Node3D = UnitSilhouettes.build_merged(5)
	var b_body: Node3D = UnitSilhouettes.build_merged(5)
	var a := (a_body.get_node("Hull") as MeshInstance3D).mesh
	var ca: PackedColorArray = a.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	assert_true(ca.has(UnitSilhouettes.BODY_COLOR), "корпус — нейтральний колір")
	assert_true(ca.has(UnitSilhouettes._BARREL_COLOR), "ствол — нейтральний")
	for c: Color in UnitView.PLAYER_COLORS:
		assert_false(ca.has(c), "жодного кольору гравця у вершинах")
	assert_same((b_body.get_node("Hull") as MeshInstance3D).mesh, a)
	assert_same((a_body.get_node("Hull") as MeshInstance3D).material_override, (b_body.get_node("Hull") as MeshInstance3D).material_override, "матеріал спільний")
	a_body.free()
	b_body.free()


## Стоячі фігури відділення — у тій самій сітці, що й плита, у нейтральному кольорі тіла; загиблих у ній
## немає: вони лежать там, де впали (шар тіл). Сітка на кількість стоячих окрема й кешується.
func test_squad_figures_live_in_the_merged_mesh_by_standing_count() -> void:
	for standing in range(0, UnitView.SQUAD_FIGURES + 1):
		var body: Node3D = UnitSilhouettes.build_merged(0, standing)
		var colors: PackedColorArray = (body.get_node("Hull") as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		var box_verts: int = 24
		assert_eq(colors.count(UnitSilhouettes.FALLEN_COLOR), 0, "лежачих у відділенні при %d стоячих" % standing)
		# Корпус (плита) — теж BODY_COLOR, тож стоячі + плита.
		assert_eq(colors.count(UnitSilhouettes.BODY_COLOR), (standing + 1) * box_verts, "стоячих при %d" % standing)
		assert_eq(colors.size(), (standing + 1) * box_verts)
		body.free()
	assert_same(UnitSilhouettes.build_merged(0, 2).get_node("Hull").mesh, UnitSilhouettes.build_merged(0, 2).get_node("Hull").mesh)


## Кожне місце має свій сталий поворот, щоб четверо не стояли клонами, а в середньому відділення
## дивиться туди ж, куди його напрям; без випадковості — те саме щоразу.
func test_each_slot_has_its_own_fixed_yaw_and_the_squad_keeps_its_facing() -> void:
	var yaws: Array[float] = []
	var sum: float = 0.0
	for i in UnitView.SQUAD_FIGURES:
		var b: Basis = UnitSilhouettes.figure_transform(i, true).basis
		var m: Basis = UnitSilhouettes.model_figure_transform(UnitModelFixture.soldier(), i, true).basis
		var yaw: float = b.get_euler().y
		assert_almost_eq(m.get_euler().y, yaw, 0.0001, "коробка й модель на місці %d повернуті однаково" % i)
		assert_almost_eq(b.y.y, 1.0, 0.0001, "стоїть рівно")
		assert_between(absf(yaw), deg_to_rad(5.0), deg_to_rad(25.0), "місце %d повернуте, але не боком" % i)
		for other: float in yaws:
			assert_gt(absf(yaw - other), deg_to_rad(5.0), "жодні два не однакові")
		yaws.append(yaw)
		sum += yaw
	assert_lt(absf(sum / UnitView.SQUAD_FIGURES), deg_to_rad(5.0), "середній поворот — напрям відділення")
	assert_eq(UnitSilhouettes.figure_transform(2, true), UnitSilhouettes.figure_transform(2, true))


## Труб дрона на штурмовому відділенні стільки, скільки дронів лишилось (§3.9), і несуть їх перші стоячі
## місця; решта — простий боєць стрілецького. Без дронів відділення таке саме, як стрілецьке.
func test_assault_squad_carries_one_tube_per_drone_left() -> void:
	var plain: ArrayMesh = UnitModelFixture.soldier()
	var tube: ArrayMesh = UnitModelFixture.tube_soldier()
	UnitSilhouettes.use_models({0: plain, 1: tube})
	var v: int = plain.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
	var top_plain: float = 0.05 + UnitSilhouettes.FIGURE_SIZE.y
	var top_tube: float = 0.05 + 0.3
	for standing in range(1, UnitView.SQUAD_FIGURES + 1):
		for drones in 3:
			var m: ArrayMesh = UnitSilhouettes.merged_mesh(1, standing, 0, drones)
			var p: PackedVector3Array = m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			assert_eq(p.size(), standing * v, "%d стоячих, %d дронів" % [standing, drones])
			var tall: int = 0
			for i in range(0, p.size(), v):
				var hi: float = -INF
				for k in v:
					hi = maxf(hi, p[i + k].y)
				if hi > top_plain + 0.01:
					tall += 1
			assert_eq(tall, mini(drones, standing), "труб при %d стоячих і %d дронах" % [standing, drones])
	assert_almost_eq(UnitSilhouettes.merged_mesh(1, 4, 0, 2).get_aabb().end.y, top_tube, 0.0001)
	assert_ne(UnitSilhouettes.merged_mesh(1, 4, 0, 1), UnitSilhouettes.merged_mesh(1, 4, 0, 2), "сітка на число труб")
	assert_same(UnitSilhouettes.merged_mesh(1, 4, 0, 1), UnitSilhouettes.merged_mesh(1, 4, 0, 1), "і кешується")
	# Відділення з трубами й без — один матеріал штурмовика: обидві моделі на одному атласі.
	var body := UnitSilhouettes.build_merged(1, 4, 0, 2)
	assert_same((body.get_node("Hull") as MeshInstance3D).material_override, UnitSilhouettes.model_material(1))
	body.free()
	assert_almost_eq(UnitSilhouettes.merged_mesh(0, 4, 0, 2).get_aabb().end.y, top_plain, 0.0001, "стрілецьке труб не несе")


## Тіла одного вигляду — одна сітка: лежать ниць, низько й рівно на основі відділення, позначені R = 1
## (шейдер темнить), а для коробок — темним кольором загиблих.
func test_bodies_lie_low_and_flat_and_are_marked_fallen() -> void:
	var soldier: ArrayMesh = UnitModelFixture.soldier()
	UnitSilhouettes.use_models({0: soldier})
	var places: Array[Transform3D] = [Transform3D(), Transform3D(), Transform3D(Basis(), Vector3(3.0, 0.0, 2.0))]
	var slots: Array[int] = [2, 3, 0]
	var m: ArrayMesh = UnitSilhouettes.bodies_mesh(0, 0, places, slots)
	var a: Array = m.surface_get_arrays(0)
	assert_eq((a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), 3 * soldier.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size())
	for col: Color in a[Mesh.ARRAY_COLOR] as PackedColorArray:
		assert_eq(col.r, 1.0)
	for i in UnitView.SQUAD_FIGURES:
		var lie: Transform3D = UnitSilhouettes.model_figure_transform(soldier, i, false)
		assert_almost_eq(absf(lie.basis.y.normalized().y), 0.0, 0.0001, "місце %d лежить" % i)
		assert_gt(lie.basis.z.normalized().y, 0.99, "ниць: спина моделі (+Z) догори, перед — у землю")
		var box: AABB = lie * soldier.get_aabb()
		# Коробка-фігура 0,05 завглибшки: лежить грудьми на основі (0,05), не висить і не тоне.
		assert_almost_eq(box.position.y, 0.05, 0.002, "місце %d на основі" % i)
		assert_lt(box.end.y, 0.05 + FIGURE_DEPTH + 0.002)
		assert_lt(Vector2(box.get_center().x, box.get_center().z).length(), 0.3, "лежить у межах тайла")
	UnitSilhouettes.use_models({})
	var boxes: ArrayMesh = UnitSilhouettes.bodies_mesh(0, 0, places, slots)
	var bc: PackedColorArray = boxes.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	assert_eq(bc.count(UnitSilhouettes.FALLEN_COLOR), bc.size(), "без моделі — темні коробки")
	assert_true(UnitSilhouettes.bodies_material(0, 0) is StandardMaterial3D)


const FIGURE_DEPTH: float = 0.05


## Модель береться, коли файл є, і коробки — коли нема: без асету гра не ламається.
func test_model_is_used_only_when_its_file_exists() -> void:
	UnitSilhouettes.reset_models()
	for id in UnitTypes.count():
		assert_eq(UnitSilhouettes.has_model(id), ResourceLoader.exists(UnitSilhouettes.model_path(id)), "тип %d" % id)
	assert_eq(UnitSilhouettes.model_path(5), "res://assets/units/medium_tank.glb")
	var model: ArrayMesh = UnitModelFixture.vehicle(5)
	UnitSilhouettes.use_models({5: model})
	var tank := UnitSilhouettes.build_merged(5).get_node("Hull") as MeshInstance3D
	assert_same(tank.mesh, model, "тіло — сітка моделі")
	assert_true(tank.material_override is ShaderMaterial)
	var car := UnitSilhouettes.build_merged(2).get_node("Hull") as MeshInstance3D
	assert_true(car.material_override is StandardMaterial3D, "без моделі — коробки")
	tank.get_parent().free()
	car.get_parent().free()


## Один матеріал на тип для всіх юнітів, без кольору власника, а specular — з
## імпортованого матеріалу (типові 0,5 власного шейдера світлішали б модель).
func test_model_bodies_share_mesh_and_material_and_carry_no_owner_colour() -> void:
	UnitSilhouettes.use_models({5: UnitModelFixture.vehicle(5)})
	var red := UnitSilhouettes.build_merged(5).get_node("Hull") as MeshInstance3D
	var blue := UnitSilhouettes.build_merged(5).get_node("Hull") as MeshInstance3D
	assert_same(red.mesh, blue.mesh)
	assert_same(red.material_override, blue.material_override)
	for u: Dictionary in (red.material_override as ShaderMaterial).shader.get_shader_uniform_list():
		assert_ne(u.name, "owner_color", "шейдер моделі не має кольору власника")
	var mat := red.material_override as ShaderMaterial
	assert_almost_eq(float(mat.get_shader_parameter("specular")), UnitModelFixture.SPECULAR, 0.0001)
	assert_not_null(mat.get_shader_parameter("albedo_tex"))
	assert_almost_eq(float(mat.get_shader_parameter("wheel_radius")), float(UnitSilhouettes.spec(5).wheel), 0.0001)
	red.get_parent().free()
	blue.get_parent().free()


## Відділення — стоячі бійці в одній сітці, ступнями на основі; загиблих у ній немає. Сітка на
## кількість стоячих кешується, а без жодного стоячого — порожня.
func test_model_squad_is_its_standing_soldiers() -> void:
	var soldier: ArrayMesh = UnitModelFixture.soldier()
	UnitSilhouettes.use_models({0: soldier})
	var verts: int = soldier.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
	var meshes: Array[Mesh] = []
	for standing in range(0, UnitView.SQUAD_FIGURES + 1):
		var m: Mesh = UnitSilhouettes.merged_mesh(0, standing)
		if standing == 0:
			assert_eq(m.get_surface_count(), 0, "знищене відділення нічого не малює")
		else:
			assert_eq(m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size(), standing * verts, "%d бійці" % standing)
		assert_false(meshes.has(m), "інша сітка при %d" % standing)
		meshes.append(m)
	assert_same(UnitSilhouettes.merged_mesh(0, 2), meshes[2], "сітка кешується")
	var full: AABB = meshes[4].get_aabb()
	assert_almost_eq(full.position.y, 0.05, 0.0001, "ступні на основі")
	assert_almost_eq(full.end.y, 0.05 + UnitSilhouettes.FIGURE_SIZE.y, 0.0001, "1,8 м заввишки")


## Перетворення вузла GLB впікається в сітку, а вісь колеса в UV2 їде разом із ним.
func test_model_merge_bakes_node_transform_into_vertices_and_axles() -> void:
	var src: ArrayMesh = UnitModelFixture.vehicle(5)
	var xfs: Array[Transform3D] = [Transform3D(Basis(), Vector3(0.0, 0.1, 0.2))]
	var out: ArrayMesh = UnitSilhouettes._merge_model(src, xfs)
	assert_almost_eq(out.get_aabb().position, src.get_aabb().position + Vector3(0.0, 0.1, 0.2), Vector3.ONE * 0.0001)
	var c: PackedColorArray = out.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var uv2: PackedVector2Array = out.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV2]
	var src_uv2: PackedVector2Array = src.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV2]
	for i in c.size():
		if c[i].b > 0.5:
			assert_almost_eq(uv2[i], src_uv2[i] + Vector2(0.1, 0.2), Vector2.ONE * 0.0001)
			return
	fail_test("у сітці нема коліс")


## Текстури юнітів усіх наборів: VRAM-стиснення (режим 2), карти нормалей позначені як нормалі.
func test_unit_texture_imports_are_vram_compressed() -> void:
	var seen: int = 0
	for set_id in UnitSilhouettes.SET_COUNT:
		var dir := DirAccess.open(UnitSilhouettes.model_dir(set_id))
		if dir == null:
			fail_test("немає каталогу моделей набору %d" % set_id)
			continue
		for f: String in dir.get_files():
			if not f.ends_with(".png.import"):
				continue
			var path: String = UnitSilhouettes.model_dir(set_id) + f
			var cfg := ConfigFile.new()
			assert_eq(cfg.load(path), OK, path)
			assert_eq(cfg.get_value("params", "compress/mode"), 2, path)
			if f.ends_with("_normal.png.import"):
				assert_eq(cfg.get_value("params", "compress/normal_map"), 1, path)
			seen += 1
	assert_gt(seen, 0, "жодної текстури юнітів")


## Імпорт моделей усіх наборів: без стиснення (точність UV2), без LOD і тіньових сіток (злиття їх однаково
## губить), UV2 не перегенеровується під lightmap (light_baking 2 стер би траки й колеса).
func test_unit_model_imports_keep_uv2_exact() -> void:
	var seen: int = 0
	for set_id in UnitSilhouettes.SET_COUNT:
		var dir := DirAccess.open(UnitSilhouettes.model_dir(set_id))
		if dir == null:
			fail_test("немає каталогу моделей набору %d: %s" % [set_id, UnitSilhouettes.model_dir(set_id)])
			continue
		for f: String in dir.get_files():
			if not f.ends_with(".glb.import"):
				continue
			var path: String = UnitSilhouettes.model_dir(set_id) + f
			var cfg := ConfigFile.new()
			assert_eq(cfg.load(path), OK, path)
			assert_eq(cfg.get_value("params", "meshes/force_disable_compression"), true, path)
			assert_eq(cfg.get_value("params", "meshes/generate_lods"), false, path)
			assert_eq(cfg.get_value("params", "meshes/create_shadow_meshes"), false, path)
			assert_ne(cfg.get_value("params", "meshes/light_baking"), 2, path)
			assert_eq(cfg.get_value("params", "import_script/path"), "res://tools/prop_import.gd", path)
			seen += 1
	if seen == 0:
		pass_test("моделей ще нема")
		return
	pass_test("перевірено")
