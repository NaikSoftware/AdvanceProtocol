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


## Дошка в один рядок з інженером у куті: міст — його єдиний сусід, тож причина
## відмови — саме мостова (з кількома сусідами різні причини дали б
## ERR_NO_ADJACENT_TARGET).
func test_demolish_refused_with_own_unit_on_bridge() -> void:
	var eng_pos := Vector2i(0, 0)
	var bridge := Vector2i(1, 0)
	await _e2e.boot(10, 1, [_spawn(ENGINEER, 0, eng_pos), _spawn(RIFLE, 0, bridge), _spawn(RIFLE, 1, Vector2i(9, 0))],
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


## Рішення контролера: на малому телефоні озброєна верба згортає панель у смужку,
## і кожен тайл-ціль лишається відкритим для тапу.
func test_armed_targets_are_tappable_on_small_phone() -> void:
	var eng_pos := Vector2i(4, 2)
	await _e2e.boot(10, 5, [_spawn(ENGINEER, 0, eng_pos), _spawn(RIFLE, 1, Vector2i(9, 4))],
		{"viewport_size": LayoutProbe.PHONE_SMALL})
	var eng: Unit = _state().unit_at(eng_pos)
	_e2e.tap(eng_pos)
	_e2e.press(_e2e.engineer_panel().button_for(A.LAY_MINE))
	await _e2e.settle()
	var previews: Array[Dictionary] = []
	_e2e.screen.input_controller().action_preview.connect(func(pv: Dictionary) -> void: previews.append(pv))
	var tiles: Array[Vector2i] = EngineerCommand.action_status(_state(), eng.id, A.LAY_MINE)["tiles"]
	assert_eq(tiles.size(), 4)
	var screen_rect := Rect2(Vector2.ZERO, Vector2(LayoutProbe.PHONE_SMALL))
	for t: Vector2i in tiles:
		var p: Vector2 = _e2e.px(t)
		assert_true(screen_rect.has_point(p), "%s на екрані: %s" % [t, p])
		assert_eq(_covering(p), [] as Array[String], "тайл %s @ %s" % [t, p])
		_e2e.tap(t)
		await _e2e.settle()
		assert_eq(previews.back(), {"type": InputController.ActionType.ENGINEER, "unit_id": eng.id,
			"action": A.LAY_MINE, "target": t})


## Усі видимі Control HUD, що перехопили б тап у точці p.
func _covering(p: Vector2) -> Array[String]:
	var out: Array[String] = []
	var hud: Hud = _e2e.hud()
	for n in hud.find_children("*", "Control", true, false):
		var c := n as Control
		if c.is_visible_in_tree() and c.mouse_filter != Control.MOUSE_FILTER_IGNORE and c.get_global_rect().has_point(p):
			out.append("%s %s" % [hud.get_path_to(c), c.get_global_rect()])
	return out


func test_strip_cancel_and_completed_action_restore_the_panel() -> void:
	await _boot()
	var panel: EngineerPanel = _e2e.engineer_panel()
	_e2e.tap(ENG)
	_e2e.press(panel.button_for(A.LAY_MINE))
	await _e2e.settle()
	assert_true((panel.get_node("%Strip") as Control).visible, "озброєно — смужка")
	_e2e.tap(Vector2i(7, 1))  # не сусід
	await _e2e.settle()
	assert_eq((panel.get_node("%ReasonLabel") as Label).text, tr("ERR_NOT_ADJACENT"))
	_e2e.press(panel.get_node("%StripCancel"))
	await _e2e.settle()
	assert_false((panel.get_node("%Strip") as Control).visible)
	assert_true((panel.get_node("%Scroll") as Control).visible)
	assert_eq(_board_view().contour_segments(BoardView.LAYER_TARGETS), [])
	# інженер досі вибраний — повторний тап по ньому зняв би вибір
	_e2e.press(panel.button_for(A.LAY_MINE))
	_e2e.tap(TARGET)
	await _e2e.confirm()
	assert_eq(_state().mines.size(), 1)
	assert_false((panel.get_node("%Strip") as Control).visible, "дію виконано — смужку знято")


# --- Task 9: межі ремонту до підтвердження ---

func _heal_text() -> String:
	return (_e2e.hud().get_node("%PreviewHealValue") as Label).text


func _repair_box() -> Control:
	return _e2e.hud().get_node("%PreviewRepairBox")


func _boot_hurt_tank(hp: int, eng_ap: int = -1) -> void:
	await _boot([_spawn(MEDIUM_TANK, 0, TARGET)], {"prepare": func(st: BattleState) -> void:
		st.unit_at(TARGET).hp = hp
		if eng_ap >= 0:
			st.unit_at(ENG).ap = eng_ap})
	_e2e.tap(ENG)
	await _e2e.settle()
	_e2e.press(_e2e.engineer_panel().button_for(A.REPAIR_UNIT))
	await _e2e.settle()
	_e2e.tap(TARGET)
	await _e2e.settle()


func test_repair_preview_full_ap_shows_20_to_43() -> void:
	await _boot_hurt_tank(300)
	assert_true(_repair_box().is_visible_in_tree())
	assert_eq(_heal_text(), "20–43")
	var tank: Unit = _state().unit_at(TARGET)
	await _e2e.confirm()
	# Golden, seed 7: перший кидок матчу дає 20 (див. test_repair_unit_heals_within_bounds).
	assert_eq(tank.hp, 320)
	assert_false(_repair_box().visible, "дію виконано — прев'ю знято")


func test_repair_preview_after_one_field_step_shows_20_to_30() -> void:
	# 51 AP — стан інженера після кроку по полю, як у core-тесті repair_bounds.
	await _boot_hurt_tank(300, 51)
	assert_eq(_heal_text(), "20–30")
	var tank: Unit = _state().unit_at(TARGET)
	await _e2e.confirm()
	# Seed 7: randi_range(0, 51 - 30) = 1 -> (40 + 1) / 2 = 20.
	assert_eq(tank.hp, 321)


func test_repair_preview_capped_by_missing_hp() -> void:
	await _boot_hurt_tank(388)
	assert_eq(_heal_text(), "12–12")
	var tank: Unit = _state().unit_at(TARGET)
	await _e2e.confirm()
	assert_eq(tank.hp, 400)


## Follow-up C: озброєння верби над відкладеним рухом знімає прев'ю руху в HUD.
func test_arming_a_verb_clears_a_pending_move_preview() -> void:
	await _boot()
	_e2e.tap(ENG)
	await _e2e.settle()
	_e2e.tap(Vector2i(1, 1))
	await _e2e.settle()
	var hud: Hud = _e2e.hud()
	assert_true((hud.get_node("%PreviewMoveBox") as Control).visible, "передумова: прев'ю руху")
	_e2e.press(_e2e.engineer_panel().button_for(A.LAY_MINE))
	await _e2e.settle()
	assert_false((hud.get_node("%PreviewMoveBox") as Control).visible)
	assert_true((hud.get_node("%ConfirmButton") as Button).disabled)


## Follow-up B: озброєна верба не переживає гейт передачі.
func test_armed_verb_does_not_survive_the_handover_gate() -> void:
	await _boot()
	var panel: EngineerPanel = _e2e.engineer_panel()
	_e2e.tap(ENG)
	_e2e.press(panel.button_for(A.LAY_MINE))
	await _e2e.settle()
	assert_true((panel.get_node("%Strip") as Control).visible, "передумова: озброєно")
	await _e2e.end_turn()
	assert_true(_e2e.gate().is_visible_in_tree(), "гейт показано")
	assert_eq(_board_view().contour_segments(BoardView.LAYER_TARGETS), [])
	assert_false((panel.get_node("%Strip") as Control).is_visible_in_tree())
	await _e2e.confirm_gate()
	assert_eq(_board_view().contour_segments(BoardView.LAYER_TARGETS), [])
	assert_false((panel.get_node("%Strip") as Control).is_visible_in_tree())
