class_name RiverCourse
extends RefCounted
## Гладка осьова лінія річки (рішення власника 2026-10-23: сітка живе лише в логіці й шляхах,
## на екрані річка не знає про клітинки). Береться з клітинок WATER/BRIDGE: скелет маски
## (Zhang-Suen на сітці по U пікселів на клітинку), гілки-«шпори» відрізаються, лінія
## перевибирається з кроком STEP і згладжується Гаусом, тож сходинка клітинок в 1 клітинку
## стає довгою діагоналлю. Ширина гуляє 0.6-1.4 логічної (хвиля ~4.5 клітинки), вісь — на ±0.2.
## Береги — відстань до ламаної мінус півширина (об'єднання капсул).
##
## Лише вигляд: жодне правило цього не читає. Клітинки суші лишаються сухими в радіусі
## 0.3 від центру (CLEAR), а під мостом лінія пряма й перпендикулярна настилу (піни).

const U: int = 3
const STEP: float = 0.35
const SIGMA: float = 1.2
## Вода лишається ≥ 0.3 від центру будь-якої клітинки суші (там стоять юніти); 0.05 — запас
## на кроці ламаної між вершинами.
const CLEAR: float = 0.33
const WIDTH_VAR: float = 0.3
const WANDER: float = 0.35
## Друга октава (хвиля ~2 клітинки): береги не лишаються прямими довше за клітинку-дві.
const WIDTH_FINE: float = 0.12
const WANDER_FINE: float = 0.1
## Не вужче за 9 м (1.12 клітинки), крім місць, де клітинки суші не лишають місця.
const MIN_HALF: float = 0.56
## Півширина не більша за стільки медіан осі.
const MAX_OVER_MEDIAN: float = 1.45
## Ядро площі: клітинки води далі за LAKE_DT від суші (озеро) дають диски радіуса 0.85-1.2.
const LAKE_DT: float = 1.4
## Амплітуда варпу контуру ставка (клітинок) і ставок завдовжки менше за ARC_POND.
const WARP: float = 0.3
const WARP_FINE: float = 0.1
const ARC_POND: float = 3.0
## Малий ставок збурюється слабше (множник), бо радіус ~0.6 не витримає 0.4 варпу.
const POND_WARP: float = 0.4
## Ставок — група води не більша за стільки клітинок; радіуси дисків ставка (клітинок).
const POND_CELLS: int = 8
const POND_EDGE_GAP: float = 0.12
const POND_DISC: float = 0.6
const POND_DISC_CENTRE: float = 0.62
const POND_DISC_MID: float = 0.5
const POND_JITTER: float = 0.22
## Ставок не ближче за стільки до краю дошки.
const EDGE_GAP: float = 0.3
## Клітинка води, де після зсуву берега лишається менше за цю частку води, розсуває берег (_widen).
const MIN_WET: float = 0.5
## Дальність поля: далі нього відстань до води не змінює ні схил, ні пагорб.
const REACH: float = 1.6
const FAR: float = 2.0
const KAPPA_LO: float = 0.06
const KAPPA_HI: float = 0.22

## Ламані осі (світові клітинки), півширини й знакова кривизна на вершинах.
var lines: Array[PackedVector2Array] = []
## Скільки перших ліній — справжня вісь; далі лише допоміжні виступи берега (_widen).
var main_count: int = 0
## Номери ліній-ставків (коротких): контур збурено шумом (домен-варп 0.3 клітинки), без прямих сторін.
var _pond_lines: Dictionary = {}
## Номери ліній-дисків ставка (підмножина _pond_lines).
var _disc_ponds: Dictionary = {}
var _warp_x: FastNoiseLite
var _warp_z: FastNoiseLite
var _warp_x2: FastNoiseLite
var _warp_z2: FastNoiseLite
var halfs: Array[PackedFloat32Array] = []
var kappas: Array[PackedFloat32Array] = []

var _w: int = 0
var _h: int = 0
var _wgrid: PackedByteArray = PackedByteArray()
## Диски озера (x, z, радіус).
var _discs: PackedVector3Array = PackedVector3Array()
## Центри мостів: біля них берег не розсуваємо (настил, піни).
var _bridge_centres: PackedVector2Array = PackedVector2Array()


