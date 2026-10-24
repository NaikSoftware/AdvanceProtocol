class_name RoadCourse
extends RefCounted
## Дорога як власна геометрія: сітку читають лише правила й пошук шляху. Осьова лінія —
## скелет маски клітинок ROAD і мостів (Zhang–Suen, як у RiverCourse), розбитий на граф: вузли —
## розвилки й кінці, ребра — шляхи між ними. На розвилці пара найбільш
## протилежних гілок зливається в один ланцюжок, тож прямий проїзд крізь Т-подібну розвилку
## лишається прямим. Лінія згладжується гаусом (сходинки сітки — одна крива, кути — дуги R ≥ 6 м),
## дістає бокове зміщення шумом ±0.6 м з довжиною хвилі ~30 м, а тоді зміщується до кожної
## клітинки ROAD, від центру якої відійшла далі за CELL_REACH.
## Ширина — за типом покриття й товщиною смуги клітинок: смуга у 2 клітинки — вулиця 7 м,
## у 3+ — площа. Внутрішні кути розвилок — морфологічне замикання радіусом CLOSE_M (дуга, а не 90°).
##
## Лише вигляд: правила, шляхи й туман читають клітинки, а не цей клас.

## Пікселів скелета на клітинку (непарне: смуга в 1 клітинку має центральний піксель).
const U: int = 3
## Пікселів растра на клітинку: 1 піксель = 1 м.
const PX: int = 8
const STEP: float = 0.2
const M: float = 0.125
## Півширина однієї смуги, м (індекс — тип): ширина асфальту 4.6, ґрунтівки 2.7, бруківки 4.4.
## Асфальт не 5.0: шум ширини понад 2.5 м обрізає верхня межа SINGLE_MAX_HALF_M.
const HALF_M: Array[float] = [2.3, 1.35, 2.2]
## Вулиця в смузі 2 клітинки: 7 м.
const STREET_HALF_M: float = 3.5
## Верхня межа півширини однієї смуги (ширина 5 м): на дугах капсули додають ~0.2 м, тож
## ширина ≤ 0.65 клітинки = 5.2 м.
const SINGLE_MAX_HALF_M: float = 2.5
const STREET_DT: float = 0.7
const STREET_RUN: float = 1.5
## Смуга ≥ 3 клітинок (dt у центрі 1.5): площа на всю смугу, а не вулиця 7 м посередині.
const WIDE_DT: float = 1.25
const WIDTH_VAR: float = 0.1
const WIDTH_FINE: float = 0.03
## Бокове зміщення осі ±0.6 м з довжиною хвилі ~30 м (частота шуму 0.27 на клітинку):
## ±1.2 м дає вигини R ≈ 20–40 м кожні 10–15 м, тобто S-вигини на прямих.
const WANDER_M: float = 0.6
## σ згладжування осі (клітинки): кут 90° — дуга R ≈ 0.89σ ≈ 7.8 м, сходинки 1–3 клітинки —
## одна крива.
const SMOOTH: float = 1.1
const STREET_SMOOTH: float = 0.75
## Вісь — не далі за стільки клітинок від центру кожної клітинки ROAD; σ гаусового зміщення, що
## виправляє вісь (клітинки): 1.2 дає на сходинці в 1 клітинку два протилежні зміщення за 7 м
## (S-вигин), 1.6 — одну плавну дугу.
const CELL_REACH: float = 0.55
const REPAIR_SIGMA: float = 1.6
## σ поля зсуву, що повертає відліки настилу й розвилки на скелет (клітинки).
const ANCHOR_SIGMA: float = 0.7
## Півдовжина відрізка осі на окремій клітинці дороги (клітинки).
const STUB: float = 0.35
const CLOSE_M: float = 7.0
const BEND_CLOSE_M: float = 2.0
## Радіус заокруглення опуклих кутів площі, м.
const PLAZA_R: float = 4.0
## Вага замикання — 1 до NODE_INNER клітинки від розвилки й спадає до 0 на NODE_REACH.
const NODE_INNER: float = 0.7
const NODE_REACH: float = 1.6
## Поле відстані пишеться на стільки метрів за край; далі — FAR_M.
const REACH_M: float = 4.0
const FAR_M: float = 16.0
## Період u у текстурі: B = (u mod U_WRAP) / 16, A = floor(u / U_WRAP).
const U_WRAP: float = 64.0

var lines: Array[PackedVector2Array] = []
## Півширина на вершині, м (з шумом) і без шуму (за типом і товщиною).
var halfs: Array[PackedFloat32Array] = []
var base_halfs: Array[PackedFloat32Array] = []
## Ваги типів на вершині: асфальт, ґрунтівка, бруківка.
var types: Array[PackedVector3Array] = []
## Розвилки (вузли зі ступенем ≥ 3), світові клітинки.
var nodes: PackedVector2Array = PackedVector2Array()

var _w: int = 0
var _h: int = 0
var _margin: int = 0
var _shift: int = 0
var _mask: PackedByteArray = PackedByteArray()
var _type: PackedByteArray = PackedByteArray()
var _bridge_cells: Array[Vector2i] = []
var _images: Array[Image] = []
var _d: PackedFloat32Array = PackedFloat32Array()
## Розвилки, крізь які ланцюжок повертає. Їх не фіксують на скелеті: фіксація вузла лишає
## на повороті гострий кут.
var _bend_nodes: PackedVector2Array = PackedVector2Array()


