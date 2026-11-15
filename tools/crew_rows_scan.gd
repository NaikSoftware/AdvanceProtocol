extends SceneTree
## Перевіряє й підбирає місця розрахунку гармати (рядки `crew` і `crew_travel` у `UnitSilhouettes`).
##   $GODOT --headless --path . -s tools/crew_rows_scan.gd -- check <тип> <набір> <0|1>
##       друкує для кожного бійця рядка: у тайлі й між поручнями, відстань до моделі, закриття з камери;
##   $GODOT --headless --path . -s tools/crew_rows_scan.gd -- scan <тип> <набір> <0|1> <боєць 0|1> <x> <z>
##       до 12 найближчих до (x, z) місць, що проходять усі вимоги.
## Третій аргумент: 1 — похідне положення (станини зведені, на мосту), 0 — розведені станини.
## Вимоги ті самі, що в тестах: боєць у тайлі (у похідному — між поручнями найвужчого з мостів), не ближче
## 0,3 м (0,0375 тайла) до трикутників моделі нижче його зросту, а гармата закриває з камери не більше
## 30 % його вершин за напрямів 0 і 4 на найближчому й найдальшому нахилі.
const Legal := preload("res://tools/crew_body_legal.gd")
const MARGIN: float = 0.0375
const MAX_COVER: float = 0.30
const BRIDGES: Array[String] = ["west", "centre", "east"]


func _init() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	if a.size() < 4:
		push_error("crew_rows_scan: check|scan <тип> <набір> <0|1> ...")
		quit(1)
		return
	var id: int = int(a[1])
	var set_id: int = int(a[2])
	var travel: bool = int(a[3]) == 1
	var ctx: Dictionary = _context(id, set_id, travel)
	if ctx.is_empty():
		push_error("crew_rows_scan: нема моделі типу %d набору %d (похідна: %s)" % [id, set_id, travel])
		quit(1)
		return
	if a[0] == "check":
		var ok: bool = true
		var rows: Array = UnitSilhouettes.crew_rows(id, set_id, travel)
		for fig in rows.size():
			var rep: Dictionary = report(ctx, fig, rows[fig])
			print("CHECK type %d set %d travel %s figure %d row %s: %s" % [id, set_id, travel, fig, rows[fig], rep])
			ok = ok and rep.pass
		quit(0 if ok else 1)
	else:
		var fig: int = int(a[4])
		var at := Vector2(float(a[5]), float(a[6]))
		var found: Array = []
		for xi in range(-23, 24):
			for zi in range(-23, 24):
				var c := Vector3(float(xi) * 0.02, float(zi) * 0.02, 0.0)
				var rep: Dictionary = report(ctx, fig, c)
				if rep.pass:
					found.append([Vector2(c.x, c.y).distance_to(at), c, rep])
		found.sort_custom(func(p: Array, q: Array) -> bool: return p[0] < q[0])
		for f: Array in found.slice(0, 12):
			print("SCAN figure %d  row %s  cover %.2f  clearance %.3f" % [fig, f[1], f[2].cover, f[2].clearance])
		quit()


