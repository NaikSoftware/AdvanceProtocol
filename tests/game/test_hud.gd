extends GutTest
## HUD «Field Tablet» — headless. Сцена HUD інстанціюється напряму, а перевіряється рівно те, що
## побачить гравець: текст і видимість вузлів, а не внутрішні поля скрипта.
##
## Прев'ю приходять у форматі, який ВИПУСКАЄ InputController: ключ "type" з
## InputController.ActionType. Тести з реальним контролером женуть його крізь HUD саме для того,
## щоб контракт перевірявся проти емітента, а не проти переказу контракту в цьому файлі.

const HudScene := preload("res://game/ui/hud.tscn")
const MatchServiceScript := preload("res://game/autoload/match_service.gd")
const RigScene := preload("res://game/camera/iso_camera_rig.tscn")
const UnitViewScene := preload("res://game/battle/unit_view.tscn")

## Той самий прийом, що й у tests/game/test_input_controller.gd: шпигун замість справжнього
## ZoneOverlay, бо той тягне за собою живий BoardView із MultiMesh.
class SpyZoneOverlay extends ZoneOverlay:
	func _init() -> void:
		pass

	func show_for(_unit: Unit, _zones: Pathing.Zones) -> void:
		pass

	func clear() -> void:
		pass


var hud: Hud
var _service: Node


func before_each() -> void:
	hud = HudScene.instantiate()
	add_child_autofree(hud)
	_service = MatchServiceScript.new()
	add_child_autofree(_service)


func _state(ground_state: int = Terrain.GroundState.DRY) -> BattleState:
	_service.start_match(Board.create(12, 12, ground_state), 2, 1)
	return _service.state


func _label(unique_name: String) -> Label:
	return hud.get_node("%" + unique_name) as Label


func _ctl(state: BattleState) -> InputController:
	_service.begin()
	_service.take_events()
	var controller := InputController.new(_service, SpyZoneOverlay.new())
	hud.bind(state)
	hud.attach_controller(controller)
	return controller


func _shot_preview(sector: int, dmg_min: int, dmg_max: int, extra: Dictionary = {}) -> Dictionary:
	var p: Dictionary = {
		"type": InputController.ActionType.SHOT,
		"unit_id": 1,
		"target_id": 2,
		"sector": sector,
		"min": dmg_min,
		"max": dmg_max,
	}
	p.merge(extra, true)
	return p


func _move_preview(ap_left: int) -> Dictionary:
	return {
		"type": InputController.ActionType.MOVE,
		"unit_id": 1,
		"target": Vector2i(4, 4),
		"path": [Vector2i(4, 4)] as Array[Vector2i],
		"ap_left": ap_left,
	}


# --- bind(): хід, гравець -------------------------------------------------------

func test_bind_puts_turn_number_and_player_chip_on_screen() -> void:
	var state: BattleState = _state(Terrain.GroundState.MUD)
	state.turn_number = 7
	state.active_player = 1

	hud.bind(state)

	assert_eq(_label("TurnValue").text, "7", "номер ходу читається з turn_number")
	assert_eq(_label("PlayerValue").text, "%s 2" % tr("hud_player"), "гравець — 1-based номер після слова")
	assert_eq((hud.get_node("%PlayerBar") as ColorRect).color, UnitView.PLAYER_COLORS[1],
		"смуга чипа — колір гравця з тієї ж таблиці, що й корпуси")


func test_ground_state_is_not_in_the_battle_hud() -> void:
	hud.bind(_state(Terrain.GroundState.MUD))

	assert_null(hud.get_node_or_null("%GroundStateIcon"), "стан ґрунту живе на гейті й у паузі")
	assert_null(hud.get_node_or_null("%GroundStateLabel"))


func test_set_active_player_changes_the_displayed_player() -> void:
	hud.bind(_state())
	assert_eq(_label("PlayerValue").text, "%s 1" % tr("hud_player"), "передумова: показаний гравець 0")

	hud.set_active_player(1)

	assert_eq(_label("PlayerValue").text, "%s 2" % tr("hud_player"))


func test_new_active_player_does_not_inherit_the_previous_players_selection() -> void:
	var state: BattleState = _state()
	var u: Unit = state.add_unit(1, 0, Vector2i(3, 3), 0)
	hud.bind(state)
	hud.show_selection(u)
	assert_true(hud.get_node("%DroneButton").visible, "передумова: вибір показаний")
	watch_signals(hud)

	hud.set_active_player(1)

	assert_false(hud.get_node("%DroneButton").visible, "§1.2: вибір попереднього гравця не мусить пережити передачу ходу")
	assert_signal_emitted_with_parameters(hud, "selection_tag_changed", [null, false])


# --- show_preview(): постріл -----------------------------------------------------

func test_show_preview_shot_displays_the_payload_sector_and_both_damage_bounds() -> void:
	var state: BattleState = _state()
	state.add_unit(5, 0, Vector2i(3, 3), 0)
	state.add_unit(5, 1, Vector2i(3, 2), 0)
	hud.bind(state)

	# Сектор навмисно НЕ FRONT (0): захардкоджене значення пройшло б тест із типовим значенням.
	hud.show_preview(_shot_preview(UnitTypes.ArmourSector.REAR, 37, 91))

	assert_eq(_label("PreviewSectorValue").text, tr("hud_sector_rear"))
	assert_true(_label("PreviewSectorValue").is_visible_in_tree())
	assert_true((hud.get_node("%PreviewPlate") as Control).is_visible_in_tree(), "плита-хост показана: діти під SubViewport самі цього не доводять")
	assert_eq(_label("PreviewDamageValue").text, "37–91", "обидві межі як є")
	var glyph: ArmourGlyph = (hud.get_node("%PreviewPlate") as PreviewPlate).armour_glyph
	assert_eq(glyph.sector(), UnitTypes.ArmourSector.REAR, "§3.4: на глифі горить саме той сектор, у який піде постріл")
	assert_true(glyph.visible, "ціль — техніка: корпус із бронею")
	assert_true(glyph.get_parent().is_visible_in_tree())

	# Другий сектор тим самим шляхом — доказ, що показується саме payload.
	hud.show_preview(_shot_preview(UnitTypes.ArmourSector.SIDE, 12, 20))

	assert_eq(_label("PreviewSectorValue").text, tr("hud_sector_side"))
	assert_eq(glyph.sector(), UnitTypes.ArmourSector.SIDE)
	assert_eq(_label("PreviewTargetName").text, tr(String(UnitTypes.get_type(5)["name_key"])), "ряд цілі — назва типу цілі")


func test_shot_note_and_cover_marker_follow_the_core_preview_fields() -> void:
	var state: BattleState = _state()
	state.add_unit(1, 0, Vector2i(3, 3), 0)
	state.add_unit(5, 1, Vector2i(3, 2), 0)  # id 2 — танк
	hud.bind(state)
	var note: Label = hud.get_node("%PreviewArmourNote")
	var cover: Control = hud.get_node("%PreviewCoverMarker")

	hud.show_preview(_shot_preview(UnitTypes.ArmourSector.FRONT, 10, 20, {"armour_ignored": true, "in_cover": false}))
	assert_true(note.is_visible_in_tree(), "піхота стріляє в танк: «броня не діє»")
	assert_eq(note.text, tr("hud_armour_ignored_note"))
	assert_false(cover.is_visible_in_tree(), "техніка укриття не бере")

	hud.show_preview(_shot_preview(UnitTypes.ArmourSector.FRONT, 10, 20, {"armour_ignored": false}))
	assert_false(note.is_visible_in_tree(), "броня діє — нотатки немає")

	# Ціль-піхота: силует замість корпуса, без нотатки (броні нема), маркер укриття — з поля core.
	var inf: Unit = state.add_unit(0, 1, Vector2i(8, 8), 0)
	hud.show_preview(_shot_preview(UnitTypes.ArmourSector.FRONT, 10, 20,
		{"target_id": inf.id, "armour_ignored": true, "in_cover": true}))
	var plate: PreviewPlate = hud.get_node("%PreviewPlate")
	assert_false(plate.armour_glyph.visible, "піхота без броні — глифа корпуса нема")
	assert_false(note.is_visible_in_tree(), "немає броні, яку можна ігнорувати")
	assert_true(cover.is_visible_in_tree(), "«Укриття ½» — коли core каже in_cover")
	assert_eq(_label("PreviewSectorValue").text, tr("hud_sector_front"), "сектор показується завжди (§3.4)")


