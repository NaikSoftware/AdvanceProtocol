extends GutTest
## Повтор ходів противників: після гейта гравець, що сідає, бачить, що зробили противники на
## його розвіданому, а потім починається його хід на справжньому стані.

const E2E := preload("res://tests/e2e/e2e_helpers.gd")

const MEDIUM_TANK: int = 5
const E: int = 2
const S: int = 4
const W: int = 6

var _e2e: E2E


func before_each() -> void:
	_e2e = E2E.new(self)


func after_each() -> void:
	_e2e.restore_runner_gui()
	Engine.time_scale = 1.0
	DirAccess.remove_absolute(_e2e.save_path)
	DirAccess.remove_absolute(_e2e.save_path + ".map")


func _spawn(type_id: int, owner: int, pos: Vector2i, facing: int) -> Dictionary:
	return {"type_id": type_id, "owner": owner, "pos": pos, "facing": facing}


func _overlay() -> Control:
	return _e2e.screen.get_node_or_null("%ReplayOverlay") as Control


## Крокує повтор кадр за кадром і збирає підпис такту, доки повтор не скінчиться.
func _watch_replay() -> Dictionary:
	var labels: Dictionary = {}
	for _i in 120:
		if _e2e.screen._replay_state == null:
			break
		var label: Label = _overlay().get_node("%TurnLabel") if _overlay() != null else null
		if label != null:
			labels[label.text] = true
		_e2e.step_tweens()
		await get_tree().process_frame
	return labels


func test_two_player_turn_is_replayed_after_gate() -> void:
	# Танк гравця 0 виїжджає на розвідане гравцем 1: його хід видно на повторі.
	await _e2e.boot(6, 6, [
		_spawn(MEDIUM_TANK, 0, Vector2i(1, 2), E),
		_spawn(MEDIUM_TANK, 1, Vector2i(4, 4), W),
	])
	var state: BattleState = _e2e.service.state
	var tank_id: int = state.unit_at(Vector2i(1, 2)).id
	assert_false(state.vision[1].is_seen(Vector2i(1, 2)), "передумова: танк стартує в тумані гравця 1")
	await _e2e.act(Vector2i(1, 2), Vector2i(2, 3))
	assert_eq(state.get_unit(tank_id).pos, Vector2i(2, 3), "передумова: танк доїхав")
	await _e2e.end_turn()
	assert_true(_e2e.gate().visible)

	_e2e.press(_e2e.gate().get_node("%ConfirmButton"))
	assert_false(_e2e.gate().visible)
	assert_true(_e2e.screen._replay_state != null, "після гейта йде повтор")
	assert_not_null(_overlay())
	if _overlay() == null:
		return
	assert_true(_overlay().visible)
	assert_false(_e2e.hud().visible, "HUD сховано на повторі")
	assert_true(_e2e.screen._weather.environment.adjustment_enabled, "світ під грейдом повтору")
	assert_null(_e2e.screen.unit_view_for(tank_id), "перший кадр — дошка на початку відрізка: танк ще в тумані")
	var labels: Dictionary = await _watch_replay()
	assert_true(labels.has(tr("replay_turn") % [1, 1]), "підпис такту — хід 1, гравець 1: %s" % [labels.keys()])

	await _e2e.settle()
	assert_null(_e2e.screen._replay_state)
	assert_eq(Engine.time_scale, 1.0)
	assert_true(_e2e.hud().visible)
	assert_false(_overlay().visible)
	assert_false(_e2e.screen._weather.environment.adjustment_enabled, "після повтору світ без грейду")
	var view: UnitView = _e2e.screen.unit_view_for(tank_id)
	assert_not_null(view, "після повтору танк на розвіданому видно")
	if view != null:
		assert_eq(Vector2(view.position.x, view.position.z), Vector2(2, 3))
	# Хід гравця 1 живий: його танк ходить.
	await _e2e.act(Vector2i(4, 4), Vector2i(4, 5))
	assert_eq(state.unit_at(Vector2i(4, 5)), state.units_of(1)[0], "після повтору гравець 1 ходить")


