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

## Шпигун замість справжнього ZoneOverlay (той тягне живий BoardView із MultiMesh).
class SpyZoneOverlay extends ZoneOverlay:
	func _init() -> void:
		pass

	func show_for(_unit: Unit, _zones: Pathing.Zones) -> void:
		pass

	func clear() -> void:
		pass


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


## Крайні плити (чип, пауза, «Завершити хід») стоять по кутах і не налазять одна на одну.
func test_hud_corner_chrome_does_not_overlap_at_any_size(p = use_parameters(LayoutProbe.SIZES)) -> void:
	var size: Vector2i = p
	var root: Control = await _mount("res://game/ui/hud.tscn", size)
	var chrome: Array[Control] = [root.get_node("%Chip"), root.get_node("%PauseButton"), root.get_node("%EndTurnButton")]
	assert_eq(LayoutProbe.overlapping(chrome), [] as Array[String], str(p))
	assert_eq((root.get_node("%Chip") as Control).get_global_rect().position, Vector2(24, 12), "чип: (24, 12)")
	assert_eq((root.get_node("%PauseButton") as Control).get_global_rect(),
		Rect2(size.x - 72.0, 8.0, 48.0, 48.0), "пауза: право 24, верх 8, 48 × 48")
	assert_eq((root.get_node("%EndTurnButton") as Control).get_global_rect(),
		Rect2(24.0, size.y - 60.0, 161.0, 48.0), "кінець ходу: (24, низ 12), 161 × 48")


## Кластер «плита прев'ю + ряд» на кожному розмірі: ряд 285 × 48 унизу праворуч, плита над ним на
## 8 dp, «Скасувати» 126 і «Підтвердити» 143 із проміжком 16, ніщо не налазить на кутові плити.
func test_hud_cluster_docks_bottom_right_and_fits(p = use_parameters(_repair_cases())) -> void:
	TranslationServer.set_locale(p[1])
	var size: Vector2i = p[0]
	var root: Control = await _mount("res://game/ui/hud.tscn", size)
	var hud := root as Hud
	hud.show_preview({"type": InputController.ActionType.SHOT, "unit_id": 1, "target_id": 2,
		"sector": 1, "min": 120, "max": 180, "armour_ignored": true, "in_cover": false})
	await LayoutProbe.settle(self)
	var where: String = "%s %s" % p
	var plate: Control = root.get_node("%PreviewPlate")
	var row: Control = root.get_node("%ActionRow")
	var cancel: Control = root.get_node("%CancelButton")
	var confirm: Control = root.get_node("%ConfirmButton")
	assert_eq(hud.cluster_name(), "a", where)
	assert_eq(row.get_global_rect(), Rect2(size.x - 24.0 - 285.0, size.y - 60.0, 285.0, 48.0), where)
	assert_eq(plate.get_global_rect().end.y + 8.0, row.get_global_rect().position.y, "плита над рядом на 8 dp: " + where)
	assert_eq(plate.size.x, 285.0, where)
	assert_eq(cancel.size.x, 126.0, where)
	assert_eq(confirm.size.x, 143.0, where)
	assert_eq(confirm.position.x - cancel.get_rect().end.x, 16.0, "Cancel ↔ Confirm 16: " + where)
	assert_eq(LayoutProbe.overflowing(root, p[0]), [] as Array[String], where)
	assert_eq(LayoutProbe.small_targets(root), [] as Array[String], where)
	for n: String in ["%Chip", "%PauseButton", "%EndTurnButton"]:
		var corner: Rect2 = (root.get_node(n) as Control).get_global_rect()
		assert_false(plate.get_global_rect().intersects(corner), "%s %s" % [n, where])
		assert_false(row.get_global_rect().intersects(corner), "%s %s" % [n, where])


