class_name VegetationLayer
extends Node3D
## Рослинність поля бою — лише вигляд, правил не додає:
## - береги: куртини очерету й рогозу на мілині вздовж урізу води й купи верболозу та вільхи на
##   березі — плямами, не суцільним кільцем; більше на тихих вигинах і біля боліт;
## - луки: рідкі поодинокі кущі (глід, шипшина) й дерева (груша, дуб, біля води — верба), по
##   одному або групками з 2–3, лише на неораному полі;
## - двори: у 60–75 % садиб, лише всередині паркану — яблуня чи вишня, а де дерево не влазить, і
##   другою — бузок, бузина, туя або ягідний ряд.
## Нічого біля мостів, на дорогах з узбіччям, у ріллі, на парканах і грядках; крона не заходить на
## будівлю. Кожна точка має власне зерно (point_seed) від зерна карти, тож розстановка однакова в
## усіх гравців. Юніта рослини не ховають: дерево чи кущ, чия крона над клітинкою юніта або між
## ним і камерою, стає напівпрозорим (set_reveal_cells; гола крона пізньої пори — не прозоріша за
## FADE_FLOOR). Клітинка, куди в'їхала техніка (set_crushed), показує повалений двійник
## (<вузол>_fallen). Моделі — вузли бібліотек assets/props/vegetation/<група>_veg_<пора>.glb.

const LIB: String = "res://assets/props/vegetation/%s_veg_%s.glb"
const REEDS: Array[StringName] = [&"bank_reed_01", &"bank_reed_02", &"bank_reed_03"]
const CATTAILS: Array[StringName] = [&"bank_cattail_01", &"bank_cattail_02", &"bank_cattail_03"]
const BUSHES: Array[StringName] = [
	&"bank_bush_willow_01", &"bank_bush_willow_02", &"bank_bush_willow_03",
	&"bank_bush_alder_01", &"bank_bush_alder_02", &"bank_bush_alder_03",
]
const MEADOW_BUSHES: Array[StringName] = [
	&"meadow_hawthorn_01", &"meadow_hawthorn_02", &"meadow_hawthorn_03",
	&"meadow_dogrose_01", &"meadow_dogrose_02", &"meadow_dogrose_03",
]
const MEADOW_TREES: Array[StringName] = [&"meadow_pear_01", &"meadow_pear_02", &"meadow_pear_03",
	&"meadow_oak_01", &"meadow_oak_02", &"meadow_oak_03"]
const WET_TREES: Array[StringName] = [&"meadow_willow_01", &"meadow_willow_02", &"meadow_willow_03"]
const YARD_TREES: Array[StringName] = [&"yard_apple_01", &"yard_apple_02", &"yard_apple_03",
	&"yard_cherry_01", &"yard_cherry_02", &"yard_cherry_03"]
const YARD_SMALL: Array[StringName] = [
	&"yard_lilac_01", &"yard_lilac_02", &"yard_lilac_03", &"yard_elder_01", &"yard_elder_02", &"yard_elder_03",
	&"yard_berry_row_01", &"yard_berry_row_02", &"yard_berry_row_03",
	&"yard_thuja_01", &"yard_thuja_02", &"yard_thuja_03",
]
## Радіус крони (тайли, з запасом) за префіксом вузла: для правила «крона не на будівлі» й розчинення.
const CROWN: Dictionary = {
	&"bank_reed": 0.18, &"bank_cattail": 0.15, &"bank_bush": 0.22,
	&"meadow_hawthorn": 0.2, &"meadow_dogrose": 0.26, &"meadow_pear": 0.45, &"meadow_oak": 0.55,
	&"meadow_willow": 0.45, &"yard_apple": 0.34, &"yard_cherry": 0.28, &"yard_walnut": 0.66,
	&"yard_lilac": 0.24, &"yard_elder": 0.26, &"yard_berry_row": 0.32, &"yard_thuja": 0.12,
}

## Масштаб екземпляра за префіксом вузла: дуб і верба на луках — 10–15 м, яблуня й вишня у дворі — 5–6 м.
## Модель будується меншою, бо голу крону обмежує розмах гілок; шейдер збільшує картки разом з екземпляром.
const GROW: Dictionary = {&"meadow_oak": 1.4, &"meadow_willow": 1.35, &"yard_apple": 1.15, &"yard_cherry": 0.8}

## Береги. Пляма: клітинки групуються в квадрати PATCH × PATCH; пляма «жива» з імовірністю PATCH_ON %.
const PATCH: int = 2
const PATCH_ON: int = 70
## У живій плямі клітинка води з очеретом — CELL_ON %, на тихому вигині чи біля болота — більше.
const CELL_ON: int = 80
const BEND_BONUS: int = 10
## Кущі на клітинці суходолу біля води — BUSH_ON % (у живій плямі).
const BUSH_ON: int = 55
## Ні мостів ближче за NO_BRIDGE клітинок, ні доріг ближче за NO_ROAD (Чебишев) — для берега.
const NO_BRIDGE: int = 2
const NO_ROAD: int = 1
## Мілина для очерету: ґрунт нижче рівня води на 0…SHALLOW тайла (0–1 м).
const SHALLOW: float = 0.12
## Основа куртини — не глибше REED_DIP під поверхнею води (16 см), хоч дно й глибше: вода майже непрозора, і
## з основою на дні під нею ховається весь темний мокрий низ кущика очерету — над водою лишаються самі пухнасті верхівки.
const REED_DIP: float = 0.02
## Кущ і дерево — на сухому: ґрунт вище води щонайменше на DRY; схил не крутіший за STEEP (y нормалі).
const DRY: float = 0.02
const STEEP: float = 0.85
## Береговий кущ — на краю клітинки суходолу, щонайменше BUSH_EDGE від центру.
const BUSH_EDGE: float = 0.42
## Відстань між куртинами очерету й між кущами в купі (тайли).
const REED_GAP: float = 0.07
const BUSH_GAP: float = 0.22
## Береговий кущ — не далі SHORE_REACH від урізу води.
const SHORE_REACH: float = 0.4
## Вода (а з нею й очерет) — щонайменше LAND_CLEAR від центру будь-якої клітинки суходолу (§8).
const LAND_CLEAR: float = 0.3
## Ставок — водойма не більша за POND_MAX клітинок. Очерет на ньому — POND_PATCHES плям, що разом
## з розмахом куртин займають POND_SHARE довжини урізу, і не далі POND_REACH від урізу (1 м).
const POND_MAX: int = 16
const POND_PATCHES: Vector2i = Vector2i(3, 5)
const POND_SHARE: Vector2 = Vector2(0.28, 0.36)
## Розмах куртини вбік від її центру вздовж урізу (тайли): пляма видно ширша за відрізок центрів.
const POND_SPREAD: float = 0.2
## Уріз ставка — POND_RAYS променів від центру.
const POND_RAYS: int = 96
const POND_REACH: float = 0.125
## Луки: квадрат MEADOW_PATCH × MEADOW_PATCH клітинок має групу з імовірністю MEADOW_ON %.
const MEADOW_PATCH: int = 4
const MEADOW_ON: int = 30
const MEADOW_TRIES: int = 6
## Дерево на луці — з імовірністю MEADOW_TREE % (решта — кущі); верба — лише ближче WET_REACH до води.
const MEADOW_TREE: int = 35
const WET_REACH: float = 1.5
## Луки — не ближче HOME_CLEAR клітинок до забудови (двори мають свої рослини).
const HOME_CLEAR: int = 1
## Узбіччя: стовбур не ближче ROAD_PAD тайла до дороги, а крона (коло crown) не нависає над нею.
const ROAD_PAD: float = 0.5
## Стовбур — не ближче FENCE_CLEAR до паркана й інших дрібних пропсів.
const FENCE_CLEAR: float = 0.08
## Будь-яка крона — не ближче за свій радіус плюс FENCE_CROWN_PAD до секції паркану: з камери крона над
## секцією читається рослиною, що проросла крізь паркан.
const FENCE_CROWN_PAD: float = 0.1
## Те саме на екрані: камера дивиться під кутом, і крона (диск із центром на CROWN_H_K радіусів над стовбуром)
## лягає на паркан чи ворота за деревом, хоч у плані до них є запас. Диск не ближче за свій радіус до силуету
## секції (верх FENCE_TOP, клітинки, ~1.8 м) чи воріт.
const FENCE_TOP: float = 0.23
## Рослина двору не росте на грядках: диск крони на екрані не ближче до ділянки городу за цю частку радіуса
## (нависає над краєм не глибше за решту), а стовбур — поза ділянкою.
const PLOT_GAP_SHARE: float = 0.8
const CROWN_H_K: float = 2.2
## Під дротом ЛЕП крона не стоїть ближче за WIRE_PAD від прольоту (розкид масштабу 1,1 × радіус), а стовбур — ближче за POLE_CLEAR від опори.
const WIRE_PAD: float = 0.15
const POLE_CLEAR: float = 0.3
## Двори: рослини (1–2) — у YARD_SHARE садиб карти, де вони влазять.
const YARD_SHARE: float = 0.68
## Кущ росте попід стіною: досить YARD_BUSH_WALL радіуса крони від даху (дерево — повний радіус).
const YARD_BUSH_WALL: float = 0.55
## Крок сітки точок двору (тайли).
const YARD_STEP: float = 0.05
## Розчинення над юнітом (як у PropLayer) і нижня межа альфи голої крони пізньої пори.
const FADE_ALPHA: float = 0.35
const FADE_FLOOR: float = 0.6

