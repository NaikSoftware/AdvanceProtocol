extends GutTest
## §3.13, docs/ui/overlays.md: довгий натиск на будь-якому видимому юніті — коло
## дальності й позначки загроз; відпускання знімає. Тап кілець не показує ніколи.
## Наскрізно, справжніми подіями миші по дошці.

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
	_e2e.screen.input_controller().inspected.connect(func(i: Dictionary) -> void: _last = i)


func _state() -> BattleState:
	return _e2e.service.state


func _view(cell: Vector2i) -> UnitView:
	return _e2e.screen.unit_view_for(_state().unit_at(cell).id)


func _rings() -> Array:
	return (_e2e.screen.get_node("%BoardView") as BoardView).circles(BoardView.LAYER_INSPECT)


func _floor() -> Label:
	return _e2e.hud().get_node("%ThreatFloorLabel")


## Коло радіуса дальності (танк — 4) з центром у тайлі танка і приціл на моєму
## броньовику в його дальності; відпускання знімає все.
func test_long_press_on_enemy_tank_shows_a_circle_and_marks_my_unit_in_range() -> void:
	await _boot(MEDIUM_TANK, TANK)
	_e2e.long_press(TANK)
	assert_eq(_rings(), [{"center": TANK, "radius": 4, "color": TargetOverlay.GUN_RING_COLOR}])
	var ring: MeshInstance3D = _ring_node()
	assert_eq(Vector2(ring.position.x, ring.position.z), Vector2(6.0, 1.0), "центр — середина тайла танка")
	assert_true(_view(CAR_POS).is_threatened(), "броньовик на 3 — у дальності 4")
	assert_false(_view(SQUAD).is_threatened(), "загін на 6 — поза дальністю")
	assert_true(_floor().is_visible_in_tree())
	assert_eq(_floor().text, tr("hud_threat_floor"))

	_e2e.release(TANK)
	await _e2e.settle()

	assert_eq(_rings(), [])
	assert_false(_view(CAR_POS).is_threatened())
	assert_false(_floor().is_visible_in_tree())


func _ring_node() -> MeshInstance3D:
	for c: Node in _e2e.screen.get_node("%BoardView").get_children():
		if c is MeshInstance3D and not c is MultiMeshInstance3D and not c is GroundSurface and not c is WaterSurface:
			return c
	return null


func test_a_tap_on_an_enemy_shows_no_ring() -> void:
	await _boot(MEDIUM_TANK, TANK)
	_e2e.tap(TANK)
	await _e2e.settle()
	assert_eq(_rings(), [])
	assert_false(_view(CAR_POS).is_threatened())
	assert_false(_floor().is_visible_in_tree())


## Відпускання після довгого натиску — не тап: нічого не вибрано, нічого не повернуто.
func test_release_after_long_press_is_not_a_tap() -> void:
	await _boot(MEDIUM_TANK, TANK)
	_e2e.tap(CAR_POS)
	await _e2e.settle()
	var car: Unit = _state().unit_at(CAR_POS)
	var facing: int = car.facing
	_e2e.long_press(Vector2i(5, 0))
	_e2e.release(Vector2i(5, 0))
	await _e2e.settle()
	assert_eq(car.facing, facing, "довгий натиск не повертає")
	assert_true(_e2e.hud().get_node("%SelectionRow").is_visible_in_tree(), "вибір лишився")
	assert_false(_e2e.hud().get_node("%CancelButton").is_visible_in_tree(), "прев'ю руху не з'явилось")


## Порожня земля під пальцем — кільце вибраного свого юніта.
func test_long_press_on_empty_ground_shows_selected_unit_ring() -> void:
	await _boot(MEDIUM_TANK, TANK)
	_e2e.tap(CAR_POS)
	await _e2e.settle()
	assert_eq(_rings(), [], "вибір кільця не показує")
	_e2e.long_press(Vector2i(4, 0))
	assert_eq(_rings(), [{"center": CAR_POS, "radius": 3, "color": TargetOverlay.GUN_RING_COLOR}])
	assert_true(_view(TANK).is_threatened(), "танк на 3 — ціль броньовика")
	assert_false(_floor().is_visible_in_tree())
	_e2e.release(Vector2i(4, 0))


