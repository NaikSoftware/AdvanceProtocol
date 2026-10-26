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
	# Ворог проламав клітинку, якої глядач не розвідав: known_broken_map її не містить, і ліс
	# глядача той самий, що й без проламу.
	var state := BattleState.create(_world(), 2, 1)
	state.broken_forest = {Vector2i(7, 5): true}
	var f := _layer()
	var before := _keys(f.board_plan)
	f.set_broken(state.known_broken_map(0))
	assert_eq(_keys(f.board_plan), before, "непобачений пролам не міняє ліс глядача")
	state.vision[0].reveal(Vector2i(7, 5))
	f.set_broken(state.known_broken_map(0))
	assert_ne(_keys(f.board_plan), before, "побачений пролам — видно")
	var standing: bool = f.board_plan.any(func(e: Dictionary) -> bool:
		var p: Vector2 = e["pos"]
		return Vector2i(roundi(p.x), roundi(p.y)) == Vector2i(7, 5) and String(e["node"]).get_slice("_", 0) in ForestLayer.TREES)
	assert_false(standing, "у проламаній клітинці не лишається стоячих дерев")


func test_fade_only_over_shown_units() -> void:
	var f := _layer()
	f.set_reveal_cells([])
	assert_eq(_fade_nodes(f), 0, "нікого не показано — жодна крона не розчиняється")
	f.set_reveal_cells([Vector2i(5, 5)] as Array[Vector2i])
	assert_gt(_fade_nodes(f), 0, "над показаним юнітом крони розчиняються")


func _fade_nodes(f: ForestLayer) -> int:
	return f.get_children().filter(func(n: Node) -> bool: return String(n.name).begins_with("Fade_")).size()


func test_no_realtime_shadow_and_two_forms_per_species() -> void:
	# §8: справжню тінь кидають лише юніти — тінь лісу запечена. Форм на породу дві: кожна —
	# виклик малювання.
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
		assert_lte((forms[species] as Dictionary).size(), 2, "%s: форм у бою" % species)
	assert_not_null(f.get_node_or_null("Forest_Shadow"), "запечена тінь лісу є")
