class_name ScarMap
extends RefCounted
## Шрами бою на землі: одна RGBA8-текстура на дошку (0,25 м на тексель), яку читає
## ground.gdshader. Не Decal: Mobile кладе не більше 8 декалей на меш, а земля — один
## меш; Compatibility не має їх зовсім. Не квади над землею: ті мерехтять на схилах і
## коштують виклик малювання кожен.
##
## Канали: R — випалене (пляма під уламками), A — попіл; G і B вільні. Єдиний слід бою на
## ґрунті — пляма під підбитою технікою: стріляють лише по юнітах, вирв нема. Ставиться на CPU,
## коли подія вже зіграна; додавання — максимумом, тож пляма, поставлена двічі, не
## темнішає.
##
## §3.5: шрам переживає юніт, тож має власний туман — маска `seen` глядача (тексель на тайл,
## найближчим текселем) множить його в шейдері. Пляма ширша за тайл, тож маска сама не досить: пляма
## малюється, лише коли розвідане її джерело (тайл уламків чи відділення), інакше її край на розвіданому
## сусідові видав би бій на нерозвіданому. Тому плями зберігаються як відбитки на тайлах, а текстура
## складається з них наново на `show_for`.
##
## shortcut: шрами живуть лише у вигляді — збереження бою їх не пише, і після
## завантаження лишаються тільки плями під уламками, що ще горять; коли шрами стануть
## потрібні після завантаження, `core/` має зберігати їх у стані.

const PX_PER_TILE: int = 32
## Пляма уламків 10–14 м: темне ядро ~10 м, м'який край до 7 м від центру.
const SCORCH_RADIUS_M: float = 7.0
const SCORCH_CORE_M: float = 5.0
## Знищене відділення: стримана пляма, ~5 м, ядро ~2 м і лише половина темряви уламків — ні вогню, ні
## палива там не було.
const SQUAD_SCORCH_RADIUS_M: float = 2.6
const SQUAD_SCORCH_CORE_M: float = 1.0
const SQUAD_SCORCH_DARK: float = 0.5
## Слід поваленого на мокрій землі (`stamp_scuff`): півширина смуги й найбільша темрява.
const SCUFF_HALF_M: float = 0.5
const SCUFF_DARK: float = 0.35

var _size: Vector2i
var _img: Image
var _tex: ImageTexture
var _dirty: bool = false
var _mask: Image
var _mask_tex: ImageTexture
## Сліди поваленого — без плям; на них текстура складається наново.
var _base: Image
## Плями за тайлом-джерелом: біти WRECK і SQUAD.
var _scorch: Dictionary[Vector2i, int] = {}
## Плями, що зараз намальовані (джерело розвідане глядачем).
var _painted: Dictionary[Vector2i, int] = {}
var _vision: Vision = null
const WRECK: int = 1
const SQUAD: int = 2


func _init(board_size: Vector2i) -> void:
	_size = board_size
	_img = Image.create(maxi(1, board_size.x * PX_PER_TILE), maxi(1, board_size.y * PX_PER_TILE), false, Image.FORMAT_RGBA8)
	_tex = ImageTexture.create_from_image(_img)
	_base = _img.duplicate()
	_mask = Image.create(maxi(1, board_size.x), maxi(1, board_size.y), false, Image.FORMAT_R8)
	_mask_tex = ImageTexture.create_from_image(_mask)


func image() -> Image:
	return _img


func texture() -> ImageTexture:
	return _tex


func mask() -> Image:
	return _mask


func mask_texture() -> ImageTexture:
	return _mask_tex


