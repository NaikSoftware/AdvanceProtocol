extends GutTest
## Task 8: панель верб інженера. Доступність і причина — лише з
## EngineerCommand.action_status() (§3.13); панель нічого не виводить сама.

const PanelScene := preload("res://game/ui/engineer_panel.tscn")
const HudScene := preload("res://game/ui/hud.tscn")
const MatchServiceScript := preload("res://game/autoload/match_service.gd")

const ENGINEER: int = 11
const A := EngineerCommand.Action

## Golden: підписи кнопок англійською, у порядку EngineerCommand.Action. Без ціни:
## кожна верба коштує той самий fire_cost — рядок ціни був шумом (власник).
const EN_LABELS: Array[String] = [
	"Lay mine", "Clear mine", "Repair bridge", "Demolish bridge", "Repair unit",
]
## Підказка озброєної верби — що саме тапнути, у тому ж порядку.
const EN_HINTS: Array[String] = [
	"Tap an adjacent tile to lay a mine", "Tap an adjacent mine to clear it",
	"Tap an adjacent broken bridge to repair it", "Tap an adjacent bridge to demolish it",
	"Tap an adjacent friendly unit to repair it",
]
## Верби цілей на панелі немає: механіку цілей прибирає окрема задача (рішення власника).
const VERBS: Array[int] = [A.LAY_MINE, A.CLEAR_MINE, A.REPAIR_BRIDGE, A.DEMOLISH_BRIDGE, A.REPAIR_UNIT]

var _service: Node
var _orig_locale: String


func before_each() -> void:
	_orig_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	_service = MatchServiceScript.new()
	add_child_autofree(_service)
	_service.start_match(Board.create(8, 8, Terrain.GroundState.DRY), 2, 1)


func after_each() -> void:
	TranslationServer.set_locale(_orig_locale)


func _engineer() -> Unit:
	var e: Unit = _service.state.add_unit(ENGINEER, 0, Vector2i(3, 3), 0)
	_service.begin()
	_service.take_events()
	return e


func _panel() -> EngineerPanel:
	var p: EngineerPanel = PanelScene.instantiate()
	add_child_autofree(p)
	return p


func test_five_buttons_without_ap_cost() -> void:
	var e: Unit = _engineer()
	var p: EngineerPanel = _panel()
	p.show_for(_service.state, e)
	var labels: Array[String] = []
	for a: int in VERBS:
		labels.append(p.button_for(a).text)
	assert_eq(labels, EN_LABELS)
	var order: Array[String] = []
	for b in p.get_node("%Grid").get_children():
		order.append((b as Button).text)
	assert_eq(order, EN_LABELS, "рівно п'ять кнопок, у порядку Action")


func test_unavailable_button_shows_reason_on_press() -> void:
	var e: Unit = _engineer()
	var p: EngineerPanel = _panel()
	p.show_for(_service.state, e)
	var chosen: Array[int] = []
	p.action_chosen.connect(func(a: int) -> void: chosen.append(a))
	var reason: Label = p.get_node("%ReasonLabel")

	var clear: Button = p.button_for(A.CLEAR_MINE)
	assert_false(clear.disabled, "недоступна кнопка лишається натискною — на телефоні нема наведення")
	assert_eq(clear.theme_type_variation, EngineerPanel.UNAVAILABLE_VARIATION)
	clear.pressed.emit()
	assert_eq(reason.text, "There is no mine here")
	assert_true(reason.visible)
	assert_eq(chosen, [] as Array[int], "недоступна верба нічого не озброює")

	var lay: Button = p.button_for(A.LAY_MINE)
	assert_eq(lay.theme_type_variation, &"")
	lay.pressed.emit()
	assert_eq(chosen, [A.LAY_MINE] as Array[int])
	assert_false(reason.visible, "доступна верба знімає причину")


func test_engineer_panel_relabels_on_locale_change() -> void:
	var e: Unit = _engineer()
	var p: EngineerPanel = _panel()
	TranslationServer.set_locale("uk")
	await get_tree().process_frame
	p.show_for(_service.state, e)
	p.button_for(A.CLEAR_MINE).pressed.emit()
	assert_eq(p.button_for(A.LAY_MINE).text, "Поставити міну")
	TranslationServer.set_locale("en")
	await get_tree().process_frame
	assert_eq(p.button_for(A.LAY_MINE).text, EN_LABELS[0])
	assert_eq((p.get_node("%ReasonLabel") as Label).text, "There is no mine here")


