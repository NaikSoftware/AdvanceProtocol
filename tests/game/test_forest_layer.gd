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
		if String(n.name).begins_with("Fade_") and n.has_meta("alphas"):
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
			# майже прозора: число стоячих бійців — це HP, і напівпрозоре листя робило б їх привидами
			assert_almost_eq(alphas.min(), ForestLayer.FADE_ALPHA, 0.001, "%s/%s: альфа над юнітом" % [season, node.name])
			for n: Node in f.get_children():
				if String(n.name).begins_with("Fade_"):
					var m := (n as GeometryInstance3D).material_override as ShaderMaterial
					if String(n.name).ends_with("_c"):
						assert_true(m.shader.code.contains("fade_far(VERTEX, VIEW_MATRIX)"), "%s: колір із прозорістю" % n.name)
						assert_eq(m.render_priority, PropLayer.FADE_DEPTH_PRIORITY + 1, "%s: колір після глибини" % n.name)
					else:
						assert_true(m.shader.code.contains("depth_draw_always"), "%s: спершу прохід глибини" % n.name)
						assert_null(m.next_pass, "%s: колір — окремим вузлом, не next_pass" % n.name)
		assert_gt(tested, 3, "%s: груп листя перевірено" % season)


## Камера гри на нахилі `pitch_deg` (той самий кут повороту, що й у IsoCameraRig), дивиться на `target`.
func _rig_camera(pitch_deg: float, target: Vector3) -> Camera3D:
	var cam := Camera3D.new()
	add_child_autofree(cam)
	var back: Vector3 = Basis(Vector3.UP, deg_to_rad(IsoCameraRig.YAW_DEGREES)) * Basis(Vector3.RIGHT, -deg_to_rad(pitch_deg)) * Vector3.BACK
	cam.look_at_from_position(target + back * 14.0, target)
	cam.make_current()
	return cam


## Чи закриває крона бійця в точці `o` (світ, XZ): промінь від ступень до голови до камери проходить крізь
## стовп крони. Незалежно від ForestLayer.covers_slots — дрібним кроком уздовж променя.
func _ray_hits(e: Dictionary, o: Vector2, dir: Vector2, slope: float) -> bool:
	var p: Vector2 = e["pos"]
	var r: float = float(e["r"])
	var top: float = float(e["top"])
	for k in 400:
		var sd: float = float(k) * 0.01
		var q: Vector2 = o + dir * sd
		if q.distance_to(p) >= r:
			continue
		# висоти променів бійця над цією точкою: від ступень до голови
		if ForestLayer.FIGURE_LOW + slope * sd <= top and ForestLayer.FIGURE_HIGH + slope * sd >= top * ForestLayer.CROWN_LOW:
			return true
	return false


## Скільки крон (з підростом) розчиняється над одним юнітом у тестовому лісі — стеля за сезоном і нахилом
## (38° і 55°): більше означало б, що розчиняється шмат лісу, а не те, що закриває бійців.
const FADE_CEILING: Dictionary = {&"summer": {38: 23, 55: 17}, &"late": {38: 32, 55: 28}}
## Те саме над трьома юнітами поряд (літо).
const FADE_CEILING_THREE: Dictionary = {38: 38, 55: 35}


## Для юнітів `units` на нахилі `pitch`: кожна крона, що закриває якесь місце бійця (сітка точок у межах
## місць), розчинена, і кожна розчинена закриває якесь (з запасом сітки на межі SLOT_SPREAD).
func _check_fade_matches_slot_rays(f: ForestLayer, units: Array[Vector2i], cam: Camera3D, tag: String) -> int:
	var back: Vector3 = cam.global_transform.basis.z
	var dir := Vector2(back.x, back.z).normalized()
	var slope: float = back.y / Vector2(back.x, back.z).length()
	var faded: int = 0
	for g: Dictionary in f._fadable:
		var list: Array = g["list"]
		var alpha: PackedFloat32Array = g["alpha"]
		for i in list.size():
			var e: Dictionary = list[i]
			if float(e["top"]) < ForestLayer.FADE_MIN_TOP:
				continue
			var in_slots: bool = false  # закриває справжнє місце бійця (до 0,16 від середини)
			var in_band: bool = false   # закриває квадрат ±SLOT_SPREAD, яким міряє шар
			for u in units:
				for gy in range(-4, 5):
					for gx in range(-4, 5):
						# квадрат у системі погляду: уздовж і поперек променя, як міряє шар
						var off: Vector2 = (dir * float(gx) + Vector2(-dir.y, dir.x) * float(gy)) * (ForestLayer.SLOT_SPREAD + 0.01) / 4.0
						if _ray_hits(e, Vector2(u) + off, dir, slope):
							in_band = true
							if off.length() <= 0.16:
								in_slots = true
			if alpha[i] < 1.0:
				faded += 1
				assert_true(in_band, "%s: розчинена крона %s нікого не закриває" % [tag, e["pos"]])
			else:
				assert_false(in_slots, "%s: крона %s закриває бійця, але не розчинена" % [tag, e["pos"]])
	return faded


