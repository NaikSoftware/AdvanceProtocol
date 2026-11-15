extends GutTest
## Заступники юнітів мають реальні розміри (1 тайл = 8 м): ширина × висота × довжина корпусу.

const UnitModelFixture := preload("res://tests/fixtures/unit_model_fixture.gd")

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
		# розрахунок гармати — дві коробки-фігури в тій самій сітці
		for c: Vector3 in UnitSilhouettes.spec(id).get("crew", []):
			verts += 24
			var cb: AABB = UnitSilhouettes._crew_transform(c, UnitSilhouettes.FIGURE_SIZE.y * 0.5) * AABB(-UnitSilhouettes.FIGURE_SIZE * 0.5, UnitSilhouettes.FIGURE_SIZE)
			lo = lo.min(cb.position)
			hi = hi.max(cb.end)
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


## Фігури відділення — у тій самій сітці: стоячі в нейтральному кольорі тіла, загиблі темні. Сітка на
## кількість стоячих окрема й кешується, тож падіння фігури — підміна сітки, а не нова.
func test_squad_figures_live_in_the_merged_mesh_by_standing_count() -> void:
	for standing in range(0, UnitView.SQUAD_FIGURES + 1):
		var body: Node3D = UnitSilhouettes.build_merged(0, standing)
		var colors: PackedColorArray = (body.get_node("Hull") as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		var box_verts: int = 24
		var fallen: int = colors.count(UnitSilhouettes.FALLEN_COLOR)
		assert_eq(fallen, (UnitView.SQUAD_FIGURES - standing) * box_verts, "лежачих при %d стоячих" % standing)
		# Корпус (плита) — теж BODY_COLOR, тож стоячі + плита.
		assert_eq(colors.count(UnitSilhouettes.BODY_COLOR), (standing + 1) * box_verts, "стоячих при %d" % standing)
		body.free()
	assert_same(UnitSilhouettes.build_merged(0, 2).get_node("Hull").mesh, UnitSilhouettes.build_merged(0, 2).get_node("Hull").mesh)


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


## Відділення — четверо бійців в одній сітці; стоять перші `standing` ступнями на основі,
## загиблі лежать. Сітка на кількість стоячих кешується.
func test_model_squad_is_four_soldiers_by_standing_count() -> void:
	var soldier: ArrayMesh = UnitModelFixture.soldier()
	UnitSilhouettes.use_models({0: soldier})
	var verts: int = soldier.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
	var meshes: Array[Mesh] = []
	for standing in range(0, UnitView.SQUAD_FIGURES + 1):
		var m: Mesh = UnitSilhouettes.merged_mesh(0, standing)
		assert_eq(m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size(), 4 * verts, "4 бійці при %d" % standing)
		assert_false(meshes.has(m), "інша сітка при %d" % standing)
		meshes.append(m)
	assert_same(UnitSilhouettes.merged_mesh(0, 2), meshes[2], "сітка кешується")
	var full: AABB = meshes[4].get_aabb()
	assert_almost_eq(full.position.y, 0.05, 0.0001, "ступні на основі")
	assert_almost_eq(full.end.y, 0.05 + UnitSilhouettes.FIGURE_SIZE.y, 0.0001, "1,8 м заввишки")
	assert_lt(meshes[0].get_aabb().end.y, 0.05 + UnitSilhouettes.FIGURE_SIZE.y * 0.5, "загиблі лежать")


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


## Гармата несе двох розрахунків у власній сітці (один виклик малювання): вершини гармати плюс дві фігури, 1,8 м, ступні на землі.
func test_gun_merged_mesh_carries_its_two_crew() -> void:
	var gun: ArrayMesh = UnitModelFixture.mesh(Vector3(0.4, 0.3, 0.7))
	var man: ArrayMesh = UnitModelFixture.soldier()
	var per_man: int = (man.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var gun_n: int = (gun.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	assert_eq((UnitSilhouettes.spec(9).crew as Array).size(), 2)
	assert_eq((UnitSilhouettes.spec(10).crew as Array).size(), 2)
	for with_soldier_model: bool in [true, false]:
		UnitSilhouettes.use_models({9: gun, 0: man} if with_soldier_model else {9: gun})
		var mesh: ArrayMesh = UnitSilhouettes.merged_mesh(9)
		var v: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		assert_eq(v.size(), gun_n + 2 * per_man, "гармата + 2 фігури, модель бійця: %s" % with_soldier_model)
		var top: float = 0.0
		for i in range(gun_n, v.size()):
			top = maxf(top, v[i].y)
		assert_almost_eq(top, UnitSilhouettes.FIGURE_SIZE.y, 0.0001, "ріст 1,8 м, ступні на землі")
		assert_same(mesh.surface_get_material(0), gun.surface_get_material(0))
		# фігури — не колесо й не гусениця: B = 0, UV2 = 0
		var arr: Array = mesh.surface_get_arrays(0)
		var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
		var uv2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
		for i in range(gun_n, v.size()):
			assert_eq(cols[i].b, 0.0, "колір фігури не мітить колесо")
			assert_eq(uv2[i], Vector2.ZERO, "UV2 фігури нульовий")
	UnitSilhouettes.use_models({9: gun})
	# тип без розрахунку віддає саму модель, без копії
	var eng: ArrayMesh = UnitModelFixture.mesh(Vector3(0.45, 0.24, 0.92))
	UnitSilhouettes.use_models({9: gun, 11: eng})
	assert_same(UnitSilhouettes.merged_mesh(11), eng, "тип без розрахунку — без змін")


## Розрахунок стоїть на вільній землі: під слідом фігури (0,5 × 0,4 м) із запасом 0,3 м нема
## жодного трикутника моделі гармати нижче 1,8 м.
func test_crew_stands_clear_of_the_shipped_gun_models() -> void:
	UnitSilhouettes.reset_models()
	# 0,3 м від будь-якої балки станини чи ящика: 0,0375 тайла
	var margin: float = 0.0375
	for set_id in UnitSilhouettes.SET_COUNT:
		for id: int in [9, 10]:
			if not ResourceLoader.exists(UnitSilhouettes.model_path(id, set_id)):
				continue
			var mesh: ArrayMesh = UnitSilhouettes._own_model(id, set_id)
			assert_not_null(mesh, "модель типу %d набору %d" % [id, set_id])
			var a: Array = mesh.surface_get_arrays(0)
			var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
			for c: Vector3 in UnitSilhouettes.spec(id, set_id).crew:
				var half := Vector2(UnitSilhouettes.FIGURE_SIZE.x, UnitSilhouettes.FIGURE_SIZE.z) * 0.5 + Vector2.ONE * margin
				var rot := Transform2D(-deg_to_rad(c.z), Vector2(c.x, c.y))
				var corners: Array[Vector2] = []
				for sx: float in [-1.0, 1.0]:
					for sz: float in [-1.0, 1.0]:
						corners.append(rot * Vector2(sx * half.x, sz * half.y))
				var hits: int = 0
				for t in range(0, idx.size(), 3):
					var tri: Array[Vector3] = [v[idx[t]], v[idx[t + 1]], v[idx[t + 2]]]
					if minf(tri[0].y, minf(tri[1].y, tri[2].y)) >= UnitSilhouettes.FIGURE_SIZE.y:
						continue
					if _tri_overlaps_rect(tri, corners):
						hits += 1
				assert_eq(hits, 0, "розрахунок типу %d набору %d у точці %s вільний від моделі" % [id, set_id, c])


## Перетин трикутника (проєкція на XZ) з опуклим чотирикутником: розділова вісь серед нормалей сторін обох.
func _tri_overlaps_rect(tri: Array[Vector3], rect: Array[Vector2]) -> bool:
	var t: Array[Vector2] = [Vector2(tri[0].x, tri[0].z), Vector2(tri[1].x, tri[1].z), Vector2(tri[2].x, tri[2].z)]
	var axes: Array[Vector2] = []
	for i in 3:
		var e: Vector2 = t[(i + 1) % 3] - t[i]
		axes.append(Vector2(-e.y, e.x))
	# кути чотирикутника: (-,-), (-,+), (+,-), (+,+) — його осі це дві сторони від першого кута
	axes.append(rect[2] - rect[0])
	axes.append(rect[1] - rect[0])
	for ax in axes:
		if ax.length_squared() < 1e-12:
			continue
		var tmin: float = INF
		var tmax: float = -INF
		for p in t:
			tmin = minf(tmin, ax.dot(p))
			tmax = maxf(tmax, ax.dot(p))
		var rmin: float = INF
		var rmax: float = -INF
		for p in rect:
			rmin = minf(rmin, ax.dot(p))
			rmax = maxf(rmax, ax.dot(p))
		if tmax < rmin or rmax < tmin:
			return false
	return true


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
