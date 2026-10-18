extends GutTest
## Task 14: тап по будь-якому видимому юніту — кільце дальності й позначки загроз
## (§3.13) наскрізно, справжніми тапами по дошці.

const E2E := preload("res://tests/e2e/e2e_helpers.gd")

const RIFLE: int = 0
const ASSAULT: int = 1
const CAR: int = 2
const MEDIUM_TANK: int = 5
const E: int = 2

const SQUAD := Vector2i(0, 1)
const CAR_POS := Vector2i(3, 1)
const TANK := Vector2i(6, 1)
const ENEMY_SQUAD := Vector2i(8, 1)  # 5 від броньовика — дістає лише дрон

var _e2e: E2E
var _last: Dictionary = {}


func before_each() -> void:
	_e2e = E2E.new(self)
	_last = {}


func after_each() -> void:
	_e2e.restore_runner_gui()
	DirAccess.remove_absolute(_e2e.save_path)
	DirAccess.remove_absolute(_e2e.save_path + ".map")


func _spawn(type_id: int, owner: int, pos: Vector2i) -> Dictionary:
	return {"type_id": type_id, "owner": owner, "pos": pos, "facing": E}


## 10×3, усе розвідано обома гравцями. enemy — ворожий юніт (тип, тайл).
func _boot(enemy_type: int, enemy_pos: Vector2i, prepare: Callable = Callable()) -> void:
	await _e2e.boot(10, 3, [_spawn(RIFLE, 0, SQUAD), _spawn(CAR, 0, CAR_POS), _spawn(enemy_type, 1, enemy_pos)],
		{"prepare": func(st: BattleState) -> void:
			for p in st.player_count:
				st.vision[p].seen.fill(1)
			st.unit_at(enemy_pos).ap = 0
			if prepare.is_valid():
				prepare.call(st)})
	_e2e.screen.input_controller().inspected.connect(
		func(ring: Array[Vector2i], drone_ring: Array[Vector2i], marked: Array[int], is_floor: bool) -> void:
			_last = {"ring": ring, "drone_ring": drone_ring, "marked": marked, "is_floor": is_floor})


func _state() -> BattleState:
	return _e2e.service.state


func _view(cell: Vector2i) -> UnitView:
	return _e2e.screen.unit_view_for(_state().unit_at(cell).id)


func _rings() -> Array:
	return (_e2e.screen.get_node("%BoardView") as BoardView).contour_segments(BoardView.LAYER_INSPECT)


func _floor() -> Label:
	return _e2e.hud().get_node("%ThreatFloorLabel")


func test_tap_enemy_tank_with_nothing_selected_shows_its_threat() -> void:
	await _boot(MEDIUM_TANK, TANK)
	_e2e.tap(TANK)
	await _e2e.settle()
	assert_ne(_rings(), [], "кільце танка")
	assert_true(_view(CAR_POS).is_threatened(), "броньовик на 3 — у дальності 4")
	assert_false(_view(SQUAD).is_threatened(), "загін на 6 — поза дальністю")
	assert_true(_floor().is_visible_in_tree())
	assert_eq(_floor().text, tr("hud_threat_floor"))
	assert_true(_last["is_floor"])


func test_enemy_squad_with_drones_threatens_at_5() -> void:
	await _boot(ASSAULT, ENEMY_SQUAD)
	_e2e.tap(ENEMY_SQUAD)
	await _e2e.settle()
	var id: int = _state().unit_at(ENEMY_SQUAD).id
	assert_eq(_last["drone_ring"], Targeting.reach_tiles(_state(), id, DroneCommand.RANGE))
	assert_ne(_last["drone_ring"], [])
	assert_true(_view(CAR_POS).is_threatened(), "броньовик на 5 — дрон")


func test_enemy_squad_without_drones_does_not_threaten_at_5() -> void:
	await _boot(ASSAULT, ENEMY_SQUAD, func(st: BattleState) -> void: st.unit_at(ENEMY_SQUAD).drones_left = 0)
	_e2e.tap(ENEMY_SQUAD)
	await _e2e.settle()
	assert_eq(_last["drone_ring"], [])
	assert_false(_view(CAR_POS).is_threatened())


func test_empty_tap_clears_inspection() -> void:
	await _boot(MEDIUM_TANK, TANK)
	_e2e.tap(TANK)
	await _e2e.settle()
	_e2e.tap(Vector2i(4, 0))
	await _e2e.settle()
	assert_eq(_rings(), [])
	assert_false(_view(CAR_POS).is_threatened())
	assert_false(_floor().is_visible_in_tree())


func test_own_unit_selection_shows_ring_without_floor() -> void:
	await _boot(MEDIUM_TANK, TANK)
	_e2e.tap(CAR_POS)
	await _e2e.settle()
	assert_ne(_rings(), [])
	assert_true(_view(TANK).is_threatened(), "танк на 3 — ціль броньовика")
	assert_false(_floor().is_visible_in_tree())


func test_inspection_does_not_survive_the_handover_gate() -> void:
	await _boot(MEDIUM_TANK, TANK)
	_e2e.tap(TANK)
	await _e2e.settle()
	assert_ne(_rings(), [], "передумова")
	await _e2e.end_turn()
	assert_true(_e2e.gate().is_visible_in_tree(), "гейт показано")
	assert_eq(_rings(), [])
	assert_false(_floor().is_visible_in_tree())
	await _e2e.confirm_gate()
	assert_eq(_rings(), [])
	for id: int in [_state().unit_at(CAR_POS).id, _state().unit_at(SQUAD).id]:
		var v: UnitView = _e2e.screen.unit_view_for(id)
		if v != null:
			assert_false(v.is_threatened())
