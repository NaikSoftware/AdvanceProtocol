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
	"res://game/ui/match_setup.tscn": "SafeArea/Scroll/Center/Card",
	"res://game/ui/settings_screen.tscn": "SafeArea/Scroll/Center/Card",
	"res://game/ui/pause_menu.tscn": "Scroll/Center/Card",
	"res://game/ui/results_screen.tscn": "SafeArea/Scroll/Center/Card",
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


func test_hud_bars_do_not_overlap_on_phone(p = use_parameters(LayoutProbe.SIZES)) -> void:
	var size: Vector2i = p
	var root: Control = await _mount("res://game/ui/hud.tscn", size)
	var bars: Array[Control] = [root.get_node("SafeArea/Layout/TopBar"), root.get_node("%BottomBar")]
	assert_eq(LayoutProbe.overlapping(bars), [] as Array[String], str(p))


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