## Розставлення: {node, pos (Vector3, світ), yaw, scale, cell, kind ("reed" | "bush" | "tree"), group}.
var placements: Array[Dictionary] = []
## Рілля, з якою будувалось розставлення (для тестів).
var fields: Array[Rect2] = []
var _season: StringName = &"late"
## Сонячна карта (BoardView.structure_shadows): плями затінення витягуються в тінь від сонця.
var cast_shadows: bool = false
var _crushed: Dictionary = {}
var _reveal: Dictionary = {}
## Меші вузлів бібліотек за порою року й готові меші з матеріалами: спільні на процес, бо GLB і
## шейдери ті самі для кожної дошки (без кешу кожна побудова дошки завантажувала три бібліотеки).
static var _lib_meshes: Dictionary = {}
static var _ready_meshes: Dictionary = {}
## Шейдери злитого меша (рослина й пляма) і масиви поверхонь вузлів бібліотеки.
static var _batch_shaders: Dictionary = {}
static var _surface_arrays: Dictionary = {}
## Для кожної рослини з `placements`: батч, у якому вона зліпилась, і номер у ньому (−1 — не малюється).
var _slot_batch: Array[FoliageBatch] = []
var _slot_id: PackedInt32Array = PackedInt32Array()
## Вузли бібліотеки, що малюються (повалені — з суфіксом `_fallen`): для тестів.
var _drawn: Array[StringName] = []


## Зерно точки: окреме для кожної клітинки й солі, від зерна карти — однакове в усіх гравців.
static func point_seed(map_seed: int, cell: Vector2i, salt: int) -> int:
	return hash([map_seed, cell.x, cell.y, salt])


## Пляма затінення під рослиною. Очерет стоїть у воді: на похмурій карті (без сонця) чорна пляма лише темнила б воду
## довкола куртини, а на сонячній вона — єдина тінь очерету (cast), тож лишається.
static func has_shade(node: StringName, sunny: bool) -> bool:
	return sunny or not (REEDS.has(node) or CATTAILS.has(node))


static func crown_of(node: StringName) -> float:
	for k: StringName in CROWN:
		if String(node).begins_with(String(k)):
			return CROWN[k] * grow_of(node)
	return 0.2


static func grow_of(node: StringName) -> float:
	for k: StringName in GROW:
		if String(node).begins_with(String(k)):
			return GROW[k]
	return 1.0


## Перешкоди з PropLayer: прямокутники XZ будівель (крона на них не заходить) і дрібних пропсів —
## парканів, стовпів, тюків (на них не стає стовбур), плюс грядки городів.
static func obstacles(props: PropLayer) -> Dictionary:
	var roofs: Array[Rect2] = []
	var small: Array[Rect2] = []
	var poles: Array[Rect2] = []
	var fences: Array[Rect2] = []
	if props == null:
		return {"roofs": roofs, "small": small, "poles": poles, "fences": fences, "fence_hulls": [], "plots": [], "plot_hulls": [], "wires": []}
	for inst: Dictionary in props.all_instances():
		var info: Variant = PropLayer.model(inst["model"])
		if not (info is Dictionary) or not (info as Dictionary).has("aabb"):
			continue
		var box: AABB = ((inst["transform"] as Transform3D) * ((info as Dictionary)["local"] as Transform3D)) * ((info as Dictionary)["aabb"] as AABB)
		var r := Rect2(box.position.x, box.position.z, box.size.x, box.size.z)
		var kind: int = int(PropLayer.spec_of(inst["model"]).get("kind", -1))
		if kind in [PropLayer.Kind.STRUCTURE, PropLayer.Kind.RUIN, PropLayer.Kind.BLOCK, PropLayer.Kind.BRIDGE]:
			roofs.append(r)
		else:
			small.append(r)
		if kind == PropLayer.Kind.POLE:
			poles.append(r)
		if kind == PropLayer.Kind.GARDEN_FENCE or kind == PropLayer.Kind.FIELD_FENCE:
			fences.append(r)
	var plots: Array[Rect2] = []
	var plot_hulls: Array = []
	for t: Transform3D in props.garden_beds():
		var box: AABB = t * AABB(Vector3(-0.5, 0, -0.5), Vector3(1, 0.1, 1))
		small.append(Rect2(box.position.x, box.position.z, box.size.x, box.size.z))
		plots.append(small.back())
		var ppts := PackedVector2Array()
		for c: Vector2 in [small.back().position, Vector2(small.back().end.x, small.back().position.y), small.back().end, Vector2(small.back().position.x, small.back().end.y)]:
			ppts.append(PropLayer._Placer._screen_pt(c, 0.0))
		plot_hulls.append(Geometry2D.convex_hull(ppts))
	# Ворота — теж паркан: стовпи a, b (mid між ними), полотно не вище FENCE_TOP.
	for g: Dictionary in props.gates():
		fences.append(Rect2(g["a"], Vector2.ZERO).expand(g["b"]).grow(0.03))
	var hulls: Array = []
	for r: Rect2 in fences:
		var pts := PackedVector2Array()
		for c: Vector2 in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
			for y: float in [0.0, FENCE_TOP]:
				pts.append(PropLayer._Placer._screen_pt(c, y))
		hulls.append(Geometry2D.convex_hull(pts))
	return {"roofs": roofs, "small": small, "poles": poles, "fences": fences, "fence_hulls": hulls, "plots": plots, "plot_hulls": plot_hulls, "wires": props.wire_lines()}


