extends GutTest
## Повна партія на карті River (`res://maps/river.tres`) від першого ходу до
## повної елімінації противника — лише через справжні події вводу у viewport
## та кнопки HUD/гейта, у справжньому вікні гри з живими анімаціями руху й бою.
##
## Обидва гравці грають стратегічно по всій карті (усі три мости — східний
## понтонний x=21, центральний бетонний x=13, західний понтонний x=4) та
## використовують усі механіки гри:
## - повалення лісу танком (`Events.ForestBroken`, §3.2),
## - інженерне мінування (`LAY_MINE`), виявлення чужої міни (`Events.MineRevealed`) і
##   розмінування (`CLEAR_MINE`), підрив на міні (`Events.MineTriggered`),
##   підрив мосту з ворогом (`DEMOLISH_BRIDGE`), відбудову мосту (`REPAIR_BRIDGE`)
##   та польовий ремонт техніки (`REPAIR_UNIT`, §3.8, §3.11),
## - огляд кілець загрози довгим натиском (`long_press` / `release`, §3.13),
## - безкоштовний розворот корпусу лобовою бронею (`TurnCommand`, §3.4),
## - сковування боєм і фланговий/тиловий вогонь у `FRONT`, `SIDE` та `REAR` (§3.4),
## - ближній бій піхоти в забудові/руїнах (`×4` на `d² <= 2`, §3.3),
## - удари FPV-дронів (`%DroneButton`, §3.9) та вогонь артилерії з глибини.
##
## Ім'я файла навмисно без префікса `test_`, щоб звичайний прогін `./run_tests.sh`
## (який шукає `test_*.gd` у `res://tests`) пропускав цей довгий сценарій.
## Запуск вручну за вимогою (відкриває вікно гри і програє весь бій наживо):
##   GODOT=/home/naik/.local/bin/godot ./run_tests.sh -gtest=res://tests/e2e/full_river_e2e.gd
## Швидкий режим перегляду (`--fast` або `--speedup`, також `RIVER_E2E_SPEED=fast`):
##   GODOT=/home/naik/.local/bin/godot ./run_tests.sh --fast -gtest=res://tests/e2e/full_river_e2e.gd

const E2E := preload("res://tests/e2e/e2e_helpers.gd")
const A := EngineerCommand.Action

const SEED: int = 7
const VIEWPORT_SIZE := Vector2i(1280, 720)

var _e2e: E2E
var _prev_low_proc: bool = false
var _runner_was_visible: bool = true
var _layer_was_visible: bool = true


func _is_headless() -> bool:
	return DisplayServer.get_name() == "headless"


func _is_fast() -> bool:
	var mode: String = OS.get_environment("RIVER_E2E_SPEED").to_lower()
	return mode == "fast" or mode == "speedup"


func before_each() -> void:
	_prev_low_proc = OS.low_processor_usage_mode
	if not _is_headless():
		OS.low_processor_usage_mode = false
		get_window().size = VIEWPORT_SIZE
	var runner: CanvasItem = get_tree().root.get_node_or_null("GutRunner") as CanvasItem
	if runner != null:
		_runner_was_visible = runner.visible
		runner.visible = false
		var layer: CanvasLayer = runner.get_node_or_null("GutLayer") as CanvasLayer
		if layer != null:
			_layer_was_visible = layer.visible
			layer.visible = false
	_e2e = E2E.new(self)


func after_each() -> void:
	OS.low_processor_usage_mode = _prev_low_proc
	var runner: CanvasItem = get_tree().root.get_node_or_null("GutRunner") as CanvasItem
	if runner != null:
		runner.visible = _runner_was_visible
		var layer: CanvasLayer = runner.get_node_or_null("GutLayer") as CanvasLayer
		if layer != null:
			layer.visible = _layer_was_visible
	_e2e.restore_runner_gui()
	DirAccess.remove_absolute(_e2e.save_path)
	DirAccess.remove_absolute(_e2e.save_path + ".map")


func _state() -> BattleState:
	return _e2e.service.state


func _unit(id: int) -> Unit:
	return _state().get_unit(id)


