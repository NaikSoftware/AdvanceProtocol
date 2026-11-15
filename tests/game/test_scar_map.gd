extends GutTest
## Карта шрамів: одна текстура на дошку, яку читає шейдер землі (Decal на Mobile —
## не більше 8 на меш, на Compatibility — жодного). Шрами бачить лише той, хто
## розвідав тайл (§3.5): маска `seen` глядача множить їх у шейдері.

var scars: ScarMap


func before_each() -> void:
	scars = ScarMap.new(Vector2i(8, 6))


func test_one_texel_is_a_quarter_metre() -> void:
	assert_eq(ScarMap.PX_PER_TILE, 32, "1 тайл = 8 м, тексель = 0,25 м")
	assert_eq(scars.image().get_size(), Vector2i(8 * 32, 6 * 32))


## Пляма уламків 10–14 м: темне ядро в центрі тайла, нуль за 7 м від центру.
func test_wreck_scorch_is_darkest_at_the_centre_and_ends_within_seven_metres() -> void:
	scars.stamp_scorch(Vector2i(3, 2))
	var c := Vector2i(3 * 32 + 16, 2 * 32 + 16)
	assert_eq(scars.image().get_pixelv(c).r8, 255, "ядро — повна сила")
	var r: int = int(ScarMap.SCORCH_RADIUS_M * 4.0)
	assert_eq(r, 28)
	for d: Vector2i in [Vector2i(r, 0), Vector2i(-r, 0), Vector2i(0, r), Vector2i(0, -r)]:
		assert_eq(scars.image().get_pixelv(c + d).r8, 0, "за 7 м від центру плями вже нема")
	assert_eq(scars.image().get_pixelv(Vector2i(0, 0)).r8, 0)


## Двічі поставлена пляма (бій зі збереження перемальовує уламки зі стану) не темнішає.
func test_stamping_twice_does_not_darken_further() -> void:
	scars.stamp_scorch(Vector2i(3, 2))
	var once: PackedByteArray = scars.image().get_data()
	scars.stamp_scorch(Vector2i(3, 2))
	assert_eq(scars.image().get_data(), once)


func test_seen_mask_is_one_texel_per_tile_from_the_viewers_seen() -> void:
	var state := BattleState.create(Board.create(8, 6, Terrain.GroundState.DRY), 2, 3)
	state.vision[1].seen[2 * 8 + 5] = 1
	scars.show_for(state.vision[1])
	assert_eq(scars.mask().get_size(), Vector2i(8, 6))
	assert_eq(scars.mask().get_pixel(5, 2).r8, 255)
	assert_eq(scars.mask().get_pixel(4, 2).r8, 0, "нерозвіданий тайл ховає свої шрами")


func test_apply_hands_both_textures_to_the_ground_material() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://game/battle/shaders/ground.gdshader")
	scars.apply(mat)
	assert_eq(mat.get_shader_parameter("has_scars"), true)
	assert_eq(mat.get_shader_parameter("scar_map"), scars.texture())
	assert_eq(mat.get_shader_parameter("scar_seen"), scars.mask_texture())
	assert_eq(mat.get_shader_parameter("scar_size"), Vector2(8, 6))


## Вирв нема: єдиний шрам бою на ґрунті — пляма під уламками в R (з попелом в A); G і B
## лишаються нулями.
func test_wreck_scorch_writes_only_scorch_and_ash() -> void:
	scars.stamp_scorch(Vector2i(3, 2))
	var img: Image = scars.image()
	for y in img.get_height():
		for x in img.get_width():
			var c: Color = img.get_pixel(x, y)
			assert_true(c.g8 == 0 and c.b8 == 0, "G і B вільні (%d, %d)" % [x, y])
			if c.g8 != 0 or c.b8 != 0:
				return


## Пляма уламків (7 м) заходить на сусідні тайли: на нерозвіданому джерелі її край на розвіданому
## сусідові видав би бій. Малюється, лише коли розвідане джерело; знову сховане — зникає.
func test_scorch_shows_only_once_its_source_cell_is_seen() -> void:
	var state := BattleState.create(Board.create(8, 6, Terrain.GroundState.DRY), 2, 3)
	var v: Vision = state.vision[0]
	v.seen.fill(0)
	v.seen[2 * 8 + 2] = 1
	scars.show_for(v)
	scars.stamp_scorch(Vector2i(3, 2))
	# край плями на сусідньому (2, 2): 4 текселі від межі тайлів у бік (3, 2)
	var edge := Vector2i(3 * 32 - 4, 2 * 32 + 16)
	assert_eq(scars.image().get_pixelv(edge).r8, 0, "джерело нерозвідане — краю на сусідові нема")
	assert_false(scars.is_painted(Vector2i(3, 2)))
	v.seen[2 * 8 + 3] = 1
	scars.show_for(v)
	assert_gt(scars.image().get_pixelv(edge).r8, 0, "джерело розвідане — край на місці")
	scars.reset_scorches()
	scars.show_for(v)
	assert_eq(scars.image().get_pixelv(edge).r8, 0, "перебудова без загиблого — плями нема")


