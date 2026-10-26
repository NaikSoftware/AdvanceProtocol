extends GutTest
## Густота меша землі за рельєфом (GroundLod): рівне — 2 трикутники на клітинку, поле висот світу
## зведене до меша, що його малює шейдер, шви між густотами без щілин, меш у бюджеті кадру.

const _MAPS: Array[String] = ["res://maps/river.tres", "res://maps/crossroads.tres", "res://maps/ridge.tres"]
## Трикутників землі на кадрі (CLAUDE.md §8: решта бюджету — на пропси й ліс).
const GROUND_TRIS_MAX: int = 30000

## Запікання світу — секунди на карту, тож одне на карту на весь файл.
static var _cache: Dictionary = {}


func _world(path: String) -> Array:
	if not _cache.has(path):
		var m: MapData = load(path)
		var b: Board = m.to_board()
		var ring: int = Surroundings.ring_of(m)
		var t := TerrainHeight.bake(Surroundings.world_board(b, m), 0, m.name_key.hash(), Surroundings.world_surface(m), ring)
		_cache[path] = [m, Vector2i(b.width, b.height), ring, t]
	return _cache[path]


## Блок відліків однієї клітинки (s = 7) з функції (u, v) -> висота; поле в один рядок 8 відліків.
func _block(f: Callable) -> PackedFloat32Array:
	var h := PackedFloat32Array()
	for j in 8:
		for i in 8:
			h.append(f.call(i / 7.0, j / 7.0))
	return h


## Рівні вкладені, а найгустіший — усі відліки: інакше шов між густотами мав би щілину.
func test_axes_nest_and_end_in_every_sample() -> void:
	var a: Array[PackedInt32Array] = GroundLod.axes(7)
	assert_eq(a.size(), 4)
	assert_eq(a[0], PackedInt32Array([0, 7]))
	assert_eq(a[1], PackedInt32Array([0, 4, 7]))
	assert_eq(a[2], PackedInt32Array([0, 2, 4, 6, 7]))
	assert_eq(a[3], PackedInt32Array([0, 1, 2, 3, 4, 5, 6, 7]))
	for s in range(1, 10):
		var levels: Array[PackedInt32Array] = GroundLod.axes(s)
		assert_eq(levels[-1].size(), s + 1, "s = %d: найгустіший — усі відліки" % s)
		for k in levels.size() - 1:
			for v in levels[k]:
				assert_true(levels[k + 1].has(v), "s = %d: рівень %d вкладений у наступний" % [s, k])


func test_flat_and_planar_cells_take_one_quad() -> void:
	assert_eq(GroundLod.level(_block(func(_u: float, _v: float) -> float: return 0.4), 8, 7, 0, 0, 0.001), 1)
	assert_eq(GroundLod.level(_block(func(u: float, v: float) -> float: return 0.1 * u - 0.05 * v), 8, 7, 0, 0, 0.001), 1,
			"похилу площину два трикутники повторюють точно")


func test_a_curved_cell_takes_the_least_density_that_fits_the_tolerance() -> void:
	# Парабола 4u(1-u) * a: у квад n = 1 хорда лягає на 0, відхилення — a; з n = 2 хорди коротші вдвічі,
	# похибка вчетверо менша (a / 4), з n = 4 — a / 16.
	var a := 0.04
	var bump: Callable = func(u: float, v: float) -> float: return a * 4.0 * u * (1.0 - u)
	var h: PackedFloat32Array = _block(bump)
	assert_eq(GroundLod.level(h, 8, 7, 0, 0, a * 1.01), 1, "допуск більший за відхилення — один квад")
	assert_eq(GroundLod.level(h, 8, 7, 0, 0, a * 0.5), 2)
	assert_eq(GroundLod.level(h, 8, 7, 0, 0, a * 0.2), 4)
	assert_eq(GroundLod.level(h, 8, 7, 0, 0, a * 0.01), 7, "найгустіший рівень — самі відліки")


## Висота, яку малює вершинний шейдер землі, у вершині меша: поле в самій вершині, а на ребрі з
## грубішою клітинкою (COLOR.a = 1) — пряма між кінцями грубого ребра в UV й UV2.
func _vertex_heights(t: TerrainHeight, a: Array, centre: Vector2) -> PackedFloat32Array:
	var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
	var uv2: PackedVector2Array = a[Mesh.ARRAY_TEX_UV2]
	var col: PackedColorArray = a[Mesh.ARRAY_COLOR]
	var out := PackedFloat32Array()
	for i in verts.size():
		var q := Vector2(verts[i].x, verts[i].z) + centre
		if col[i].a > 0.5:
			var p0: Vector2 = uv[i] + centre
			var p1: Vector2 = uv2[i] + centre
			var ab: Vector2 = p1 - p0
			var f: float = clampf((q - p0).dot(ab) / ab.dot(ab), 0.0, 1.0)
			out.append(lerpf(t.at(p0.x, p0.y), t.at(p1.x, p1.y), f))
		else:
			out.append(t.at(q.x, q.y))
	return out


