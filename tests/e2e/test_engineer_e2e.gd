extends GutTest
## Task 8: кожна з п'яти верб інженера (верби цілей прибрано — рішення власника) наскрізно — справжні тапи по дошці й кнопки
## панелі HUD, перевірки на MatchService.state.

const E2E := preload("res://tests/e2e/e2e_helpers.gd")
const A := EngineerCommand.Action

const RIFLE: int = 0
const MEDIUM_TANK: int = 5
const ENGINEER: int = 11
const E: int = 2

const ENG := Vector2i(2, 1)
const TARGET := Vector2i(3, 1)
## Далекий юніт P1: живий противник, щоб жодна дія не закінчила матч.
const FAR := Vector2i(9, 2)

var _e2e: E2E


func before_each() -> void:
	_e2e = E2E.new(self)


func after_each() -> void:
	_e2e.restore_runner_gui()
	DirAccess.remove_absolute(_e2e.save_path)
	DirAccess.remove_absolute(_e2e.save_path + ".map")


func _spawn(type_id: int, owner: int, pos: Vector2i) -> Dictionary:
	return {"type_id": type_id, "owner": owner, "pos": pos, "facing": E}


func _boot(extra: Array = [], opts: Dictionary = {}) -> void:
	var spawns: Array = [_spawn(ENGINEER, 0, ENG), _spawn(RIFLE, 1, FAR)]
	spawns.append_array(extra)
	await _e2e.boot(10, 3, spawns, opts)


func _state() -> BattleState:
	return _e2e.service.state


func _eng() -> Unit:
	return _state().unit_at(ENG)


## Повне коло до того самого гравця (2 гравці).
func _next_own_turn() -> void:
	await _e2e.end_turn()
	await _e2e.confirm_gate()
	await _e2e.end_turn()
	await _e2e.confirm_gate()
	assert_eq(_state().active_player, 0)


func _board_view() -> BoardView:
	return _e2e.screen.get_node("%BoardView")


func test_lay_and_clear_mine() -> void:
	await _boot()
	await _e2e.engineer_act(ENG, A.LAY_MINE, TARGET)
	assert_eq(_state().mines.size(), 1)
	assert_eq(_state().mines[0].pos, TARGET)
	assert_eq(_eng().ap, 0)
	await _next_own_turn()
	await _e2e.engineer_act(ENG, A.CLEAR_MINE, TARGET)
	assert_eq(_state().mines.size(), 0)
	assert_eq(_eng().ap, 0)


func test_demolish_bridge_with_enemy_on_it() -> void:
	await _boot([_spawn(RIFLE, 1, TARGET)], {"tiles": {TARGET: Terrain.Kind.BRIDGE}})
	var victim: Unit = _state().unit_at(TARGET)
	await _e2e.engineer_act(ENG, A.DEMOLISH_BRIDGE, TARGET)
	assert_eq(_state().board.kind_at(TARGET), Terrain.Kind.BRIDGE_DESTROYED)
	assert_false(victim.is_alive())
	assert_eq(_state().damage_dealt[0], 100)
	assert_eq(_board_view().kind_at(TARGET), Terrain.Kind.BRIDGE_DESTROYED, "дошку перебудовано на BridgeChanged")
	assert_eq(_e2e.events_of(Events.BridgeChanged).size(), 1)


## Міст — перший сусід у порядку DIRS_4 (вгору поза дошкою, далі праворуч), тож
## причина відмови — саме його.
func test_demolish_refused_with_own_unit_on_bridge() -> void:
	var eng_pos := Vector2i(2, 0)
	var bridge := Vector2i(3, 0)
	await _e2e.boot(10, 3, [_spawn(ENGINEER, 0, eng_pos), _spawn(RIFLE, 0, bridge), _spawn(RIFLE, 1, FAR)],
		{"tiles": {bridge: Terrain.Kind.BRIDGE}})
	var eng: Unit = _state().unit_at(eng_pos)
	_e2e.tap(eng_pos)
	_e2e.press(_e2e.engineer_panel().button_for(A.DEMOLISH_BRIDGE))
	await _e2e.settle()
	assert_eq((_e2e.engineer_panel().get_node("%ReasonLabel") as Label).text, tr("ERR_TILE_OCCUPIED"))
	assert_eq(_board_view().contour_segments(BoardView.LAYER_TARGETS), [], "нічого не озброєно")
	assert_eq(_state().board.kind_at(bridge), Terrain.Kind.BRIDGE)
	assert_eq(eng.ap, 76)
	assert_false(eng.has_fired)
	assert_true(_state().unit_at(bridge).is_alive())


func test_repair_bridge() -> void:
	await _boot([], {"tiles": {TARGET: Terrain.Kind.BRIDGE_DESTROYED}})
	await _e2e.engineer_act(ENG, A.REPAIR_BRIDGE, TARGET)
	assert_eq(_state().board.kind_at(TARGET), Terrain.Kind.BRIDGE)
	assert_eq(_board_view().kind_at(TARGET), Terrain.Kind.BRIDGE)
	assert_eq(_eng().ap, 0)


## Golden: seed 7, повний AP інженера.
func test_repair_unit_heals_within_bounds() -> void:
	await _boot([_spawn(MEDIUM_TANK, 0, TARGET)],
		{"prepare": func(st: BattleState) -> void: st.unit_at(TARGET).hp = 300})
	var tank: Unit = _state().unit_at(TARGET)
	await _e2e.engineer_act(ENG, A.REPAIR_UNIT, TARGET)
	var repaired: Array[Events.BattleEvent] = _e2e.events_of(Events.UnitRepaired)
	assert_eq(repaired.size(), 1)
	# Seed 7, перший кидок матчу: randi_range(0, 76 - 30) = 1 → (40 + 1) / 2 = 20;
	# межі T9 для повного AP — [20, 43]. Точні межі прев'ю — Task 9.
	assert_eq((repaired[0] as Events.UnitRepaired).amount, 20)
	assert_eq(tank.hp, 320)
	assert_eq((repaired[0] as Events.UnitRepaired).hp_left, 320)


func test_engineer_buttons_hidden_for_non_engineer() -> void:
	await _boot([_spawn(MEDIUM_TANK, 0, Vector2i(2, 2))])
	var panel: EngineerPanel = _e2e.engineer_panel()
	assert_false(panel.is_visible_in_tree(), "нічого не вибрано")
	_e2e.tap(Vector2i(2, 2))
	await _e2e.settle()
	assert_false(panel.is_visible_in_tree(), "танк — не інженер")
	_e2e.tap(ENG)
	await _e2e.settle()
	assert_true(panel.is_visible_in_tree())