func test_show_preview_move_has_no_plate_and_leaves_no_shot_fields_behind() -> void:
	var state: BattleState = _state()
	state.add_unit(5, 0, Vector2i(3, 3), 0)
	hud.bind(state)
	hud.show_preview(_shot_preview(UnitTypes.ArmourSector.REAR, 37, 91))
	assert_true(_label("PreviewSectorValue").is_visible_in_tree(), "передумова: прев'ю пострілу показане")
	assert_true((hud.get_node("%PreviewPlate") as Control).is_visible_in_tree(), "плита-хост показана: діти під SubViewport самі цього не доводять")

	hud.show_preview(_move_preview(18))

	assert_false((hud.get_node("%PreviewPlate") as Control).visible, "рух без плити: хост прихований (діти під SubViewport самі цього не доводять)")
	assert_true((hud.get_node("%ConfirmButton") as Button).visible, "ряд [Скасувати Підтвердити] лишається")
	assert_false((hud.get_node("%ConfirmButton") as Button).disabled, "плити нема, чекати запікання нічого")
	var texts: Array[String] = []
	_collect_texts(hud, texts)
	assert_false(texts.has("18"), "залишок AP числом не показується")
	assert_false(_label("PreviewSectorValue").is_visible_in_tree(), "сектор попереднього прев'ю не лишається")
	assert_false(_label("PreviewDamageValue").is_visible_in_tree())
	assert_false(hud.get_node("%PreviewTargetRow").visible, "рух не має ряду цілі")


func test_selecting_another_unit_clears_the_pending_preview() -> void:
	var state: BattleState = _state()
	var u: Unit = state.add_unit(5, 0, Vector2i(3, 3), 0)
	hud.bind(state)
	hud.show_preview(_shot_preview(UnitTypes.ArmourSector.REAR, 37, 91))

	hud.show_selection(u)

	assert_false(_label("PreviewSectorValue").is_visible_in_tree(), "прев'ю, якого вже нема, не показується")
	assert_true((hud.get_node("%ConfirmButton") as Button).disabled, "без прев'ю підтверджувати нічого")
	assert_false(hud.get_node("%ActionRow").visible)


# --- Вибраний юніт: гачок тега, дрони, AP ворога ----------------------------------

func test_selection_hook_reports_own_unit_with_ap_allowed() -> void:
	var state: BattleState = _state()
	var u: Unit = state.add_unit(5, 0, Vector2i(3, 3), 0)
	hud.bind(state)
	watch_signals(hud)

	hud.show_selection(u)
	assert_signal_emitted_with_parameters(hud, "selection_tag_changed", [u, true])

	hud.show_selection(null)
	assert_signal_emitted_with_parameters(hud, "selection_tag_changed", [null, false])


func test_drone_button_shows_pips_not_a_count_and_follows_the_unit() -> void:
	var state: BattleState = _state()
	var squad: Unit = state.add_unit(1, 0, Vector2i(3, 3), 0)  # 2 дрони
	hud.bind(state)

	hud.show_selection(squad)

	var button: DroneButton = hud.get_node("%DroneButton")
	assert_true(button.visible, "§3.9: кнопка дрона у загону з дронами")
	assert_eq(button.text, tr("hud_drone_strike"), "у тексті лише «Дрон»")
	assert_eq(button.pips(), Vector2i(2, 2))
	assert_eq(button.size, Vector2(116, 48), "тап-ціль 116 × 48, малюнок 116 × 40")

	squad.drones_left = 1
	hud.show_selection(squad)

	assert_eq(button.pips(), Vector2i(1, 2), "лічильник читається з юніта, а не константа")


func test_drone_count_is_public_and_reaches_the_tag_hook_for_an_enemy_squad() -> void:
	var state: BattleState = _state()
	state.active_player = 0
	var enemy_squad: Unit = state.add_unit(1, 1, Vector2i(8, 8), 0)
	enemy_squad.drones_left = 1
	hud.bind(state)
	watch_signals(hud)

	hud.show_selection(enemy_squad)

	assert_signal_emitted_with_parameters(hud, "selection_tag_changed", [enemy_squad, false])
	assert_eq(enemy_squad.drones_left, 1, "§3.9: тег бере залишок із самого юніта")
	assert_false(hud.get_node("%DroneButton").visible, "дрон — дія лише свого загону")


## AP не показується ніде: ні чужий (прихований залишок дій), ні свій (його показують зони руху).
func test_selection_never_shows_ap_anywhere() -> void:
	var state: BattleState = _state()
	state.active_player = 0
	var own: Unit = state.add_unit(5, 0, Vector2i(3, 3), 0)
	var enemy: Unit = state.add_unit(5, 1, Vector2i(8, 8), 0)
	own.ap = 37
	enemy.ap = 29
	hud.bind(state)
	watch_signals(hud)

	for u: Unit in [own, enemy]:
		hud.show_selection(u)
		var texts: Array[String] = []
		_collect_texts(hud, texts)
		for t in texts:
			assert_false(t.contains("37") or t.contains("29"), "«%s»: AP юніта в HUD" % t)
			assert_false(t.contains("/%d" % int(UnitTypes.get_type(5)["max_ap"])), "«%s»: знаменник AP в HUD" % t)
	assert_signal_emitted_with_parameters(hud, "selection_tag_changed", [enemy, false])


func test_unit_without_drones_has_no_drone_button() -> void:
	var state: BattleState = _state()
	var tank: Unit = state.add_unit(5, 0, Vector2i(3, 3), 0)
	hud.bind(state)

	hud.show_selection(tank)

	assert_false(hud.get_node("%DroneButton").visible, "дронів у танка не буває взагалі")


func test_engineer_panel_only_for_an_own_engineer() -> void:
	var state: BattleState = _state()
	state.active_player = 0
	var own: Unit = state.add_unit(11, 0, Vector2i(3, 3), 0)
	var foreign: Unit = state.add_unit(11, 1, Vector2i(8, 8), 0)
	hud.bind(state)

	hud.show_selection(foreign)
	assert_false(hud.get_node("%EngineerPanel").visible, "чужі верби — не дія, а їх доступність була б підказкою")

	hud.show_selection(own)
	assert_true(hud.get_node("%EngineerPanel").visible)
	assert_true((hud.get_node("%EngineerPanel") as EngineerPanel).plate().visible, "нічого не озброєно — плита верб")


# --- R29: жоден підпис не є захардкодженим рядком --------------------------------

## Оракул — сам CSV: кожен нечисловий підпис мусить бути або ключем, або перекладом ОДНІЄЇ
## зафіксованої мови. Якби брали обидві колонки, захардкоджене «Damage» співпало б з en-перекладом.
func test_no_user_facing_label_is_a_hard_coded_literal() -> void:
	var prev_locale := TranslationServer.get_locale()
	TranslationServer.set_locale("uk")

	var state: BattleState = _state(Terrain.GroundState.MUD)
	var squad: Unit = state.add_unit(1, 0, Vector2i(3, 3), 0)
	state.add_unit(5, 1, Vector2i(3, 2), 0)
	hud.bind(state)
	hud.show_selection(squad)
	hud.show_preview(_shot_preview(UnitTypes.ArmourSector.SIDE, 40, 60, {"armour_ignored": true, "in_cover": true}))

	var texts: Array[String] = []
	_collect_texts(hud, texts)

	assert_gt(texts.size(), 15, "обхід дерева мусить справді щось знайти, інакше тест порожній")
	var numeric_re := RegEx.create_from_string("^[0-9 /.%–-]+$")
	var known := _csv_keys_and_locale("uk")
	var formats: Array[RegEx] = []
	for k: String in known:
		if k.contains("%d") or k.contains("%s"):
			formats.append(RegEx.create_from_string("^" + _regex_escape(k).replace("%d", "[0-9]+").replace("%s", ".+") + "$"))
	for text in texts:
		if text.is_empty() or numeric_re.search(text) != null:
			continue
		# Підписи-заголовки набираються ВЕЛИКИМИ (тема не вміє) — звіряємо з перекладом без регістру.
		if known.has(text) or known.has(text.to_lower()) or known.has(text.capitalize()):
			continue
		if formats.any(func(r: RegEx) -> bool: return r.search(text) != null):
			continue
		var matched: bool = false
		for k: String in known:
			if k.to_upper() == text:
				matched = true
				break
		assert_true(matched, "«%s» — не число, не ключ і не uk-переклад (§9, R29)" % text)

	TranslationServer.set_locale(prev_locale)


func _regex_escape(t: String) -> String:
	var out := ""
	for c in t:
		out += "\\" + c if "\\^$.|?*+()[]{}".contains(c) else c
	return out


