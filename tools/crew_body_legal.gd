extends RefCounted
## Дозволені місця тіл розрахунку гармати. Рядок `_SPECS` (`body_spots`) задає кілька місць довкола гармати в її
## системі, а `body_legal` — для кожного з восьми напрямів маску тих, що можна брати, коли гармату знищено. Маску
## складає цей клас: місце дозволене, коли тіло (прямокутник BODY_LENGTH × BODY_WIDTH із запасом MARGIN):
##   - лежить у тайлі;
##   - не торкається уламка, яким його малюють: модель із осадкою й найбільшим нахилом, який дає будь-яка мапа
##     (`build_wreck`: до ±2° довкола двох осей), нижче 1,8 м;
##   - на виду: з фіксованої камери уламок закриває не більше MAX_COVER (таблиця — TABLE_COVER) його екранного прямокутника, на обох краях
##     нахилу камери (PITCH_NEAR_DEG, PITCH_FAR_DEG). Закриває лише те, що ближче до камери за тіло.
## Інструмент `tools/crew_body_table.gd` друкує рядки, тест перераховує таблицю й порівнює.

const MARGIN: float = 0.05
const MAX_COVER: float = 0.30
## Таблиця бере суворіше за правило: екранна тінь складена при нульовому нахилі, а на дошці уламок нахилений до ±2°.
const TABLE_COVER: float = 0.17
const TILT_DEG: float = 2.0
## Нижче цієї висоти (1,8 м) частина уламка стоїть на землі й заважає лягти.
const LOW: float = 0.225
const GROUND_CELL: float = 0.05
const GROUND_N: int = 48
const GROUND_ORIGIN: float = -1.2
const SCREEN_RES: float = 0.01
const SCREEN_N: int = 240
const SCREEN_ORIGIN: float = -1.2


## Вершини уламка, як його малюють: корінь = поворот напряму × нахил (`tilt` у градусах довкола X і Z), модель осідає
## на HULL_SAG. Координати відносно середини тайла; по три вершини на трикутник.
static func wreck_tris(type_id: int, set_id: int, facing: int, tilt: Vector2) -> PackedVector3Array:
	var out := PackedVector3Array()
	var mesh: ArrayMesh = UnitSilhouettes.model_mesh(type_id, set_id)
	if mesh == null:
		return out
	var a: Array = mesh.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var basis: Basis = Basis(Vector3.UP, deg_to_rad(UnitView._degrees_for_facing(facing))) \
			* Basis.from_euler(Vector3(deg_to_rad(tilt.x), 0.0, deg_to_rad(tilt.y)))
	var lift := Vector3(0.0, -WreckLayer.HULL_SAG, 0.0)
	var world := PackedVector3Array()
	world.resize(v.size())
	for i in v.size():
		world[i] = basis * (v[i] + lift)
	for i in idx:
		out.append(world[i])
	return out


## Трикутники нижче LOW у комірках сітки землі: прямокутник питає лише сусідні.
static func ground_index(tris: PackedVector3Array) -> Dictionary:
	var flat := PackedVector2Array()
	var bb := PackedFloat32Array()
	var grid: Array = []
	grid.resize(GROUND_N * GROUND_N)
	for g in grid.size():
		grid[g] = PackedInt32Array()
	for t in range(0, tris.size(), 3):
		var p0: Vector3 = tris[t]
		var p1: Vector3 = tris[t + 1]
		var p2: Vector3 = tris[t + 2]
		if minf(p0.y, minf(p1.y, p2.y)) >= LOW:
			continue
		var n: int = flat.size() / 3
		flat.append_array([Vector2(p0.x, p0.z), Vector2(p1.x, p1.z), Vector2(p2.x, p2.z)])
		var x0: float = minf(p0.x, minf(p1.x, p2.x))
		var x1: float = maxf(p0.x, maxf(p1.x, p2.x))
		var z0: float = minf(p0.z, minf(p1.z, p2.z))
		var z1: float = maxf(p0.z, maxf(p1.z, p2.z))
		bb.append_array([x0, z0, x1, z1])
		for gz in range(_gcell(z0), _gcell(z1) + 1):
			for gx in range(_gcell(x0), _gcell(x1) + 1):
				# Packed* у масиві віддається копією: `as` додав би в тимчасову, тож комірку беремо в змінну й кладемо назад.
				var cell: PackedInt32Array = grid[gz * GROUND_N + gx]
				cell.append(n)
				grid[gz * GROUND_N + gx] = cell
	return {"tris": flat, "bb": bb, "grid": grid}


static func _gcell(v: float) -> int:
	return clampi(floori((v - GROUND_ORIGIN) / GROUND_CELL), 0, GROUND_N - 1)


## Скільки трикутників у сітці землі (тест перевіряє, що вона не порожня й збігається з прямим перебором).
static func indexed_count(index: Dictionary) -> int:
	var n: int = 0
	for cell: PackedInt32Array in index.grid:
		n += cell.size()
	return n