func _rig() -> IsoCameraRig:
	return _e2e.screen.get_node("%CameraRig")


func _board_view() -> BoardView:
	return _e2e.screen.get_node("%BoardView")


## Чекає завершення EventPlayer у реальному часі без step_tweens(), щоб у вікні
## було видно справжній рух тайл за тайлом, повороти башт, постріли й вибухи.
func _wait_idle(max_seconds: float = 15.0) -> void:
	if _is_headless():
		await _e2e.settle()
		return
	var deadline: int = Time.get_ticks_msec() + int(max_seconds * 1000.0)
	await get_tree().process_frame
	while _e2e.screen._event_player.is_playing():
		if Time.get_ticks_msec() > deadline:
			fail_test("не дочекались завершення анімації подій")
			return
		await get_tree().process_frame


func _pause(normal_sec: float, fast_sec: float) -> void:
	if _is_headless():
		return
	var sec: float = fast_sec if _is_fast() else normal_sec
	await get_tree().create_timer(sec).timeout


## У звичайному режимі (`normal`) плавно веде камеру через `fly_to(cell)`, щоб
## око глядача встигало за переміщенням між мостами; у `--fast` або `--headless`
## центрує камеру миттєво.
func _focus_camera(cell: Vector2i) -> void:
	var rig: IsoCameraRig = _rig()
	if _is_headless() or _is_fast():
		rig.center_on(cell)
		return
	var target: Vector3 = IsoCameraRig.cell_to_world(cell)
	if (rig.global_position - target).length() > 0.05:
		var tw: Tween = rig.fly_to(cell)
		if tw != null and tw.is_valid():
			await tw.finished
	rig.center_on(cell)


func _confirm_action() -> void:
	_e2e.press(_e2e.hud().get_node("%ConfirmButton"))
	await _wait_idle()
	await _pause(0.25, 0.05)


func _select(u: Unit) -> void:
	var ctl: InputController = _e2e.screen.input_controller()
	if ctl._selected_unit != u:
		await _focus_camera(u.pos)
		await _pause(0.15, 0.05)
		_e2e.tap(u.pos)
		await _pause(0.45, 0.06)
	assert_eq(ctl._selected_unit, u, "вибрано юніт #%d на %s" % [u.id, u.pos])


func _move(u: Unit, to: Vector2i) -> void:
	await _select(u)
	await _focus_camera(to)
	await _pause(0.15, 0.05)
	_e2e.tap(to)
	await _pause(0.55, 0.08)
	await _confirm_action()


func _turn_towards(u: Unit, look_at_cell: Vector2i) -> void:
	await _select(u)
	await _focus_camera(look_at_cell)
	await _pause(0.15, 0.05)
	_e2e.tap(look_at_cell)
	await _wait_idle()
	await _pause(0.25, 0.06)


func _inspect_threat(cell: Vector2i, expected_rings: int = 1) -> void:
	await _focus_camera(cell)
	await _pause(0.15, 0.05)
	_e2e.long_press(cell)
	assert_eq(_board_view().circles(BoardView.LAYER_INSPECT).size(), expected_rings,
		"довгий натиск показав кільця загрози на %s" % cell)
	if expected_rings >= 2:
		var floor_lbl: Control = _e2e.hud().get_node("%ThreatFloorLabel")
		assert_true(floor_lbl.is_visible_in_tree(), "підпис мінімальної загрози видимий під час огляду")
	await _pause(0.70, 0.16)
	_e2e.release(cell)
	await _wait_idle()
	assert_eq(_board_view().circles(BoardView.LAYER_INSPECT), [], "відпускання зняло кільця огляду")
	await _pause(0.20, 0.05)


func _fire(u: Unit, target: Unit) -> void:
	await _select(u)
	await _focus_camera(target.pos)
	await _pause(0.15, 0.05)
	_e2e.tap(target.pos)
	await _pause(0.55, 0.10)
	await _confirm_action()


