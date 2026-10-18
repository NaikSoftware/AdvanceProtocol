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
func test_rebuild_keeps_the_probe_and_the_water_node() -> void:
	var board := Board.create(4, 3, Terrain.GroundState.DRY)
	board.set_kind(Vector2i(1, 1), Terrain.Kind.BRIDGE)
	view.build(board)
	var probe: ReflectionProbe = view.reflection_probe()
	var water: WaterSurface = _waters()[0]
	assert_true(water.visible, "річка тече й під цілим мостом")
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


## Маска: вода на WATER, BRIDGE і BRIDGE_DESTROYED — річка тече під мостом.
func test_water_material_gets_the_kind_map_and_water_kinds() -> void:
	var board := Board.create(4, 3, Terrain.GroundState.DRY)
	board.set_kind(Vector2i(0, 0), Terrain.Kind.WATER)
	view.build(board)
	var mat: ShaderMaterial = _waters()[0].material_override
	var tex: ImageTexture = mat.get_shader_parameter("kind_map")
	assert_eq(tex.get_image().get_pixel(0, 0).r8, Terrain.Kind.WATER)
	assert_eq(mat.get_shader_parameter("water_kind"), Terrain.Kind.WATER)
	assert_eq(mat.get_shader_parameter("broken_bridge_kind"), Terrain.Kind.BRIDGE_DESTROYED)
	assert_eq(mat.get_shader_parameter("bridge_kind"), Terrain.Kind.BRIDGE)
	assert_eq(mat.get_shader_parameter("map_origin"), Vector2(0, 0))


## На River кожна клітинка мосту — вода в масці (вид мосту серед видів води
## шейдера, і в kind_map вона саме BRIDGE).
func test_every_river_bridge_cell_is_water_in_the_mask() -> void:
	var board := _river()
	view.build(board)
	var mat: ShaderMaterial = _waters()[0].material_override
	var water_kinds: Array = [mat.get_shader_parameter("water_kind"), mat.get_shader_parameter("bridge_kind"),
			mat.get_shader_parameter("broken_bridge_kind")]
	var img: Image = (mat.get_shader_parameter("kind_map") as ImageTexture).get_image()
	var bridges := 0
	for y in board.height:
		for x in board.width:
			if board.kind_at(Vector2i(x, y)) == Terrain.Kind.BRIDGE:
				bridges += 1
				assert_has(water_kinds, img.get_pixel(x, y).r8, "міст %d,%d" % [x, y])
	assert_eq(bridges, 8, "на River вісім клітинок мостів")


## Тимчасовий настил (до мостів Task 8): по екземпляру на кожну клітинку BRIDGE.
## Підірваний міст не зникає — руїни лишаються, щоб гравець бачив, де інженер
## може його відновити: BRIDGE_DESTROYED отримує уламки, не порожнечу.
func test_placeholder_deck_on_every_bridge_cell_and_ruins_on_a_destroyed_one() -> void:
	var board := _river()
	board.set_kind(Vector2i(4, 10), Terrain.Kind.BRIDGE_DESTROYED)
	view.build(board)
	var expected: Array[Vector2i] = []
	for y in board.height:
		for x in board.width:
			if board.kind_at(Vector2i(x, y)) == Terrain.Kind.BRIDGE:
				expected.append(Vector2i(x, y))
	assert_eq(expected.size(), 7)
	assert_eq_deep(view._placeholder_bridge_deck_cells, expected)
	var deck: MultiMeshInstance3D = view.get_node("PlaceholderBridgeDeck")
	assert_eq(deck.multimesh.instance_count, 7)
	assert_eq(deck.layers, 1, "настил — світ, зонд його бачить")
	assert_eq(BoardView.PLACEHOLDER_DECK_TOP, 0.25)
	assert_eq_deep(view._placeholder_bridge_ruin_cells, [Vector2i(4, 10)] as Array[Vector2i])
	var ruin: MultiMeshInstance3D = view.get_node("PlaceholderBridgeRuin")
	assert_gt(ruin.multimesh.instance_count, 0, "руїни видно")
	assert_eq(ruin.layers, 1)


## Підрив міняє настил клітинки на руїни, ремонт — назад.
func test_demolish_and_repair_swap_deck_and_ruins() -> void:
	var board := _river()
	var cell := Vector2i(12, 10)
	view.build(board)
	assert_true(view._placeholder_bridge_deck_cells.has(cell))
	assert_false(view._placeholder_bridge_ruin_cells.has(cell))
	assert_false(view.has_node("PlaceholderBridgeRuin"), "руїн ще немає")

	board.set_kind(cell, Terrain.Kind.BRIDGE_DESTROYED)
	view.rebuild_tiles(board)
	assert_false(view._placeholder_bridge_deck_cells.has(cell), "підірваний — без настилу")
	assert_true(view._placeholder_bridge_ruin_cells.has(cell), "підірваний — руїни")
	assert_eq((view.get_node("PlaceholderBridgeDeck") as MultiMeshInstance3D).multimesh.instance_count, 7)
	var ruin_count: int = (view.get_node("PlaceholderBridgeRuin") as MultiMeshInstance3D).multimesh.instance_count
	assert_between(ruin_count, 4, 5, "2–3 уламки настилу і 2 опори")

	board.set_kind(cell, Terrain.Kind.BRIDGE)
	view.rebuild_tiles(board)
	assert_true(view._placeholder_bridge_deck_cells.has(cell), "відновлений — настил")
	assert_false(view._placeholder_bridge_ruin_cells.has(cell))
	assert_false(view.has_node("PlaceholderBridgeRuin"))
	assert_eq((view.get_node("PlaceholderBridgeDeck") as MultiMeshInstance3D).multimesh.instance_count, 8)


