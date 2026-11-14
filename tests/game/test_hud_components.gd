extends GutTest
## Малі компоненти HUD: глиф броні, ромбики дронів, смужка озброєння.

const THEME := preload("res://game/ui/theme/hud_theme.tres")


func test_armour_glyph_holds_the_sector_core_gave_it() -> void:
	var g := ArmourGlyph.new()
	add_child_autofree(g)
	assert_eq(g.sector(), ArmourGlyph.NO_SECTOR, "типово нічого не світиться (картка утримання)")
	assert_eq(g.custom_minimum_size, Vector2(26, 40), "глиф 26 × 40")
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
	assert_eq(s.size, Vector2(HudDocking.CLUSTER_W, 48), "спільна ширина × 48 тап-цілі, як ряд дій")
	assert_eq(s.size.x, 252.0, "спільна ширина — 252 dp")
	assert_eq(s.cancel_button.global_position.x - s.global_position.x + s.cancel_button.size.x, 104.0, "«Скасувати» — 104 dp, як у ряду")
	var face := s.get_theme_stylebox(&"panel")
	assert_eq(face.get_expand_margin(SIDE_BOTTOM), -8.0, "малюнок смужки — 40 dp, нижні 8 dp тап-цілі без плити")
	assert_eq(s.armed_cell.mouse_filter, Control.MOUSE_FILTER_STOP)
	var presses: Array[int] = [0]
	s.cancel_pressed.connect(func() -> void: presses[0] += 1)
	s.cancel_button.pressed.emit()
	assert_eq(presses[0], 1)


## Смужка не розширюється під підпис: вона ділить ширину з плитою прев'ю й рядом. Кожна справжня назва
## й підказка (дрон і п'ять верб, обома мовами) влазить у клітинку «озброєно» без обрізання.
func test_armed_strip_keeps_the_shared_width_for_every_real_title() -> void:
	var s := ArmedStrip.new()
	s.theme = THEME
	add_child_autofree(s)
	var locale: String = TranslationServer.get_locale()
	var titles: Array[Array] = [["hud_drone_strike", "drone_hint_tap_target", Vector2i(2, 2)]]
	for key: String in EngineerPanel.LABEL_KEYS.values():
		titles.append([key, "eng_hint_tap_tile", Vector2i(-1, -1)])
	for loc: String in ["uk", "en"]:
		TranslationServer.set_locale(loc)
		for t: Array in titles:
			s.configure(preload("res://assets/ui/icons/btn_drone.svg"), tr(t[0]), tr(t[1]), t[2])
			await get_tree().process_frame
			var where: String = "%s %s" % [loc, t[0]]
			assert_eq(s.get_combined_minimum_size().x, HudDocking.CLUSTER_W, "смужка не ширшає: " + where)
			for l: Label in [s.title_label, s.hint_label]:
				var w: float = l.get_theme_font(&"font").get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size(&"font_size")).x
				assert_lte(w, l.size.x, "підпис цілий: %s «%s»" % [where, l.text])
				assert_lte(l.get_global_rect().end.x, s.get_global_rect().end.x - 7.0, "≥ 7 dp до краю смужки: %s «%s»" % [where, l.text])
	TranslationServer.set_locale(locale)


func _row_with(texts: Array[String], variations: Array[StringName]) -> BaselineRow:
	var holder := Control.new()
	holder.theme = THEME
	add_child_autofree(holder)
	var row := BaselineRow.new()
	holder.add_child(row)
	for i in texts.size():
		var l := Label.new()
		l.theme_type_variation = variations[i]
		l.text = texts[i]
		row.add_child(l)
	return row


func test_baseline_row_puts_value_and_max_on_one_baseline_without_a_gap() -> void:
	var row: BaselineRow = _row_with(["28", "/48"], [&"HudNumberMove", &"HudNumberDim15"])
	await get_tree().process_frame
	var big := row.get_child(0) as Label
	var small := row.get_child(1) as Label
	var big_base: float = big.position.y + big.get_theme_font(&"font").get_ascent(big.get_theme_font_size(&"font_size"))
	var small_base: float = small.position.y + small.get_theme_font(&"font").get_ascent(small.get_theme_font_size(&"font_size"))
	assert_eq(small_base, big_base, "базові лінії збігаються")
	assert_eq(small.position.x, big.size.x - BaselineRow.TUCK, "знаменник одразу за числом, з підтяжкою")
	assert_eq(row.get_combined_minimum_size().x, big.size.x + small.size.x - BaselineRow.TUCK)


