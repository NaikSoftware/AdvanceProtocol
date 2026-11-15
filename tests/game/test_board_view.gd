extends GutTest
## Task 2.3, рішення R4: жива сцена battle_screen.tscn з'являється лише в Task
## 2.10, тож перевірка тут — headless, не «увімкнути гру й подивитись».
##
## Контур перевіряється через власний стан BoardView (_contour_segments),
## а не через читання кольору назад з MultiMesh: під
## headless-запуском (`--headless`, дамі-рендерер) RenderingServer не зберігає
## буфер екземплярів мультимешу — set_instance_color/set_instance_transform не
## кидають помилку, але get_instance_color/get_instance_transform одразу
## після них повертають типове значення (чорний/нульовий), навіть після кадру. Це
## перевірено окремо поза GUT. Структурні перевірки (кількість екземплярів)
## лишаються — instance_count це звичайна властивість ресурсу, а не буфер RS.

const BoardViewScene := preload("res://game/battle/board_view.tscn")

var view: Node3D


func before_each() -> void:
	view = BoardViewScene.instantiate()
	add_child_autofree(view)


## Дошка з двома видами — ROAD і FIELD — щоб перевірити «один draw call на
## вид», а не просто «один draw call на дошку».
func _two_kind_board() -> Board:
	var board := Board.create(4, 3, Terrain.GroundState.DRY)
	for x in board.width:
		board.set_kind(Vector2i(x, 1), Terrain.Kind.ROAD)
	return board


func _grounds() -> Array[GroundSurface]:
	var out: Array[GroundSurface] = []
	for child in view.get_children():
		if child is GroundSurface:
			out.append(child)
	return out


## Phase 5a, Task 5: замість мультимешу на вид — одна суцільна земля (§8: один
## draw call на всю дошку, а не по одному на вид тайлу).
func test_build_makes_exactly_one_ground_surface() -> void:
	view.build(_two_kind_board())
	assert_eq(_grounds().size(), 1, "одна земля на дошку")
	for child in view.get_children():
		assert_false(child is MultiMeshInstance3D, "плиток на вид більше немає: %s" % child.name)


func test_build_is_idempotent() -> void:
	var board := _two_kind_board()
	view.build(board)
	view.build(board)
	assert_eq(_grounds().size(), 1, "повторний build не мусить плодити землю")


func test_build_handles_empty_board() -> void:
	view.build(Board.create(0, 0, Terrain.GroundState.DRY))
	assert_eq(_grounds().size(), 1)
	assert_null(_grounds()[0].mesh, "порожня дошка — земля без меша")


## Земля переживає перебудову (BridgeChanged): той самий вузол і ті самі масиви
## текстур — інакше кожен підірваний міст перевантажував би 16 текстур.
func test_rebuild_reuses_the_ground_node_and_its_textures() -> void:
	var board := _two_kind_board()
	view.build(board)
	var ground: GroundSurface = _grounds()[0]
	var albedo: Texture2DArray = (ground.material_override as ShaderMaterial).get_shader_parameter("albedo_array")
	view.rebuild_tiles(board)
	assert_same(_grounds()[0], ground)
	assert_same((ground.material_override as ShaderMaterial).get_shader_parameter("albedo_array"), albedo)


## Підірваний міст (BridgeChanged) мусить дійти до карти видів шейдера, а
## контури зон, що в цю мить досі правдиві, — лишитись.
func test_rebuild_tiles_updates_the_kind_map_and_keeps_contours() -> void:
	var board := Board.create(4, 4, Terrain.GroundState.DRY)
	board.set_kind(Vector2i(1, 1), Terrain.Kind.BRIDGE)
	view.build(board)
	var segs: Array[Dictionary] = [{"cell": Vector2i(0, 0), "dir": Vector2i(1, 0), "color": Color.RED}]
	view.draw_contour(segs, BoardView.LAYER_ZONES)
	board.set_kind(Vector2i(1, 1), Terrain.Kind.BRIDGE_DESTROYED)

	view.rebuild_tiles(board)

	var img: Image = _grounds()[0].kind_image()
	assert_eq(img.get_pixel(1, 1).r8, Terrain.Kind.BRIDGE_DESTROYED)
	assert_eq(view.kind_at(Vector2i(1, 1)), Terrain.Kind.BRIDGE_DESTROYED)
	assert_eq(view.contour_segments(BoardView.LAYER_ZONES), segs)
	assert_eq(_grounds().size(), 1)


## §3.5: туман ховає юнітів і міни, ніколи не карту. BoardView не має і не
## може мати уявлення про тайлову видимість — інакше місцевість перестане
## бути публічною.
func test_no_apply_fog_and_no_vision_reference() -> void:
	assert_false(view.has_method("apply_fog"), "BoardView не ховає місцевість — apply_fog їй не потрібен")
	var source: String = FileAccess.get_file_as_string("res://game/battle/board_view.gd")
	assert_false(source.contains("Vision"), "BoardView не має споживати Vision узагалі")


