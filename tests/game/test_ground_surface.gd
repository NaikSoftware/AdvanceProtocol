extends GutTest
## Phase 5a, Task 5: суцільна земля. Шейдер GUT не компілює (дамі-рендерер),
## тож тут перевіряється те, що шейдер отримує: карта видів, геометрія, uniform'и.

## S3TC/RGTC/BPTC на ПК, ETC2/ASTC на телефоні.
const _VRAM_FORMATS: Array[int] = [
	Image.FORMAT_DXT1, Image.FORMAT_DXT3, Image.FORMAT_DXT5, Image.FORMAT_RGTC_R, Image.FORMAT_RGTC_RG,
	Image.FORMAT_BPTC_RGBA, Image.FORMAT_ETC2_RGB8, Image.FORMAT_ETC2_RG11, Image.FORMAT_ETC2_RGBA8,
	Image.FORMAT_ASTC_4x4, Image.FORMAT_ASTC_8x8,
]

var ground: GroundSurface


func before_each() -> void:
	ground = GroundSurface.new()
	add_child_autofree(ground)


func _board_4x3() -> Board:
	var board := Board.create(4, 3, Terrain.GroundState.DRY)
	board.set_kind(Vector2i(0, 0), Terrain.Kind.ROAD)
	board.set_kind(Vector2i(3, 0), Terrain.Kind.WATER)
	board.set_kind(Vector2i(1, 1), Terrain.Kind.FOREST)
	board.set_kind(Vector2i(2, 2), Terrain.Kind.BRIDGE_DESTROYED)
	board.set_kind(Vector2i(3, 2), Terrain.Kind.MARSH)
	return board


func test_kind_image_matches_the_board() -> void:
	var board := _board_4x3()
	ground.build(board, 0)
	var img: Image = ground.kind_image()
	assert_eq(img.get_format(), Image.FORMAT_R8)
	assert_eq(img.get_size(), Vector2i(4, 3))
	for y in 3:
		for x in 4:
			assert_eq(img.get_pixel(x, y).r8, board.kind_at(Vector2i(x, y)), "клітинка %d,%d" % [x, y])


## Поза дошкою (Task 9) клітинка бере вид найближчої крайової.
func test_kind_image_margin_takes_the_nearest_edge_kind() -> void:
	var board := _board_4x3()
	ground.build(board, 2)
	var img: Image = ground.kind_image()
	assert_eq(img.get_size(), Vector2i(8, 7))
	assert_eq(img.get_pixel(0, 0).r8, Terrain.Kind.ROAD, "кут (-2,-2) -> (0,0)")
	assert_eq(img.get_pixel(7, 0).r8, Terrain.Kind.WATER, "кут (5,-2) -> (3,0)")
	assert_eq(img.get_pixel(7, 6).r8, Terrain.Kind.MARSH, "кут (5,4) -> (3,2)")
	assert_eq(img.get_pixel(3, 3).r8, Terrain.Kind.FOREST, "усередині дошки піксель зсунуто на відступ: (3,3) -> (1,1)")
	assert_eq(img.get_pixel(3, 0).r8, Terrain.Kind.FIELD, "(1,-2) -> (1,0)")


func test_mesh_covers_the_board_at_y_zero() -> void:
	ground.build(_board_4x3(), 0)
	var aabb: AABB = ground.transform * ground.get_aabb()
	assert_almost_eq(aabb.position.x, -0.5, 0.0001)
	assert_almost_eq(aabb.end.x, 3.5, 0.0001)
	assert_almost_eq(aabb.position.z, -0.5, 0.0001)
	assert_almost_eq(aabb.end.z, 2.5, 0.0001)
	assert_almost_eq(aabb.position.y, 0.0, 0.0001)
	assert_almost_eq(aabb.end.y, 0.0, 0.0001)


