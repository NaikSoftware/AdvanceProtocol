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
				assert_lt(wm, 10.0 + 1e-3, "%s: ширина %.1f м у %s" % [path, wm, p])
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
	# Смуга у 2 клітинки на Crossroads (стовпці 12–13, рядки 9–12) — одна вулиця: проїзна частина 5.4 м і гравійні узбіччя, разом 8–10 м, не дві.
	var rc: RoadCourse = _bake("res://maps/crossroads.tres").roads
	var img: Image = rc.rasterise()[0]
	for y: float in [10.0, 10.5, 11.0]:
		var p := Vector2(12.5, y)
		assert_lt(_dist_to_lines(rc, p), 0.3, "вісь вулиці посередині смуги у %s" % p)
		var wm: float = _width_at(rc, img, p, Vector2(1, 0))
		assert_between(wm, 8.0, 10.0, "вулиця у %s: %.1f м" % [p, wm])
	var near_lines := 0
	for pts in rc.lines:
		for q in pts:
			if q.x > 11.6 and q.x < 13.4 and q.y > 10.0 and q.y < 11.0:
				near_lines += 1
				break
	assert_eq(near_lines, 1, "у смузі 2 клітинки — одна лінія, а не дві")


## Місця, де до дороги примикає польова дорога чи заїзд: ґрунтовий глухий відросток до 8 клітинок.
## Заокруглення такого примикання стягує сусідні дуги, а справжня дорога біля двору чи поля й
## повертає круто, тож вимога дуг 6–14 м тут не діє — вона для доріг, якими їздять наскрізь.
static func _track_joins(m: MapData) -> Array[Vector2]:
	var b: Board = m.to_board()
	var out: Array[Vector2] = []
	for y in b.height:
		for x in b.width:
			var c := Vector2i(x, y)
			if not _is_road(b, c):
				continue
			var nbrs: Array[Vector2i] = []
			for d: Vector2i in Board.DIRS_4:
				if _is_road(b, c + d):
					nbrs.append(c + d)
			if nbrs.size() < 3:
				continue
			for n: Vector2i in nbrs:
				var prev: Vector2i = c
				var cur: Vector2i = n
				for step in 8:
					if b.kind_at(cur) != Terrain.Kind.ROAD or m.surface_at(cur) != MapData.RoadSurface.DIRT:
						break
					var next: Array[Vector2i] = []
					for d: Vector2i in Board.DIRS_4:
						if cur + d != prev and _is_road(b, cur + d):
							next.append(cur + d)
					if next.is_empty():
						out.append(Vector2(c))
						break
					if next.size() > 1:
						break
					prev = cur
					cur = next[0]
	return out


static func _near_any(p: Vector2, pts: Array[Vector2], r: float) -> bool:
	for q in pts:
		if p.distance_to(q) <= r:
			return true
	return false


## Кожен поворот на 90° у ланцюжку клітинок — дуга радіусом 6–14 м, а біля забудови (вулиця містечка)
## — 3–7 м, без «гоночної» петлі; деінде зламів нема (R > 4 м, на вулиці міста й біля забудови
## R > 3 м). Біля примикання польової дороги чи заїзду — див. `_track_joins`.
func test_corners_are_arcs_of_6_to_14_metres() -> void:
	for path in _MAPS:
		var b := _board(path)
		var rc: RoadCourse = _bake(path).roads
		if rc == null:
			fail_test(path)
			continue
		var joins: Array[Vector2] = _track_joins(load(path) as MapData)
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
				if rc.near_node(pts[i]) < 1.0 or _near_any(pts[i], joins, 4.5):
					continue
				var r: float = _circumradius(pts[i - 2], pts[i], pts[i + 2]) * _TILE_M
				# Вулиця міста повертає в межах смуги 2 клітинки: радіус бордюру 3–6 м, як у справжньому місті.
				var lim: float = 3.0 if rc.base_halfs[li][i] >= RoadCourse.STREET_HALF_M - 1.0 or _by_built(b, pts[i]) else 4.0
				assert_gt(r, lim, "%s: злам осі в %s, R = %.1f м" % [path, pts[i], r])
		for c in corners:
			if rc.near_node(c) < 1.6 or _near_any(c, joins, 4.5):
				continue
			var best := 1e9
			for pts in rc.lines:
				for i in range(2, pts.size() - 2):
					if pts[i].distance_to(c) < 1.0:
						best = minf(best, _circumradius(pts[i - 2], pts[i], pts[i + 2]) * _TILE_M)
			if _by_built(b, c):
				assert_between(best, 3.0, 7.0, "%s: кут вулиці в %s, R = %.1f м" % [path, c, best])
			else:
				assert_between(best, 6.0, 14.0, "%s: кут у %s, R = %.1f м" % [path, c, best])


