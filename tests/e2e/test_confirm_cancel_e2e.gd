extends GutTest
## Плейтест власника: повторний тап по цілі руху підтверджує його, а «Скасувати»
## видно лише тоді, коли натиск щось робить. Справжні тапи по дошці й кнопках HUD.

const E2E := preload("res://tests/e2e/e2e_helpers.gd")

const RIFLE: int = 0
const ASSAULT: int = 1
const MEDIUM_TANK: int = 5
const E: int = 2

const TANK := Vector2i(1, 1)
const SQUAD := Vector2i(1, 3)
const ENEMY := Vector2i(4, 1)  # 3 від танка — у дальності пострілу
const DEST := Vector2i(2, 1)

var _e2e: E2E


func before_each() -> void:
	_e2e = E2E.new(self)


func after_each() -> void:
	_e2e.restore_runner_gui()
	DirAccess.remove_absolute(_e2e.save_path)
	DirAccess.remove_absolute(_e2e.save_path + ".map")


func _spawn(type_id: int, owner: int, pos: Vector2i) -> Dictionary:
	return {"type_id": type_id, "owner": owner, "pos": pos, "facing": E}


func _boot() -> void:
	await _e2e.boot(10, 5, [_spawn(MEDIUM_TANK, 0, TANK), _spawn(ASSAULT, 0, SQUAD), _spawn(MEDIUM_TANK, 1, ENEMY)],
		{"prepare": func(st: BattleState) -> void:
			for pl in st.player_count:
				st.vision[pl].seen.fill(1)})


func _tap(cell: Vector2i) -> void:
	_e2e.tap(cell)
	await _e2e.settle()


func _cancel() -> Button:
	return _e2e.hud().get_node("%CancelButton")


func test_second_tap_on_move_target_confirms_the_move() -> void:
	await _boot()
	var tank: Unit = _e2e.service.state.unit_at(TANK)
	await _tap(TANK)
	await _tap(DEST)
	var ap_left: String = (_e2e.hud().get_node("%PreviewApValue") as Label).text
	assert_eq(tank.pos, TANK, "перший тап лише показує шлях")
	await _tap(DEST)
	assert_eq(tank.pos, DEST)
	assert_eq(str(tank.ap), ap_left, "AP — рівно той, що показало прев'ю")
	assert_eq((_e2e.hud().get_node("%ApValue") as Label).text, ap_left, "HUD перечитав AP")
	assert_true((_e2e.hud().get_node("%ConfirmButton") as Button).disabled)
	assert_eq(_e2e.screen.input_controller()._selected_unit, tank, "танк лишається вибраним")


func test_confirm_button_still_confirms_a_move() -> void:
	await _boot()
	var tank: Unit = _e2e.service.state.unit_at(TANK)
	await _e2e.act(TANK, DEST)
	assert_eq(tank.pos, DEST)


func test_cancel_visible_only_while_it_does_something() -> void:
	await _boot()
	assert_false(_cancel().is_visible_in_tree(), "нічого не вибрано")
	await _tap(TANK)
	assert_false(_cancel().is_visible_in_tree(), "лише вибір — скасовувати нічого")
	await _tap(DEST)
	assert_true(_cancel().is_visible_in_tree(), "прев'ю руху")
	_e2e.press(_cancel())
	await _e2e.settle()
	assert_false(_cancel().is_visible_in_tree(), "скасовано")
	assert_false(_e2e.hud().get_node("%PreviewMoveBox").is_visible_in_tree())
	await _tap(ENEMY)
	assert_true(_cancel().is_visible_in_tree(), "прев'ю пострілу")
	_e2e.press(_cancel())
	await _e2e.settle()
	assert_false(_cancel().is_visible_in_tree())
	await _tap(SQUAD)
	_e2e.press(_e2e.hud().get_node("%DroneButton"))
	await _e2e.settle()
	assert_true(_cancel().is_visible_in_tree(), "озброєний дрон")
	await _tap(DEST)  # порожній тайл у режимі дрона знімає режим
	assert_false(_cancel().is_visible_in_tree(), "режим знято")
	await _tap(DEST)
	assert_true(_cancel().is_visible_in_tree(), "прев'ю руху загону")
	await _e2e.end_turn()
	assert_false(_cancel().is_visible_in_tree(), "не переживає передачу ходу")
	await _e2e.confirm_gate()
	assert_false(_cancel().is_visible_in_tree(), "у наступного гравця теж")