## bridges — {centre: Vector2, axis: Vector2 (вісь настилу), length: float (клітинок уздовж осі),
## across: float (клітинок упоперек)}. pad — на скільки клітинок за межею дошки продовжити річку.
static func build(wgrid: PackedByteArray, w: int, h: int, pad: int, bridges: Array[Dictionary], seed_value: int) -> RiverCourse:
	var rc := RiverCourse.new()
	rc._w = w
	rc._h = h
	rc._wgrid = wgrid
	for br in bridges:
		rc._bridge_centres.append(br["centre"])
	var x0: int = w
	var x1: int = -1
	var y0: int = h
	var y1: int = -1
	for cy in h:
		for cx in w:
			if wgrid[cy * w + cx] == 1:
				x0 = mini(x0, cx)
				x1 = maxi(x1, cx)
				y0 = mini(y0, cy)
				y1 = maxi(y1, cy)
	if x1 < 0:
		return rc
	# Зображення з рамкою в 1 піксель суші (скелет не липне до краю); піксель (i, j) → світ.
	var ox: float = float(x0) - 0.5 - pad
	var oz: float = float(y0) - 0.5 - pad
	var nx: int = (x1 - x0 + 1 + 2 * pad) * U + 2
	var ny: int = (y1 - y0 + 1 + 2 * pad) * U + 2
	var img := PackedByteArray()
	img.resize(nx * ny)
	for j in range(1, ny - 1):
		for i in range(1, nx - 1):
			img[j * nx + i] = 1 if rc._is_water_at(floori(ox + (float(i) - 0.5) / U + 0.5), floori(oz + (float(j) - 0.5) / U + 0.5)) else 0
	_thin(img, nx, ny)
	_prune(img, nx, ny, 3 * U)
	_prune(img, nx, ny, 3 * U)
	var n_w := FastNoiseLite.new()
	n_w.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n_w.seed = seed_value + 909
	n_w.frequency = 0.22
	var n_l := FastNoiseLite.new()
	n_l.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n_l.seed = seed_value + 919
	n_l.frequency = 0.22
	var n_w2 := FastNoiseLite.new()
	n_w2.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n_w2.seed = seed_value + 929
	n_w2.frequency = 0.5
	var n_l2 := FastNoiseLite.new()
	n_l2.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n_l2.seed = seed_value + 939
	n_l2.frequency = 0.45
	rc._warp_x = _mk_noise(seed_value + 961, 0.9)
	rc._warp_z = _mk_noise(seed_value + 971, 0.9)
	rc._warp_x2 = _mk_noise(seed_value + 981, 2.2)
	rc._warp_z2 = _mk_noise(seed_value + 991, 2.2)
	var pinned: Array[bool] = []
	pinned.resize(bridges.size())
	for path in _trace(img, nx, ny):
		var raw := PackedVector2Array()
		for k in path:
			raw.append(Vector2(ox + ((k % nx) - 0.5) / U, oz + (float(k / nx) - 0.5) / U))
		rc._add_line(raw, bridges, [n_w, n_l, n_w2, n_l2], pinned)
	# Міст, до якого не дотяглась жодна вісь, дістає власну коротку вісь: вода під настилом
	# гарантована, а кінці настилу лишаються сухими (піввисота ≤ довжина / 2 - 0.15).
	for bi in bridges.size():
		if pinned[bi]:
			continue
		var br: Dictionary = bridges[bi]
		var c: Vector2 = br["centre"]
		var axis: Vector2 = br["axis"]
		var perp := Vector2(-axis.y, axis.x)
		var run: float = float(br["across"]) * 0.5 + 0.6
		var pts := PackedVector2Array([c - perp * run, c, c + perp * run])
		var hw := PackedFloat32Array()
		for p in pts:
			hw.append(maxf(minf(float(br["length"]) * 0.5 - 0.15, rc._land_centre_dist(p.x, p.y) - CLEAR), 0.02))
		rc.lines.append(pts)
		rc.halfs.append(hw)
		rc.kappas.append(PackedFloat32Array([0.0, 0.0, 0.0]))
	rc._lakes(seed_value)
	rc.main_count = rc.lines.size()
	rc._widen()
	return rc


## Розсуває береги там, де клітинка води лишилась би (майже) сухою: півширина осі плавно
## росте на ~3.5 клітинки уздовж течії (виступ того ж профілю, що берег, без окремих плям).
func _widen() -> void:
	for cz in _h:
		for cx in _w:
			if _wgrid[cz * _w + cx] == 0:
				continue
			var wet := 0
			for j in 5:
				for i in 5:
					# Береговий зсув звужує воду до 0.2: рахуємо те, що його переживе.
					wet += 1 if _water_d(cx - 0.4 + i * 0.2, cz - 0.4 + j * 0.2) < -0.2 else 0
			if float(wet) >= MIN_WET * 25.0:
				continue
			var c := Vector2(cx, cz)
			var best_li := -1
			var best_vi := 0
			var best_d := 1e9
			for li in lines.size():
				for vi in lines[li].size():
					var dd: float = lines[li][vi].distance_to(c)
					if dd < best_d:
						best_d = dd
						best_li = li
						best_vi = vi
			# Найближче озерне ядро: якщо воно ближче за вісь, розсуваємо диски озера (кут озера).
			var disc_best := -1
			var disc_d := 1e9
			for di in _discs.size():
				var dd: float = Vector2(_discs[di].x, _discs[di].y).distance_to(c)
				if dd < disc_d:
					disc_d = dd
					disc_best = di
			if disc_best >= 0 and disc_d < best_d:
				for di in _discs.size():
					var dc: Vector3 = _discs[di]
					var dd: float = Vector2(dc.x, dc.y).distance_to(c)
					if dd > disc_d + 1.6:
						continue
					# Клітинка суші дальше за 0.3: радіус ≤ відстань до суші + 0.2 - запас.
					var cap: float = _dt(dc.x, dc.y) + CLEAR - 0.2 + 0.2 - 0.13
					var w: float = exp(-pow((dd - disc_d) / 0.8, 2.0))
					var target: float = minf(dd + 0.15, cap)
					_discs[di].z = maxf(dc.z, lerpf(dc.z, target, w))
				continue
			if best_li < 0:
				continue
			var pts: PackedVector2Array = lines[best_li]
			var hw: PackedFloat32Array = halfs[best_li]
			var dir: Vector2 = (c - pts[best_vi]).normalized()
			# Односторонній виступ — окрема гладка ламана, зсунута до клітинки: береги об'єднуються,
			# вісь і її кривизна не чіпаються; зсув згасає по Гаусу вздовж течії (~5 клітинок).
			var q := PackedVector2Array()
			var qh := PackedFloat32Array()
			for vi in range(maxi(best_vi - 10, 0), mini(best_vi + 11, pts.size())):
				var near_bridge := false
				for bc in _bridge_centres:
					near_bridge = near_bridge or pts[vi].distance_to(bc) < 1.6
				var w: float = exp(-pow(float(vi - best_vi) * STEP / 1.4, 2.0))
				var rr: float = maxf(0.55 * hw[vi], 0.36)
				var sh: float = maxf(best_d + 0.15 - rr, 0.0) * w
				if near_bridge:
					sh = 0.0
				var ok := false
				for _k in 9:
					var e: Vector2 = pts[vi] + dir * sh
					# Диск радіуса rr у точці e: до найближчого центру суші не ближче CLEAR.
					ok = _land_centre_dist(e.x, e.y) - rr >= CLEAR
					ok = ok and (not _pond_lines.has(best_li) or _edge_dist(e.x, e.y) - rr >= EDGE_GAP)
					if ok:
						break
					# Спершу зсув, далі й радіус: виступ не має заходити ближче CLEAR до центру суші.
					if _k < 4:
						sh *= 0.5
					else:
						rr *= 0.7
				if not ok:
					sh = 0.0
					rr = 0.02
				q.append(pts[vi] + dir * sh)
				qh.append(rr)
			if q.size() > 1:
				lines.append(q)
				halfs.append(qh)
				kappas.append(PackedFloat32Array())
				kappas[kappas.size() - 1].resize(q.size())