## Ключі CSV плюс переклади ОДНІЄЇ мови. Читається з файлу, а не з коду HUD.
func _csv_keys_and_locale(locale: String) -> Dictionary:
	var known := {}
	var f := FileAccess.open("res://assets/i18n/strings.csv", FileAccess.READ)
	assert_not_null(f, "не відкривається strings.csv — джерело локалізації зникло")
	var header := f.get_csv_line()
	var col := header.find(locale)
	assert_gt(col, 0, "у CSV немає колонки мови %s" % locale)
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() > col:
			if not row[0].is_empty():
				known[row[0]] = true
			if not row[col].is_empty():
				known[row[col]] = true
	return known


func _collect_texts(node: Node, out: Array[String]) -> void:
	for child in node.get_children():
		if child is Label:
			out.append((child as Label).text)
		elif child is Button:
			out.append((child as Button).text)
		_collect_texts(child, out)


# --- Тапабельність і бюджет ---------------------------------------------------------

func test_every_button_is_at_least_48_dp_tall() -> void:
	var buttons: Array[Button] = []
	_collect_buttons(hud, buttons)
	assert_gt(buttons.size(), 10, "кнопок мусить бути багато: пауза, кінець ходу, ряд дій, дрон, верби, смужки")
	for b in buttons:
		assert_true(b.custom_minimum_size.y >= 48.0 and b.custom_minimum_size.x >= 48.0,
			"%s менша за 48 dp — палець у неї не влучить (§9)" % b.name)


## Тап-ціль 48 dp, малюнок 40: плита кнопки ряду, «Завершити хід» і «Дрон» не займає нижніх 8 dp
## тап-цілі (вони лягають у нижнє поле екрана), а значок і підпис стоять по центру малюнка.
func test_bottom_buttons_draw_a_40_dp_plate_inside_a_48_dp_hit_area() -> void:
	for n: String in ["%EndTurnButton", "%CancelButton", "%ConfirmButton", "%DroneButton"]:
		var b: Button = hud.get_node(n)
		assert_eq(b.custom_minimum_size.y, 48.0, n)
		for st: StringName in [&"normal", &"pressed", &"disabled", &"hover"]:
			var box: StyleBox = b.get_theme_stylebox(st)
			assert_eq(box.get_expand_margin(SIDE_BOTTOM), -8.0, "%s %s: малюнок 40 dp" % [n, st])
			assert_eq(box.content_margin_bottom, 8.0, "%s %s: вміст по центру малюнка" % [n, st])
			assert_eq(box.get_expand_margin(SIDE_TOP), 0.0, "%s %s" % [n, st])


## Пауза — лише значок: жодного фону в жодному стані, зокрема у фокусі після тапу.
func test_pause_button_has_no_background_in_any_state() -> void:
	var b: Button = hud.get_node("%PauseButton")
	for st: StringName in [&"normal", &"hover", &"pressed", &"focus", &"disabled", &"hover_pressed", &"normal_mirrored"]:
		assert_true(b.get_theme_stylebox(st) is StyleBoxEmpty, "пауза без плити: %s" % st)
	assert_eq(b.size, Vector2(48, 48), "тап-ціль 48 × 48")
	var mark := b.get_meta(&"group_mark") as TextureRect
	assert_eq(mark.texture.resource_path, "res://assets/ui/icons/btn_pause.svg", "запечена тінь")
	# Самі смужки малює код по цілих пікселях: кісткова смужка в текстурі розмилася б фільтром поверх них.
	assert_false(FileAccess.get_file_as_string("res://assets/ui/icons/btn_pause.svg").contains("#fff"), "у текстурі лише тінь")
	assert_eq(mark.draw.get_connections().size(), 1, "смужки малює draw значка")
	await get_tree().process_frame
	var visual := Rect2(Vector2(0, 8), Vector2(40, 40))
	assert_eq(mark.get_rect().get_center() + (mark.get_parent() as Control).position + ((mark.get_parent() as Control).get_parent() as Control).position, visual.get_center(),
		"значок по центру малюнка 40 × 40, зсунутого від кута екрана на 8 dp")


## Смужки паузи — 2–2,5 dp × ~16 dp і лягають на цілі пікселі за обох масштабів: 2 px/dp і 1,51875
## (1496 × 672 при 243 dpi), де текстура, розтягнута фільтром, давала смужкам різну яскравість.
func test_pause_bars_snap_to_whole_device_pixels_at_both_scales() -> void:
	assert_eq(Hud.pause_bars(Vector2(1000.3, 100.7), 2.0),
		[Rect2(991, 85, 5, 32), Rect2(1005, 85, 5, 32)] as Array[Rect2], "2 px/dp: 2,5 × 16 dp")
	assert_eq(Hud.pause_bars(Vector2(700.2, 40.6), 1.51875),
		[Rect2(693, 29, 3, 24), Rect2(704, 29, 3, 24)] as Array[Rect2], "1,51875 px/dp: 3 px ≈ 2 dp, 24 px ≈ 16 dp")


## «Дрон» / "Drone": значок 16, проміжок 6 і слово лишають ≥ 7 dp до роздільника перед ромбиками, обома мовами.
func test_drone_button_label_clears_the_divider_in_both_locales() -> void:
	var state: BattleState = _state()
	var squad: Unit = state.add_unit(1, 0, Vector2i(3, 3), 0)
	hud.bind(state)
	var locale: String = TranslationServer.get_locale()
	for loc: String in ["uk", "en"]:
		TranslationServer.set_locale(loc)
		hud.show_selection(squad)
		var b: DroneButton = hud.get_node("%DroneButton")
		var box: StyleBox = b.get_theme_stylebox(&"normal")
		var text_w: float = b.get_theme_font(&"font").get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, b.get_theme_font_size(&"font_size")).x
		var word_end: float = box.content_margin_left + float(b.get_theme_constant(&"icon_max_width")) + float(b.get_theme_constant(&"h_separation")) + text_w
		var divider_x: float = DroneButton.WIDTH + b._divider.offset_left
		assert_gte(divider_x - word_end, 7.0, "%s «%s»: слово → роздільник" % [loc, b.text])
		assert_gte(box.content_margin_left, 7.0, "%s: значок → край" % loc)
	TranslationServer.set_locale(locale)


## Спільна ширина — одна стала: ряд, плита прев'ю й смужка озброєння.
func test_row_plate_and_strip_share_one_width_constant() -> void:
	assert_eq(HudDocking.CLUSTER_W, 252.0)
	assert_eq(PreviewPlate.WIDTH, HudDocking.CLUSTER_W)
	assert_eq(ArmedStrip.WIDTH, HudDocking.CLUSTER_W)
	var row: Control = hud.get_node("%ActionRow")
	assert_eq(row.size.x, HudDocking.CLUSTER_W, "ряд у сцені")
	var cancel: Control = hud.get_node("%CancelButton")
	var confirm: Control = hud.get_node("%ConfirmButton")
	assert_eq(cancel.custom_minimum_size.x + float((row as HBoxContainer).get_theme_constant(&"separation")) + confirm.custom_minimum_size.x,
		HudDocking.CLUSTER_W, "104 + 12 + 136")


func _collect_buttons(node: Node, out: Array[Button]) -> void:
	for child in node.get_children():
		if child is Button:
			out.append(child as Button)
		_collect_buttons(child, out)


func test_hud_does_no_per_frame_work() -> void:
	assert_false(hud.is_processing(), "правила й показ не живуть у _process (§9)")
	assert_false(hud.is_physics_processing())
	assert_false((hud.get_node("%EngineerPanel") as Node).is_processing())


# --- Контракт перевіряється проти справжнього емітента ------------------------------

func test_controller_drives_the_hud_and_the_confirm_button_is_the_only_way_to_act() -> void:
	var state: BattleState = _state()
	var u: Unit = state.add_unit(5, 0, Vector2i(3, 3), 0)  # medium tank, ap 48
	var controller: InputController = _ctl(state)

	controller.select_unit(u)
	controller.tap_cell(Vector2i(4, 3))
	assert_false((hud.get_node("%PreviewPlate") as Control).visible, "рух: плити нема, лише ряд дій")
	assert_true((hud.get_node("%ConfirmButton") as Button).visible, "action_preview від справжнього контролера читається HUD'ом")
	assert_false((hud.get_node("%ConfirmButton") as Button).disabled, "плити нема — підтвердження живе одразу")
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false((hud.get_node("%ConfirmButton") as Button).disabled, "є що підтверджувати")

	(hud.get_node("%CancelButton") as Button).pressed.emit()
	assert_eq(u.pos, Vector2i(3, 3), "скасування не рухає юніт")
	assert_true((hud.get_node("%ConfirmButton") as Button).disabled, "після скасування підтверджувати нічого")

	controller.tap_cell(Vector2i(4, 3))
	(hud.get_node("%ConfirmButton") as Button).pressed.emit()

	assert_eq(u.pos, Vector2i(4, 3), "кнопка підтвердження — єдиний шлях до дії")
	assert_true((hud.get_node("%ConfirmButton") as Button).disabled, "прев'ю спожите разом із дією")