## surface — MapData.surface (підтип ROAD: 0 асфальт, 1 ґрунтівка, 2 бруківка).
## Повертає null, якщо дороги нема.
## shift — ширина кільця, коли board — світ разом із кільцем (TerrainHeight.bake з ring): шум
## майданів береться в координатах дошки. Хвилястість і ширина доріг ідуть за довжиною й номером
## ланцюжка, тож дорога, що продовжилась у кільце, на дошці хитається трохи інакше.
static func build(board: Board, surface: PackedByteArray, margin: int, seed_value: int, shift: int = 0) -> RoadCourse:
	var rc := RoadCourse.new()
	rc._w = board.width
	rc._h = board.height
	rc._margin = margin
	rc._shift = shift
	rc._mask.resize(rc._w * rc._h)
	rc._type.resize(rc._w * rc._h)
	var any := false
	for y in rc._h:
		for x in rc._w:
			var i: int = y * rc._w + x
			var k: int = board.kind_at(Vector2i(x, y))
			if k == Terrain.Kind.ROAD:
				rc._mask[i] = 1
				rc._type[i] = clampi(surface[i] if i < surface.size() else 0, 0, 2)
				any = true
			elif k == Terrain.Kind.BRIDGE or k == Terrain.Kind.BRIDGE_DESTROYED:
				rc._mask[i] = 2
				rc._bridge_cells.append(Vector2i(x, y))
	if not any:
		return null
	rc._fill_bridge_types()
	rc._build_lines(seed_value)
	return rc


## Тип під мостом — від найближчої клітинки дороги (настил продовжує дорогу).
func _fill_bridge_types() -> void:
	for c in _bridge_cells:
		var best := 1e9
		for y in _h:
			for x in _w:
				if _mask[y * _w + x] == 1:
					var dd: float = Vector2(c).distance_squared_to(Vector2(x, y))
					if dd < best:
						best = dd
						_type[c.y * _w + c.x] = _type[y * _w + x]


func _build_lines(seed_value: int) -> void:
	var pad: int = _margin + 2
	var ox: float = -0.5 - pad
	var oz: float = -0.5 - pad
	var nx: int = (_w + 2 * pad) * U + 2
	var ny: int = (_h + 2 * pad) * U + 2
	var img := PackedByteArray()
	img.resize(nx * ny)
	for j in range(1, ny - 1):
		for i in range(1, nx - 1):
			img[j * nx + i] = 1 if _is_road_at(floori(ox + (float(i) - 0.5) / U + 0.5), floori(oz + (float(j) - 0.5) / U + 0.5)) else 0
	RiverCourse._thin(img, nx, ny)
	RiverCourse._prune(img, nx, ny, 2 * U)
	var g: Array = _graph(img, nx, ny)
	var node_px: PackedVector2Array = g[0]
	var edges: Array[PackedInt32Array] = g[1]
	var ends: PackedInt32Array = g[2]
	var rings: Array[PackedInt32Array] = g[3]
	var to_world := func(px: Vector2) -> Vector2: return Vector2(ox + (px.x - 0.5) / U, oz + (px.y - 0.5) / U)
	var node_pos := PackedVector2Array()
	for p in node_px:
		node_pos.append(to_world.call(p))
	var epts: Array[PackedVector2Array] = []
	for ei in edges.size():
		var path: PackedInt32Array = edges[ei]
		var pts := PackedVector2Array()
		for k in path:
			pts.append(to_world.call(Vector2(k % nx, k / nx)))
		pts[0] = node_pos[ends[2 * ei]]
		if ends[2 * ei + 1] >= 0:
			pts[pts.size() - 1] = node_pos[ends[2 * ei + 1]]
		epts.append(pts)
	var chains: Array[PackedVector2Array] = _chains(epts, ends, node_pos)
	var closed: Array[bool] = []
	closed.resize(chains.size())
	# Кільце без розвилки — замкнений ланцюжок (перша точка повторена в кінці).
	for path in rings:
		var pts := PackedVector2Array()
		for k in path:
			pts.append(to_world.call(Vector2(k % nx, k / nx)))
		pts.append(pts[0])
		chains.append(pts)
		closed.append(true)
	# Окрема клітинка (вузол без ребер) — відрізок осі завдовжки 2·STUB; кут залежить від
	# зерна шуму й координат.
	var degree := PackedInt32Array()
	degree.resize(node_pos.size())
	for e in ends:
		if e >= 0:
			degree[e] += 1
	for ni in node_pos.size():
		if degree[ni] == 0:
			var c: Vector2 = node_pos[ni]
			var dir := Vector2.from_angle(fposmod(float(seed_value % 1000) * 0.37 + c.x * 1.7 + c.y * 2.3, PI))
			chains.append(PackedVector2Array([c - dir * STUB, c + dir * STUB]))
			closed.append(false)
	var n_l := _noise(seed_value + 1221, 0.27)
	for ci in chains.size():
		lines.append(_smooth_chain(chains[ci], ci, n_l, closed[ci]))
	var n_w := _noise(seed_value + 1201, 0.7)
	var n_w2 := _noise(seed_value + 1211, 1.2)
	# Ширина рахується двічі: _repair() бере допуск із ширини (вулиця покриває кутову клітинку з
	# відстані 0.69, одна смуга — лише з CELL_REACH), а після виправлення вісь зміщена.
	for pass_i in 2:
		halfs.clear()
		base_halfs.clear()
		types.clear()
		for li in lines.size():
			_widths(li, n_w, n_w2)
		if pass_i == 0:
			_repair()