## Трикутники меша за клітинкою (кожен лежить в одній клітинці): ключ — клітинка дошки.
func _buckets(a: Array, centre: Vector2) -> Dictionary:
	var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var out: Dictionary = {}
	for k in range(0, idx.size(), 3):
		var m: Vector3 = (verts[idx[k]] + verts[idx[k + 1]] + verts[idx[k + 2]]) / 3.0
		var c := Vector2i(roundi(m.x + centre.x), roundi(m.z + centre.y))
		if not out.has(c):
			out[c] = []
		(out[c] as Array).append(k)
	return out


## Висота меша в точці p (координати дошки): трикутник, що її накриває, і площина через його вершини.
func _mesh_y(a: Array, buckets: Dictionary, hs: PackedFloat32Array, centre: Vector2, p: Vector2) -> float:
	var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var q: Vector2 = p - centre
	var home := Vector2i(roundi(p.x), roundi(p.y))
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			for k: int in buckets.get(home + Vector2i(dx, dy), []):
				var v0: Vector3 = verts[idx[k]]
				var v1: Vector3 = verts[idx[k + 1]]
				var v2: Vector3 = verts[idx[k + 2]]
				var d: float = (v1.z - v2.z) * (v0.x - v2.x) + (v2.x - v1.x) * (v0.z - v2.z)
				var l0: float = ((v1.z - v2.z) * (q.x - v2.x) + (v2.x - v1.x) * (q.y - v2.z)) / d
				var l1: float = ((v2.z - v0.z) * (q.x - v2.x) + (v0.x - v2.x) * (q.y - v2.z)) / d
				var l2: float = 1.0 - l0 - l1
				if l0 >= -1e-4 and l1 >= -1e-4 and l2 >= -1e-4:
					return l0 * hs[idx[k]] + l1 * hs[idx[k + 1]] + l2 * hs[idx[k + 2]]
	return NAN


## Поле висот — те, що малює меш: пропс, юніт і вода на ньому не висять і не тонуть. Допуск 0.004 (3 см) —
## лише злам поверхні меша всередині клітинки відліків, де поле білінійне, а меш кусково-лінійний.
func test_height_field_lies_on_the_drawn_mesh() -> void:
	for path: String in _MAPS:
		var w: Array = _world(path)
		var size: Vector2i = w[1]
		var t: TerrainHeight = w[3]
		var mesh: ArrayMesh = Surroundings.ground_mesh(size, w[2], t.samples, t.bank_cells(), t.mesh_quads())
		var arr: Array = mesh.surface_get_arrays(0)
		var centre := Vector2(size - Vector2i.ONE) * 0.5
		var hs: PackedFloat32Array = _vertex_heights(t, arr, centre)
		var buckets: Dictionary = _buckets(arr, centre)
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		var worst := 0.0
		for _i in 60:
			var p := Vector2(rng.randf_range(-3.0, size.x + 2.0), rng.randf_range(-3.0, size.y + 2.0))
			var y: float = _mesh_y(arr, buckets, hs, centre, p)
			assert_false(is_nan(y), "%s: точка %s поза мешем" % [path, p])
			worst = maxf(worst, absf(y - t.at(p.x, p.y)))
		assert_lte(worst, 0.004, "%s: меш розійшовся з полем висот" % path)


## Шов між клітинками різної густоти: на ребрі висота однакова з обох боків.
func test_mesh_has_no_crack_on_seams_between_densities() -> void:
	var w: Array = _world("res://maps/river.tres")
	var size: Vector2i = w[1]
	var t: TerrainHeight = w[3]
	var quads: Dictionary = t.mesh_quads()
	var mesh: ArrayMesh = Surroundings.ground_mesh(size, w[2], t.samples, t.bank_cells(), quads)
	var arr: Array = mesh.surface_get_arrays(0)
	var centre := Vector2(size - Vector2i.ONE) * 0.5
	var hs: PackedFloat32Array = _vertex_heights(t, arr, centre)
	var buckets: Dictionary = _buckets(arr, centre)
	var seams := 0
	var worst := 0.0
	for c: Vector2i in quads:
		var right := Vector2i(c.x + 1, c.y)
		if not quads.has(right) or quads[right] == quads[c]:
			continue
		seams += 1
		# Ребро між c і правою сусідкою: x = c.x + 0.5; точки уздовж нього (не вершини решіток).
		for f in [0.13, 0.37, 0.61, 0.89]:
			var e := Vector2(c.x + 0.5, c.y - 0.5 + f)
			var l: float = _mesh_y(arr, buckets, hs, centre, e - Vector2(1e-5, 0.0))
			var r: float = _mesh_y(arr, buckets, hs, centre, e + Vector2(1e-5, 0.0))
			if not is_nan(l) and not is_nan(r):
				worst = maxf(worst, absf(l - r))
		if seams >= 40:
			break
	assert_gt(seams, 0, "на Річці є шви між різними густотами")
	assert_lte(worst, 0.0001, "щілина на шві між густотами")