func test_shot_preview_from_the_real_controller_shows_its_sector_and_bounds() -> void:
	var state: BattleState = _state()
	var u: Unit = state.add_unit(5, 0, Vector2i(3, 3), 0)
	# Ціль дивиться на північ, стрілець південніше — постріл у корму.
	var enemy: Unit = state.add_unit(5, 1, Vector2i(3, 2), 0)
	var controller: InputController = _ctl(state)
	var expected: Dictionary = FireCommand.preview(state, u.id, enemy.id)

	controller.select_unit(u)
	controller.tap_cell(enemy.pos)

	assert_eq(_label("PreviewSectorValue").text, tr(HudKit.SECTOR_KEYS[int(expected["sector"])]),
		"сектор на екрані — той, що порахував FireCommand.preview()")
	assert_eq(_label("PreviewDamageValue").text, "%d–%d" % [int(expected["min"]), int(expected["max"])])
	assert_eq(hud.get_node("%PreviewPlate").armour_glyph.sector(), int(expected["sector"]))


func test_end_turn_button_reports_the_press_and_submits_nothing_itself() -> void:
	var state: BattleState = _state()
	state.add_unit(5, 0, Vector2i(3, 3), 0)
	_service.begin()
	_service.take_events()
	hud.bind(state)
	watch_signals(hud)

	(hud.get_node("%EndTurnButton") as Button).pressed.emit()

	assert_signal_emitted(hud, "end_turn_pressed")
	assert_true(_service.take_events().is_empty(), "HUD не подає команд сам")


func test_end_turn_button_is_disabled_once_the_match_is_over() -> void:
	var state: BattleState = _state()
	state.add_unit(5, 0, Vector2i(3, 3), 0)
	_service.begin()
	_service.take_events()
	hud.bind(state)
	hud.attach_match_service(_service)
	var button := hud.get_node("%EndTurnButton") as Button
	assert_false(button.disabled, "передумова: поки матч триває, кінець ходу доступний")

	_service.submit(EndTurnCommand.create())

	assert_true(state.is_over(), "передумова: гравець 1 без юнітів — матч завершився")
	assert_true(button.disabled, "core/ цю команду вже відхиляє")


func test_events_ready_refreshes_the_tag_hook_after_a_command() -> void:
	var state: BattleState = _state()
	var u: Unit = state.add_unit(5, 0, Vector2i(3, 3), 0)
	_service.begin()
	_service.take_events()
	hud.bind(state)
	hud.attach_match_service(_service)
	hud.show_selection(u)
	var seen: Array = []
	hud.selection_tag_changed.connect(func(unit: Unit, own: bool) -> void: seen.append([unit, own]))

	_service.submit(MoveCommand.create(u.id, Vector2i(4, 3)))

	assert_eq(seen.size(), 1, "після події тег перечитується рівно раз")
	assert_eq(seen[0], [u, true], "тег отримує того самого юніта з нинішнім станом")


# --- Прев'ю ремонту, верб -----------------------------------------------------------

func _repair_preview(heal_min: int, heal_max: int, target: Vector2i = Vector2i(4, 3)) -> Dictionary:
	return {"type": InputController.ActionType.ENGINEER, "unit_id": 1, "action": EngineerCommand.Action.REPAIR_UNIT,
		"target": target, "heal_min": heal_min, "heal_max": heal_max}


func test_repair_preview_shows_target_hp_and_both_heal_bounds_verbatim() -> void:
	var state: BattleState = _state()
	var patient: Unit = state.add_unit(5, 0, Vector2i(4, 3), 0)
	patient.hp = 320
	hud.bind(state)

	hud.show_preview(_repair_preview(20, 43))

	assert_true((hud.get_node("%PreviewRepairBox") as Control).visible)
	assert_eq(_label("PreviewHealValue").text, "20–43")
	assert_eq(_label("PreviewHpValue").text, "320")
	assert_eq(_label("PreviewHpMax").text, "/%d" % int(UnitTypes.get_type(5)["max_hp"]))
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false((hud.get_node("%ConfirmButton") as Button).disabled)
	hud.show_preview(_move_preview(10))
	assert_false((hud.get_node("%PreviewRepairBox") as Control).visible, "прев'ю руху гасить ремонт")


func test_verb_preview_has_no_plate_the_button_names_the_verb() -> void:
	hud.bind(_state())
	hud.show_preview({"type": InputController.ActionType.ENGINEER, "unit_id": 1,
		"action": EngineerCommand.Action.DEMOLISH_BRIDGE, "target": Vector2i(4, 3)})

	assert_false((hud.get_node("%PreviewRepairBox") as Control).visible)
	assert_false(hud.get_node("%PreviewPlate").visible, "слово верби стоїть на кнопці, плити нема")
	assert_false(hud.get_node("%PreviewTargetRow").visible, "верби-тайли — без ряду цілі й чисел")
	assert_false((hud.get_node("%ConfirmButton") as Button).disabled, "плити нема — чекати запікання нічого")


func test_drone_preview_shows_armour_ignored_and_bounds() -> void:
	var state: BattleState = _state()
	state.add_unit(1, 0, Vector2i(3, 3), 0)
	state.add_unit(5, 1, Vector2i(3, 2), 0)
	hud.bind(state)

	hud.show_preview({"type": InputController.ActionType.DRONE, "unit_id": 1, "target_id": 2, "min": 120, "max": 180})

	assert_eq(_label("PreviewDroneDamageValue").text, "120–180")
	assert_eq(_label("PreviewDroneArmour").text, tr("hud_armour_ignored"))
	assert_true(hud.get_node("%PreviewTargetRow").visible)
	assert_false((hud.get_node("%PreviewShotBox") as Control).visible, "у дрона сектора нема")


## Озброєння верби скидає pending у контролері; прев'ю руху (і Confirm) не мусить пережити це.
func test_arming_a_verb_over_a_pending_move_clears_the_hud_preview() -> void:
	var state: BattleState = _state()
	var eng: Unit = state.add_unit(11, 0, Vector2i(3, 3), 0)
	state.add_unit(5, 1, Vector2i(9, 9), 0)
	var controller: InputController = _ctl(state)
	controller.select_unit(eng)
	controller.tap_cell(Vector2i(3, 5))
	assert_false((hud.get_node("%ConfirmButton") as Button).disabled, "передумова: прев'ю руху")
	controller.arm_engineer(EngineerCommand.Action.LAY_MINE)
	assert_true((hud.get_node("%ConfirmButton") as Button).disabled)


# --- «Скасувати»: рівно одне, і там, де воно щось робить -----------------------------

