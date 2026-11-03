class_name Footpaths
extends RefCounted
## Протоптані стежки: від дверей кожної хати через ворота до дороги, витоптані плями біля воріт і
## сараїв, 1–2 стежки від дороги до води на карту. Знос — одна RG8-маска на дошку (64 px на клітинку,
## ~12 см на піксель, з мипмапами), яку читає ground.gdshader: ні вузлів, ні декалей, ні draw call.
## R — знос стежки, G — витоптана пляма. Маска публічна (§3.5): не залежить від туману й боєвих слідів.
##
## Вигляд не знає про сітку (§8): шум зносу лежить у координатах самої стежки (s вздовж, d поперек),
## тож та сама стежка в іншому місці дає ті самі пікселі. Світової текстури зносу нема.
##
## Стежка — {kind: &"yard"/&"water", home, door, pts, half, seed}; pts — ламана в координатах дошки
## (рівний крок STEP), half — півширина в кожній точці (клітинки). Плями — Vector3(x, y, радіус).

const PX_PER_TILE: int = 64
## Крок ламаної, клітинки.
const STEP: float = 0.1
## Скільки півширин від осі ще може лежати знос (край зсунуто шумом до 0.35 півширини).
const REACH: float = 2.4
## Півширина втоптаної середини: ~0.7 м завширшки, ±0.2 м плавним шумом. З боків по 0.3–0.5 м прим'ята
## рідша трава (слабший знос, до REACH півширин).
const HALF: float = 0.045


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
	# _hash розгорнуто в чотири кути вручну: виклик функції у гарячому циклі дорожчий за саму арифметику.
	var sh: int = seed_value * 1274126177
	var jx: int = ix * 374761393
	var jy: int = iy * 668265263
	var n00: int = (jx + jy + sh) & 0x7fffffff
	var n10: int = (jx + 374761393 + jy + sh) & 0x7fffffff
	var n01: int = (jx + jy + 668265263 + sh) & 0x7fffffff
	var n11: int = (jx + 374761393 + jy + 668265263 + sh) & 0x7fffffff
	n00 = ((n00 ^ (n00 >> 13)) * 1274126177) & 0x7fffffff
	n10 = ((n10 ^ (n10 >> 13)) * 1274126177) & 0x7fffffff
	n01 = ((n01 ^ (n01 >> 13)) * 1274126177) & 0x7fffffff
	n11 = ((n11 ^ (n11 >> 13)) * 1274126177) & 0x7fffffff
	return lerpf(lerpf(float(n00 ^ (n00 >> 16)) / 2147483647.0, float(n10 ^ (n10 >> 16)) / 2147483647.0, ux),
			lerpf(float(n01 ^ (n01 >> 16)) / 2147483647.0, float(n11 ^ (n11 >> 16)) / 2147483647.0, ux), uy)


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
	var ramp: float = minf(0.3, length * 0.4)
	for k in range(1, n):
		var s: float = length * k / n
		var env: float = smoothstep(0.0, ramp, minf(s, length - s))
		var v: float = 0.8 * (2.0 * _noise(s / wavelength, 0.5, seed_value) - 1.0) \
				+ 0.2 * (2.0 * _noise(s / wavelength * 2.3 + 31.0, 7.5, seed_value) - 1.0)
		out.append(a + dir * s + side * amp * env * v)
	out.append(b)
	return out


## Згладжує ламану (три точки [1 2 1]/4, кінці нерухомі): стики ділянок стають однією плавною кривою.
static func smooth(pts: PackedVector2Array, passes: int = 8) -> PackedVector2Array:
	var cur := pts.duplicate()
	for _p in passes:
		var nxt := cur.duplicate()
		for k in range(1, cur.size() - 1):
			nxt[k] = cur[k - 1] * 0.25 + cur[k] * 0.5 + cur[k + 1] * 0.25
		cur = nxt
	return cur


