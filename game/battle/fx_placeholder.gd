class_name FxPlaceholder
extends RefCounted
## Заступник запечених флипбуків, поки справжні атласи (assets/vfx/) не лягли: та сама
## сітка 8×8 кадрів, тож заміна — лише файл. Це процедурна імітація, а не симуляція:
## клуба складена з освітлених куль із твердим краєм (кулі видно як клуби, а не як
## розмиту пляму), язик полум'я — з кількох крапель з готовим кольором серця й краю.
##
## Складання — `Image.blend_rect`, а не попіксельний цикл: атлас будується раз за запуск
## і не гальмує ні тести, ні перший кадр бою.

const CELL: int = 64
const GRID: int = 8

static var _smoke: Image
static var _fire: Image


static func smoke_atlas() -> Image:
	if _smoke == null:
		_smoke = _build(false)
	return _smoke


static func fire_atlas() -> Image:
	if _fire == null:
		_fire = _build(true)
	return _fire


## Куля, освітлена згори-зліва: нормаль сфери, тінь знизу-справа, край — 1,5 px
## згладження. Для полум'я — витягнута вгору крапля з кольором від білого серця до
## помаранчевого краю.
static func _sprite(size: int, fire: bool) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var light := Vector3(-0.45, -0.6, 0.66).normalized()
	var h: float = float(size) * 0.5
	for y in size:
		for x in size:
			var dx: float = (float(x) + 0.5 - h) / h
			var dy: float = (float(y) + 0.5 - h) / h
			if fire:
				# Крапля: вужча вгорі, кругла внизу.
				dx /= lerpf(0.35, 0.9, clampf((dy + 1.0) * 0.5, 0.0, 1.0))
			var r: float = sqrt(dx * dx + dy * dy)
			var a: float = clampf((1.0 - r) * h / 1.5, 0.0, 1.0)
			if a <= 0.0:
				continue
			if fire:
				var hot: float = clampf(1.0 - r * 1.15, 0.0, 1.0)
				var c: Color = Color("e0702a").lerp(Color("ffd9a0"), smoothstep(0.0, 0.5, hot)).lerp(Color.WHITE, smoothstep(0.55, 0.9, hot))
				img.set_pixel(x, y, Color(c, a))
			else:
				var n := Vector3(dx, dy, sqrt(maxf(0.0, 1.0 - r * r)))
				var lit: float = clampf(n.dot(light), 0.0, 1.0)
				var v: float = 0.4 + 0.6 * lit
				img.set_pixel(x, y, Color(v, v, v, a))
	return img


static func _build(fire: bool) -> Image:
	var atlas := Image.create(CELL * GRID, CELL * GRID, false, Image.FORMAT_RGBA8)
	var sprites: Array[Image] = []
	for s: int in ([18, 24, 30, 36, 42] if fire else [12, 15, 19, 23, 27]):
		sprites.append(_sprite(s, fire))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7 if fire else 3
	# Кулі одної клуби: кут, відстань від центру й розмір; кадр повертає й піднімає їх,
	# тож клуба котиться, а не мерехтить.
	var lobes: Array[Vector3] = []
	for i in (6 if fire else 16):
		lobes.append(Vector3(rng.randf() * TAU, rng.randf_range(0.1, 0.55) if fire else rng.randf_range(0.15, 0.95), float(rng.randi_range(0, sprites.size() - 1))))
	for f in GRID * GRID:
		var origin := Vector2i((f % GRID) * CELL, (f / GRID) * CELL)
		var t: float = float(f) / float(GRID * GRID)
		var order: Array[int] = []
		for i in lobes.size():
			order.append(i)
		for i: int in order:
			var l: Vector3 = lobes[i]
			var spr: Image = sprites[int(l.z)]
			var p: Vector2
			if fire:
				# Язики злітають угору й опадають, кожен зі своєю фазою.
				var ph: float = fposmod(t * 3.0 + l.x / TAU, 1.0)
				p = Vector2(cos(l.x) * l.y * 0.6, 0.35 - ph * 0.8) * float(CELL) * 0.5
				var k: int = clampi(int(l.z) - int(ph * 3.0), 0, sprites.size() - 1)
				spr = sprites[k]
			else:
				var ang: float = l.x + t * TAU * 0.5 * (1.0 if i % 2 == 0 else -1.0)
				p = Vector2(cos(ang), sin(ang) * 0.8) * l.y * float(CELL) * 0.42
			var at := origin + Vector2i(CELL / 2, CELL / 2) + Vector2i(p) - spr.get_size() / 2
			atlas.blend_rect(spr, Rect2i(Vector2i.ZERO, spr.get_size()), at)
	return atlas