func test_mesh_with_margin_covers_the_margin_cells() -> void:
	ground.build(_board_4x3(), 2)
	var aabb: AABB = ground.transform * ground.get_aabb()
	assert_almost_eq(aabb.position.x, -2.5, 0.0001)
	assert_almost_eq(aabb.end.x, 5.5, 0.0001)
	assert_almost_eq(aabb.position.z, -2.5, 0.0001)
	assert_almost_eq(aabb.end.z, 4.5, 0.0001)


## Земля — шар 1: юніти на шарі 2 (UnitView.UNIT_LAYER), тінь лише від юнітів (§8).
func test_ground_is_on_render_layer_one_and_casts_no_shadow() -> void:
	ground.build(_board_4x3(), 0)
	assert_eq(ground.layers, 1)
	assert_eq(ground.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)


func test_every_kind_has_a_texture_layer() -> void:
	for kind: int in Terrain.Kind.values():
		assert_true(GroundSurface.TEX_LAYER_FOR_KIND.has(kind), "вид %d без шару текстури" % kind)
		var layer: int = GroundSurface.TEX_LAYER_FOR_KIND[kind]
		assert_between(layer, 0, GroundSurface.TEX_LAYERS.size() - 1)
	# Річка тече під мостом: під цілим мостом — русло, як під водою.
	assert_eq(GroundSurface.TEX_LAYERS[GroundSurface.TEX_LAYER_FOR_KIND[Terrain.Kind.BRIDGE]], "bank")
	assert_eq(GroundSurface.TEX_LAYERS[GroundSurface.TEX_LAYER_FOR_KIND[Terrain.Kind.WATER]], "bank")
	assert_eq(GroundSurface.TEX_LAYERS[GroundSurface.TEX_LAYER_FOR_KIND[Terrain.Kind.BUILDING]], "rubble")


## Шейдер отримує карти класів покриття (межі малює він, без сітки): у кожній клітинці рівно
## один слот; дорога — власна геометрія, тож її клітинка бере покриття сусідів.
func test_material_receives_class_maps_where_road_cells_take_the_neighbours_surface() -> void:
	ground.build(_board_4x3(), 0)
	var mat := ground.material_override as ShaderMaterial
	assert_not_null(mat)
	var slots: PackedInt32Array = mat.get_shader_parameter("class_layer")
	assert_eq(slots.size(), GroundSurface.CLASS_SLOTS)
	var maps: Array[Image] = [(mat.get_shader_parameter("class_map0") as ImageTexture).get_image(), (mat.get_shader_parameter("class_map1") as ImageTexture).get_image()]
	assert_eq(maps[0].get_size(), Vector2i(4, 3))
	var layer_at := func(c: Vector2i) -> int:
		var found: Array[int] = []
		for sl in GroundSurface.CLASS_SLOTS:
			if maps[sl / 4].get_pixel(c.x, c.y)[sl % 4] > 0.5:
				found.append(slots[sl])
		assert_eq(found.size(), 1, "один клас у клітинці %s" % c)
		return found[0] if found.size() == 1 else -1
	var name_at := func(c: Vector2i) -> String: return GroundSurface.TEX_LAYERS[layer_at.call(c)]
	assert_eq(name_at.call(Vector2i(0, 0)), "field", "дорога бере покриття сусідів")
	assert_eq(name_at.call(Vector2i(1, 1)), "forest")
	assert_eq(name_at.call(Vector2i(3, 2)), "marsh")
	assert_eq(name_at.call(Vector2i(3, 0)), "bank", "без рельєфу вода лишається руслом")
	assert_eq(name_at.call(Vector2i(2, 2)), "bank", "підірваний міст — русло, як вода")
	var board := _board_4x3()
	for y in 3:
		for x in 4:
			if board.kind_at(Vector2i(x, y)) == Terrain.Kind.FIELD:
				assert_eq(name_at.call(Vector2i(x, y)), "field", "поле %d,%d" % [x, y])
	assert_eq(mat.get_shader_parameter("yard_slot"), -1, "будівель нема — двору нема")
	assert_eq(mat.get_shader_parameter("map_origin"), Vector2(0, 0))
	assert_false(mat.get_shader_parameter("has_roads"), "без рельєфу доріг нема")