## Граф скелета: вузли (кластери розвилок і кінці; координати в пікселях), ребра (шляхи пікселів
## від вузла до вузла), номери вузлів на кінцях ребер (2 на ребро; -1 — кінець без вузла) і кільця
## без жодної розвилки (шляхи пікселів, що замикаються самі на себе).
static func _graph(img: PackedByteArray, nx: int, ny: int) -> Array:
	var ring: Array[int] = RiverCourse._ring(nx)
	var node_id := PackedInt32Array()
	node_id.resize(nx * ny)
	node_id.fill(-1)
	var is_node := PackedByteArray()
	is_node.resize(nx * ny)
	for j in range(1, ny - 1):
		for i in range(1, nx - 1):
			var k: int = j * nx + i
			if img[k] == 1 and RiverCourse._crossings(img, k, ring) != 2:
				is_node[k] = 1
	var node_px := PackedVector2Array()
	for k in nx * ny:
		if is_node[k] == 0 or node_id[k] >= 0:
			continue
		var id: int = node_px.size()
		var stack: Array[int] = [k]
		node_id[k] = id
		var acc := Vector2.ZERO
		var cnt := 0
		while not stack.is_empty():
			var q: int = stack.pop_back()
			acc += Vector2(q % nx, q / nx)
			cnt += 1
			for o in 8:
				var r: int = q + ring[o]
				if is_node[r] == 1 and node_id[r] < 0:
					node_id[r] = id
					stack.append(r)
		node_px.append(acc / cnt)
	var order: Array[int] = [0, 2, 4, 6, 1, 3, 5, 7]
	var seen := PackedByteArray()
	seen.resize(nx * ny)
	var edges: Array[PackedInt32Array] = []
	var ends := PackedInt32Array()
	for k in nx * ny:
		if is_node[k] == 0:
			continue
		var start_id: int = node_id[k]
		for o in order:
			var q: int = k + ring[o]
			if img[q] == 0:
				continue
			if is_node[q] == 1:
				if node_id[q] > start_id:
					edges.append(PackedInt32Array([k, q]))
					ends.append(start_id)
					ends.append(node_id[q])
				continue
			if seen[q] == 1:
				continue
			var path := PackedInt32Array([k, q])
			seen[q] = 1
			var prev: int = k
			var cur: int = q
			var end_id := -1
			while true:
				var nxt := -1
				for o2 in order:
					var r: int = cur + ring[o2]
					if r == prev or img[r] == 0 or is_node[r] == 0:
						continue
					# Свій кластер на перших кроках — не кінець ребра, а сусідній піксель розвилки.
					if node_id[r] == start_id and path.size() < 5:
						continue
					nxt = r
					break
				if nxt >= 0:
					path.append(nxt)
					end_id = node_id[nxt]
					break
				for o2 in order:
					var r: int = cur + ring[o2]
					if img[r] == 1 and is_node[r] == 0 and seen[r] == 0:
						nxt = r
						break
				if nxt < 0:
					break
				path.append(nxt)
				seen[nxt] = 1
				prev = cur
				cur = nxt
			edges.append(path)
			ends.append(start_id)
			ends.append(end_id)
	# Пікселі скелета, не пройдені від жодного вузла, — кільця.
	var rings: Array[PackedInt32Array] = []
	for k in nx * ny:
		if img[k] == 0 or is_node[k] == 1 or seen[k] == 1:
			continue
		var path := PackedInt32Array([k])
		seen[k] = 1
		var cur: int = k
		while true:
			var nxt := -1
			for o in order:
				var r: int = cur + ring[o]
				if img[r] == 1 and seen[r] == 0:
					nxt = r
					break
			if nxt < 0:
				break
			path.append(nxt)
			seen[nxt] = 1
			cur = nxt
		if path.size() >= 3:
			rings.append(path)
	return [node_px, edges, ends, rings]


## Ланцюжки: на кожному вузлі пара найбільш протилежних гілок (кут між ними > ~135°)
## зливається, а на вузлі зі ступенем 2 — завжди. Розвилки (ступінь ≥ 3) — у nodes.
func _chains(epts: Array[PackedVector2Array], ends: PackedInt32Array, node_pos: PackedVector2Array) -> Array[PackedVector2Array]:
	var at_node: Dictionary = {}
	for ei in epts.size():
		for side in 2:
			var nid: int = ends[2 * ei + side]
			if nid < 0:
				continue
			if not at_node.has(nid):
				at_node[nid] = []
			(at_node[nid] as Array).append(2 * ei + side)
	var links: Dictionary = {}
	for nid: int in at_node:
		var list: Array = at_node[nid]
		if list.size() >= 3:
			nodes.append(node_pos[nid])
		var dirs: Dictionary = {}
		var typ: Dictionary = {}
		for key: int in list:
			dirs[key] = _end_dir(epts[key / 2], key % 2)
			typ[key] = _type_near(node_pos[nid] + dirs[key])
		var free: Array = list.duplicate()
		# Дві гілки одного покриття утворюють поворот (кут 84–134°), решта — інше покриття (асфальт
		# пн→сх, ґрунтівка на зх): поворот стає одним ланцюжком і згладжується в дугу. Пара найбільш
		# протилежних гілок (ґрунтівка + асфальт) дає асфальту прямий кут і поперечну межу типів.
		if free.size() > 2:
			var bd := 0.1
			var ba := -1
			var bb := -1
			for a in free.size():
				for b in range(a + 1, free.size()):
					var dt: float = (dirs[free[a]] as Vector2).dot(dirs[free[b]])
					if typ[free[a]] != typ[free[b]] or dt >= bd:
						continue
					var alone := true
					for c: int in free:
						if c != free[a] and c != free[b] and typ[c] == typ[free[a]]:
							alone = false
					if alone:
						bd = dt
						ba = free[a]
						bb = free[b]
			if ba >= 0 and bd > -0.7:
				links[ba] = bb
				links[bb] = ba
				free.erase(ba)
				free.erase(bb)
				_bend_nodes.append(node_pos[nid])
		while free.size() >= 2:
			var best := 1e9
			var pa := -1
			var pb := -1
			for a in free.size():
				for b in range(a + 1, free.size()):
					var dt: float = (dirs[free[a]] as Vector2).dot(dirs[free[b]])
					if dt < best:
						best = dt
						pa = free[a]
						pb = free[b]
			if free.size() > 2 and best > -0.7:
				break
			links[pa] = pb
			links[pb] = pa
			free.erase(pa)
			free.erase(pb)
	var out: Array[PackedVector2Array] = []
	var used := PackedByteArray()
	used.resize(epts.size())
	for e0 in epts.size():
		if used[e0] == 1:
			continue
		# Назад до початку ланцюжка: вхідний кінець ребра, через який немає зв'язку.
		var e: int = e0
		var entry: int = 0
		for _guard in epts.size():
			var key: int = 2 * e + entry
			if not links.has(key):
				break
			var other: int = links[key]
			if other / 2 == e0:
				break
			e = other / 2
			entry = 1 - other % 2
		var pts := PackedVector2Array()
		for _guard in epts.size() + 1:
			if used[e] == 1:
				break
			used[e] = 1
			var seg: PackedVector2Array = epts[e]
			if entry == 1:
				seg = _reversed(seg)
			if pts.is_empty():
				pts.append_array(seg)
			else:
				pts.append_array(seg.slice(1))
			var key: int = 2 * e + (1 - entry)
			if not links.has(key):
				break
			var other: int = links[key]
			e = other / 2
			entry = other % 2
		if pts.size() >= 2:
			out.append(pts)
	return out


