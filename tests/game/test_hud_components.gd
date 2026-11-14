extends GutTest
## Малі компоненти HUD: глиф броні, ромбики дронів, смужка озброєння.

const THEME := preload("res://game/ui/theme/hud_theme.tres")


func test_armour_glyph_holds_the_sector_core_gave_it() -> void:
	var g := ArmourGlyph.new()
	add_child_autofree(g)
	assert_eq(g.sector(), ArmourGlyph.NO_SECTOR, "типово нічого не світиться (картка утримання)")
	assert_eq(g.custom_minimum_size, Vector2(30, 46))
	for s: int in [UnitTypes.ArmourSector.FRONT, UnitTypes.ArmourSector.SIDE, UnitTypes.ArmourSector.REAR]:
		g.set_sector(s)
		assert_eq(g.sector(), s)
	g.set_sector(ArmourGlyph.NO_SECTOR)
	assert_eq(g.sector(), ArmourGlyph.NO_SECTOR, "FRONT (0) і «нічого» (−1) — різні речі")
	g.set_turret(true)
	g.set_sector(UnitTypes.ArmourSector.SIDE)
	await get_tree().process_frame


func test_armour_glyph_wedges_are_clipped_to_the_hull() -> void:
	var g := ArmourGlyph.new()
	add_child_autofree(g)
	g.set_sector(UnitTypes.ArmourSector.FRONT)
	var polys: Array[PackedVector2Array] = g._lit_polygons()
	assert_eq(polys.size(), 1)
	for p: Vector2 in polys[0]:
		assert_true(Geometry2D.is_point_in_polygon(p, ArmourGlyph._HULL) or ArmourGlyph._HULL.has(p) or _on_edge(p),
			"вершина клина %s лежить на корпусі" % p)
	g.set_sector(UnitTypes.ArmourSector.SIDE)
	assert_eq(g._lit_polygons().size(), 2, "борт — два клини")


func _on_edge(p: Vector2) -> bool:
	var h: PackedVector2Array = ArmourGlyph._HULL
	for i in h.size():
		if Geometry2D.get_closest_point_to_segment(p, h[i], h[(i + 1) % h.size()]).distance_to(p) < 0.01:
			return true
	return false


func test_drone_pips_track_remaining_and_total() -> void:
	var p := DronePips.new()
	add_child_autofree(p)
	p.set_counts(1, 2)
	assert_eq(p.counts(), Vector2i(1, 2))
	assert_gt(p.custom_minimum_size.x, 0.0)
	p.set_counts(0, 2)
	assert_eq(p.counts(), Vector2i(0, 2), "на нулі два контури лишаються: лічильник публічний (§3.9)")


func test_armed_strip_geometry_and_input() -> void:
	var s := ArmedStrip.new()
	s.theme = THEME
	add_child_autofree(s)
	s.configure(null, "Test", "Hint")
	await get_tree().process_frame
	assert_eq(s.size, Vector2(285, 52), "285 × 52")
	assert_eq(s.cancel_button.global_position.x - s.global_position.x + s.cancel_button.size.x, 126.0, "«Скасувати» з лівим краєм — 126 dp")
	assert_eq(s.armed_cell.mouse_filter, Control.MOUSE_FILTER_STOP)
	var presses: Array[int] = [0]
	s.cancel_pressed.connect(func() -> void: presses[0] += 1)
	s.cancel_button.pressed.emit()
	assert_eq(presses[0], 1)


func test_armed_strip_grows_leftwards_not_rightwards_for_long_text() -> void:
	var s := ArmedStrip.new()
	s.theme = THEME
	add_child_autofree(s)
	s.configure(null, "Test", "Дуже довга підказка, що не влізає у 285 dp ніяк і навіть близько")
	await get_tree().process_frame
	assert_gt(s.size.x, 285.0, "довший вміст розширює смужку (HUD приторкає її правим краєм)")
	assert_eq(s.cancel_button.global_position.x - s.global_position.x, 1.0, "«Скасувати» лишається першою коміркою зліва, за краєм 1 dp")