## Чи перетинає прямокутник (середина, довга вісь, пів-довжини, пів-ширини) якийсь трикутник сітки землі.
static func rect_hits(mid: Vector2, long: Vector2, half_l: float, half_w: float, index: Dictionary) -> bool:
	var tris: PackedVector2Array = index.tris
	var bb: PackedFloat32Array = index.bb
	var grid: Array = index.grid
	var wide := Vector2(-long.y, long.x)
	var ex: float = absf(long.x) * half_l + absf(wide.x) * half_w
	var ez: float = absf(long.y) * half_l + absf(wide.y) * half_w
	for gz in range(_gcell(mid.y - ez), _gcell(mid.y + ez) + 1):
		for gx in range(_gcell(mid.x - ex), _gcell(mid.x + ex) + 1):
			for t: int in (grid[gz * GROUND_N + gx] as PackedInt32Array):
				if bb[t * 4] > mid.x + ex or bb[t * 4 + 2] < mid.x - ex or bb[t * 4 + 1] > mid.y + ez or bb[t * 4 + 3] < mid.y - ez:
					continue
				if _tri_hits(mid, long, wide, half_l, half_w, tris[t * 3], tris[t * 3 + 1], tris[t * 3 + 2]):
					return true
	return false


## Той самий перетин прямим перебором усіх трикутників: еталон для перевірки сітки.
static func rect_hits_brute(mid: Vector2, long: Vector2, half_l: float, half_w: float, index: Dictionary) -> bool:
	var tris: PackedVector2Array = index.tris
	var wide := Vector2(-long.y, long.x)
	for t in range(0, tris.size(), 3):
		if _tri_hits(mid, long, wide, half_l, half_w, tris[t], tris[t + 1], tris[t + 2]):
			return true
	return false