func _drone(u: Unit, target: Unit) -> void:
	await _select(u)
	var btn: DroneButton = _e2e.hud().get_node("%DroneButton")
	_e2e.press(btn)
	await _wait_idle()
	await _pause(0.40, 0.08)
	await _focus_camera(target.pos)
	await _pause(0.15, 0.05)
	_e2e.tap(target.pos)
	await _pause(0.55, 0.10)
	await _confirm_action()


func _engineer(u: Unit, action: int, to: Vector2i) -> void:
	await _select(u)
	_e2e.press(_e2e.engineer_panel().button_for(action))
	await _wait_idle()
	await _pause(0.40, 0.08)
	await _focus_camera(to)
	await _pause(0.15, 0.05)
	_e2e.tap(to)
	if action == A.LAY_MINE:
		await _wait_idle()
		await _pause(0.25, 0.06)
	else:
		await _pause(0.55, 0.10)
		await _confirm_action()


func _pass_turn() -> void:
	var prev_player: int = _state().active_player
	_e2e.press(_e2e.hud().get_node("%EndTurnButton"))
	await _wait_idle()
	assert_true(_e2e.gate().visible, "гейт передачі ходу видимий після EndTurn")
	assert_ne(_state().active_player, prev_player, "активний гравець змінився")
	await _pause(0.65, 0.14)
	_e2e.press(_e2e.gate().get_node("%ConfirmButton"))
	await _wait_idle()
	assert_false(_e2e.gate().visible, "гейт сховано після підтвердження")
	await _pause(0.25, 0.06)


