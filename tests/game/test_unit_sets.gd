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
	# справжній рядок набору 1 для типу 5 тут заважав би: тест перевіряє саме його відсутність
	UnitSilhouettes.use_set_specs({1: {}, 2: {}})
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


## Рядок набору описує модель, яку показує: довжина ствола — за найнижчою за Z вершиною (дуло), висота осі — за
## середнім колом вершин дула. Рядки набору 0 — заступники ролі (його висоту осі задає _SPECS, а не модель), тож
## для нього перевіряється лише довжина.
func test_spec_row_matches_every_model_muzzle() -> void:
	UnitSilhouettes.reset_models()
	var checked: int = 0
	var wheeled_checked: int = 0
	for set_id in UnitSilhouettes.SET_COUNT:
		for id in UnitTypes.count():
			if not ResourceLoader.exists(UnitSilhouettes.model_path(id, set_id)):
				continue
			var mesh: ArrayMesh = UnitSilhouettes._own_model(id, set_id)
			var v: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			if v.is_empty():
				continue
			var row: Dictionary = UnitSilhouettes.spec(id, set_id)
			# Колісна машина носить гармату на даху в межах корпусу, тож дуло — найпередніша вершина на висоті осі біля осі,
			# а не передок корпусу.
			var wheeled: bool = (row.extras as Array).has(&"wheels")
			var bore: float = UnitSilhouettes.barrel_y(id, set_id)
			var cand := PackedVector3Array()
			for p in v:
				if not wheeled or (absf(p.x) < 0.06 and absf(p.y - bore) < 0.02):
					cand.append(p)
			if cand.is_empty():
				fail_test("немає вершин дула: набір %d тип %d" % [set_id, id])
				continue
			var zmin: float = cand[0].z
			for p in cand:
				zmin = minf(zmin, p.z)
			var ring_y: float = 0.0
			var n: int = 0
			for p in cand:
				if p.z < zmin + 0.001:
					ring_y += p.y
					n += 1
			if not ((row.extras as Array).has(&"turret") or (row.extras as Array).has(&"roof_gun") or row.has("bore")):
				continue
			checked += 1
			wheeled_checked += int(wheeled and set_id == 0)
			var where: String = "набір %d тип %d" % [set_id, id]
			assert_almost_eq(-zmin, float(row.barrel), 0.01, "довжина ствола, " + where)
			if set_id > 0:
				assert_almost_eq(ring_y / float(n), UnitSilhouettes.barrel_y(id, set_id), 0.005, "висота осі ствола, " + where)
			elif row.has("bore"):
				# піднятий ствол: рядок несе виміряну висоту дульного зрізу, модель тримає її в межах 1,5 см
				assert_almost_eq(ring_y / float(n), UnitSilhouettes.barrel_y(id, set_id), 0.015, "висота осі піднятого ствола, " + where)
			elif wheeled:
				# рядок набору 0 дає висоту осі як корпус + пів башти; модель тримає гармату в межах 1,5 см (0,12 м) від неї
				assert_almost_eq(ring_y / float(n), UnitSilhouettes.barrel_y(id, set_id), 0.015, "висота осі ствола, " + where)
	assert_gt(checked, 0)
	assert_eq(wheeled_checked, 3, "бронеавто, транспортер і розвідувальна машина набору 0 перевірено")


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


