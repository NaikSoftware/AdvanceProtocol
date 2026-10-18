extends GutTest
## Task 4.6: цілі на дошці під туманом активного гравця, наскрізно.
## Кнопки «Захопити» (T8) ще немає — захоплення подає EngineerCommand у prepare.

const E2E := preload("res://tests/e2e/e2e_helpers.gd")

const RIFLE: int = 0
const ENGINEER: int = 11
const E: int = 2

const NEAR := Vector2i(5, 1)
const FAR := Vector2i(9, 1)

var _e2e: E2E


func before_each() -> void:
	_e2e = E2E.new(self)


func after_each() -> void:
	_e2e.restore_runner_gui()
	DirAccess.remove_absolute(_e2e.save_path)
	DirAccess.remove_absolute(_e2e.save_path + ".map")


func _spawn(type_id: int, owner: int, pos: Vector2i) -> Dictionary:
	return {"type_id": type_id, "owner": owner, "pos": pos, "facing": E}


func _layer() -> ObjectiveView:
	return _e2e.screen.get_node("%ObjectiveView")


func _capture(state: BattleState) -> void:
	var eng: Unit = state.unit_at(Vector2i(4, 1))
	assert_eq(_e2e.service.submit(EngineerCommand.create(eng.id, EngineerCommand.Action.CAPTURE_OBJECTIVE, NEAR)), "")


## Інженер P0 на (4,1) бачить ромб радіуса 3: (5,1) всередині, (9,1) ні.
func _boot(opts: Dictionary = {}) -> void:
	opts["objectives"] = [NEAR, FAR]
	await _e2e.boot(10, 3, [_spawn(ENGINEER, 0, Vector2i(4, 1)), _spawn(RIFLE, 1, Vector2i(9, 2))], opts)


func test_only_seen_objective_has_marker() -> void:
	await _boot()
	assert_not_null(_layer().marker_at(NEAR))
	assert_null(_layer().marker_at(FAR))


func test_capture_recolours_marker() -> void:
	await _boot({"prepare": _capture})
	assert_eq(_layer().marker_state(NEAR).owner, 0)
	assert_null(_layer().marker_at(FAR))