## Будівля стоїть у дворі: клас двору малюється шаром field (шейдер додає плями втоптаного
## ґрунту), а не щебенем.
func test_building_cells_get_a_yard_slot_drawn_with_the_field_layer() -> void:
	var board := _board_4x3()
	board.set_kind(Vector2i(2, 1), Terrain.Kind.BUILDING)
	ground.build(board, 0)
	var mat := ground.material_override as ShaderMaterial
	var slot: int = mat.get_shader_parameter("yard_slot")
	assert_true(slot >= 0, "є слот двору")
	var slots: PackedInt32Array = mat.get_shader_parameter("class_layer")
	assert_eq(GroundSurface.TEX_LAYERS[slots[slot]], "field")
	var img: Image = (mat.get_shader_parameter("class_map%d" % (slot / 4)) as ImageTexture).get_image()
	assert_gt(img.get_pixel(2, 1)[slot % 4], 0.5, "клітинка будівлі — у слоті двору")


## §3.12: MUD — правило, і земля мусить це показувати; DRY — не мусить.
func test_mud_ground_state_blends_field_and_hill_toward_mud() -> void:
	ground.build(Board.create(2, 2, Terrain.GroundState.MUD), 0)
	var mat := ground.material_override as ShaderMaterial
	assert_eq(mat.get_shader_parameter("mud_amount"), GroundSurface.MUD_BLEND)
	ground.build(Board.create(2, 2, Terrain.GroundState.DRY), 0)
	assert_eq((ground.material_override as ShaderMaterial).get_shader_parameter("mud_amount"), 0.0)


## Мобільний бюджет (§8): стиснені шари з готовими міпмапами, жодної генерації
## міпмап на CPU під час завантаження бою.
func test_texture_arrays_are_vram_compressed_with_mipmaps() -> void:
	ground.build(_board_4x3(), 0)
	var mat := ground.material_override as ShaderMaterial
	for param in ["albedo_array", "normal_array"]:
		var arr: Texture2DArray = mat.get_shader_parameter(param)
		assert_eq(arr.get_layers(), GroundSurface.TEX_LAYERS.size(), param)
		# get_layer_data() під дамі-рендерером — null, тож формат і міпмапи — з масиву.
		assert_has(_VRAM_FORMATS, arr.get_format(), "%s: стиснений формат" % param)
		assert_true(arr.has_mipmaps(), "%s: міпмапи з імпорту" % param)


## Масиви текстур (~17 МБ) живуть, поки живе земля: вийшли з бою — пам'ять повернулась.
func test_texture_arrays_are_released_with_the_ground() -> void:
	var g := GroundSurface.new()
	add_child(g)
	g.build(_board_4x3(), 0)
	var ref: WeakRef = weakref((g.material_override as ShaderMaterial).get_shader_parameter("albedo_array"))
	g.free()
	assert_null(ref.get_ref())


func test_empty_board_builds_without_errors() -> void:
	ground.build(Board.create(0, 0, Terrain.GroundState.DRY), 0)
	assert_null(ground.mesh)
	assert_eq(ground.kind_image().get_size(), Vector2i(0, 0))