func apply(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("has_scars", true)
	mat.set_shader_parameter("scar_map", _tex)
	mat.set_shader_parameter("scar_seen", _mask_tex)
	mat.set_shader_parameter("scar_size", Vector2(_size))


func show_for(vision: Vision) -> void:
	for y in _size.y:
		for x in _size.x:
			_mask.set_pixel(x, y, Color(1, 1, 1) if vision.is_seen(Vector2i(x, y)) else Color(0, 0, 0))
	_mask_tex.update(_mask)
	_vision = vision
	var shown: Dictionary[Vector2i, int] = {}
	for cell: Vector2i in _scorch:
		if vision.is_seen(cell):
			shown[cell] = _scorch[cell]
	if shown == _painted:
		return
	_img.copy_from(_base)
	_painted.clear()
	for cell: Vector2i in shown:
		_paint(cell, shown[cell])
	_mark_dirty()


## Плями з нуля — перебудова на гейті й на повторі ставить їх за станом, який показує.
func reset_scorches() -> void:
	_scorch.clear()


## Нерівна пляма з променями різної довжини (не зірка й не коло) і цятками попелу.
## Форма — з хешу тайла: усі гравці бачать ту саму, і кидки правил не зсуваються.
func stamp_scorch(cell: Vector2i) -> void:
	_add(cell, WRECK)


## Слід знищеного відділення (art-direction, «a scorch, restrained»): менший і світліший за пляму уламків.
## Ставиться раз на тайл; уламки на тому самому тайлі однаково накривають його своєю.
func stamp_squad_scorch(cell: Vector2i) -> void:
	_add(cell, SQUAD)


func has_squad_scorch(cell: Vector2i) -> bool:
	return _scorch.get(cell, 0) & SQUAD != 0


## Чи намальована пляма з цього тайла (джерело розвідане глядачем).
func is_painted(cell: Vector2i) -> bool:
	return _painted.has(cell)


## Записати відбиток і, якщо джерело вже розвідане (або глядача ще нема), одразу намалювати.
func _add(cell: Vector2i, kind: int) -> void:
	_scorch[cell] = _scorch.get(cell, 0) | kind
	if _vision == null or _vision.is_seen(cell):
		_paint(cell, kind)


func _paint(cell: Vector2i, kinds: int) -> void:
	var fresh: int = kinds & ~_painted.get(cell, 0)
	if fresh == 0:
		return
	_painted[cell] = _painted.get(cell, 0) | fresh
	if fresh & WRECK:
		_stamp(cell, SCORCH_RADIUS_M, SCORCH_CORE_M)
	if fresh & SQUAD:
		_stamp(cell, SQUAD_SCORCH_RADIUS_M, SQUAD_SCORCH_CORE_M, SQUAD_SCORCH_DARK, 0.0)


## Слід, який повалена опора чи паркан лишає на розмоклій землі: темна смуга ~1 м завширшки вздовж
## a→b (світові точки, тайли) з рваним краєм; та сама темрява R, що в плями, але слабка (до SCUFF_DARK),
## щоб читалась як мокра прим'ята земля, а не як згарище. Той самий туман `seen`, що в плями.
func stamp_scuff(a: Vector3, b: Vector3) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = hash(Vector4(a.x, a.z, b.x, b.z))
	noise.frequency = 0.3
	var pa := (Vector2(a.x, a.z) + Vector2(0.5, 0.5)) * PX_PER_TILE
	var pb := (Vector2(b.x, b.z) + Vector2(0.5, 0.5)) * PX_PER_TILE
	var half_px: float = SCUFF_HALF_M * PX_PER_TILE / 8.0
	var lo := Vector2i(floori(minf(pa.x, pb.x) - half_px * 2.0), floori(minf(pa.y, pb.y) - half_px * 2.0))
	var hi := Vector2i(ceili(maxf(pa.x, pb.x) + half_px * 2.0), ceili(maxf(pa.y, pb.y) + half_px * 2.0))
	for y in range(maxi(lo.y, 0), mini(hi.y, _img.get_height())):
		for x in range(maxi(lo.x, 0), mini(hi.x, _img.get_width())):
			var p := Vector2(x, y)
			var d: float = p.distance_to(Geometry2D.get_closest_point_to_segment(p, pa, pb))
			# Край гуляє на ±40 % півширини: смуга не рівна, як від лінійки.
			var w: float = half_px * (1.0 + 0.4 * noise.get_noise_2d(p.x, p.y))
			var v: float = (1.0 - smoothstep(w * 0.4, w, d)) * SCUFF_DARK
			if v <= 0.0:
				continue
			var old: Color = _img.get_pixel(x, y)
			_img.set_pixel(x, y, Color(maxf(old.r, v), old.g, old.b, old.a))
			var ob: Color = _base.get_pixel(x, y)
			_base.set_pixel(x, y, Color(maxf(ob.r, v), ob.g, ob.b, ob.a))
	_mark_dirty()


## Кілька відбитків за кадр (падіння кількох парканів разом) вантажать текстуру дошки на відеокарту один раз.
func _mark_dirty() -> void:
	if _dirty:
		return
	_dirty = true
	_flush_upload.call_deferred()


func _flush_upload() -> void:
	_dirty = false
	_tex.update(_img)


## `ash_k` — частка цяток попелу: у плями відділення їх нема (світлі цятки посеред неї читались камінцем).
func _stamp(cell: Vector2i, radius_m: float, core_m: float, dark: float = 1.0, ash_k: float = 1.0) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = hash(cell)
	noise.frequency = 1.0
	var fine := FastNoiseLite.new()
	fine.seed = hash(cell) + 1
	fine.frequency = 0.35
	var r_px: float = radius_m * 4.0
	var core_px: float = core_m * 4.0
	var c := Vector2(cell.x * PX_PER_TILE + PX_PER_TILE / 2, cell.y * PX_PER_TILE + PX_PER_TILE / 2)
	var ri: int = int(r_px)
	for dy in range(-ri, ri + 1):
		for dx in range(-ri, ri + 1):
			var p := Vector2i(int(c.x) + dx, int(c.y) + dy)
			if p.x < 0 or p.y < 0 or p.x >= _img.get_width() or p.y >= _img.get_height():
				continue
			var dist: float = Vector2(dx, dy).length()
			if dist >= r_px:
				continue
			var ang: float = atan2(float(dy), float(dx))
			# Множник лише збільшує відстань: край ніколи не виходить за `radius_m`.
			var lobes: float = 0.5 + 0.5 * noise.get_noise_2d(cos(ang) * 1.3, sin(ang) * 1.3)
			var rays: float = 0.5 + 0.5 * noise.get_noise_2d(cos(ang) * 6.0 + 9.0, sin(ang) * 6.0)
			var d_eff: float = dist * (1.0 + 0.18 * lobes + 0.3 * smoothstep(0.55, 0.9, 1.0 - rays) * dist / r_px)
			var v: float = 1.0 - smoothstep(core_px, r_px, d_eff)
			var f: float = 0.5 + 0.5 * fine.get_noise_2d(float(p.x), float(p.y))
			v = clampf(v * (0.85 + 0.3 * f), 0.0, 1.0) if dist > 1.5 else v
			v *= dark
			var ash: float = smoothstep(0.72, 0.85, f) * v * ash_k
			var old: Color = _img.get_pixelv(p)
			_img.set_pixelv(p, Color(maxf(old.r, v), old.g, old.b, maxf(old.a, ash)))
	_mark_dirty()
