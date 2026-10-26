class_name GroundLod
extends RefCounted
## Густота меша землі за рельєфом: кожна клітинка отримує найменше число квадів на бік, за якого
## меш відхиляється від поля висот TerrainHeight менше за допуск. Рівне поле — 2 трикутники на
## клітинку, берег і схил — до 98. Меш тримає лише висоту, на якій стоять юніти й пропси;
## нормаль, маски берега й кривизну шейдер землі бере з карт у кожному пікселі (ground.gdshader),
## тож густота вершин вигляду рельєфу не міняє. Правил висоти не читає.
##
## Вершини меша лежать у відліках поля (а не на рівномірній решітці): висота вершини — точне
## значення відліку, а найгустіший рівень — самі відліки, тож він збігається з полем без похибки.
## Рівні вкладені (`axes`): грубе ребро проходить крізь усі вершини дрібного, шва між клітинками
## різної густоти нема.
##
## Поле висот світу з кільцем TerrainHeight після запікання зводить до поверхні цього меша
## (`surface`): юніт, пропс, вода й камера читають ту саму висоту, що й малює меш, а не гладке
## поле, з якого його знято. Майданчики будівель міняють поле вже після цього, і меш добирається
## знову (GroundSurface.refit) у клітинках, які вони зачепили.

## Допуск зведення поля до меша, світ (8 м = 1.0): 0.016 — 13 см. Береговим клітинкам — вужчий, бо
## уріз води йде за висотою: 0.008 — 6 см, схил берега ~0.4, тож урізу зсув ≤ 15 см. Допуск стосується
## меша клітинки без зшивання; біля ребра з грубішою сусідкою вершини лягають на її ребро, і відхил
## може сягнути суми двох допусків (виміряно 0.0176 при 0.016). Відлік ніколи не міняє бік
## відносно рівня води (`level`).
const TOL_BODY: float = 0.016
const TOL_BANK: float = 0.008
## Допуск меша в клітинках, де майданчики змінили поле: поза ними поле вже лежить на меші точно, а тут
## меш розходиться з висотою, на якій стоять пропси, не більш ніж на це.
const TOL_FIT: float = 0.003
## Допуск росте з відстанню клітинок від дошки: поза нею юнітів нема, а імла далі закриває рельєф.
const RING_GROWTH: float = 0.5

static var _axes: Dictionary = {}


## Вершини уздовж ребра клітинки в номерах відліків (0..s) для рівнів від найгрубішого: [0, s], далі
## кожен рівень додає середину кожного відрізка (округлену вгору), поки не лишаться всі відліки.
static func axes(s: int) -> Array[PackedInt32Array]:
	if not _axes.has(s):
		var out: Array[PackedInt32Array] = []
		var cur := PackedInt32Array([0, s])
		out.append(cur)
		while cur.size() < s + 1:
			var next := PackedInt32Array()
			for k in cur.size() - 1:
				next.append(cur[k])
				if cur[k + 1] - cur[k] > 1:
					next.append((cur[k] + cur[k + 1] + 1) / 2)
			next.append(cur[-1])
			cur = next
			out.append(cur)
		_axes[s] = out
	return _axes[s]


## Вершини ребра для клітинки з n квадами на бік (n — одне з чисел рівнів; інше — найближчий грубший).
static func axis(s: int, n: int) -> PackedInt32Array:
	var all: Array[PackedInt32Array] = axes(s)
	var best: PackedInt32Array = all[0]
	for a in all:
		if a.size() - 1 <= n:
			best = a
	return best


## Клітинка (координати дошки, -ring .. розмір + ring - 1) -> квадів на бік. `height` — світ із
## кільцем (TerrainHeight.bake з тим самим ring), `size` — розмір дошки без кільця, `fine` —
## клітинки берега (TerrainHeight.bank_cells), `tol` — допуск у решті клітинок. Берегові клітинки допуск
## з відстанню не збільшують: уріз води йде за висотою, і ґрунт не має виринати над водою в кільці.
static func levels(height: TerrainHeight, size: Vector2i, ring: int, fine: Dictionary = {},
		tol: float = TOL_BODY, tol_bank: float = TOL_BANK) -> Dictionary:
	var h: PackedFloat32Array = height.heights()
	var out: Dictionary = {}
	for cy in range(-ring, size.y + ring):
		for cx in range(-ring, size.x + ring):
			var c := Vector2i(cx, cy)
			var dt: int = maxi(maxi(-cx, cx - size.x + 1), maxi(-cy, cy - size.y + 1))
			out[c] = level(h, height.cols, height.samples,
					(cx + height.margin) * height.samples, (cy + height.margin) * height.samples,
					(tol_bank if fine.has(c) else tol * (1.0 + RING_GROWTH * maxi(dt - 1, 0))))
	return out


## Рівні лише для `cells` (координати дошки) за допуском TOL_FIT: клітинки, де майданчики змінили поле.
static func levels_of(height: TerrainHeight, cells: Dictionary) -> Dictionary:
	var h: PackedFloat32Array = height.heights()
	var out: Dictionary = {}
	for c: Vector2i in cells:
		out[c] = level(h, height.cols, height.samples, (c.x + height.margin) * height.samples,
				(c.y + height.margin) * height.samples, TOL_FIT)
	return out