## Відстань на екрані від диска крони (радіус crown) стовбура q до силуету найближчої секції чи воріт.
static func fence_screen_gap(obst: Dictionary, q: Vector2, crown: float) -> float:
	return PropLayer._Placer._hull_gap(q, CROWN_H_K * crown, obst["fence_hulls"])


## Мінімальна відстань стовбура до осі ЛЕП: крона з розкидом масштабу й запасом, не менше POLE_CLEAR.
static func power_clear(crown: float) -> float:
	return maxf(crown * 1.1 + WIRE_PAD, POLE_CLEAR)


## Відстань від точки до найближчої опори чи дроту ЛЕП: крона не росте під ними.
static func _power_dist(obst: Dictionary, p: Vector2) -> float:
	var d: float = INF
	for r: Rect2 in obst.get("poles", []):
		d = minf(d, _rect_dist(r, p))
	for w: Array in obst.get("wires", []):
		d = minf(d, p.distance_to(Geometry2D.get_closest_point_to_segment(p, w[0], w[1])))
	return d


static func _rect_dist(r: Rect2, p: Vector2) -> float:
	var dx: float = maxf(maxf(r.position.x - p.x, 0.0), p.x - r.end.x)
	var dy: float = maxf(maxf(r.position.y - p.y, 0.0), p.y - r.end.y)
	return Vector2(dx, dy).length()


## Чи можна поставити рослину з коренем у p і кроною радіуса crown: не на дорозі з узбіччям, не на
## мосту, не у воді, не в ріллі, не на пропсі, крона — не на будівлі.
static func _free(board: Board, height: TerrainHeight, props: PropLayer, obst: Dictionary, fields: Array[Rect2],
		p: Vector2, crown: float, stats: Dictionary) -> bool:
	var c := Vector2i(roundi(p.x), roundi(p.y))
	# Ліс (FOREST) має свій шар — рослина поверх нього стояла б у кронах.
	if not board.in_bounds(c) or board.kind_at(c) in [Terrain.Kind.ROAD, Terrain.Kind.BRIDGE,
			Terrain.Kind.BRIDGE_DESTROYED, Terrain.Kind.WATER, Terrain.Kind.BUILDING, Terrain.Kind.RUBBLE,
			Terrain.Kind.FOREST]:
		_bump(stats, "bad_cell")
		return false
	if near_road(props, p, crown):
		_bump(stats, "on_road")
		return false
	for r: Rect2 in fields:
		if r.has_point(p):
			_bump(stats, "ploughed")
			return false
	if height.at(p.x, p.y) < TerrainHeight.WATER_LEVEL + DRY or height.normal_at(p.x, p.y).y < STEEP:
		_bump(stats, "wet_or_steep")
		return false
	for r: Rect2 in obst["roofs"]:
		if _rect_dist(r, p) < crown:
			_bump(stats, "roof")
			return false
	for r: Rect2 in obst["small"]:
		if _rect_dist(r, p) < FENCE_CLEAR:
			_bump(stats, "fence")
			return false
	for r: Rect2 in obst["fences"]:
		if _rect_dist(r, p) < crown + FENCE_CROWN_PAD:
			_bump(stats, "fence")
			return false
	if fence_screen_gap(obst, p, crown) < crown:
		_bump(stats, "fence")
		return false
	if _power_dist(obst, p) < power_clear(crown):
		_bump(stats, "power_line")
		return false
	return true


## Стовбур ближче ROAD_PAD до дороги або край крони радіуса crown над дорогою. Край крони —
## 8 точок кола: on_road шукає відрізки лише в індексі клітинки точки, великий запас його минає.
static func near_road(props: PropLayer, p: Vector2, crown: float) -> bool:
	if props == null:
		return false
	if props.on_road(p, ROAD_PAD):
		return true
	for k in 8:
		if props.on_road(p + Vector2.from_angle(TAU * k / 8.0) * crown, 0.05):
			return true
	return false


static func _in_fields(fields: Array[Rect2], p: Vector2) -> bool:
	for r: Rect2 in fields:
		if r.has_point(p):
			return true
	return false


static func _bump(stats: Dictionary, key: String) -> void:
	stats[key] = int(stats.get(key, 0)) + 1


## Розставлення для дошки — чиста функція (тести перевіряють її без сцени).
## stats (необов'язково) — лічильники відкинутих кандидатів за причиною.
static func plan(board: Board, height: TerrainHeight, fields: Array[Rect2], map_seed: int,
		props: PropLayer = null, homes: Array = [], stats: Dictionary = {}) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if height == null:
		return out
	var obst: Dictionary = obstacles(props)
	_plan_banks(board, height, fields, map_seed, obst, out, stats)
	_plan_meadows(board, height, fields, map_seed, props, obst, out, stats)
	_plan_yards(board, height, fields, map_seed, props, obst, homes, out, stats)
	return out


static func _near_kind(board: Board, c: Vector2i, r: int, kinds: Array) -> bool:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var n: Vector2i = c + Vector2i(dx, dy)
			if board.in_bounds(n) and board.kind_at(n) in kinds:
				return true
	return false


