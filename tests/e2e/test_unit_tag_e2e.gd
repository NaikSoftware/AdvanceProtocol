extends GutTest
## Тег вибраного юніта й картка утримання на справжній сцені бою: екранні прямокутники беруться з
## вузлів UnitView, тап і довгий натиск — справжні події миші через viewport.

const E2E := preload("res://tests/e2e/e2e_helpers.gd")

const RIFLE: int = 0
const ASSAULT: int = 1
const MEDIUM_TANK: int = 5
const ENGINEER: int = 11
const E: int = 2

const SQUAD := Vector2i(2, 2)
const TANK := Vector2i(3, 2)
const ENEMY_TANK := Vector2i(6, 2)
const ENEMY_SQUAD := Vector2i(4, 4)
const HIDDEN := Vector2i(8, 4)

var _e2e: E2E
var _orig_locale: String


func before_each() -> void:
	_e2e = E2E.new(self)
	_orig_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("uk")


func after_each() -> void:
	TranslationServer.set_locale(_orig_locale)
	_e2e.restore_runner_gui()
	DirAccess.remove_absolute(_e2e.save_path)
	DirAccess.remove_absolute(_e2e.save_path + ".map")


func _spawn(type_id: int, owner: int, pos: Vector2i) -> Dictionary:
	return {"type_id": type_id, "owner": owner, "pos": pos, "facing": E}


func _boot(size: Vector2i, spawns: Array, scouted: bool = true) -> void:
	await _e2e.boot(10, 5, spawns, {"viewport_size": size,
		"prepare": func(st: BattleState) -> void:
			if scouted:
				for pl in st.player_count:
					st.vision[pl].seen.fill(1)})


func _tap(cell: Vector2i) -> void:
	_e2e.tap(cell)
	await _e2e.settle()


func _tag() -> UnitTag:
	return _e2e.hud().unit_tag()


func _card() -> HoldCard:
	return _e2e.hud().hold_card()


func _sizes() -> Array:
	var out: Array = []
	for s: Vector2i in LayoutProbe.SIZES:
		out.append(s)
	return out


# --- Тег ----------------------------------------------------------------------------

## Тег не лягає ні на свого юніта, ні на коробку жодного іншого видимого юніта, ні на хром.
func test_tag_never_covers_a_visible_unit(size = use_parameters(_sizes())) -> void:
	await _boot(size, [_spawn(ASSAULT, 0, SQUAD), _spawn(MEDIUM_TANK, 0, TANK), _spawn(MEDIUM_TANK, 1, ENEMY_TANK),
		_spawn(RIFLE, 1, ENEMY_SQUAD)])
	await _tap(SQUAD)
	var tag: UnitTag = _tag()
	assert_true(tag.visible, "тег вибраного юніта: %s" % size)
	var rig: IsoCameraRig = _e2e.screen.get_node("%CameraRig")
	var rect: Rect2 = Rect2(tag.global_position, tag.size)
	for id: int in _e2e.service.state.units:
		var view: UnitView = _e2e.screen.unit_view_for(id)
		if view == null:
			continue
		var box: Rect2 = UnitScreenBox.of(view, rig)
		assert_false(rect.intersects(box), "тег накриває юніта %d: %s" % [id, size])
	for n: String in ["%Chip", "%PauseButton", "%EndTurnButton"]:
		assert_false(rect.intersects((_e2e.hud().get_node(n) as Control).get_global_rect()), "%s: %s" % [n, size])
	assert_true(Rect2(Vector2.ZERO, Vector2(size)).encloses(rect), "тег у межах екрана: %s" % size)


func test_tag_shows_name_ap_and_drone_pips_of_a_squad() -> void:
	await _boot(LayoutProbe.PHONE_LARGE, [_spawn(ASSAULT, 0, SQUAD), _spawn(MEDIUM_TANK, 1, ENEMY_TANK)])
	await _tap(SQUAD)
	var tag: UnitTag = _tag()
	var u: Unit = _e2e.service.state.unit_at(SQUAD)
	assert_eq(tag.name_label.text, tr("UNIT_ASSAULT_SQUAD"))
	assert_eq(tag.ap_value.text, str(u.ap))
	assert_eq(tag.ap_max.text, "/%d" % u.max_ap())
	assert_eq(tag.pips.counts(), Vector2i(2, 2))