## Ламана з рівним кроком STEP за довжиною дуги (кінці лишаються): звивина не розтягує кроку.
static func resample(pts: PackedVector2Array) -> PackedVector2Array:
	var total: float = length(pts)
	var n: int = maxi(1, ceili(total / STEP))
	var out := PackedVector2Array([pts[0]])
	var k: int = 0
	var acc: float = 0.0
	for i in range(1, n):
		var want: float = total * i / n
		while k < pts.size() - 2 and acc + pts[k].distance_to(pts[k + 1]) < want:
			acc += pts[k].distance_to(pts[k + 1])
			k += 1
		var seg: float = maxf(pts[k].distance_to(pts[k + 1]), 1e-6)
		out.append(pts[k].lerp(pts[k + 1], clampf((want - acc) / seg, 0.0, 1.0)))
	out.append(pts[pts.size() - 1])
	return out


## Скільки разів стежка перегинається відносно хорди (гістерезис 0.06 клітинки).
static func turns(pts: PackedVector2Array) -> int:
	var a: Vector2 = pts[0]
	var chord: Vector2 = (pts[pts.size() - 1] - a).normalized()
	var count: int = 0
	var dir: int = 0
	var ref: float = 0.0
	for q in pts:
		var d: float = chord.cross(q - a)
		if dir == 0:
			if absf(d - ref) > 0.06:
				dir = 1 if d > ref else -1
				ref = d
		elif (dir == 1 and d < ref - 0.06) or (dir == -1 and d > ref + 0.06):
			count += 1
			dir = -dir
			ref = d
		else:
			ref = maxf(ref, d) if dir == 1 else minf(ref, d)
	return count


## Спрямляє ламану плавними дугами: кожен злам замінено квадратичною кривою Безьє, яка зрізає кут на
## radius (не більше 0.48 сусіднього відрізка); кінці нерухомі.
static func fillet(ctrl: PackedVector2Array, radius: float) -> PackedVector2Array:
	var out := PackedVector2Array([ctrl[0]])
	for i in range(1, ctrl.size() - 1):
		var v: Vector2 = ctrl[i]
		var c: float = minf(radius, 0.48 * minf(v.distance_to(ctrl[i - 1]), v.distance_to(ctrl[i + 1])))
		var a: Vector2 = v + (ctrl[i - 1] - v).normalized() * c
		var b: Vector2 = v + (ctrl[i + 1] - v).normalized() * c
		var n: int = maxi(2, ceili(2.0 * c / 0.05))
		for k in range(n + 1):
			var t: float = float(k) / n
			out.append(a.lerp(v, t).lerp(v.lerp(b, t), t))
	out.append(ctrl[ctrl.size() - 1])
	return out


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
			f += float(pin["boost"]) * exp(-d * d / 0.06)
		out[k] = base * f
	return out


## Маска зносу. dry (Vector2 -> bool): де сухо; на воді знос обнуляється. cache — узяти з диска
## (BuildCache) і зберегти туди зліпок без dry: сухість залежить лише від піксельної позиції, тож
## знос у мокрому пікселі просто обнуляється, а решта пікселів — ті самі, що дав би штамп із dry.
static func bake(walks: Array, patches: PackedVector3Array, board_size: Vector2i, dry: Callable = Callable(), cache: bool = false) -> Image:
	var w: int = maxi(1, board_size.x * PX_PER_TILE)
	var h: int = maxi(1, board_size.y * PX_PER_TILE)
	var k: String = BuildCache.key([walks, patches, board_size], ["res://game/battle/footpaths.gd"]) if cache else ""
	var buf := PackedByteArray()
	var touched := PackedInt32Array()
	var cached: Variant = BuildCache.fetch("footpaths", k) if cache else null
	if cached is Array and (cached as Array).size() == 2 and (cached[0] as PackedByteArray).size() == w * h * 2:
		buf = cached[0]
		touched = cached[1]
	else:
		buf.resize(w * h * 2)
		for walk: Dictionary in walks:
			_stamp_walk(buf, w, h, walk, touched)
		for pi in patches.size():
			_stamp_patch(buf, w, h, patches[pi], pi, touched)
		if cache:
			BuildCache.store("footpaths", k, [buf, touched])
	if dry.is_valid():
		# Лише пікселі, де щось записано, і кожен раз: в touched піксель стоїть стільки разів, скільки в нього писали.
		var checked := PackedByteArray()
		checked.resize(w * h)
		for i in touched:
			var pix: int = i / 2
			if checked[pix] == 1:
				continue
			checked[pix] = 1
			if not dry.call(_px_pos(pix % w, pix / w)):
				buf[pix * 2] = 0
				buf[pix * 2 + 1] = 0
	return Image.create_from_data(w, h, false, Image.FORMAT_RG8, buf)


