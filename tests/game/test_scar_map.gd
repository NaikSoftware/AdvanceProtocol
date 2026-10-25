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