func test_exactly_one_cancel_per_state() -> void:
	var state: BattleState = _state()
	var u: Unit = state.add_unit(5, 0, Vector2i(3, 3), 0)
	var eng: Unit = state.add_unit(11, 0, Vector2i(6, 6), 0)
	var friend: Unit = state.add_unit(5, 0, Vector2i(6, 7), 0)
	friend.hp = 100
	var sq: Unit = state.add_unit(1, 0, Vector2i(9, 3), 0)
	state.add_unit(5, 1, Vector2i(9, 9), 0)
	var controller: InputController = _ctl(state)
	var row: Control = hud.get_node("%ActionRow")
	var strip: Control = (hud.get_node("%EngineerPanel") as EngineerPanel).strip()
	var drone_strip: Control = hud.get_node("%DroneStrip")
	var cancel: Button = hud.get_node("%CancelButton")

	assert_false(row.visible, "нічого не вибрано")

	controller.select_unit(u)
	assert_false(row.visible, "лише вибір (own_tank)")
	assert_false(strip.visible or drone_strip.visible)

	controller.tap_cell(Vector2i(4, 3))
	assert_true(row.visible and cancel.visible, "прев'ю руху — «Скасувати» ряду")
	assert_false(strip.visible or drone_strip.visible, "смужки немає — «Скасувати» одне")
	cancel.pressed.emit()
	assert_false(row.visible, "скасовано")

	controller.select_unit(eng)
	assert_false(row.visible, "інженер (плита верб) — без «Скасувати»")
	assert_true((hud.get_node("%EngineerPanel") as EngineerPanel).plate().visible)
	controller.arm_engineer(EngineerCommand.Action.REPAIR_UNIT)
	assert_true(strip.visible, "верба озброєна — смужка зі своїм «Скасувати»")
	assert_false(row.visible, "ряд не дублює «Скасувати»")
	controller.tap_cell(friend.pos)
	assert_true(row.visible and cancel.visible, "engineer_pending: ряд з прев'ю")
	assert_false(hud.get_node("%EngineerPanel").visible, "смужку замінив ряд")
	cancel.pressed.emit()
	assert_false(row.visible)
	assert_true((hud.get_node("%EngineerPanel") as EngineerPanel).plate().visible,
		"скасування повертає до плити верб")

	controller.select_unit(sq)
	assert_true(hud.get_node("%DroneButton").visible, "squad: кнопка «Дрон», без «Скасувати»")
	assert_false(row.visible)
	controller.arm_drone()
	assert_true(drone_strip.visible, "дрон озброєно — смужка")
	assert_false(hud.get_node("%DroneButton").visible)
	assert_false(row.visible)
	controller.select_unit(null)
	assert_false(row.visible or drone_strip.visible, "вибір знято")


## Смужка озброєння: «Скасувати» стоїть на місці «Скасувати» ряду й НЕ накривається «Підтвердити»,
## що з'являється після одного тапу по цілі — інакше другий тап «передумав» підтверджував би дію.
func test_armed_strip_cancel_sits_on_the_row_cancel_slot_and_clear_of_confirm() -> void:
	var state: BattleState = _state()
	var eng: Unit = state.add_unit(11, 0, Vector2i(6, 6), 0)
	var friend: Unit = state.add_unit(5, 0, Vector2i(6, 7), 0)
	friend.hp = 100
	state.add_unit(5, 1, Vector2i(9, 9), 0)
	var controller: InputController = _ctl(state)
	controller.select_unit(eng)
	controller.arm_engineer(EngineerCommand.Action.REPAIR_UNIT)
	var strip: ArmedStrip = (hud.get_node("%EngineerPanel") as EngineerPanel).strip()
	await get_tree().process_frame
	var strip_cancel: Rect2 = strip.cancel_button.get_global_rect()
	var cell: Rect2 = strip.armed_cell.get_global_rect()

	controller.tap_cell(friend.pos)
	await get_tree().process_frame
	var row_cancel: Rect2 = (hud.get_node("%CancelButton") as Control).get_global_rect()
	var confirm: Rect2 = (hud.get_node("%ConfirmButton") as Control).get_global_rect()

	assert_eq(strip_cancel, row_cancel, "«Скасувати» смужки — на прямокутнику «Скасувати» ряду")
	assert_eq(cell, confirm, "клітинка «озброєно» — на прямокутнику основної кнопки")
	assert_eq(cell.position.x - strip_cancel.end.x, confirm.position.x - row_cancel.end.x, "той самий проміжок, що в ряду")
	assert_eq((hud.get_node("%ActionRow") as HBoxContainer).get_theme_constant(&"separation"), int(HudDocking.ROW_GAP), "ряд бере проміжок зі сталої")
	assert_false(strip_cancel.intersects(confirm), "«Скасувати» смужки не під «Підтвердити», що її замінює")
	assert_true(strip.armed_cell.mouse_filter == Control.MOUSE_FILTER_STOP, "клітинка «озброєно» поглинає тап")


# --- Стикування -----------------------------------------------------------------------

const SCREEN := Vector2(985, 442)


func test_docking_takes_a_when_nothing_is_in_the_way() -> void:
	var pick: Dictionary = HudDocking.choose_cluster(SCREEN, 100.0, [] as Array[Rect2], [] as Array[Rect2])
	var rects: Array[Rect2] = pick["rects"]
	assert_eq(pick["name"], "a")
	assert_true(pick["clear"])
	assert_eq(rects[1], Rect2(709, 390, 252, 48), "ряд: право 24; малюнок 40 над нижнім полем 12, тап-ціль заходить у поле на 8")
	assert_eq(rects[0], Rect2(709, 282, 252, 100), "плита над рядом з проміжком 8")


func test_docking_falls_to_a4_when_the_target_ends_between_four_and_eight_dp_from_the_plate() -> void:
	var targets: Array[Rect2] = [Rect2(600, 300, 103.0, 40)]  # правий край 703, плита з 709: проміжок 6
	var pick: Dictionary = HudDocking.choose_cluster(SCREEN, 100.0, [] as Array[Rect2], targets)
	assert_eq(pick["name"], "a4")


func test_docking_moves_the_plate_up_when_a_unit_would_be_covered() -> void:
	var units: Array[Rect2] = [Rect2(700, 300, 40, 100)]  # накриває і плиту a, і ряд унизу
	var pick: Dictionary = HudDocking.choose_cluster(SCREEN, 100.0, units, [] as Array[Rect2])
	var rects: Array[Rect2] = pick["rects"]
	assert_eq(pick["name"], "c", "b лишає ряд унизу, де той самий юніт; c кладе обох угору")
	assert_eq(rects[0].position, Vector2(709, 56), "під тап-ціллю паузи (вона закінчується на 48) з проміжком 8")
	assert_eq(rects[1].position, Vector2(709, 164), "ряд на 8 під плитою")


func test_docking_picks_b_when_only_the_plate_area_is_busy() -> void:
	var units: Array[Rect2] = [Rect2(700, 290, 40, 30)]  # у плиті a, не в ряду
	var pick: Dictionary = HudDocking.choose_cluster(SCREEN, 100.0, units, [] as Array[Rect2])
	assert_eq(pick["name"], "b", "ряд лишається внизу праворуч, плита — під паузу")


func test_docking_goes_top_left_when_the_right_side_is_covered() -> void:
	var units: Array[Rect2] = [Rect2(700, 80, 40, 30), Rect2(700, 300, 40, 30), Rect2(700, 400, 40, 20)]
	var pick: Dictionary = HudDocking.choose_cluster(SCREEN, 100.0, units, [] as Array[Rect2])
	var rects: Array[Rect2] = pick["rects"]
	assert_eq(pick["name"], "d")
	assert_eq(rects[0].position, Vector2(24, 52), "під чипом (він закінчується на 44) з проміжком 8")


func test_docking_with_nothing_clear_takes_the_least_overlap_then_order() -> void:
	var units: Array[Rect2] = [Rect2(20, 50, 280, 200), Rect2(600, 50, 380, 390)]
	var pick: Dictionary = HudDocking.choose_cluster(SCREEN, 100.0, units, [] as Array[Rect2])
	assert_false(pick["clear"], "жоден варіант не вільний")
	var best: float = INF
	var options: Dictionary = HudDocking.cluster_rects(SCREEN, 100.0)
	for n: String in HudDocking.CLUSTER_ORDER:
		best = minf(best, HudDocking._overlap(options[n], units, HudDocking.UNIT_MARGIN))
	assert_eq(HudDocking._overlap(pick["rects"], units, HudDocking.UNIT_MARGIN), best, "найменше перекриття юнітів")


func test_verb_plate_goes_bottom_left_of_end_turn_when_bottom_right_is_busy() -> void:
	var size := Vector2(269, 148)
	var free: Dictionary = HudDocking.choose_verb_plate(SCREEN, size, [] as Array[Rect2], [] as Array[Rect2])
	assert_eq(free["name"], "br")
	var targets: Array[Rect2] = [Rect2(800, 250, 60, 60)]
	var pick: Dictionary = HudDocking.choose_verb_plate(SCREEN, size, [] as Array[Rect2], targets)
	var rects: Array[Rect2] = pick["rects"]
	assert_eq(pick["name"], "bl")
	assert_eq(rects[0].position.x, 24.0 + 136.0 + 16.0, "праворуч від «Завершити хід» з проміжком 16")


