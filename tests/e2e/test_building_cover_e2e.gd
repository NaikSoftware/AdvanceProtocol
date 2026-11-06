extends GutTest
## Укриття в будівлі наскрізно: піхота в будинку не видна ворогові на розвіданій землі,
## тап по її тайлі її не вибирає й не цілить, поки той не стане поруч (8 клітинок);
## тоді вона з'являється, прев'ю пострілу показує половинні межі, а знайдена лишається
## знайденою, коли шукач відходить. Справжні події миші, кнопки HUD і гейта.

const E2E := preload("res://tests/e2e/e2e_helpers.gd")

const RIFLE: int = 0
const E: int = 2

# будівля коштує 30 AP (10 + 100 - 80), тож із 30 AP у неї входять лише з сусіднього тайла
const START := Vector2i(2, 2)
const HOUSE := Vector2i(3, 2)
const WATCHER := Vector2i(5, 2)  # 2 від будинку: у дальності 3, але юніт у укритті не видно
const FINDER := Vector2i(4, 3)  # по діагоналі від будинку
const AWAY := Vector2i(4, 4)  # крок від FINDER, уже не сусід будинку

var _e2e: E2E
var _preview: Dictionary = {}


func before_each() -> void:
	_e2e = E2E.new(self)
	_preview = {}


func after_each() -> void:
	_e2e.restore_runner_gui()
	DirAccess.remove_absolute(_e2e.save_path)
	DirAccess.remove_absolute(_e2e.save_path + ".map")


func _boot() -> void:
	await _e2e.boot(9, 5, [
		{"type_id": RIFLE, "owner": 0, "pos": START, "facing": E},
		{"type_id": RIFLE, "owner": 1, "pos": WATCHER, "facing": E}],
		{"tiles": {HOUSE: Terrain.Kind.BUILDING},
		"prepare": func(st: BattleState) -> void:
			for p in st.player_count:
				st.vision[p].seen.fill(1)})
	_e2e.screen.input_controller().action_preview.connect(func(p: Dictionary) -> void: _preview = p)


func _state() -> BattleState:
	return _e2e.service.state


func _squad() -> Unit:
	return _state().get_unit(1)


func _watcher() -> Unit:
	return _state().get_unit(2)


## Гравець 0 заходить у будинок, хід переходить до гравця 1.
func _squad_into_house_then_handover() -> void:
	await _e2e.act(START, HOUSE)
	assert_eq(_squad().pos, HOUSE, "передумова: відділення в будинку")
	await _e2e.end_turn()
	await _e2e.confirm_gate()
	assert_eq(_state().active_player, 1)


func _crosshairs() -> Array[int]:
	var out: Array[int] = []
	for u in _state().alive_units():
		var v: UnitView = _e2e.screen.unit_view_for(u.id)
		if v != null and (v.get_node("Crosshair") as Sprite3D).visible:
			out.append(u.id)
	return out


func test_hidden_then_found_by_walking_adjacent_then_stays_found() -> void:
	await _boot()
	await _squad_into_house_then_handover()

	# Прихований: вузла нема, тап не вибирає й не цілить, прицілу нема.
	assert_null(_e2e.screen.unit_view_for(_squad().id), "вузла відділення нема")
	assert_false(_state().can_see_unit(1, _squad()))
	_e2e.tap(WATCHER)
	_e2e.tap(HOUSE)
	assert_false(_preview.has("target_id") and _preview["target_id"] == _squad().id, "прев'ю пострілу по прихованому нема")
	assert_false(_e2e.hud().get_node("%PreviewShotBox").is_visible_in_tree(), "панель пострілу не з'явилась")
	assert_false(Targeting.firing_targets(_state(), _watcher().id).has(_squad()), "не серед цілей")
	assert_eq(_crosshairs(), [], "жодного прицілу")
	assert_eq(_squad().hp, 100)

	# Стає поруч (діагональ): відділення з'являється.
	_e2e.tap(FINDER)
	await _e2e.confirm()
	assert_eq(_watcher().pos, FINDER)
	assert_true(_state().can_see_unit(1, _squad()))
	var view: UnitView = _e2e.screen.unit_view_for(_squad().id)
	assert_not_null(view, "вузол відділення з'явився")

	# Прев'ю — половинні межі.
	_e2e.tap(HOUSE)
	var halved: Vector2i = Rules.damage_bounds(_watcher(), _squad(),
		Rules.armour_sector(_squad().facing, _squad().pos, _watcher().pos),
		Rules.distance_sq(FINDER, HOUSE), true)
	var plain: Vector2i = Rules.damage_bounds(_watcher(), _squad(),
		Rules.armour_sector(_squad().facing, _squad().pos, _watcher().pos),
		Rules.distance_sq(FINDER, HOUSE), false)
	assert_ne(halved, plain, "передумова: укриття справді міняє межі")
	assert_eq(_preview.get("target_id"), _squad().id)
	assert_eq([_preview["min"], _preview["max"]], [halved.x, halved.y])
	var label: Label = _e2e.hud().get_node("%PreviewDamageValue")
	assert_eq(label.text, "%d–%d" % [halved.x, halved.y], "HUD показує половинні межі")
	assert_eq(_crosshairs(), [_squad().id])

	# Постріл: шкода в половинних межах.
	await _e2e.confirm()
	var dealt: int = 100 - _squad().hp
	assert_between(dealt, halved.x, halved.y, "шкода в межах укриття")


func test_found_squad_stays_visible_after_the_finder_walks_away() -> void:
	await _boot()
	await _squad_into_house_then_handover()
	_e2e.tap(WATCHER)
	_e2e.tap(FINDER)
	await _e2e.confirm()
	assert_not_null(_e2e.screen.unit_view_for(_squad().id), "передумова: знайдено")
	_e2e.tap(AWAY)
	await _e2e.confirm()
	assert_eq(_watcher().pos, AWAY, "шукач відійшов")
	assert_true(_state().can_see_unit(1, _squad()))
	assert_not_null(_e2e.screen.unit_view_for(_squad().id), "знайдене лишається видимим")