## Уламки — з хешу клітинки, не з випадковості: обидва гравці бачать те саме.
func test_ruins_are_deterministic_per_cell() -> void:
	var board := _river()
	board.set_kind(Vector2i(21, 11), Terrain.Kind.BRIDGE_DESTROYED)
	view.build(board)
	var first: Array[Transform3D] = view._placeholder_bridge_ruin_transforms.duplicate()
	view.build(board)
	assert_eq_deep(view._placeholder_bridge_ruin_transforms, first)
	assert_gt(first.size(), 0)


## Настил лягає вздовж дороги: міст між дорогами по X — довгий по X.
func test_placeholder_deck_follows_the_road_axis() -> void:
	var board := Board.create(3, 3, Terrain.GroundState.DRY)
	for x in 3:
		board.set_kind(Vector2i(x, 1), Terrain.Kind.WATER)
	board.set_kind(Vector2i(1, 0), Terrain.Kind.ROAD)
	board.set_kind(Vector2i(1, 1), Terrain.Kind.BRIDGE)
	board.set_kind(Vector2i(1, 2), Terrain.Kind.ROAD)
	view.build(board)
	assert_eq(view._placeholder_bridge_deck_axes, [Vector2i(0, 1)] as Array[Vector2i], "дорога йде по Z")
	board.set_kind(Vector2i(1, 0), Terrain.Kind.WATER)
	board.set_kind(Vector2i(1, 2), Terrain.Kind.WATER)
	board.set_kind(Vector2i(0, 1), Terrain.Kind.ROAD)
	board.set_kind(Vector2i(2, 1), Terrain.Kind.ROAD)
	view.rebuild_tiles(board)
	assert_eq(view._placeholder_bridge_deck_axes, [Vector2i(1, 0)] as Array[Vector2i], "дорога йде по X")


## Брижа й смуги течії йдуть уздовж річки, а не вздовж екрана. Вісь — та, вздовж
## якої більше пар сусідніх клітинок води.
func test_flow_axis_follows_the_river() -> void:
	view.build(_river())
	var mat: ShaderMaterial = _waters()[0].material_override
	assert_eq(mat.get_shader_parameter("flow_dir"), Vector2(1, 0), "River тече вздовж X")
	var board := Board.create(5, 6, Terrain.GroundState.DRY)
	for y in 6:
		board.set_kind(Vector2i(2, y), Terrain.Kind.WATER)
	view.build(board)
	mat = _waters()[0].material_override
	assert_eq(mat.get_shader_parameter("flow_dir"), Vector2(0, 1), "вертикальна річка — вздовж Z")


## Поки сцена без неба (Task 10), вода й калюжі відбивають власне похмуре небо;
## погода гасить його глобальним uniform, щоб із справжнім небом не було подвійного.
func test_sky_fallback_is_a_global_uniform_on_by_default() -> void:
	assert_true(ProjectSettings.has_setting("shader_globals/sky_fallback"))
	var entry: Dictionary = ProjectSettings.get_setting("shader_globals/sky_fallback", {})
	assert_eq(entry.get("type"), "float")
	assert_eq(entry.get("value"), 1.0)


## Накладки (контури всіх шарів, кільця) — стан активного гравця. Якщо зонд колись
## перезніме посеред партії, наступний гравець не сміє побачити їх у річці.
func test_overlays_are_on_the_overlay_layer_outside_the_probe_mask() -> void:
	view.build(_river())
	var seg: Array[Dictionary] = [{"cell": Vector2i(3, 3), "dir": Vector2i(1, 0), "color": Color.GOLD}]
	for layer: int in [BoardView.LAYER_ZONES, BoardView.LAYER_PATH, BoardView.LAYER_TARGETS, BoardView.LAYER_INSPECT]:
		view.draw_contour(seg, layer)
	var circles: Array[Dictionary] = [{"center": Vector2i(4, 4), "radius": 3, "color": Color.WHITE}]
	view.draw_circles(circles, BoardView.LAYER_INSPECT)
	var bit: int = 1 << (BoardView.OVERLAY_LAYER - 1)
	var overlays: Array[VisualInstance3D] = []
	for child in view.get_children():
		if child is VisualInstance3D and not child is GroundSurface and not child is WaterSurface and not child is ReflectionProbe \
				and not String(child.name).begins_with("PlaceholderBridge"):
			overlays.append(child)
	assert_eq(overlays.size(), 5, "4 контури і одне кільце")
	for node in overlays:
		assert_eq(node.layers, bit, node.name)
	assert_eq(view.reflection_probe().cull_mask & bit, 0)
	var camera := Camera3D.new()
	assert_ne(camera.cull_mask & bit, 0, "камера за замовчуванням малює шар накладок")
	camera.free()


## Будь-яка зміна size/origin_offset/position зонда перезнімає його; перебудова
## (підірваний міст) не сміє їх чіпати.
func test_rebuild_tiles_leaves_the_probe_box_unchanged() -> void:
	var board := _river()
	view.build(board)
	var probe: ReflectionProbe = view.reflection_probe()
	assert_eq(probe.size, Vector3(30, 12, 26))
	assert_eq(probe.position, Vector3(12.5, 5.0, 10.5))
	assert_eq(probe.origin_offset, Vector3(0.0, -3.5, 0.0))
	board.set_kind(Vector2i(12, 10), Terrain.Kind.BRIDGE_DESTROYED)
	view.rebuild_tiles(board)
	assert_eq(probe.size, Vector3(30, 12, 26))
	assert_eq(probe.position, Vector3(12.5, 5.0, 10.5))
	assert_eq(probe.origin_offset, Vector3(0.0, -3.5, 0.0))
