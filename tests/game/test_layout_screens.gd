extends GutTest
## Task 4.1: кожен наявний екран влазить у малий і великий телефон, ПК і
## планшет (логічні px ≈ dp після UiScale), а тап-цілі не менші за 48.
## Обома мовами: українські підписи довші, і саме вони першими не влізають.

const SCREENS: Array[String] = [
	"res://game/ui/hud.tscn", "res://game/ui/main_menu.tscn", "res://game/ui/match_setup.tscn",
	"res://game/ui/settings_screen.tscn", "res://game/ui/pause_menu.tscn",
	"res://game/ui/results_screen.tscn", "res://game/ui/handover_gate.tscn",
]
## Основний вміст меню на WIDE: той самий розмір, що на ПК, — не тягнеться.
const CAPPED_CONTENT: Dictionary = {
	"res://game/ui/main_menu.tscn": "SafeArea/Scroll/Row/MenuColumn",
	"res://game/ui/match_setup.tscn": "SafeArea/Frame/Scroll/Center/Card",
	"res://game/ui/settings_screen.tscn": "SafeArea/Frame/Scroll/Center/Card",
	"res://game/ui/pause_menu.tscn": "Scroll/Center/Card",
	"res://game/ui/results_screen.tscn": "SafeArea/Frame/Scroll/Center/Card",
}

## Головні дії екрана: гравець не сміє їх шукати прокруткою. Для паузи —
## обидва стани картки (звичайний і підтвердження «Здатися»).
const PRIMARY_ACTIONS: Dictionary = {
	"res://game/ui/main_menu.tscn": ["%NewMatchButton"],
	"res://game/ui/match_setup.tscn": ["%BackButton", "%StartButton"],
	"res://game/ui/settings_screen.tscn": ["%BackButton"],
	"res://game/ui/results_screen.tscn": ["%ToMenuButton", "%RematchButton"],
	"res://game/ui/pause_menu.tscn": ["%ResumeButton", "%SettingsButton", "%SaveQuitButton", "%SurrenderButton"],
	"pause_confirm": ["%ConfirmYesButton", "%ConfirmCancelButton"],
}

const MatchServiceScript := preload("res://game/autoload/match_service.gd")

const LOCALES: Array[String] = ["en", "uk"]

var _service: Node
var _orig_locale: String


func before_each() -> void:
	_orig_locale = TranslationServer.get_locale()
	_service = MatchServiceScript.new()
	add_child_autofree(_service)
	_service.start_match(Board.create(12, 12, Terrain.GroundState.MUD), 3, 1)


func after_each() -> void:
	TranslationServer.set_locale(_orig_locale)


func _cases() -> Array:
	var out: Array = []
	for scene: String in SCREENS:
		for size: Vector2i in LayoutProbe.SIZES:
			for locale: String in LOCALES:
				out.append([scene, size, locale])
	return out


## Найважчий вміст кожного екрана: результати з матчем на трьох, HUD із
## вибраною штурмовою групою (рядок дронів) і прев'ю пострілу одночасно.
func _setup(scene: String) -> Callable:
	match scene:
		"res://game/ui/results_screen.tscn":
			return func(n: Node) -> void: n.match_service = _service
	return Callable()


func _fill(scene: String, root: Control) -> void:
	var state: BattleState = _service.state
	match scene:
		"res://game/ui/hud.tscn":
			var hud := root as Hud
			hud.bind(state)
			hud.show_selection(state.add_unit(1, 0, Vector2i(3, 3), 0))
			hud.show_preview({"type": InputController.ActionType.SHOT, "unit_id": 1,
				"target_id": 2, "sector": 0, "min": 120, "max": 180})
		"res://game/ui/handover_gate.tscn":
			(root as HandoverGate).show_for(2)


func _mount(scene: String, size: Vector2i) -> Control:
	var root: Control = await LayoutProbe.mount(self, load(scene), size, _setup(scene))
	_fill(scene, root)
	await LayoutProbe.settle(self)
	return root