## Напрям гілки від вузла: до точки ребра ~1 клітинку від кінця.
static func _end_dir(pts: PackedVector2Array, side: int) -> Vector2:
	var p: PackedVector2Array = pts if side == 0 else _reversed(pts)
	var acc: float = 0.0
	for i in range(1, p.size()):
		acc += p[i].distance_to(p[i - 1])
		if acc >= 1.0 or i == p.size() - 1:
			return (p[i] - p[0]).normalized()
	return Vector2.RIGHT


static func _reversed(p: PackedVector2Array) -> PackedVector2Array:
	var r := PackedVector2Array()
	for i in range(p.size() - 1, -1, -1):
		r.append(p[i])
	return r


## Вісь ланцюжка: скелет, згладжений гаусом σ = SMOOTH уздовж довжини (сходинки клітинок зливаються
## в одну криву, кут 90° — дуга R ≈ 0.89σ); у смузі 2+ клітинки σ = STREET_SMOOTH, щоб вулиця йшла
## медіальною віссю. Кінці нерухомі (непарне відбиття). Відліки на настилі мосту й біля розвилки
## повертаються на скелет гладким полем зсуву (гаус σ = ANCHOR_SIGMA): жорстка фіксація дає злам
## на краю настилу, а вага якорів у самому згладжуванні зменшує радіус сусідніх кутів. Далі —
## бокове зміщення ±WANDER_M на прямих (на дугах воно гасне, бо зменшує радіус).
func _smooth_chain(raw: PackedVector2Array, ci: int, n_l: FastNoiseLite, closed: bool) -> PackedVector2Array:
	var pts: PackedVector2Array = _resample(raw, STEP)
	var n: int = pts.size()
	var m: int = n - 1 if closed else n
	var r: int = ceili(2.5 * SMOOTH / STEP)
	var sig := PackedFloat32Array()
	sig.resize(n)
	# Вужче σ — лише на вулиці (смуга 2 клітинки завдовжки ≥ STREET_RUN): з ним вісь крізь блок
	# 2×2 на повороті повторює сходинку клітинок і дістає вигини кожні 10–15 м.
	var street: PackedByteArray = _street_flags(pts)
	for i in n:
		sig[i] = lerpf(SMOOTH, STREET_SMOOTH, smoothstep(0.7, 0.95, _dt(pts[i])) * street[i])
	# Різка зміна σ уздовж лінії сама дає злам: профіль σ теж гладкий.
	sig = _gauss_f(sig, 0.8)
	var out: PackedVector2Array = pts.duplicate()
	for i in m:
		var acc := Vector2.ZERO
		var ws: float = 0.0
		for k in range(-r, r + 1):
			var j: int = i + k
			var q: Vector2
			if closed:
				q = pts[posmod(j, m)]
			elif j < 0:
				q = 2.0 * pts[0] - pts[mini(-j, n - 1)]
			elif j >= n:
				q = 2.0 * pts[n - 1] - pts[maxi(2 * (n - 1) - j, 0)]
			else:
				q = pts[j]
			var g: float = exp(-0.5 * pow(float(k) * STEP / sig[i], 2.0))
			acc += q * g
			ws += g
		out[i] = acc / ws
	if closed:
		out[n - 1] = out[0]
	# Поле зсуву до якорів: на якорі ≈ повний зсув (сума ваг ≫ 1), далі гасне до нуля.
	var anchor := PackedByteArray()
	anchor.resize(n)
	for i in n:
		anchor[i] = 1 if near_bridge(pts[i]) <= 0.0 or _near_fixed_node(pts[i]) < 0.3 else 0
	var ra: int = ceili(2.5 * ANCHOR_SIGMA / STEP)
	var fixed: PackedVector2Array = out.duplicate()
	for i in m:
		var acc := Vector2.ZERO
		var ws: float = 0.0
		for k in range(-ra, ra + 1):
			var j: int = posmod(i + k, m) if closed else i + k
			if j < 0 or j >= n or anchor[j] == 0:
				continue
			var g: float = exp(-0.5 * pow(float(k) * STEP / ANCHOR_SIGMA, 2.0))
			acc += (pts[j] - out[j]) * g
			ws += g
		fixed[i] = out[i] + acc / maxf(ws, 1.0)
	out = fixed
	if closed:
		out[n - 1] = out[0]
	var s := PackedFloat32Array()
	s.resize(n)
	for i in range(1, n):
		s[i] = s[i - 1] + out[i].distance_to(out[i - 1])
	var tang: PackedVector2Array = RiverCourse._tangents(out)
	var moved: PackedVector2Array = out.duplicate()
	for i in n:
		var ia: int = maxi(i - 1, 0)
		var ib: int = mini(i + 1, n - 1)
		var kappa: float = tang[ib].distance_to(tang[ia]) / maxf(s[ib] - s[ia], 1e-4)
		var fade: float = (1.0 if closed else smoothstep(0.6, 2.0, minf(s[i], s[n - 1] - s[i]))) * smoothstep(0.6, 2.0, near_node(out[i])) * smoothstep(0.6, 2.0, near_bridge(out[i])) * (1.0 - smoothstep(0.15, 0.5, kappa))
		var off: float = WANDER_M * M * clampf(1.6 * n_l.get_noise_2d(s[i], 37.0 * ci), -1.0, 1.0) * fade
		moved[i] = out[i] + Vector2(-tang[i].y, tang[i].x) * off
	if closed:
		moved[n - 1] = moved[0]
	return moved