## Меш землі на кадрі — до 30 тис. трикутників на найгіршій карті разом із кільцем і майданчиками
## будівель (меш добирається після них), що лишає решту бюджету кадру пропсам і лісу.
func test_ground_mesh_with_pads_fits_the_frame_budget() -> void:
	for path: String in _MAPS:
		var m: MapData = load(path)
		var view: BoardView = (preload("res://game/battle/board_view.tscn") as PackedScene).instantiate()
		add_child_autofree(view)
		view.relief_seed = m.name_key.hash()
		view.ring_map = m
		view.build(m.to_board())
		var ground: GroundSurface = null
		for child in view.get_children():
			if child is GroundSurface:
				ground = child
		var tris: int = (ground.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		assert_lte(tris, GROUND_TRIS_MAX, "%s: земля %d трикутників" % [path, tris])
		gut.p("%s: земля %d трикутників" % [path, tris])


## Майданчик на схилі змінює поле після зведення до меша: меш добирається в зачеплених клітинках
## (GroundSurface.refit), і висота, на якій стоять пропси, лишається на ньому.
func test_pad_on_a_slope_refits_the_mesh_to_the_field() -> void:
	var m: MapData = load("res://maps/ridge.tres")
	var b: Board = m.to_board()
	var ring: int = Surroundings.ring_of(m)
	var world: Board = Surroundings.world_board(b, m)
	var t := TerrainHeight.bake(world, 0, m.name_key.hash(), Surroundings.world_surface(m), ring)
	var size := Vector2i(b.width, b.height)
	# Найкрутіше місце дошки: там майданчик урізається найглибше.
	var steepest := Vector2i.ZERO
	var best := 0.0
	for y in range(2, size.y - 2):
		for x in range(2, size.x - 2):
			var d: float = absf(t.at(x + 0.4, y) - t.at(x - 0.4, y)) + absf(t.at(x, y + 0.4) - t.at(x, y - 0.4))
			if t.at(x, y) > TerrainHeight.WATER_LEVEL and d > best:
				best = d
				steepest = Vector2i(x, y)
	var before: int = t.revision
	t.clear_pads()
	t.add_pad(Rect2(steepest.x - 0.4, steepest.y - 0.4, 0.8, 0.8))
	t.finish_pads()
	assert_eq(t.revision, before + 1, "майданчик міняє поле — лічильник росте")
	var cells: Dictionary = t.pad_cells()
	assert_true(cells.has(steepest), "клітинка майданчика позначена")
	assert_lt(cells.size(), 40, "позначені лише клітинки поруч із майданчиком")
	var ground := GroundSurface.new()
	add_child_autofree(ground)
	ground.build(world, 0, Surroundings.world_surface(m), t, ring)
	ground.refit(t, size, ring)
	var arr: Array = ground.mesh.surface_get_arrays(0)
	var centre := Vector2(size - Vector2i.ONE) * 0.5
	var hs: PackedFloat32Array = _vertex_heights(t, arr, centre)
	var buckets: Dictionary = _buckets(arr, centre)
	# У відліках поле й меш мають збігатися (між відліками поле білінійне, меш кусковий: на різкому
	# переході майданчика це злам до 2 см, і він був би й на меші з усіх відліків).
	var worst := 0.0
	for k in 196:
		# Відліки лежать на краях клітинок і через 1/7: x = ціле - 0.5 + a / 7.
		var p := Vector2(steepest.x - 0.5 + (k % 14 - 3) / 7.0, steepest.y - 0.5 + (k / 14 - 3) / 7.0)
		worst = maxf(worst, absf(_mesh_y(arr, buckets, hs, centre, p) - t.at(p.x, p.y)))
	assert_lte(worst, GroundLod.TOL_FIT, "меш під майданчиком і його схилом лежить на полі")