## Над юнітом розчиняються рівно ті крони, що закривають бійців: на краю лісу й у ньому, на обох нахилах.
func test_fade_selects_exactly_the_crowns_over_the_slot_rays() -> void:
	for season: StringName in [&"summer", &"late"]:
		for pitch: float in [IsoCameraRig.PITCH_NEAR_DEG, IsoCameraRig.PITCH_FAR_DEG]:
			for u: Vector2i in [Vector2i(5, 5), Vector2i(10, 5), Vector2i(5, 8), Vector2i(1, 4)]:
				var f := _layer(season)
				var cam := _rig_camera(pitch, Vector3(u.x, 0.0, u.y))
				f.set_reveal_cells([u] as Array[Vector2i])
				var faded: int = _check_fade_matches_slot_rays(f, [u] as Array[Vector2i], cam, "%s %d° %s" % [season, pitch, u])
				# сторож від плями-«привида»: зафіксовані кількості для цього лісу (з підростом від 0,8 м)
				assert_between(faded, 0, int(FADE_CEILING[season][int(pitch)]), "%s %d° %s: розчинено крон" % [season, pitch, u])
				if u == Vector2i(5, 5):
					assert_gt(faded, 0, "у лісі над юнітом щось розчиняється")
				cam.free()


## Розчинені крони не нашаровуються, хай з якого атласу чи шару (ліс, садові дерева, окремі злиті сітки):
## спершу всі проходи глибини (найближча поверхня), потім усі проходи кольору — колір проходить лише там, де
## його поверхня найближча. Тож і пріоритети тих самих двох рівнів, що в рослин (PropLayer).
func test_faded_crowns_of_every_atlas_blend_only_the_nearest_surface() -> void:
	var f := _layer(&"summer")
	assert_gt(f._fade_mat.size(), 1, "передумова: кілька атласів")
	for atlas: Texture2D in f._fade_mat:
		var depth: ShaderMaterial = f._fade_mat[atlas]
		var color: ShaderMaterial = f._fade_color[atlas]
		assert_null(depth.next_pass, "колір — окремим вузлом: next_pass малюється одразу за своєю глибиною")
		assert_true(depth.shader.code.contains("depth_draw_always"), "прохід глибини пише глибину")
		assert_eq(depth.render_priority, PropLayer.FADE_DEPTH_PRIORITY, "глибина — на рівні рослин")
		assert_eq(color.render_priority, PropLayer.FADE_DEPTH_PRIORITY + 1, "колір — після всіх проходів глибини")
		assert_gt(depth.render_priority, BoardView.CONTOUR_PRIORITY, "контур зон — до розчиненої крони")


## На рельєфі крона на вищій землі сягає вище в погляд: та сама крона, що на рівній землі промінь бійця минає
## згори, на пагорбі перед юнітом його закриває.
func test_crown_on_higher_ground_covers_a_slot_it_would_miss_on_flat() -> void:
	var dir := Vector2(1, 1).normalized()
	var slope: float = 0.78
	var u := Vector2(4, 15)
	var p: Vector2 = u + dir * 1.4
	assert_false(ForestLayer.covers_slots(p, 0.5, 0.44, u, dir, slope), "передумова: на рівному промінь іде над кущем")
	assert_true(ForestLayer.covers_slots(p, 0.5, 0.44, u, dir, slope, 0.15), "кущ на 1,2 м вище — закриває")


## Розчинена крона прозора лише довкола юнітів під нею: матеріал кольору отримує їхні точки (клітинка на
## висоті середини фігури) — лише тих, над ким крону справді розчинено; юніт у полі точки не займає.
func test_fade_colour_gets_only_the_units_under_a_faded_crown() -> void:
	var f := _layer(&"summer")
	f.set_reveal_cells([Vector2i(5, 5), Vector2i(-40, -40)] as Array[Vector2i])
	assert_true(f._fading.has(Vector2i(5, 5)), "передумова: над (5, 5) крону розчинено")
	assert_false(f._fading.has(Vector2i(-40, -40)), "далеко від лісу — нічого не розчинено")
	for m: ShaderMaterial in f._fade_color.values():
		assert_eq(m.get_shader_parameter("fade_count"), f._fading.size())
		var pts: PackedVector4Array = m.get_shader_parameter("fade_points")
		assert_eq(pts[0], Vector4(5.0, ForestLayer.FIGURE_MID_Y, 5.0, 0.0), "середина фігури над клітинкою")
	f.set_reveal_cells([] as Array[Vector2i])
	for m: ShaderMaterial in f._fade_color.values():
		assert_eq(m.get_shader_parameter("fade_count"), 0)