## Рядок гармат і інженерної машини (в усіх наборах) описує суцільний лафет чи корпус, а не всю
## модель: ширина — за колесами (гармати) чи траками (машина), довжина й висота — за самим мешем
## всередині сліду рядка.
func test_rows_match_carriage_and_running_gear_in_every_set() -> void:
	UnitSilhouettes.reset_models()
	var checked: int = 0
	for set_id in UnitSilhouettes.SET_COUNT:
		for id: int in [9, 10, 11]:
			if not ResourceLoader.exists(UnitSilhouettes.model_path(id, set_id)):
				continue
			var where: String = "набір %d тип %d" % [set_id, id]
			var mesh: ArrayMesh = UnitSilhouettes._own_model(id, set_id)
			assert_not_null(mesh, "модель, " + where)
			var a: Array = mesh.surface_get_arrays(0)
			var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var col: PackedColorArray = a[Mesh.ARRAY_COLOR]
			var hull: Vector3 = UnitSilhouettes.spec(id, set_id).hull
			var wx := Vector2(INF, -INF)
			var wz := Vector2(INF, -INF)
			var tx := Vector2(INF, -INF)
			var tz := Vector2(INF, -INF)
			var top: float = 0.0
			var rear: float = -INF
			var nrm: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
			var up_ys: Array[float] = []
			for i in v.size():
				if col[i].b > 0.5:
					wx = Vector2(minf(wx.x, v[i].x), maxf(wx.y, v[i].x))
					wz = Vector2(minf(wz.x, v[i].z), maxf(wz.y, v[i].z))
				elif col[i].g > 0.5:
					tx = Vector2(minf(tx.x, v[i].x), maxf(tx.y, v[i].x))
					tz = Vector2(minf(tz.x, v[i].z), maxf(tz.y, v[i].z))
				if absf(v[i].x) < hull.x * 0.5 and absf(v[i].z) < hull.z * 0.5:
					top = maxf(top, v[i].y)
					if nrm[i].y > 0.9 and col[i].b < 0.5 and col[i].g < 0.5:
						up_ys.append(v[i].y)
				rear = maxf(rear, v[i].z)
			var gear_x: Vector2 = tx if id == 11 else wx
			assert_almost_eq(gear_x.y - gear_x.x, hull.x, 0.03, "ширина рядка за колесами чи траками, " + where)
			assert_gte(wz.x, -hull.z * 0.5 - 0.02, "колеса в межах довжини лафета, " + where)
			assert_lte(wz.y, hull.z * 0.5 + 0.02, "колеса в межах довжини лафета, " + where)
			if id == 11 and set_id > 0:
				# рядок інженерної машини — палуба корпусу (медіана верхніх поверхонь), а не верх
				# кабіни чи стріли
				up_ys.sort()
				assert_almost_eq(up_ys[up_ys.size() / 2], hull.y, 0.06, "висота рядка — палуба корпусу, " + where)
				assert_gt(top, hull.y, "надбудова вища за палубу, " + where)
			else:
				assert_almost_eq(top, hull.y, 0.06, "висота рядка — верх лафета чи корпусу, " + where)
			if id == 11:
				# довжина рядка: не коротша за траки й не довша за них більш ніж на 0,12 тайла
				assert_gte(hull.z, tz.y - tz.x - 0.02, "корпус не коротший за траки, " + where)
				assert_lte(hull.z, tz.y - tz.x + 0.12, "корпус не довший за траки більш ніж на 0,12, " + where)
				# корма корпусу — край рядка; стріла може виступати за неї, але не вкорочувати
				assert_gte(rear, hull.z * 0.5 - 0.02, "корма машини не коротша за рядок, " + where)
				if set_id == 0:
					assert_almost_eq(rear, hull.z * 0.5, 0.02, "корма машини — край рядка, " + where)
			checked += 1
	assert_eq(checked, 9, "три моделі в кожному з трьох наборів")


## Кінці станин і передні опори лежать симетрично до лінії ствола. Для кожного боку беруться
## низькі точки (y < 0,2), без смуги ствола (|x| < 0,05), а в гармат — без ящиків (|x| > 0,225).
## Три величини: найдальша назад точка (сума x лівої й правої станини), найдальша вперед за z і
## найдальша вбік серед точок передньої половини (z < 0), тобто передні опори, а не станини.
## Суми й різниці лівого та правого боку не перевищують 0,04 тайла (0,3 м).
func test_trail_ends_are_symmetric_about_the_barrel_line() -> void:
	UnitSilhouettes.reset_models()
	var checked: int = 0
	for set_id in UnitSilhouettes.SET_COUNT:
		for id: int in [9, 10]:
			if not ResourceLoader.exists(UnitSilhouettes.model_path(id, set_id)):
				continue
			var v: PackedVector3Array = UnitSilhouettes._own_model(id, set_id).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			var rear: Array[Vector2] = [Vector2(0.0, -INF), Vector2(0.0, -INF)]
			var front_z: Array[float] = [INF, INF]
			var side_max: Array[float] = [0.0, 0.0]
			for p in v:
				if p.y > 0.2 or absf(p.x) < 0.05 or (id == 9 and absf(p.x) > 0.225):
					continue
				var side: int = 0 if p.x < 0.0 else 1
				if p.y <= 0.12 and p.z > rear[side].y:
					rear[side] = Vector2(p.x, p.z)
				front_z[side] = minf(front_z[side], p.z)
				if p.z < 0.0:
					side_max[side] = maxf(side_max[side], absf(p.x))
			var where: String = "набору %d типу %d" % [set_id, id]
			assert_lte(absf(rear[0].x + rear[1].x), 0.04, "кінці станин %s: %s і %s" % [where, rear[0], rear[1]])
			assert_lte(absf(front_z[0] - front_z[1]), 0.04, "виліт уперед %s: %s і %s" % [where, front_z[0], front_z[1]])
			assert_lte(absf(side_max[0] - side_max[1]), 0.04, "виліт убік %s: %s і %s" % [where, side_max[0], side_max[1]])
			checked += 1
	assert_eq(checked, 6, "дві гармати в кожному з трьох наборів")


