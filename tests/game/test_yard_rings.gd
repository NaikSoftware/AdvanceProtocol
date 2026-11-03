extends GutTest
## Двори з воротами: кільце паркану замкнене.

const MAPS: Array[String] = ["river", "crossroads", "ridge"]
## Допуск, на який точка межі двору вважається замкненою секцією чи стіною.
const OPEN_TOL: float = 0.15
var _views: Dictionary = {}


func _props(name: String) -> PropLayer:
	if not _views.has(name):
		var m: MapData = load("res://maps/%s.tres" % name) as MapData
		var view: BoardView = (load("res://game/battle/board_view.tscn") as PackedScene).instantiate()
		add_child(view)
		view.ring_map = m
		view.surface = m.surface
		view.relief_seed = m.name_key.hash()
		view.build(m.to_board())
		_views[name] = view
	return (_views[name] as BoardView).props()


func after_all() -> void:
	for v: BoardView in _views.values():
		v.free()
	_views.clear()


func _dist_seg(q: Vector2, a: Vector2, b: Vector2) -> float:
	return q.distance_to(Geometry2D.get_closest_point_to_segment(q, a, b))


## Секції паркану дворів і стулки воріт як відрізки.
func _segments(props: PropLayer) -> Array:
	var segs: Array = []
	for inst in props.all_instances():
		if int(PropLayer.spec_of(inst["model"]).get("kind", -1)) != PropLayer.Kind.GARDEN_FENCE:
			continue
		var xf: Transform3D = inst["transform"]
		var box: AABB = (PropLayer.model(inst["model"]) as Dictionary)["aabb"]
		var a3: Vector3 = xf * Vector3(box.position.x, 0.0, 0.0)
		var b3: Vector3 = xf * Vector3(box.end.x, 0.0, 0.0)
		segs.append([Vector2(a3.x, a3.z), Vector2(b3.x, b3.z)])
	return segs


## Довжина паркану, що тягнеться від стовпа воріт (далі за кутами, але не крізь самі ворота): ланцюг секцій, з'єднаних кінцями.
func _flank(segs: Array, post: Vector2) -> float:
	var seen: Dictionary = {}
	var front: Array[Vector2] = [post]
	var total := 0.0
	while not front.is_empty():
		var q: Vector2 = front.pop_back()
		for si in segs.size():
			if seen.has(si):
				continue
			for e in 2:
				if ((segs[si] as Array)[e] as Vector2).distance_to(q) < 0.05:
					seen[si] = true
					total += ((segs[si] as Array)[0] as Vector2).distance_to((segs[si] as Array)[1])
					front.append((segs[si] as Array)[1 - e])
					break
	return total


## Ворота не стоять на уламку: з кожного боку від стовпа паркан тягнеться щонайменше GATE_FLANK (за кутом — далі),
## інакше двір читається двома короткими панелями біля воріт, що нічого не обгороджують.
func test_gate_has_a_real_fence_on_both_sides(p = use_parameters(MAPS)) -> void:
	var props: PropLayer = _props(p)
	var segs: Array = _segments(props)
	assert_gt(props._gates.size(), 0, p)
	var short: Array = []
	for g: Dictionary in props._gates:
		var fa: float = _flank(segs, g["a"])
		var fb: float = _flank(segs, g["b"])
		if minf(fa, fb) < PropLayer.GATE_FLANK:
			short.append([g["a"], snappedf(fa, 0.01), snappedf(fb, 0.01)])
	assert_eq(short, [], "%s: ворота біля уламка паркану (стовп, паркан від a, від b)" % p)


## Будівлі й сараї дворів як прямокутники (стіна теж замикає двір).
func _boxes(props: PropLayer) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for inst in props.all_instances():
		var k: int = int(PropLayer.spec_of(inst["model"]).get("kind", -1))
		if k == PropLayer.Kind.STRUCTURE or k == PropLayer.Kind.RUIN or k == PropLayer.Kind.YARD:
			var b: AABB = (inst["transform"] as Transform3D) * ((PropLayer.model(inst["model"]) as Dictionary)["aabb"] as AABB)
			out.append(Rect2(b.position.x, b.position.z, b.size.x, b.size.z))
	return out


## Слід стін будівель і сараїв дворів (без звісу даху й димаря): паркан доходить до нього, але не заходить.
func _buildings(props: PropLayer) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for inst in props.all_instances():
		var k: int = int(PropLayer.spec_of(inst["model"]).get("kind", -1))
		if k == PropLayer.Kind.STRUCTURE or k == PropLayer.Kind.RUIN or k == PropLayer.Kind.YARD:
			out.append(PropLayer.wall_rect(inst))
	return out


