extends GutTest
## Дорога — власна геометрія, незалежна від сітки: осьова лінія
## зі скелета клітинок ROAD/BRIDGE, ширина за типом і товщиною смуги, кути — дуги. Лише вигляд:
## правила й шляхи читають клітинки, тож тут перевіряється тільки сама форма.

const _MAPS: Array[String] = ["res://maps/river.tres", "res://maps/crossroads.tres", "res://maps/ridge.tres"]
const _TILE_M: float = 8.0

var _cache: Dictionary = {}


func _bake(path: String) -> TerrainHeight:
	if not _cache.has(path):
		var m: MapData = load(path)
		_cache[path] = TerrainHeight.bake(m.to_board(), 0, m.name_key.hash(), m.surface)
	return _cache[path]


func _board(path: String) -> Board:
	return (load(path) as MapData).to_board()


static func _is_road(b: Board, c: Vector2i) -> bool:
	if not b.in_bounds(c):
		return false
	var k: int = b.kind_at(c)
	return k == Terrain.Kind.ROAD or k == Terrain.Kind.BRIDGE or k == Terrain.Kind.BRIDGE_DESTROYED


## Відстань від точки до найближчої осьової лінії (клітинки).
static func _dist_to_lines(rc: RoadCourse, p: Vector2) -> float:
	var best := 1e9
	for pts in rc.lines:
		for i in pts.size() - 1:
			best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1])))
	return best


func test_every_map_has_a_road_course() -> void:
	for path in _MAPS:
		var rc: RoadCourse = _bake(path).roads
		assert_not_null(rc, path)
		if rc != null:
			assert_gt(rc.lines.size(), 0, path)


## Правило читаності: кожна клітинка ROAD — під дорогою: вісь не далі 0.6 клітинки від її центру
## або покриття ≥ 25 % клітинки (широка смуга, де вісь іде посередині).
func test_every_road_cell_is_under_the_drawn_road() -> void:
	for path in _MAPS:
		_assert_cells_covered(_board(path), _bake(path).roads, path)


func _assert_cells_covered(b: Board, rc: RoadCourse, label: String) -> void:
	if rc == null:
		fail_test(label)
		return
	var img: Image = rc.rasterise()[0]
	for y in b.height:
		for x in b.width:
			var c := Vector2i(x, y)
			if b.kind_at(c) != Terrain.Kind.ROAD:
				continue
			var d: float = _dist_to_lines(rc, Vector2(c))
			var cov: float = _coverage(rc, img, c)
			assert_true(d < 0.6 or cov >= 0.25, "%s: клітинка %s — вісь за %.2f, покриття %.0f %%" % [label, c, d, cov * 100.0])


## Частка клітинки під дорогою (d < 0) за 8×8 відліками.
static func _coverage(rc: RoadCourse, img: Image, c: Vector2i) -> float:
	var hit := 0
	for j in 8:
		for i in 8:
			if rc.d_from(img, Vector2(c) + Vector2((i + 0.5) / 8.0 - 0.5, (j + 0.5) / 8.0 - 0.5)) < 0.0:
				hit += 1
	return hit / 64.0


static func _synthetic(w: int, h: int, cells: Array[Vector2i]) -> Board:
	var b := Board.create(w, h, Terrain.GroundState.DRY)
	for c in cells:
		b.set_kind(c, Terrain.Kind.ROAD)
	return b


func test_isolated_road_cell_draws_a_patch() -> void:
	var b := _synthetic(9, 9, [Vector2i(4, 4)])
	var rc := RoadCourse.build(b, PackedByteArray(), 2, 7)
	assert_not_null(rc)
	if rc != null:
		assert_gt(rc.lines.size(), 0, "окрема клітинка без лінії")
		_assert_cells_covered(b, rc, "окрема клітинка")


