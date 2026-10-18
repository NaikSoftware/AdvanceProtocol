extends GutTest
## Task 10: дроновий удар (§3.9) наскрізно — кнопка HUD, справжні тапи по дошці,
## перевірки на MatchService.state.

const E2E := preload("res://tests/e2e/e2e_helpers.gd")

const RIFLE: int = 0
const ASSAULT: int = 1
const MEDIUM_TANK: int = 5
const E: int = 2

const SQUAD := Vector2i(0, 1)
const INF := Vector2i(3, 1)
const TANK := Vector2i(5, 1)

var _e2e: E2E


func before_each() -> void:
	_e2e = E2E.new(self)


func after_each() -> void:
	_e2e.restore_runner_gui()
	DirAccess.remove_absolute(_e2e.save_path)
	DirAccess.remove_absolute(_e2e.save_path + ".map")


func _spawn(type_id: int, owner: int, pos: Vector2i) -> Dictionary:
	return {"type_id": type_id, "owner": owner, "pos": pos, "facing": E}


## 10×3, усе розвідано обома гравцями.
func _boot(squad_type: int = ASSAULT, prepare: Callable = Callable()) -> void:
	await _e2e.boot(10, 3, [_spawn(squad_type, 0, SQUAD), _spawn(MEDIUM_TANK, 1, TANK), _spawn(RIFLE, 1, INF)],
		{"prepare": func(st: BattleState) -> void:
			for p in st.player_count:
				st.vision[p].seen.fill(1)
			if prepare.is_valid():
				prepare.call(st)})


func _state() -> BattleState:
	return _e2e.service.state


func _button() -> DroneButton:
	return _e2e.hud().get_node("%DroneButton")


func _reason() -> Label:
	return _e2e.hud().get_node("%DroneReasonLabel")


func _board_view() -> BoardView:
	return _e2e.screen.get_node("%BoardView")


func _arm() -> void:
	_e2e.tap(SQUAD)
	await _e2e.settle()
	_e2e.press(_button())
	await _e2e.settle()


func test_drone_strike_through_button() -> void:
	await _boot()
	var squad: Unit = _state().unit_at(SQUAD)
	var tank: Unit = _state().unit_at(TANK)
	_e2e.tap(SQUAD)
	await _e2e.settle()
	assert_true(_button().is_visible_in_tree())
	assert_eq(_button().text, tr("hud_drone_strike") % 2)
	_e2e.press(_button())
	await _e2e.settle()
	assert_ne(_board_view().contour_segments(BoardView.LAYER_TARGETS), [], "кільце дрона")
	assert_true(_e2e.screen.unit_view_for(tank.id)._crosshair.visible, "танк — приціл")
	assert_true(_e2e.screen.unit_view_for(_state().unit_at(INF).id)._forbidden.visible, "піхота — заборонена")
	assert_false(_e2e.screen.unit_view_for(tank.id)._forbidden.visible)
	_e2e.tap(TANK)
	await _e2e.settle()
	assert_eq((_e2e.hud().get_node("%PreviewDroneDamageValue") as Label).text, "120–180")
	await _e2e.confirm()
	assert_eq(squad.drones_left, 1)
	assert_eq(_button().text, tr("hud_drone_strike") % 1)
	assert_eq(_e2e.screen.unit_view_for(squad.id)._drones_left, 1, "значок на юніті")
	# Golden, seed 7: перший кидок матчу — roll(60) = 1 → 120 + 1 = 121; 400 − 121.
	assert_eq(tank.hp, 279)
	assert_eq(_e2e.events_of(Events.ShotRetaliated).size(), 0, "танк: дальність 4 < 5")
	assert_eq(_board_view().contour_segments(BoardView.LAYER_TARGETS), [], "кільце знято після удару")
	assert_false(_e2e.screen.unit_view_for(_state().unit_at(INF).id)._forbidden.visible)


func test_drone_on_infantry_shows_reason_and_does_nothing() -> void:
	await _boot()
	var squad: Unit = _state().unit_at(SQUAD)
	await _arm()
	_e2e.tap(INF)
	await _e2e.settle()
	assert_true(_reason().is_visible_in_tree())
	assert_eq(_reason().text, tr("ERR_DRONE_CANNOT_TARGET_INFANTRY"))
	assert_true((_e2e.hud().get_node("%ConfirmButton") as Button).disabled, "прев'ю немає")
	assert_eq(squad.drones_left, 2)
	assert_eq(squad.ap, 30)


func test_drone_button_hidden_for_rifle_squad() -> void:
	await _boot(RIFLE)
	_e2e.tap(SQUAD)
	await _e2e.settle()
	assert_true((_e2e.hud().get_node("%SelectionRow") as Control).is_visible_in_tree(), "вибрано")
	assert_false(_button().is_visible_in_tree())


func test_third_strike_refused() -> void:
	await _boot(ASSAULT, func(st: BattleState) -> void: st.unit_at(SQUAD).drones_left = 0)
	await _arm()
	assert_eq(_reason().text, tr("ERR_NO_DRONES_LEFT"))
	assert_eq(_board_view().contour_segments(BoardView.LAYER_TARGETS), [], "нічого не озброєно")


## Рішення контролера: тап по ворогу без кнопки — звичайний постріл.
func test_plain_tap_on_tank_is_a_shot_preview() -> void:
	await _boot()
	_e2e.tap(SQUAD)
	await _e2e.settle()
	_e2e.tap(INF)  # дальність пострілу загону 3
	await _e2e.settle()
	assert_true((_e2e.hud().get_node("%PreviewShotBox") as Control).visible)
	assert_false((_e2e.hud().get_node("%PreviewDroneBox") as Control).visible)


## Рішення контролера: озброєння дрона знімає прев'ю руху.
func test_arming_drone_clears_a_pending_move_preview() -> void:
	await _boot()
	_e2e.tap(SQUAD)
	await _e2e.settle()
	_e2e.tap(Vector2i(0, 0))
	await _e2e.settle()
	var hud: Hud = _e2e.hud()
	assert_true((hud.get_node("%PreviewMoveBox") as Control).visible, "передумова: прев'ю руху")
	_e2e.press(_button())
	await _e2e.settle()
	assert_false((hud.get_node("%PreviewMoveBox") as Control).visible)
	assert_true((hud.get_node("%ConfirmButton") as Button).disabled)


## Рішення контролера: озброєний дрон не переживає гейт передачі.
func test_armed_drone_does_not_survive_the_handover_gate() -> void:
	await _boot()
	await _arm()
	var inf_id: int = _state().unit_at(INF).id
	assert_ne(_board_view().contour_segments(BoardView.LAYER_TARGETS), [], "передумова: озброєно")
	await _e2e.end_turn()
	assert_true(_e2e.gate().is_visible_in_tree(), "гейт показано")
	assert_eq(_board_view().contour_segments(BoardView.LAYER_TARGETS), [])
	assert_false((_e2e.hud().get_node("%DroneRangeLabel") as Control).is_visible_in_tree())
	await _e2e.confirm_gate()
	assert_eq(_board_view().contour_segments(BoardView.LAYER_TARGETS), [])
	var inf_view: UnitView = _e2e.screen.unit_view_for(inf_id)
	if inf_view != null:
		assert_false(inf_view._forbidden.visible)
	assert_false(_button().is_visible_in_tree(), "нічого не вибрано у гравця, що зайшов")