func test_enemy_squad_with_drones_threatens_at_5() -> void:
	await _boot(ASSAULT, ENEMY_SQUAD)
	_e2e.long_press(ENEMY_SQUAD)
	assert_eq(_rings(), [{"center": ENEMY_SQUAD, "radius": 3, "color": TargetOverlay.GUN_RING_COLOR},
		{"center": ENEMY_SQUAD, "radius": DroneCommand.RANGE, "color": TargetOverlay.DRONE_RING_COLOR}])
	assert_true(_view(CAR_POS).is_drone_threatened(), "броньовик на 5 — дрон")
	assert_false(_view(CAR_POS).is_threatened(), "гармата загону дістає лише на 3")
	assert_eq(_last["drone_marked"], [_state().unit_at(CAR_POS).id])
	assert_eq(_floor().text, tr("hud_threat_floor_drone"))
	_e2e.release(ENEMY_SQUAD)


func test_enemy_squad_without_drones_does_not_threaten_at_5() -> void:
	await _boot(ASSAULT, ENEMY_SQUAD, func(st: BattleState) -> void: st.unit_at(ENEMY_SQUAD).drones_left = 0)
	_e2e.long_press(ENEMY_SQUAD)
	assert_eq(_last["drone_radius"], 0)
	assert_eq(_rings().size(), 1, "лише коло гармати")
	assert_false(_view(CAR_POS).is_threatened())
	assert_false(_view(CAR_POS).is_drone_threatened())
	assert_eq(_floor().text, tr("hud_threat_floor"))
	_e2e.release(ENEMY_SQUAD)


## Драг — ніколи не довгий натиск: палець поїхав за поріг, потім тримається.
func test_a_drag_is_never_a_long_press() -> void:
	await _boot(MEDIUM_TANK, TANK)
	var from: Vector2 = _e2e.px(TANK)
	_e2e._mouse_button(from, true)
	# Справжній захист — ignore_runner_gui() у _boot, що тепер гасить і внутрішні
	# вузли GUT: за FOV 42° +60 px вправо потрапляли на внутрішню смугу прокрутки
	# вікна виводу GUT (x ≥ 1258), яку хелпер раніше пропускав. До центру екрана
	# тягнемо додатково, щоб драг не залежав від того, що лежить біля краю.
	var shift: Vector2 = (get_viewport().get_visible_rect().get_center() - from).normalized() * 60.0
	var mv := InputEventMouseMotion.new()
	mv.position = from + shift
	mv.global_position = mv.position
	mv.relative = shift
	mv.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(mv, true)
	_e2e.screen._process(BattleScreen.LONG_PRESS_SEC * 2.0)
	assert_eq(_rings(), [])
	_e2e._mouse_button(mv.position, false)
	await _e2e.settle()
	assert_eq(_rings(), [])


func test_peek_does_not_survive_the_handover_gate() -> void:
	await _boot(MEDIUM_TANK, TANK)
	_e2e.long_press(TANK)
	assert_ne(_rings(), [], "передумова")
	await _e2e.end_turn()
	assert_true(_e2e.gate().is_visible_in_tree(), "гейт показано")
	assert_eq(_rings(), [])
	assert_false(_floor().is_visible_in_tree())
	_e2e.release(TANK)
	await _e2e.confirm_gate()
	assert_eq(_rings(), [])
	for id: int in [_state().unit_at(CAR_POS).id, _state().unit_at(SQUAD).id]:
		var v: UnitView = _e2e.screen.unit_view_for(id)
		if v != null:
			assert_false(v.is_threatened())


func test_enemy_engineer_shows_no_ring_and_no_floor() -> void:
	await _boot(11, TANK)
	_e2e.long_press(TANK)
	assert_eq(_last["radius"], 0, "§3.6: у інженера немає гармати")
	assert_eq(_rings(), [])
	assert_false(_view(CAR_POS).is_threatened())
	assert_false(_floor().is_visible_in_tree())
	_e2e.release(TANK)


## Власник 2026-10-18: справжній тап по полю розвертає вибраного юніта туди.
func test_a_real_tap_turns_the_selected_unit() -> void:
	await _boot(MEDIUM_TANK, TANK)
	_e2e.tap(CAR_POS)
	await _e2e.settle()
	var car: Unit = _state().unit_at(CAR_POS)
	var ap: int = car.ap
	var target := Vector2i(3, 2)
	assert_ne(car.facing, Board.facing_towards(CAR_POS, target), "передумова")
	var node: UnitView = _view(CAR_POS)

	_e2e.tap(target)
	await _e2e.settle()

	assert_same(_view(CAR_POS), node, "поворот анімовано на тому самому вузлі, а не знято перебудовою")

	assert_eq(car.facing, Board.facing_towards(CAR_POS, target))
	assert_eq(car.ap, ap, "поворот безкоштовний")
	assert_eq(_view(CAR_POS).facing, car.facing, "вузол повернуто")
	assert_eq(_e2e.events_of(Events.UnitTurned).size(), 1)