## 1 — точку можна рухати, 0 — вона зафіксована на скелеті (розвилка чи міст поруч).
func _pin(p: Vector2) -> float:
	return smoothstep(0.3, 1.3, _near_fixed_node(p)) * smoothstep(0.2, 1.2, near_bridge(p))


## Правило читаності: кожна клітинка ROAD — під дорогою. Вісь має пройти не далі CELL_REACH від
## центру клітинки (або, на широкій смузі, покрити ≥ 25 % клітинки). Де згладжування відвело вісь
## далі, її зсуває до клітинки гаусове зміщення σ = REPAIR_SIGMA, без зламу.
func _repair() -> void:
	var cells: Array[Vector2] = []
	for y in _h:
		for x in _w:
			if _mask[y * _w + x] == 1:
				cells.append(Vector2(x, y))
	var reach: int = ceili(2.5 * REPAIR_SIGMA / STEP)
	for _it in 10:
		var bad := 0
		for c in cells:
			var best := 1e9
			var bl := -1
			var bk := -1
			for li in lines.size():
				var pts: PackedVector2Array = lines[li]
				for k in pts.size():
					var dd: float = c.distance_squared_to(pts[k])
					if dd < best:
						best = dd
						bl = li
						bk = k
			var d: float = sqrt(best)
			var q: PackedVector2Array = lines[bl]
			var lim: float = maxf(CELL_REACH, base_halfs[bl][bk] * M + 0.25)
			if d <= lim:
				continue
			bad += 1
			var delta: Vector2 = (c - q[bk]) * ((d - lim + 0.08) / d)
			var ring: bool = q.size() > 2 and q[0].distance_squared_to(q[q.size() - 1]) < 1e-10
			for j in range(maxi(bk - reach, 0), mini(bk + reach + 1, q.size())):
				q[j] += delta * exp(-0.5 * pow(float(j - bk) * STEP / REPAIR_SIGMA, 2.0)) * _pin(q[j])
			if ring:
				q[q.size() - 1] = q[0]
			lines[bl] = q
		if bad == 0:
			break


## Півширина площі (м) у смузі ≥ 3 клітинок: крайні клітинки теж під покриттям; 0 — смуга вужча.
func _wide_half_m(p: Vector2) -> float:
	var dt: float = _dt(p)
	return (dt - 0.25) / M if dt >= WIDE_DT else 0.0


## Тип, клас (одна смуга / вулиця / площа) і півширина на кожній вершині лінії li.
func _widths(li: int, n_w: FastNoiseLite, n_w2: FastNoiseLite) -> void:
	var pts: PackedVector2Array = lines[li]
	var n: int = pts.size()
	var s := PackedFloat32Array()
	s.resize(n)
	for i in range(1, n):
		s[i] = s[i - 1] + pts[i].distance_to(pts[i - 1])
	var tw := PackedVector3Array()
	for i in n:
		var t: int = _type_near(pts[i])
		# Біля повороту клітинка вузла — асфальт повороту; бічна дорога бере тип клітинки за крок від
		# вузла у своєму напрямку, інакше її перші 0.75 клітинки мають тип повороту (асфальт).
		for q in _bend_nodes:
			if pts[i].distance_to(q) < 0.75 and pts[i].distance_to(q) > 1e-4:
				t = _type_near(q + (pts[i] - q).normalized())
		tw.append(Vector3(1.0 if t == 0 else 0.0, 1.0 if t == 1 else 0.0, 1.0 if t == 2 else 0.0))
	var street: PackedByteArray = _street_flags(pts)
	var base := PackedFloat32Array()
	for i in n:
		var single: float = tw[i].x * HALF_M[0] + tw[i].y * HALF_M[1] + tw[i].z * HALF_M[2]
		base.append(maxf(STREET_HALF_M, _wide_half_m(pts[i])) if street[i] == 1 else single)
	base = _gauss_f(base, 0.35)
	tw = _gauss_v3(tw, 0.3)
	var hw := PackedFloat32Array()
	for i in n:
		# Шум підсилено ×2.5 з обрізанням до ±1: симплекс рідко сягає ±1, і CV ширини < 3 %.
		var f: float = 1.0 + WIDTH_VAR * clampf(2.5 * n_w.get_noise_2d(s[i], 11.0 * li + 5.3), -1.0, 1.0) + WIDTH_FINE * clampf(2.5 * n_w2.get_noise_2d(s[i], 11.0 * li + 5.3), -1.0, 1.0)
		# Верхня межа росте разом із базовою півшириною на переході до вулиці: ширина без сходинки.
		hw.append(minf(base[i] * f, SINGLE_MAX_HALF_M + maxf(base[i] - HALF_M[0], 0.0) * 1.5))
	halfs.append(hw)
	base_halfs.append(base)
	types.append(tw)


## Вулиця — лише смуга dt ≥ STREET_DT (2+ клітинки завширшки) завдовжки ≥ STREET_RUN, не на мосту.
func _street_flags(pts: PackedVector2Array) -> PackedByteArray:
	var n: int = pts.size()
	var street := PackedByteArray()
	street.resize(n)
	for i in n:
		street[i] = 1 if _dt(pts[i]) >= STREET_DT and near_bridge(pts[i]) > 0.0 else 0
	var i0 := 0
	while i0 < n:
		if street[i0] == 0:
			i0 += 1
			continue
		var i1: int = i0
		var run: float = 0.0
		while i1 + 1 < n and street[i1 + 1] == 1:
			run += pts[i1 + 1].distance_to(pts[i1])
			i1 += 1
		if run < STREET_RUN:
			for i in range(i0, i1 + 1):
				street[i] = 0
		i0 = i1 + 1
	return street


static func _resample(raw: PackedVector2Array, step: float) -> PackedVector2Array:
	var total: float = 0.0
	for i in range(1, raw.size()):
		total += raw[i].distance_to(raw[i - 1])
	var segs: int = maxi(1, roundi(total / step))
	var st: float = total / segs
	var out := PackedVector2Array([raw[0]])
	var acc: float = 0.0
	var next: float = st
	for i in range(1, raw.size()):
		var seg: float = raw[i].distance_to(raw[i - 1])
		while acc + seg >= next - 1e-6 and seg > 0.0 and out.size() < segs:
			out.append(raw[i - 1].lerp(raw[i], clampf((next - acc) / seg, 0.0, 1.0)))
			next += st
		acc += seg
	out.append(raw[raw.size() - 1])
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


