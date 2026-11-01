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


func test_chainlink_is_galvanised_mid_grey() -> void:
	var worst: float = 0.0
	for c in _pixels("chainlink"):
		worst = maxf(worst, maxf(c.r, maxf(c.g, c.b)))
	assert_lte(worst, 0.5, "найсвітліший піксель сітки й труб")