## Найменше знакове d серед осей і дисків у точці (клітинки; мінус у воді).
func _water_d(x: float, z: float) -> float:
	var best: float = FAR
	var p0 := Vector2(x, z)
	var pw: Vector2 = p0 + _warp(x, z)
	for li in lines.size():
		var p: Vector2 = p0 + _warp(x, z, _pond_lines[li]) if _pond_lines.has(li) else p0
		var pts: PackedVector2Array = lines[li]
		var hw: PackedFloat32Array = halfs[li]
		for si in maxi(pts.size() - 1, 1):
			var sj: int = mini(si + 1, pts.size() - 1)
			var a: Vector2 = pts[si]
			var ab: Vector2 = pts[sj] - a
			if absf(p.x - a.x) > 4.0 or absf(p.y - a.y) > 4.0:
				continue
			var t: float = clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
			best = minf(best, p.distance_to(a + ab * t) - lerpf(hw[si], hw[sj], t))
	for dc in _discs:
		best = minf(best, pw.distance_to(Vector2(dc.x, dc.y)) - dc.z)
	return best


static func _mk_noise(seed_value: int, freq: float) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = seed_value
	n.frequency = freq
	return n


## Зсув точки для контурів ставків і озер: 0.3 клітинки на хвилі ~1 клітинка + 0.1 на ~0.4.
func _warp(x: float, z: float, k: float = 1.0) -> Vector2:
	return k * Vector2(WARP * clampf(1.6 * _warp_x.get_noise_2d(x, z), -1.0, 1.0) + WARP_FINE * clampf(1.6 * _warp_x2.get_noise_2d(x, z), -1.0, 1.0),
			WARP * clampf(1.6 * _warp_z.get_noise_2d(x, z), -1.0, 1.0) + WARP_FINE * clampf(1.6 * _warp_z2.get_noise_2d(x, z), -1.0, 1.0))


## Відстань від точки до краю дошки (клітинок).
func _edge_dist(x: float, z: float) -> float:
	return minf(minf(x + 0.5, _w - 0.5 - x), minf(z + 0.5, _h - 0.5 - z))


## Диски озера: центри клітинок води, що далі LAKE_DT від суші; радіус гуляє 0.85-1.2 за шумом.
func _lakes(seed_value: int) -> void:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = seed_value + 949
	n.frequency = 0.35
	for cz in _h:
		for cx in _w:
			if _wgrid[cz * _w + cx] == 1 and _dt(cx, cz) >= LAKE_DT:
				_discs.append(Vector3(cx, cz, 1.2 - 0.35 * (0.5 + 0.5 * clampf(1.6 * n.get_noise_2d(cx, cz), -1.0, 1.0))))


## Знакова відстань до урізу (клітинки; мінус у воді) і «вигин» -1..1 (+ зовнішній берег, - коса)
## на ГРУБІЙ сітці з кроком step відліків: вузол (ic, jc) — відлік (ic * step, jc * step) повної
## сітки cols x rows, що лежить у світі на (-0.5 - margin + i / samples, ...).
func field(cols: int, rows: int, samples: int, margin: int, step: int) -> Array[PackedFloat32Array]:
	var cw: int = (cols - 1 + step - 1) / step + 1
	var ch: int = (rows - 1 + step - 1) / step + 1
	var d := PackedFloat32Array()
	var lat := PackedFloat32Array()
	var kap := PackedFloat32Array()
	d.resize(cw * ch)
	d.fill(FAR)
	lat.resize(cw * ch)
	kap.resize(cw * ch)
	# Ставки — окреме поле: TerrainHeight згладжує його сильніше за річку (контур без слідів клітинок).
	var pond := PackedFloat32Array()
	pond.resize(cw * ch)
	pond.fill(FAR)
	var lat_p := PackedFloat32Array()
	lat_p.resize(cw * ch)
	var kap_p := PackedFloat32Array()
	kap_p.resize(cw * ch)
	var cs: float = float(step) / float(samples)
	var org: float = -0.5 - margin
	for li in lines.size():
		var pts: PackedVector2Array = lines[li]
		var hw: PackedFloat32Array = halfs[li]
		var kp: PackedFloat32Array = kappas[li]
		for si in maxi(pts.size() - 1, 1):
			var sj: int = mini(si + 1, pts.size() - 1)
			if _disc_ponds.has(li):
				_splat(pond, lat_p, kap_p, cw, ch, cs, org, pts[si], pts[sj], hw[si], hw[sj], kp[si], kp[sj], _pond_lines.get(li, 0.0))
			else:
				_splat(d, lat, kap, cw, ch, cs, org, pts[si], pts[sj], hw[si], hw[sj], kp[si], kp[sj], _pond_lines.get(li, 0.0))
	for dc in _discs:
		var c := Vector2(dc.x, dc.y)
		_splat(d, lat, kap, cw, ch, cs, org, c, c, dc.z, dc.z, 0.0, 0.0, 1.0)
	var bend := PackedFloat32Array()
	bend.resize(cw * ch)
	for k in bend.size():
		if d[k] < REACH:
			# Центр кривизни — з боку lat > 0 при kap > 0: зовнішній берег там, де lat і kap різних знаків.
			var kn: float = signf(kap[k]) * smoothstep(KAPPA_LO, KAPPA_HI, absf(kap[k]))
			bend[k] = -clampf(lat[k] / 0.35, -1.0, 1.0) * kn
	return [d, bend, pond]


