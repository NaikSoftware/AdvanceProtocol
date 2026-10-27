extends GutTest
## Ліс на дошці бою (ForestLayer): стоїть лише на клітинках FOREST, той самий світ дає той
## самий ліс, а туман війни через ліс нічого не видає — ні проломи, яких глядач не бачив,
## ні юніти, яких йому не показано.


func _world() -> Board:
	# 12 × 10, ліс — прямокутник 2..9 × 2..7 і окрема клітинка 0,0.
	var b: Board = Board.create(12, 10, Terrain.GroundState.DRY)
	for y in range(2, 8):
		for x in range(2, 10):
			b.tiles[y * b.width + x] = Terrain.Kind.FOREST
	b.tiles[0] = Terrain.Kind.FOREST
	return b


func _layer(season: StringName = &"summer") -> ForestLayer:
	var f := ForestLayer.new()
	add_child_autofree(f)
	var b := _world()
	f.build(b, PackedByteArray(), 0, Vector2i(b.width, b.height), season, 7)
	return f


func _keys(plan: Array[Dictionary]) -> Array[String]:
	var out: Array[String] = []
	for e: Dictionary in plan:
		out.append("%s %s" % [e["node"], e["xf"]])
	out.sort()
	return out


func _fade_alphas(f: ForestLayer) -> Array[float]:
	var out: Array[float] = []
	for n: Node in f.get_children():
		if String(n.name).begins_with("Fade_"):
			for a: float in n.get_meta("alphas"):
				out.append(a)
	return out


func test_only_on_forest_cells() -> void:
	var b := _world()
	for season: StringName in [&"late", &"summer", &"early"]:
		var f := _layer(season)
		assert_gt(f.board_plan.size(), 50, "%s: ліс розставлено" % season)
		for e: Dictionary in f.board_plan:
			var p: Vector2 = e["pos"]
			var c := Vector2i(roundi(p.x), roundi(p.y))
			assert_eq(b.kind_at(c), Terrain.Kind.FOREST, "%s: %s стоїть на %s, а не в лісі" % [season, e["node"], c])


func test_same_world_same_forest() -> void:
	assert_eq(_keys(_layer().board_plan), _keys(_layer().board_plan), "той самий світ — той самий ліс")


func test_unseen_break_changes_nothing() -> void:
	# Глядач розвідав пролам на 3,3; ворог проламав ще 8,6, якої глядач не бачив. Ліс глядача —
	# рівно ліс із самим 3,3: будь-який слід 8,6 видав би, де пройшов ворог.
	var state := BattleState.create(_world(), 2, 1)
	state.broken_forest = {Vector2i(3, 3): true, Vector2i(8, 6): true}
	state.vision[0].reveal(Vector2i(3, 3))
	var known: Dictionary = state.known_broken_map(0)
	assert_eq(known.keys(), [Vector2i(3, 3)], "знає лише розвіданий пролам")
	var f := _layer()
	f.set_broken(known)
	var g := _layer()
	g.set_broken({Vector2i(3, 3): true})
	assert_eq(_keys(f.board_plan), _keys(g.board_plan), "ліс глядача — лише з розвіданим проламом")
	var truth := _layer()
	truth.set_broken(state.broken_forest)
	assert_ne(_keys(f.board_plan), _keys(truth.board_plan), "правда (з невидимим проламом) інша — інакше тест нічого б не ловив")
	var standing: bool = f.board_plan.any(func(e: Dictionary) -> bool:
		var p: Vector2 = e["pos"]
		return Vector2i(roundi(p.x), roundi(p.y)) == Vector2i(3, 3) and String(e["node"]).get_slice("_", 0) in ForestLayer.TREES)
	assert_false(standing, "у проламаній клітинці не лишається стоячих дерев")


func test_local_replan_equals_full_plan() -> void:
	# Новий пролам перепланує лише ділянку навколо себе — і дає той самий ліс, що й повне планування.
	var f := _layer(&"late")
	f.set_broken({Vector2i(4, 4): true})
	f.set_broken({Vector2i(4, 4): true, Vector2i(5, 4): true, Vector2i(8, 6): true})
	var local := _keys(f.board_plan)
	f._rebuild_board()
	assert_eq(local, _keys(f.board_plan), "план ділянки збігається з повним")