## Город не підходить до розриву в паркані: там, де межу двору ніщо не замикає (ні секція чи ворота, ні стіна), грядки
## лишаються не ближче OPEN_SIDE_CLEAR — інакше вони виходять за лінію паркану, а двір читається незамкненим.
func test_garden_keeps_off_open_fence_sides(p = use_parameters(MAPS)) -> void:
	var props: PropLayer = _props(p)
	var segs: Array = _segments(props)
	for g: Dictionary in props._gates:
		segs.append([g["a"], g["b"]])
	var walls: Array[Rect2] = _boxes(props)
	var plots: Array = props._placer.garden_plots
	var worst := INF
	for poly: PackedVector2Array in props._placer.yard_polys:
		for k in poly.size():
			var a: Vector2 = poly[k]
			var b: Vector2 = poly[(k + 1) % poly.size()]
			for j in ceili(a.distance_to(b) / 0.05) + 1:
				var q: Vector2 = a.lerp(b, float(j) * 0.05 / a.distance_to(b))
				var covered := false
				for s: Array in segs:
					covered = covered or _dist_seg(q, s[0], s[1]) < OPEN_TOL
				for r: Rect2 in walls:
					covered = covered or r.grow(OPEN_TOL).has_point(q)
				if covered:
					continue
				for gp: Dictionary in plots:
					var r: Rect2 = gp["rect"]
					var d: Vector2 = Vector2(maxf(maxf(r.position.x - q.x, q.x - r.end.x), 0.0), maxf(maxf(r.position.y - q.y, q.y - r.end.y), 0.0))
					if d.length() < worst:
						worst = d.length()
	gut.p("%s: найближчий город до розриву %.3f" % [p, worst])
	assert_gte(worst, PropLayer.OPEN_SIDE_CLEAR - 1e-3, "%s: город підходить до розриву паркану на %.3f" % [p, worst])



## Скільки довжини сторони кільця (a→b) не замикає ні намальований паркан чи ворота, ні стіна (як у _fence_ring).
func _uncovered(sd: Dictionary, segs: Array, walls: Array[Rect2]) -> float:
	var a: Vector2 = sd["a"]
	var b: Vector2 = sd["b"]
	var open_len := 0.0
	for j in ceili(a.distance_to(b) / 0.05) + 1:
		var q: Vector2 = a.lerp(b, minf(1.0, float(j) * 0.05 / maxf(a.distance_to(b), 1e-6)))
		var covered := false
		for s: Array in segs:
			covered = covered or _dist_seg(q, s[0], s[1]) < 0.06
		for r: Rect2 in walls:
			covered = covered or r.grow(0.15).has_point(q)
		if not covered:
			open_len += 0.05
	return open_len


## Прапорець «сторона відкрита» читає паркан, який справді намальований (після відсіву уламків), а не плановані ходи:
## хід, що його відсіяли, не замикає сторону. Кожна сторона кільця без сусіда: відкрита рівно тоді, коли її
## довжина поза парканом, воротами й стінами більша за 0,1.
func test_open_flag_reads_the_drawn_fence(p = use_parameters(MAPS)) -> void:
	var props: PropLayer = _props(p)
	var segs: Array = _segments(props)
	for g: Dictionary in props._gates:
		segs.append([g["a"], g["b"]])
	var walls: Array[Rect2] = _boxes(props)
	var sides_checked := 0
	for i: int in props._placer.ring_sides:
		for sd: Dictionary in props._placer.ring_sides[i]:
			if int(sd["nb"]) >= 0:
				continue
			sides_checked += 1
			var open_len: float = _uncovered(sd, segs, walls)
			assert_eq(bool(sd["open"]), open_len > 0.1, "%s: двір %d, сторона %s–%s, поза парканом %.2f" % [p, i, sd["a"], sd["b"], open_len])
	assert_gt(sides_checked, 0, p)


## Хід, якого в намальованому паркані нема (відсіяний як уламок), сторону не замикає: з двох ходів лишився один —
## друга половина відкрита; стіна поруч замикає свою частину (стіна 1,5 зі звісом 0,15 → відкрито від 1,05 до 1,35).
func test_open_length_counts_only_drawn_fence() -> void:
	var a := Vector2(0, 0)
	var b := Vector2(2, 0)
	var drawn: Array = [[Vector2(0, 0), Vector2(1, 0)]]
	var none: Array[Rect2] = []
	assert_almost_eq(PropLayer._Placer._open_length(a, b, drawn, none), 1.0 - 0.06, 0.06)
	assert_almost_eq(PropLayer._Placer._open_length(a, b, [], none), 2.0, 0.051)
	var wall: Array[Rect2] = [Rect2(1.5, -1, 1, 2)]
	assert_almost_eq(PropLayer._Placer._open_length(a, b, drawn, wall), 0.25, 0.001)