## Капсула a-b з півширинами ha-hb: оновлює d (мінімум), бік lat і кривизну kap у вузлах.
func _splat(d: PackedFloat32Array, lat: PackedFloat32Array, kap: PackedFloat32Array, cw: int, ch: int, cs: float, org: float, a: Vector2, b: Vector2, ha: float, hb: float, ka: float, kb: float, warp: float = 0.0) -> void:
	var r: float = maxf(ha, hb) + REACH + (WARP + WARP_FINE) * warp
	var ic0: int = maxi(ceili((minf(a.x, b.x) - r - org) / cs), 0)
	var ic1: int = mini(floori((maxf(a.x, b.x) + r - org) / cs), cw - 1)
	var jc0: int = maxi(ceili((minf(a.y, b.y) - r - org) / cs), 0)
	var jc1: int = mini(floori((maxf(a.y, b.y) + r - org) / cs), ch - 1)
	var abx: float = b.x - a.x
	var abz: float = b.y - a.y
	var len2: float = maxf(abx * abx + abz * abz, 1e-9)
	var inv_len: float = 1.0 / sqrt(len2)
	for jc in range(jc0, jc1 + 1):
		var pz: float = org + jc * cs
		for ic in range(ic0, ic1 + 1):
			var px: float = org + ic * cs
			var qz0: float = pz
			if warp > 0.0:
				var wv: Vector2 = _warp(px, pz, warp)
				px += wv.x
				qz0 += wv.y
			var t: float = clampf(((px - a.x) * abx + (qz0 - a.y) * abz) / len2, 0.0, 1.0)
			var qx: float = px - (a.x + abx * t)
			var qz: float = qz0 - (a.y + abz * t)
			var dd: float = sqrt(qx * qx + qz * qz) - lerpf(ha, hb, t)
			var k: int = jc * cw + ic
			if dd < d[k]:
				d[k] = dd
				lat[k] = (abx * qz - abz * qx) * inv_len
				kap[k] = lerpf(ka, kb, t)


## Білінійне значення грубої сітки field() у відліку (i, j) повної сітки.
static func upsample(coarse: PackedFloat32Array, cols: int, rows: int, step: int, i: int, j: int) -> float:
	var cw: int = (cols - 1 + step - 1) / step + 1
	var ch: int = (rows - 1 + step - 1) / step + 1
	var fx: float = float(i) / float(step)
	var fz: float = float(j) / float(step)
	var ix: int = mini(int(fx), cw - 2)
	var iz: int = mini(int(fz), ch - 2)
	var tx: float = fx - ix
	var tz: float = fz - iz
	return lerpf(lerpf(coarse[iz * cw + ix], coarse[iz * cw + ix + 1], tx), lerpf(coarse[(iz + 1) * cw + ix], coarse[(iz + 1) * cw + ix + 1], tx), tz)