func _hud_cases() -> Array:
	var out: Array = []
	for size: Vector2i in LayoutProbe.SIZES:
		for locale: String in ["en", "uk"]:
			out.append([size, locale])
	return out


func test_panel_fits_phone_without_overlapping_bars(p = use_parameters(_hud_cases())) -> void:
	TranslationServer.set_locale(p[1])
	var size: Vector2i = p[0]
	var hud: Hud = await LayoutProbe.mount(self, HudScene, size)
	var e: Unit = _engineer()
	hud.bind(_service.state)
	hud.show_selection(e)
	# Найдовша причина — у рядку причини теж.
	hud.get_node("%EngineerPanel").button_for(A.REPAIR_UNIT).pressed.emit()
	await LayoutProbe.settle(self)
	var panel: Control = hud.get_node("%EngineerPanel")
	var where: String = "%s %s" % p
	assert_true(panel.is_visible_in_tree(), where)
	assert_eq(LayoutProbe.overflowing(hud, size), [] as Array[String], where)
	assert_eq(LayoutProbe.small_targets(hud), [] as Array[String], where)
	var bars: Array[Control] = [hud.get_node("SafeArea/Layout/TopBar"), hud.get_node("%BottomBar"), panel]
	assert_eq(LayoutProbe.overlapping(bars), [] as Array[String], where)
	# Ширина — не більше ~40 % екрана: решта дошки лишається тапабельною.
	assert_true(panel.size.x <= 0.4 * size.x, "%s: ширина %s > 40 %%" % [where, panel.size.x])
	# Висота — за вмістом, без розтягування на весь Middle.
	var reason: Label = panel.get_node("%ReasonLabel")
	var natural: float = (panel.get_node("%Box") as Control).get_combined_minimum_size().y \
			+ panel.get_theme_stylebox("panel").get_minimum_size().y
	if reason.visible:
		natural += reason.get_combined_minimum_size().y + float(panel.get_node("%Root").get_theme_constant("separation"))
	assert_true(panel.size.y <= natural + 1.0, "%s: висота %s > вмісту %s" % [where, panel.size.y, natural])
	assert_true((panel.get_node("%Scroll") as Control).size.y >= 48.0, "%s: видно хоча б одну кнопку" % where)


func test_armed_panel_collapses_to_strip_with_cancel() -> void:
	var e: Unit = _engineer()
	var p: EngineerPanel = _panel()
	p.show_for(_service.state, e)
	var cancels: Array[int] = [0]
	p.cancel_pressed.connect(func() -> void: cancels[0] += 1)
	p.button_for(A.LAY_MINE).pressed.emit()
	p.set_armed(true)
	assert_false((p.get_node("%Scroll") as Control).visible)
	assert_true((p.get_node("%Strip") as Control).visible)
	assert_eq((p.get_node("%ArmedLabel") as Label).text, "Lay mine")
	var cancel: Button = p.get_node("%StripCancel")
	assert_true(cancel.custom_minimum_size.y >= 48.0 and cancel.custom_minimum_size.x >= 48.0)
	p.show_reason("ERR_NOT_ADJACENT")
	assert_true((p.get_node("%ReasonLabel") as Label).is_visible_in_tree(), "причина видна й у згорнутому стані")
	cancel.pressed.emit()
	assert_eq(cancels[0], 1)
	p.set_armed(false)
	assert_true((p.get_node("%Scroll") as Control).visible)
	assert_false((p.get_node("%Strip") as Control).visible)


func test_armed_verb_shows_what_to_tap() -> void:
	var p: EngineerPanel = _panel()
	p.show_for(_service.state, _engineer())
	var hint: Label = p.get_node("%HintLabel")
	assert_false(hint.visible, "не озброєно — підказки нема")
	for i in VERBS.size():
		p._chosen = VERBS[i]  # верба вибрана; доступність тут не важить
		p.set_armed(true)
		assert_true(hint.visible, EN_HINTS[i])
		assert_eq(hint.text, EN_HINTS[i])
		p.set_armed(false)
		assert_false(hint.visible)
