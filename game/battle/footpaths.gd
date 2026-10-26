class_name Footpaths
extends RefCounted
## Протоптані стежки: від дверей кожної хати через ворота до дороги, витоптані плями біля воріт і
## сараїв, 1–2 стежки до води на карту. Знос — одна R8-маска на дошку (128 px на клітинку, ~6 см на піксель), яку
## читає ground.gdshader і підмішує до неї голий ґрунт: ні вузлів, ні декалей, ні draw call.
## Маска публічна (§3.5): не залежить від туману й боєвих слідів.
##
## Вигляд не знає про сітку (§8): шум зносу лежить у координатах самої стежки — s вздовж, d
## поперек, — тож смужки йдуть уздовж стежки, а та сама стежка в іншому місці дає ті самі
## пікселі. Світової текстури зносу нема.
##
## Стежка — {kind: &"yard"/&"water", home, door, pts, half, seed}; pts — ламана в координатах
## дошки, half — півширина в кожній точці (клітинки). Плями — Vector3(x, y, радіус).

const PX_PER_TILE: int = 128
## Крок ламаної, клітинки.
const STEP: float = 0.1
## Дальність крайки поза півшириною: 1.0 + найбільший зсув шумом від краю.
const REACH: float = 1.3
## Довжина, на якій звивина наростає від нуля на прив'язаних кінцях.
const RAMP: float = 0.3


static func _hash(x: int, y: int, seed_value: int) -> float:
	var n: int = (x * 374761393 + y * 668265263 + seed_value * 1274126177) & 0x7fffffff
	n = ((n ^ (n >> 13)) * 1274126177) & 0x7fffffff
	return float(n ^ (n >> 16)) / float(0x7fffffff)


static func _noise(x: float, y: float, seed_value: int) -> float:
	var ix: int = floori(x)
	var iy: int = floori(y)
	var fx: float = x - ix
	var fy: float = y - iy
	var ux: float = fx * fx * (3.0 - 2.0 * fx)
	var uy: float = fy * fy * (3.0 - 2.0 * fy)
	return lerpf(lerpf(_hash(ix, iy, seed_value), _hash(ix + 1, iy, seed_value), ux),
			lerpf(_hash(ix, iy + 1, seed_value), _hash(ix + 1, iy + 1, seed_value), ux), uy)


## Звивиста лінія від a до b рівно в a і b: зсув вбік — шум у двох масштабах, нуль на кінцях.
## amp — найбільший зсув (клітинки), wavelength — довжина хвилі шуму.
static func meander(a: Vector2, b: Vector2, amp: float, wavelength: float, seed_value: int) -> PackedVector2Array:
	var length: float = a.distance_to(b)
	var out := PackedVector2Array([a])
	if length < 1e-4:
		return out
	var n: int = maxi(1, ceili(length / STEP))
	var dir: Vector2 = (b - a) / length
	var side := Vector2(-dir.y, dir.x)
	for k in range(1, n):
		var s: float = length * k / n
		var env: float = smoothstep(0.0, RAMP, minf(s, length - s))
		var v: float = 0.75 * (2.0 * _noise(s / wavelength, 0.5, seed_value) - 1.0) \
				+ 0.25 * (2.0 * _noise(s / wavelength * 2.0 + 31.0, 7.5, seed_value) - 1.0)
		out.append(a + dir * s + side * amp * env * v)
	out.append(b)
	return out


## Згладжує ламану (три точки [1 2 1]/4, кінці нерухомі): стики відрізків і повороти між ділянками
## стають однією плавною кривою.
static func smooth(pts: PackedVector2Array, passes: int = 8) -> PackedVector2Array:
	var cur := pts.duplicate()
	for _p in passes:
		var nxt := cur.duplicate()
		for k in range(1, cur.size() - 1):
			nxt[k] = cur[k - 1] * 0.25 + cur[k] * 0.5 + cur[k + 1] * 0.25
		cur = nxt
	return cur