func _add_line(raw: PackedVector2Array, bridges: Array[Dictionary], noises: Array[FastNoiseLite], pinned: Array[bool]) -> void:
	var n_w: FastNoiseLite = noises[0]
	var n_l: FastNoiseLite = noises[1]
	var n_w2: FastNoiseLite = noises[2]
	var n_l2: FastNoiseLite = noises[3]
	var pts: PackedVector2Array = _resample(raw)
	var n: int = pts.size()
	pts = _gauss_v(pts, SIGMA)
	# Скелет короткого ставка коротший за сам ставок на півширини з кінців: подовжуємо його.
	if n >= 2 and (pts[n - 1] - pts[0]).length() + 0.0 < ARC_POND:
		var t0: Vector2 = (pts[0] - pts[1]).normalized() if pts[0] != pts[1] else Vector2.ZERO
		var t1: Vector2 = (pts[n - 1] - pts[n - 2]).normalized() if pts[n - 1] != pts[n - 2] else Vector2.ZERO
		if t0 != Vector2.ZERO:
			pts.insert(0, pts[0] + t0 * 0.4)
		if t1 != Vector2.ZERO:
			pts.append(pts[pts.size() - 1] + t1 * 0.4)
		n = pts.size()
	# Довжина дуги й дотичні вздовж течії.
	var s := PackedFloat32Array()
	s.resize(n)
	for i in range(1, n):
		s[i] = s[i - 1] + pts[i].distance_to(pts[i - 1])
	var tang := _tangents(pts)
	var wander: float = 1.0 if s[n - 1] >= ARC_POND else 0.0
	for i in n:
		var off: float = wander * (WANDER * clampf(1.6 * n_l.get_noise_2d(pts[i].x, pts[i].y), -1.0, 1.0) \
				+ WANDER_FINE * clampf(1.6 * n_l2.get_noise_2d(pts[i].x, pts[i].y), -1.0, 1.0))
		pts[i] += Vector2(-tang[i].y, tang[i].x) * off
	# Після зсуву — ще раз згладити, щоб кривизна не стала різкішою за R ≈ 1.5 ширини.
	pts = _gauss_v(pts, 0.8)
	# Піни мостів: пряма через центр настилу, перпендикулярно його осі.
	var cap := PackedFloat32Array()
	cap.resize(n)
	cap.fill(1e3)
	if n > 1:
		for bi in bridges.size():
			var br: Dictionary = bridges[bi]
			var c: Vector2 = br["centre"]
			var axis: Vector2 = br["axis"]
			var perp := Vector2(-axis.y, axis.x)
			var half_run: float = float(br["across"]) * 0.5 + 0.1
			var near := -1
			var near_d := 1.0
			for i in n:
				var dd: float = pts[i].distance_to(c)
				if dd < near_d:
					near_d = dd
					near = i
			if near < 0:
				continue
			pinned[bi] = true
			var cap_b: float = float(br["length"]) * 0.5 - 0.15
			for i in n:
				var w: float = 1.0 - smoothstep(half_run, half_run + 1.0, absf(s[i] - s[near]))
				if w <= 0.0:
					continue
				var target: Vector2 = c + perp * (pts[i] - c).dot(perp)
				pts[i] = pts[i].lerp(target, w)
				cap[i] = minf(cap[i], lerpf(1e3, cap_b, w))
	# Півширина береться від запасу до центрів суші (вода майже на всю логічну смугу, тож клітинки
	# води лишаються мокрими), згладженого вздовж осі, і гуляє 0.6-1.0 цього запасу.
	var room := PackedFloat32Array()
	for i in n:
		room.append(_land_centre_dist(pts[i].x, pts[i].y) - CLEAR)
	var smooth: PackedFloat32Array = _gauss_f(room, 0.7)
	var sorted_room: Array = Array(smooth)
	sorted_room.sort()
	var hmax: float = MAX_OVER_MEDIAN * sorted_room[n / 2]
	var hw := PackedFloat32Array()
	hw.resize(n)
	for i in n:
		var f: float = 0.85 + WIDTH_VAR * 0.5 * clampf(1.6 * n_w.get_noise_2d(pts[i].x, pts[i].y), -1.0, 1.0) \
				+ WIDTH_FINE * clampf(1.6 * n_w2.get_noise_2d(pts[i].x, pts[i].y), -1.0, 1.0)
		# Мінімальна ширина — найслабше з обмежень: і кришка під мостом, і запас до центрів суші
		# (юніти стоять там) сильніші за неї.
		var v: float = maxf(minf(smooth[i] * clampf(f, 0.6, 1.0), hmax), MIN_HALF)
		hw[i] = maxf(minf(minf(v, cap[i]), room[i]), 0.02)
	# Короткий контур — ставок: береги не пряміші за варп, тож півширина менша на амплітуду варпу,
	# а до краю дошки лишається проміжок EDGE_GAP.
	if s[n - 1] < ARC_POND:
		var pinned_here := false
		for v in cap:
			pinned_here = pinned_here or v < 1e3
		var cells: Array[Vector2i] = []
		if not pinned_here:
			cells = _pond_cells(pts[n / 2])
		if not cells.is_empty():
			_add_pond_discs(cells)
			return
		_pond_lines[lines.size()] = POND_WARP
		var amp: float = (WARP + WARP_FINE) * POND_WARP
		for i in n:
			var edge_room: float = _edge_dist(pts[i].x, pts[i].y) - EDGE_GAP - amp
			hw[i] = maxf(minf(room[i] - amp, edge_room), minf(0.3, maxf(room[i], 0.02)))
			# Лінза замість капсули: у ставка нема прямих боків (кінці звужені за еліпсом).
			var u: float = s[i] / maxf(s[n - 1], 1e-4)
			var lens: float = sqrt(clampf(1.0 - pow(2.0 * u - 1.0, 2.0), 0.0, 1.0))
			if s[n - 1] > 0.1:
				hw[i] = maxf(hw[i] * lerpf(1.0, lens, 0.85), minf(0.2, hw[i]))
	# Кривизна: поворот дотичної на довжину дуги, згладжена (сирий другий різницевий шумить).
	var kp := PackedFloat32Array()
	kp.resize(n)
	if n > 2:
		var ang := PackedFloat32Array()
		for i in n - 1:
			ang.append((pts[i + 1] - pts[i]).angle())
		for i in range(1, n - 1):
			kp[i] = angle_difference(ang[i - 1], ang[i]) / STEP
		kp = _gauss_f(kp, 0.9)
	lines.append(pts)
	halfs.append(hw)
	kappas.append(kp)


