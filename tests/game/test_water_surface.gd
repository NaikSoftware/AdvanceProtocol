extends GutTest
## Phase 5a, Task 6: річка й відбиття. Шейдер GUT не компілює (дамі-рендерер),
## тож перевіряється те, що отримують шейдер і зонд: маска, геометрія, шари.
## Головне тут — §3.5 і анти-ціль специфікації: відбиття не сміє показати
## прихованого юніта чи міну.

const BoardViewScene := preload("res://game/battle/board_view.tscn")

var view: BoardView


func before_each() -> void:
	view = BoardViewScene.instantiate()
	add_child_autofree(view)


func _waters() -> Array[WaterSurface]:
	var out: Array[WaterSurface] = []
	for child in view.get_children():
		if child is WaterSurface:
			out.append(child)
	return out


func _river() -> Board:
	return (load("res://maps/river.tres") as MapData).to_board()


func test_board_with_water_gets_one_water_surface() -> void:
	view.build(_river())
	assert_eq(_waters().size(), 1)
	assert_true(_waters()[0].visible, "на River є вода")


func test_board_without_water_still_builds_one_hidden_water() -> void:
	view.build(Board.create(4, 3, Terrain.GroundState.DRY))
	assert_eq(_waters().size(), 1)
	assert_false(_waters()[0].visible, "суцільне поле — води не видно")


func test_reflection_probe_never_sees_units() -> void:
	view.build(_river())
	var probe: ReflectionProbe = view.reflection_probe()
	assert_not_null(probe)
	assert_eq(probe.cull_mask & (1 << (UnitView.UNIT_LAYER - 1)), 0, "зонд не бачить шару юнітів")
	assert_eq(probe.cull_mask, 1, "зонд бачить лише світ")
	assert_eq(probe.update_mode, ReflectionProbe.UPDATE_ONCE)


## Міни теж прихована інформація (§3.11): маркер власника, що потрапив у знімок
## зонда (збережена партія вантажиться з мінами), показав би міну суперникові.
func test_mine_markers_are_outside_the_probe_mask() -> void:
	view.build(_river())
	var mines := MineLayer.new()
	add_child_autofree(mines)
	var state := BattleState.create(Board.create(4, 3, Terrain.GroundState.DRY), 2, 7)
	Mines.place(state, Vector2i(1, 1), 0)
	mines.rebuild(state, 0)
	var marker: VisualInstance3D = mines.marker_at(Vector2i(1, 1))
	assert_eq(marker.layers & view.reflection_probe().cull_mask, 0)


func test_probe_box_covers_the_board() -> void:
	view.build(Board.create(10, 6, Terrain.GroundState.DRY))
	var probe: ReflectionProbe = view.reflection_probe()
	var box := AABB(probe.position - probe.size * 0.5, probe.size)
	assert_true(box.has_point(Vector3(-0.4, 0.0, -0.4)), "кут (0,0)")
	assert_true(box.has_point(Vector3(9.4, 0.0, 5.4)), "кут (9,5)")
	assert_true(box.has_point(Vector3(4.5, 0.02, 2.5)), "площина води всередині")


## Зонд знімає один раз: перебудова (підірваний міст) не створює нового зонда,
## бо новий знімок посеред партії міг би захопити тимчасові маркери.
func test_rebuild_keeps_the_probe_and_shows_water_under_a_destroyed_bridge() -> void:
	var board := Board.create(4, 3, Terrain.GroundState.DRY)
	board.set_kind(Vector2i(1, 1), Terrain.Kind.BRIDGE)
	view.build(board)
	var probe: ReflectionProbe = view.reflection_probe()
	var water: WaterSurface = _waters()[0]
	assert_false(water.visible, "цілий міст — води на поверхні немає")
	board.set_kind(Vector2i(1, 1), Terrain.Kind.BRIDGE_DESTROYED)
	view.rebuild_tiles(board)
	assert_same(view.reflection_probe(), probe)
	assert_eq(_waters().size(), 1)
	assert_same(_waters()[0], water)
	assert_true(water.visible, "підірваний міст — вода")


func test_water_plane_lies_at_y_002_over_the_board() -> void:
	view.build(_river())
	var water: WaterSurface = _waters()[0]
	var aabb: AABB = water.transform * water.get_aabb()
	assert_almost_eq(aabb.position.y, 0.02, 0.0001)
	assert_almost_eq(aabb.position.x, -0.5, 0.0001)
	assert_almost_eq(aabb.end.x, 25.5, 0.0001)
	assert_almost_eq(aabb.end.z, 21.5, 0.0001)
	assert_eq(water.layers, 1)
	assert_eq(water.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)


## Маска: вода лише на WATER і BRIDGE_DESTROYED; цілий BRIDGE — дорога.
func test_water_material_gets_the_kind_map_and_water_kinds() -> void:
	var board := Board.create(4, 3, Terrain.GroundState.DRY)
	board.set_kind(Vector2i(0, 0), Terrain.Kind.WATER)
	view.build(board)
	var mat: ShaderMaterial = _waters()[0].material_override
	var tex: ImageTexture = mat.get_shader_parameter("kind_map")
	assert_eq(tex.get_image().get_pixel(0, 0).r8, Terrain.Kind.WATER)
	assert_eq(mat.get_shader_parameter("water_kind"), Terrain.Kind.WATER)
	assert_eq(mat.get_shader_parameter("broken_bridge_kind"), Terrain.Kind.BRIDGE_DESTROYED)
	assert_eq(mat.get_shader_parameter("map_origin"), Vector2(0, 0))