## Просвіт між руїною й хатою на східній стороні двору River (x = 10,5, між y = 14,47 і 14,72) вужчий за ворота: його
## замикає секція від стіни до стіни (не лише звіс стін), так що двір не лишає проходу з боку дороги. Обидва кінці секції
## стоять на стінах (руїна зверху, хата знизу, стик до хати — не довший за 0,05).
func test_river_ruin_yard_gap_is_closed_by_a_fence_piece() -> void:
	var props: PropLayer = _props("river")
	var ruin := Rect2()
	var house := Rect2()
	for inst in props.all_instances():
		var b: AABB = (inst["transform"] as Transform3D) * ((PropLayer.model(inst["model"]) as Dictionary)["aabb"] as AABB)
		if String(inst["model"]).begins_with("ruin_half_shed"):
			ruin = Rect2(b.position.x, b.position.z, b.size.x, b.size.z)
		elif inst["model"] == &"house_h7" and absf(b.position.x - 9.54) < 0.05:
			house = Rect2(b.position.x, b.position.z, b.size.x, b.size.z)
	assert_gt(ruin.size.x, 0.0, "передумова: руїна на місці")
	assert_gt(house.size.x, 0.0, "передумова: хата на місці")
	var found := 0
	var reach_ruin := 0
	var reach_house := 0
	for sg: Array in _segments(props):
		var a: Vector2 = sg[0]
		var b: Vector2 = sg[1]
		if absf(a.x - 10.5) > 0.03 or absf(b.x - 10.5) > 0.03:
			continue
		for e: Vector2 in [a, b]:
			reach_ruin += 1 if ruin.grow(0.03).has_point(e) else 0
			reach_house += 1 if house.grow(0.05).has_point(e) else 0
		if minf(a.y, b.y) < ruin.end.y + 0.05 and maxf(a.y, b.y) > house.position.y - 0.05 and absf(a.y - b.y) < 0.4:
			found += 1
	assert_gte(reach_ruin, 2, "паркан сходить до руїни знизу й зверху її (кінці секцій на стіні)")
	assert_gte(found, 1, "між руїною й хатою стоїть секція паркану")
	assert_gte(reach_house, 1, "секція доходить до хати")


## Прямі ходи паркану: секції на одній прямій, що стикаються кінцями (в межах 0,03), — один хід; повертає [початок, кінець]
## крайніх точок.
func _runs(segs: Array) -> Array:
	var parent: Array[int] = []
	for i in segs.size():
		parent.append(i)
	var root := func(i: int) -> int:
		while parent[i] != i:
			i = parent[i]
		return i
	for i in segs.size():
		for j in range(i + 1, segs.size()):
			var di: Vector2 = ((segs[i][1] as Vector2) - (segs[i][0] as Vector2)).normalized()
			var dj: Vector2 = ((segs[j][1] as Vector2) - (segs[j][0] as Vector2)).normalized()
			if absf(di.cross(dj)) > 0.05:
				continue
			for ea: Vector2 in segs[i]:
				for eb: Vector2 in segs[j]:
					if ea.distance_to(eb) < 0.03:
						parent[root.call(i)] = root.call(j)
	var by: Dictionary = {}
	for i in segs.size():
		var r: int = root.call(i)
		if not by.has(r):
			by[r] = []
		by[r].append(i)
	var out: Array = []
	for idx: Array in by.values():
		var dir: Vector2 = ((segs[idx[0]][1] as Vector2) - (segs[idx[0]][0] as Vector2)).normalized()
		var lo: Vector2 = segs[idx[0]][0]
		var hi: Vector2 = lo
		for i: int in idx:
			for e: Vector2 in segs[i]:
				lo = e if e.dot(dir) < lo.dot(dir) else lo
				hi = e if e.dot(dir) > hi.dot(dir) else hi
		out.append([lo, hi])
	return out


