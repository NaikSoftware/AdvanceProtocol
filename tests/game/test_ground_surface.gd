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


## Шейдер отримує саме цю карту видів і відповідність вид -> шар.
func test_material_receives_the_kind_map_and_layer_table() -> void:
	ground.build(_board_4x3(), 0)
	var mat := ground.material_override as ShaderMaterial
	assert_not_null(mat)
	var tex := mat.get_shader_parameter("kind_map") as ImageTexture
	assert_not_null(tex)
	assert_eq(tex.get_size(), Vector2(4, 3))
	var img: Image = tex.get_image()
	var board := _board_4x3()
	for y in 3:
		for x in 4:
			assert_eq(img.get_pixel(x, y).r8, board.kind_at(Vector2i(x, y)), "kind_map %d,%d" % [x, y])
	var table: PackedInt32Array = mat.get_shader_parameter("layer_for_kind")
	assert_eq(table.size(), Terrain.Kind.size())
	for kind: int in Terrain.Kind.values():
		assert_eq(table[kind], GroundSurface.TEX_LAYER_FOR_KIND[kind])
	assert_eq(mat.get_shader_parameter("map_origin"), Vector2(0, 0))


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