func test_full_river_game_to_elimination() -> void:
	await _e2e.boot(0, 0, [], {
		"map_path": "res://maps/river.tres",
		"seed": SEED,
	})
	watch_signals(_e2e.screen)

	var st: BattleState = _state()
	assert_eq(st.board.width, 26)
	assert_eq(st.board.height, 22)
	assert_eq(st.board.ground_state, Terrain.GroundState.MUD)
	assert_eq(st.units_of(0).size(), 6)
	assert_eq(st.units_of(1).size(), 6)

	# --- P0 юніти ---
	var p0_rifle: Unit = _unit(1)     # (17, 19)
	var p0_assault: Unit = _unit(3)   # (18, 20)
	var p0_car: Unit = _unit(5)       # (19, 19)
	var p0_tank: Unit = _unit(7)      # (20, 20)
	var p0_gun: Unit = _unit(9)       # (21, 20)
	var p0_eng: Unit = _unit(11)      # (19, 21)

	# --- P1 юніти ---
	var p1_rifle: Unit = _unit(2)     # (8, 2)
	var p1_assault: Unit = _unit(4)   # (7, 1)
	var p1_car: Unit = _unit(6)       # (6, 2)
	var p1_tank: Unit = _unit(8)      # (5, 1)
	var p1_gun: Unit = _unit(10)      # (4, 1)
	var p1_eng: Unit = _unit(12)      # (6, 0)

	# === РАУНД 1: розходження на три оперативні напрямки ======================
	# P0 відправляє броньовик на східний понтонний міст (x=21), а головні сили —
	# до центрального вузла. P1 симетрично кидає свій броньовик на західний
	# понтонний міст (x=4), ведучи ударну групу до центру (x=13).
	assert_eq(st.turn_number, 1)
	assert_eq(st.active_player, 0)

	await _move(p0_car, Vector2i(21, 15))
	await _move(p0_rifle, Vector2i(15, 18))
	await _move(p0_eng, Vector2i(17, 18))
	await _move(p0_tank, Vector2i(18, 18))
	await _move(p0_assault, Vector2i(16, 19))
	await _move(p0_gun, Vector2i(21, 19))
	await _pass_turn()

	assert_eq(st.turn_number, 1)
	assert_eq(st.active_player, 1)

	await _move(p1_car, Vector2i(4, 6))
	await _move(p1_rifle, Vector2i(10, 3))
	await _move(p1_eng, Vector2i(8, 3))
	await _move(p1_tank, Vector2i(7, 3))
	await _move(p1_assault, Vector2i(9, 2))
	await _move(p1_gun, Vector2i(4, 2))
	await _pass_turn()

	# === РАУНД 2: форсування СХІДНОГО (x=21) та ЗАХІДНОГО (x=4) мостів ========
	assert_eq(st.turn_number, 2)
	assert_eq(st.active_player, 0)

	await _move(p0_car, Vector2i(21, 9))
	assert_eq(p0_car.pos, Vector2i(21, 9), "броньовик P0 перетнув східний міст (21,11)->(21,10)")
	await _move(p0_rifle, Vector2i(13, 17))
	await _move(p0_eng, Vector2i(13, 18))
	await _move(p0_assault, Vector2i(14, 18))
	await _move(p0_tank, Vector2i(15, 18))
	await _move(p0_gun, Vector2i(20, 18))
	await _pass_turn()

	assert_eq(st.turn_number, 2)
	assert_eq(st.active_player, 1)

	await _move(p1_car, Vector2i(4, 12))
	assert_eq(p1_car.pos, Vector2i(4, 12), "броньовик P1 перетнув західний міст (4,10)->(4,11)")
	await _move(p1_rifle, Vector2i(13, 3))
	await _move(p1_eng, Vector2i(12, 3))
	await _move(p1_tank, Vector2i(11, 3))
	await _move(p1_assault, Vector2i(10, 3))
	await _move(p1_gun, Vector2i(5, 3))
	await _pass_turn()

	# === РАУНД 3: вихід рейдерів у тил і прокладання просіки танком P1 ========
	assert_eq(st.turn_number, 3)
	assert_eq(st.active_player, 0)

	await _move(p0_car, Vector2i(19, 5))
	await _move(p0_rifle, Vector2i(11, 16))
	await _move(p0_eng, Vector2i(13, 16))
	await _move(p0_assault, Vector2i(13, 17))
	await _move(p0_tank, Vector2i(13, 18))
	await _move(p0_gun, Vector2i(18, 18))
	await _pass_turn()

	assert_eq(st.turn_number, 3)
	assert_eq(st.active_player, 1)

	await _move(p1_car, Vector2i(6, 16))
	await _move(p1_rifle, Vector2i(14, 5))
	await _move(p1_eng, Vector2i(13, 7))
	# Танк P1 виходить на (13,3) і валить ліс на (13,2) (§3.2 ForestBroken).
	await _move(p1_tank, Vector2i(13, 2))
	assert_true(st.broken_forest.has(Vector2i(13, 2)), "танк P1 повалив ліс на (13,2)")
	assert_eq(_e2e.events_of(Events.ForestBroken).size(), 1)
	await _move(p1_assault, Vector2i(13, 3))
	await _move(p1_gun, Vector2i(7, 3))
	await _pass_turn()

	# === РАУНД 4: пастка P0 на шосе y=16, рейд P0 по y=5 і контратака P1 ======
	assert_eq(st.turn_number, 4)
	assert_eq(st.active_player, 0)

	# Броньовик P0 зі східного мосту вривається в тил P1 на (15,5) і б'є по стрільцях P1.
	await _move(p0_car, Vector2i(15, 5))
	await _fire(p0_car, p1_rifle)
	assert_eq(p1_rifle.hp, 44)

	# На півдні P0 готує мінний мішок на (11,16) для західного рейдера P1:
	# стрільці займають позицію в міських руїнах (RUBBLE) на (11,14), інженер мінує (11,16),
	# а танк стає на (12,18) і безкоштовно розвертає лобову броню на північний захід (TurnCommand, 0 AP).
	await _move(p0_rifle, Vector2i(11, 14))
	assert_eq(st.board.kind_at(p0_rifle.pos), Terrain.Kind.RUBBLE, "піхота P0 зайняла руїни в місті")
	await _move(p0_eng, Vector2i(12, 16))
	await _engineer(p0_eng, A.LAY_MINE, Vector2i(11, 16))
	assert_eq(st.mines.size(), 1)
	assert_eq(st.mines[0].pos, Vector2i(11, 16))
	await _move(p0_tank, Vector2i(12, 18))
	var tank_ap_before_turn: int = p0_tank.ap
	await _turn_towards(p0_tank, Vector2i(11, 16))
	assert_eq(p0_tank.ap, tank_ap_before_turn, "розворот корпусу TurnCommand безкоштовний")
	assert_eq(p0_tank.facing, 7, "танк P0 розвернувся лобом на північний захід до (11,16)")
	await _move(p0_gun, Vector2i(16, 18))
	await _pass_turn()

	assert_eq(st.turn_number, 4)
	assert_eq(st.active_player, 1)

	# P1 довгим натиском перевіряє радіус гармати рейдера p0_car на (15,5),
	# після чого знищує його комбінованим ударом піхоти впритул (×4), FPV-дрона й танка!
	await _inspect_threat(p0_car.pos, 1)
	await _fire(p1_rifle, p0_car)
	assert_eq(p0_car.hp, 201, "піхота P1 впритул (d²=1) завдала ×4 шкоди броньовику P0")
	await _move(p1_assault, Vector2i(14, 4))
	await _drone(p1_assault, p0_car)
	assert_eq(p0_car.hp, 47)
	await _move(p1_tank, Vector2i(13, 4))
	await _fire(p1_tank, p0_car)
	assert_false(p0_car.is_alive(), "P1 знищив східний рейдер P0 на (15,5)")

	# Інженер P1 виходить на центральний міст (13,10) і мінує південний прогін (13,11).
	await _move(p1_eng, Vector2i(13, 10))
	await _engineer(p1_eng, A.LAY_MINE, Vector2i(13, 11))
	assert_eq(st.mines.size(), 2)

	# Західний рейдер p1_car мчить по шосе y=16 у тил P0 і підривається на міні (11,16)!
	await _move(p1_car, Vector2i(11, 16))
	assert_eq(_e2e.events_of(Events.MineTriggered).size(), 1)
	assert_eq(p1_car.hp, 82)
	await _move(p1_gun, Vector2i(9, 3))
	await _pass_turn()

	# === РАУНД 5: виявлення міни P1 та Pin-and-Flank (FRONT/SIDE/REAR) ========
	assert_eq(st.turn_number, 5)
	assert_eq(st.active_player, 0)

	# Інженер P0 першим проходить вільним шосе на (13,13) і виявляє міну P1 на мосту (13,11)!
	await _move(p0_eng, Vector2i(13, 13))
	assert_true(Mines.is_known(st, Vector2i(13, 11), 0), "інженер P0 виявив міну P1 на мосту (13,11)")
	assert_eq(_e2e.events_of(Events.MineRevealed).size(), 1)

	# 1) Pin (FRONT): штурмовики P0 виходять на (13,15) і сковують p1_car з фронту; той відповідає й повертається NE (1).
	await _move(p0_assault, Vector2i(13, 15))
	await _fire(p0_assault, p1_car)
	assert_eq(p1_car.facing, 1, "p1_car розвернувся на північний схід до штурмовиків P0")
	# 2) Flank (SIDE): стрільці P0 з міських руїн (11,14) б'ють у лівий борт (SIDE), розвертаючи p1_car на північ (0).
	await _fire(p0_rifle, p1_car)
	assert_eq(p1_car.facing, 0, "p1_car розвернувся на північ до стрільців P0")
	assert_eq(p1_car.hp, 57)
	# 3) Rear Kill (REAR): танк P0 з (12,18) добиває p1_car пострілом у відкриту корму (REAR)!
	await _fire(p0_tank, p1_car)
	assert_false(p1_car.is_alive(), "танк P0 добив p1_car пострілом у корму (REAR)")

	await _move(p0_gun, Vector2i(14, 18))
	await _pass_turn()

	assert_eq(st.turn_number, 5)
	assert_eq(st.active_player, 1)

	await _move(p1_eng, Vector2i(12, 8))
	await _move(p1_tank, Vector2i(13, 8))
	await _move(p1_assault, Vector2i(13, 6))
	await _move(p1_rifle, Vector2i(13, 5))
	await _move(p1_gun, Vector2i(11, 3))
	await _pass_turn()

	# === РАУНД 6: розмінування мосту (CLEAR_MINE) та удар FPV-дроном P0 =======
	assert_eq(st.turn_number, 6)
	assert_eq(st.active_player, 0)

	await _move(p0_eng, Vector2i(13, 12))
	await _engineer(p0_eng, A.CLEAR_MINE, Vector2i(13, 11))
	assert_eq(st.mines.size(), 0, "інженер P0 розмінував центральний міст (13,11)")
	assert_eq(_e2e.events_of(Events.MineCleared).size(), 1)

	await _move(p0_assault, Vector2i(13, 13))
	await _drone(p0_assault, p1_tank)
	assert_eq(p1_tank.hp, 220)
	await _move(p0_rifle, Vector2i(13, 14))
	await _move(p0_tank, Vector2i(13, 15))
	await _move(p0_gun, Vector2i(13, 17))
	await _pass_turn()

	assert_eq(st.turn_number, 6)
	assert_eq(st.active_player, 1)

	await _move(p1_tank, Vector2i(13, 11))
	await _move(p1_assault, Vector2i(13, 9))
	await _move(p1_rifle, Vector2i(13, 8))
	await _move(p1_gun, Vector2i(13, 3))
	await _pass_turn()

	# === РАУНД 7: огляд 2 кілець загрози, удар дрона й бій за міст ============
	assert_eq(st.turn_number, 7)
	assert_eq(st.active_player, 0)

	# Довгий натиск по штурмовиках P1 на (13,9) показує 2 кільця (гармата + дрон) і підпис!
	await _inspect_threat(p1_assault.pos, 2)
	await _move(p0_assault, Vector2i(14, 12))
	await _drone(p0_assault, p1_tank)
	assert_eq(p1_tank.hp, 89)
	await _move(p0_rifle, Vector2i(14, 13))
	await _fire(p0_rifle, p1_tank)
	assert_eq(p1_tank.hp, 76)
	await _move(p0_tank, Vector2i(13, 13))
	await _fire(p0_tank, p1_assault)
	assert_eq(p1_assault.hp, 78)
	await _move(p0_gun, Vector2i(13, 15))
	await _pass_turn()

	assert_eq(st.turn_number, 7)
	assert_eq(st.active_player, 1)

	await _fire(p1_tank, p0_tank)
	await _move(p1_assault, Vector2i(13, 10))
	await _drone(p1_assault, p0_tank)
	assert_eq(p0_tank.hp, 207)
	await _move(p1_rifle, Vector2i(13, 9))
	await _move(p1_gun, Vector2i(13, 5))
	await _pass_turn()

	# === РАУНД 8: підрив мосту з танком P1 (DEMOLISH_BRIDGE) ==================
	assert_eq(st.turn_number, 8)
	assert_eq(st.active_player, 0)

	await _engineer(p0_eng, A.DEMOLISH_BRIDGE, Vector2i(13, 11))
	assert_false(p1_tank.is_alive(), "танк P1 скинутий у річку підривом мосту")
	assert_eq(st.board.kind_at(Vector2i(13, 11)), Terrain.Kind.BRIDGE_DESTROYED)
	await _fire(p0_assault, p1_assault)
	await _fire(p0_tank, p1_assault)
	await _move(p0_gun, Vector2i(13, 14))
	await _fire(p0_gun, p1_assault)
	assert_false(p1_assault.is_alive(), "штурмовики P1 знищені на (13,10)")
	await _pass_turn()

	assert_eq(st.turn_number, 8)
	assert_eq(st.active_player, 1)

	await _move(p1_rifle, Vector2i(13, 10))
	await _fire(p1_rifle, p0_eng)
	await _move(p1_eng, Vector2i(13, 8))
	await _move(p1_gun, Vector2i(13, 7))
	await _pass_turn()

	# === РАУНД 9: польовий ремонт танка (REPAIR_UNIT) та вогонь через річку ===
	assert_eq(st.turn_number, 9)
	assert_eq(st.active_player, 0)

	var tank_hp_before_repair: int = p0_tank.hp
	await _engineer(p0_eng, A.REPAIR_UNIT, Vector2i(13, 13))
	assert_gt(p0_tank.hp, tank_hp_before_repair, "інженер P0 відремонтував пошкоджений танк P0")
	assert_eq(_e2e.events_of(Events.UnitRepaired).size(), 1)
	await _fire(p0_assault, p1_rifle)
	await _fire(p0_tank, p1_rifle)
	await _fire(p0_gun, p1_rifle)
	assert_false(p1_rifle.is_alive(), "стрільці P1 знищені на (13,10)")
	await _pass_turn()

	assert_eq(st.turn_number, 9)
	assert_eq(st.active_player, 1)

	await _move(p1_eng, Vector2i(13, 10))
	await _move(p1_gun, Vector2i(13, 9))
	await _pass_turn()

	# === РАУНД 10: відбудова мосту (REPAIR_BRIDGE) та вогонь по колоні P1 =====
	assert_eq(st.turn_number, 10)
	assert_eq(st.active_player, 0)

	await _engineer(p0_eng, A.REPAIR_BRIDGE, Vector2i(13, 11))
	assert_eq(st.board.kind_at(Vector2i(13, 11)), Terrain.Kind.BRIDGE)
	await _fire(p0_assault, p1_eng)
	await _fire(p0_tank, p1_eng)
	await _fire(p0_gun, p1_eng)
	assert_false(p1_eng.is_alive(), "інженер P1 знищений на (13,10)")
	await _pass_turn()

	assert_eq(st.turn_number, 10)
	assert_eq(st.active_player, 1)

	await _fire(p1_gun, p0_tank)
	await _pass_turn()

	# === РАУНД 11: фінальний залп і повна перемога P0 =========================
	assert_eq(st.turn_number, 11)
	assert_eq(st.active_player, 0)

	await _fire(p0_tank, p1_gun)
	await _fire(p0_gun, p1_gun)
	assert_false(p1_gun.is_alive(), "останній юніт P1 (польова гармата) знищений")

	# Перевіряємо повний набір стратегічних механік і фінал матчу:
	assert_true(st.is_over(), "матч завершився повною елімінацією P1")
	assert_eq(st.winner, 0, "переможець — Гравець 0")
	assert_eq(st.units_of(1).size(), 0, "у P1 не залишилось живих юнітів")
	assert_eq(st.units_of(0).size(), 5, "у P0 вижили 5 із 6 юнітів після рейду на східний міст")
	assert_signal_emitted(_e2e.screen, "match_finished")

	assert_eq(_e2e.events_of(Events.ForestBroken).size(), 1, "танк повалив ліс")
	assert_eq(_e2e.events_of(Events.MineRevealed).size(), 1, "інженер виявив ворожу міну")
	assert_eq(_e2e.events_of(Events.MineCleared).size(), 1, "інженер розмінував міст")
	assert_eq(_e2e.events_of(Events.MineTriggered).size(), 1, "ворожий рейдер підірвався на міні")
	assert_eq(_e2e.events_of(Events.BridgeChanged).size(), 2, "міст підірвано і відбудовано")
	assert_eq(_e2e.events_of(Events.UnitRepaired).size(), 1, "інженер відремонтував танк")
	assert_eq(_e2e.events_of(Events.DroneLaunched).size(), 4, "обидві сторони використали всі 4 FPV-дрони")
	assert_gt(_e2e.events_of(Events.UnitTurned).size(), 0, "відпрацьовано розвороти корпусу")
	assert_gt(_e2e.events_of(Events.ShotRetaliated).size(), 0, "відпрацьовано вогонь у відповідь")
	assert_eq(_e2e.events_of(Events.UnitDestroyed).size(), 7, "знищено 1 юніт P0 та всі 6 юнітів P1")

	var sectors: Dictionary = {}
	for ev: Events.BattleEvent in _e2e.events_of(Events.ShotFired):
		sectors[(ev as Events.ShotFired).sector] = true
	assert_true(sectors.has(UnitTypes.ArmourSector.FRONT), "були постріли в лобову броню (FRONT)")
	assert_true(sectors.has(UnitTypes.ArmourSector.SIDE), "були флангові постріли в борт (SIDE)")
	assert_true(sectors.has(UnitTypes.ArmourSector.REAR), "були постріли в корму (REAR)")

	await _pause(2.0, 0.4)