static func _plan_banks(board: Board, height: TerrainHeight, fields: Array[Rect2], map_seed: int, obst: Dictionary,
		out: Array[Dictionary], stats: Dictionary) -> void:
	var land := [Terrain.Kind.FIELD, Terrain.Kind.MARSH, Terrain.Kind.HILL]
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var pond_cells: Dictionary = {}
	for pond: Array[Vector2i] in ponds(board):
		for pc in pond:
			pond_cells[pc] = true
		_plan_pond(board, height, map_seed, pond, out)
	for y in board.height:
		for x in board.width:
			var c := Vector2i(x, y)
			var k: int = board.kind_at(c)
			if _near_kind(board, c, NO_BRIDGE, [Terrain.Kind.BRIDGE, Terrain.Kind.BRIDGE_DESTROYED]) \
					or _near_kind(board, c, NO_ROAD, [Terrain.Kind.ROAD]):
				_bump(stats, "bank_near_road")
				continue
			var prng := RandomNumberGenerator.new()
			prng.seed = point_seed(map_seed, Vector2i(floori(float(x) / PATCH), floori(float(y) / PATCH)), 1)
			if prng.randi_range(0, 99) >= PATCH_ON:
				continue
			var rng := RandomNumberGenerator.new()
			if k == Terrain.Kind.WATER and not pond_cells.has(c):
				var shore: bool = false
				for d in dirs:
					shore = shore or (board.in_bounds(c + d) and board.kind_at(c + d) in land)
				if not shore:
					continue
				var landish: int = 0
				var marsh: bool = false
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						var n: Vector2i = c + Vector2i(dx, dy)
						if board.in_bounds(n) and board.kind_at(n) != Terrain.Kind.WATER:
							landish += 1
							marsh = marsh or board.kind_at(n) == Terrain.Kind.MARSH
				rng.seed = point_seed(map_seed, c, 2)
				# Тихий вигин: вода оточена суходолом з багатьох боків (≥ 4 з 8 сусідів).
				if rng.randi_range(0, 99) >= CELL_ON + (BEND_BONUS if landish >= 4 or marsh else 0):
					continue
				# Куртина — смуга вздовж урізу: усі точки мілини клітинки (сітка 8 × 8 зі зсувом від зерна;
				# русло вузьке й лежить не по центрах клітинок), з них — 8–14 на відстані ≥ REED_GAP.
				var cand: Array[Vector3] = []
				for j in 8:
					for i in 8:
						var p: Vector2 = Vector2(c) + Vector2((i + rng.randf()) / 8.0 - 0.5, (j + rng.randf()) / 8.0 - 0.5)
						var g: float = height.at(p.x, p.y)
						if g > TerrainHeight.WATER_LEVEL or g < TerrainHeight.WATER_LEVEL - SHALLOW:
							continue
						if _land_dist(board, p) < LAND_CLEAR:
							continue
						cand.append(Vector3(p.x, maxf(g, TerrainHeight.WATER_LEVEL - REED_DIP), p.y))
				_shuffle(cand, rng)
				var want: int = rng.randi_range(8, 14)
				var taken: Array[Vector3] = []
				for q: Vector3 in cand:
					if taken.size() >= want:
						break
					var far: bool = true
					for o: Vector3 in taken:
						far = far and Vector2(q.x - o.x, q.z - o.z).length() >= REED_GAP
					if not far:
						continue
					taken.append(q)
					var pool: Array[StringName] = CATTAILS if (marsh or rng.randi_range(0, 2) == 0) else REEDS
					out.append({"node": pool[rng.randi_range(0, pool.size() - 1)], "pos": q, "yaw": rng.randf_range(0.0, TAU),
							"scale": rng.randf_range(1.15, 1.45), "cell": c, "kind": "reed", "group": "bank"})
			elif k in land:
				var water_d: Array[Vector2i] = []
				for d in dirs:
					if board.in_bounds(c + d) and board.kind_at(c + d) == Terrain.Kind.WATER:
						water_d.append(d)
				if water_d.is_empty():
					continue
				rng.seed = point_seed(map_seed, c, 3)
				if rng.randi_range(0, 99) >= BUSH_ON:
					continue
				# Купа кущів: 1–3 на краю клітинки біля води, на відстані ≥ BUSH_GAP один від одного.
				var want: int = rng.randi_range(1, 3)
				var taken: Array[Vector2] = []
				for t in 24:
					if taken.size() >= want:
						break
					var dv := Vector2(water_d[rng.randi_range(0, water_d.size() - 1)])
					var p: Vector2 = Vector2(c) + dv * rng.randf_range(BUSH_EDGE, 0.5) + Vector2(-dv.y, dv.x) * rng.randf_range(-0.45, 0.45)
					if (p - Vector2(c)).length() < BUSH_EDGE:
						continue
					var far: bool = true
					for o: Vector2 in taken:
						far = far and (p - o).length() >= BUSH_GAP
					if not far or not _free(board, height, null, obst, fields, p, crown_of(BUSHES[0]), stats):
						continue
					if not near_water(height, p, SHORE_REACH):
						_bump(stats, "bush_far_from_water")
						continue
					taken.append(p)
					out.append({"node": BUSHES[rng.randi_range(0, BUSHES.size() - 1)], "pos": Vector3(p.x, height.at(p.x, p.y), p.y),
							"yaw": rng.randf_range(0.0, TAU), "scale": rng.randf_range(1.0, 1.3), "cell": c, "kind": "bush", "group": "bank"})


## Водойми не більші за POND_MAX клітинок (вода разом з мостами, зв'язність по сторонах).
static func ponds(board: Board) -> Array:
	var wet := [Terrain.Kind.WATER, Terrain.Kind.BRIDGE, Terrain.Kind.BRIDGE_DESTROYED]
	var seen: Dictionary = {}
	var out: Array = []
	for y in board.height:
		for x in board.width:
			var s := Vector2i(x, y)
			if seen.has(s) or board.kind_at(s) != Terrain.Kind.WATER:
				continue
			var comp: Array[Vector2i] = []
			var stack: Array[Vector2i] = [s]
			seen[s] = true
			while not stack.is_empty():
				var c: Vector2i = stack.pop_back()
				comp.append(c)
				for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var n: Vector2i = c + d
					if board.in_bounds(n) and not seen.has(n) and board.kind_at(n) in wet:
						seen[n] = true
						stack.append(n)
			if comp.size() <= POND_MAX:
				out.append(comp)
	return out