## Два паралельні ходи паркану від стіни до стіни ближче TWIN_GAP, між якими нічого нема (ні будівлі, ні воріт),
## обгороджують смужку порожньої трави: двір читається двома. Провулок між двома дворами (ходи різних дворів) — не про це:
## тут обидва кінці кожного ходу стоять на стінах.
func test_no_parallel_fence_runs_around_an_empty_strip(p = use_parameters(MAPS)) -> void:
	var props: PropLayer = _props(p)
	var walls: Array[Rect2] = _buildings(props)
	var runs: Array = []
	for r: Array in _runs(_segments(props)):
		var on := true
		for e: Vector2 in r:
			var hit := false
			for w: Rect2 in walls:
				hit = hit or w.grow(0.05).has_point(e)
			on = on and hit
		if on and (r[0] as Vector2).distance_to(r[1]) > 0.2:
			runs.append(r)
	var posts: Array[Vector2] = []
	for g: Dictionary in props._gates:
		posts.append_array([g["a"], g["b"]])
	var bad: Array = []
	for i in runs.size():
		for j in range(i + 1, runs.size()):
			var a0: Vector2 = runs[i][0]
			var a1: Vector2 = runs[i][1]
			var b0: Vector2 = runs[j][0]
			var b1: Vector2 = runs[j][1]
			var ax: int = 0 if absf(a1.x - a0.x) > absf(a1.y - a0.y) else 1
			if absf(a1[1 - ax] - a0[1 - ax]) > 0.03 or absf(b1[1 - ax] - b0[1 - ax]) > 0.03 or absf(b1[ax] - b0[ax]) < 0.1:
				continue
			var gap: float = absf(b0[1 - ax] - a0[1 - ax])
			var lo: float = maxf(minf(a0[ax], a1[ax]), minf(b0[ax], b1[ax]))
			var hi: float = minf(maxf(a0[ax], a1[ax]), maxf(b0[ax], b1[ax]))
			if gap < 0.05 or gap > PropLayer.TWIN_GAP or hi - lo < 0.2:
				continue
			var cross_lo: float = minf(a0[1 - ax], b0[1 - ax])
			var strip := Rect2(Vector2(lo, cross_lo), Vector2(hi - lo, gap)) if ax == 0 else Rect2(Vector2(cross_lo, lo), Vector2(gap, hi - lo))
			strip = strip.grow(-0.02)
			var holds := false
			for r: Rect2 in walls:
				holds = holds or r.intersects(strip)
			for q: Vector2 in posts:
				holds = holds or strip.has_point(q)
			if not holds:
				bad.append([a0, a1, b0, b1])
	assert_eq(bad, [], "%s: паралельні ходи паркану від стіни до стіни навколо порожньої смужки" % p)


## Ні ворота, ні паркан не стоять на асфальті (за полем дороги, яке малює шейдер), у хаті чи руїні та на опорі ЛЕП: це
## перевіряє й кожна карта окремо, але саме ворота тут пересуваються ближче до кута, тож стережемо всі три.
func test_gates_and_fences_keep_off_asphalt_houses_and_poles(p = use_parameters(MAPS)) -> void:
	var props: PropLayer = _props(p)
	var walls: Array[Rect2] = []
	var poles: Array[Rect2] = []
	for inst in props.all_instances():
		var k: int = int(PropLayer.spec_of(inst["model"]).get("kind", -1))
		var b: AABB = (inst["transform"] as Transform3D) * ((PropLayer.model(inst["model"]) as Dictionary)["aabb"] as AABB)
		if k == PropLayer.Kind.STRUCTURE or k == PropLayer.Kind.RUIN:
			walls.append(PropLayer.wall_rect(inst))
		elif k == PropLayer.Kind.POLE:
			poles.append(Rect2(b.position.x, b.position.z, b.size.x, b.size.z))
	var items: Array = _segments(props)
	for g: Dictionary in props._gates:
		items.append([g["a"], g["b"]])
	assert_gt(props._gates.size(), 0, p)
	var bad: Array = []
	for sg: Array in items:
		for t in 11:
			var q: Vector2 = (sg[0] as Vector2).lerp(sg[1], float(t) / 10.0)
			var hit := props.road_edge_m(q) < PropLayer.FENCE_ROAD_INSET * 8.0
			for r: Rect2 in walls:
				hit = hit or r.grow(-0.01).has_point(q)
			for r: Rect2 in poles:
				hit = hit or r.grow(0.02).has_point(q)
			if hit:
				bad.append(q)
				break
	assert_eq(bad, [], "%s: паркан чи ворота на асфальті, у будівлі чи на опорі" % p)


## Жоден кінець секції паркану не висить у повітрі: щонайбільше за FREE_END від стіни (обрис моделі), стовпа
## воріт чи іншої секції. Хід, що доходив лише до обрису з димарем, закінчувався за метр-два від справжньої стіни.
const FREE_END: float = 0.15


func test_no_fence_end_hangs_in_the_air(p = use_parameters(MAPS)) -> void:
	var props: PropLayer = _props(p)
	var segs: Array = _segments(props)
	var walls: Array[Rect2] = _buildings(props)
	var posts: Array[Vector2] = []
	for g: Dictionary in props._gates:
		posts.append_array([g["a"], g["mid"], g["b"]])
	var bad: Array = []
	for i in segs.size():
		for e: Vector2 in segs[i]:
			var ok := false
			for w: Rect2 in walls:
				ok = ok or w.grow(FREE_END).has_point(e)
			for q: Vector2 in posts:
				ok = ok or q.distance_to(e) < FREE_END
			for j in segs.size():
				ok = ok or (j != i and _dist_seg(e, segs[j][0], segs[j][1]) < FREE_END)
			if not ok:
				bad.append(e)
	assert_eq(bad, [], "%s: кінці паркану в повітрі" % p)