static func _rect(x0: int, y0: int, x1: int, y1: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			out.append(Vector2i(x, y))
	return out


## Компактна область дороги (блок, коротка широка смуга, уся дошка): скелет — точка чи короткий
## відрізок, тож її покриває площа на всю область; кінці широкої смуги теж під покриттям.
func test_compact_road_blocks_are_paved_plazas() -> void:
	var cases: Dictionary = {
		"block2x2": [12, 10, _rect(5, 5, 6, 6)],
		"block3x3": [12, 10, _rect(4, 4, 6, 6)],
		"block4x4": [14, 10, _rect(4, 3, 7, 6)],
		"all_road": [8, 8, _rect(0, 0, 7, 7)],
		"wide3_short": [14, 10, _rect(4, 4, 8, 6)],
		"wide4": [14, 12, _rect(0, 4, 13, 7)],
	}
	for name: String in cases:
		var c: Array = cases[name]
		var b := _synthetic(c[0], c[1], c[2])
		for margin in [0, 2]:
			var rc := RoadCourse.build(b, PackedByteArray(), margin, 7)
			assert_not_null(rc, name)
			if rc != null:
				_assert_cells_covered(b, rc, "%s, відступ %d" % [name, margin])


func test_ring_without_junction_is_a_closed_chain() -> void:
	var cells: Array[Vector2i] = []
	for i in range(2, 9):
		cells.append(Vector2i(i, 2))
		cells.append(Vector2i(i, 8))
	for j in range(3, 8):
		cells.append(Vector2i(2, j))
		cells.append(Vector2i(8, j))
	var b := _synthetic(11, 11, cells)
	var rc := RoadCourse.build(b, PackedByteArray(), 2, 7)
	assert_not_null(rc)
	if rc == null:
		return
	assert_eq(rc.lines.size(), 1, "кільце — один ланцюжок")
	if rc.lines.size() == 1:
		var pts: PackedVector2Array = rc.lines[0]
		assert_lt(pts[0].distance_to(pts[pts.size() - 1]), 1e-3, "ланцюжок замкнений")
	_assert_cells_covered(b, rc, "кільце")


## Смуга в 3 клітинки до краю дошки: площа покриває всі три ряди й доходить до краю.
func test_three_wide_band_is_covered_to_the_board_edge() -> void:
	var cells: Array[Vector2i] = []
	for i in 12:
		for j in range(4, 7):
			cells.append(Vector2i(i, j))
	var b := _synthetic(12, 11, cells)
	var rc := RoadCourse.build(b, PackedByteArray(), 2, 7)
	assert_not_null(rc)
	if rc == null:
		return
	_assert_cells_covered(b, rc, "смуга 3")
	var img: Image = rc.rasterise()[0]
	for j in range(4, 7):
		for x: float in [-0.4, 11.4]:
			assert_lt(rc.d_from(img, Vector2(x, j)), 0.0, "край дошки (%.1f, %d) — під дорогою" % [x, j])


## Растр дороги (d < 0) — одна зв'язна область на кожну зв'язну групу клітинок дороги й мосту.
func test_drawn_road_is_connected_like_the_cells_including_every_bridge_deck() -> void:
	for path in _MAPS:
		var b := _board(path)
		var t := _bake(path)
		var rc: RoadCourse = t.roads
		if rc == null:
			fail_test(path)
			continue
		var img: Image = rc.rasterise()[0]
		var w: int = img.get_width()
		var h: int = img.get_height()
		var comp := PackedInt32Array()
		comp.resize(w * h)
		comp.fill(-1)
		var n := 0
		for k in w * h:
			if comp[k] >= 0 or img.get_pixel(k % w, k / w).r >= 0.0:
				continue
			var stack: Array[int] = [k]
			comp[k] = n
			while not stack.is_empty():
				var q: int = stack.pop_back()
				for dy in [-1, 0, 1]:
					for dx in [-1, 0, 1]:
						var x: int = q % w + dx
						var y: int = q / w + dy
						if x < 0 or y < 0 or x >= w or y >= h:
							continue
						var r: int = y * w + x
						if comp[r] < 0 and img.get_pixel(x, y).r < 0.0:
							comp[r] = n
							stack.append(r)
			n += 1
		# Компонента растра під кожною клітинкою: найближчий піксель дороги до центру.
		var cell_comp: Dictionary = {}
		for y in b.height:
			for x in b.width:
				var c := Vector2i(x, y)
				if not _is_road(b, c):
					continue
				var best := -1
				var best_d := 1e9
				var cx: int = int((x + 0.5) * RoadCourse.PX)
				var cy: int = int((y + 0.5) * RoadCourse.PX)
				for j in range(maxi(cy - 6, 0), mini(cy + 6, h)):
					for i in range(maxi(cx - 6, 0), mini(cx + 6, w)):
						var dd: float = Vector2(i - cx, j - cy).length()
						if comp[j * w + i] >= 0 and dd < best_d:
							best_d = dd
							best = comp[j * w + i]
				cell_comp[c] = best
				assert_true(best >= 0, "%s: під клітинкою %s дороги не намальовано" % [path, c])
		for c: Vector2i in cell_comp:
			for d in Board.DIRS_4:
				if cell_comp.has(c + d):
					assert_eq(cell_comp[c + d], cell_comp[c], "%s: дорога розірвана між %s і %s" % [path, c, c + d])
		# Кожен настил: вісь проходить під ним.
		for g in t.bridge_groups():
			var ctr: Vector2 = g["centre"]
			assert_lt(_dist_to_lines(rc, ctr), 0.75, "%s: вісь оминає міст у %s" % [path, ctr])


## Ширина впоперек осі за растром (метри): від осі в обидва боки до d = 0.
func _width_at(rc: RoadCourse, img: Image, p: Vector2, nrm: Vector2) -> float:
	var total := 0.0
	for sgn: float in [-1.0, 1.0]:
		var s := 0.0
		while s < 1.0 and rc.d_from(img, p + nrm * sgn * s) < 0.0:
			s += 0.0025
		total += s
	return total * _TILE_M


func test_widths_single_lane_town_street_and_variation() -> void:
	for path in _MAPS:
		var b := _board(path)
		var rc: RoadCourse = _bake(path).roads
		if rc == null:
			fail_test(path)
			continue
		var img: Image = rc.rasterise()[0]
		for li in rc.lines.size():
			var pts: PackedVector2Array = rc.lines[li]
			var ratios: Array[float] = []
			for i in range(1, pts.size() - 1):
				var p: Vector2 = pts[i]
				# Біля розвилки промінь перерізу заходить у її замикання — це не ширина.
				if rc.near_node(p) < 2.0 or rc.near_bridge(p) < 1.2:
					continue
				# Переріз крізь тісний поворот вулиці (R < 1.5 півширини) — не ширина.
				if i >= 2 and i + 2 < pts.size() and _circumradius(pts[i - 2], pts[i], pts[i + 2]) * _TILE_M < 1.5 * rc.halfs[li][i]:
					continue
				var tg: Vector2 = (pts[i + 1] - pts[i - 1]).normalized()
				var wm: float = _width_at(rc, img, p, Vector2(-tg.y, tg.x))
				assert_lt(wm, 8.0 + 1e-3, "%s: ширина %.1f м у %s" % [path, wm, p])
				if rc.base_halfs[li][i] * 2.0 < 5.5:
					assert_lt(wm, 0.65 * _TILE_M, "%s: одна смуга %.1f м у %s" % [path, wm, p])
				ratios.append(rc.halfs[li][i] / rc.base_halfs[li][i])
			if ratios.size() >= 12:
				var mean := 0.0
				for r in ratios:
					mean += r
				mean /= ratios.size()
				var v := 0.0
				for r in ratios:
					v += (r - mean) * (r - mean)
				var cv: float = sqrt(v / ratios.size()) / mean
				assert_between(cv, 0.03, 0.15, "%s: CV ширини лінії %d = %.3f" % [path, li, cv])
	# Смуга у 2 клітинки на Crossroads (стовпці 12–13, рядки 9–12) — одна вулиця 6–8 м, не дві.
	var rc: RoadCourse = _bake("res://maps/crossroads.tres").roads
	var img: Image = rc.rasterise()[0]
	for y: float in [10.0, 10.5, 11.0]:
		var p := Vector2(12.5, y)
		assert_lt(_dist_to_lines(rc, p), 0.3, "вісь вулиці посередині смуги у %s" % p)
		var wm: float = _width_at(rc, img, p, Vector2(1, 0))
		assert_between(wm, 6.0, 8.0, "вулиця у %s: %.1f м" % [p, wm])
	var near_lines := 0
	for pts in rc.lines:
		for q in pts:
			if q.x > 11.6 and q.x < 13.4 and q.y > 10.0 and q.y < 11.0:
				near_lines += 1
				break
	assert_eq(near_lines, 1, "у смузі 2 клітинки — одна лінія, а не дві")


## Кожен поворот на 90° у ланцюжку клітинок — дуга радіусом 6–14 м; деінде зламів нема
## (R > 4 м, на вулиці міста R > 3 м).
func test_corners_are_arcs_of_6_to_14_metres() -> void:
	for path in _MAPS:
		var b := _board(path)
		var rc: RoadCourse = _bake(path).roads
		if rc == null:
			fail_test(path)
			continue
		var corners: Array[Vector2] = []
		for y in b.height:
			for x in b.width:
				var c := Vector2i(x, y)
				if not _is_road(b, c):
					continue
				var hn: int = int(_is_road(b, c + Vector2i(1, 0))) + int(_is_road(b, c - Vector2i(1, 0)))
				var vn: int = int(_is_road(b, c + Vector2i(0, 1))) + int(_is_road(b, c - Vector2i(0, 1)))
				# Чистий кут: по одному сусіду на кожній осі й нічого по діагоналі всередині (не смуга 2×2).
				if hn == 1 and vn == 1:
					var dx: int = 1 if _is_road(b, c + Vector2i(1, 0)) else -1
					var dy: int = 1 if _is_road(b, c + Vector2i(0, 1)) else -1
					if not _is_road(b, c + Vector2i(dx, dy)):
						corners.append(Vector2(c))
		for li in rc.lines.size():
			var pts: PackedVector2Array = rc.lines[li]
			for i in range(2, pts.size() - 2):
				if rc.near_node(pts[i]) < 1.0:
					continue
				var r: float = _circumradius(pts[i - 2], pts[i], pts[i + 2]) * _TILE_M
				# Вулиця міста повертає в межах смуги 2 клітинки: радіус бордюру 3–6 м, як у справжньому місті.
				var lim: float = 3.0 if rc.base_halfs[li][i] >= RoadCourse.STREET_HALF_M - 1.0 else 4.0
				assert_gt(r, lim, "%s: злам осі в %s, R = %.1f м" % [path, pts[i], r])
		for c in corners:
			if rc.near_node(c) < 1.6:
				continue
			var best := 1e9
			for pts in rc.lines:
				for i in range(2, pts.size() - 2):
					if pts[i].distance_to(c) < 1.0:
						best = minf(best, _circumradius(pts[i - 2], pts[i], pts[i + 2]) * _TILE_M)
			assert_between(best, 6.0, 14.0, "%s: кут у %s, R = %.1f м" % [path, c, best])


func test_course_is_deterministic() -> void:
	var m: MapData = load("res://maps/river.tres")
	var a := TerrainHeight.bake(m.to_board(), 0, 5, m.surface)
	var b := TerrainHeight.bake(m.to_board(), 0, 5, m.surface)
	assert_eq(a.roads.rasterise()[0].get_data(), b.roads.rasterise()[0].get_data())


static func _circumradius(a: Vector2, b: Vector2, c: Vector2) -> float:
	var ab: float = a.distance_to(b)
	var bc: float = b.distance_to(c)
	var ca: float = c.distance_to(a)
	var cr: float = absf((b - a).cross(c - a))
	return 1e9 if cr < 1e-9 else ab * bc * ca / (2.0 * cr)