const _FIGURE_SLUGS: Array[String] = [
	"rifle_soldier", "assault_soldier", "rifle_soldier_crouch", "rifle_soldier_body",
	"rifle_soldier_body_prone", "rifle_soldier_body_back",
]
## 1,8 м у тайлах: 1 тайл = 8 м.
const _MAN: float = 0.225


func _figure_mesh(set_id: int, slug: String) -> ArrayMesh:
	var path: String = UnitSilhouettes.model_dir(set_id) + slug + ".glb"
	return UnitSilhouettes._load_model(path)


## Кожен набір має всі шість файлів фігур і рядки відділень: без рядка модель набору не діє, і набір
## тихо стояв би в одязі набору 0.
func test_every_set_has_every_figure_file_and_spec_row() -> void:
	for set_id in UnitSilhouettes.SET_COUNT:
		for slug in _FIGURE_SLUGS:
			var path: String = UnitSilhouettes.model_dir(set_id) + slug + ".glb"
			assert_true(ResourceLoader.exists(path), "нема файлу " + path)
		if set_id > 0:
			for id in 2:
				assert_true((UnitSilhouettes._SET_SPECS.get(set_id, {}) as Dictionary).has(id), "набір %d тип %d: нема рядка відділення" % [set_id, id])


## Відділення набору N справді бере фігури набору N, а не набору 0: власна модель, три пози тіл і
## поза навпочіпки.
func test_squad_figures_come_from_the_players_set() -> void:
	UnitSilhouettes.reset_models()
	for set_id in range(1, UnitSilhouettes.SET_COUNT):
		for id in 2:
			assert_ne(UnitSilhouettes.model_mesh(id, set_id), UnitSilhouettes.model_mesh(id, 0), "набір %d тип %d" % [set_id, id])
			assert_eq(UnitSilhouettes._resolved_set(id, set_id), set_id)
		assert_not_null(UnitSilhouettes.crouch_mesh(set_id))
		assert_eq(UnitSilhouettes.body_pose_count(set_id), UnitSilhouettes.BODY_POSES.size())
		assert_ne(UnitSilhouettes.body_mesh(set_id), UnitSilhouettes.body_mesh(0))


## Справжній зріст: боєць 1,8 м (0,225 тайла) на кожному наборі, підошви на нулі, труба — як у
## набору 0, загиблий лежить нижче метра, кожна фігура вкладається в бюджет трикутників набору 0.
func test_figures_have_real_height_in_every_set() -> void:
	for set_id in UnitSilhouettes.SET_COUNT:
		var where: String = "набір %d" % set_id
		var man: AABB = _figure_mesh(set_id, "rifle_soldier").get_aabb()
		assert_almost_eq(man.size.y, _MAN, 0.002, "зріст, " + where)
		assert_almost_eq(man.position.y, 0.0, 0.0002, "підошви на землі, " + where)
		var tube: AABB = _figure_mesh(set_id, "assault_soldier").get_aabb()
		assert_between(tube.end.y, 0.28, 0.31, "верх труби (1,52 м над стегном), " + where)
		var crouch: AABB = _figure_mesh(set_id, "rifle_soldier_crouch").get_aabb()
		assert_between(crouch.end.y, 0.6 * _MAN, 0.85 * _MAN, "поза пригнувся не вища за 0,85 зросту, " + where)
		assert_almost_eq(crouch.position.y, 0.0, 0.0002, "підошви пригнулого, " + where)
		for slug in ["rifle_soldier_body", "rifle_soldier_body_prone", "rifle_soldier_body_back"]:
			var body: AABB = _figure_mesh(set_id, slug).get_aabb()
			assert_lt(body.end.y, 0.11, "лежить низько: %s, %s" % [slug, where])
			assert_almost_eq(body.position.y, 0.0, 0.0002, "лежить на землі: %s, %s" % [slug, where])
			assert_lte(body.size.x, WreckLayer.BODY_WIDTH, "ширше за BODY_WIDTH: %s, %s" % [slug, where])
			assert_lte(body.size.z, WreckLayer.BODY_LENGTH, "довше за BODY_LENGTH: %s, %s" % [slug, where])
		for slug in _FIGURE_SLUGS:
			var idx: PackedInt32Array = _figure_mesh(set_id, slug).surface_get_arrays(0)[Mesh.ARRAY_INDEX]
			assert_lte(idx.size() / 3, 900, "трикутників: %s, %s" % [slug, where])


