extends GutTest

var rig: Node3D

func before_each() -> void:
	rig = load("res://game/camera/iso_camera_rig.tscn").instantiate()
	add_child_autofree(rig)
	rig.set_bounds(Vector2i(20, 20))

func test_cell_to_world_does_not_bake_the_isometric_angle() -> void:
	assert_eq(rig.cell_to_world(Vector2i(3, 4)), Vector3(3, 0, 4), "§3.1: 45° дає камера, не дані")

func test_world_to_cell_round_trips() -> void:
	for c in [Vector2i(0, 0), Vector2i(7, 2), Vector2i(19, 19)]:
		assert_eq(rig.world_to_cell(rig.cell_to_world(c)), c)

func test_zoom_is_clamped() -> void:
	for i in 50:
		rig.zoom_by(0.5)
	assert_true(rig.zoom_level >= rig.MIN_ZOOM)
	for i in 50:
		rig.zoom_by(2.0)
	assert_true(rig.zoom_level <= rig.MAX_ZOOM)

func test_pan_is_clamped_to_board() -> void:
	rig.pan(Vector2(1000, 1000))
	var focus: Vector3 = rig.global_position
	assert_true(focus.x <= 22.0 and focus.z <= 22.0, "камера не тікає з карти")

func test_center_on_moves_focus() -> void:
	rig.center_on(Vector2i(10, 10))
	assert_almost_eq(rig.global_position.x, 10.0, 0.01)
	assert_almost_eq(rig.global_position.z, 10.0, 0.01)