func test_tag_and_all_its_children_ignore_input() -> void:
	await _boot(LayoutProbe.PHONE_LARGE, [_spawn(ASSAULT, 0, SQUAD), _spawn(MEDIUM_TANK, 1, ENEMY_TANK)])
	await _tap(SQUAD)
	var tag: UnitTag = _tag()
	assert_eq(tag.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	for n in tag.find_children("*", "Control", true, false):
		assert_eq((n as Control).mouse_filter, Control.MOUSE_FILTER_IGNORE, "%s ігнорує ввід" % n.name)


## Тап по тегу лягає на клітинку під ним: тег не відкриває нічого й не глушить тап.
func test_a_tap_through_the_tag_reaches_the_board() -> void:
	await _boot(LayoutProbe.PHONE_LARGE, [_spawn(ASSAULT, 0, SQUAD), _spawn(MEDIUM_TANK, 0, TANK)])
	await _tap(SQUAD)
	var tag: UnitTag = _tag()
	var hit: Vector2 = tag.get_global_rect().get_center()
	var picked: Control = _pick(_e2e.hud(), hit)
	assert_true(picked == null or picked == _e2e.hud(), "під тегом немає вузла, що ловить ввід (знайдено %s)" % picked)


func _pick(root: Control, point: Vector2) -> Control:
	for c in root.find_children("*", "Control", true, false):
		var ctl := c as Control
		if ctl.is_visible_in_tree() and ctl.mouse_filter != Control.MOUSE_FILTER_IGNORE and ctl.get_global_rect().has_point(point):
			return ctl
	return null


func test_tag_hides_when_nothing_is_selected() -> void:
	await _boot(LayoutProbe.PHONE_LARGE, [_spawn(ASSAULT, 0, SQUAD), _spawn(MEDIUM_TANK, 1, ENEMY_TANK)])
	await _tap(SQUAD)
	assert_true(_tag().visible)
	_e2e.hud().show_selection(null)
	await _e2e.settle()
	assert_false(_tag().visible, "вибору нема — тегу нема")


## AP ворога — прихований залишок його дій: тег ворога видно, а числа ніде в ньому нема, і в прихованих Label теж.
func test_enemy_tag_is_shown_but_never_carries_its_ap() -> void:
	await _boot(LayoutProbe.PHONE_LARGE, [_spawn(ASSAULT, 0, SQUAD), _spawn(MEDIUM_TANK, 1, ENEMY_TANK)])
	var enemy: Unit = _e2e.service.state.unit_at(ENEMY_TANK)
	enemy.ap = 37
	_e2e.hud().show_selection(enemy)
	await _e2e.settle()
	assert_true(_tag().visible, "тег ворога є")
	var labels: Array = _tag().find_children("*", "Label", true, false)
	assert_gt(labels.size(), 0)
	for l: Label in labels:
		assert_ne(l.text, "37", "AP ворога у Label «%s»" % l.name)
		assert_false(l.text.contains("37"), "AP ворога у Label «%s»" % l.name)


## Плити й тег читають лише юнітів з вузлом: невидимий ворог не зсуває ні картку дій, ні тег.
func test_layout_ignores_an_unscouted_enemy() -> void:
	var with_hidden: Dictionary = await _layout_of([_spawn(ASSAULT, 0, SQUAD), _spawn(MEDIUM_TANK, 1, HIDDEN)])
	assert_null(with_hidden["hidden_view"], "ворог справді невидимий")
	var without: Dictionary = await _layout_of([_spawn(ASSAULT, 0, SQUAD)])
	assert_eq(with_hidden["cluster"], without["cluster"])
	assert_eq(with_hidden["tag"], without["tag"])
	assert_eq(with_hidden["plate"], without["plate"])


func _layout_of(spawns: Array) -> Dictionary:
	await _boot(LayoutProbe.PHONE_LARGE, spawns, false)
	await _tap(SQUAD)
	var hud: Hud = _e2e.hud()
	var plate: Control = hud._plate
	var out: Dictionary = {"cluster": hud.cluster_name(), "tag": Rect2(_tag().position, _tag().size),
		"plate": Rect2(plate.position, plate.size)}
	var hidden: Unit = _e2e.service.state.unit_at(HIDDEN)
	out["hidden_view"] = _e2e.screen.unit_view_for(hidden.id) if hidden != null else null
	return out


## Поки грають події, юніт іде, а тег стояв би на старій клітинці: він ховається і стає наново після.
func test_tag_is_held_during_playback_and_replaced_after() -> void:
	await _boot(LayoutProbe.PHONE_LARGE, [_spawn(ASSAULT, 0, SQUAD), _spawn(MEDIUM_TANK, 1, ENEMY_TANK)])
	await _tap(SQUAD)
	assert_true(_tag().visible)
	_e2e.hud().hold_tag(true)
	_e2e.hud().units_changed()
	await _e2e.settle()
	assert_false(_tag().visible, "програвання триває")
	_e2e.hud().hold_tag(false)
	_e2e.hud().units_changed()
	await _e2e.settle()
	assert_true(_tag().visible)


func test_tag_keeps_its_spot_when_the_unit_is_reselected_after_an_action() -> void:
	await _boot(LayoutProbe.PHONE_LARGE, [_spawn(ENGINEER, 0, SQUAD), _spawn(MEDIUM_TANK, 1, ENEMY_TANK)])
	await _tap(SQUAD)
	var before: Vector2 = _tag().position
	_e2e.hud().refresh()
	await _e2e.settle()
	assert_eq(_tag().position, before, "гістерезис: ті самі обставини — те саме місце")


func test_engineer_tag_avoids_its_four_target_cells() -> void:
	await _boot(LayoutProbe.PHONE_LARGE, [_spawn(ENGINEER, 0, Vector2i(4, 2)), _spawn(MEDIUM_TANK, 1, ENEMY_TANK)])
	await _tap(Vector2i(4, 2))
	var rig: IsoCameraRig = _e2e.screen.get_node("%CameraRig")
	var rect: Rect2 = Rect2(_tag().position, _tag().size)
	for d: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var poly: PackedVector2Array = UnitScreenBox.cell_poly(Vector2i(4, 2) + d, rig)
		var cell_box := Rect2(poly[0], Vector2.ZERO)
		for v in poly:
			cell_box = cell_box.expand(v)
		# Грубий bbox клітинки (ромб менший за свій bbox), тож перевіряємо найточніше: центр клітинки.
		assert_false(rect.has_point(cell_box.get_center()), "тег не лежить на центрі клітинки %s" % (Vector2i(4, 2) + d))


## Перехід, а не окремі кадри: вибір → озброєння верби. Клітинки верби — перешкода вже від вибору, тож
## озброєння тег не зрушує.
func test_engineer_tag_keeps_its_spot_when_a_verb_is_armed() -> void:
	await _boot(LayoutProbe.PHONE_LARGE, [_spawn(ENGINEER, 0, Vector2i(4, 2)), _spawn(MEDIUM_TANK, 1, ENEMY_TANK)])
	await _tap(Vector2i(4, 2))
	var before := Rect2(_tag().position, _tag().size)
	assert_true(_tag().visible)
	_e2e.engineer_panel().button_for(EngineerCommand.Action.LAY_MINE).pressed.emit()
	await _e2e.settle()
	assert_true(_tag().visible)
	assert_eq(Rect2(_tag().position, _tag().size), before, "гістерезис: озброєння верби не зсуває тег")
	# Повний перерахунок із клітинками верби — найдорожчий випадок: лідер шукає щілину між ромбами.
	var hud: Hud = _e2e.hud()
	var t0: int = Time.get_ticks_usec()
	hud._tag_has_offset = false
	hud._update_tag()
	var ms: float = (Time.get_ticks_usec() - t0) / 1000.0
	print("engineer tag full placement: %.1f ms" % ms)
	assert_lt(ms, 150.0, "повний перерахунок тега інженера (бюджет обробника подій)")


## Вибір танка → тап по ворогові (прев'ю пострілу): місце тега лишається, поки воно законне; лінія вогню його не зачіпає.
func test_tank_tag_keeps_its_spot_when_a_shot_is_previewed() -> void:
	await _boot(LayoutProbe.PHONE_LARGE, [_spawn(MEDIUM_TANK, 0, TANK), _spawn(MEDIUM_TANK, 1, ENEMY_TANK)])
	await _tap(TANK)
	var before := Rect2(_tag().position, _tag().size)
	await _tap(ENEMY_TANK)
	assert_false(_e2e.hud().get("_last_preview").is_empty(), "прев'ю пострілу показано")
	var after := Rect2(_tag().position, _tag().size)
	var scene: Dictionary = _e2e.hud()._tag_scene(_e2e.hud()._tag_view(), _tag().size)
	var legal: bool = TagPlacement.new(scene).is_legal(after, _e2e.hud().get("_tag_relax"))
	assert_true(legal, "тег стоїть на законному місці")
	assert_eq(after, before, "прев'ю не зсуває тег, поки його місце законне")


## Картка утримання на екрані — тега вибраного юніта нема; після відпускання він на тому самому місці.
func test_hold_card_hides_the_selected_tag_and_it_returns_to_the_same_spot() -> void:
	await _boot(LayoutProbe.PHONE_LARGE, [_spawn(MEDIUM_TANK, 0, TANK), _spawn(MEDIUM_TANK, 1, ENEMY_TANK)])
	await _tap(TANK)
	var before := Rect2(_tag().position, _tag().size)
	assert_true(_tag().visible)
	_e2e.long_press(ENEMY_TANK)
	await _e2e.settle()
	assert_true(_card().visible)
	assert_false(_tag().visible, "поки картка на екрані, тег прихований")
	_e2e.release(ENEMY_TANK)
	await _e2e.settle()
	assert_false(_card().visible)
	assert_true(_tag().visible)
	assert_eq(Rect2(_tag().position, _tag().size), before, "після відпускання — те саме місце")


func test_placement_is_fast_enough_for_an_event_handler() -> void:
	await _boot(LayoutProbe.PHONE_SMALL, [_spawn(ASSAULT, 0, SQUAD), _spawn(MEDIUM_TANK, 0, TANK),
		_spawn(MEDIUM_TANK, 1, ENEMY_TANK), _spawn(RIFLE, 1, ENEMY_SQUAD)])
	await _tap(SQUAD)
	var hud: Hud = _e2e.hud()
	var t0: int = Time.get_ticks_usec()
	hud._tag_has_offset = false
	hud._update_tag()
	var ms: float = (Time.get_ticks_usec() - t0) / 1000.0
	print("tag full placement: %.1f ms" % ms)
	assert_lt(ms, 150.0, "повний перерахунок тега")


# --- Картка утримання ---------------------------------------------------------------

func test_hold_card_for_an_enemy_tank_has_no_ap_and_no_drones() -> void:
	await _boot(LayoutProbe.PHONE_LARGE, [_spawn(ASSAULT, 0, SQUAD), _spawn(MEDIUM_TANK, 1, ENEMY_TANK)])
	_e2e.long_press(ENEMY_TANK)
	await _e2e.settle()
	var card: HoldCard = _card()
	var t: Dictionary = UnitTypes.get_type(MEDIUM_TANK)
	assert_true(card.visible)
	assert_eq(card.name_label.text, tr("UNIT_MEDIUM_TANK"))
	assert_eq(card.class_label.text, tr("unit_class_tank").to_upper())
	assert_eq(card.attack_value.text, str(int(t["attack"])))
	assert_eq(card.range_value.text, str(int(t["attack_range"])))
	assert_eq(card.vision_value.text, str(int(t["vision"])))
	assert_eq(card.armour_rows.map(func(l: Label) -> String: return l.text), ["37", "27", "18"])
	assert_eq(card.armour_glyph.sector(), ArmourGlyph.NO_SECTOR, "жоден сектор не світиться")
	assert_true(card.armour_table_row.visible)
	assert_false(card.armour_none_row.visible)
	assert_false(card.drones_row.visible, "у танка дронів нема")
	assert_false(card.floor_label.is_visible_in_tree(), "кільце гармати — без «щонайменше»")
	assert_eq(card.find_children("*", "Label", true, false).filter(func(l: Label) -> bool: return l.text == str(_e2e.service.state.unit_at(ENEMY_TANK).ap)), [],
		"AP ворога картка не показує")
	_e2e.release(ENEMY_TANK)
	await _e2e.settle()
	assert_false(card.visible, "палець відпущено — картки нема")


## Довга назва переноситься на два рядки, і картка підростає, а не лізе на підпис класу.
func test_hold_card_with_a_wrapping_name_does_not_cover_the_class_caption() -> void:
	await _boot(LayoutProbe.PHONE_LARGE, [_spawn(RIFLE, 0, SQUAD), _spawn(4, 1, ENEMY_TANK)])
	_e2e.long_press(ENEMY_TANK)
	await _e2e.settle()
	var card: HoldCard = _card()
	assert_true(card.visible)
	assert_eq(card.name_label.text, tr("UNIT_SCOUT_CAR"))
	assert_lte(card.name_label.get_global_rect().end.y, card.class_label.get_global_rect().position.y,
		"назва не накриває підпис класу")
	assert_gte(card.name_label.get_global_rect().position.y, card.get_global_rect().position.y, "назва в межах картки")


func test_hold_card_for_an_enemy_squad_shows_drones_and_the_floor_caption() -> void:
	await _boot(LayoutProbe.PHONE_LARGE, [_spawn(RIFLE, 0, SQUAD), _spawn(ASSAULT, 1, ENEMY_SQUAD)])
	_e2e.long_press(ENEMY_SQUAD)
	await _e2e.settle()
	var card: HoldCard = _card()
	assert_true(card.visible)
	assert_true(card.drones_row.visible)
	assert_eq(card.drone_pips.counts(), Vector2i(2, 2))
	assert_eq(card.drone_count.text, "×2")
	assert_true(card.floor_label.is_visible_in_tree(), "is_floor — підпис «щонайменше»")
	assert_eq(card.floor_label.text, tr("hud_threat_floor_drone"))
	assert_true(card.armour_none_row.visible, "піхота: «Броня немає»")
	assert_false(card.armour_table_row.visible)


func test_hold_card_keeps_the_drone_row_at_zero() -> void:
	await _boot(LayoutProbe.PHONE_LARGE, [_spawn(RIFLE, 0, SQUAD), _spawn(ASSAULT, 1, ENEMY_SQUAD)])
	_e2e.service.state.unit_at(ENEMY_SQUAD).drones_left = 0
	_e2e.long_press(ENEMY_SQUAD)
	await _e2e.settle()
	assert_true(_card().drones_row.visible, "ряд лишається й на нулі: лічильник публічний")
	assert_eq(_card().drone_count.text, "×0")
	assert_eq(_card().drone_pips.counts(), Vector2i(0, 2))
	assert_false(_card().floor_label.is_visible_in_tree(), "кільця дрона нема — підпису нема")


func test_hold_card_for_an_own_unit_and_an_engineer_dash() -> void:
	await _boot(LayoutProbe.PHONE_LARGE, [_spawn(ENGINEER, 0, SQUAD), _spawn(MEDIUM_TANK, 1, ENEMY_TANK)])
	_e2e.long_press(SQUAD)
	await _e2e.settle()
	var card: HoldCard = _card()
	assert_true(card.visible)
	assert_eq(card.attack_value.text, "—")
	assert_eq(card.range_value.text, "—")
	assert_eq(card.vision_value.text, str(int(UnitTypes.get_type(ENGINEER)["vision"])), "огляд лишає число")
	assert_false(card.floor_label.is_visible_in_tree(), "свій юніт — без «щонайменше»")


func test_no_hold_card_over_a_hidden_enemy() -> void:
	await _boot(LayoutProbe.PHONE_LARGE, [_spawn(RIFLE, 0, SQUAD), _spawn(MEDIUM_TANK, 1, HIDDEN)], false)
	assert_null(_e2e.screen.unit_view_for(_e2e.service.state.unit_at(HIDDEN).id), "приховано: вузла нема")
	_e2e.long_press(HIDDEN)
	await _e2e.settle()
	assert_false(_card().visible, "картка лише для видимого юніта")
	_e2e.release(HIDDEN)


func test_hold_card_stays_off_the_finger_and_inside_the_screen() -> void:
	await _boot(LayoutProbe.PHONE_SMALL, [_spawn(ASSAULT, 0, SQUAD), _spawn(ASSAULT, 1, ENEMY_SQUAD)])
	_e2e.long_press(ENEMY_SQUAD)
	await _e2e.settle()
	var card: HoldCard = _card()
	var press: Vector2 = _e2e.px(ENEMY_SQUAD)
	var finger := Rect2(press - Vector2(60.0, 60.0), Vector2(120.0, 120.0))
	assert_false(card.get_rect().intersects(finger), "палець не закритий карткою %s %s" % [card.get_rect(), finger])
	assert_true(Rect2(Vector2.ZERO, Vector2(LayoutProbe.PHONE_SMALL)).encloses(card.get_rect()), "картка %s" % card.get_rect())
