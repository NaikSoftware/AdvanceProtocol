extends GutTest
## Заступники юнітів мають реальні розміри (1 тайл = 8 м): ширина × висота × довжина корпусу.

const UnitModelFixture := preload("res://tests/fixtures/unit_model_fixture.gd")
const CrewLegal := preload("res://tools/crew_body_legal.gd")

const _METRES := {
	2: Vector3(2.7, 2.4, 6.6), 3: Vector3(2.7, 2.6, 7.6), 4: Vector3(2.2, 2.0, 4.9),
	5: Vector3(3.44, 1.6, 6.72), 6: Vector3(3.5, 1.5, 7.5), 7: Vector3(2.94, 1.5, 5.6),
	8: Vector3(3.8, 2.0, 7.2), 9: Vector3(2.16, 2.24, 2.72), 10: Vector3(2.44, 3.2, 4.16), 11: Vector3(3.6, 1.76, 7.36),
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
		# розрахунок гармати — єдине, що малюється окремо: свій матеріал бійця, один виклик зверху
		var crew_nodes: int = 1 if (UnitSilhouettes.spec(id).get("crew", []) as Array).size() > 0 else 0
		assert_eq(body.get_child_count(), 1 + crew_nodes, "тип %d: сітка тіла й, у гармат, розрахунок" % id)
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
		var m: Basis = UnitSilhouettes.model_figure_transform(i).basis
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


## Розкладки місць — у світових осях: місця поперек погляду через ~0,76 м, перестановка між бійцями й сталі
## зсуви; бійці лишаються в межах сліду відділення, і різні відділення — різні розкладки.
func test_squads_take_seeded_layouts_that_keep_standing_figures_apart_on_screen() -> void:
	for k in UnitSilhouettes.LAYOUT_COUNT:
		for i in UnitView.SQUAD_FIGURES:
			var lay: Transform3D = UnitSilhouettes.model_figure_transform(i, k)
			assert_lte(Vector2(lay.origin.x, lay.origin.z).length(), 0.2, "у межах сліду відділення")
			assert_lte(absf(wrapf(lay.basis.get_euler().y, -PI, PI)), 0.3 + 0.35 + 0.0001, "поворот фігури до ±37°")
			assert_eq(lay, UnitSilhouettes.model_figure_transform(i, k), "стала розкладка")
	# Місця стоять у світі, тож проміжок поперек погляду — властивість розкладки, а не напряму: кожна з
	# розкладок, яку може взяти відділення, тримає його для будь-якої кількості стоячих (коли фігура падає,
	# решта не скаче). Повороти фігур на 8 напрямах перевіряє test_unit_view (екранний проміжок фігур).
	for k in range(1, UnitSilhouettes.LAYOUT_COUNT):
		for up in range(2, UnitView.SQUAD_FIGURES + 1):
			assert_gte(UnitSilhouettes.screen_gap(k, up), UnitSilhouettes.MIN_SCREEN_GAP,
				"розкладка %d, стоїть %d: двоє не стоять один за одним" % [k, up])
	var picked: Dictionary = {}
	for unit_id in 12:
		var k: int = UnitSilhouettes.pick_layout(unit_id)
		assert_between(k, 1, UnitSilhouettes.LAYOUT_COUNT - 1)
		picked[k] = true
	assert_gt(picked.size(), 3, "різні відділення — різні розкладки")
	UnitSilhouettes.use_models({0: UnitModelFixture.soldier()})
	assert_ne(UnitSilhouettes.merged_mesh(0, 4, 0, 0, 1), UnitSilhouettes.merged_mesh(0, 4, 0, 0, 2), "сітка на розкладку")


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


## Друга поза: прості бійці на непарних місцях пригнулись (своя сітка того самого атласу), труби дрона
## несуть стоячі; без файлу пози всі стоять.
func test_odd_plain_slots_crouch_and_tube_carriers_stand() -> void:
	var plain: ArrayMesh = UnitModelFixture.soldier()
	var crouch: ArrayMesh = UnitModelFixture.mesh(Vector3(0.0625, 0.18, 0.05))
	UnitSilhouettes.use_models({0: plain, 1: UnitModelFixture.tube_soldier(), UnitSilhouettes.CROUCH_KEY: crouch})
	var v: int = plain.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
	var heights := func(m: ArrayMesh) -> Array:
		var p: PackedVector3Array = m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var out: Array = []
		for i in range(0, p.size(), v):
			var hi: float = -INF
			for k in v:
				hi = maxf(hi, p[i + k].y)
			out.append(snappedf(hi - 0.05, 0.001))
		out.sort()
		return out
	assert_eq(heights.call(UnitSilhouettes.merged_mesh(0, 4)), [0.18, 0.18, 0.225, 0.225], "двоє пригнулись, двоє стоять")
	assert_eq(heights.call(UnitSilhouettes.merged_mesh(1, 4, 0, 2)), [0.18, 0.225, 0.3, 0.3], "труби — на стоячих")
	assert_eq(heights.call(UnitSilhouettes.merged_mesh(0, 1)), [0.225], "останній — стоячий перший")
	UnitSilhouettes.use_models({0: plain})
	assert_eq(heights.call(UnitSilhouettes.merged_mesh(0, 4)), [0.225, 0.225, 0.225, 0.225], "без пози — усі стоять")


## Загиблий — своя сітка й матеріал простого бійця з `fallen`, один на набір; без моделі — коробка плазом
## у темному кольорі загиблих.
func test_fallen_use_the_body_mesh_and_a_fallen_copy_of_the_plain_material() -> void:
	var body: ArrayMesh = UnitModelFixture.mesh(Vector3(0.06, 0.05, 0.225))
	UnitSilhouettes.use_models({0: UnitModelFixture.soldier(), UnitSilhouettes.BODY_KEY: body})
	assert_same(UnitSilhouettes.body_or_box(0), body)
	assert_eq(UnitSilhouettes.body_pose(0), Transform3D(), "модель лежить як є")
	var m := UnitSilhouettes.fallen_material(0) as ShaderMaterial
	assert_same(m.shader, UnitSilhouettes._FALLEN_SHADER)
	assert_ne(m, UnitSilhouettes.model_material(0))
	assert_same(m, UnitSilhouettes.fallen_material(0), "один на набір")
	UnitSilhouettes.use_models({})
	assert_true(UnitSilhouettes.body_or_box(0) is BoxMesh)
	assert_eq((UnitSilhouettes.fallen_material(0) as StandardMaterial3D).albedo_color, UnitSilhouettes.FALLEN_COLOR)
	var pose: Transform3D = UnitSilhouettes.body_pose(0)
	assert_almost_eq(absf(pose.basis.y.normalized().y), 0.0, 0.0001, "коробка плазом")
	assert_almost_eq(pose.origin.y, UnitSilhouettes.FIGURE_SIZE.z * 0.5, 0.0001, "на землі, не в ній")


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


## Розрахунок гармати — окремий вузол `Crew` з матеріалом бійця: двоє фігур по 1,8 м, ступні на землі, без масштабування;
## сама сітка гармати лишається моделлю як є.
func test_gun_crew_is_two_real_figures_with_the_soldier_material() -> void:
	var gun: ArrayMesh = UnitModelFixture.mesh(Vector3(0.4, 0.3, 0.7))
	var man: ArrayMesh = UnitModelFixture.soldier()
	var per_man: int = (man.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	assert_eq((UnitSilhouettes.spec(9).crew as Array).size(), 2)
	assert_eq((UnitSilhouettes.spec(10).crew as Array).size(), 2)
	for with_soldier_model: bool in [true, false]:
		UnitSilhouettes.use_models({9: gun, 0: man} if with_soldier_model else {9: gun})
		assert_same(UnitSilhouettes.merged_mesh(9), gun, "гармата без розрахунку в сітці")
		var node: Node3D = UnitSilhouettes.build_merged(9)
		assert_eq(node.get_child_count(), 2, "корпус і розрахунок")
		var crew := node.get_node("Crew") as MeshInstance3D
		var arr: Array = crew.mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		assert_eq(v.size(), 2 * per_man, "дві фігури, модель бійця: %s" % with_soldier_model)
		var top: float = 0.0
		for p in v:
			top = maxf(top, p.y)
		assert_almost_eq(top, UnitSilhouettes.FIGURE_SIZE.y, 0.0001, "ріст 1,8 м, ступні на землі")
		if with_soldier_model:
			assert_same(crew.material_override, UnitSilhouettes.model_material(UnitSilhouettes.PLAIN_FIGURE), "матеріал бійця, не гармати")
		else:
			assert_same(crew.material_override, UnitSilhouettes._merged_mat(), "коробки з кольором у вершинах, без матеріалу гармати")
		# фігури — не колесо й не гусениця: B = 0, UV2 = 0
		var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
		var uv2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
		for i in v.size():
			if with_soldier_model:
				assert_eq(cols[i], Color.BLACK, "колір фігури не мітить ні колесо, ні гусеницю")
			assert_eq(uv2[i], Vector2.ZERO, "UV2 фігури нульовий")
		node.free()
	# тип без розрахунку віддає саму модель й без вузла Crew
	var eng: ArrayMesh = UnitModelFixture.mesh(Vector3(0.45, 0.24, 0.92))
	UnitSilhouettes.use_models({9: gun, 11: eng})
	assert_same(UnitSilhouettes.merged_mesh(11), eng, "тип без розрахунку — без змін")
	assert_null(UnitSilhouettes.crew_mesh(11))
	var plain: Node3D = UnitSilhouettes.build_merged(11)
	assert_eq(plain.get_child_count(), 1)
	plain.free()


## Розрахунок стоїть на вільній землі: жодна вершина справжньої сітки бійців (`crew_mesh`: руки,
## гвинтівка) не ближче 0,3 м (0,0375 тайла) по землі до трикутника моделі гармати нижче 1,8 м.
## Міряється відстань від точки до трикутника, а не прямокутник-слід: той пропускав бійця, що
## торкався станини рукою.
func test_crew_stands_clear_of_the_shipped_gun_models() -> void:
	UnitSilhouettes.reset_models()
	for set_id in UnitSilhouettes.SET_COUNT:
		for id: int in [9, 10]:
			assert_not_null(UnitSilhouettes._own_model(id, set_id), "модель типу %d набору %d" % [id, set_id])
			var gun: ArrayMesh = UnitSilhouettes.model_mesh(id, set_id)
			var crew: ArrayMesh = UnitSilhouettes.crew_mesh(id, set_id, false)
			assert_gte(_crew_gap(crew, gun, 0.0), 0.0375 - 0.0005, "розрахунок типу %d набору %d не ближче 0,3 м до моделі" % [id, set_id])


## Найменша відстань по землі від вершин `crew` до трикутників `gun` нижче зросту фігури; `dz`
## зсуває гармату по z (сусідній тайл). Сітка трикутників з коміркою 0,05 — перебір усіх пар був би
## надто повільним.
func _crew_gap(crew: ArrayMesh, gun: ArrayMesh, dz: float) -> float:
	var a: Array = gun.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var cell: float = 0.05
	var tris: Array = []
	var grid: Dictionary = {}
	for t in range(0, idx.size(), 3):
		var p: Array[Vector2] = []
		var low: float = INF
		for k in 3:
			low = minf(low, v[idx[t + k]].y)
			p.append(Vector2(v[idx[t + k]].x, v[idx[t + k]].z + dz))
		if low >= UnitSilhouettes.FIGURE_SIZE.y:
			continue
		tris.append(p)
		var lo := Vector2(minf(p[0].x, minf(p[1].x, p[2].x)), minf(p[0].y, minf(p[1].y, p[2].y)))
		var hi := Vector2(maxf(p[0].x, maxf(p[1].x, p[2].x)), maxf(p[0].y, maxf(p[1].y, p[2].y)))
		for gx in range(floori(lo.x / cell), floori(hi.x / cell) + 1):
			for gz in range(floori(lo.y / cell), floori(hi.y / cell) + 1):
				var k := Vector2i(gx, gz)
				if not grid.has(k):
					grid[k] = []
				(grid[k] as Array).append(tris.size() - 1)
	var best: float = INF
	for c: Vector3 in (crew.surface_get_arrays(0) as Array)[Mesh.ARRAY_VERTEX]:
		var q := Vector2(c.x, c.z)
		var home := Vector2i(floori(q.x / cell), floori(q.y / cell))
		# трикутник у комірці лежить не далі за комірку, тож дві комірки навколо накривають 0,1
		for dx in range(-2, 3):
			for dy in range(-2, 3):
				for ti: int in grid.get(home + Vector2i(dx, dy), []):
					best = minf(best, _point_to_triangle(q, tris[ti]))
	return best


func _point_to_triangle(q: Vector2, tri: Array) -> float:
	var a: Vector2 = tri[0]
	var b: Vector2 = tri[1]
	var c: Vector2 = tri[2]
	var d1: float = (b - a).cross(q - a)
	var d2: float = (c - b).cross(q - b)
	var d3: float = (a - c).cross(q - c)
	if (d1 >= 0.0 and d2 >= 0.0 and d3 >= 0.0) or (d1 <= 0.0 and d2 <= 0.0 and d3 <= 0.0):
		return 0.0
	var best: float = INF
	for e: Array in [[a, b], [b, c], [c, a]]:
		var s: Vector2 = e[1] - e[0]
		var u: float = clampf((q - e[0]).dot(s) / maxf(s.length_squared(), 1e-12), 0.0, 1.0)
		best = minf(best, q.distance_to(e[0] + s * u))
	return best


## Набір без власного бійця бере бійця набору 0: розрахунок є й у наборах 1 і 2, і сітка в кеші не плутається між ними.
func test_gun_crew_of_a_set_without_soldier_falls_back_to_set_zero() -> void:
	var gun: ArrayMesh = UnitModelFixture.mesh(Vector3(0.4, 0.3, 0.7))
	var man: ArrayMesh = UnitModelFixture.soldier()
	UnitSilhouettes.use_models({9: gun, 0: man})
	assert_not_null(UnitSilhouettes.crew_mesh(9, 1), "розрахунок набору 1")
	assert_same(UnitSilhouettes.crew_mesh(9, 1), UnitSilhouettes.crew_mesh(9, 0), "боєць набору 0 — та сама сітка")


## Кожен розрахунок гармати стоїть у своєму тайлі: слід фігури (з поворотом) не виходить за ±0,5.
func test_crew_footprints_stay_inside_their_tile() -> void:
	for set_id in UnitSilhouettes.SET_COUNT:
		for id: int in [9, 10]:
			if UnitSilhouettes._resolved_set(id, set_id) != set_id:
				continue
			assert_eq((UnitSilhouettes.spec(id, set_id).crew as Array).size(), 2, "двоє розрахунків, набір %d тип %d" % [set_id, id])
			for c: Vector3 in UnitSilhouettes.spec(id, set_id).crew:
				var half := Vector2(UnitSilhouettes.FIGURE_SIZE.x, UnitSilhouettes.FIGURE_SIZE.z) * 0.5
				var rot := Transform2D(-deg_to_rad(c.z), Vector2(c.x, c.y))
				for sx: float in [-1.0, 1.0]:
					for sz: float in [-1.0, 1.0]:
						var p: Vector2 = rot * Vector2(sx * half.x, sz * half.y)
						assert_lte(absf(p.x), 0.5, "x розрахунку типу %d набору %d у тайлі" % [id, set_id])
						assert_lte(absf(p.y), 0.5, "z розрахунку типу %d набору %d у тайлі" % [id, set_id])


## Довжина моделі (по сліду разом зі стволом, станинами й відвалом) не більша за справжню техніку
## більш ніж на 3 %, не менша за неї більш ніж на 5 %: модель не збільшена й не вкорочена.
## Справжні довжини — з docs/art/unit-models-research.md §5, за набором і роллю.
## Виняток — гаубиця набору 1: у документі лише довжина в похідному положенні (12,7 м), тож
## межі 10,1–10,6 м — регресія довжини самої моделі (виміряно 10,36 м), а не справжній розмір.
## Висота інженерної машини набору 1 — теж із §5 (3,43 м): не вища за неї більш ніж на 3 %
## і не нижча більш ніж на 5 %.
func test_set_towed_and_engineer_models_keep_real_lengths() -> void:
	UnitSilhouettes.reset_models()
	var bounds: Dictionary = {
		Vector2i(1, 9): Vector2(5.42, 5.87),
		Vector2i(1, 10): Vector2(10.1, 10.6),
		Vector2i(1, 11): Vector2(8.85, 9.6),
		Vector2i(2, 9): Vector2(6.0, 6.51),
		Vector2i(2, 10): Vector2(10.17, 11.02),
		Vector2i(2, 11): Vector2(11.59, 12.57),
	}
	for key: Vector2i in bounds:
		var mesh: ArrayMesh = UnitSilhouettes._own_model(key.y, key.x)
		assert_not_null(mesh, "модель набору %d типу %d" % [key.x, key.y])
		if mesh == null:
			continue
		var length: float = mesh.get_aabb().size.z * 8.0
		var b: Vector2 = bounds[key]
		assert_between(length, b.x, b.y, "довжина набору %d типу %d, м" % [key.x, key.y])
	var height: float = UnitSilhouettes._own_model(11, 1).get_aabb().size.y * 8.0
	assert_between(height, 3.43 * 0.95, 3.43 * 1.03, "висота інженерної машини набору 1, м")


## Другий боєць розрахунку — у присіді, коли набір має таку модель: перший стоячи, другий заряджає навколішки.
func test_the_second_crew_figure_is_the_crouch_mesh_when_the_set_has_one() -> void:
	UnitSilhouettes.reset_models()
	var stand: ArrayMesh = UnitSilhouettes.model_mesh(UnitSilhouettes.PLAIN_FIGURE)
	var kneel: ArrayMesh = UnitSilhouettes.crouch_mesh(0)
	assert_not_null(stand, "передумова: модель бійця набору 0")
	assert_not_null(kneel, "передумова: модель бійця в присіді")
	var count_of := func(m: ArrayMesh) -> int:
		return (m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var crew: ArrayMesh = UnitSilhouettes.crew_mesh(9)
	assert_eq(count_of.call(crew), count_of.call(stand) + count_of.call(kneel), "стоячий і в присіді")
	# присід нижчий за стоячого
	var v: PackedVector3Array = crew.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var first_top: float = 0.0
	var second_top: float = 0.0
	var n_first: int = count_of.call(stand)
	for i in v.size():
		if i < n_first:
			first_top = maxf(first_top, v[i].y)
		else:
			second_top = maxf(second_top, v[i].y)
	assert_gt(first_top, second_top + 0.01, "другий нижчий: у присіді")


## Поручні мостів переправи: найближча до осі настилу грань вище за настил (вісь x, міст іде вздовж z); висота настилу — з PropLayer.
const _BRIDGES: Array[String] = ["west", "centre", "east"]


func _deck_top(name: String) -> float:
	return float(PropLayer.spec_of(StringName("bridge_river_" + name))["deck_top"])


func _rail_inner_face(name: String) -> float:
	var root: Node = (load("res://assets/props/bridge_river_%s.glb" % name) as PackedScene).instantiate()
	var inner: float = INF
	var curb: float = INF
	var stack: Array = [[root, Transform3D()]]
	while not stack.is_empty():
		var it: Array = stack.pop_back()
		var n: Node = it[0]
		var xf: Transform3D = it[1] * ((n as Node3D).transform if n is Node3D else Transform3D())
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var m: Mesh = (n as MeshInstance3D).mesh
			for s in m.get_surface_count():
				for v: Vector3 in (m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
					var p: Vector3 = xf * v
					if p.y > _deck_top(name) + 0.03 and absf(p.x) > 0.05:
						inner = minf(inner, absf(p.x))
					if p.y > _deck_top(name) + 0.005 and absf(p.x) > 0.05:
						curb = minf(curb, absf(p.x))
		for c in n.get_children():
			stack.append([c, xf])
	root.free()
	# Східний міст має лише низький бордюр; решта — ферми вище настилу.
	return inner if inner < INF else curb


## Гармата в похідному положенні й її розрахунок стоять між поручнями кожного з мостів переправи — з кожного боку, а не
## за шириною габариту, — і в тайлі. Стопа розрахунку не ближче 0,3 м до моделі гармати.
func test_travel_pose_gun_and_crew_fit_between_the_rails_of_every_bridge() -> void:
	UnitSilhouettes.reset_models()
	for set_id in UnitSilhouettes.SET_COUNT:
		_travel_fits_between_the_rails(set_id)


func _travel_fits_between_the_rails(set_id: int) -> void:
	for name: String in _BRIDGES:
		var inner: float = _rail_inner_face(name)
		assert_lt(inner, 0.5, "передумова: поручні міста «%s» знайдено" % name)
		for id: int in [9, 10]:
			assert_not_null(UnitSilhouettes.travel_mesh(id, set_id), "похідна модель типу %d набору %d є" % [id, set_id])
			var gun: PackedVector3Array = (UnitSilhouettes.travel_mesh(id, set_id).surface_get_arrays(0) as Array)[Mesh.ARRAY_VERTEX]
			var crew: PackedVector3Array = (UnitSilhouettes.crew_mesh(id, set_id, true).surface_get_arrays(0) as Array)[Mesh.ARRAY_VERTEX]
			var gx_min: float = INF
			var gx_max: float = -INF
			for v in gun:
				gx_min = minf(gx_min, v.x)
				gx_max = maxf(gx_max, v.x)
			assert_lt(-gx_min, inner, "лівий бік гармати %d набору %d до поручня «%s»" % [id, set_id, name])
			assert_lt(gx_max, inner, "правий бік гармати %d набору %d до поручня «%s»" % [id, set_id, name])
			for v in crew:
				assert_lt(absf(v.x), inner, "розрахунок гармати %d набору %d між поручнями «%s»" % [id, set_id, name])
				assert_lte(absf(v.z), 0.5, "розрахунок у тайлі")
			var travel_gun: ArrayMesh = UnitSilhouettes.travel_mesh(id, set_id)
			assert_gte(_crew_gap(UnitSilhouettes.crew_mesh(id, set_id, true), travel_gun, 0.0), 0.05 - 0.0005,
					"розрахунок гармати %d набору %d не ближче 0,4 м до моделі" % [id, set_id])
		# розрахунок на землі (розведені станини) — теж у своєму тайлі
		for id: int in [9, 10]:
			for v in (UnitSilhouettes.crew_mesh(id, set_id, false).surface_get_arrays(0) as Array)[Mesh.ARRAY_VERTEX]:
				assert_lte(absf(v.x), 0.5, "розрахунок на землі в тайлі")
				assert_lte(absf(v.z), 0.5, "розрахунок на землі в тайлі")


## Розрахунок видно з камери: за напрямів 0 і 4 (вздовж настилу) гармата закриває не більше 15 %
## вершин жодної з двох фігур, на найближчому й найдальшому нахилі камери, у кожному наборі — в
## похідному положенні (на мосту) і розведеною.
func test_crew_is_visible_from_the_camera_in_both_poses_of_every_set() -> void:
	UnitSilhouettes.reset_models()
	for set_id in UnitSilhouettes.SET_COUNT:
		var figures: Array = [UnitSilhouettes.model_mesh(UnitSilhouettes.PLAIN_FIGURE, set_id), UnitSilhouettes.crouch_mesh(set_id)]
		for id: int in [9, 10]:
			for travel: bool in [true, false]:
				var gun: ArrayMesh = UnitSilhouettes.travel_mesh(id, set_id) if travel else UnitSilhouettes.model_mesh(id, set_id)
				assert_not_null(gun, "модель типу %d набору %d, похідна: %s" % [id, set_id, travel])
				var a: Array = gun.surface_get_arrays(0)
				var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
				var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
				var rows: Array = UnitSilhouettes.crew_rows(id, set_id, travel)
				for facing: int in [0, 4]:
					var basis := Basis(Vector3.UP, deg_to_rad(UnitView._degrees_for_facing(facing)))
					var tris := PackedVector3Array()
					for i in idx:
						tris.append(basis * v[i])
					for pitch: float in [IsoCameraRig.PITCH_NEAR_DEG, IsoCameraRig.PITCH_FAR_DEG]:
						var buf: PackedFloat32Array = CrewLegal.silhouette(tris, pitch)
						for fig in 2:
							var mesh: ArrayMesh = figures[fig] if figures[fig] != null else figures[0]
							var pts: PackedVector3Array = (mesh.surface_get_arrays(0) as Array)[Mesh.ARRAY_VERTEX]
							var at := Vector2((rows[fig] as Vector3).x, (rows[fig] as Vector3).y)
							assert_lte(CrewLegal.figure_cover(pts, at, facing, buf, pitch), 0.15,
									"гармата %d набору %d не закриває бійця %d, напрям %d, нахил %d, похідна: %s" % [id, set_id, fig, facing, int(pitch), travel])


## Польова гармата в похідному положенні стоїть у сусідньому з гаубицею тайлі (станини гаубиці виступають за її
## тайл): розрахунок польової не ближче 0,3 м до них.
func test_field_gun_travel_crew_clears_the_spades_of_a_howitzer_ahead() -> void:
	UnitSilhouettes.reset_models()
	for set_id in UnitSilhouettes.SET_COUNT:
		_field_crew_clears_howitzer_spades(set_id)


func _field_crew_clears_howitzer_spades(set_id: int) -> void:
	var gap: float = _crew_gap(UnitSilhouettes.crew_mesh(9, set_id, true), UnitSilhouettes.travel_mesh(10, set_id), -1.0)
	assert_gte(gap, 0.0375 - 0.0005, "розрахунок польової гармати набору %d не ближче 0,3 м до станин гаубиці" % set_id)