func test_screens_fit_phone_pc_tablet(p = use_parameters(_cases())) -> void:
	TranslationServer.set_locale(p[2])
	var root: Control = await _mount(p[0], p[1])
	var where: String = "%s @ %s %s" % p
	assert_eq(LayoutProbe.overflowing(root, p[1]), [] as Array[String], where)
	assert_eq(LayoutProbe.small_targets(root), [] as Array[String], where)


func test_hud_bars_do_not_overlap_at_any_size(p = use_parameters(LayoutProbe.SIZES)) -> void:
	var size: Vector2i = p
	var root: Control = await _mount("res://game/ui/hud.tscn", size)
	var bars: Array[Control] = [root.get_node("SafeArea/Layout/TopBar"), root.get_node("%BottomBar")]
	assert_eq(LayoutProbe.overlapping(bars), [] as Array[String], str(p))


## Task 9: рядок меж ремонту при згорнутій панелі інженера влізає на кожен розмір
## обома мовами, а HUD не виходить за екран.
func test_hud_repair_preview_fits_with_collapsed_panel(p = use_parameters(_repair_cases())) -> void:
	TranslationServer.set_locale(p[1])
	var root: Control = await _mount("res://game/ui/hud.tscn", p[0])
	var hud := root as Hud
	hud.show_selection(_service.state.add_unit(11, 0, Vector2i(4, 4), 0))
	(root.get_node("%EngineerPanel") as EngineerPanel).set_armed(true)
	hud.show_preview({"type": InputController.ActionType.ENGINEER, "unit_id": 1,
		"action": EngineerCommand.Action.REPAIR_UNIT, "target": Vector2i(4, 3), "heal_min": 20, "heal_max": 43})
	await LayoutProbe.settle(self)
	var where: String = "%s %s" % p
	assert_true((root.get_node("%PreviewRepairBox") as Control).is_visible_in_tree(), where)
	assert_eq(LayoutProbe.overflowing(root, p[0]), [] as Array[String], where)
	assert_eq(LayoutProbe.small_targets(root), [] as Array[String], where)
	assert_eq(LayoutProbe.overlapping([root.get_node("SafeArea/Layout/TopBar"), root.get_node("%BottomBar")] as Array[Control]),
		[] as Array[String], where)


## Task 10: озброєний дрон — кнопка, межі шкоди, радіус і причина відмови разом —
## влазить на кожен розмір обома мовами, кнопка ≥ 48 і не налазить на сусідні.
func test_hud_drone_controls_fit(p = use_parameters(_repair_cases())) -> void:
	TranslationServer.set_locale(p[1])
	var root: Control = await _mount("res://game/ui/hud.tscn", p[0])
	var hud := root as Hud
	hud.show_preview({"type": InputController.ActionType.DRONE, "unit_id": 1, "target_id": 2, "min": 120, "max": 180})
	hud._show_drone_range()
	hud._show_drone_reason("ERR_DRONE_CANNOT_TARGET_INFANTRY")
	await LayoutProbe.settle(self)
	var where: String = "%s %s" % p
	var drone: Control = root.get_node("%DroneButton")
	assert_true(drone.is_visible_in_tree(), where)
	for n: String in ["%PreviewDroneBox", "%DroneRangeLabel", "%DroneReasonLabel"]:
		assert_true((root.get_node(n) as Control).is_visible_in_tree(), "%s %s" % [n, where])
	assert_true(drone.size.x >= 48.0 and drone.size.y >= 48.0, where)
	assert_eq(LayoutProbe.overflowing(root, p[0]), [] as Array[String], where)
	assert_eq(LayoutProbe.small_targets(root), [] as Array[String], where)
	assert_eq(LayoutProbe.overlapping([root.get_node("SafeArea/Layout/TopBar"), root.get_node("%BottomBar")] as Array[Control]),
		[] as Array[String], where)
	assert_eq(LayoutProbe.overlapping([drone, root.get_node("%CancelButton"), root.get_node("%ConfirmButton"),
		root.get_node("%EndTurnButton"), root.get_node("%EngineerPanel")] as Array[Control]), [] as Array[String], where)


func _repair_cases() -> Array:
	var out: Array = []
	for size: Vector2i in LayoutProbe.SIZES:
		for locale: String in LOCALES:
			out.append([size, locale])
	return out