## Клітинки малої водойми (4-зв'язна група води на дошці, не більша за POND_CELLS), що містить
## точку p; порожньо, якщо це не ставок (тоді лишається капсула).
func _pond_cells(p: Vector2) -> Array[Vector2i]:
	var start := Vector2i(roundi(p.x), roundi(p.y))
	var out: Array[Vector2i] = []
	if start.x < 0 or start.y < 0 or start.x >= _w or start.y >= _h or _wgrid[start.y * _w + start.x] == 0:
		return out
	out.append(start)
	var i := 0
	while i < out.size():
		var c: Vector2i = out[i]
		i += 1
		for d in Board.DIRS_4:
			var q: Vector2i = c + d
			if q.x >= 0 and q.y >= 0 and q.x < _w and q.y < _h and _wgrid[q.y * _w + q.x] == 1 and not out.has(q):
				out.append(q)
		if out.size() > POND_CELLS:
			out.clear()
			return out
	return out


## Ставок — об'єднання круглих дисків (по одному на клітинку води + трохи більший центральний),
## кожен у своєму доменному варпі: без прямих сторін і «хреста» накладених виступів. Радіус
## обмежено запасом до центрів суші й до краю дошки, як у лінзи.
func _add_pond_discs(cells: Array[Vector2i]) -> void:
	var amp: float = (WARP + WARP_FINE) * POND_WARP
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := Vector2i(-(1 << 20), -(1 << 20))
	for c in cells:
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	var ext: Vector2i = hi - lo + Vector2i.ONE
	# Майже повний прямокутник клітинок (3x2 тощо) — еліпс, а не ґратка дисків: ґратка з рівними
	# рядами дає прямі боки. Інакше (Г-подібний ставок) — диски на клітинках.
	if cells.size() * 4 >= ext.x * ext.y * 3:
		_add_pond_ellipse(Vector2(lo + hi) * 0.5, Vector2(ext), amp)
		return
	var centre := Vector2.ZERO
	for c in cells:
		centre += Vector2(c)
	centre /= float(cells.size())
	var spots: Array[Vector3] = []
	for c in cells:
		spots.append(Vector3(c.x, c.y, POND_DISC))
	spots.append(Vector3(centre.x, centre.y, POND_DISC_CENTRE))
	# Диски сусідніх клітинок торкаються лише «шийкою»: диск на середині кожної пари (і в центрі
	# квадрата 2x2) заповнює її, тож контур не бубликовий, а один овал.
	for c in cells:
		for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
			if cells.has(c + d):
				spots.append(Vector3(c.x + 0.5 * d.x, c.y + 0.5 * d.y, POND_DISC_MID))
		if cells.has(c + Vector2i(1, 0)) and cells.has(c + Vector2i(0, 1)) and cells.has(c + Vector2i(1, 1)):
			spots.append(Vector3(c.x + 0.5, c.y + 0.5, POND_DISC_CENTRE))
	for sp in spots:
		# Диск біля краю дошки зсунуто всередину й може підійти до краю ближче, ніж лінза: інакше
		# береговий зсув з'їдає воду в клітинці краю, і вона лишається сухою.
		var inset: float = POND_EDGE_GAP + 0.45
		# Радіус і зсув кожного диска — свої (шум від координат), щоб ряд клітинок не давав рівних випуклин.
		var jx: float = _warp_x2.get_noise_2d(sp.x * 5.3 + 1.7, sp.y * 5.3)
		var jz: float = _warp_z2.get_noise_2d(sp.x * 5.3, sp.y * 5.3 + 3.1)
		var jr: float = _warp_x.get_noise_2d(sp.x * 4.1 + 9.0, sp.y * 4.1)
		sp = Vector3(sp.x + POND_JITTER * clampf(1.6 * jx, -1.0, 1.0), sp.y + POND_JITTER * clampf(1.6 * jz, -1.0, 1.0), sp.z * (1.0 + 0.3 * clampf(1.6 * jr, -1.0, 1.0)))
		# Біля краю диск стоїть на своїй глибині й не впирається в EDGE_GAP, тож верх ставка не рівна лінія.
		inset += 0.2 * (0.5 + 0.5 * clampf(1.6 * jr, -1.0, 1.0))
		var pos := Vector2(clampf(sp.x, inset - 0.5, _w - 0.5 - inset), clampf(sp.y, inset - 0.5, _h - 0.5 - inset))
		var room: float = _land_centre_dist(pos.x, pos.y) - CLEAR
		var edge_room: float = _edge_dist(pos.x, pos.y) - POND_EDGE_GAP - 0.12 * (0.5 + 0.5 * clampf(1.6 * jx, -1.0, 1.0))
		var r: float = maxf(minf(minf(sp.z, room - amp), edge_room), minf(0.3, maxf(room, 0.02)))
		_pond_lines[lines.size()] = POND_WARP
		_disc_ponds[lines.size()] = true
		lines.append(PackedVector2Array([pos]))
		halfs.append(PackedFloat32Array([r]))
		kappas.append(PackedFloat32Array([0.0]))