## Уріз ставка: на кожному з POND_RAYS променів від центру — перша точка, де ґрунт вищий за воду.
static func shore_ring(height: TerrainHeight, centre: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in POND_RAYS:
		var d := Vector2.from_angle(TAU * k / POND_RAYS)
		var r: float = 0.0
		while r < 8.0 and height.at(centre.x + d.x * r, centre.y + d.y * r) <= TerrainHeight.WATER_LEVEL:
			r += 0.02
		out.append(centre + d * r)
	return out


## Відстань уздовж урізу від променя 0 до кожного променя (останній елемент — уся довжина).
static func shore_length(ring: PackedVector2Array) -> PackedFloat32Array:
	var s := PackedFloat32Array([0.0])
	for k in ring.size():
		s.append(s[k] + ring[k].distance_to(ring[(k + 1) % ring.size()]))
	return s


static func pond_centre(pond: Array[Vector2i]) -> Vector2:
	var centre := Vector2.ZERO
	for c in pond:
		centre += Vector2(c)
	return centre / pond.size()


## Очерет ставка: точки мілини біля урізу, з них лишаються ті, що в одній з плям. Пляма — відрізок
## урізу (за довжиною, не за кутом: на видовженому ставку кут перебільшує бічні береги); уріз
## поділено на рівні частини, по плямі в кожній, тож плями не зливаються в кільце.
static func _plan_pond(board: Board, height: TerrainHeight, map_seed: int, pond: Array[Vector2i],
		out: Array[Dictionary]) -> void:
	var centre: Vector2 = pond_centre(pond)
	var along: PackedFloat32Array = shore_length(shore_ring(height, centre))
	var total: float = along[along.size() - 1]
	var rng := RandomNumberGenerator.new()
	rng.seed = point_seed(map_seed, pond[0], 6)
	# Усі придатні точки мілини біля урізу з місцем уздовж урізу.
	var shore: Array = []
	for c in pond:
		if board.kind_at(c) != Terrain.Kind.WATER \
				or _near_kind(board, c, NO_BRIDGE, [Terrain.Kind.BRIDGE, Terrain.Kind.BRIDGE_DESTROYED]) \
				or _near_kind(board, c, NO_ROAD, [Terrain.Kind.ROAD]):
			continue
		for j in 12:
			for i in 12:
				var p: Vector2 = Vector2(c) + Vector2((i + rng.randf()) / 12.0 - 0.5, (j + rng.randf()) / 12.0 - 0.5)
				var g: float = height.at(p.x, p.y)
				if g > TerrainHeight.WATER_LEVEL or g < TerrainHeight.WATER_LEVEL - SHALLOW:
					continue
				if _land_dist(board, p) < LAND_CLEAR or not near_dry(height, p, POND_REACH):
					continue
				# Місце точки вздовж урізу — за її кутом, між сусідніми променями.
				var t: float = fposmod((p - centre).angle(), TAU) / TAU * POND_RAYS
				var k: int = mini(floori(t), POND_RAYS - 1)
				shore.append([Vector3(p.x, maxf(g, TerrainHeight.WATER_LEVEL - REED_DIP), p.y), c, lerpf(along[k], along[k + 1], t - k)])
	if shore.is_empty():
		return
	# Пляма — відрізок урізу навколо придатної точки; уріз поділено на рівні частини, по плямі в
	# кожній, де є мілина, тож плями не зливаються в кільце. Довжина плями — частка урізу мінус
	# розмах куртин з обох боків.
	var n: int = rng.randi_range(POND_PATCHES.x, POND_PATCHES.y)
	var span: float = maxf(rng.randf_range(POND_SHARE.x, POND_SHARE.y) * total / n - 2.0 * POND_SPREAD, 0.1)
	var sector: float = total / n
	var start: float = rng.randf_range(0.0, total)
	var arcs: Array[float] = []
	for i in n:
		var lo: float = start + sector * i
		var inside: Array = shore.filter(func(e: Array) -> bool:
			return fposmod(float(e[2]) - lo, total) < sector - span)
		if not inside.is_empty():
			arcs.append(float(inside[rng.randi_range(0, inside.size() - 1)][2]))
	var cand: Array = []
	for e: Array in shore:
		for a0: float in arcs:
			if fposmod(float(e[2]) - a0, total) < span:
				cand.append(e)
				break
	_shuffle(cand, rng)
	var taken: Array[Vector3] = []
	for e: Array in cand:
		var q: Vector3 = e[0]
		var c: Vector2i = e[1]
		var far: bool = true
		for o: Vector3 in taken:
			far = far and Vector2(q.x - o.x, q.z - o.z).length() >= REED_GAP
		if not far:
			continue
		taken.append(q)
		var pool: Array[StringName] = CATTAILS if rng.randi_range(0, 1) == 0 else REEDS
		out.append({"node": pool[rng.randi_range(0, pool.size() - 1)], "pos": q, "yaw": rng.randf_range(0.0, TAU),
				"scale": rng.randf_range(1.15, 1.45), "cell": c, "kind": "reed", "group": "pond"})


## Чи є сухий ґрунт (вище рівня води) в межах r від точки: 16 напрямів на відстанях r/2 і r.
static func near_dry(height: TerrainHeight, p: Vector2, r: float) -> bool:
	for k in 16:
		var d := Vector2.from_angle(TAU * k / 16.0)
		for f: float in [0.5, 1.0]:
			var q: Vector2 = p + d * r * f
			if height.at(q.x, q.y) > TerrainHeight.WATER_LEVEL:
				return true
	return false


## Луки: рідкі групи 1–3 (кущі або дерева) на неораному полі, подалі від забудови.
static func _plan_meadows(board: Board, height: TerrainHeight, fields: Array[Rect2], map_seed: int, props: PropLayer,
		obst: Dictionary, out: Array[Dictionary], stats: Dictionary) -> void:
	for py in ceili(float(board.height) / MEADOW_PATCH):
		for px in ceili(float(board.width) / MEADOW_PATCH):
			var rng := RandomNumberGenerator.new()
			rng.seed = point_seed(map_seed, Vector2i(px, py), 4)
			if rng.randi_range(0, 99) >= MEADOW_ON:
				continue
			# Опорна клітинка групи — випадкова в квадраті; луг, не ближче HOME_CLEAR до забудови. До
			# MEADOW_TRIES спроб: на тісній карті з ріллею й річкою перша клітинка рідко буває лугом.
			var c := Vector2i(-1, -1)
			for t in MEADOW_TRIES:
				var q := Vector2i(px * MEADOW_PATCH + rng.randi_range(0, MEADOW_PATCH - 1), py * MEADOW_PATCH + rng.randi_range(0, MEADOW_PATCH - 1))
				if board.in_bounds(q) and board.kind_at(q) == Terrain.Kind.FIELD and not _in_fields(fields, Vector2(q)) \
						and not _near_kind(board, q, HOME_CLEAR, [Terrain.Kind.BUILDING, Terrain.Kind.RUBBLE]) \
						and not _near_kind(board, q, NO_BRIDGE, [Terrain.Kind.BRIDGE, Terrain.Kind.BRIDGE_DESTROYED]):
					c = q
					break
			if c.x < 0:
				_bump(stats, "meadow_cell")
				continue
			var tree: bool = rng.randi_range(0, 99) < MEADOW_TREE
			var n: int = 1 if tree and rng.randi_range(0, 2) > 0 else rng.randi_range(1, 3)
			var anchor := Vector2(c) + Vector2(rng.randf_range(-0.4, 0.4), rng.randf_range(-0.4, 0.4))
			var placed: int = 0
			for t in 12 * n:
				if placed >= n:
					break
				var p: Vector2 = anchor + (Vector2.ZERO if placed == 0 else Vector2.from_angle(rng.randf_range(0.0, TAU)) * rng.randf_range(0.35, 0.7))
				var node: StringName
				if tree:
					var wet: bool = near_water(height, p, WET_REACH)
					var pool: Array[StringName] = WET_TREES if wet and rng.randi_range(0, 1) == 0 else MEADOW_TREES
					node = pool[rng.randi_range(0, pool.size() - 1)]
				else:
					node = MEADOW_BUSHES[rng.randi_range(0, MEADOW_BUSHES.size() - 1)]
				if not _free(board, height, props, obst, fields, p, crown_of(node), stats):
					if placed == 0:
						anchor = Vector2(c) + Vector2(rng.randf_range(-0.4, 0.4), rng.randf_range(-0.4, 0.4))
					continue
				out.append({"node": node, "pos": Vector3(p.x, height.at(p.x, p.y), p.y), "yaw": rng.randf_range(0.0, TAU),
						"scale": rng.randf_range(0.9, 1.1) * grow_of(node), "cell": Vector2i(roundi(p.x), roundi(p.y)),
						"kind": "tree" if tree else "bush", "group": "meadow"})
				placed += 1


## Двори: у частині садиб 1–2 рослини в клітинках двору; крона не на хаті й сараї.
static func _plan_yards(board: Board, height: TerrainHeight, fields: Array[Rect2], map_seed: int, props: PropLayer,
		obst: Dictionary, homes: Array, out: Array[Dictionary], stats: Dictionary) -> void:
	# Рослини — у YARD_SHARE садиб карти: садиби по черзі за зерном; затісна садиба віддає своє
	# місце наступній, тож частка не залежить від того, скільки садиб затісні.
	var order: Array = homes.duplicate()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return point_seed(map_seed, a["house"], 5) < point_seed(map_seed, b["house"], 5))
	var target: int = roundi(YARD_SHARE * homes.size())
	var green: int = 0
	for h: Dictionary in order:
		if green >= target:
			break
		var house: Vector2i = h["house"]
		var rng := RandomNumberGenerator.new()
		rng.seed = point_seed(map_seed, house, 5)
		# Лише всередині паркану: дерево за парканом глядач бачить лучним, і хата поруч здається вищою.
		# Вільне місце в дворі — вузькі смужки між хатою, сараєм, грядками й парканом: точки шукаються
		# перебором сітки YARD_STEP, а не випадково (випадкові спроби в смужки рідко влучали).
		var spots: Array = []
		for c: Vector2i in h.get("cells", [house]):
			for j in roundi(0.9 / YARD_STEP) + 1:
				for i in roundi(0.9 / YARD_STEP) + 1:
					var q: Vector2 = Vector2(c) + Vector2(i, j) * YARD_STEP - Vector2(0.45, 0.45)
					if height.at(q.x, q.y) < TerrainHeight.WATER_LEVEL + DRY \
							or obst["small"].any(func(r: Rect2) -> bool: return _rect_dist(r, q) < FENCE_CLEAR):
						continue
					var room: float = INF
					for r: Rect2 in obst["roofs"]:
						room = minf(room, _rect_dist(r, q))
					spots.append([q, c, room])
		_shuffle(spots, rng)
		var placed: Array[Vector2] = []
		# Перша рослина — дерево 5–6 м (яблуня, вишня); не влазить біля даху чи дороги — кущ (бузок,
		# бузина, ягідний ряд, туя). Друга, не завжди, — кущ.
		var plan: Array[StringName] = [YARD_TREES[rng.randi_range(0, YARD_TREES.size() - 1)]]
		var small: StringName = YARD_SMALL[rng.randi_range(0, YARD_SMALL.size() - 1)]
		if rng.randi_range(0, 1) == 0:
			plan.append(YARD_SMALL[rng.randi_range(0, YARD_SMALL.size() - 1)])
		for k in plan.size():
			var choice: Array = []
			# Найвужча — туя: останній запасний варіант для тісного двору.
			for node: StringName in ([plan[k], small, &"yard_thuja_01"] if k == 0 else [plan[k]]):
				var need: float = crown_of(node) * (1.0 if YARD_TREES.has(node) else YARD_BUSH_WALL)
				var fence_room: float = crown_of(node) + FENCE_CROWN_PAD
				for e: Array in spots:
					var q: Vector2 = e[0]
					if float(e[2]) >= need and placed.all(func(o: Vector2) -> bool: return (q - o).length() >= 0.35) \
							and obst["fences"].all(func(r: Rect2) -> bool: return _rect_dist(r, q) >= fence_room) \
							and fence_screen_gap(obst, q, crown_of(node)) >= crown_of(node) \
							and (obst["plots"] as Array).all(func(r: Rect2) -> bool: return not r.has_point(q)) \
							and PropLayer._Placer._hull_gap(q, CROWN_H_K * crown_of(node), obst["plot_hulls"]) >= PLOT_GAP_SHARE * crown_of(node) \
							and not near_road(props, q, crown_of(node)) and _power_dist(obst, q) >= power_clear(crown_of(node)):
						choice = [node, e]
						break
				if not choice.is_empty():
					break
			if choice.is_empty():
				_bump(stats, "yard_no_room")
				break
			if k == 0:
				green += 1
			var node: StringName = choice[0]
			var q: Vector2 = choice[1][0]
			placed.append(q)
			out.append({"node": node, "pos": Vector3(q.x, height.at(q.x, q.y), q.y), "yaw": rng.randf_range(0.0, TAU),
					"scale": rng.randf_range(0.9, 1.1) * grow_of(node), "cell": choice[1][1],
					"kind": "tree" if YARD_TREES.has(node) else "bush", "group": "yard"})