func test_fade_only_over_shown_units() -> void:
	for with_camera: bool in [false, true]:
		var f := _layer()
		if with_camera:
			# Камера гри: погляд згори під ~50°, з боку −x −z — розчинення за віссю погляду.
			var cam := Camera3D.new()
			add_child_autofree(cam)
			cam.look_at_from_position(Vector3(-4.0, 14.0, -4.0), Vector3(5.0, 0.0, 5.0))
			cam.make_current()
		var tag: String = "з камерою" if with_camera else "без камери"
		f.set_reveal_cells([])
		assert_eq(_fade_alphas(f).size(), 0, "%s: нікого не показано — жодна крона не розчиняється" % tag)
		var u := Vector2i(5, 5)
		f.set_reveal_cells([u] as Array[Vector2i])
		assert_gt(_fade_alphas(f).size(), 0, "%s: над показаним юнітом крони розчиняються" % tag)
		# Далекі крони (далі 4 клітинок від юніта) лишаються цілими.
		for g: Dictionary in f._fadable:
			var list: Array = g["list"]
			var alpha: PackedFloat32Array = g["alpha"]
			for i in list.size():
				if (list[i]["pos"] as Vector2).distance_to(Vector2(u)) > 4.0:
					assert_eq(alpha[i], 1.0, "%s: далека крона %s лишається цілою" % [tag, (g["mmi"] as Node).name])
					break