## Наближення через DETAIL_ZOOM навіть на крок, менший за FADE_ZOOM_STEP, перераховує розчинення: підлісок,
## пропущений далі за DETAIL_ZOOM, мусить розчинитись над юнітом, щойно з'являється.
func test_crossing_detail_zoom_refades_even_on_a_small_step() -> void:
	var f := _layer(&"summer")
	var step: float = ForestLayer.FADE_ZOOM_STEP * 0.25
	f.set_zoom(ForestLayer.DETAIL_ZOOM + step)
	f.set_reveal_cells([Vector2i(5, 5)] as Array[Vector2i])
	assert_almost_eq(f._fade_zoom, ForestLayer.DETAIL_ZOOM + step, 1e-6, "передумова: розчинено на дальньому зумі")
	f.set_zoom(ForestLayer.DETAIL_ZOOM - step)
	assert_almost_eq(f._fade_zoom, ForestLayer.DETAIL_ZOOM - step, 1e-6, "перетин DETAIL_ZOOM — перерахунок")
	f.set_zoom(ForestLayer.DETAIL_ZOOM - step * 2.0)
	assert_almost_eq(f._fade_zoom, ForestLayer.DETAIL_ZOOM - step, 1e-6, "малий крок без перетину — без перерахунку")


## Юнітів під кронами більше, ніж точок у шейдері: розчинені крони гаснуть цілими до 35 % (fade_count −1),
## а не стають непрозорими над тим, хто не вліз у список.
func test_more_units_than_points_fade_whole_crowns_never_opaque() -> void:
	var f := _layer(&"summer")
	var cells: Array[Vector2i] = []
	for y in range(1, 11):
		for x in range(1, 11):
			cells.append(Vector2i(x, y))
	f.set_reveal_cells(cells)
	assert_gt(f._fading.size(), ForestLayer.FADE_POINTS, "передумова: під кронами більше юнітів, ніж точок")
	for m: ShaderMaterial in f._fade_color.values():
		assert_eq(m.get_shader_parameter("fade_count"), -1, "ціла крона, а не непрозора")
		assert_true(m.shader.code.contains("if (fade_count < 0)"), "шейдер знає про переповнення")


## Три юніти поряд — те саме для кожного.
func test_fade_over_adjacent_units_covers_every_slot() -> void:
	for pitch: float in [IsoCameraRig.PITCH_NEAR_DEG, IsoCameraRig.PITCH_FAR_DEG]:
		var f := _layer(&"summer")
		var units: Array[Vector2i] = [Vector2i(4, 5), Vector2i(5, 5), Vector2i(5, 6)]
		var cam := _rig_camera(pitch, Vector3(5.0, 0.0, 5.0))
		f.set_reveal_cells(units)
		var n3: int = _check_fade_matches_slot_rays(f, units, cam, "троє, %d°" % pitch)
		assert_between(n3, 1, int(FADE_CEILING_THREE[int(pitch)]), "троє, %d°: розчинено крон" % pitch)
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
		# 2 атласи × (кільце, дошка, підлісок).
		assert_lte(drawn.size(), 6, "%s: %d вузлів листя" % [season, drawn.size()])
		assert_gt(f._ring_fadable.size(), 0, "%s: кільце в злитій сітці" % season)


## Розчинення працює і зі злитою сіткою: розчинений екземпляр гасне в таблиці даних батча (й
## вертає, коли юніт іде), а решта лишається.
func test_fade_hides_the_instance_inside_the_merged_mesh() -> void:
	var f := _ring_layer()
	var cam := Camera3D.new()
	add_child_autofree(cam)
	cam.look_at_from_position(Vector3(-4.0, 14.0, -4.0), Vector3(5.0, 0.0, 5.0))
	cam.make_current()
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
	assert_gt(gone, 0, "над юнітом щось розчинилось")
	f.set_reveal_cells([] as Array[Vector2i])
	for g: Dictionary in f._fadable + f._ring_fadable:
		for i in (g["list"] as Array).size():
			assert_true((g["batch"] as FoliageBatch).is_alive(int(g["first"]) + i), "юніт пішов — усе знову ціле")