func test_menu_content_capped_on_wide(p = use_parameters(CAPPED_CONTENT.keys())) -> void:
	var scene: String = p
	var pc: Control = await _mount(scene, LayoutProbe.PC)
	var on_pc: Vector2 = (pc.get_node(CAPPED_CONTENT[scene]) as Control).size
	var wide: Control = await _mount(scene, LayoutProbe.WIDE)
	var on_wide: Vector2 = (wide.get_node(CAPPED_CONTENT[scene]) as Control).size
	assert_eq(on_wide.x, on_pc.x, scene)


## ПК зберігає нинішній вигляд — прев'ю й кнопки одним рядком; на малому
## телефоні кнопки переносяться під прев'ю цілим блоком, а не по одній.
func test_hud_bottom_bar_wraps_only_when_it_must(p = use_parameters(
		[[LayoutProbe.PC, true], [LayoutProbe.TABLET, true], [LayoutProbe.PHONE_SMALL, false]])) -> void:
	var size: Vector2i = p[0]
	var one_row: bool = p[1]
	TranslationServer.set_locale("uk")
	var root: Control = await _mount("res://game/ui/hud.tscn", size)
	var bar: Control = root.get_node("%BottomBar")
	var buttons: Control = root.get_node("%BottomBar/ButtonRow")
	assert_eq(bar.size.y, 64.0 if one_row else 64.0 + 8.0 + _info_row_height(root), str(size))
	assert_eq(buttons.get_global_rect().end.x, bar.get_global_rect().end.x, "кнопки праворуч: %s" % size)


func _info_row_height(root: Control) -> float:
	return maxf((root.get_node("%SelectionRow") as Control).size.y,
		(root.get_node("%PreviewShotBox") as Control).size.y)


func _primary_cases() -> Array:
	var out: Array = []
	for key: String in PRIMARY_ACTIONS:
		for size: Vector2i in LayoutProbe.SIZES:
			for locale: String in LOCALES:
				out.append([key, size, locale])
	return out


func test_primary_actions_never_need_scrolling(p = use_parameters(_primary_cases())) -> void:
	TranslationServer.set_locale(p[2])
	var key: String = p[0]
	var confirm: bool = key == "pause_confirm"
	var scene: String = "res://game/ui/pause_menu.tscn" if confirm else key
	var root: Control = await _mount(scene, p[1])
	if confirm:
		root.get_node("%SurrenderButton").pressed.emit()
		await LayoutProbe.settle(self)
	var buttons: Array[Control] = []
	for path: String in PRIMARY_ACTIONS[key]:
		buttons.append(root.get_node(path) as Control)
	assert_eq(LayoutProbe.clipped(root, buttons, p[1]), [] as Array[String], "%s @ %s %s" % p)


## Картка з закріпленим футером на ПК і планшеті читається ОДНИМ блоком по
## центру: прокрутка вмикається лише тоді, коли вміст не влазить (телефони).
const FOOTED_SCREENS: Array[String] = [
	"res://game/ui/match_setup.tscn", "res://game/ui/settings_screen.tscn",
	"res://game/ui/results_screen.tscn",
]


func _block_cases() -> Array:
	var out: Array = []
	for scene: String in FOOTED_SCREENS:
		for size: Vector2i in [LayoutProbe.PC, LayoutProbe.TABLET]:
			for locale: String in LOCALES:
				out.append([scene, size, locale])
	return out


func test_card_and_footer_are_one_centred_block_on_pc(p = use_parameters(_block_cases())) -> void:
	TranslationServer.set_locale(p[2])
	var root: Control = await _mount(p[0], p[1])
	var card: Rect2 = (root.get_node("SafeArea/Frame/Scroll/Center/Card") as Control).get_global_rect()
	var footer: Rect2 = (root.get_node("SafeArea/Frame/FooterRow/Footer") as Control).get_global_rect()
	var where: String = "%s @ %s %s" % p
	var gap: float = footer.position.y - card.end.y
	assert_between(gap, 0.0, 16.0, "розрив картка→футер: " + where)
	var block_centre: float = (card.position.y + footer.end.y) * 0.5
	assert_almost_eq(block_centre, p[1].y * 0.5, 16.0, "блок по центру: " + where)