static func _gauss_v3(v: PackedVector3Array, sigma: float) -> PackedVector3Array:
	var n: int = v.size()
	var out: PackedVector3Array = v.duplicate()
	var r: int = ceili(2.5 * sigma / STEP)
	for i in n:
		var acc := Vector3.ZERO
		var ws: float = 0.0
		for k in range(-r, r + 1):
			var g: float = exp(-0.5 * pow(float(k) * STEP / sigma, 2.0))
			acc += v[clampi(i + k, 0, n - 1)] * g
			ws += g
		out[i] = acc / ws
	return out


static func _noise(seed_value: int, freq: float) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = seed_value
	n.frequency = freq
	return n


## Дорога (або міст) у клітинці; за межею дошки смуга не ширша за 3 продовжується назовні (ширша —
## дорога вздовж краю, і назовні вона не продовжується).
func _is_road_at(cx: int, cz: int) -> bool:
	var ix: int = clampi(cx, 0, _w - 1)
	var iz: int = clampi(cz, 0, _h - 1)
	if _mask[iz * _w + ix] == 0:
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
			if qx < 0 or qz < 0 or qx >= _w or qz >= _h or _mask[qz * _w + qx] == 0:
				break
			run += 1
			k += 1
	return run <= 3


## Відстань (клітинки, ≤ 2.5) від точки до квадрата найближчої клітинки без дороги.
func _dt(p: Vector2) -> float:
	var cx0: int = floori(p.x + 0.5)
	var cz0: int = floori(p.y + 0.5)
	var best: float = 2.5
	for cz in range(cz0 - 2, cz0 + 3):
		for cx in range(cx0 - 2, cx0 + 3):
			if _is_road_at(cx, cz):
				continue
			var dx: float = maxf(absf(p.x - cx) - 0.5, 0.0)
			var dz: float = maxf(absf(p.y - cz) - 0.5, 0.0)
			best = minf(best, sqrt(dx * dx + dz * dz))
	return best


## Тип найближчої клітинки дороги (0 асфальт, 1 ґрунтівка, 2 бруківка).
func _type_near(p: Vector2) -> int:
	var cx0: int = clampi(floori(p.x + 0.5), 0, _w - 1)
	var cz0: int = clampi(floori(p.y + 0.5), 0, _h - 1)
	var best := 1e9
	var t := 0
	for cz in range(maxi(cz0 - 2, 0), mini(cz0 + 3, _h)):
		for cx in range(maxi(cx0 - 2, 0), mini(cx0 + 3, _w)):
			if _mask[cz * _w + cx] == 0:
				continue
			var dd: float = p.distance_squared_to(Vector2(cx, cz))
			if dd < best:
				best = dd
				t = _type[cz * _w + cx]
	return t


## Відстань до найближчої розвилки (клітинки).
func near_node(p: Vector2) -> float:
	var best := 1e9
	for q in nodes:
		best = minf(best, p.distance_to(q))
	return best


## Відстань до найближчої розвилки, що не є поворотом (клітинки).
func _near_fixed_node(p: Vector2) -> float:
	var best := 1e9
	for q in nodes:
		if not _bend_nodes.has(q):
			best = minf(best, p.distance_to(q))
	return best


## Відстань до квадрата найближчої клітинки мосту (0 — над мостом).
func near_bridge(p: Vector2) -> float:
	var best := 1e9
	for c in _bridge_cells:
		var dx: float = maxf(absf(p.x - c.x) - 0.5, 0.0)
		var dz: float = maxf(absf(p.y - c.y) - 0.5, 0.0)
		best = minf(best, sqrt(dx * dx + dz * dz))
	return best


## [поле RGBAH: R — знакова відстань до краю d (м, мінус на дорозі), G — бокове v (м),
## B — (u mod 64) / 16, A — floor(u / 64) (u — уздовж осі, м); типи RGBA8: асфальт, ґрунтівка,
## бруківка, A — близькість розвилки]. Піксель (i, j) — центр у світі
## (-0.5 - margin + (i + 0.5) / PX, ...). Рахується раз і кешується.
func rasterise() -> Array[Image]:
	if not _images.is_empty():
		return _images
	var rw: int = (_w + 2 * _margin) * PX
	var rh: int = (_h + 2 * _margin) * PX
	var org: float = -0.5 - _margin
	var n: int = rw * rh
	var d := PackedFloat32Array()
	d.resize(n)
	d.fill(FAR_M)
	var v := PackedFloat32Array()
	v.resize(n)
	var u := PackedFloat32Array()
	u.resize(n)
	var tw := PackedVector3Array()
	tw.resize(n)
	var jw := PackedFloat32Array()
	jw.resize(n)
	var inv: float = 1.0 / PX
	for li in lines.size():
		var pts: PackedVector2Array = lines[li]
		var hw: PackedFloat32Array = halfs[li]
		var ty: PackedVector3Array = types[li]
		var s0: float = 0.0
		for si in pts.size() - 1:
			var a: Vector2 = pts[si]
			var b: Vector2 = pts[si + 1]
			var ab: Vector2 = b - a
			var len2: float = maxf(ab.length_squared(), 1e-12)
			var seg_len: float = sqrt(len2)
			var abn: Vector2 = ab / seg_len
			var big: bool = near_node(a) < NODE_REACH + 0.6
			var r: float = (maxf(hw[si], hw[si + 1]) + (CLOSE_M + 1.0 if big else REACH_M)) * M
			var i0: int = maxi(floori((minf(a.x, b.x) - r - org) * PX), 0)
			var i1: int = mini(ceili((maxf(a.x, b.x) + r - org) * PX), rw - 1)
			var j0: int = maxi(floori((minf(a.y, b.y) - r - org) * PX), 0)
			var j1: int = mini(ceili((maxf(a.y, b.y) + r - org) * PX), rh - 1)
			for j in range(j0, j1 + 1):
				var pz: float = org + (j + 0.5) * inv
				for i in range(i0, i1 + 1):
					var px: float = org + (i + 0.5) * inv
					var t: float = clampf(((px - a.x) * ab.x + (pz - a.y) * ab.y) / len2, 0.0, 1.0)
					var qx: float = px - (a.x + ab.x * t)
					var qz: float = pz - (a.y + ab.y * t)
					var dd: float = sqrt(qx * qx + qz * qz) * 8.0 - lerpf(hw[si], hw[si + 1], t)
					var k: int = j * rw + i
					if dd < d[k]:
						d[k] = dd
						v[k] = (abn.x * qz - abn.y * qx) * 8.0
						u[k] = (s0 + t * seg_len) * 8.0
						tw[k] = ty[si].lerp(ty[si + 1], t)
			s0 += seg_len
	_close_junctions(d, jw, rw, rh, org)
	_plazas(d, tw, jw, rw, rh, org)
	var fimg := Image.create_empty(rw, rh, false, Image.FORMAT_RGBAH)
	var timg := Image.create_empty(rw, rh, false, Image.FORMAT_RGBA8)
	for j in rh:
		for i in rw:
			var k: int = j * rw + i
			var uu: float = u[k]
			var wrap: float = floorf(uu / U_WRAP)
			fimg.set_pixel(i, j, Color(d[k], v[k], (uu - wrap * U_WRAP) / 16.0, wrap))
			var c: Vector3 = tw[k]
			var sum: float = maxf(c.x + c.y + c.z, 1e-4)
			timg.set_pixel(i, j, Color(c.x / sum, c.y / sum, c.z / sum, jw[k]))
	_d = d
	_images = [fimg, timg]
	return _images