static func length(pts: PackedVector2Array) -> float:
	var l: float = 0.0
	for k in range(1, pts.size()):
		l += pts[k].distance_to(pts[k - 1])
	return l


## Півширина в точках: base, ширша біля прив'язок (двері, ворота, берег) — pins — {at, boost}.
static func widths(pts: PackedVector2Array, base: float, pins: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(pts.size())
	for k in pts.size():
		var f: float = 1.0
		for pin: Dictionary in pins:
			var d: float = pts[k].distance_to(pin["at"])
			f += float(pin["boost"]) * exp(-d * d / 0.09)
		out[k] = base * f
	return out


## Маска зносу. dry (Vector2 -> bool): де сухо; на воді знос обнуляється.
static func bake(walks: Array, patches: PackedVector3Array, board_size: Vector2i, dry: Callable = Callable()) -> Image:
	var w: int = maxi(1, board_size.x * PX_PER_TILE)
	var h: int = maxi(1, board_size.y * PX_PER_TILE)
	var buf := PackedByteArray()
	buf.resize(w * h)
	for walk: Dictionary in walks:
		_stamp_walk(buf, w, h, walk, dry)
	for pi in patches.size():
		_stamp_patch(buf, w, h, patches[pi], pi, dry)
	return Image.create_from_data(w, h, false, Image.FORMAT_R8, buf)


static func _px_pos(px: int, py: int) -> Vector2:
	return Vector2((px + 0.5) / PX_PER_TILE - 0.5, (py + 0.5) / PX_PER_TILE - 0.5)


static func _put(buf: PackedByteArray, w: int, idx: int, v: float, q: Vector2, dry: Callable) -> void:
	var b: int = int(clampf(v, 0.0, 1.0) * 255.0 + 0.5)
	if b <= buf[idx]:
		return
	if dry.is_valid() and not dry.call(q):
		return
	buf[idx] = b


## Кожен піксель обчислює лише найближчий до нього відрізок (сусідні — для стиків), а s і d беруться
## від проєкції на нього: шум неперервний уздовж усієї кривої, відрізків і стиків не видно.
static func _stamp_walk(buf: PackedByteArray, w: int, h: int, walk: Dictionary, dry: Callable) -> void:
	var pts: PackedVector2Array = walk["pts"]
	var hw: PackedFloat32Array = walk["half"]
	var sd: int = int(walk["seed"])
	var fade_in: float = float(walk.get("fade_start", 0.0))
	var fade_out: float = float(walk.get("fade_end", 0.0))
	var cum := PackedFloat32Array([0.0])
	for k in range(1, pts.size()):
		cum.append(cum[k - 1] + pts[k].distance_to(pts[k - 1]))
	var total: float = cum[cum.size() - 1]
	for k in range(pts.size() - 1):
		var a: Vector2 = pts[k]
		var ab: Vector2 = pts[k + 1] - a
		if ab.length() < 1e-6:
			continue
		var reach: float = maxf(hw[k], hw[k + 1]) * 1.6 * REACH
		var lo := Vector2(minf(a.x, a.x + ab.x), minf(a.y, a.y + ab.y)) - Vector2.ONE * reach
		var hi := Vector2(maxf(a.x, a.x + ab.x), maxf(a.y, a.y + ab.y)) + Vector2.ONE * reach
		var x0: int = maxi(0, floori((lo.x + 0.5) * PX_PER_TILE))
		var x1: int = mini(w - 1, ceili((hi.x + 0.5) * PX_PER_TILE))
		var y0: int = maxi(0, floori((lo.y + 0.5) * PX_PER_TILE))
		var y1: int = mini(h - 1, ceili((hi.y + 0.5) * PX_PER_TILE))
		for py in range(y0, y1 + 1):
			for px in range(x0, x1 + 1):
				var q: Vector2 = _px_pos(px, py)
				var dist: float = _seg_dist(q, a, ab)
				if (k > 0 and _seg_dist(q, pts[k - 1], a - pts[k - 1]) < dist - 1e-6) \
						or (k + 2 < pts.size() and _seg_dist(q, pts[k + 1], pts[k + 2] - pts[k + 1]) <= dist):
					continue
				var seg: float = ab.length()
				var dir: Vector2 = ab / seg
				var t: float = clampf((q - a).dot(dir) / seg, 0.0, 1.0)
				var s: float = cum[k] + seg * t
				var d: float = dir.cross(q - a)
				var half: float = lerpf(hw[k], hw[k + 1], t) * (0.65 + 0.7 * _noise(s * 1.3, 5.5, sd + 3))
				_put(buf, w, py * w + px, _wear(s, d, dist / half, total, fade_in, fade_out, sd), q, dry)


static func _seg_dist(q: Vector2, a: Vector2, ab: Vector2) -> float:
	return q.distance_to(a + ab * clampf((q - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0))


## Знос в точці стежки: s — уздовж, d — поперек (клітинки), r — відстань від осі в півширинах.
## Рваний край (шум у двох масштабах), посередині плями голої землі там, де ступають частіше, і
## місця, де трава проростає навіть посередині; у шуму вісь s розтягнута.
static func _wear(s: float, d: float, r: float, total: float, fade_in: float, fade_out: float, sd: int) -> float:
	var edge: float = 0.5 * _noise(s * 4.0, d * 22.0, sd) + 0.3 * _noise(s * 11.0, d * 55.0, sd + 5) + 0.2 * _noise(s * 26.0, d * 110.0, sd + 9)
	var rr: float = r + 0.9 * (edge - 0.5)
	var prof: float = 1.0 - smoothstep(0.15, 1.0, rr)
	var bare: float = smoothstep(0.4, 0.62, _noise(s * 2.6, d * 12.0, sd + 11))
	var sprout: float = smoothstep(0.58, 0.78, _noise(s * 9.0, d * 45.0, sd + 17))
	var v: float = prof * (0.15 + 0.85 * bare) * (1.0 - 0.8 * sprout)
	if fade_in > 0.0:
		v *= smoothstep(0.0, fade_in, s)
	if fade_out > 0.0:
		v *= smoothstep(0.0, fade_out, total - s)
	return v


static func _stamp_patch(buf: PackedByteArray, w: int, h: int, patch: Vector3, index: int, dry: Callable) -> void:
	var c := Vector2(patch.x, patch.y)
	var reach: float = patch.z * 1.3
	var x0: int = maxi(0, floori((c.x - reach + 0.5) * PX_PER_TILE))
	var x1: int = mini(w - 1, ceili((c.x + reach + 0.5) * PX_PER_TILE))
	var y0: int = maxi(0, floori((c.y - reach + 0.5) * PX_PER_TILE))
	var y1: int = mini(h - 1, ceili((c.y + reach + 0.5) * PX_PER_TILE))
	for py in range(y0, y1 + 1):
		for px in range(x0, x1 + 1):
			var q: Vector2 = _px_pos(px, py)
			var u: Vector2 = (q - c) / patch.z
			var rr: float = u.length()
			if rr > 1.3:
				continue
			var edge: float = 0.6 * _noise(u.x * 3.0 + 9.0, u.y * 3.0 + 9.0, 401 + index) + 0.4 * _noise(u.x * 9.0, u.y * 9.0, 433 + index)
			var bare: float = smoothstep(0.25, 0.7, _noise(u.x * 2.0 + 4.0, u.y * 2.0, 467 + index))
			_put(buf, w, py * w + px, (0.35 + 0.65 * bare) * (1.0 - smoothstep(0.2, 1.0, rr + 0.5 * (edge - 0.5))), q, dry)


static func apply(mat: ShaderMaterial, img: Image, board_size: Vector2i) -> void:
	mat.set_shader_parameter("has_paths", true)
	mat.set_shader_parameter("path_map", ImageTexture.create_from_image(img))
	mat.set_shader_parameter("path_size", Vector2(board_size))