## З рельєфом: дорога — власний шар (has_roads, поле й типи RoadCourse, шари асфальту, ґрунтівки
## й бруківки), розмір макротекстури — у метрах для кожного шару, а вода й міст малюються полем
## (берег задає висота).
func test_relief_build_passes_roads_layer_sizes_and_draws_water_as_field() -> void:
	var board := _board_4x3()
	var height := TerrainHeight.bake(board, 0, 7)
	ground.build(board, 0, PackedByteArray(), height)
	var mat := ground.material_override as ShaderMaterial
	assert_true(mat.get_shader_parameter("has_roads"))
	assert_not_null(mat.get_shader_parameter("road_field"))
	assert_not_null(mat.get_shader_parameter("road_type"))
	var road_layers: PackedInt32Array = mat.get_shader_parameter("road_layer")
	assert_eq(road_layers.size(), 3)
	var names: Array[String] = ground._macro_layers
	for i in 3:
		var want: String = GroundSurface.SURFACE_LAYERS[Terrain.Kind.ROAD][i]
		var got: String = names[road_layers[i]]
		assert_true(got == want or got == "road", "шар дороги %d: %s" % [i, got])
	var macro: PackedFloat32Array = mat.get_shader_parameter("macro_m")
	for i in names.size():
		assert_almost_eq(macro[i], float(GroundSurface.MACRO_M.get(names[i], GroundSurface.DEFAULT_MACRO_M)), 1e-4, names[i])
	var detail: PackedInt32Array = mat.get_shader_parameter("layer_detail")
	assert_eq(GroundSurface.TEX_LAYERS[detail[names.find("mud")]], "bank", "деталь багна — без колій шин")
	var slots: PackedInt32Array = mat.get_shader_parameter("class_layer")
	var map: Image = (mat.get_shader_parameter("class_map0") as ImageTexture).get_image()
	for c: Vector2i in [Vector2i(3, 0), Vector2i(2, 2)]:
		for sl in mini(4, GroundSurface.CLASS_SLOTS):
			if map.get_pixel(c.x, c.y)[sl] > 0.5:
				assert_eq(GroundSurface.TEX_LAYERS[slots[sl]], "field", "з рельєфом %s — поле" % c)


## Копія hash12 / vnoise / fbm і class_warp з ground.gdshader (terrain_noise.gdshaderinc): шейдер у
## GUT не виконується, а межу класів, яку бачить гравець, дає саме цей зсув.
static func _fract(x: float) -> float:
	return x - floorf(x)


static func _hash12(p: Vector2) -> float:
	var a := Vector3(_fract(p.x * 0.1031), _fract(p.y * 0.1031), _fract(p.x * 0.1031))
	var d: float = a.dot(Vector3(a.y, a.z, a.x) + Vector3.ONE * 33.33)
	a += Vector3.ONE * d
	return _fract((a.x + a.y) * a.z)


static func _vnoise(p: Vector2) -> float:
	var i := p.floor()
	var f := p - i
	var u := f * f * (Vector2(3.0, 3.0) - 2.0 * f)
	return lerpf(lerpf(_hash12(i), _hash12(i + Vector2(1, 0)), u.x),
		lerpf(_hash12(i + Vector2(0, 1)), _hash12(i + Vector2(1, 1)), u.x), u.y)


static func _fbm(p: Vector2) -> float:
	return 0.5 * _vnoise(p) + 0.3 * _vnoise(p * 2.03 + Vector2.ONE * 17.1) + 0.2 * _vnoise(p * 4.01 + Vector2.ONE * 31.7)


## mat2(c0, c1) * v у GLSL — стовпці c0, c1.
static func _rot(c0: Vector2, c1: Vector2, v: Vector2) -> Vector2:
	return c0 * v.x + c1 * v.y


static func _class_warp(p: Vector2) -> Vector2:
	var a0 := Vector2(0.8, 0.6)
	var a1 := Vector2(-0.6, 0.8)
	var b0 := Vector2(0.28, 0.96)
	var b1 := Vector2(-0.96, 0.28)
	var a := _rot(a0, a1, p) * 0.5
	var lobe := Vector2(_fbm(a + Vector2.ONE * 3.1), _fbm(a + Vector2(17.3, 5.9))) - Vector2.ONE * 0.5
	var b := _rot(b0, b1, p) * 4.0
	var bite := Vector2(_vnoise(b), _vnoise(b + Vector2.ONE * 9.7)) - Vector2.ONE * 0.5
	var c := _rot(a0, a1, _rot(b0, b1, p)) * 1.4
	var mid := Vector2(_vnoise(c + Vector2.ONE * 4.4), _vnoise(c + Vector2.ONE * 23.1)) - Vector2.ONE * 0.5
	return lobe * 2.0 + mid + bite * 0.32


