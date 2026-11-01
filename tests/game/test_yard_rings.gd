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


## Скільки воріт карти може стояти біля уламка паркану: їхня сторона двору коротша за ворота й GATE_FLANK з обох кінців
## (хата, сарай і руїна по периметру) — відрізок між кутом і стіною просто не вміщує ні тих, ні тих.
const CRAMPED_GATES: Dictionary = {"crossroads": 1}


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
	assert_eq(short.size(), CRAMPED_GATES.get(p, 0), "%s: ворота біля уламка паркану (стовп, паркан від a, від b) %s" % [p, short])


## Будівлі й сараї дворів як прямокутники (стіна теж замикає двір).
func _buildings(props: PropLayer) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for inst in props.all_instances():
		var k: int = int(PropLayer.spec_of(inst["model"]).get("kind", -1))
		if k == PropLayer.Kind.STRUCTURE or k == PropLayer.Kind.RUIN or k == PropLayer.Kind.YARD:
			var b: AABB = (inst["transform"] as Transform3D) * ((PropLayer.model(inst["model"]) as Dictionary)["aabb"] as AABB)
			out.append(Rect2(b.position.x, b.position.z, b.size.x, b.size.z))
	return out


## Город не підходить до розриву в паркані: там, де межу двору ніщо не замикає (ні секція чи ворота, ні стіна), грядки
## лишаються не ближче OPEN_SIDE_CLEAR — інакше вони виходять за лінію паркану, а двір читається незамкненим.
func test_garden_keeps_off_open_fence_sides(p = use_parameters(MAPS)) -> void:
	var props: PropLayer = _props(p)
	var segs: Array = _segments(props)
	for g: Dictionary in props._gates:
		segs.append([g["a"], g["b"]])
	var walls: Array[Rect2] = _buildings(props)
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