static func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var t: Variant = a[i]
		a[i] = a[j]
		a[j] = t


## Чи є вода (ґрунт нижче рівня води) в межах r від точки: 16 напрямів на відстанях r/2 і r.
static func near_water(height: TerrainHeight, p: Vector2, r: float) -> bool:
	for k in 16:
		var d := Vector2.from_angle(TAU * k / 16.0)
		for f: float in [0.5, 1.0]:
			var q: Vector2 = p + d * r * f
			if height.at(q.x, q.y) < TerrainHeight.WATER_LEVEL:
				return true
	return false


## Відстань від точки до центру найближчої клітинки суходолу (не води й не мосту).
static func _land_dist(board: Board, p: Vector2) -> float:
	var best: float = INF
	var c := Vector2i(roundi(p.x), roundi(p.y))
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var n: Vector2i = c + Vector2i(dx, dy)
			if board.in_bounds(n) and board.kind_at(n) != Terrain.Kind.WATER:
				best = minf(best, (p - Vector2(n)).length())
	return best


func build(board: Board, height: TerrainHeight, p_fields: Array[Rect2], map_seed: int, season: StringName,
		props: PropLayer = null, homes: Array = []) -> void:
	_season = season if season in [&"late", &"summer", &"early"] else &"late"
	fields = p_fields
	placements = plan(board, height, fields, map_seed, props, homes)
	_rebuild()


## Клітинки, куди в'їжджала техніка (уже обрізані розвіданим глядача, §3.5): кущі й дерева на
## них показують повалений двійник; очерет у воді техніка не топче.
func set_crushed(cells: Array[Vector2i]) -> void:
	var next: Dictionary = {}
	for c in cells:
		next[c] = true
	if next == _crushed:
		return
	_crushed = next
	_rebuild()


