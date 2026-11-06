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


## Площина лежить на рівні води над усіма клітинками води з запасом у клітинку, але в межах
## дошки: за ними вона лише рахувала б фрагменти, які однаково відкидає.
func test_water_plane_lies_at_the_water_level_over_the_water_cells() -> void:
	var board: Board = _river()
	view.build(board)
	var water: WaterSurface = _waters()[0]
	var aabb: AABB = water.transform * water.get_aabb()
	var z0: int = board.height
	var z1: int = -1
	for i in board.tiles.size():
		if WaterSurface._is_water(board, Vector2i(i % board.width, i / board.width)):
			z0 = mini(z0, i / board.width)
			z1 = maxi(z1, i / board.width)
	assert_almost_eq(aabb.position.y, TerrainHeight.WATER_LEVEL, 0.0001)
	assert_almost_eq(aabb.position.x, -0.5, 0.0001, "річка River тече від краю до краю")
	assert_almost_eq(aabb.end.x, 25.5, 0.0001)
	assert_almost_eq(aabb.position.z, maxf(z0 - 1.5, -0.5), 0.0001)
	assert_almost_eq(aabb.end.z, minf(z1 + 1.5, 21.5), 0.0001)
	assert_lt(aabb.size.z, 22.0, "уся дошка площиною не вкрита")
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
	assert_eq(bridges, 7, "на River сім клітинок мостів")


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


## Вода й калюжі відбивають небо WeatherRig напряму, з власною силою відбиття:
## вбудоване відбиття Godot для діелектрика не перевищує ~16 %. Сила — глобальний
## uniform, типово 1.
func test_sky_reflection_gain_is_a_global_uniform_on_by_default() -> void:
	assert_false(ProjectSettings.has_setting("shader_globals/sky_fallback"), "стару назву прибрано")
	assert_true(ProjectSettings.has_setting("shader_globals/sky_reflection_gain"))
	var entry: Dictionary = ProjectSettings.get_setting("shader_globals/sky_reflection_gain", {})
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
		if child is VisualInstance3D and not child is GroundSurface and not child is WaterSurface and not child is ReflectionProbe:
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
	board.set_kind(Vector2i(13, 10), Terrain.Kind.BRIDGE_DESTROYED)
	view.rebuild_tiles(board)
	assert_eq(probe.size, Vector3(30, 12, 26))
	assert_eq(probe.position, Vector3(12.5, 5.0, 10.5))
	assert_eq(probe.origin_offset, Vector3(0.0, -3.5, 0.0))


## Дві власні карти нормалей (tools/water_normals.py), імпортовані як стиснені
## в пам'яті відеокарти карти нормалей з міпмапами — не процедурний шум у шейдері.
func test_wave_normals_are_vram_compressed_normal_maps() -> void:
	view.build(_river())
	var mat: ShaderMaterial = _waters()[0].material_override
	for param: String in ["wave_a", "wave_b"]:
		var tex: Texture2D = mat.get_shader_parameter(param)
		assert_not_null(tex, param)
		if tex == null:
			continue
		assert_string_starts_with(tex.resource_path, "res://assets/water/water_normal_")
		var cfg := ConfigFile.new()
		assert_eq(cfg.load(tex.resource_path + ".import"), OK)
		assert_eq(cfg.get_value("params", "compress/mode"), 2, param + ": VRAM")
		assert_eq(cfg.get_value("params", "compress/normal_map"), 1, param + ": карта нормалей")
		assert_eq(cfg.get_value("params", "mipmaps/generate"), true, param + ": міпмапи")


## Перебудова (підірваний міст) просить зонд перезняти світ, щоб руїни були й у
## відбитті. Безпечно: накладки, юніти й міни — поза його маскою.
func test_rebuild_tiles_requests_a_probe_recapture() -> void:
	var board := _river()
	view.build(board)
	var before: int = view.probe_captures_requested
	board.set_kind(Vector2i(13, 10), Terrain.Kind.BRIDGE_DESTROYED)
	view.rebuild_tiles(board)
	assert_eq(view.probe_captures_requested, before + 1)
	assert_eq(view.reflection_probe().update_mode, ReflectionProbe.UPDATE_ONCE)


## Вода йде за гладкою віссю річки, а не за клітинками: карта висот у матеріалі води — та сама,
## що в землі, і вершини осі лежать нижче рівня води.
func test_water_height_map_follows_the_smooth_course() -> void:
	view.build(_river())
	var mat: ShaderMaterial = _waters()[0].material_override
	var h: TerrainHeight = view._height
	# Той самий об'єкт текстури: майданчики будівель оновлюють її на місці (без рендера get_image()
	# повертає дані з часу створення, тож порівнюється об'єкт, а не байти).
	assert_same(mat.get_shader_parameter("height_map"), h.texture(), "та сама карта висот")
	var img: Image = h.image()
	var s: int = h.samples
	var pts: PackedVector2Array = h.course.lines[0]
	var checked := 0
	for i in range(0, pts.size(), 4):
		var p: Vector2 = pts[i]
		if p.x < 0.0 or p.x > 25.0 or p.y < 0.0 or p.y > 21.0:
			continue
		checked += 1
		assert_lt(img.get_pixel(roundi((p.x + 0.5) * s), roundi((p.y + 0.5) * s)).r, TerrainHeight.WATER_LEVEL, "вода під віссю %s" % p)
	assert_gt(checked, 10)


## Прозорі об'єкти сортуються за центром: площина річки проти квада диму — хто ближче, той зверху, і дим
## уламків на березі зникав над водою. Вода — перша з прозорих і пише глибину, тож порядок вирішує глибина.
func test_water_is_drawn_first_of_the_transparent_and_writes_depth() -> void:
	view.build(_river())
	var mat: ShaderMaterial = _waters()[0].material_override
	assert_eq(mat.render_priority, WaterSurface.WATER_PRIORITY)
	assert_lt(WaterSurface.WATER_PRIORITY, ForestLayer.FOREST_PRIORITY, "раніше за тінь і глибинний прохід лісу")
	assert_lt(WaterSurface.WATER_PRIORITY, PropLayer.FENCE_ALPHA_PRIORITY, "раніше за прозорий паркан")
	assert_lt(WaterSurface.WATER_PRIORITY, 0, "раніше за дим (0)")
	assert_true(mat.shader.code.contains("depth_draw_always"), "вода пише глибину: прозоре під її рівнем вона ховає")