## Справжній ввід крізь оверлей: тап повз кнопку доходить до дошки й лише прискорює такт, клік по
## «Пропустити» кінчає повтор.
func test_real_tap_fast_forwards_and_skip_click_ends_replay() -> void:
	await _e2e.boot(6, 6, [
		_spawn(MEDIUM_TANK, 0, Vector2i(1, 2), E),
		_spawn(MEDIUM_TANK, 0, Vector2i(3, 5), W),
		_spawn(MEDIUM_TANK, 1, Vector2i(4, 4), W),
	])
	var state: BattleState = _e2e.service.state
	await _e2e.act(Vector2i(1, 2), Vector2i(2, 3))
	await _e2e.act(Vector2i(3, 5), Vector2i(2, 5))
	await _e2e.end_turn()
	_e2e.press(_e2e.gate().get_node("%ConfirmButton"))
	assert_true(_e2e.screen._replay_state != null, "передумова: повтор іде")
	assert_not_null(_overlay())
	if _overlay() == null:
		return
	var p1: Unit = state.units_of(1)[0]
	var taken: int = _e2e.service.events.size()
	_e2e.tap(p1.pos)
	_e2e.tap(p1.pos + Vector2i(0, 1))
	assert_eq(Engine.time_scale, BattleScreen.REPLAY_FAST_FORWARD, "тап крізь оверлей прискорює такт")
	assert_true(_e2e.screen._replay_state != null, "тап не кінчає повтор")
	assert_eq(_e2e.service.events.size(), taken, "тап на повторі не дає жодної команди")
	assert_eq(p1.pos, Vector2i(4, 4))
	var skip: Button = _overlay().get_node("%SkipButton")
	_e2e.click_at(skip.get_global_rect().get_center(), _e2e.vp)
	assert_null(_e2e.screen._replay_state, "клік по «Пропустити» кінчає повтор")
	assert_eq(Engine.time_scale, 1.0)
	assert_true(_e2e.hud().visible)
	await _e2e.settle()
	await _e2e.act(Vector2i(4, 4), Vector2i(4, 5))
	assert_eq(state.unit_at(Vector2i(4, 5)), p1, "після пропуску гравець 1 ходить")


func test_three_player_replay_shows_both_opponents() -> void:
	# Гравець 2 у центрі бачить обох: хід гравця 0 і хід гравця 1 ідуть на його повторі по черзі.
	await _e2e.boot(9, 9, [
		_spawn(MEDIUM_TANK, 0, Vector2i(4, 0), S),
		_spawn(MEDIUM_TANK, 1, Vector2i(4, 8), 0),
		_spawn(MEDIUM_TANK, 2, Vector2i(4, 4), E),
	], {"players": 3})
	var state: BattleState = _e2e.service.state
	await _e2e.act(Vector2i(4, 0), Vector2i(4, 1))
	await _e2e.end_turn()
	await _e2e.confirm_gate()
	assert_eq(state.active_player, 1)
	await _e2e.act(Vector2i(4, 8), Vector2i(4, 7))
	await _e2e.end_turn()
	assert_eq(state.active_player, 2)
	var r: ReplayFilter.Result = _e2e.service.replay_for(2)
	assert_not_null(r, "передумова: гравцеві 2 є що показати")
	if r == null:
		return
	assert_eq(r.beats.map(func(b: ReplayFilter.Beat) -> int: return b.actor), [0, 1], "передумова: обидва противники, по черзі")

	_e2e.press(_e2e.gate().get_node("%ConfirmButton"))
	assert_not_null(_overlay())
	if _overlay() == null:
		return
	var expected: Dictionary = {}
	for b in r.beats:
		expected[tr("replay_turn") % [b.turn, b.actor + 1]] = true
	var labels: Dictionary = await _watch_replay()
	assert_eq(labels.keys().size(), 2, "повтор показав обидва ходи: %s" % [labels.keys()])
	for text: String in expected:
		assert_true(labels.has(text), "такт «%s» показано" % text)
	await _e2e.settle()
	assert_null(_e2e.screen._replay_state)
	assert_eq(Engine.time_scale, 1.0)
	assert_true(_e2e.hud().visible)