static func _px_pos(px: int, py: int) -> Vector2:
	return Vector2((px + 0.5) / PX_PER_TILE - 0.5, (py + 0.5) / PX_PER_TILE - 0.5)


static func _put(buf: PackedByteArray, idx: int, v: float, touched: PackedInt32Array) -> void:
	var b: int = int(clampf(v, 0.0, 1.0) * 255.0 + 0.5)
	if b <= buf[idx]:
		return
	buf[idx] = b
	touched.append(idx)


## Кожен піксель обчислює лише найближчий до нього відрізок (сусідні — для стиків), а s і d беруться
## від проєкції на нього: шум неперервний уздовж усієї кривої, відрізків і стиків не видно.
static func _stamp_walk(buf: PackedByteArray, w: int, h: int, walk: Dictionary, touched: PackedInt32Array) -> void:
	var pts: PackedVector2Array = walk["pts"]
	var hw: PackedFloat32Array = walk["half"]
	var sd: int = int(walk["seed"])
	var fade_in: float = float(walk.get("fade_start", 0.0))
	var fade_out: float = float(walk.get("fade_end", 0.0))
	var solid: float = float(walk.get("solid", 0.3))
	var flat: float = float(walk.get("flat", 1.3))
	var cum := PackedFloat32Array([0.0])
	for k in range(1, pts.size()):
		cum.append(cum[k - 1] + pts[k].distance_to(pts[k - 1]))
	var total: float = cum[cum.size() - 1]
	for k in range(pts.size() - 1):
		var a: Vector2 = pts[k]
		var ab: Vector2 = pts[k + 1] - a
		var seg: float = ab.length()
		if seg < 1e-6:
			continue
		var reach: float = maxf(hw[k], hw[k + 1]) * 1.35 * REACH
		var lo := Vector2(minf(a.x, a.x + ab.x), minf(a.y, a.y + ab.y)) - Vector2.ONE * reach
		var hi := Vector2(maxf(a.x, a.x + ab.x), maxf(a.y, a.y + ab.y)) + Vector2.ONE * reach
		var x0: int = maxi(0, floori((lo.x + 0.5) * PX_PER_TILE))
		var x1: int = mini(w - 1, ceili((hi.x + 0.5) * PX_PER_TILE))
		var y0: int = maxi(0, floori((lo.y + 0.5) * PX_PER_TILE))
		var y1: int = mini(h - 1, ceili((hi.y + 0.5) * PX_PER_TILE))
		var dir: Vector2 = ab / seg
		# Сусідні відрізки й квадрат довжини — раз на відрізок, а не на піксель. Дистанції лишено на
		# Vector2 (float32), як у _seg_dist: інакше байт на межі кроку міг би змінитись.
		var l2: float = maxf(ab.length_squared(), 1e-9)
		var has_prev: bool = k > 0
		var has_next: bool = k + 2 < pts.size()
		var pa: Vector2 = pts[k - 1] if has_prev else Vector2.ZERO
		var pab: Vector2 = a - pa
		var pl2: float = maxf(pab.length_squared(), 1e-9)
		var na: Vector2 = pts[k + 1]
		var nab: Vector2 = pts[k + 2] - na if has_next else Vector2.ZERO
		var nl2: float = maxf(nab.length_squared(), 1e-9)
		var hw_a: float = hw[k]
		var hw_b: float = hw[k + 1]
		for py in range(y0, y1 + 1):
			var qy: float = (py + 0.5) / PX_PER_TILE - 0.5
			for px in range(x0, x1 + 1):
				var q := Vector2((px + 0.5) / PX_PER_TILE - 0.5, qy)
				var dist: float = q.distance_to(a + ab * clampf((q - a).dot(ab) / l2, 0.0, 1.0))
				# Поза досяжністю знос однаково нуль: сусідні відрізки навіть не міряємо.
				if dist > reach:
					continue
				if (has_prev and q.distance_to(pa + pab * clampf((q - pa).dot(pab) / pl2, 0.0, 1.0)) < dist - 1e-6) \
						or (has_next and q.distance_to(na + nab * clampf((q - na).dot(nab) / nl2, 0.0, 1.0)) <= dist):
					continue
				var t: float = clampf((q - a).dot(dir) / seg, 0.0, 1.0)
				var s: float = cum[k] + seg * t
				var d: float = dir.cross(q - a)
				# Ширина гуляє на ±0.2 м плавним шумом уздовж стежки.
				var half: float = lerpf(hw_a, hw_b, t) * (0.67 + 0.66 * _noise(s * 1.7, 5.5, sd + 3))
				_put(buf, (py * w + px) * 2, _wear(s, d, dist / half, total, fade_in, fade_out, sd, solid, flat), touched)