## Еліптичний ставок: лінза з ~9 дисків уздовж довшої осі (профіль півширини sqrt(1 - t^2)), вісь
## повернута на ±10°, профіль і центр збурено шумом від координат. Півширина обмежена запасом
## до центрів суші й краю дошки; біля краю центр зсунуто всередину, тож верх не рівна лінія.
func _add_pond_ellipse(centre: Vector2, ext: Vector2, amp: float) -> void:
	var along_x: bool = ext.x >= ext.y
	var a: float = (ext.x if along_x else ext.y) * 0.5 * 0.97 + 0.12
	var short: float = ext.y if along_x else ext.x
	var b: float = short * 0.5 * (0.9 if short >= 2.0 else 1.0)
	var n1: float = clampf(1.6 * _warp_x.get_noise_2d(centre.x * 3.7, centre.y * 3.7), -1.0, 1.0)
	var n2: float = clampf(1.6 * _warp_z.get_noise_2d(centre.x * 3.7 + 5.0, centre.y * 3.7), -1.0, 1.0)
	var c: Vector2 = centre + Vector2(POND_JITTER * 0.5 * n1, POND_JITTER * 0.5 * n2)
	var ang: float = deg_to_rad(10.0) * n2
	var dir := Vector2(1.0, 0.0).rotated(ang) if along_x else Vector2(0.0, 1.0).rotated(ang)
	var perp := Vector2(-dir.y, dir.x)
	# Центр зсунуто так, щоб верх еліпса не заходив у проміжок до краю дошки.
	var inset: float = POND_EDGE_GAP + b * 0.9
	c = Vector2(clampf(c.x, inset - 0.5, _w - 0.5 - inset) if not along_x else c.x, clampf(c.y, inset - 0.5, _h - 0.5 - inset) if along_x else c.y)
	var pts := PackedVector2Array()
	var hw := PackedFloat32Array()
	var kp := PackedFloat32Array()
	var steps: int = 9
	for i in steps + 1:
		var t: float = 2.0 * float(i) / float(steps) - 1.0
		var pt: Vector2 = c + dir * (t * a)
		var prof: float = b * sqrt(maxf(1.0 - t * t, 0.0)) * (1.0 + 0.1 * clampf(1.6 * _warp_x2.get_noise_2d(pt.x * 4.3, pt.y * 4.3), -1.0, 1.0))
		var room: float = _land_centre_dist(pt.x, pt.y) - CLEAR
		var edge_room: float = _edge_dist(pt.x, pt.y) - POND_EDGE_GAP
		pts.append(pt)
		hw.append(maxf(minf(minf(prof, room - amp), edge_room), 0.02))
		kp.append(0.0)
	_pond_lines[lines.size()] = POND_WARP
	_disc_ponds[lines.size()] = true
	lines.append(pts)
	halfs.append(hw)
	kappas.append(kp)


## Відстань (клітинки, ≤ 2.5) від точки до найближчого квадрата клітинки суші; поза дошкою
## клітинки продовжують крайові.
func _dt(x: float, z: float) -> float:
	var cx0: int = floori(x + 0.5)
	var cz0: int = floori(z + 0.5)
	var best: float = 2.5
	for cz in range(cz0 - 2, cz0 + 3):
		for cx in range(cx0 - 2, cx0 + 3):
			if _is_water_at(cx, cz):
				continue
			var dx: float = maxf(absf(x - cx) - 0.5, 0.0)
			var dz: float = maxf(absf(z - cz) - 0.5, 0.0)
			best = minf(best, sqrt(dx * dx + dz * dz))
	return best


## Відстань (клітинки, ≤ 2.5) від точки до центру найближчої клітинки суші.
func _land_centre_dist(x: float, z: float) -> float:
	var cx0: int = floori(x + 0.5)
	var cz0: int = floori(z + 0.5)
	var best: float = 2.5
	for cz in range(cz0 - 2, cz0 + 3):
		for cx in range(cx0 - 2, cx0 + 3):
			if not _is_water_at(cx, cz):
				best = minf(best, sqrt((x - cx) * (x - cx) + (z - cz) * (z - cz)))
	return best


## Вода в клітинці; за межею дошки річка (смуга води на краю завширшки ≤ 2) продовжується
## назовні, а ставок чи озеро на краю — ні: їх обрізає межа.
func _is_water_at(cx: int, cz: int) -> bool:
	var ix: int = clampi(cx, 0, _w - 1)
	var iz: int = clampi(cz, 0, _h - 1)
	if _wgrid[iz * _w + ix] == 0:
		return false
	var out_x: bool = ix != cx
	var out_z: bool = iz != cz
	if not (out_x or out_z):
		return true
	if out_x and out_z:
		return false
	var run: int = 1
	for sgn: int in [-1, 1]:
		var k: int = 1
		while true:
			var qx: int = ix if out_x else ix + sgn * k
			var qz: int = iz if out_z else iz + sgn * k
			if qx < 0 or qz < 0 or qx >= _w or qz >= _h or _wgrid[qz * _w + qx] == 0:
				break
			run += 1
			k += 1
	return run <= 2


static func _tangents(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n: int = pts.size()
	out.resize(n)
	for i in n:
		var d: Vector2 = pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]
		out[i] = d.normalized() if d.length_squared() > 1e-12 else Vector2.RIGHT
	return out