func test_hold_card_tank_is_142_dp_and_squad_adds_its_rows() -> void:
	var holder := Control.new()
	holder.theme = THEME
	add_child_autofree(holder)
	var card := HoldCard.new()
	holder.add_child(card)
	card.show_unit(Unit.create(1, 5, 1, Vector2i.ZERO, 0), false)
	await get_tree().process_frame
	assert_eq(card.get_combined_minimum_size().y, 142.0, "картка танка: 2 краї + 44 голова + 43 характеристики + 53 броня")
	card.show_unit(Unit.create(2, 1, 1, Vector2i.ZERO, 0), true)
	await get_tree().process_frame
	await get_tree().process_frame
	# Рядок «Броня немає» 30, ряд дронів 1 + 24, підпис «щонайменше» 1 + 5 + текст + 5.
	var floor_h: float = card.floor_label.get_combined_minimum_size().y
	assert_eq(card.get_combined_minimum_size().y, 2.0 + 44.0 + 43.0 + 30.0 + 25.0 + 11.0 + floor_h, "сума секцій")
	assert_eq(card.floor_label.get_line_count(), 2, "підпис «щонайменше» — два рядки")


func test_hold_card_width_is_one_constant_for_every_unit_and_caption() -> void:
	var holder := Control.new()
	holder.theme = THEME
	add_child_autofree(holder)
	var card := HoldCard.new()
	holder.add_child(card)
	assert_eq(HoldCard.WIDTH, 212.0, "картка 212 dp")
	var locale: String = TranslationServer.get_locale()
	for loc: String in ["uk", "en"]:
		TranslationServer.set_locale(loc)
		for type_id in UnitTypes.TYPES.size():
			for floor_on: bool in [false, true]:
				card.show_unit(Unit.create(1, type_id, 1, Vector2i.ZERO, 0), floor_on)
				await get_tree().process_frame
				await get_tree().process_frame
				assert_eq(card.get_combined_minimum_size().x, HoldCard.WIDTH, "%s/тип %d/підпис %s: мінімальна ширина" % [loc, type_id, floor_on])
				assert_eq(card.size.x, HoldCard.WIDTH, "%s/тип %d/підпис %s: справжня ширина" % [loc, type_id, floor_on])
	TranslationServer.set_locale(locale)


## Назва ділить рядок із силуетом 34 dp і проміжком 6: 212 − 2 (рамка) − 16 (відступ із вкладкою) − 12 − 34 − 6 = 142 dp.
## «Штурмове відділення» (найдовша назва зі спеку) вміщується цілою в обох мовах.
func test_hold_card_shows_the_assault_squad_name_in_full() -> void:
	var holder := Control.new()
	holder.theme = THEME
	add_child_autofree(holder)
	var card := HoldCard.new()
	holder.add_child(card)
	var locale: String = TranslationServer.get_locale()
	for loc: String in ["uk", "en"]:
		TranslationServer.set_locale(loc)
		card.show_unit(Unit.create(1, 1, 1, Vector2i.ZERO, 0), false)
		await get_tree().process_frame
		await get_tree().process_frame
		var label: Label = card.name_label
		var font: Font = label.get_theme_font("font")
		var text_w: float = font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, label.get_theme_font_size("font_size")).x
		assert_lte(text_w, label.size.x, "%s/%s: назва вміщується без крапок" % [loc, label.text])
	TranslationServer.set_locale(locale)


func test_unit_tag_name_label_is_as_wide_as_its_text() -> void:
	var holder := Control.new()
	holder.theme = THEME
	add_child_autofree(holder)
	var tag := UnitTag.new()
	holder.add_child(tag)
	tag.show_unit(Unit.create(1, 11, 0, Vector2i.ZERO, 0), true)
	await get_tree().process_frame
	var font: Font = tag.name_label.get_theme_font(&"font")
	var text_w: float = font.get_string_size(tag.name_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, tag.name_label.get_theme_font_size(&"font_size")).x
	assert_true(tag.name_label.get_combined_minimum_size().x >= text_w, "назва не обрізається")
	var t := tag.get_combined_minimum_size()
	assert_eq(t.y, 26.0, "тег 26 dp заввишки")
	assert_eq(t.x, 2.0 + 6.0 + 22.0 + 5.0 + tag.name_label.get_combined_minimum_size().x + 7.0, "краї 1 + 1, поле 6, силует 22, проміжок 5, назва, поле 7")
