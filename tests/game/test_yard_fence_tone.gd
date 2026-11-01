extends GutTest
## Тон воріт і сітки дворів: полотно воріт не світліше за свій паркан і не помаранчевіше, а оцинковка — середньо-сіра.

## Атлас береться з самої моделі: гра бачить текстуру, вшиту в GLB (файл-сусід .png — лише слід імпорту).
const MODEL: String = "res://assets/props/infra_fence_yard.glb"
## Порядок видів і розмір блоку атласу — tools/blender/infra/yard_fences.py (KINDS, HS, PAD).
const KINDS: Array[String] = ["picket", "sheet", "chainlink", "brickbars", "slat"]
const STRIP: int = 192
const PAD: int = 12
## Скільки світліше за паркан дозволено бути воротам (запас на шум текстури).
const LUMA_MARGIN: float = 1.1
## Скільки найменше від яскравості паркану дозволено мати воротам.
const LUMA_MIN: float = 0.9
const TILE_M: float = 2.5
const H_MAX: float = 2.0
## Дріт оцинковки: найсвітліший піксель і середня яскравість (світло-середній сірий).
const WIRE_MAX: float = 0.6
const WIRE_MIN_MEAN: float = 0.42


## Атлас з GLB: PNG у буферному вікні першого зображення (заголовок 12 байт, далі шматки JSON і BIN).
func _atlas() -> Image:
	var f := FileAccess.open(ProjectSettings.globalize_path(MODEL), FileAccess.READ)
	var data: PackedByteArray = f.get_buffer(f.get_length())
	var json_len: int = data.decode_u32(12)
	var gltf: Dictionary = JSON.parse_string(data.slice(20, 20 + json_len).get_string_from_utf8())
	var bin_start: int = 20 + json_len + 8
	var view: Dictionary = gltf["bufferViews"][int(gltf["images"][0]["bufferView"])]
	var from: int = bin_start + int(view.get("byteOffset", 0))
	var img := Image.new()
	img.load_png_from_buffer(data.slice(from, from + int(view["byteLength"])))
	return img


## Усі непрозорі пікселі смуги виду kind в атласі, sRGB, як лежать у файлі.
func _pixels(kind: String) -> Array[Color]:
	var img: Image = _atlas()
	var k: int = KINDS.find(kind)
	var top: int = k * (STRIP + 2 * PAD) + PAD
	var out: Array[Color] = []
	for y in range(top, top + STRIP):
		for x in img.get_width():
			var c: Color = img.get_pixel(x, y)
			if c.a > 0.5:
				out.append(c)
	return out


func _mean(cs: Array[Color]) -> Color:
	var s := Color(0, 0, 0, 1)
	for c in cs:
		s += Color(c.r, c.g, c.b, 0.0)
	return Color(s.r / cs.size(), s.g / cs.size(), s.b / cs.size())


func _luma(c: Color) -> float:
	return c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722


func _sat(c: Color) -> float:
	var mx: float = maxf(c.r, maxf(c.g, c.b))
	return (mx - minf(c.r, minf(c.g, c.b))) / mx


## Кольори коробок, які справжній _gate_leaf кладе в SmallBoxes для воріт роду gate (по всіх варіантах дощок).
func _gate_colors(gate: StringName) -> Array[Color]:
	var props := PropLayer.new()
	for seed in 8:
		props._gate_leaf(Vector2.ZERO, Vector2(0.5, 0.0), Vector2.RIGHT, Vector2.DOWN, 0.0, 0.245, gate, 0, seed)
	var out: Array[Color] = props._small_colors.duplicate()
	props.free()
	return out


func test_wooden_gates_are_no_lighter_or_more_orange_than_their_fence(p = use_parameters([["wood", "picket"], ["slat", "slat"]])) -> void:
	var fence: Color = _mean(_pixels(p[1]))
	var gate: Color = _mean(_gate_colors(StringName(p[0])))
	assert_lte(_luma(gate), _luma(fence) * LUMA_MARGIN, "%s: ворота %s світліші за паркан %s" % [p[0], gate, fence])
	assert_lte(_sat(gate), _sat(fence), "%s: ворота %s насиченіші за паркан %s" % [p[0], gate, fence])
	# І не темніші за нього: чорне полотно в сірому парканi — найконтрастніша річ двору.
	assert_gte(_luma(gate), _luma(fence) * LUMA_MIN, "%s: ворота %s темніші за паркан %s" % [p[0], gate, fence])


## Оцинковка: дріт — світло-середній сірий, не майже білий; труби й стовпи (суцільні, під сірим небом світляться
## самі) — не світліші за дріт і темніші за стіну хати, без білого відблиску.
func test_chainlink_is_galvanised_grey() -> void:
	var img: Image = _atlas()
	var top: int = KINDS.find("chainlink") * (STRIP + 2 * PAD) + PAD
	var wire: Array[Color] = []
	var steel: Array[Color] = []
	for r in STRIP:
		var z: float = (float(STRIP - 1 - r) + 0.5) / float(STRIP) * H_MAX
		for x in img.get_width():
			var c: Color = img.get_pixel(x, top + r)
			if c.a <= 0.5:
				continue
			var xm: float = (float(x) + 0.5) / float(img.get_width()) * TILE_M
			var on_post: bool = absf(fposmod(xm - 0.04 + TILE_M / 2.0, TILE_M) - TILE_M / 2.0) < 0.04
			(steel if on_post or absf(z - 1.46) < 0.02 else wire).append(c)
	assert_gt(wire.size(), 0)
	assert_gt(steel.size(), 0)
	var wire_max: float = 0.0
	var steel_max: float = 0.0
	for c in wire:
		wire_max = maxf(wire_max, maxf(c.r, maxf(c.g, c.b)))
	for c in steel:
		steel_max = maxf(steel_max, maxf(c.r, maxf(c.g, c.b)))
	assert_lte(_luma(_mean(steel)), _luma(_mean(wire)), "труби не світліші за дріт")
	assert_lte(steel_max, wire_max, "найсвітліша точка труби не світліша за найсвітлішу точку дроту")
	assert_lte(wire_max, WIRE_MAX, "дріт майже білий")
	assert_gte(_luma(_mean(wire)), WIRE_MIN_MEAN, "сітка зникає на тлі")