## Усі види плити прев'ю влазять у 285 dp обома мовами й не роздувають плиту.
func test_hud_preview_plate_content_fits_285_for_every_type(p = use_parameters(_repair_cases())) -> void:
	TranslationServer.set_locale(p[1])
	var root: Control = await _mount("res://game/ui/hud.tscn", p[0])
	var hud := root as Hud
	var previews: Array[Dictionary] = [
		{"type": InputController.ActionType.MOVE, "unit_id": 1, "target": Vector2i(4, 5),
			"path": [Vector2i(4, 5)] as Array[Vector2i], "ap_left": 28},
		{"type": InputController.ActionType.SHOT, "unit_id": 1, "target_id": 2, "sector": 1,
			"min": 120, "max": 180, "armour_ignored": true, "in_cover": true},
		{"type": InputController.ActionType.DRONE, "unit_id": 1, "target_id": 2, "min": 120, "max": 180},
		{"type": InputController.ActionType.ENGINEER, "unit_id": 1, "action": EngineerCommand.Action.REPAIR_UNIT,
			"target": Vector2i(4, 3), "heal_min": 20, "heal_max": 43},
		{"type": InputController.ActionType.ENGINEER, "unit_id": 1, "action": EngineerCommand.Action.DEMOLISH_BRIDGE,
			"target": Vector2i(4, 3)},
	]
	var plate: Control = root.get_node("%PreviewPlate")
	for i in previews.size():
		hud.show_preview(previews[i])
		await LayoutProbe.settle(self)
		var where: String = "%s %s #%d" % [p[0], p[1], i]
		assert_true(plate.is_visible_in_tree(), where)
		assert_eq(plate.size.x, 285.0, "ширина плити не росте від вмісту: " + where)
		assert_eq(LayoutProbe.overflowing(root, p[0]), [] as Array[String], where)
		assert_lte(plate.get_combined_minimum_size().x, 285.0, "вміст не ширший за плиту: " + where)


## Озброєний дрон: смужка [Скасувати | озброєно] 285 × 52 унизу праворуч, ≥ 48, без накладання.
func test_hud_drone_strip_fits(p = use_parameters(_repair_cases())) -> void:
	TranslationServer.set_locale(p[1])
	var size: Vector2i = p[0]
	var root: Control = await _mount("res://game/ui/hud.tscn", size)
	var hud := root as Hud
	var state: BattleState = _service.state
	var squad: Unit = state.units.values()[0]
	state.add_unit(5, 1, squad.pos + Vector2i(0, 3), 0)
	_service.begin()
	_service.take_events()
	var controller := InputController.new(_service, SpyZoneOverlay.new())
	hud.attach_controller(controller)
	controller.select_unit(squad)
	controller.arm_drone()
	await LayoutProbe.settle(self)
	var where: String = "%s %s" % p
	var strip: ArmedStrip = root.get_node("%DroneStrip")
	assert_true(strip.is_visible_in_tree(), where)
	assert_eq(strip.get_global_rect(), Rect2(size.x - 24.0 - 285.0, size.y - 12.0 - 52.0, 285.0, 52.0), where)
	assert_eq(LayoutProbe.overflowing(root, size), [] as Array[String], where)
	assert_eq(LayoutProbe.small_targets(root), [] as Array[String], where)
	assert_false(strip.get_global_rect().intersects((root.get_node("%EndTurnButton") as Control).get_global_rect()), where)


## Підпис «нижня межа» стоїть під чипом і не налазить на кутові плити.
func test_hud_threat_floor_fits(p = use_parameters(_repair_cases())) -> void:
	TranslationServer.set_locale(p[1])
	var root: Control = await _mount("res://game/ui/hud.tscn", p[0])
	var hud := root as Hud
	hud._show_threat_floor(true)
	await LayoutProbe.settle(self)
	var where: String = "%s %s" % [p[0], p[1]]
	assert_true((root.get_node("%ThreatFloorLabel") as Control).is_visible_in_tree(), where)
	assert_eq(LayoutProbe.overflowing(root, p[0]), [] as Array[String], where)
	var plate: Control = root.get_node("%ThreatFloorPlate")
	for n: String in ["%Chip", "%PauseButton", "%EndTurnButton"]:
		assert_false(plate.get_global_rect().intersects((root.get_node(n) as Control).get_global_rect()), "%s %s" % [n, where])


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