## Клас-переможець у точці p (клітинки), як у fragment(): згладжена білінійна індикаторів класів
## (Ерміт, край затиснуто), за рівних — менший слот.
## CLASS_CORE з ground.gdshader.
const CLASS_CORE: float = 0.5


static func _class_at(p: Vector2, layers: PackedInt32Array, w: int, h: int, slot_of: Dictionary) -> int:
	var r: float = (p - p.round()).length()
	var g := p + _class_warp(p) * lerpf(CLASS_CORE, 1.0, smoothstep(0.0, 0.5, r))
	var i0 := g.floor()
	var f := g - i0
	f = f * f * (Vector2(3.0, 3.0) - 2.0 * f)
	var score: Dictionary = {}
	for k in 4:
		var cx: int = clampi(int(i0.x) + (k & 1), 0, w - 1)
		var cy: int = clampi(int(i0.y) + (k >> 1), 0, h - 1)
		var wt: float = (f.x if k & 1 else 1.0 - f.x) * (f.y if k >> 1 else 1.0 - f.y)
		var l: int = layers[cy * w + cx]
		score[l] = float(score.get(l, 0.0)) + wt
	var best: int = -1
	var top: float = -1.0
	for l: int in score:
		var v: float = score[l]
		if v > top + 1e-6 or (v > top - 1e-6 and slot_of[l] < slot_of[best]):
			best = l
			top = maxf(top, v)
	return best


## Кожен вид міняє число руху (§3.2), тож гравець мусить бачити вид кожної клітинки: зсув межі
## класів (±2.5 м) лишає власному класу клітинки ≥ 25 % її площі. Дорогу, воду й міст малює
## власна геометрія; пагорб з рельєфом — поле, а сам пагорб дає висота (test_terrain_height).
func test_every_cell_shows_its_own_class_over_a_quarter_of_its_area() -> void:
	const N: int = 6
	var names: Array[String] = GroundSurface._macro_layer_names()
	var table: PackedInt32Array = GroundSurface._surface_table(names)
	var field: int = GroundSurface.TEX_LAYER_FOR_KIND[Terrain.Kind.FIELD]
	for sub in GroundSurface.SURFACES_PER_KIND:
		table[Terrain.Kind.HILL * GroundSurface.SURFACES_PER_KIND + sub] = field
	var field_group: Dictionary = {field: true}
	for sub in GroundSurface.SURFACES_PER_KIND:
		field_group[table[Terrain.Kind.FIELD * GroundSurface.SURFACES_PER_KIND + sub]] = true
	var skip: Array = [Terrain.Kind.ROAD, Terrain.Kind.WATER, Terrain.Kind.BRIDGE, Terrain.Kind.BRIDGE_DESTROYED]
	for file in ["crossroads", "ridge", "river"]:
		var m: MapData = load("res://maps/%s.tres" % file) as MapData
		var board: Board = m.to_board()
		var layers: PackedInt32Array = GroundSurface.class_layers(board, 0, m.surface, table, true)
		var slot_of: Dictionary = {}
		for l in layers:
			if not slot_of.has(l):
				slot_of[l] = slot_of.size()
		var worst: float = 1.0
		var bad: Array[String] = []
		for y in board.height:
			for x in board.width:
				if skip.has(board.kind_at(Vector2i(x, y))):
					continue
				var own: int = layers[y * board.width + x]
				var hit: int = 0
				for j in N:
					for i in N:
						var p := Vector2(x - 0.5 + (i + 0.5) / N, y - 0.5 + (j + 0.5) / N)
						var c: int = _class_at(p, layers, board.width, board.height, slot_of)
						if c == own or (field_group.has(c) and field_group.has(own)):
							hit += 1
				var share: float = float(hit) / (N * N)
				worst = minf(worst, share)
				if share < 0.25:
					bad.append("(%d, %d) %s %.0f %%" % [x, y, Terrain.Kind.keys()[board.kind_at(Vector2i(x, y))], share * 100.0])
		gut.p("%s: найменша частка власного класу %.0f %%" % [file, worst * 100.0])
		assert_eq(bad.size(), 0, "%s: клітинки без свого виду: %s" % [file, bad.slice(0, 10)])


