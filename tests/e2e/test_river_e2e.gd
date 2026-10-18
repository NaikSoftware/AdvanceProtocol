extends GutTest
## Фаза 5a: перспективна камера на справжній карті. Тап іде крізь промінь
## перспективи, тож перевіряємо обидва краї зуму — на далекому тайли дрібні й
## стиснуті нахилом, на ближньому промінь б'є в землю під іншим кутом.

const E2E := preload("res://tests/e2e/e2e_helpers.gd")
const RIFLE: int = 0
const ARMOURED_CAR: int = 2

var _e2e: E2E


func before_each() -> void:
	_e2e = E2E.new(self)


func after_each() -> void:
	_e2e.restore_runner_gui()
	DirAccess.remove_absolute(_e2e.save_path)
	DirAccess.remove_absolute(_e2e.save_path + ".map")


func _rig() -> IsoCameraRig:
	return _e2e.screen.get_node("%CameraRig")


func _zoom_to(zoom: float) -> void:
	var rig: IsoCameraRig = _rig()
	rig.zoom_by(zoom / rig.zoom_level)
	for i in 240:
		rig._process(1.0 / 60.0)
	assert_eq(rig.zoom_level, zoom, "передумова: зум дійшов до краю")


func _own_unit(type_id: int) -> Unit:
	for u: Unit in _e2e.service.state.units_of(0):
		if u.type_id == type_id:
			return u
	return null


## Найближчий золотий тайл за 2+ кроки, що лежить на екрані з запасом від HUD.
func _gold_cell(u: Unit) -> Vector2i:
	var state: BattleState = _e2e.service.state
	var occ: Dictionary = state.known_blocked_map(u.owner)
	occ.erase(u.pos)
	var zones: Pathing.Zones = Pathing.compute_zones(state.board, u, occ)
	var safe: Rect2 = _e2e.vp.get_visible_rect().grow(-160.0)
	var best := Vector2i(-1, -1)
	var best_d: int = 1 << 30
	for c: Vector2i in zones.move_and_fire:
		var d: int = absi(c.x - u.pos.x) + absi(c.y - u.pos.y)
		if d < 2 or occ.has(c) or not safe.has_point(_e2e.px(c)):
			continue
		if d < best_d:
			best_d = d
			best = c
	return best


func _move_by_taps(u: Unit) -> void:
	_rig().center_on(u.pos)
	var target: Vector2i = _gold_cell(u)
	assert_ne(target, Vector2i(-1, -1), "передумова: є золотий тайл на екрані")
	var ap_before: int = u.ap
	_e2e.tap(u.pos)
	assert_eq(_e2e.screen.input_controller()._selected_unit, u, "тап вибрав юніт")
	_e2e.tap(target)
	await _e2e.confirm()
	assert_eq(u.pos, target, "юніт дійшов на тапнутий тайл")
	assert_lt(u.ap, ap_before, "рух списав AP")


func test_a_unit_moves_on_river_through_real_taps_at_both_zoom_ends() -> void:
	await _e2e.boot(0, 0, [], {"map_path": "res://maps/river.tres", "viewport_size": Vector2i(1280, 720)})
	_zoom_to(IsoCameraRig.MAX_ZOOM)
	await _move_by_taps(_own_unit(ARMOURED_CAR))
	_zoom_to(IsoCameraRig.MIN_ZOOM)
	await _move_by_taps(_own_unit(RIFLE))