## Рівномірний крок дуги STEP уздовж сирої ламаної (кінці лишаються).
static func _resample(raw: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.append(raw[0])
	var acc: float = 0.0
	var next: float = STEP
	for i in range(1, raw.size()):
		var seg: float = raw[i].distance_to(raw[i - 1])
		while acc + seg >= next and seg > 0.0:
			out.append(raw[i - 1].lerp(raw[i], (next - acc) / seg))
			next += STEP
		acc += seg
	if raw.size() > 1 and out[out.size() - 1].distance_to(raw[raw.size() - 1]) > 0.5 * STEP:
		out.append(raw[raw.size() - 1])
	elif out.size() == 1:
		out.append(raw[raw.size() - 1])
	return out


## Гаус по вершинах; кінці нерухомі, за кінцем лінія продовжується непарним відбиттям
## (дотична на кінці зберігається).
static func _gauss_v(v: PackedVector2Array, sigma: float) -> PackedVector2Array:
	var n: int = v.size()
	var out: PackedVector2Array = v.duplicate()
	var r: int = ceili(2.5 * sigma / STEP)
	for i in range(1, n - 1):
		var acc := Vector2.ZERO
		var ws: float = 0.0
		for k in range(-r, r + 1):
			var j: int = i + k
			var p: Vector2
			if j < 0:
				p = 2.0 * v[0] - v[mini(-j, n - 1)]
			elif j > n - 1:
				p = 2.0 * v[n - 1] - v[maxi(2 * (n - 1) - j, 0)]
			else:
				p = v[j]
			var g: float = exp(-0.5 * pow(float(k) * STEP / sigma, 2.0))
			acc += p * g
			ws += g
		out[i] = acc / ws
	return out


static func _gauss_f(v: PackedFloat32Array, sigma: float) -> PackedFloat32Array:
	var n: int = v.size()
	var out: PackedFloat32Array = v.duplicate()
	var r: int = ceili(2.5 * sigma / STEP)
	for i in n:
		var acc: float = 0.0
		var ws: float = 0.0
		for k in range(-r, r + 1):
			var g: float = exp(-0.5 * pow(float(k) * STEP / sigma, 2.0))
			acc += v[clampi(i + k, 0, n - 1)] * g
			ws += g
		out[i] = acc / ws
	return out


# Сусіди за годинниковою від півночі: N, NE, E, SE, S, SW, W, NW.
static func _ring(nx: int) -> Array[int]:
	return [-nx, -nx + 1, 1, nx + 1, nx, nx - 1, -1, -nx - 1]


## Число переходів 0 -> 1 навколо піксела: 1 — кінець, 2 — звичайний, >= 3 — розвилка.
static func _crossings(img: PackedByteArray, k: int, ring: Array[int]) -> int:
	var c: int = 0
	for o in 8:
		if img[k + ring[o]] == 0 and img[k + ring[(o + 1) % 8]] == 1:
			c += 1
	return c


## Витончення Zhang-Suen до скелета в 1 піксель.
static func _thin(img: PackedByteArray, nx: int, ny: int) -> void:
	var ring: Array[int] = _ring(nx)
	var changed: bool = true
	while changed:
		changed = false
		for sub in 2:
			var kill := PackedInt32Array()
			for j in range(1, ny - 1):
				for i in range(1, nx - 1):
					var k: int = j * nx + i
					if img[k] == 0:
						continue
					var p2: int = img[k - nx]
					var p3: int = img[k - nx + 1]
					var p4: int = img[k + 1]
					var p5: int = img[k + nx + 1]
					var p6: int = img[k + nx]
					var p7: int = img[k + nx - 1]
					var p8: int = img[k - 1]
					var p9: int = img[k - nx - 1]
					var bsum: int = p2 + p3 + p4 + p5 + p6 + p7 + p8 + p9
					if bsum < 2 or bsum > 6 or _crossings(img, k, ring) != 1:
						continue
					if sub == 0:
						if p2 * p4 * p6 != 0 or p4 * p6 * p8 != 0:
							continue
					elif p2 * p4 * p8 != 0 or p2 * p6 * p8 != 0:
						continue
					kill.append(k)
			for k in kill:
				img[k] = 0
				changed = true


## Іде від start уздовж скелета: до розвилки, глухого кута чи вже пройденого.
static func _walk(img: PackedByteArray, seen: PackedByteArray, nx: int, start: int, ring: Array[int]) -> PackedInt32Array:
	var path := PackedInt32Array([start])
	seen[start] = 1
	var cur: int = start
	# Спершу ортогональні сусіди (індекси 0, 2, 4, 6), потім діагональні.
	var order: Array[int] = [0, 2, 4, 6, 1, 3, 5, 7]
	while true:
		var nxt: int = -1
		for o in order:
			var q: int = cur + ring[o]
			if img[q] == 1 and seen[q] == 0:
				nxt = q
				break
		if nxt < 0:
			break
		path.append(nxt)
		seen[nxt] = 1
		cur = nxt
		if _crossings(img, nxt, ring) >= 3:
			break
	return path


## Відрізає гілки коротші за min_len пікселів, що ростуть із розвилки.
static func _prune(img: PackedByteArray, nx: int, ny: int, min_len: int) -> void:
	var ring: Array[int] = _ring(nx)
	for j in range(1, ny - 1):
		for i in range(1, nx - 1):
			var k: int = j * nx + i
			if img[k] == 0 or _crossings(img, k, ring) != 1:
				continue
			var seen := PackedByteArray()
			seen.resize(img.size())
			var path: PackedInt32Array = _walk(img, seen, nx, k, ring)
			var end: int = path[path.size() - 1]
			if path.size() < min_len and _crossings(img, end, ring) >= 3:
				for pi in path.size() - 1:
					img[path[pi]] = 0


## Розбиває скелет на шляхи: від кінців, далі від розвилок, далі що лишилось (петлі).
static func _trace(img: PackedByteArray, nx: int, ny: int) -> Array[PackedInt32Array]:
	var ring: Array[int] = _ring(nx)
	var seen := PackedByteArray()
	seen.resize(img.size())
	var out: Array[PackedInt32Array] = []
	var ends: Array[int] = []
	var rest: Array[int] = []
	for j in range(1, ny - 1):
		for i in range(1, nx - 1):
			var k: int = j * nx + i
			if img[k] == 0:
				continue
			if _crossings(img, k, ring) == 1:
				ends.append(k)
			else:
				rest.append(k)
	for k in ends + rest:
		if seen[k] == 0:
			out.append(_walk(img, seen, nx, k, ring))
	return out