## Маска розвіданого — тексель на тайл, і читається найближчим текселем: лінійна фільтрація розмазувала б
## шрам на пів тайла в нерозвідане (§3.5).
func test_ground_shader_samples_the_seen_mask_nearest() -> void:
	var code: String = (load("res://game/battle/shaders/ground.gdshader") as Shader).code
	var decl := RegEx.create_from_string("uniform\\s+sampler2D\\s+scar_seen\\s*:([^;]*);")
	var m: RegExMatch = decl.search(code)
	assert_not_null(m, "маска оголошена")
	if m != null:
		assert_true(m.get_string(1).contains("filter_nearest"), "найближчим текселем")
		assert_false(m.get_string(1).contains("filter_linear"))


## Слід поваленого — як пляма: малюється, лише коли розвіданий тайл, звідки він почався, і не перелазить
## із нерозвіданого на розвіданий сусідній тайл.
func test_scuff_shows_only_once_its_source_cell_is_seen() -> void:
	var state := BattleState.create(Board.create(8, 6, Terrain.GroundState.DRY), 2, 3)
	var v: Vision = state.vision[0]
	v.seen.fill(0)
	v.seen[2 * 8 + 2] = 1
	scars.show_for(v)
	scars.stamp_scuff(Vector3(3, 0, 2), Vector3(2, 0, 2))  # з нерозвіданого (3, 2) на розвіданий (2, 2)
	var on_seen := Vector2i(2 * 32 + 16, 2 * 32 + 16)
	assert_eq(scars.image().get_pixelv(on_seen).r8, 0, "джерело нерозвідане — сліду на сусідові нема")
	v.seen[2 * 8 + 3] = 1
	scars.show_for(v)
	assert_gt(scars.image().get_pixelv(on_seen).r8, 0, "джерело розвідане — слід на місці")


## Поки показане лише росте, нові плями домальовуються, а вже намальовані не перемальовуються з нуля.
func test_growing_seen_set_paints_only_new_stamps() -> void:
	var state := BattleState.create(Board.create(8, 6, Terrain.GroundState.DRY), 2, 3)
	var v: Vision = state.vision[0]
	v.seen.fill(0)
	v.seen[2 * 8 + 3] = 1
	scars.show_for(v)
	scars.stamp_scorch(Vector2i(3, 2))
	scars.stamp_scorch(Vector2i(6, 4))
	# позначка поверх намальованої плями: повне перемальовування стерло б її
	scars.image().set_pixel(3 * 32 + 16, 2 * 32 + 16, Color(1, 1, 1, 1))
	v.seen[4 * 8 + 6] = 1
	scars.show_for(v)
	assert_true(scars.is_painted(Vector2i(6, 4)), "нова пляма домальована")
	assert_eq(scars.image().get_pixel(3 * 32 + 16, 2 * 32 + 16).g8, 255, "стара не перемальована з нуля")


## Крайній пропс (паркан на межі клітинок): слід його падіння прив'язаний до клітинки, з якої його повалено, а
## не до точки падіння — та може лежати на вже розвіданій сусідній клітинці й видати техніку на нерозвіданій.
func test_edge_scuff_follows_its_crush_cell_not_its_pivot() -> void:
	var state := BattleState.create(Board.create(8, 6, Terrain.GroundState.DRY), 2, 3)
	var v: Vision = state.vision[0]
	v.seen.fill(0)
	v.seen[2 * 8 + 2] = 1
	scars.show_for(v)
	# точка падіння на межі (2,5; 2) округлюється в розвідану (2, 2), але повалено з нерозвіданої (3, 2)
	scars.stamp_scuff(Vector3(2.5, 0, 2), Vector3(1.6, 0, 2), Vector2i(3, 2))
	var on_seen := Vector2i(2 * 32 + 10, 2 * 32 + 16)
	assert_eq(scars.image().get_pixelv(on_seen).r8, 0, "з нерозвіданої клітинки — сліду нема")
	v.seen[2 * 8 + 3] = 1
	scars.show_for(v)
	assert_gt(scars.image().get_pixelv(on_seen).r8, 0, "клітинку розвідано — слід на місці")


## Показ звужується (інший глядач): слід, чиє джерело новий глядач не розвідав, зникає.
func test_painted_scuff_disappears_for_a_viewer_who_has_not_seen_its_source() -> void:
	var state := BattleState.create(Board.create(8, 6, Terrain.GroundState.DRY), 2, 3)
	var a: Vision = state.vision[0]
	var b: Vision = state.vision[1]
	a.seen.fill(0)
	b.seen.fill(0)
	a.seen[2 * 8 + 3] = 1
	a.seen[2 * 8 + 2] = 1
	b.seen[2 * 8 + 2] = 1
	scars.show_for(a)
	scars.stamp_scuff(Vector3(3, 0, 2), Vector3(2, 0, 2), Vector2i(3, 2))
	var on_seen := Vector2i(2 * 32 + 16, 2 * 32 + 16)
	assert_gt(scars.image().get_pixelv(on_seen).r8, 0, "перший глядач бачить слід")
	scars.show_for(b)
	assert_eq(scars.image().get_pixelv(on_seen).r8, 0, "другий джерела не розвідав — сліду нема")