## Замикання (дилатація + ерозія диском CLOSE_M) біля кожної розвилки: внутрішні кути стають
## дугами радіуса CLOSE_M, а прямі й опуклі краї не змінюються. Точна відстань
## (Felzenszwalb–Huttenlocher) у вікні навколо вузла; вага спадає від NODE_INNER до NODE_REACH
## клітинки.
func _close_junctions(d: PackedFloat32Array, jw: PackedFloat32Array, rw: int, rh: int, org: float) -> void:
	var d0: PackedFloat32Array = d.duplicate()
	var half: int = ceili(NODE_REACH * PX + CLOSE_M + 4.0)
	for node in nodes:
		# На повороті з бічною дорогою — замикання радіусом BEND_CLOSE_M: воно лише з'єднує кінець бічної
		# дороги з дугою; радіус CLOSE_M заповнив би зовнішній бік дуги до прямого кута.
		var cm: float = BEND_CLOSE_M if _bend_nodes.has(node) else CLOSE_M
		var ci: int = floori((node.x - org) * PX)
		var cj: int = floori((node.y - org) * PX)
		var i0: int = maxi(ci - half, 0)
		var i1: int = mini(ci + half, rw - 1)
		var j0: int = maxi(cj - half, 0)
		var j1: int = mini(cj + half, rh - 1)
		var ww: int = i1 - i0 + 1
		var wh: int = j1 - j0 + 1
		var f := PackedFloat32Array()
		f.resize(ww * wh)
		for j in wh:
			for i in ww:
				f[j * ww + i] = 0.0 if d0[(j + j0) * rw + i + i0] > cm else 1e9
		_edt(f, ww, wh)
		for j in wh:
			for i in ww:
				var k: int = (j + j0) * rw + i + i0
				if d0[k] > cm:
					continue
				var dist: float = Vector2(org + (i + i0 + 0.5) / PX, org + (j + j0 + 0.5) / PX).distance_to(node)
				var w: float = 1.0 - smoothstep(NODE_INNER, NODE_REACH, dist)
				if w <= 0.0:
					continue
				var dc: float = cm - sqrt(f[j * ww + i])
				d[k] = minf(d[k], lerpf(d0[k], minf(d0[k], dc), w))
				jw[k] = maxf(jw[k], w)