static func _tri_hits(mid: Vector2, long: Vector2, wide: Vector2, half_l: float, half_w: float, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var e0: Vector2 = b - a
	var e1: Vector2 = c - b
	var e2: Vector2 = a - c
	for ax: Vector2 in [long, wide, Vector2(-e0.y, e0.x), Vector2(-e1.y, e1.x), Vector2(-e2.y, e2.x)]:
		if ax.length_squared() < 1e-12:
			continue
		var tmin: float = minf(ax.dot(a), minf(ax.dot(b), ax.dot(c)))
		var tmax: float = maxf(ax.dot(a), maxf(ax.dot(b), ax.dot(c)))
		var cen: float = ax.dot(mid)
		var r: float = absf(ax.dot(long)) * half_l + absf(ax.dot(wide)) * half_w
		if tmax < cen - r or cen + r < tmin:
			return false
	return true


## Екранні координати точки (світ, відносно середини тайла) при нахилі камери `pitch`: ортографічно, поперек погляду —
## `across`, угору — висота й глибина вздовж погляду. Остання координата — глибина від камери (менше — ближче).
static func screen_of(p: Vector3, pitch_deg: float) -> Vector3:
	var cam: float = deg_to_rad(IsoCameraRig.YAW_DEGREES)
	var across := Vector2(cos(cam), -sin(cam))
	var away := Vector2(-sin(cam), -cos(cam))
	var pr: float = deg_to_rad(pitch_deg)
	var d: float = Vector2(p.x, p.z).dot(away)
	return Vector3(Vector2(p.x, p.z).dot(across), p.y * cos(pr) + d * sin(pr), d * cos(pr) - p.y * sin(pr))


## Екранна «тінь» уламка: на кожну комірку SCREEN_RES — глибина найближчої його точки (INF — порожньо).
static func silhouette(tris: PackedVector3Array, pitch_deg: float) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(SCREEN_N * SCREEN_N)
	buf.fill(INF)
	for t in range(0, tris.size(), 3):
		var a: Vector3 = screen_of(tris[t], pitch_deg)
		var b: Vector3 = screen_of(tris[t + 1], pitch_deg)
		var c: Vector3 = screen_of(tris[t + 2], pitch_deg)
		var den: float = (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
		if absf(den) < 1e-12:
			continue
		var x0: int = clampi(floori((minf(a.x, minf(b.x, c.x)) - SCREEN_ORIGIN) / SCREEN_RES), 0, SCREEN_N - 1)
		var x1: int = clampi(floori((maxf(a.x, maxf(b.x, c.x)) - SCREEN_ORIGIN) / SCREEN_RES), 0, SCREEN_N - 1)
		var y0: int = clampi(floori((minf(a.y, minf(b.y, c.y)) - SCREEN_ORIGIN) / SCREEN_RES), 0, SCREEN_N - 1)
		var y1: int = clampi(floori((maxf(a.y, maxf(b.y, c.y)) - SCREEN_ORIGIN) / SCREEN_RES), 0, SCREEN_N - 1)
		for gy in range(y0, y1 + 1):
			var py: float = SCREEN_ORIGIN + (float(gy) + 0.5) * SCREEN_RES
			for gx in range(x0, x1 + 1):
				var px: float = SCREEN_ORIGIN + (float(gx) + 0.5) * SCREEN_RES
				var wa: float = ((b.y - c.y) * (px - c.x) + (c.x - b.x) * (py - c.y)) / den
				var wb: float = ((c.y - a.y) * (px - c.x) + (a.x - c.x) * (py - c.y)) / den
				var wc: float = 1.0 - wa - wb
				if wa >= 0.0 and wb >= 0.0 and wc >= 0.0:
					var depth: float = wa * a.z + wb * b.z + wc * c.z
					var k: int = gy * SCREEN_N + gx
					if depth < buf[k]:
						buf[k] = depth
	return buf


## Яку частку екранного прямокутника тіла (точки зразка на землі) закриває уламок, що ближче до камери.
static func covered(mid: Vector2, long: Vector2, buf: PackedFloat32Array, pitch_deg: float) -> float:
	var wide := Vector2(-long.y, long.x)
	var hl: float = WreckLayer.BODY_LENGTH * 0.5
	var hw: float = WreckLayer.BODY_WIDTH * 0.5
	var n: int = 6
	var hit: int = 0
	for i in n:
		for j in n:
			var q: Vector2 = mid + long * (-hl + (float(i) + 0.5) / float(n) * 2.0 * hl) + wide * (-hw + (float(j) + 0.5) / float(n) * 2.0 * hw)
			var s: Vector3 = screen_of(Vector3(q.x, 0.02, q.y), pitch_deg)
			var gx: int = floori((s.x - SCREEN_ORIGIN) / SCREEN_RES)
			var gy: int = floori((s.y - SCREEN_ORIGIN) / SCREEN_RES)
			if gx >= 0 and gy >= 0 and gx < SCREEN_N and gy < SCREEN_N and buf[gy * SCREEN_N + gx] < s.z - 0.002:
				hit += 1
	return float(hit) / float(n * n)


## Тіло на місці: (середина, довга вісь) у системі тайла. Те саме перетворення, що й на дошці (crew_spot_xf).
static func spot_rect(spot: Vector3, facing: int) -> Array:
	var xf: Transform3D = WreckLayer.crew_spot_xf(spot, facing)
	var mid: Vector3 = WreckLayer.body_centre(xf)
	return [Vector2(mid.x, mid.z), Vector2(xf.basis.z.x, xf.basis.z.z).normalized()]


## Три перевірки одного місця при одному напрямі; `tilts` — сітки землі уламка при крайніх нахилах, `bufs` — його екранні
## тіні на двох краях нахилу камери. Повертає {tile, clear, cover} для діагностики.
static func spot_report(spot: Vector3, facing: int, tilts: Array, bufs: Array) -> Dictionary:
	var r: Array = spot_rect(spot, facing)
	var mid: Vector2 = r[0]
	var long: Vector2 = r[1]
	var wide := Vector2(-long.y, long.x)
	var hl: float = WreckLayer.BODY_LENGTH * 0.5
	var hw: float = WreckLayer.BODY_WIDTH * 0.5
	var tile: bool = true
	for sl: float in [-1.0, 1.0]:
		for sw: float in [-1.0, 1.0]:
			var corner: Vector2 = mid + long * (hl * sl) + wide * (hw * sw)
			tile = tile and absf(corner.x) <= 0.5 and absf(corner.y) <= 0.5
	var clear: bool = true
	for index: Dictionary in tilts:
		clear = clear and not rect_hits(mid, long, hl + MARGIN, hw + MARGIN, index)
	var cover: float = 0.0
	var pitches: Array[float] = [IsoCameraRig.PITCH_NEAR_DEG, IsoCameraRig.PITCH_FAR_DEG]
	for i in bufs.size():
		cover = maxf(cover, covered(mid, long, bufs[i], pitches[i]))
	return {"tile": tile, "clear": clear, "cover": cover}


## Маски дозволених місць (напрям → маска) для рядка типу `type_id` набору `set_id`.
static func legal_masks(type_id: int, set_id: int) -> PackedInt32Array:
	var spots: Array = UnitSilhouettes.spec(type_id, set_id).get("body_spots", [])
	var out := PackedInt32Array()
	for facing in 8:
		var tilts: Array = []
		for tx: float in [-TILT_DEG, TILT_DEG]:
			for tz: float in [-TILT_DEG, TILT_DEG]:
				tilts.append(ground_index(wreck_tris(type_id, set_id, facing, Vector2(tx, tz))))
		var plain: PackedVector3Array = wreck_tris(type_id, set_id, facing, Vector2.ZERO)
		tilts.append(ground_index(plain))
		var bufs: Array = [silhouette(plain, IsoCameraRig.PITCH_NEAR_DEG), silhouette(plain, IsoCameraRig.PITCH_FAR_DEG)]
		var mask: int = 0
		for i in spots.size():
			var rep: Dictionary = spot_report(spots[i], facing, tilts, bufs)
			if rep.tile and rep.clear and rep.cover <= TABLE_COVER:
				mask |= 1 << i
		out.append(mask)
	return out