## «Закласти міну» не має кроку підтвердження. Коли плита верб не може стати осторонь
## інженера й сусідніх клітинок, вона лежить над дошкою, і другий тап подвійного торкання
## влучив би в клітинку — тоді контролер мусить ковтати тапи по дошці одразу після озброєння.
func test_verb_plate_over_the_engineer_arms_the_tap_guard_and_a_clear_plate_drops_it() -> void:
	var state: BattleState = _state()
	state.active_player = 0
	var eng: Unit = state.add_unit(11, 0, Vector2i(4, 8), 0)
	var controller: InputController = _ctl(state)
	var rig: IsoCameraRig = _rig_for(Vector2i(6, 6))
	hud.attach_camera(rig)
	hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hud.size = Vector2(1280, 720)
	controller.select_unit(eng)
	var plate: Vector2 = (hud.get_node("%EngineerPanel") as EngineerPanel).active_size()
	var cell: Rect2 = UnitScreenBox.cell_rect(eng.pos, rig)
	assert_eq(controller.tap_guard_ms, 0, "плита праворуч унизу вільна — запобіжник не потрібен")

	# Ширина, за якої обидва місця плити (праворуч унизу й ліворуч від «Завершити хід»)
	# збігаються, а висота ставить їх просто на клітинку інженера.
	var left_x: float = HudDocking.SAFE_X + HudDocking.END_TURN_W + 16.0
	hud.size = Vector2(left_x + plate.x + HudDocking.SAFE_X, cell.get_center().y + HudDocking.SAFE_BOTTOM + plate.y * 0.5)
	assert_true(cell.position.x < left_x + plate.x and cell.end.x > left_x, "передумова: інженер під плитою")
	assert_eq(controller.tap_guard_ms, Hud.ENGINEER_TAP_GUARD_MS, "плита над інженером — тапи по дошці під запобіжником")

	hud.size = Vector2(1280, 720)
	assert_eq(controller.tap_guard_ms, 0, "плита знову вільна — запобіжник знято")


func test_strip_docks_bottom_right_then_top_right_then_top_left() -> void:
	var size := Vector2(ArmedStrip.WIDTH, ArmedStrip.HEIGHT)
	var none: Array[Rect2] = []
	var br: Dictionary = HudDocking.choose_strip(SCREEN, size, none, none)
	assert_eq(br["name"], "br")
	assert_eq((br["rects"] as Array)[0], Rect2(709, 390, 252, 48), "на місці ряду дій")
	var busy_bottom: Array[Rect2] = [Rect2(700, 390, 40, 30)]
	assert_eq(HudDocking.choose_strip(SCREEN, size, none, busy_bottom)["name"], "tr")
	var busy_both: Array[Rect2] = [Rect2(700, 390, 40, 30), Rect2(700, 64, 40, 30)]
	assert_eq(HudDocking.choose_strip(SCREEN, size, none, busy_both)["name"], "tl")


func _rig_for(cell: Vector2i) -> IsoCameraRig:
	var rig: IsoCameraRig = RigScene.instantiate()
	add_child_autofree(rig)
	rig.set_bounds(Vector2i(12, 12))
	rig.center_on(cell)
	return rig


## Реальна проєкція: клітинка призначення руху (з рига) не накривається плитою кластера.
func test_move_preview_cluster_keeps_the_destination_clear_with_a_real_camera() -> void:
	var state: BattleState = _state()
	var u: Unit = state.add_unit(5, 0, Vector2i(6, 6), 0)
	var rig: IsoCameraRig = _rig_for(Vector2i(6, 6))
	hud.bind(state)
	hud.attach_camera(rig)
	var destination := Vector2i(10, 10)  # проєктується в правий нижній бік — туди, де варіант a

	hud.show_preview({"type": InputController.ActionType.MOVE, "unit_id": u.id, "target": destination,
		"path": [destination] as Array[Vector2i], "ap_left": 10})

	var cell: Rect2 = UnitScreenBox.cell_rect(destination, rig).grow(HudDocking.TARGET_GROW)
	var plate := Rect2((hud.get_node("%PreviewPlate") as Control).position, (hud.get_node("%PreviewPlate") as Control).size)
	var row := Rect2((hud.get_node("%ActionRow") as Control).position, (hud.get_node("%ActionRow") as Control).size)
	assert_false(cell.intersects(plate), "плита (варіант %s) не накриває ціль" % hud.cluster_name())
	assert_false(cell.intersects(row))


func test_bridge_cell_poly_sits_at_deck_height_not_on_the_river_bed() -> void:
	var b := Board.create(14, 14, Terrain.GroundState.DRY)
	for x in 14:
		b.set_kind(Vector2i(x, 7), Terrain.Kind.WATER)
		b.set_kind(Vector2i(x, 8), Terrain.Kind.WATER)
	b.set_kind(Vector2i(11, 7), Terrain.Kind.BRIDGE)
	b.set_kind(Vector2i(11, 8), Terrain.Kind.BRIDGE)
	b.set_kind(Vector2i(11, 6), Terrain.Kind.ROAD)
	b.set_kind(Vector2i(11, 9), Terrain.Kind.ROAD)
	var previous: TerrainHeight = TerrainHeight.active
	var t := TerrainHeight.bake(b, 0, 1)
	TerrainHeight.active = t
	var rig: IsoCameraRig = _rig_for(Vector2i(11, 7))
	assert_eq(UnitScreenBox.cell_poly(Vector2i(11, 7), rig)[0], rig.unproject(Vector3(10.5, t.deck_y(Vector2i(11, 7)), 6.5)), "куток мосту — на настилі")
	assert_ne(UnitScreenBox.cell_poly(Vector2i(11, 7), rig)[0], rig.unproject(Vector3(10.5, TerrainHeight.ground_y(10.5, 6.5), 6.5)))
	TerrainHeight.active = previous


func test_unit_screen_box_contains_the_projected_unit_and_its_hp_bar() -> void:
	var state: BattleState = _state()
	var u: Unit = state.add_unit(5, 0, Vector2i(6, 6), 0)
	var rig: IsoCameraRig = _rig_for(Vector2i(6, 6))
	var view: UnitView = UnitViewScene.instantiate()
	add_child_autofree(view)
	view.bind(u)
	view.global_position = IsoCameraRig.cell_to_world(u.pos)

	var box: Rect2 = UnitScreenBox.of(view, rig)

	assert_gt(box.size.x, 0.0, "модель має ненульовий екранний прямокутник")
	assert_true(box.has_point(rig.unproject(IsoCameraRig.cell_to_world(u.pos) + Vector3(0, 0.3, 0))),
		"центр юніта лежить усередині його екранного прямокутника")
	var bar: Node3D = view.get_node("HpBar")
	assert_true(box.has_point(rig.unproject(bar.global_position)), "смуга HP — частина прямокутника юніта")


## Смуга HP — білборд: її екранна ширина не залежить від повороту юніта й дорівнює 48 px × 0,02
## світової одиниці вздовж осі камери (а не вужчому спроєктованому квадові).
func test_billboard_parts_have_the_same_screen_rect_at_any_unit_yaw() -> void:
	var state: BattleState = _state()
	var u: Unit = state.add_unit(5, 0, Vector2i(6, 6), 0)
	var rig: IsoCameraRig = _rig_for(Vector2i(6, 6))
	var view: UnitView = UnitViewScene.instantiate()
	add_child_autofree(view)
	view.bind(u)
	view.global_position = IsoCameraRig.cell_to_world(u.pos)
	var bar: Sprite3D = view.get_node("HpBar")
	var camera: Camera3D = rig.get_node("Yaw/Camera3D")

	var first: Rect2 = UnitScreenBox.part_rect(bar, rig)
	view.rotation.y = 1.0
	var second: Rect2 = UnitScreenBox.part_rect(bar, rig)

	assert_eq(second, first, "поворот юніта не міняє екранний прямокутник білборда")
	var half: Vector3 = camera.global_transform.basis.x.normalized() * 0.48
	var centre: Vector3 = bar.global_position
	var left_x: float = rig.unproject(centre - half).x
	var right_x: float = rig.unproject(centre + half).x
	assert_almost_eq(first.position.x, minf(left_x, right_x), 0.01, "ліва межа — центр мінус пів ширини смуги")
	assert_almost_eq(first.size.x, absf(right_x - left_x), 0.01, "ширина — 48 px × 0,02 вздовж осі камери")


# --- Тост -------------------------------------------------------------------------------

func test_toast_shows_the_err_text_for_two_seconds_and_fades_in_150_ms() -> void:
	hud.bind(_state())
	hud.show_toast("ERR_OUT_OF_RANGE")

	var toast: Control = hud.get_node("%Toast")
	assert_true(toast.visible)
	assert_eq(_label("ToastLabel").text, tr("ERR_OUT_OF_RANGE"))
	var tween: Tween = hud.toast_tween()

	tween.custom_step(1.8)
	assert_true(toast.visible, "ще тримається")
	assert_eq(toast.modulate.a, 1.0)
	tween.custom_step(0.125)
	assert_almost_eq(toast.modulate.a, 0.5, 0.001, "середина 150-мс зникання")
	tween.custom_step(0.1)
	assert_false(toast.visible, "через 2,0 с тост пішов")


