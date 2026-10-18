extends GutTest
## Task 8: панель верб інженера. Доступність і причина — лише з
## EngineerCommand.action_status() (§3.13); панель нічого не виводить сама.

const PanelScene := preload("res://game/ui/engineer_panel.tscn")
const HudScene := preload("res://game/ui/hud.tscn")
const MatchServiceScript := preload("res://game/autoload/match_service.gd")

const ENGINEER: int = 11
const A := EngineerCommand.Action

## Golden: підписи кнопок англійською (назва · fire_cost 30), у порядку EngineerCommand.Action.
const EN_LABELS: Array[String] = [
	"Lay mine · 30 AP", "Clear mine · 30 AP", "Repair bridge · 30 AP", "Demolish bridge · 30 AP",
	"Repair unit · 30 AP",
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


func test_five_buttons_with_ap_cost() -> void:
	var e: Unit = _engineer()
	var p: EngineerPanel = _panel()
	p.show_for(_service.state, e)
	var labels: Array[String] = []
	for a: int in VERBS:
		labels.append(p.button_for(a).text)
	assert_eq(labels, EN_LABELS)
	var order: Array[String] = []
	for b in p.find_children("*", "Button", true, false):
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
	assert_eq(p.button_for(A.LAY_MINE).text, "Поставити міну · 30 ОД")
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