func test_no_realtime_shadow_and_budget_forms() -> void:
	# §8: справжню тінь кидають лише юніти — тінь лісу запечена. Форми — лише з FORMS (по дві на
	# породу й бура пізньої осені): кожна — виклик малювання.
	var f := _layer(&"late")
	var forms: Dictionary = {}
	for n: Node in f.get_children():
		if n is GeometryInstance3D:
			assert_eq((n as GeometryInstance3D).cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s кидає тінь" % n.name)
	for e: Dictionary in f.board_plan:
		var species: String = String(e["node"]).get_slice("_", 0)
		if species in ForestLayer.TREES:
			if not forms.has(species):
				forms[species] = {}
			forms[species][e["node"]] = true
	for species: String in forms:
		for node: String in forms[species]:
			assert_true(node in ForestLayer.FORMS, "%s: форма не з бюджету бою" % node)
	assert_not_null(f.get_node_or_null("Forest_Shadow"), "запечена тінь лісу є")


func test_fade_reaches_every_foliage_group() -> void:
	# Над показаним юнітом напівпрозорим стає все листя від ~1,6 м, а не лише намет: крони (й
	# пожовклі осінні), смуги узлісся, кущі. Кожну групу перевіряємо юнітом на її першому досить
	# високому екземплярі: той зникає з головної групи й з'являється в злитій сітці розчинення з
	# альфою 30–40 %, з проходом глибини й проходом кольору з прозорістю.
	for season: StringName in [&"early", &"late"]:
		var f := _layer(season)
		var tested: int = 0
		for g: Dictionary in f._fadable:
			var list: Array = g["list"]
			# Екземпляр близько центру своєї клітинки: юніт стоїть у центрі, а без камери (погляд згори)
			# крона закриває його, лише стоячи над ним.
			var i: int = list.find_custom(func(it: Dictionary) -> bool:
				var q: Vector2 = it["pos"]
				return float(it["top"]) >= ForestLayer.FADE_MIN_TOP and q.distance_to(Vector2(roundi(q.x), roundi(q.y))) < 0.25)
			if i < 0:
				continue
			tested += 1
			var node: Node = g["mmi"]
			var p: Vector2 = list[i]["pos"]
			f.set_reveal_cells([Vector2i(roundi(p.x), roundi(p.y))] as Array[Vector2i])
			assert_almost_eq((g["alpha"] as PackedFloat32Array)[i], 0.0, 0.001, "%s/%s: у головній групі зник" % [season, node.name])
			var alphas := _fade_alphas(f)
			assert_false(alphas.is_empty(), "%s/%s: є сітка розчинення" % [season, node.name])
			if alphas.is_empty():
				continue
			assert_between(alphas.min(), 0.3, 0.4, "%s/%s: альфа над юнітом" % [season, node.name])
			for n: Node in f.get_children():
				if String(n.name).begins_with("Fade_"):
					var depth := (n as GeometryInstance3D).material_override as ShaderMaterial
					var color := depth.next_pass as ShaderMaterial
					assert_true(depth.shader.code.contains("depth_draw_always"), "%s: спершу прохід глибини" % n.name)
					assert_true(color != null and color.shader.code.contains("ALPHA = COLOR.a;"), "%s: потім колір із прозорістю" % n.name)
		assert_gt(tested, 3, "%s: груп листя перевірено" % season)


func test_fade_only_crowns_on_the_view_axis() -> void:
	# Над юнітом розчиняються лише крони, що на екрані його перекривають: 1–4 дерева, а не шмат
	# лісу довкола. Крони за ~1 клітинку вбік від осі погляду лишаються цілими.
	for season: StringName in [&"summer", &"late"]:
		var f := _layer(season)
		var cam := Camera3D.new()
		add_child_autofree(cam)
		cam.look_at_from_position(Vector3(-4.0, 14.0, -4.0), Vector3(5.0, 0.0, 5.0))
		cam.make_current()
		var u := Vector2i(5, 5)
		f.set_reveal_cells([u] as Array[Vector2i])
		var back: Vector3 = cam.global_transform.basis.z
		var dir := Vector2(back.x, back.z).normalized()
		var faded: int = 0
		for g: Dictionary in f._fadable:
			var list: Array = g["list"]
			var alpha: PackedFloat32Array = g["alpha"]
			for i in list.size():
				if float(list[i]["top"]) < ForestLayer.UNDER_TOP:
					continue
				if alpha[i] < 1.0:
					faded += 1
				var rel: Vector2 = (list[i]["pos"] as Vector2) - Vector2(u)
				var lateral: float = absf(rel.x * dir.y - rel.y * dir.x)
				if lateral > 1.0:
					assert_eq(alpha[i], 1.0, "%s: крона за %.1f клітинки вбік від осі погляду лишається цілою" % [season, lateral])
		assert_between(faded, 1, 4, "%s: розчинено крон над юнітом" % season)
		cam.free()


## Світ 18 × 14 із кільцем у 3 клітинки: дошка 12 × 8, ліс і на дошці, і в кільці.
func _ring_layer(season: StringName = &"summer") -> ForestLayer:
	var f := ForestLayer.new()
	add_child_autofree(f)
	var w: Board = Board.create(18, 14, Terrain.GroundState.DRY)
	for y in 14:
		for x in 18:
			if (x < 3 or y < 3 or x >= 15 or y >= 11) or (x in range(6, 12) and y in range(5, 9)):
				w.tiles[y * w.width + x] = Terrain.Kind.FOREST
	f.build(w, PackedByteArray(), 3, Vector2i(12, 8), season, 7)
	return f


func _drawn(f: ForestLayer) -> Array[Node]:
	var out: Array[Node] = []
	for n: Node in f.get_children():
		if n is GeometryInstance3D and not (String(n.name).begins_with("Fade_") or n.name == &"Forest_Shadow" or n.name == &"Forest_Soil_Lane"):
			out.append(n)
	return out


## Бюджет кадру (§8): ліс — один виклик малювання на атлас і шар (кільце з дошкою, підлісок), а не на
## кожну форму. Без цього тридцять з гаком MultiMesh з'їдали третину ліміту викликів.
func test_foliage_is_one_mesh_per_atlas_and_layer() -> void:
	for season: StringName in [&"early", &"late"]:
		var f := _ring_layer(season)
		var drawn := _drawn(f)
		assert_gt(f.board_plan.size(), 20, "%s: ліс на дошці" % season)
		for n: Node in drawn:
			assert_false(n is MultiMeshInstance3D, "%s: %s — MultiMesh на форму" % [season, n.name])
		# 2 атласи × (дошка з кільцем, підлісок).
		assert_lte(drawn.size(), 4, "%s: %d вузлів листя" % [season, drawn.size()])
		assert_gt(f._ring_fadable.size(), 0, "%s: кільце в злитій сітці" % season)


## Розчинення працює і зі злитою сіткою: розчинений екземпляр гасне в таблиці даних батча (й
## вертає, коли юніт іде), а решта лишається.
func test_fade_hides_the_instance_inside_the_merged_mesh() -> void:
	var f := _ring_layer()
	var cam := Camera3D.new()
	add_child_autofree(cam)
	cam.look_at_from_position(Vector3(-4.0, 14.0, -4.0), Vector3(5.0, 0.0, 5.0))
	cam.make_current()
	var shown: int = 0
	for g: Dictionary in f._fadable:
		for i in (g["list"] as Array).size():
			assert_true((g["batch"] as FoliageBatch).is_alive(int(g["first"]) + i), "до розчинення всі цілі")
	var u := Vector2i(5, 3)
	f.set_reveal_cells([u] as Array[Vector2i])
	var gone: int = 0
	for g: Dictionary in f._fadable + f._ring_fadable:
		var alpha: PackedFloat32Array = g["alpha"]
		for i in alpha.size():
			var alive: bool = (g["batch"] as FoliageBatch).is_alive(int(g["first"]) + i)
			assert_eq(alive, alpha[i] >= 1.0, "таблиця батча збігається з альфою")
			if not alive:
				gone += 1
	assert_between(gone, 1, 4, "над юнітом зникли 1–4 крони")
	f.set_reveal_cells([] as Array[Vector2i])
	for g: Dictionary in f._fadable + f._ring_fadable:
		for i in (g["list"] as Array).size():
			assert_true((g["batch"] as FoliageBatch).is_alive(int(g["first"]) + i), "юніт пішов — усе знову ціле")
