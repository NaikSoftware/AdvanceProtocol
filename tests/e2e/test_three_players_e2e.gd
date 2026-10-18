extends GutTest
## Task 4.12: матч на трьох. Вибулий гравець випадає з черги ходів, гейт називає
## наступного живого, а матч триває між двома, що лишились. І карта на трьох,
## зіграна вдвох, стартує без юнітів третього (рішення власника — пропуск спавнів).

const E2E := preload("res://tests/e2e/e2e_helpers.gd")

const RIFLE: int = 0
const HEAVY_TANK: int = 8
const N: int = 0
const E: int = 2
const W: int = 6

var _e2e: E2E


func before_each() -> void:
	_e2e = E2E.new(self)


func after_each() -> void:
	_e2e.restore_runner_gui()
	DirAccess.remove_absolute(_e2e.save_path)
	DirAccess.remove_absolute(_e2e.save_path + ".map")


func _spawn(type_id: int, owner: int, pos: Vector2i, facing: int) -> Dictionary:
	return {"type_id": type_id, "owner": owner, "pos": pos, "facing": facing}


func _gate_player() -> String:
	return (_e2e.gate().get_node("%PlayerValue") as Label).text


## Гравець 1 — один стрілець упритул до важкого танка гравця 0, з 10 HP:
## мінімальна шкода 10 (§3.3) добиває його першим же пострілом, без відповіді.
func _boot_and_eliminate_p1() -> void:
	await _e2e.boot(10, 6, [
		_spawn(HEAVY_TANK, 0, Vector2i(2, 2), E),
		_spawn(RIFLE, 1, Vector2i(3, 2), W),
		_spawn(RIFLE, 2, Vector2i(9, 5), N),
	], {"players": 3, "prepare": func(s: BattleState) -> void: s.get_unit(2).hp = 10})
	await _e2e.act(Vector2i(2, 2), Vector2i(3, 2))


func test_eliminated_player_is_skipped_and_gate_names_next() -> void:
	await _boot_and_eliminate_p1()
	var out: Array[Events.BattleEvent] = _e2e.events_of(Events.PlayerEliminated)
	assert_eq(out.size(), 1)
	if out.size() == 1:
		assert_eq((out[0] as Events.PlayerEliminated).player, 1)

	await _e2e.end_turn()
	assert_true(_e2e.gate().visible)
	assert_eq(_gate_player(), "3", "гравець 2 вибув — хід переходить до третього")
	assert_eq(_e2e.service.state.active_player, 2)

	await _e2e.confirm_gate()
	await _e2e.end_turn()
	assert_eq(_gate_player(), "1")
	assert_eq(_e2e.service.state.active_player, 0)
	assert_false(_e2e.service.state.is_over())


func test_match_continues_between_remaining_two() -> void:
	await _boot_and_eliminate_p1()
	var state: BattleState = _e2e.service.state
	assert_eq(state.eliminated, [false, true, false] as Array[bool])
	assert_eq(state.winner, BattleState.NO_WINNER)
	assert_eq(state.winner, -1)
	assert_eq(_e2e.events_of(Events.MatchEnded).size(), 0)


func test_three_player_map_runs_with_two_players() -> void:
	var map: MapData = load("res://tests/fixtures/three_player_map.tres") as MapData
	assert_true(MatchSetup.map_supports(map, 3), "передумова: карта розрахована на трьох")
	_e2e.service = E2E.RecService.new()
	add_child_autofree(_e2e.service)
	_e2e.screen = E2E.BattleScreenScene.instantiate()
	add_child_autofree(_e2e.screen)
	_e2e.screen.save_path = _e2e.save_path
	assert_true(_e2e.screen.setup(map, 2, 7, _e2e.service))
	_e2e.ignore_runner_gui([_e2e.screen])
	await _e2e.settle()

	var state: BattleState = _e2e.service.state
	var owners: Dictionary = {}
	for u in state.alive_units():
		owners[u.owner] = true
	assert_eq(owners.keys().size(), 2, "лише два власники")
	assert_false(owners.has(2), "юнітів третього гравця на дошці немає")
	assert_eq(state.units_of(0).size(), 6)
	assert_eq(state.units_of(1).size(), 6)
	assert_false(state.is_over())

	await _e2e.end_turn()
	assert_eq(_gate_player(), "2")
	await _e2e.confirm_gate()
	await _e2e.end_turn()
	assert_eq(_gate_player(), "1", "коло на двох, без третього")