## Забудова (BUILDING, RUBBLE) за ≤ 1 клітинку від клітинки точки p.
static func _by_built(b: Board, p: Vector2) -> bool:
	var c := Vector2i(floori(p.x + 0.5), floori(p.y + 0.5))
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var n: Vector2i = c + Vector2i(dx, dy)
			if b.in_bounds(n) and b.kind_at(n) in [Terrain.Kind.BUILDING, Terrain.Kind.RUBBLE]:
				return true
	return false


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


## Вага розвилки (альфа растра типів) у світовій точці p — найближчий піксель.
static func _jw_at(rc: RoadCourse, p: Vector2) -> float:
	var img: Image = rc.rasterise()[1]
	var i: int = clampi(roundi((p.x + 0.5 + rc._margin) * RoadCourse.PX - 0.5), 0, img.get_width() - 1)
	var j: int = clampi(roundi((p.y + 0.5 + rc._margin) * RoadCourse.PX - 0.5), 0, img.get_height() - 1)
	return img.get_pixel(i, j).a


## Глухий кінець дороги має вагу розвилки (колії там гаснуть, бо u, v обвивають заокруглення),
## середина дороги — ні.
func test_dead_end_cap_gets_junction_weight_and_mid_road_none() -> void:
	var b := _synthetic(15, 9, _rect(3, 4, 11, 4))
	var rc := RoadCourse.build(b, PackedByteArray(), 2, 7)
	assert_not_null(rc)
	if rc == null:
		return
	assert_eq(rc.lines.size(), 1)
	var pts: PackedVector2Array = rc.lines[0]
	var end: Vector2 = pts[pts.size() - 1]
	var dir: Vector2 = (end - pts[pts.size() - 2]).normalized()
	assert_true(rc.is_free_end(end), "кінець окремої дороги — глухий")
	assert_gt(_jw_at(rc, end + dir * (0.5 / _TILE_M)), 0.9, "за 0.5 м за кінцем")
	assert_lt(_jw_at(rc, pts[pts.size() / 2]), 0.05, "посередині дороги")


## Кінці ліній на розвилці не глухі: заокруглення там малює замикання розвилки, а не кінець.
func test_line_ends_at_a_junction_are_not_free() -> void:
	var cells: Array[Vector2i] = _rect(2, 4, 12, 4)
	cells.append_array(_rect(7, 5, 7, 8))
	var rc := RoadCourse.build(_synthetic(15, 11, cells), PackedByteArray(), 2, 7)
	assert_not_null(rc)
	if rc == null:
		return
	var at_node := 0
	var free := 0
	for pts in rc.lines:
		for e in [pts[0], pts[pts.size() - 1]]:
			if rc.near_node(e) < 0.5:
				at_node += 1
				assert_false(rc.is_free_end(e), "кінець у вузлі %s" % e)
			elif rc.is_free_end(e):
				free += 1
	# Наскрізна дорога — одна лінія через вузол, у вузлі кінчається лише відгалуження.
	assert_eq(at_node, 1, "відгалуження кінчається у вузлі")
	assert_eq(free, 3, "три глухі кінці")


## Кінець лінії або у вузлі (~0), або далеко від нього: кінець за 1.0–1.5 клітинки від вузла
## поріг is_free_end рахував би глухим помилково.
func test_no_map_road_end_sits_just_past_the_free_end_threshold() -> void:
	for path in _MAPS:
		var rc: RoadCourse = _bake(path).roads
		if rc == null:
			continue
		for pts in rc.lines:
			for e in [pts[0], pts[pts.size() - 1]]:
				var d: float = rc.near_node(e)
				assert_false(d > 1.0 and d < 1.5, "%s: кінець %s за %.2f клітинки від вузла" % [path, e, d])