# Пора року: сезонний файл, де він є; інакше — звичайний. Шар без сезонних файлів (берег,
# асфальт) і невідома пора лишаються як є, тож пора не ламає жодної карти.
func test_macro_path_takes_the_season_file_and_falls_back_to_the_plain_one() -> void:
	var dir := "res://assets/terrain/macro/"
	assert_eq(GroundSurface.macro_path("field", 0, &"summer"), dir + "field_albedo_0.summer.png")
	assert_eq(GroundSurface.macro_path("field", 1, &"early"), dir + "field_albedo_1.early.png")
	assert_eq(GroundSurface.macro_path("bank", 0, &"summer"), dir + "bank_albedo_0.png")
	assert_eq(GroundSurface.macro_path("road", 1, &"early"), dir + "road_albedo_0.png")
	assert_eq(GroundSurface.macro_path("field", 0, &"winter"), dir + "field_albedo_0.png")
	assert_eq(GroundSurface.macro_path("field", 1), dir + "field_albedo_1.png")


# Бракуючий варіант бере варіант 0 тієї ж пори, а не звичайний файл: інакше в літній ріллі
# лягли б осінні латки.
func test_missing_season_variant_takes_variant_zero_of_the_same_season() -> void:
	var dir := "res://assets/terrain/macro/"
	assert_eq(GroundSurface.macro_path("ploughed", 1, &"summer"), dir + "ploughed_albedo_0.summer.png")
	assert_eq(GroundSurface.macro_path("marsh", 1), dir + "marsh_albedo_0.png")


# Рілля — прямокутні поля: зв'язні групи клітинок дають номер у кожній клітинці й прямокутник.
func test_plough_fields_gives_one_rectangle_per_connected_group() -> void:
	var P := 9
	# 5×4: поле 3×2 угорі ліворуч, поле 1×3 праворуч, решта — 1.
	var cells := PackedInt32Array([
		P, P, P, 1, P,
		P, P, P, 1, P,
		1, 1, 1, 1, P,
		1, 1, 1, 1, 1,
	])
	var res: Array = GroundSurface.plough_fields(cells, 5, P)
	var ids: PackedByteArray = res[0]
	var rects: Array[Rect2i] = res[1]
	assert_eq(rects.size(), 2)
	assert_eq(rects[0], Rect2i(0, 0, 3, 2))
	assert_eq(rects[1], Rect2i(4, 0, 1, 3))
	assert_eq(ids[0], 1)
	assert_eq(ids[4], 2)
	assert_eq(ids[3], 0)
	assert_eq(GroundSurface.plough_fields(cells, 5, -1)[1].size(), 0, "без шару ріллі полів нема")


# Понад MAX_PLOUGH_FIELDS поля мовчки лишились би лукою: жодна карта не має їх стільки.
# Рахується світ разом із кільцем — те, що build() справді отримує від BoardView.
func test_every_map_fits_its_plough_fields_into_the_shader() -> void:
	var names: Array[String] = GroundSurface._macro_layer_names()
	var table: PackedInt32Array = GroundSurface._surface_table(names)
	var plough: int = names.find("ploughed")
	assert_gt(plough, -1)
	for file in ["crossroads", "ridge", "river"]:
		var m: MapData = load("res://maps/%s.tres" % file) as MapData
		var board: Board = m.to_board()
		var world: Board = Surroundings.world_board(board, m) if Surroundings.ring_of(m) > 0 else board
		var surface: PackedByteArray = Surroundings.world_surface(m) if Surroundings.ring_of(m) > 0 else m.surface
		var cells: PackedInt32Array = GroundSurface.plough_cells(world, 0, surface, table, true)
		var n: int = (GroundSurface.plough_fields(cells, world.width, plough)[1] as Array).size()
		gut.p("%s: полів ріллі у світі %d" % [file, n])
		assert_between(n, 1, GroundSurface.MAX_PLOUGH_FIELDS - 1, file)