## Вектор носків: куди дивляться ступні відносно щиколоток (x, z). Ступні ділить уздовж осі
## найбільшого розкиду підошов, а не
## за знаком x: після повороту на чверть оберту поділ за x зникає, а вісь розкиду переходить на z.
func _toe_vector(verts: PackedVector3Array) -> Vector2:
	var sole: float = 0.10 / 1.8 * _MAN
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for v in verts:
		if v.y < sole:
			lo = lo.min(v)
			hi = hi.max(v)
	var on_x: bool = hi.x - lo.x >= hi.z - lo.z
	var mid: float = (lo.x + hi.x) * 0.5 if on_x else (lo.z + hi.z) * 0.5
	var sum := Vector2.ZERO
	var feet: int = 0
	for side in [-1.0, 1.0]:
		var foot := Vector3.ZERO
		var ankle := Vector3.ZERO
		var nf: int = 0
		var na: int = 0
		for v in verts:
			if signf((v.x if on_x else v.z) - mid) != side:
				continue
			if v.y < sole:
				foot += v
				nf += 1
			elif v.y > 0.15 / 1.8 * _MAN and v.y < 0.30 / 1.8 * _MAN:
				ankle += v
				na += 1
		if nf > 3 and na > 3:
			var d: Vector3 = foot / float(nf) - ankle / float(na)
			sum += Vector2(d.x, d.z)
			feet += 1
	assert_eq(feet, 2, "обидві ступні знайдено")
	return sum / maxf(feet, 1.0)


func _turned(verts: PackedVector3Array, degrees: float) -> PackedVector3Array:
	var basis := Basis(Vector3.UP, deg_to_rad(degrees))
	var out := PackedVector3Array()
	for v in verts:
		out.append(basis * v)
	return out


func _faces_forward(toe: Vector2) -> bool:
	return toe.y < 0.0 and -toe.y > absf(toe.x)


## Обличчям вперед (−Z): носки обох ступнів лежать попереду щиколоток і більше вперед, ніж убік.
## Труба для цього не годиться (вона завжди ззаду, хоч би куди дивилась модель), а темні текселі
## гвинтівки зміщуються, коли її перенесено впоперек тулуба. Тут геометрія: модель, повернута на
## чверть оберту (±90°) чи на пів оберту, носками вперед не дивиться в жодному з трьох наборів (тест
## повертає вершини сам).
func test_standing_figures_face_forward_in_every_set() -> void:
	for set_id in UnitSilhouettes.SET_COUNT:
		var verts: PackedVector3Array = _figure_mesh(set_id, "rifle_soldier").surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var toe: Vector2 = _toe_vector(verts)
		assert_true(_faces_forward(toe), "носки вперед (−Z), набір %d: %s" % [set_id, toe])
		for turn in [90.0, -90.0, 180.0]:
			var turned: Vector2 = _toe_vector(_turned(verts, turn))
			assert_false(_faces_forward(turned), "повернута на %d° модель не має дивитись вперед, набір %d: %s" % [int(turn), set_id, turned])


## Тон загиблих набору: набір 0 — як у живого (матеріал бійця без змін), набори 1 і 2 — рівно
## добуток тону бійця на `FALLEN_TINT`.
func test_fallen_material_carries_the_sets_tint() -> void:
	UnitSilhouettes.reset_models()
	assert_eq(UnitSilhouettes.FALLEN_TINT.keys(), [1, 2], "відтінок мають набори 1 і 2")
	for set_id in UnitSilhouettes.SET_COUNT:
		var base: Color = (UnitSilhouettes.model_material(0, set_id) as ShaderMaterial).get_shader_parameter("albedo_color")
		var got: Color = (UnitSilhouettes.fallen_material(set_id) as ShaderMaterial).get_shader_parameter("albedo_color")
		var want: Color = base
		if UnitSilhouettes.FALLEN_TINT.has(set_id):
			var t: Color = UnitSilhouettes.FALLEN_TINT[set_id]
			want = Color(base.r * t.r, base.g * t.g, base.b * t.b, base.a)
		assert_eq(got, want, "матеріал загиблих, набір %d" % set_id)
	assert_gt(UnitSilhouettes.FALLEN_TINT[1].b, UnitSilhouettes.FALLEN_TINT[1].r, "набір 1 холодніший")
	assert_gt(UnitSilhouettes.FALLEN_TINT[2].r, 1.0, "набір 2 світліший")