## Клітинки юнітів: рослина, чия крона над такою клітинкою або між нею й камерою (ті самі
## сусіди, що й у PropLayer.REVEAL_OFFSETS), стає напівпрозорою.
func set_reveal_cells(cells: Array[Vector2i]) -> void:
	var next: Dictionary = {}
	for c in cells:
		for o in PropLayer.REVEAL_OFFSETS:
			next[c + o] = true
	if next == _reveal:
		return
	_reveal = next
	_refade()


## Прогрів за гейтом (BattleScreen._warm_board): рослина, найближча до `near`, показана розчиненою,
## щоб прохід глибини й колір розчинення скомпілювались до першого юніта під нею (шейдери спільні
## для всіх вузлів — досить однієї). Повертає її клітинку (−1, −1 — рослин немає); показане скидає
## наступний set_reveal_cells.
func warm_fade(near: Vector2i) -> Vector2i:
	var cell := Vector2i(-1, -1)
	var best: float = INF
	for p: Dictionary in placements:
		var c := Vector2i(roundi(p["pos"].x), roundi(p["pos"].z))
		var d: float = Vector2(c).distance_squared_to(Vector2(near))
		if d < best:
			best = d
			cell = c
	if cell.x >= 0:
		_reveal = {cell: true}
		_refade()
	return cell


func _covers(p: Dictionary) -> bool:
	if _reveal.is_empty():
		return false
	var r: float = crown_of(p["node"]) * float(p.get("scale", 1.0))
	var q := Vector2(p["pos"].x, p["pos"].z)
	for c: Vector2i in _reveal:
		if _rect_dist(Rect2(Vector2(c) - Vector2(0.5, 0.5), Vector2.ONE), q) < r:
			return true
	return false


func drawn_nodes() -> Array[StringName]:
	return _drawn


## Чи стоїть рослина `i` у злитому мейші цілою (над юнітом її малює напівпрозорий двійник `_faded`).
func plant_visible(i: int) -> bool:
	return _slot_batch[i] != null and _slot_batch[i].is_alive(_slot_id[i])


## Усі рослини — по мешу на атлас бібліотеки (береги, луки, двори), а не MultiMesh на вузол: у кожної
## моделі ще й поверхня плями затінення, тож вузлів було вдвічі більше, ніж моделей (§8). Тіні сонця
## рослини не кидають — це пляма на землі, а не прохід тіней. Перебудова — лише коли міняється розстановка
## чи розчавлене; розчинення над юнітом (`_refade`) пише в таблицю батча.
func _rebuild() -> void:
	for ch in get_children():
		ch.free()
	_slot_batch.clear()
	_slot_batch.resize(placements.size())
	_slot_id.resize(placements.size())
	_slot_id.fill(-1)
	_drawn.clear()
	if placements.is_empty():
		return
	var meshes: Dictionary = _meshes_of(_season)
	var by_node: Dictionary = {}  ## вузол -> {"list", "idx", "mesh"}
	for i in placements.size():
		var p: Dictionary = placements[i]
		var node: StringName = p["node"]
		if p["kind"] != "reed" and _crushed.has(p["cell"]):
			node = StringName(String(node) + "_fallen")
		if not meshes.has(node):
			push_error("VegetationLayer: нема вузла %s" % node)
			continue
		if not by_node.has(node):
			by_node[node] = {"list": [], "idx": [], "mesh": meshes[node], "arrays": _arrays_of(meshes[node]),
					"shade": has_shade(node, cast_shadows)}
			_drawn.append(node)
		(by_node[node]["list"] as Array).append({"xf": Transform3D(Basis(Vector3.UP, p["yaw"]).scaled(Vector3.ONE * float(p.get("scale", 1.0))), p["pos"]), "rgb": Color.WHITE})
		(by_node[node]["idx"] as Array).append(i)
	var by_atlas: Dictionary = {}  ## атлас -> Array[entry]
	for node: StringName in by_node:
		var e: Dictionary = by_node[node]
		var atlas: Texture2D = ((e["mesh"] as Mesh).surface_get_material(0) as BaseMaterial3D).albedo_texture
		if not by_atlas.has(atlas):
			by_atlas[atlas] = []
		e["arrays"] = (e["arrays"] as Array)[0]
		(by_atlas[atlas] as Array).append(e)
	var k: int = 0
	for atlas: Texture2D in by_atlas:
		var entries: Array = by_atlas[atlas]
		var total: int = 0
		for e: Dictionary in entries:
			total += (e["list"] as Array).size()
		var batch: FoliageBatch = FoliageBatch.create(total)
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, batch.merge(entries, true), [], {}, FoliageBatch.custom_flags())
		var plant := ShaderMaterial.new()
		plant.shader = _batch_shader(&"plant")
		plant.set_shader_parameter("albedo_tex", atlas)
		plant.set_shader_parameter("inst_data", batch.texture)
		m.surface_set_material(0, plant)
		# Пляма затінення — друга поверхня, лише в моделей, що її мають; номери екземплярів ті самі.
		var shade_entries: Array = []
		for e: Dictionary in entries:
			if e["shade"] and _arrays_of(e["mesh"]).size() > 1:
				shade_entries.append({"arrays": _arrays_of(e["mesh"])[1], "list": e["list"], "first": e["first"]})
		if not shade_entries.is_empty():
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, batch.merge(shade_entries, false), [], {}, FoliageBatch.custom_flags())
			var shade := ShaderMaterial.new()
			shade.shader = _batch_shader(&"shade")
			shade.set_shader_parameter("albedo_tex", atlas)
			shade.set_shader_parameter("cast", 1.0 if cast_shadows else 0.0)
			shade.set_shader_parameter("inst_data", batch.texture)
			m.surface_set_material(1, shade)
		batch.texture.update(batch.image)
		for e: Dictionary in entries:
			var idx: Array = e["idx"]
			for j in idx.size():
				_slot_batch[idx[j]] = batch
				_slot_id[idx[j]] = int(e["first"]) + j
		var mi := MeshInstance3D.new()
		mi.name = "Plants_%d" % k
		k += 1
		mi.mesh = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Картки розгортаються в шейдері, тож AABB меша не містить країв пучків.
		mi.extra_cull_margin = 0.6
		add_child(mi)
	_refade()