# Дорога між двома полями лишається дорогою: голосування сусідів не робить її ріллею й не
# зливає поля в одне через неї.
func test_road_between_ploughed_cells_splits_the_fields() -> void:
	var names: Array[String] = GroundSurface._macro_layer_names()
	var table: PackedInt32Array = GroundSurface._surface_table(names)
	var plough: int = names.find("ploughed")
	var board := Board.create(5, 1, Terrain.GroundState.DRY)
	board.set_kind(Vector2i(2, 0), Terrain.Kind.ROAD)
	var surface := PackedByteArray([1, 1, 0, 1, 1])
	var cells: PackedInt32Array = GroundSurface.plough_cells(board, 0, surface, table, true)
	assert_eq(cells[2], -1, "дорога не бере шар ріллі від сусідів")
	assert_eq((GroundSurface.plough_fields(cells, 5, plough)[1] as Array).size(), 2)


# Біля річки стоячої води нема: кожна клітинка води й кожна сусідня з нею має в bank_mask 255
# (шейдер гасить там вікна болота), а клітинка далі за одну від води — 0.
func test_bank_mask_covers_every_cell_next_to_water() -> void:
	for file in ["crossroads", "ridge", "river"]:
		var m: MapData = load("res://maps/%s.tres" % file) as MapData
		var board: Board = m.to_board()
		var mask: PackedByteArray = GroundSurface.bank_mask(board, 0)
		var bad: Array[Vector2i] = []
		for y in board.height:
			for x in board.width:
				var near := false
				var far := true
				for dy in range(-2, 3):
					for dx in range(-2, 3):
						var q := Vector2i(x + dx, y + dy)
						if q.x < 0 or q.y < 0 or q.x >= board.width or q.y >= board.height:
							continue
						var k: int = board.kind_at(q)
						if k == Terrain.Kind.WATER or k == Terrain.Kind.BRIDGE or k == Terrain.Kind.BRIDGE_DESTROYED:
							far = false
							if absi(dx) <= 1 and absi(dy) <= 1:
								near = true
				var v: int = mask[y * board.width + x]
				if (near and v != 255) or (far and v != 0):
					bad.append(Vector2i(x, y))
		assert_eq(bad.size(), 0, "%s: %s" % [file, bad.slice(0, 8)])


func test_build_passes_the_bank_map_to_the_shader() -> void:
	var board := Board.create(3, 1, Terrain.GroundState.DRY)
	board.set_kind(Vector2i(0, 0), Terrain.Kind.WATER)
	ground.build(board, 0)
	var tex: Texture2D = (ground.material_override as ShaderMaterial).get_shader_parameter("bank_map")
	assert_not_null(tex)
	var img: Image = tex.get_image()
	assert_eq(img.get_pixel(1, 0).r8, 255, "сусід води — без стоячої води")
	assert_eq(img.get_pixel(2, 0).r8, 0)


## Нормаль і похил шейдер бере з карти похилу в пікселі, а не з вершин: без неї меш землі мусив би
## тримати рельєф густотою вершин.
func test_build_passes_the_gradient_map_to_the_shader() -> void:
	var board := Board.create(4, 3, Terrain.GroundState.DRY)
	var th := TerrainHeight.bake(board, 0, 3)
	ground.build(board, 0, PackedByteArray(), th)
	var mat := ground.material_override as ShaderMaterial
	assert_same(mat.get_shader_parameter("gradient_map"), th.gradient_texture())
	assert_same(mat.get_shader_parameter("height_map"), th.texture())