func test_toast_is_dropped_when_the_selection_changes() -> void:
	hud.bind(_state())
	hud.show_toast("ERR_NOT_ADJACENT")
	hud.show_selection(null)
	assert_false((hud.get_node("%Toast") as Control).visible, "відмова одного юніта не висить над іншим")


func test_toast_sits_8_dp_above_the_button_that_was_refused() -> void:
	var state: BattleState = _state()
	var squad: Unit = state.add_unit(1, 0, Vector2i(3, 3), 0)
	hud.bind(state)
	hud.show_selection(squad)
	var button: Control = hud.get_node("%DroneButton")

	hud.show_toast("ERR_DRONE_CANNOT_TARGET_INFANTRY")

	var toast: Control = hud.get_node("%Toast")
	assert_eq(toast.position.y + toast.size.y + 8.0, button.position.y, "на 8 dp над кнопкою")
	assert_eq(toast.position.x + toast.size.x, button.position.x + button.size.x, "по правому краю")


func test_toast_takes_the_bottom_right_slot_when_nothing_is_there() -> void:
	hud.bind(_state())
	hud.show_toast("ERR_OUT_OF_RANGE")

	var toast: Control = hud.get_node("%Toast")
	assert_eq(toast.position.y + toast.size.y, hud.size.y - 12.0)
	assert_eq(toast.position.x + toast.size.x, hud.size.x - 24.0)


func test_a_controller_refusal_becomes_a_toast() -> void:
	var state: BattleState = _state()
	var sq: Unit = state.add_unit(1, 0, Vector2i(3, 3), 0)
	state.add_unit(5, 1, Vector2i(9, 9), 0)
	var controller: InputController = _ctl(state)
	controller.select_unit(sq)
	sq.drones_left = 0

	controller.arm_drone()

	assert_true(hud.get_node("%Toast").visible, "відмова дрона — тост, а не окремий рядок")


## Картка, що накрила плиту дій, ховає її на час натиску; після відпускання плита знову видима й
## не прозора — інакше невидимий, але живий «Підтвердити» лишився б на екрані.
func test_releasing_the_hold_restores_a_covered_row_to_full_alpha() -> void:
	var state: BattleState = _state()
	var u: Unit = state.add_unit(5, 0, Vector2i(6, 6), 0)
	var rig: IsoCameraRig = _rig_for(Vector2i(6, 6))
	var view: UnitView = UnitViewScene.instantiate()
	add_child_autofree(view)
	view.bind(u)
	view.global_position = IsoCameraRig.cell_to_world(u.pos)
	hud.bind(state)
	hud.attach_camera(rig)
	hud.attach_unit_views(func() -> Dictionary: return {u.id: view})
	var row := hud.get_node("%ActionRow") as Control
	hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hud.size = SCREEN
	row.visible = true
	row.position = Vector2(709.0, 390.0)
	row.size = Vector2(252.0, 48.0)
	# Картка на пів екрана гарантовано перетинає ряд, де б той не стояв.
	hud.hold_card().custom_minimum_size = Vector2(900.0, 400.0)
	hud._on_inspected({"unit_id": u.id, "center": u.pos, "radius": 0, "drone_radius": 0, "marked": [], "drone_marked": [], "is_floor": false})
	assert_eq(row.modulate.a, 0.0, "під карткою ряд схований")
	assert_eq(row.process_mode, Node.PROCESS_MODE_DISABLED, "схований ряд не ловить дотик")

	hud._on_inspected({})

	assert_true(row.visible)
	assert_eq(row.modulate.a, 1.0, "після відпускання ряд знову непрозорий")
	assert_eq(row.process_mode, Node.PROCESS_MODE_INHERIT)




# --- Підпис міни -------------------------------------------------------------

func _mine_tag() -> UnitTag:
	return hud._mine_tag


func _tag_rect(t: Control) -> Rect2:
	return Rect2(t.position, t.size)


## HUD з камерою на (6, 6) і видимим UnitView юніта; розмір HUD — вікно камери, бо тайли
## проєктуються в нього.
func _hud_with_view(state: BattleState, u: Unit) -> IsoCameraRig:
	var rig: IsoCameraRig = _rig_for(Vector2i(6, 6))
	var view: UnitView = UnitViewScene.instantiate()
	add_child_autofree(view)
	view.bind(u)
	view.global_position = IsoCameraRig.cell_to_world(u.pos)
	hud.bind(state)
	hud.attach_camera(rig)
	hud.attach_unit_views(func() -> Dictionary: return {u.id: view})
	hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hud.size = rig.get_viewport().get_visible_rect().size
	return rig


func test_mine_caption_is_a_tag_naming_whose_mine_it_is_in_the_owner_colour() -> void:
	var state: BattleState = _state()
	hud.bind(state)
	hud._on_mine_caption(0, Vector2i(4, 4))
	assert_true(_mine_tag().visible)
	assert_eq(_mine_tag().name_label.text, tr("mine_own"))
	assert_eq(_mine_tag().name_label.get_theme_color("font_color"), UnitView.hp_fill_color(0))
	hud._on_mine_caption(1, Vector2i(5, 5))
	assert_true(_mine_tag().visible)
	assert_eq(_mine_tag().name_label.text, tr("mine_enemy"))
	assert_eq(_mine_tag().name_label.get_theme_color("font_color"), UnitView.hp_fill_color(1))
	assert_false(_mine_tag().pips.is_visible_in_tree(), "у міни нема дронів")
	hud._on_mine_caption(-1, Vector2i(5, 5))
	assert_false(_mine_tag().visible, "наступний тап знімає підпис")


func test_mine_caption_stands_near_its_tile_clear_of_chrome_and_follows_the_camera() -> void:
	var state: BattleState = _state()
	hud.bind(state)
	var rig: IsoCameraRig = _rig_for(Vector2i(6, 6))
	hud.attach_camera(rig)
	hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hud.size = rig.get_viewport().get_visible_rect().size
	var cell := Vector2i(6, 6)
	hud._on_mine_caption(0, cell)
	var tag: UnitTag = _mine_tag()
	assert_true(tag.visible)
	var box: Rect2 = UnitScreenBox.cell_rect(cell, rig)
	assert_true(Rect2(Vector2.ZERO, hud.size).encloses(_tag_rect(tag)), "підпис у межах екрана")
	assert_false(_tag_rect(tag).intersects(box), "підпис не накриває тайл міни")
	for c: Rect2 in hud._chrome_rects():
		assert_false(_tag_rect(tag).intersects(c), "підпис не накриває хром")
	var before: Vector2 = tag.position
	var box_before: Vector2 = box.position
	rig.center_on(Vector2i(8, 6))
	hud._on_view_changed()
	var moved: Vector2 = UnitScreenBox.cell_rect(cell, rig).position - box_before
	assert_ne(moved, Vector2.ZERO, "камера справді зсунула тайл")
	assert_eq(tag.position, before + moved.round())


func test_a_new_selection_clears_the_mine_caption() -> void:
	var state: BattleState = _state()
	var u: Unit = state.add_unit(5, 0, Vector2i(3, 3), 0)
	hud.bind(state)
	hud._on_mine_caption(0, Vector2i(4, 4))
	assert_true(_mine_tag().visible)
	hud.show_selection(u)
	assert_false(_mine_tag().visible, "новий вибір знімає підпис міни")
	hud._on_mine_caption(0, Vector2i(4, 4))
	assert_true(_mine_tag().visible)
	hud.show_selection(null)
	assert_false(_mine_tag().visible)


func test_mine_caption_does_not_survive_the_handover() -> void:
	var state: BattleState = _state()
	hud.bind(state)
	hud._on_mine_caption(0, Vector2i(4, 4))
	assert_true(_mine_tag().visible)
	hud.set_active_player(1)
	assert_false(_mine_tag().visible, "підпис своєї міни не лишається наступному гравцеві")