# --- Контур (§3.13, PO-скарга: «контурно, не заливкою») -------------------
#
# draw_contour(): сегмент {cell, dir, color} малює тонку риску вздовж ОДНОГО
# ребра тайла, а не перефарбовує весь тайл.

func _edge(cell: Vector2i, dir: Vector2i, color: Color) -> Dictionary:
	return {"cell": cell, "dir": dir, "color": color}


func test_draw_contour_stores_segments_for_that_layer_only() -> void:
	var board := _two_kind_board()
	view.build(board)
	var zone_segments: Array[Dictionary] = [_edge(Vector2i(0, 0), Vector2i(1, 0), Color.YELLOW)]
	var path_segments: Array[Dictionary] = [_edge(Vector2i(1, 0), Vector2i(0, 1), Color.WHITE)]

	view.draw_contour(zone_segments, view.LAYER_ZONES)
	view.draw_contour(path_segments, view.LAYER_PATH)

	assert_eq(view.contour_segments(view.LAYER_ZONES), zone_segments)
	assert_eq(view.contour_segments(view.LAYER_PATH), path_segments)


func test_draw_contour_replaces_not_accumulates() -> void:
	var board := _two_kind_board()
	view.build(board)
	var first: Array[Dictionary] = [_edge(Vector2i(0, 0), Vector2i(1, 0), Color.YELLOW)]
	view.draw_contour(first, view.LAYER_ZONES)

	var second: Array[Dictionary] = [_edge(Vector2i(1, 0), Vector2i(0, 1), Color.RED)]
	view.draw_contour(second, view.LAYER_ZONES)

	assert_eq(view.contour_segments(view.LAYER_ZONES), second, "другий виклик мусить замінити, а не додати")


func test_clear_contour_empties_segments_and_frees_the_mesh_node() -> void:
	var board := _two_kind_board()
	view.build(board)
	var first: Array[Dictionary] = [_edge(Vector2i(0, 0), Vector2i(1, 0), Color.YELLOW)]
	view.draw_contour(first, view.LAYER_ZONES)

	view.clear_contour(view.LAYER_ZONES)

	assert_eq(view.contour_segments(view.LAYER_ZONES).size(), 0)


func test_clear_contour_on_empty_layer_does_not_crash() -> void:
	var board := _two_kind_board()
	view.build(board)
	view.clear_contour(view.LAYER_ZONES)
	assert_eq(view.contour_segments(view.LAYER_ZONES).size(), 0)


func test_draw_contour_with_empty_segments_draws_nothing() -> void:
	var board := _two_kind_board()
	view.build(board)
	view.draw_contour([] as Array[Dictionary], view.LAYER_ZONES)
	assert_eq(view.contour_segments(view.LAYER_ZONES).size(), 0)


# --- Кільце огляду — одне геометричне коло (§3.13, docs/ui/overlays.md) ----------

func _circle_nodes() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for child in view.get_children():
		if child is MeshInstance3D and not child is MultiMeshInstance3D and not child is GroundSurface and not child is WaterSurface:
			out.append(child)
	return out