## Асфальт переходить у ґрунтівку різко: вага асфальту падає з 1 до 0 у межах 0.25 клітинки вздовж осі
## (раніше гаус розмивав перехід на ~0.8 клітинки — сірий серпанок замість зламаного краю).
func test_asphalt_weight_drops_within_a_fraction_of_a_tile_at_a_join_to_dirt() -> void:
	var surface := PackedByteArray()
	surface.resize(15 * 9)
	for x in range(7, 15):
		surface[4 * 15 + x] = 1
	var rc := RoadCourse.build(_synthetic(15, 9, _rect(3, 4, 11, 4)), surface, 2, 7)
	assert_not_null(rc)
	if rc == null:
		return
	var img: Image = rc.rasterise()[1]
	var j: int = roundi((4.0 + 0.5 + 2) * RoadCourse.PX - 0.5)
	var last_asphalt: float = -1.0
	var first_dirt: float = -1.0
	for i in range(roundi((4.0 + 0.5 + 2) * RoadCourse.PX - 0.5), roundi((9.0 + 0.5 + 2) * RoadCourse.PX - 0.5)):
		var x: float = (i + 0.5) / RoadCourse.PX - 2.5
		var r: float = img.get_pixel(i, j).r
		if r >= 0.95:
			last_asphalt = x
		if r <= 0.05 and first_dirt < 0.0:
			first_dirt = x
	assert_gt(last_asphalt, 4.5, "асфальт доходить до переходу")
	assert_gt(first_dirt, 0.0, "далі — ґрунтівка")
	# Перепад — один крок лінії (0.2 клітинки, від 95 % до 5 % — 0.18); 0.25 лишає запас на піксель растра (0.125).
	assert_lte(first_dirt - last_asphalt, 0.25, "перехід довший за 0.25 клітинки")


## Асфальт — лише проїзна частина: далі за 3.0 м від осі найближчої лінії (крім площ) лежить ґрунтівка-
## узбіччя. Інакше заокруглення розвилок і смуги шириною у 2 клітинки малювались асфальтом на 7–15 м.
func test_asphalt_stays_within_the_carriageway_of_the_nearest_axis() -> void:
	for path in _MAPS:
		var rc: RoadCourse = _bake(path).roads
		if rc == null:
			continue
		var imgs: Array[Image] = rc.rasterise()
		var worst: float = 0.0
		for j in imgs[0].get_height():
			for i in imgs[0].get_width():
				var f: Color = imgs[0].get_pixel(i, j)
				var t: Color = imgs[1].get_pixel(i, j)
				if f.r < 0.0 and t.r > 0.5 and t.a < 0.99:
					worst = maxf(worst, absf(f.g))
		assert_lte(worst, 3.0, "%s: асфальт на %.1f м від осі" % [path, worst])


## Ґрунтівка, що відходить від асфальтової дороги, починається одразу від краю проїзної частини: вздовж
## її осі асфальт не заходить далі за ~0.5 м від краю головної дороги (півширина до 2.7 м) — без язика.
func test_dirt_branch_starts_at_the_asphalt_edge() -> void:
	var checked := 0
	for path in _MAPS:
		var rc: RoadCourse = _bake(path).roads
		if rc == null:
			continue
		var t_img: Image = rc.rasterise()[1]
		var f_img: Image = rc.rasterise()[0]
		for li in rc.lines.size():
			var pts: PackedVector2Array = rc.lines[li]
			var ty: PackedVector3Array = rc.types[li]
			for end in [0, pts.size() - 1]:
				var node: Vector2 = pts[end]
				if rc.near_node(node) > 0.05:
					continue
				# Гілка — ґрунтівка за 1.5 клітинки від вузла.
				var step: int = 1 if end == 0 else -1
				var far: int = clampi(end + step * 8, 0, pts.size() - 1)
				if ty[far].y < 0.5:
					continue
				checked += 1
				var reach: float = 0.0
				var i: int = end
				while i != far:
					var a: Vector2 = pts[i]
					var b: Vector2 = pts[i + step]
					for s in 4:
						var p: Vector2 = a.lerp(b, s / 4.0)
						var px: int = clampi(roundi((p.x + 0.5 + rc._margin) * RoadCourse.PX - 0.5), 0, t_img.get_width() - 1)
						var py: int = clampi(roundi((p.y + 0.5 + rc._margin) * RoadCourse.PX - 0.5), 0, t_img.get_height() - 1)
						if t_img.get_pixel(px, py).r > 0.5 and f_img.get_pixel(px, py).r < 0.0:
							reach = maxf(reach, p.distance_to(node) * _TILE_M)
					i += step
				assert_lte(reach, 3.2, "%s: лінія %d, асфальт заходить у відгалуження на %.1f м від вузла" % [path, li, reach])
	assert_gt(checked, 0, "жодного відгалуження ґрунтівки від вузла")