## Площі: клітинки ROAD, що входять у суцільний блок 3×3, і окремі блоки 2×2. Скелет такого блоку
## стискається в точку чи короткий відрізок, тож лінія осі не покриває більшості його клітинок,
## хоча за правилами вони — дорога. Обрис площі — область клітинок після морфологічного
## розмикання диском PLAZA_R (опуклі кути — дуги R = 4 м) із шумом краю ±0.6 м на хвилі ~12 м.
## Де площа ближча за лінію, jw = 1: край задає шум у світових координатах, без колій.
func _plazas(d: PackedFloat32Array, tw: PackedVector3Array, jw: PackedFloat32Array, rw: int, rh: int, org: float) -> void:
	var plaza := PackedByteArray()
	plaza.resize(_w * _h)
	var any := false
	for y in range(1, _h - 1):
		for x in range(1, _w - 1):
			var full := true
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if _mask[(y + dy) * _w + x + dx] != 1:
						full = false
			if full:
				any = true
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						plaza[(y + dy) * _w + x + dx] = 1
	# Окремий блок 2×2 (жодної іншої клітинки дороги поруч, включно з діагоналями): його вісь — відрізок
	# ~0.6 клітинки, і гаусове зміщення σ = REPAIR_SIGMA зсуває його цілком, не покриваючи всі 4 кути.
	for y in _h - 1:
		for x in _w - 1:
			var cnt := 0
			for dy in range(-1, 3):
				for dx in range(-1, 3):
					var qx: int = x + dx
					var qy: int = y + dy
					if qx >= 0 and qy >= 0 and qx < _w and qy < _h and _mask[qy * _w + qx] != 0:
						cnt += 1
			var k: int = y * _w + x
			if cnt == 4 and _mask[k] == 1 and _mask[k + 1] == 1 and _mask[k + _w] == 1 \
					and _mask[k + _w + 1] == 1:
				any = true
				for dy in 2:
					for dx in 2:
						plaza[(y + dy) * _w + x + dx] = 1
	if not any:
		return
	var n_e := _noise(7919 + (_w - 2 * _shift) * 31 + _h - 2 * _shift, 1.0 / 12.0)
	var pad: int = ceili(PLAZA_R) + 4
	# Вікно — увесь растр: площ мало, а растр ≤ кількох сотень пікселів на бік.
	var inside := PackedFloat32Array()
	inside.resize(rw * rh)
	var outside := PackedFloat32Array()
	outside.resize(rw * rh)
	for j in rh:
		var cz: int = floori(org + (j + 0.5) / PX + 0.5)
		for i in rw:
			var cx: int = floori(org + (i + 0.5) / PX + 0.5)
			var on: bool = cx >= 0 and cz >= 0 and cx < _w and cz < _h and plaza[cz * _w + cx] == 1
			inside[j * rw + i] = 1e9 if on else 0.0
			outside[j * rw + i] = 0.0 if on else 1e9
	_edt(inside, rw, rh)
	# Ерозія на PLAZA_R; відстань до неї мінус PLAZA_R — знакове поле розімкнення (опуклі кути — дуги).
	var eroded := PackedFloat32Array()
	eroded.resize(rw * rh)
	for k in rw * rh:
		eroded[k] = 0.0 if sqrt(inside[k]) >= PLAZA_R else 1e9
	_edt(eroded, rw, rh)
	for j in rh:
		for i in rw:
			var k: int = j * rw + i
			# Дошка, уся вкрита площею, не має краю, і EDT лишає 1e9: обмежуємо, як поле за краєм.
			var di: float = minf(sqrt(inside[k]), FAR_M)
			var de: float = sqrt(eroded[k])
			if de > PLAZA_R + pad:
				continue
			var wp := Vector2(org + (i + 0.5) / PX, org + (j + 0.5) / PX)
			var dp: float = (de - PLAZA_R if de > 0.0 else -di) + 0.6 * clampf(2.0 * n_e.get_noise_2dv((wp - Vector2(_shift, _shift)) * 8.0), -1.0, 1.0)
			var wj: float = smoothstep(0.0, 2.0, d[k] - dp)
			if wj <= 0.0:
				continue
			tw[k] = tw[k].lerp(_type_soft(wp), wj)
			jw[k] = maxf(jw[k], wj)
			d[k] = minf(d[k], dp)


## Ваги типів у точці: гаусове зважування клітинок дороги навколо (σ 0.6 клітинки) — межа типів
## на площі плавна, а не по лінії клітинок.
func _type_soft(p: Vector2) -> Vector3:
	var acc := Vector3.ZERO
	var cx0: int = floori(p.x + 0.5)
	var cz0: int = floori(p.y + 0.5)
	for cz in range(maxi(cz0 - 2, 0), mini(cz0 + 3, _h)):
		for cx in range(maxi(cx0 - 2, 0), mini(cx0 + 3, _w)):
			if _mask[cz * _w + cx] != 1:
				continue
			var g: float = exp(-p.distance_squared_to(Vector2(cx, cz)) / 0.72)
			var t: int = _type[cz * _w + cx]
			acc += Vector3(g if t == 0 else 0.0, g if t == 1 else 0.0, g if t == 2 else 0.0)
	var s: float = acc.x + acc.y + acc.z
	return acc / s if s > 1e-6 else Vector3(1.0, 0.0, 0.0)


## Квадрат евклідової відстані до найближчого нуля (Felzenszwalb–Huttenlocher), на місці.
static func _edt(f: PackedFloat32Array, w: int, h: int) -> void:
	var col := PackedFloat32Array()
	var out := PackedFloat32Array()
	for i in w:
		col.resize(h)
		for j in h:
			col[j] = f[j * w + i]
		out = _edt1(col)
		for j in h:
			f[j * w + i] = out[j]
	for j in h:
		out = _edt1(f.slice(j * w, j * w + w))
		for i in w:
			f[j * w + i] = out[i]


static func _edt1(f: PackedFloat32Array) -> PackedFloat32Array:
	var n: int = f.size()
	var out := PackedFloat32Array()
	out.resize(n)
	var v := PackedInt32Array()
	v.resize(n)
	var z := PackedFloat32Array()
	z.resize(n + 1)
	var k := 0
	z[0] = -1e20
	z[1] = 1e20
	for q in range(1, n):
		var s: float = ((f[q] + q * q) - (f[v[k]] + v[k] * v[k])) / (2.0 * q - 2.0 * v[k])
		while s <= z[k]:
			k -= 1
			s = ((f[q] + q * q) - (f[v[k]] + v[k] * v[k])) / (2.0 * q - 2.0 * v[k])
		k += 1
		v[k] = q
		z[k] = s
		z[k + 1] = 1e20
	k = 0
	for q in n:
		while z[k + 1] < q:
			k += 1
		out[q] = (q - v[k]) * (q - v[k]) + f[v[k]]
	return out


## Знакова відстань до краю дороги (м) у світовій точці p — білінійно з поля rasterise().
func d_from(img: Image, p: Vector2) -> float:
	var rw: int = img.get_width()
	var rh: int = img.get_height()
	var tx: float = (p.x + 0.5 + _margin) * PX - 0.5
	var tz: float = (p.y + 0.5 + _margin) * PX - 0.5
	var ix: int = clampi(floori(tx), 0, rw - 2)
	var iz: int = clampi(floori(tz), 0, rh - 2)
	var fx: float = clampf(tx - ix, 0.0, 1.0)
	var fz: float = clampf(tz - iz, 0.0, 1.0)
	var a: float = lerpf(img.get_pixel(ix, iz).r, img.get_pixel(ix + 1, iz).r, fx)
	var b: float = lerpf(img.get_pixel(ix, iz + 1).r, img.get_pixel(ix + 1, iz + 1).r, fx)
	return lerpf(a, b, fz)


## Те саме поле d (м) масивом rasterise(): rw = (ширина + 2 * відступ) * PX.
func d_grid() -> PackedFloat32Array:
	rasterise()
	return _d