## Контракт проти справжнього контролера: відома міна дає підпис, нерозкрита ворожа — ні.
func test_a_real_tap_captions_a_known_mine_and_an_unknown_enemy_mine_gives_nothing() -> void:
	var state: BattleState = _state()
	state.add_unit(5, 0, Vector2i(2, 2), 0)
	var controller: InputController = _ctl(state)
	Mines.place(state, Vector2i(8, 8), 0)
	Mines.place(state, Vector2i(9, 9), 1)
	Mines.place(state, Vector2i(10, 10), 1)
	state.mines[2].known_to[0] = true
	controller.tap_cell(Vector2i(8, 8))
	assert_true(_mine_tag().visible)
	assert_eq(_mine_tag().name_label.text, tr("mine_own"))
	controller.tap_cell(Vector2i(9, 9))
	assert_false(_mine_tag().visible, "нерозкрита ворожа міна — як порожня земля")
	controller.tap_cell(Vector2i(10, 10))
	assert_true(_mine_tag().visible)
	assert_eq(_mine_tag().name_label.text, tr("mine_enemy"))
	controller.tap_cell(Vector2i(11, 11))
	assert_false(_mine_tag().visible)


## Юніт вибрано, тап за зоною: контролер подає поворот на місці, події перемальовують вибір, —
## підпис мусить пережити і це, і кілька кадрів.
func test_caption_survives_a_tap_with_a_unit_selected() -> void:
	var state: BattleState = _state()
	var u: Unit = state.add_unit(5, 0, Vector2i(2, 2), 0)
	var controller: InputController = _ctl(state)
	hud.attach_match_service(_service)
	Mines.place(state, Vector2i(10, 2), 0)
	controller.select_unit(u)
	controller.tap_cell(Vector2i(10, 2))
	await wait_frames(3)
	assert_eq(u.facing, 2, "тап справді повернув юніта на схід")
	assert_true(_mine_tag().visible)
	assert_eq(_mine_tag().name_label.text, tr("mine_own"))


func test_the_hold_card_hides_the_mine_caption_and_releasing_brings_it_back() -> void:
	var state: BattleState = _state()
	var u: Unit = state.add_unit(5, 0, Vector2i(6, 6), 0)
	_hud_with_view(state, u)
	var cell := Vector2i(9, 6)
	hud._on_mine_caption(0, cell)
	assert_true(_mine_tag().visible, "передумова: підпис на екрані")
	hud._on_inspected({"unit_id": u.id, "center": u.pos, "radius": 0, "drone_radius": 0, "marked": [], "drone_marked": [], "is_floor": false})
	assert_true(hud.hold_card().visible)
	assert_false(_mine_tag().visible, "під карткою утримання підпис схований")
	hud._on_inspected({})
	assert_false(hud.hold_card().visible)
	assert_true(_mine_tag().visible, "після відпускання підпис повертається")


## Місця для підпису нема (екран закрито плитою): картка й відпускання його не повертають.
func test_a_caption_with_no_spot_stays_hidden_after_the_hold_is_released() -> void:
	var state: BattleState = _state()
	var u: Unit = state.add_unit(5, 0, Vector2i(6, 6), 0)
	_hud_with_view(state, u)
	var row := hud.get_node("%ActionRow") as Control
	row.visible = true
	row.size = hud.size
	row.position = Vector2.ZERO
	hud._on_mine_caption(0, Vector2i(9, 6))
	assert_false(_mine_tag().visible, "передумова: законного місця нема")
	hud._on_inspected({"unit_id": u.id, "center": u.pos, "radius": 0, "drone_radius": 0, "marked": [], "drone_marked": [], "is_floor": false})
	hud._on_inspected({})
	assert_false(_mine_tag().visible, "після відпускання підпис не з'являється на застарілому місці")


## Підпис тримає зсув від тайла: повторна розкладка без змін лишає його на місці.
func test_the_mine_caption_keeps_its_spot_on_a_relayout() -> void:
	var state: BattleState = _state()
	var u: Unit = state.add_unit(5, 0, Vector2i(6, 6), 0)
	_hud_with_view(state, u)
	hud._on_mine_caption(0, Vector2i(9, 6))
	assert_true(hud._mine_has_offset)
	var spot: Vector2 = _mine_tag().position
	hud._place_mine_tag()
	assert_eq(_mine_tag().position, spot)


func test_arming_a_drone_or_a_verb_takes_the_caption_down() -> void:
	var state: BattleState = _state()
	var sq: Unit = state.add_unit(1, 0, Vector2i(3, 3), 0)
	var eng: Unit = state.add_unit(11, 0, Vector2i(5, 8), 0)
	state.add_unit(5, 1, Vector2i(6, 3), 0)
	var controller: InputController = _ctl(state)
	Mines.place(state, Vector2i(9, 9), 0)
	controller.select_unit(sq)
	controller.tap_cell(Vector2i(9, 9))
	assert_true(_mine_tag().visible, "передумова: підпис на екрані")
	controller.arm_drone()
	assert_false(_mine_tag().visible, "озброєний дрон знімає підпис")
	controller.select_unit(eng)
	controller.tap_cell(Vector2i(9, 9))
	assert_true(_mine_tag().visible, "передумова: підпис на екрані")
	controller.arm_engineer(EngineerCommand.Action.LAY_MINE)
	assert_false(_mine_tag().visible, "озброєна верба знімає підпис")


## Тег вибраного юніта й підпис міни стоять разом і не накладаються; другий обходить перший.
func test_a_selected_units_tag_and_a_mine_caption_never_overlap() -> void:
	var state: BattleState = _state()
	var u: Unit = state.add_unit(5, 0, Vector2i(6, 6), 0)
	_hud_with_view(state, u)
	hud.show_selection(u)
	await wait_frames(3)
	var unit_tag: UnitTag = hud.unit_tag()
	assert_true(unit_tag.visible, "передумова: тег юніта на екрані")
	for cell: Vector2i in [Vector2i(6, 5), Vector2i(7, 6), Vector2i(5, 6), Vector2i(6, 7)]:
		hud._on_mine_caption(0, cell)
		await wait_frames(3)
		# Підпис — хром для тега юніта: без цього правила тег міг би накрити його.
		var chrome: Array = hud._tag_scene(hud._tag_view(), unit_tag.size)["chrome"]
		assert_true(chrome.has(_tag_rect(_mine_tag())), "підпис у хромі тега юніта біля %s" % cell)
		assert_true(_mine_tag().visible, "підпис на %s є" % cell)
		assert_true(unit_tag.visible, "тег юніта на місці")
		assert_false(_tag_rect(unit_tag).intersects(_tag_rect(_mine_tag())), "теги не накладаються біля %s" % cell)


## Тайл біля краю екрана: підпис не лягає ні на «Завершити хід», ні на «Підтвердити» (він у ряді дій).
## Кожну плиту по черзі ставимо саме туди, де підпис щойно стояв: другий підпис мусить піти геть.
func test_a_caption_near_the_screen_edge_keeps_off_end_turn_and_confirm() -> void:
	var state: BattleState = _state()
	var u: Unit = state.add_unit(5, 0, Vector2i(6, 6), 0)
	_hud_with_view(state, u)
	var row := hud.get_node("%ActionRow") as Control
	row.visible = true
	row.size = Vector2(252.0, 48.0)
	var row_home: Vector2 = hud.size - row.size - Vector2(24.0, 12.0)
	row.position = row_home
	var end_turn := hud.get_node("%EndTurnButton") as Control
	var end_home: Vector2 = end_turn.position
	var confirm := hud.get_node("%ConfirmButton") as Control
	var shown: int = 0
	for cell: Vector2i in [Vector2i(10, 10), Vector2i(2, 10), Vector2i(10, 2), Vector2i(2, 2), Vector2i(11, 6)]:
		hud._on_mine_caption(0, cell)
		if not _mine_tag().visible:
			continue
		shown += 1
		var r: Rect2 = _tag_rect(_mine_tag())
		assert_true(Rect2(Vector2.ZERO, hud.size).encloses(r), "підпис у межах екрана біля %s" % cell)
		assert_false(r.intersects(hud._local_rect(end_turn)), "не на «Завершити хід» біля %s" % cell)
		assert_false(r.intersects(hud._local_rect(confirm)), "не на «Підтвердити» біля %s" % cell)
		for plate: Control in [end_turn, row]:
			plate.position = r.get_center() - plate.size * 0.5
			hud._on_mine_caption(0, cell)
			assert_true(_mine_tag().visible, "місце знайшлося біля %s" % cell)
			assert_false(_tag_rect(_mine_tag()).intersects(hud._local_rect(plate)), "обходить %s біля %s" % [plate.name, cell])
			assert_ne(_mine_tag().position, r.position, "підпис зрушив із зайнятого місця біля %s" % cell)
		end_turn.position = end_home
		row.position = row_home
		hud._on_mine_caption(0, cell)
	assert_gt(shown, 0, "хоч один підпис показано")