## Рослини над юнітом: у злитому мейші гаснуть, а їхні напівпрозорі двійники — по вузлу бібліотеки на
## MultiMesh (їх лише кілька, і лише поки юніт стоїть під кроною).
func _refade() -> void:
	for ch in get_children():
		if String(ch.name).ends_with("_faded"):
			ch.free()
	if placements.is_empty():
		return
	var meshes: Dictionary = _meshes_of(_season)
	var groups: Dictionary = {}
	var touched: Dictionary = {}
	for i in placements.size():
		var p: Dictionary = placements[i]
		var fallen: bool = p["kind"] != "reed" and _crushed.has(p["cell"])
		var faded: bool = not fallen and _covers(p)
		var batch: FoliageBatch = _slot_batch[i]
		if batch != null:
			batch.set_alive(_slot_id[i], not faded)
			touched[batch] = true
		if faded and meshes.has(p["node"]):
			if not groups.has(p["node"]):
				groups[p["node"]] = []
			(groups[p["node"]] as Array).append(p)
	for batch: FoliageBatch in touched:
		batch.upload()
	for node: StringName in groups:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		var mkey: Array = [_season, node, true, cast_shadows]
		if not _ready_meshes.has(mkey):
			_ready_meshes[mkey] = veg_mesh(meshes[node], FADE_ALPHA, FADE_FLOOR if _season == &"late" else 0.0, cast_shadows, false)
		mm.mesh = _ready_meshes[mkey]
		var list: Array = groups[node]
		mm.instance_count = list.size()
		for i in list.size():
			var p: Dictionary = list[i]
			mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, p["yaw"]).scaled(Vector3.ONE * float(p.get("scale", 1.0))), p["pos"]))
			mm.set_instance_color(i, Color(1, 1, 1, FADE_ALPHA))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s_faded" % node
		mmi.multimesh = mm
		# §8: сонце кидає тінь лише на юнітів.
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)


## Масиви поверхонь вузла бібліотеки (0 — рослина, 1 — пляма): спільні на процес.
static func _arrays_of(mesh: Mesh) -> Array:
	if not _surface_arrays.has(mesh):
		var out: Array = []
		for s in mesh.get_surface_count():
			out.append(mesh.surface_get_arrays(s))
		_surface_arrays[mesh] = out
	return _surface_arrays[mesh]


## Шейдери злитого меша: ті самі veg.gdshader (+ тіло з veg_body.gdshaderinc) і veg_shade.gdshader, але
## тон, масштаб картки й видимість екземпляра беруться з таблиці батча (FoliageBatch) за номером у
## CUSTOM0.x, а не з матриці й кольору екземпляра MultiMesh.
static func _batch_shader(kind: StringName) -> Shader:
	if _batch_shaders.has(kind):
		return _batch_shaders[kind]
	var code: String
	if kind == &"plant":
		var body: String = (load("res://assets/props/vegetation/veg_body.gdshaderinc") as ShaderInclude).code
		body = _replace(body, [
				["varying flat float no_floor;", "varying flat float no_floor;\n" + FoliageBatch.glsl_decl()],
				["inst_tone = dot(INSTANCE_CUSTOM.rgb, INSTANCE_CUSTOM.rgb) > 0.0 ? INSTANCE_CUSTOM.rgb : vec3(1.0);",
						FoliageBatch.glsl_fetch() + "\n\tinst_tone = batch_a.rgb;\n\tCOLOR.a *= batch_a.a;"],
				["float s = length(MODEL_MATRIX[0].xyz);", "float s = batch_scale;"]])
		code = _replace((load("res://assets/props/vegetation/veg.gdshader") as Shader).code, [
				['#include "res://assets/props/vegetation/veg_body.gdshaderinc"', body]])
	else:
		code = _replace((load("res://assets/props/vegetation/veg_shade.gdshader") as Shader).code, [
				["uniform float cast = 0.0;", "uniform float cast = 0.0;\n" + FoliageBatch.glsl_decl()],
				["vec3 centre = MODEL_MATRIX[3].xyz;", FoliageBatch.glsl_fetch(true) + "\n\tvec3 centre = batch_origin;"]])
	var sh := Shader.new()
	sh.code = code
	_batch_shaders[kind] = sh
	return sh


## Заміна рядків шейдера; рядок, що зник із джерела, — помилка навіть у релізі: злитий меш без неї
## мовчки малював би рослини без таблиці.
static func _replace(code: String, pairs: Array) -> String:
	for pair: Array in pairs:
		if not code.contains(pair[0]):
			push_error("VegetationLayer: у шейдері рослинності немає рядка «%s» — злитий шейдер не зібрано" % pair[0])
			continue
		code = code.replace(pair[0], pair[1])
	return code


static func _meshes_of(season: StringName) -> Dictionary:
	if _lib_meshes.has(season):
		return _lib_meshes[season]
	var meshes: Dictionary = {}
	for group: String in ["bank", "meadow", "yard"]:
		var scene := load(LIB % [group, season]) as PackedScene
		if scene == null:
			continue
		var lib: Node3D = scene.instantiate()
		for mi: MeshInstance3D in lib.find_children("*", "MeshInstance3D", true, false):
			meshes[StringName(mi.name)] = mi.mesh
		lib.free()
	_lib_meshes[season] = meshes
	return meshes


## Копія меша вузла рослинності з матеріалами гри: поверхня 0 — рослина (veg.gdshader; над юнітом —
## veg_fade_depth з next_pass veg_fade, пріоритети PropLayer.FADE_DEPTH_PRIORITY і +1), поверхня 1 —
## пляма затінення (veg_shade.gdshader). fade < 0 — звичайний вигляд; fade_floor — нижня межа
## альфи голої крони дерев; cast — пляма витягується в тінь від сонця. Атлас — albedo_tex матеріалу GLB.
static func veg_mesh(src: Mesh, fade: float = -1.0, fade_floor: float = 0.0, cast: bool = false, with_shade: bool = true) -> Mesh:
	var tex: Texture2D = (src.surface_get_material(0) as BaseMaterial3D).albedo_texture
	var sm := ShaderMaterial.new()
	sm.set_shader_parameter("albedo_tex", tex)
	if fade >= 0.0:
		sm.shader = load("res://assets/props/vegetation/veg_fade_depth.gdshader")
		sm.render_priority = PropLayer.FADE_DEPTH_PRIORITY
		var col := ShaderMaterial.new()
		col.shader = load("res://assets/props/vegetation/veg_fade.gdshader")
		col.set_shader_parameter("albedo_tex", tex)
		col.render_priority = PropLayer.FADE_DEPTH_PRIORITY + 1
		for m: ShaderMaterial in [sm, col]:
			m.set_shader_parameter("fade_floor", fade_floor)
		sm.next_pass = col
	else:
		sm.shader = load("res://assets/props/vegetation/veg.gdshader")
	var mesh: Mesh = src.duplicate()
	if not with_shade and mesh.get_surface_count() > 1:
		# Пляма затінення вже в злитому мейші: двійник над юнітом малює лише рослину, інакше пляма темнішала б удвічі.
		var plant := ArrayMesh.new()
		plant.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, src.surface_get_arrays(0))
		mesh = plant
	mesh.surface_set_material(0, sm)
	if with_shade and mesh.get_surface_count() > 1:
		var shade := ShaderMaterial.new()
		shade.shader = load("res://assets/props/vegetation/veg_shade.gdshader")
		shade.set_shader_parameter("albedo_tex", tex)
		shade.set_shader_parameter("cast", 1.0 if cast else 0.0)
		mesh.surface_set_material(1, shade)
	return mesh