## Усе потрібне для перевірок гармати: трикутники низу, екранні тіні на напрямах 0 і 4, фігури, поручні.
func _context(id: int, set_id: int, travel: bool) -> Dictionary:
	var gun: ArrayMesh = UnitSilhouettes.travel_mesh(id, set_id) if travel else UnitSilhouettes.model_mesh(id, set_id)
	if gun == null:
		return {}
	var a: Array = gun.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var low: Array = []
	for t in range(0, idx.size(), 3):
		var tri: Array[Vector3] = [v[idx[t]], v[idx[t + 1]], v[idx[t + 2]]]
		if minf(tri[0].y, minf(tri[1].y, tri[2].y)) < UnitSilhouettes.FIGURE_SIZE.y:
			low.append(tri)
	var bufs: Dictionary = {}
	for facing: int in [0, 4]:
		var basis := Basis(Vector3.UP, deg_to_rad(UnitView._degrees_for_facing(facing)))
		var tris := PackedVector3Array()
		for i in idx:
			tris.append(basis * v[i])
		for pitch: float in [IsoCameraRig.PITCH_NEAR_DEG, IsoCameraRig.PITCH_FAR_DEG]:
			bufs[Vector2(facing, pitch)] = Legal.silhouette(tris, pitch)
	var stand: ArrayMesh = UnitSilhouettes.model_mesh(UnitSilhouettes.PLAIN_FIGURE, set_id)
	var kneel: ArrayMesh = UnitSilhouettes.crouch_mesh(set_id)
	var inner: float = 0.5
	if travel:
		for name: String in BRIDGES:
			inner = minf(inner, _rail_inner_face(name))
	if travel:
		print("RAIL inner %.4f" % inner)
	var pts2: Array[Vector2] = []
	for tri: Array in low:
		for p: Vector3 in tri:
			pts2.append(Vector2(p.x, p.z))
	if travel and id == 9:
		# гаубиця попереду в сусідньому тайлі: її станини не ближче за запас (як у тесті)
		var how: ArrayMesh = UnitSilhouettes.travel_mesh(10, set_id)
		for p: Vector3 in ((how.surface_get_arrays(0) as Array)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			if p.y < UnitSilhouettes.FIGURE_SIZE.y:
				pts2.append(Vector2(p.x, p.z - 1.0))
	var bucket: Dictionary = {}
	for p in pts2:
		var k := Vector2i(floori(p.x / MARGIN), floori(p.y / MARGIN))
		if not bucket.has(k):
			bucket[k] = []
		(bucket[k] as Array).append(p)
	return {"low": low, "bucket": bucket, "bufs": bufs, "figures": [stand, kneel if kneel != null else stand], "inner": inner, "travel": travel}


## Відповідь про одного бійця в точці `row` (x, z, поворот): {pass, tile, clearance, cover}.
func report(ctx: Dictionary, fig: int, row: Vector3) -> Dictionary:
	var half := Vector2(UnitSilhouettes.FIGURE_SIZE.x, UnitSilhouettes.FIGURE_SIZE.z) * 0.5
	var rot := Transform2D(-deg_to_rad(row.z), Vector2(row.x, row.y))
	var reach: float = ctx.inner if ctx.travel else 0.5
	var tile: bool = true
	var padded: Array[Vector2] = []
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var p: Vector2 = rot * Vector2(sx * half.x, sz * half.y)
			tile = tile and absf(p.x) < reach and absf(p.y) <= 0.5
			padded.append(rot * Vector2(sx * (half.x + MARGIN), sz * (half.y + MARGIN)))
	var clear: bool = true
	for tri: Array in ctx.low:
		if _tri_overlaps_rect(tri, padded):
			clear = false
			break
	var pts: PackedVector3Array = ((ctx.figures[fig] as ArrayMesh).surface_get_arrays(0) as Array)[Mesh.ARRAY_VERTEX]
	var cover: float = 0.0
	if tile and clear:
		for key: Vector2 in ctx.bufs:
			cover = maxf(cover, Legal.figure_cover(pts, Vector2(row.x, row.y), int(key.x), ctx.bufs[key], key.y))
	# справжня сітка бійця (руки, гвинтівка): у тайлі й між поручнями, і не ближче за запас до моделі
	var basis := Basis(Vector3.UP, deg_to_rad(row.z))
	var worst: float = INF
	if tile and clear and cover <= MAX_COVER:
		for v in pts:
			var w: Vector3 = basis * v + Vector3(row.x, 0.0, row.y)
			if absf(w.x) >= reach or absf(w.z) > 0.5:
				tile = false
				break
			var c := Vector2i(floori(w.x / MARGIN), floori(w.z / MARGIN))
			for dx in range(-1, 2):
				for dz in range(-1, 2):
					for q: Vector2 in ctx.bucket.get(c + Vector2i(dx, dz), []):
						worst = minf(worst, q.distance_to(Vector2(w.x, w.z)))
	clear = clear and worst >= MARGIN - 0.0005
	return {"pass": tile and clear and cover <= MAX_COVER, "tile": tile, "clearance": snappedf(worst, 0.001), "cover": snappedf(cover, 0.01)}


func _rail_inner_face(name: String) -> float:
	var deck_top: float = float(PropLayer.spec_of(StringName("bridge_river_" + name))["deck_top"])
	var root: Node = (load("res://assets/props/bridge_river_%s.glb" % name) as PackedScene).instantiate()
	var inner: float = INF
	var curb: float = INF
	var stack: Array = [[root, Transform3D()]]
	while not stack.is_empty():
		var it: Array = stack.pop_back()
		var n: Node = it[0]
		var xf: Transform3D = it[1] * ((n as Node3D).transform if n is Node3D else Transform3D())
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var m: Mesh = (n as MeshInstance3D).mesh
			for s in m.get_surface_count():
				for v: Vector3 in (m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
					var p: Vector3 = xf * v
					if p.y > deck_top + 0.03 and absf(p.x) > 0.05:
						inner = minf(inner, absf(p.x))
					if p.y > deck_top + 0.005 and absf(p.x) > 0.05:
						curb = minf(curb, absf(p.x))
		for c in n.get_children():
			stack.append([c, xf])
	root.free()
	return inner if inner < INF else curb


## Перетин трикутника (проєкція на XZ) з опуклим чотирикутником: розділова вісь серед нормалей сторін обох.
func _tri_overlaps_rect(tri: Array, rect: Array[Vector2]) -> bool:
	var t: Array[Vector2] = [Vector2(tri[0].x, tri[0].z), Vector2(tri[1].x, tri[1].z), Vector2(tri[2].x, tri[2].z)]
	var axes: Array[Vector2] = []
	for i in 3:
		var e: Vector2 = t[(i + 1) % 3] - t[i]
		axes.append(Vector2(-e.y, e.x))
	axes.append(rect[2] - rect[0])
	axes.append(rect[1] - rect[0])
	for ax in axes:
		if ax.length_squared() < 1e-12:
			continue
		var tmin: float = INF
		var tmax: float = -INF
		for p in t:
			tmin = minf(tmin, ax.dot(p))
			tmax = maxf(tmax, ax.dot(p))
		var rmin: float = INF
		var rmax: float = -INF
		for p in rect:
			rmin = minf(rmin, ax.dot(p))
			rmax = maxf(rmax, ax.dot(p))
		if tmax < rmin or rmax < tmin:
			return false
	return true
