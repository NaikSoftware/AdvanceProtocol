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
	rig.pan(Vector2(0, 2000))
	var focus: Vector3 = rig.global_position
	assert_almost_eq(focus.x, 21.0, 0.01, "R12: межа — (board_size - 1) + BOARD_MARGIN, не board_size + BOARD_MARGIN")
	assert_almost_eq(focus.z, 21.0, 0.01, "R12: межа — (board_size - 1) + BOARD_MARGIN, не board_size + BOARD_MARGIN")

## R13: дельта — це палець на екрані, не світові осі; ріг мусить сам повернути
## її на свій yaw. Рух лише по одній екранній осі, що не зрушив би обидві
## світові осі, доводив би, що поворот не застосовується (кут "просочився"
## би назовні, у контролер вводу — саме те, що §3.1 забороняє).
func test_pan_rotates_screen_delta_by_the_rig_yaw() -> void:
	rig.center_on(Vector2i(10, 10))
	rig.pan(Vector2(1, 0))
	var focus: Vector3 = rig.global_position
	assert_false(is_equal_approx(focus.x, 10.0), "рух по одній осі екрана мусить зрушити фокус по світовому x")
	assert_false(is_equal_approx(focus.z, 10.0), "і по світовому z — це і є сенс 45°-рига (R13)")

func test_center_on_moves_focus() -> void:
	rig.center_on(Vector2i(10, 10))
	assert_almost_eq(rig.global_position.x, 10.0, 0.01)
	assert_almost_eq(rig.global_position.z, 10.0, 0.01)


## Task 2.10: тап по екрану мусить перетворюватись на клітинку дошки САМЕ тут
## (game/camera/), а не десь у battle_screen.gd — §1 non-goals і R13 разом:
## уся екранна геометрія 45°-рига лишається в одному місці. Раунд-трип через
## справжню проєкцію камери (unproject_position -> screen_point_to_cell), а не
## ручний перерахунок математики променя в самому тесті — так тест ловить
## розбіжність з реальною Camera3D, а не з переказом її формул.
func test_screen_point_to_cell_round_trips_through_camera_projection() -> void:
	rig.center_on(Vector2i(10, 10))
	var camera: Camera3D = rig.get_node("Yaw/Camera3D")
	for c in [Vector2i(10, 10), Vector2i(5, 12), Vector2i(15, 8)]:
		var world: Vector3 = rig.cell_to_world(c)
		var screen: Vector2 = camera.unproject_position(world)
		assert_eq(rig.screen_point_to_cell(screen), c, "клітинка %s мусить пережити проєкцію туди й назад" % c)


func test_screen_point_to_cell_degrades_safely_when_the_ray_never_meets_the_board_plane() -> void:
	# Промінь, паралельний площині y=0 (камера дивиться рівно вперед, без
	# нахилу вниз), не має перетину з нею взагалі — деградація мусить бути
	# безпечним значенням поза дошкою (Board.in_bounds() завжди false), а не
	# діленням на нуль чи крашем.
	var camera: Camera3D = rig.get_node("Yaw/Camera3D")
	camera.rotation_degrees = Vector3.ZERO
	var cell: Vector2i = rig.screen_point_to_cell(Vector2(640, 360))
	assert_false(Board.create(20, 20, Terrain.GroundState.DRY).in_bounds(cell))