## Найменше число квадів, чий меш у клітинці з блоком відліків від (ox, oz) вкладається в допуск.
## Найгустіший рівень не перевіряється: це самі відліки.
static func level(h: PackedFloat32Array, cols: int, s: int, ox: int, oz: int, tol: float) -> int:
	# Похибка інтерполяції не більша за розмах значень у клітинці: рівне місце перевіряти нічого.
	var lo: float = INF
	var hi: float = -INF
	for j in s + 1:
		for i in s + 1:
			var v: float = h[(oz + j) * cols + ox + i]
			lo = minf(lo, v)
			hi = maxf(hi, v)
	var all: Array[PackedInt32Array] = axes(s)
	# Рівень води не перетинаємо: клітинка, де поле заходить під воду, грубим мешем не стає.
	if hi - lo <= tol and not (lo < TerrainHeight.WATER_LEVEL and hi >= TerrainHeight.WATER_LEVEL):
		return all[0].size() - 1
	for k in all.size() - 1:
		if _fits(h, cols, s, ox, oz, all[k], tol):
			return all[k].size() - 1
	return s


static func _fits(h: PackedFloat32Array, cols: int, s: int, ox: int, oz: int, ax: PackedInt32Array, tol: float) -> bool:
	var lat: PackedFloat32Array = _lattice(h, cols, ox, oz, ax)
	for j in s + 1:
		for i in s + 1:
			var f: float = h[(oz + j) * cols + ox + i]
			var m: float = _on_lattice(lat, ax, i, j)
			# Відлік не міняє бік відносно рівня води: сухе лишається сухим, мокре — мокрим.
			if absf(m - f) > tol or (m < TerrainHeight.WATER_LEVEL) != (f < TerrainHeight.WATER_LEVEL):
				return false
	return true


## Значення поля у вершинах решітки: точні відліки.
static func _lattice(h: PackedFloat32Array, cols: int, ox: int, oz: int, ax: PackedInt32Array) -> PackedFloat32Array:
	var n: int = ax.size() - 1
	var lat := PackedFloat32Array()
	lat.resize((n + 1) * (n + 1))
	for b in n + 1:
		for q in n + 1:
			lat[b * (n + 1) + q] = h[(oz + ax[b]) * cols + ox + ax[q]]
	return lat


## Висота меша у відліку (i, j) клітинки: ті самі два трикутники, що й в індексах Surroundings.ground_mesh.
static func _on_lattice(lat: PackedFloat32Array, ax: PackedInt32Array, i: int, j: int) -> float:
	var n: int = ax.size() - 1
	var qa: int = 0
	while qa < n - 1 and ax[qa + 1] <= i:
		qa += 1
	var qb: int = 0
	while qb < n - 1 and ax[qb + 1] <= j:
		qb += 1
	var lu: float = float(i - ax[qa]) / (ax[qa + 1] - ax[qa])
	var lv: float = float(j - ax[qb]) / (ax[qb + 1] - ax[qb])
	var k: int = qb * (n + 1) + qa
	var v00: float = lat[k]
	var v10: float = lat[k + 1]
	var v01: float = lat[k + n + 1]
	var v11: float = lat[k + n + 2]
	return v00 + (v10 - v00) * lu + (v01 - v00) * lv if lu + lv <= 1.0 \
			else v11 + (v01 - v11) * (1.0 - lu) + (v10 - v11) * (1.0 - lv)


## Поле висот, зведене до меша: для кожного відліку — висота меша в тій точці. Вершини решітки
## беруть висоту поля, а вершина на ребрі з грубішою сусідкою — пряму грубого ребра (як вершинний
## шейдер землі), тож поверхня збігається з намальованою й на швах. `quads` — квадів на бік кожної
## клітинки (Surroundings.cell_quads).
static func surface(h: PackedFloat32Array, cols: int, s: int, margin: int, size: Vector2i, ring: int,
		quads: Dictionary) -> PackedFloat32Array:
	var out: PackedFloat32Array = h.duplicate()
	var dirs: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
	for cy in range(-ring, size.y + ring):
		for cx in range(-ring, size.x + ring):
			var c := Vector2i(cx, cy)
			var ax: PackedInt32Array = axis(s, quads[c])
			var n: int = ax.size() - 1
			var ox: int = (cx + margin) * s
			var oz: int = (cy + margin) * s
			var lat: PackedFloat32Array = _lattice(h, cols, ox, oz, ax)
			for side in 4:
				var coarse: PackedInt32Array = axis(s, int(quads.get(c + dirs[side], quads[c])))
				var m: int = coarse.size() - 1
				if m >= n:
					continue
				var k: int = 0
				for q in range(1, n):
					# Вершина лежить на відрізку грубого ребра між вершинами k і k + 1.
					while k < m - 1 and coarse[k + 1] <= ax[q]:
						k += 1
					var t: float = float(ax[q] - coarse[k]) / (coarse[k + 1] - coarse[k])
					var a: float
					var b: float
					var idx: int
					match side:
						0:
							idx = q
							a = h[oz * cols + ox + coarse[k]]
							b = h[oz * cols + ox + coarse[k + 1]]
						1:
							idx = n * (n + 1) + q
							a = h[(oz + s) * cols + ox + coarse[k]]
							b = h[(oz + s) * cols + ox + coarse[k + 1]]
						2:
							idx = q * (n + 1)
							a = h[(oz + coarse[k]) * cols + ox]
							b = h[(oz + coarse[k + 1]) * cols + ox]
						_:
							idx = q * (n + 1) + n
							a = h[(oz + coarse[k]) * cols + ox + s]
							b = h[(oz + coarse[k + 1]) * cols + ox + s]
					lat[idx] = lerpf(a, b, t)
			for j in s + 1:
				for i in s + 1:
					out[(oz + j) * cols + ox + i] = _on_lattice(lat, ax, i, j)
	return out