static func _seg_dist(q: Vector2, a: Vector2, ab: Vector2) -> float:
	return q.distance_to(a + ab * clampf((q - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0))


## Знос у точці стежки: s вздовж, d поперек (клітинки), r — відстань від осі в півширинах. Профіль —
## гострий пік, а не плато: від осі знос спадає лінійно, край рваний шумом 0.3–0.5 м, на шумі ж
## проміжки й острівці трави (клітини шуму ≥ 2.5 px, дрібніше за піксель не буває).
static func _wear(s: float, d: float, r: float, total: float, fade_in: float, fade_out: float, sd: int, solid: float, flat: float = 1.3) -> float:
	# Край рваний шумом ±0.15 м (0.4 півширини); на тому ж шумі проміжки й острівці трави.
	var edge: float = 0.6 * _noise(s * 7.0, d * 11.0, sd) + 0.4 * _noise(s * 15.0, d * 23.0, sd + 5)
	var rr: float = r + 0.8 * (edge - 0.5)
	var prof: float = clampf(flat * (1.0 - rr), 0.0, 1.0)
	var bare: float = smoothstep(0.3, 0.55, _noise(s * 7.0, d * 10.0, sd + 11))
	var along: float = 0.65 + 0.35 * _noise(s * 1.4, 3.5, sd + 17)
	var core: float = prof * (solid + (1.0 - solid) * bare) * along
	# Прим'ята трава з боків: на 30–50 % слабша за середину, теж з рваним краєм.
	var band: float = 0.4 * (1.0 - smoothstep(0.9, 2.1, r + 0.8 * (edge - 0.5)))
	var v: float = maxf(core, band)
	if fade_in > 0.0:
		v *= smoothstep(0.0, fade_in, s)
	if fade_out > 0.0:
		v *= smoothstep(0.0, fade_out, total - s)
	return v


## Пляма: рваний овал, в канал G; усередині шматки голішої землі.
static func _stamp_patch(buf: PackedByteArray, w: int, h: int, patch: Vector3, index: int, touched: PackedInt32Array) -> void:
	var c := Vector2(patch.x, patch.y)
	var reach: float = patch.z * 1.45
	var x0: int = maxi(0, floori((c.x - reach + 0.5) * PX_PER_TILE))
	var x1: int = mini(w - 1, ceili((c.x + reach + 0.5) * PX_PER_TILE))
	var y0: int = maxi(0, floori((c.y - reach + 0.5) * PX_PER_TILE))
	var y1: int = mini(h - 1, ceili((c.y + reach + 0.5) * PX_PER_TILE))
	for py in range(y0, y1 + 1):
		for px in range(x0, x1 + 1):
			var q: Vector2 = _px_pos(px, py)
			var u: Vector2 = (q - c) / patch.z
			var rr: float = u.length()
			if rr > 1.45:
				continue
			# Третя, дрібна октава й більший розмах краю: рівний край плями біля паркану читався лінією
			# вздовж його основи.
			var edge: float = 0.5 * _noise(u.x * 2.4 + 9.0, u.y * 2.4 + 9.0, 401 + index) + 0.3 * _noise(u.x * 5.0, u.y * 5.0, 433 + index) \
					+ 0.2 * _noise(u.x * 7.0 + 2.0, u.y * 7.0, 449 + index)
			var bare: float = smoothstep(0.25, 0.65, _noise(u.x * 3.0 + 4.0, u.y * 3.0, 467 + index))
			var v: float = (0.5 + 0.5 * bare) * (1.0 - smoothstep(0.1, 1.0, rr + 0.9 * (edge - 0.5)))
			_put(buf, (py * w + px) * 2 + 1, v, touched)


## Відтінки землі й прим'ятої трави: R:G:B, яскравість тут не 1 — тон ділить відтінок на його
## яскравість у момент змішування, тож відтінок і яскравість — окремі ручки. Відтінок не береться з
## трави: на блідій траві (Хребет) чи під сірою імлою дощу стежка однаково бура, а не сіра пляма.
## Суха — курна жовто-бура; це типові значення, карта ставить свої (BattleLook.path_*_dry): на блідій
## вохристій траві Хребта стежка потребує теплішого відтінку й більшого k, і синього менше, ніж у трави,
## інакше вона рожево-ліловіє. Мокра — тепліша й темніша бура, синього мало, однакова для всіх карт.
const EARTH_DRY := Vector3(1.5, 1.0, 0.4)
const EARTH_WET := Vector3(2.0, 1.0, 0.35)
const TRAMPLED_DRY := Vector3(1.3, 1.0, 0.45)
const TRAMPLED_WET := Vector3(1.35, 1.0, 0.4)
## k сухої стежки: (середина, прим'ята смуга, пляма біля дверей і воріт).
const DRY_K := Vector3(1.4, 1.2, 1.45)
const LUMA := Vector3(0.299, 0.587, 0.114)


## Колір землі під стежкою — та сама формула, що в ground.gdshader (блок Footpaths). Тон —
## яскравість трави в цьому пікселі × відтінок × k, а не сталий колір: у дощ трава темнішає разом зі
## стежкою, текстура ґрунту лишається, і стежка відрізняється від трави лише трохи. k середини:
## суха 1.4, мокра 0.6; прим'ятої смуги — 1.2 / 0.72; плями біля дверей і воріт — 1.45 / 0.5, у повну
## силу вже з G 0.4, щоб вхід у двір читався й на краю плями. Імла й небо на екрані стискають різницю
## альбедо приблизно до k^0.35: k 1.4 дає ~1.12 яскравості трави, 0.6 — ~0.83 (насичений відтінок
## на екрані трохи світліший, тож мокрі k нижчі, ніж без нього). wet_p — 0 сухо, 1 дощ (MUD — 0.7).
## Сухі відтінки й k — карти (BattleLook.path_earth_dry, path_trod_dry, path_dry_k); типові — EARTH_DRY,
## TRAMPLED_DRY, DRY_K.
static func tone(alb: Color, pm: Vector2, wet_p: float, earth_dry: Vector3 = EARTH_DRY,
		trod_dry: Vector3 = TRAMPLED_DRY, dry_k: Vector3 = DRY_K) -> Color:
	var a := Vector3(alb.r, alb.g, alb.b)
	var lum: float = a.dot(LUMA)
	var earth: Vector3 = earth_dry.lerp(EARTH_WET, wet_p)
	earth /= earth.dot(LUMA)
	var trampled: Vector3 = trod_dry.lerp(TRAMPLED_WET, wet_p)
	trampled /= trampled.dot(LUMA)
	var core_t: float = smoothstep(0.5, 0.78, pm.x)
	var band_t: float = smoothstep(0.08, 0.3, pm.x)
	a = a.lerp(trampled * lum * lerpf(dry_k.y, 0.72, wet_p), band_t * 0.8)
	a = a.lerp(earth * lum * lerpf(dry_k.x, 0.6, wet_p), core_t)
	a = a.lerp(earth * lum * lerpf(dry_k.z, 0.5, wet_p), smoothstep(0.05, 0.4, pm.y))
	return Color(a.x, a.y, a.z, alb.a)


static func apply(mat: ShaderMaterial, img: Image, board_size: Vector2i) -> void:
	img.generate_mipmaps()
	mat.set_shader_parameter("has_paths", true)
	mat.set_shader_parameter("path_map", ImageTexture.create_from_image(img))
	mat.set_shader_parameter("path_size", Vector2(board_size))