# Калюжі лише на рівному й у низинах: пагорб, схил понад ~7.5° і гребінь — без стоячої води.
func test_puddle_gate_keeps_hills_slopes_and_crests_dry() -> void:
	assert_almost_eq(GroundSurface.puddle_gate(0.0, 0.0, 0.0), 1.0, 1e-4, "рівне — калюжа можлива")
	assert_almost_eq(GroundSurface.puddle_gate(0.0, -0.2, 0.0), 1.0, 1e-4, "низина — калюжа можлива")
	assert_eq(GroundSurface.puddle_gate(0.0, 0.0, 1.0), 0.0, "клітинка пагорба")
	assert_eq(GroundSurface.puddle_gate(tan(deg_to_rad(7.5)), 0.0, 0.0), 0.0, "схил 7.5°")
	assert_eq(GroundSurface.puddle_gate(tan(deg_to_rad(20.0)), -0.2, 0.0), 0.0, "крутий схил і в низині")
	assert_eq(GroundSurface.puddle_gate(0.0, 0.1, 0.0), 0.0, "гребінь")
	assert_lt(GroundSurface.puddle_gate(tan(deg_to_rad(6.0)), 0.0, 0.0), 1.0, "між 5° і 7.5° калюжа вже слабне")


# Кожна клітинка пагорба на картах позначена в hill_mask: шейдер не кладе туди калюж.
func test_hill_mask_marks_every_hill_cell() -> void:
	for file in ["crossroads", "ridge", "river"]:
		var m: MapData = load("res://maps/%s.tres" % file) as MapData
		var board: Board = m.to_board()
		var mask: PackedByteArray = GroundSurface.hill_mask(board, 0)
		var bad := 0
		for y in board.height:
			for x in board.width:
				var hill: bool = board.kind_at(Vector2i(x, y)) == Terrain.Kind.HILL
				if (mask[y * board.width + x] == 255) != hill:
					bad += 1
				if hill:
					assert_eq(GroundSurface.puddle_gate(0.0, 0.0, mask[y * board.width + x] / 255.0), 0.0)
		assert_eq(bad, 0, file)


## Дорога біля будинку не бере покриття двору, інакше заокруглення розвилки лягає сірим ґрунтом двору.
func test_road_cell_beside_a_building_takes_the_other_neighbour_not_the_yard() -> void:
	var board := Board.create(3, 3, Terrain.GroundState.DRY)
	board.set_kind(Vector2i(1, 1), Terrain.Kind.ROAD)
	board.set_kind(Vector2i(0, 1), Terrain.Kind.BUILDING)
	board.set_kind(Vector2i(1, 0), Terrain.Kind.BUILDING)
	board.set_kind(Vector2i(1, 2), Terrain.Kind.BUILDING)
	# Двори в більшості (3 проти 1): без правила голосування перемагав би двір.
	board.set_kind(Vector2i(2, 1), Terrain.Kind.FOREST)
	ground.build(board, 0)
	var mat := ground.material_override as ShaderMaterial
	var slots: PackedInt32Array = mat.get_shader_parameter("class_layer")
	var maps: Array[Image] = [(mat.get_shader_parameter("class_map0") as ImageTexture).get_image(), (mat.get_shader_parameter("class_map1") as ImageTexture).get_image()]
	var found: Array[String] = []
	for sl in GroundSurface.CLASS_SLOTS:
		if maps[sl / 4].get_pixel(1, 1)[sl % 4] > 0.5:
			found.append(GroundSurface.TEX_LAYERS[slots[sl]])
	assert_eq(found, ["forest"] as Array[String])


## Шейдер малює кришіння асфальту лише біля кінців, які дає RoadCourse: вони мусять дійти до матеріалу.
func test_relief_build_passes_the_asphalt_ends_to_the_shader() -> void:
	var m: MapData = load("res://maps/crossroads.tres")
	var board: Board = m.to_board()
	var height := TerrainHeight.bake(board, 0, m.name_key.hash(), m.surface)
	ground.build(board, 0, m.surface, height)
	var mat := ground.material_override as ShaderMaterial
	var ends: PackedVector2Array = height.roads.asphalt_ends()
	assert_gt(ends.size(), 0)
	assert_eq(mat.get_shader_parameter("asphalt_end_count"), ends.size())
	var sent: PackedVector4Array = mat.get_shader_parameter("asphalt_ends")
	assert_eq(sent.size(), GroundSurface.ASPHALT_ENDS_MAX)
	for i in ends.size():
		assert_eq(Vector2(sent[i].x, sent[i].y), ends[i])