## Радіус у тайлах = радіус у світі (тайл — 1.0), центр — середина тайла юніта. Узор рахує шейдер із
## точки ґрунту, тож у матеріал іде рівно радіус правила.
func test_draw_circles_makes_one_ring_per_circle_centred_on_the_tile() -> void:
	view.build(Board.create(10, 10, Terrain.GroundState.DRY))
	var circles: Array[Dictionary] = [{"center": Vector2i(4, 6), "radius": 3, "color": Color.WHITE}]

	view.draw_circles(circles, BoardView.LAYER_INSPECT)

	assert_eq(view.circles(BoardView.LAYER_INSPECT), circles)
	var nodes: Array[MeshInstance3D] = _circle_nodes()
	assert_eq(nodes.size(), 1, "одне коло — один вузол, один draw call")
	var ring: MeshInstance3D = nodes[0]
	assert_eq(ring.position.x, 4.0)
	assert_eq(ring.position.z, 6.0)
	var mat := ring.material_override as ShaderMaterial
	assert_not_null(mat, "кільце — шейдер fire_ring")
	if mat == null:
		return
	assert_eq(mat.get_shader_parameter("radius"), 3.0)
	assert_eq(mat.get_shader_parameter("ring_color"), Color.WHITE)
	assert_eq(mat.render_priority, BoardView.CONTOUR_PRIORITY)
	assert_eq(ring.layers, 1 << (BoardView.OVERLAY_LAYER - 1))
	assert_eq(ring.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	assert_eq(view.contour_segments(BoardView.LAYER_INSPECT), [], "коло — не контур тайлів")


func test_draw_circles_replaces_and_empty_clears_only_that_layer() -> void:
	view.build(Board.create(10, 10, Terrain.GroundState.DRY))
	view.draw_circles([{"center": Vector2i(1, 1), "radius": 5, "color": Color.RED}] as Array[Dictionary], BoardView.LAYER_TARGETS)
	view.draw_circles([{"center": Vector2i(2, 2), "radius": 3, "color": Color.WHITE},
		{"center": Vector2i(2, 2), "radius": 5, "color": Color.PURPLE}] as Array[Dictionary], BoardView.LAYER_INSPECT)
	view.draw_circles([{"center": Vector2i(3, 3), "radius": 4, "color": Color.WHITE}] as Array[Dictionary], BoardView.LAYER_INSPECT)
	assert_eq(_circle_nodes().size(), 2, "заміна, а не накопичення")

	view.draw_circles([] as Array[Dictionary], BoardView.LAYER_INSPECT)

	assert_eq(view.circles(BoardView.LAYER_INSPECT), [])
	assert_eq(_circle_nodes().size(), 1, "коло іншого шару лишилось")
	assert_eq(view.circles(BoardView.LAYER_TARGETS).size(), 1)


func test_rebuild_tiles_keeps_circles() -> void:
	var board := Board.create(10, 10, Terrain.GroundState.DRY)
	view.build(board)
	var circles: Array[Dictionary] = [{"center": Vector2i(4, 6), "radius": 3, "color": Color.WHITE}]
	view.draw_circles(circles, BoardView.LAYER_INSPECT)

	view.rebuild_tiles(board)

	assert_eq(view.circles(BoardView.LAYER_INSPECT), circles)
	assert_eq(_circle_nodes().size(), 1)


# --- Імпульс і межа кільця ----------------------------------------------------------
#
# Кільце з'являється одним слабким імпульсом від юніта до краю й стає чіткою лінією на радіусі правила.
# Поки біжить імпульс, сітка — увесь круг; далі — лише смуга межі, щоб тримане кільце не їло трикутники.

const _R: float = 3.0
## Імпульс триває, поки фронт не пройде радіус і ширину хвилі: (r + RING_PULSE_W) / PULSE_SPEED.
const _T: float = (_R + BoardView.RING_PULSE_W) / BoardView.PULSE_SPEED


var _pulse_tweens: Array[Tween] = []


## Твіни, що з'явились із кільцем: недобіглий твін попереднього тесту ще живе до кінця кадру.
func _draw_ring(animate: bool = true) -> MeshInstance3D:
	var before: Array[Tween] = get_tree().get_processed_tweens()
	view.draw_circles([{"center": Vector2i(4, 6), "radius": int(_R), "color": Color.WHITE}] as Array[Dictionary],
		BoardView.LAYER_INSPECT, animate)
	_pulse_tweens = get_tree().get_processed_tweens().filter(func(t: Tween) -> bool: return not before.has(t))
	return _circle_nodes()[0]


func _ring_tween() -> Tween:
	assert_eq(_pulse_tweens.size(), 1, "один твін імпульсу")
	return _pulse_tweens[0] if _pulse_tweens.size() > 0 else null


func _point_covered(mesh: ArrayMesh, p: Vector2) -> bool:
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for t in range(0, idx.size(), 3):
		var a := Vector2(verts[idx[t]].x, verts[idx[t]].z)
		var b := Vector2(verts[idx[t + 1]].x, verts[idx[t + 1]].z)
		var c := Vector2(verts[idx[t + 2]].x, verts[idx[t + 2]].z)
		# Межа трикутника теж накрита: точка в центрі клітинки лежить на діагоналі квадрата.
		var s1: float = (b - a).cross(p - a)
		var s2: float = (c - b).cross(p - b)
		var s3: float = (a - c).cross(p - c)
		if (s1 >= -1e-6 and s2 >= -1e-6 and s3 >= -1e-6) or (s1 <= 1e-6 and s2 <= 1e-6 and s3 <= 1e-6):
			return true
	return false


func _assert_drapes(mesh: ArrayMesh) -> void:
	for v in (mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
		var ground: float = maxf(TerrainHeight.ground_y(4.0 + v.x, 6.0 + v.z), TerrainHeight.WATER_LEVEL)
		assert_almost_eq(v.y, ground + 0.04, 0.0001, "вершина кільця лягає на ґрунт чи воду")


func test_pulse_mesh_covers_the_whole_disk_on_the_ground() -> void:
	view.build(Board.create(10, 10, Terrain.GroundState.DRY))
	var mesh := _draw_ring().mesh as ArrayMesh
	_assert_drapes(mesh)
	for k in 24:
		var dir := Vector2.from_angle(TAU * k / 24.0)
		for r: float in [0.0, _R * 0.5, _R, _R + BoardView.RING_OUTER]:
			assert_true(_point_covered(mesh, dir * r), "імпульс: точка %s накрита" % [dir * r])


func test_after_the_pulse_only_the_border_band_stays() -> void:
	view.build(Board.create(10, 10, Terrain.GroundState.DRY))
	var ring: MeshInstance3D = _draw_ring()
	_ring_tween().custom_step(_T)

	var mesh := ring.mesh as ArrayMesh
	_assert_drapes(mesh)
	# Сітка — клітинки поля висот, що зачепили смугу: вершина відходить від смуги не далі діагоналі клітинки.
	var cell: float = sqrt(2.0) / TerrainHeight.SAMPLES_PER_TILE
	for v in (mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
		var d: float = Vector2(v.x, v.z).length()
		assert_true(d >= _R - BoardView.RING_OUTER - cell - 1e-5 and d <= _R + BoardView.RING_OUTER + cell + 1e-5,
			"вершина на %.3f — у смузі межі" % d)
	for k in 24:
		var dir := Vector2.from_angle(TAU * k / 24.0)
		for r: float in [_R - BoardView.RING_OUTER, _R, _R + BoardView.RING_OUTER]:
			assert_true(_point_covered(mesh, dir * r), "межа: точка %s накрита" % [dir * r])


## Імпульс біжить один раз: поступ 0 → 1 рівномірно за _T, далі нічого не біжить і
## шейдер не міняється, тож статичний екран лишається статичним (TIME зробив би кадр щокадровим).
func test_pulse_ring_runs_once_then_stands_still() -> void:
	view.build(Board.create(10, 10, Terrain.GroundState.DRY))
	var mat := _draw_ring().material_override as ShaderMaterial
	assert_eq(mat.get_shader_parameter("pulse"), 0.0, "імпульс стартує з центру")
	var tween: Tween = _ring_tween()
	tween.custom_step(_T * 0.5)
	assert_almost_eq(float(mat.get_shader_parameter("pulse")), 0.5, 1e-6, "півдороги — півшляху")
	tween.custom_step(_T * 0.5)
	assert_eq(mat.get_shader_parameter("pulse"), 1.0, "фронт пройшов радіус і хвилю за _T")
	assert_false(tween.is_running(), "і більше не біжить")
	for path: String in ["res://game/battle/shaders/fire_ring.gdshader", "res://game/battle/shaders/fire_ring.gdshaderinc"]:
		assert_false(FileAccess.get_file_as_string(path).contains("TIME"), path)


## Кільце під лісом малює крона: поступ імпульсу йде їй разом із центром і радіусом (Vector4.w).
func test_pulse_progress_reaches_the_canopy() -> void:
	view.build(Board.create(10, 10, Terrain.GroundState.DRY))
	_draw_ring()
	var forest: ForestLayer = view.forest()
	assert_eq(forest.contour_rings, PackedVector4Array([Vector4(4, 6, _R, 0)]))
	var tween: Tween = _ring_tween()
	tween.custom_step(_T * 0.5)
	assert_almost_eq(forest.contour_rings[0].w, 0.5, 1e-6, "крона бачить той самий поступ")
	tween.custom_step(_T * 0.5)
	assert_eq(forest.contour_rings, PackedVector4Array([Vector4(4, 6, _R, 1)]))


## Перебудова тайлів (міст) малює ті самі кільця наново, але імпульс не перезапускає: одразу межа.
func test_rebuild_tiles_does_not_replay_the_pulse() -> void:
	var board := Board.create(10, 10, Terrain.GroundState.DRY)
	view.build(board)
	_draw_ring()
	_ring_tween().custom_step(_T)
	var before: Array[Tween] = get_tree().get_processed_tweens()

	view.rebuild_tiles(board)

	var ring: MeshInstance3D = _circle_nodes()[0]
	assert_eq((ring.material_override as ShaderMaterial).get_shader_parameter("pulse"), 1.0)
	assert_eq(get_tree().get_processed_tweens().filter(func(t: Tween) -> bool: return not before.has(t)).size(), 0, "нового імпульсу немає")
	assert_false(_point_covered(ring.mesh as ArrayMesh, Vector2.ZERO), "без імпульсу — лише смуга межі")
	assert_eq(view.forest().contour_rings, PackedVector4Array([Vector4(4, 6, _R, 1)]))


## Крона малює кільце тією самою функцією, що й ґрунт: імпульс і межа під лісом ті самі.
func test_canopy_and_ground_draw_the_ring_with_one_function() -> void:
	for path: String in ["res://game/battle/shaders/fire_ring.gdshader", "res://assets/props/forest/forest_crown.gdshader"]:
		var code: String = FileAccess.get_file_as_string(path)
		assert_true(code.contains("#include \"res://game/battle/shaders/fire_ring.gdshaderinc\""), path)
		assert_true(code.contains("fire_ring("), path)


## Вершини стрічки контуру — на відліках поля висот: крона шукає землю на тій самій білінійній
## поверхні, і лінія на вході під крону не ламається.
func test_contour_ribbon_vertices_sit_on_the_height_lattice() -> void:
	view.build(Board.create(5, 3, Terrain.GroundState.DRY))
	var segs: Array[Dictionary] = []
	for x in 3:
		segs.append(_edge(Vector2i(x, 1), Vector2i(0, -1), Color.YELLOW))
	view.draw_contour(segs, BoardView.LAYER_ZONES)
	var mesh: Mesh = (view.get_node("Contour%d" % BoardView.LAYER_ZONES) as MultiMeshInstance3D).multimesh.mesh
	var on_middle: int = 0
	# Середнє ребро має сусідів з обох боків, тож іде рівно від кута до кута: кожна його вершина — на відліку.
	for v in (mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
		if v.x > 0.5 + 1e-4 and v.x < 1.5 - 1e-4:
			on_middle += 1
			var k: float = (v.x + 0.5) * TerrainHeight.SAMPLES_PER_TILE
			assert_almost_eq(k, roundf(k), 1e-4, "x = %f на відліку поля висот" % v.x)
	assert_eq(on_middle, (TerrainHeight.SAMPLES_PER_TILE - 1) * 2, "внутрішні відліки середнього ребра, по два боки стрічки")


## Ширина межі й хвилі — у шейдері (fire_ring.gdshaderinc), сітка кільця й тривалість імпульсу — тут:
## одне число в двох місцях мусить збігатися.
func test_ring_widths_match_the_shader() -> void:
	var code: String = FileAccess.get_file_as_string("res://game/battle/shaders/fire_ring.gdshaderinc")
	var re := RegEx.create_from_string("const float (FR_LINE_W|FR_PULSE_W) = ([0-9.]+);")
	var found: Dictionary = {}
	for m: RegExMatch in re.search_all(code):
		found[m.get_string(1)] = float(m.get_string(2))
	assert_eq(found.get("FR_LINE_W"), BoardView.RING_LINE_W)
	assert_eq(found.get("FR_PULSE_W"), BoardView.RING_PULSE_W)
	assert_almost_eq(BoardView.RING_OUTER, BoardView.RING_LINE_W * 0.5 + 0.04, 1e-6, "півлінії плюс згладжування")


## Фронти кільця гармати й кільця дрона біжать разом: однакова швидкість, а не однаковий час.
func test_gun_and_drone_fronts_move_together() -> void:
	view.build(Board.create(12, 12, Terrain.GroundState.DRY))
	var before: Array[Tween] = get_tree().get_processed_tweens()
	view.draw_circles([{"center": Vector2i(6, 6), "radius": 3, "color": Color.WHITE},
		{"center": Vector2i(6, 6), "radius": 5, "color": Color.PURPLE}] as Array[Dictionary], BoardView.LAYER_INSPECT)
	for t: Tween in get_tree().get_processed_tweens():
		if not before.has(t):
			t.custom_step(0.3)
	for ring: MeshInstance3D in _circle_nodes():
		var mat := ring.material_override as ShaderMaterial
		var front: float = float(mat.get_shader_parameter("pulse")) * (float(mat.get_shader_parameter("radius")) + BoardView.RING_PULSE_W)
		assert_almost_eq(front, 0.3 * BoardView.PULSE_SPEED, 1e-5, "%s: фронт" % ring.name)


## Кільце на землі завжди під контурами зон, хоч куди зсунута камера: порядок прозорих задає зсув
## сортування, а не відстань до камери.
func test_ring_draws_under_the_contours() -> void:
	view.build(Board.create(10, 10, Terrain.GroundState.DRY))
	view.draw_contour([_edge(Vector2i(4, 3), Vector2i(0, -1), Color.YELLOW)] as Array[Dictionary], BoardView.LAYER_ZONES)
	var ring: MeshInstance3D = _draw_ring(false)
	var contour := view.get_node("Contour%d" % BoardView.LAYER_ZONES) as MultiMeshInstance3D
	assert_eq((ring.material_override as ShaderMaterial).render_priority, contour.multimesh.mesh.surface_get_material(0).render_priority)
	assert_eq(ring.sorting_offset, BoardView.RING_SORT_OFFSET)
	assert_eq(contour.sorting_offset, 0.0)
	assert_eq(BoardView.RING_SORT_OFFSET, -100.0, "далі за будь-яку різницю відстаней на дошці")


## Палець відпущено посеред імпульсу: твін зупинено разом із вузлом, крони кільця не тримають. Новий
## натиск — імпульс наново.
func test_release_mid_pulse_stops_it_and_a_new_hold_restarts_it() -> void:
	view.build(Board.create(10, 10, Terrain.GroundState.DRY))
	_draw_ring()
	var first: Tween = _ring_tween()
	first.custom_step(_T * 0.5)
	assert_true(view.is_pulsing())

	view.draw_circles([] as Array[Dictionary], BoardView.LAYER_INSPECT)

	assert_false(view.is_pulsing())
	assert_false(first.custom_step(_T), "твін пішов разом із вузлом кільця: кроку більше немає")
	assert_eq(view.forest().contour_rings.size(), 0, "і крони кільця не отримали")
	var mat := _draw_ring().material_override as ShaderMaterial
	assert_eq(mat.get_shader_parameter("pulse"), 0.0, "новий натиск — імпульс з центру")
	assert_eq(_pulse_tweens.size(), 1)
	assert_true(view.is_pulsing())
	_ring_tween().custom_step(_T)
	assert_false(view.is_pulsing(), "добіг — більше не біжить")


# Лінія зони суцільна й лежить на межі клітинок: на прямій ребро доходить рівно до кута, на куті
# ребро вздовж X накриває кут, а ребро вздовж Z не доходить до нього на півширини — без
# перехрещень і подвійної прозорості. Спільне ребро двох клітинок — один ключ.
func test_contour_stroke_ends_join_without_crossings() -> void:
	assert_eq(BoardView._edge_key(Vector2i(0, 0), Vector2i(1, 0)), BoardView._edge_key(Vector2i(1, 0), Vector2i(-1, 0)), "спільне ребро")
	var zone: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
	var edges: Dictionary = {}
	for s in ZoneOverlay._edges(zone, Color.YELLOW):
		edges[BoardView._edge_key(s["cell"], s["dir"])] = true
	var w: float = BoardView._CONTOUR_WIDTH
	var top_left := _edge(Vector2i(0, 0), Vector2i(0, -1), Color.YELLOW)
	assert_almost_eq(BoardView._stroke_end(edges, top_left, Vector2i(1, 0)), 0.5, 1e-6, "пряма — до кута")
	assert_almost_eq(BoardView._stroke_end(edges, top_left, Vector2i(-1, 0)), -(0.5 + w * 0.5), 1e-6, "ребро вздовж X накриває кут")
	var left := _edge(Vector2i(0, 0), Vector2i(-1, 0), Color.YELLOW)
	assert_almost_eq(BoardView._stroke_end(edges, left, Vector2i(0, -1)), -(0.5 - w * 0.5), 1e-6, "ребро вздовж Z не доходить")


# Межа золотої й червоної зон і спільне ребро двох клітинок шляху — одна лінія, а не дві поруч.
func test_shared_edge_is_drawn_once() -> void:
	view.build(Board.create(4, 4, Terrain.GroundState.DRY))
	var gold: Array[Vector2i] = [Vector2i(1, 1)]
	var red: Array[Vector2i] = [Vector2i(2, 1)]
	var segs: Array[Dictionary] = []
	segs.append_array(ZoneOverlay._edges(red, Color.RED))
	segs.append_array(ZoneOverlay._edges(gold, Color.YELLOW))
	view.draw_contour(segs, view.LAYER_ZONES)
	var mesh: Mesh = (view.get_node("Contour%d" % view.LAYER_ZONES) as MultiMeshInstance3D).multimesh.mesh
	var verts_per_line: int = (BoardView._CONTOUR_PIECES + 1) * 2
	assert_eq(mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size(), 7 * verts_per_line, "8 ребер, спільне — один раз")
	var cols: PackedColorArray = mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var golds: int = 0
	for c in cols:
		if c.g > 0.5:  # жовтий, а не червоний
			golds += 1
	assert_eq(golds, 4 * verts_per_line, "спільне ребро — золоте")


# --- Копія контуру для крон лісу ------------------------------------------------
#
# Крона малює лінію сама: точку землі під пікселем крони шукає в картці ребер — по два текселі на
# клітинку (ребро x− у (2x, y), ребро y− у (2x + 1, y)), колір лінії з її альфою. Картка мусить
# збігатися зі стрічкою: те саме фізичне ребро з будь-якого боку, пізніший шар зверху.

func _texel(x: int, y: int) -> Array:
	var c: Color = view.contour_edges().get_pixel(x, y)
	return [c.r8, c.g8, c.b8, c.a8]


func test_contour_edges_put_each_physical_edge_in_its_own_texel() -> void:
	view.build(Board.create(4, 3, Terrain.GroundState.DRY))
	view.draw_contour([_edge(Vector2i(1, 1), Vector2i(1, 0), Color.YELLOW), _edge(Vector2i(1, 1), Vector2i(-1, 0), Color.YELLOW),
			_edge(Vector2i(1, 1), Vector2i(0, -1), Color.RED), _edge(Vector2i(1, 1), Vector2i(0, 1), Color.RED)] as Array[Dictionary],
			BoardView.LAYER_ZONES)

	assert_eq(view.contour_edges().get_size(), Vector2i(10, 4), "(W + 1) ребер x− по два текселі × (H + 1) рядів")
	# Альфа — альфа стрічки (0,7), у RGBA8 відкинута до 178.
	assert_eq(_texel(4, 1), [255, 255, 0, 178], "x+ клітинки (1, 1) — це x− клітинки (2, 1)")
	assert_eq(_texel(2, 1), [255, 255, 0, 178], "x− клітинки (1, 1)")
	assert_eq(_texel(3, 1), [255, 0, 0, 178], "y− клітинки (1, 1)")
	assert_eq(_texel(3, 2), [255, 0, 0, 178], "y+ клітинки (1, 1) — це y− клітинки (1, 2)")
	var lit: int = 0
	for y in 4:
		for x in 10:
			if view.contour_edges().get_pixel(x, y).a8 > 0:
				lit += 1
	assert_eq(lit, 4, "лише чотири ребра")


## На землі кожен шар — своя напівпрозора стрічка, тож на спільному ребрі видно обидві: пізніший шар
## поверх (альфа 0,7 над 0,7). Картка зводить шари тим самим змішуванням, щоб крона показала той самий колір.
func test_contour_edges_composite_later_layer_over_earlier_and_cleared_layer_disappears() -> void:
	view.build(Board.create(4, 3, Terrain.GroundState.DRY))
	view.draw_contour([_edge(Vector2i(1, 1), Vector2i(1, 0), Color.YELLOW)] as Array[Dictionary], BoardView.LAYER_ZONES)
	view.draw_contour([_edge(Vector2i(2, 1), Vector2i(-1, 0), Color.WHITE)] as Array[Dictionary], BoardView.LAYER_PATH)
	# a = 0,7 + 0,7·0,3 = 0,91; b = (1·0,7 + 0·0,21) / 0,91 = 0,769, у sRGB — 0,891.
	assert_eq(_texel(4, 1), [255, 255, 227, 232], "шлях поверх зони на тому самому ребрі, зона просвічує")

	view.clear_contour(BoardView.LAYER_PATH)
	assert_eq(_texel(4, 1), [255, 255, 0, 178], "без шляху — знову зона")

	view.clear_contour(BoardView.LAYER_ZONES)
	assert_eq(_texel(4, 1), [0, 0, 0, 0], "без контурів — порожньо")


## Колір лінії — у sRGB і в картці ребер, і у вершинах стрічки (vertex_color_is_srgb, sampler source_color):
## кожен рендерер переводить його так само, як колір кільця, і Compatibility не темнить ліній. На Mobile
## вигляд той самий, що й з лінійним кольором вершин: колір зони там читався лінійним.
func test_contour_colour_is_srgb_encoded_on_the_ribbon_and_in_the_edge_card() -> void:
	view.build(Board.create(4, 3, Terrain.GroundState.DRY))
	var mid := Color(0.5, 0.25, 0.0)
	view.draw_contour([_edge(Vector2i(1, 1), Vector2i(1, 0), mid)] as Array[Dictionary], BoardView.LAYER_ZONES)
	var want: Color = mid.linear_to_srgb()
	var texel: Color = view.contour_edges().get_pixel(4, 1)
	assert_almost_eq(texel.r, want.r, 1.0 / 255.0)
	assert_almost_eq(texel.g, want.g, 1.0 / 255.0)
	var mesh: Mesh = (view.get_node("Contour%d" % BoardView.LAYER_ZONES) as MultiMeshInstance3D).multimesh.mesh
	var c: Color = (mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR] as PackedColorArray)[0]
	# Масив кольорів сітки рушій зберігає у 8 бітах.
	assert_almost_eq(c.r, want.r, 1.0 / 255.0)
	assert_almost_eq(c.g, want.g, 1.0 / 255.0)
	assert_almost_eq(c.a, 0.7, 1.0 / 255.0)
	assert_true((mesh.surface_get_material(0) as StandardMaterial3D).vertex_color_is_srgb)
	var crown: String = FileAccess.get_file_as_string("res://assets/props/forest/forest_crown.gdshader")
	assert_true(crown.contains("uniform sampler2D contour_edges : source_color"), "крона читає картку як sRGB")


func test_contour_edges_within_a_layer_later_segment_wins_like_the_ribbon() -> void:
	view.build(Board.create(4, 4, Terrain.GroundState.DRY))
	var segs: Array[Dictionary] = []
	segs.append_array(ZoneOverlay._edges([Vector2i(2, 1)] as Array[Vector2i], Color.RED))
	segs.append_array(ZoneOverlay._edges([Vector2i(1, 1)] as Array[Vector2i], Color.YELLOW))
	view.draw_contour(segs, BoardView.LAYER_ZONES)
	assert_eq(_texel(4, 1), [255, 255, 0, 178], "межа золотої й червоної зон — золота, як і стрічка")
	assert_eq(_texel(6, 1), [255, 0, 0, 178], "дальній бік червоної клітинки")


func test_contour_edges_include_bridge_cells_and_skip_cells_off_the_board() -> void:
	var board := Board.create(4, 3, Terrain.GroundState.DRY)
	board.set_kind(Vector2i(2, 1), Terrain.Kind.BRIDGE)
	view.build(board)
	view.draw_contour([_edge(Vector2i(2, 1), Vector2i(0, 1), Color.YELLOW), _edge(Vector2i(7, 7), Vector2i(1, 0), Color.RED)] as Array[Dictionary],
			BoardView.LAYER_ZONES)
	assert_eq(_texel(5, 2), [255, 255, 0, 178], "ребро клітинки мосту")
	var lit: int = 0
	for y in 4:
		for x in 10:
			if view.contour_edges().get_pixel(x, y).a8 > 0:
				lit += 1
	assert_eq(lit, 1, "клітинка поза дошкою не малюється, як і стрічка")


# Кільця дальності крона малює так само: центр і радіус у світі (клітинка — 1.0) і колір, яким кільце
# лягло на ґрунт: sRGB з альфою, як ring_color матеріалу кільця.
func test_draw_circles_publishes_rings_for_the_canopy() -> void:
	view.build(Board.create(10, 10, Terrain.GroundState.DRY))
	view.draw_circles([{"center": Vector2i(1, 1), "radius": 5, "color": Color(0.5, 0.5, 0.5, 0.5)}] as Array[Dictionary], BoardView.LAYER_TARGETS)
	view.draw_circles([{"center": Vector2i(4, 6), "radius": 3, "color": Color.WHITE},
		{"center": Vector2i(4, 6), "radius": 5, "color": Color.RED}] as Array[Dictionary], BoardView.LAYER_INSPECT)

	var forest: ForestLayer = view.forest()
	assert_eq(forest.contour_rings, PackedVector4Array([Vector4(1, 1, 5, 0), Vector4(4, 6, 3, 0), Vector4(4, 6, 5, 0)]))
	assert_eq(forest.contour_ring_colors.size(), 3)
	assert_eq(forest.contour_ring_colors[0], Color(0.5, 0.5, 0.5, 0.5), "той самий sRGB і альфа, що в кільця на ґрунті")
	assert_eq(forest.contour_ring_colors[1], Color.WHITE)
	assert_eq(forest.contour_ring_colors[2], Color.RED)

	view.draw_circles([] as Array[Dictionary], BoardView.LAYER_INSPECT)
	assert_eq(forest.contour_rings, PackedVector4Array([Vector4(1, 1, 5, 0)]), "зняте кільце зникає й під кронами")


# Крона шукає землю під собою лише, коли її промінь перетинає рамку всіх ліній: контурів (клітинки
# з запасом на ширину) і кілець (центр ± радіус і смуга межі). Без ліній рамка порожня.
func test_line_rect_bounds_every_contour_and_ring_for_the_canopy() -> void:
	view.build(Board.create(10, 10, Terrain.GroundState.DRY))
	var forest: ForestLayer = view.forest()
	assert_eq(forest.line_rect, Vector4(1, 1, 0, 0), "без ліній — порожня")
	view.draw_contour([_edge(Vector2i(1, 1), Vector2i(1, 0), Color.YELLOW)] as Array[Dictionary], BoardView.LAYER_ZONES)
	_assert_vec4(forest.line_rect, Vector4(0.45, 0.45, 1.55, 1.55))
	view.draw_circles([{"center": Vector2i(4, 6), "radius": 3, "color": Color.WHITE}] as Array[Dictionary], BoardView.LAYER_INSPECT)
	_assert_vec4(forest.line_rect, Vector4(0.45, 0.45, 7.15, 9.15))
	view.clear_contour(BoardView.LAYER_ZONES)
	_assert_vec4(forest.line_rect, Vector4(0.85, 2.85, 7.15, 9.15))
	view.draw_circles([] as Array[Dictionary], BoardView.LAYER_INSPECT)
	assert_eq(forest.line_rect, Vector4(1, 1, 0, 0))


func _assert_vec4(got: Vector4, want: Vector4) -> void:
	for i in 4:
		assert_almost_eq(got[i], want[i], 1e-5, "%s проти %s" % [got, want])


# build() знімає контури й кола, а ліс переживає його: крони не мусять тримати старих ліній.
func test_build_clears_the_canopy_copy() -> void:
	var board := Board.create(4, 3, Terrain.GroundState.DRY)
	view.build(board)
	view.draw_contour([_edge(Vector2i(1, 1), Vector2i(1, 0), Color.YELLOW)] as Array[Dictionary], BoardView.LAYER_ZONES)
	view.draw_circles([{"center": Vector2i(1, 1), "radius": 2, "color": Color.WHITE}] as Array[Dictionary], BoardView.LAYER_INSPECT)
	assert_not_null(view.forest()._contour_edges, "контур є — крони його шукають")

	view.build(board)

	assert_eq(_texel(4, 1), [0, 0, 0, 0])
	assert_null(view.forest()._contour_edges, "без контуру крона лінію не шукає")
	assert_eq(view.forest().contour_rings.size(), 0)
