class_name Surroundings
extends RefCounted
## Світ довкола дошки (docs/art/surroundings-research.md):
## намальоване автором кільце outer:, тонка червона лінія на краю дошки, легке затемнення поза
## нею й серпанок далі. Суто вигляд: core/ кільця не бачить, юніт туди не ступає, дотик поза
## дошкою нічого не вибирає (Board.in_bounds).

## Серпанок за евклідовою відстанню від прямокутника дошки (клітинки): чисто до 3, повний на 11 —
## за клітинку до краю кільця, бо край кільця видно на будь-якому віддаленні. Ті самі числа — у
## ground.gdshader і water.gdshader (surround_*), міняти разом.
const HAZE_START: float = 3.0
const HAZE_FULL: float = 11.0
## Колір серпанку, лінійний: холодний, світліший за мокру землю на 8–15 L* (бриф, P1 і M).
const HAZE_COLOR: Color = Color(0.10, 0.135, 0.155)
## Яскравість ×0.8 і насиченість ×0.65 — лише разом із серпанком, тією самою кривою (grade()):
## біля краю земля поза дошкою та сама, що й на дошці, і межу позначає тільки лінія.
const GRADE_LUMA: float = 0.8
const GRADE_SAT: float = 0.65
## Межа гри: суцільна лінія 0.28 % висоти кадру (3 px на 1080p, 2–4 px), назовні від краю.
const LINE_COLOR: Color = Color(0.38, 0.015, 0.012)
const LINE_ALPHA: float = 0.9
const LINE_FRAC: float = 0.0028
## Заслін у кольорі серпанку — до 48 клітинок від дошки: кут кадру 20:9 на найбільшому
## віддаленні сягає 34.8 клітинки.
const SKIRT_REACH: float = 48.0


## Густота меша кільця, квадів на клітинку (бриф: 17k трикутників замість 169k за густоти дошки):
## перша клітинка за краєм — як дошка, щоб на межі не було сходинки; до 6 клітинок — 2 (4 м),
## далі — 1 (8 м), там серпанок уже ≥ 50 % і гранування не видно. Смуга — за Чебишовим.
const BAND_FINE: int = 1
const BAND_MID: int = 6
const MID_QUADS: int = 2
const FAR_QUADS: int = 1

const _SKIRT_SHADER: Shader = preload("res://game/battle/shaders/haze_skirt.gdshader")


## Числа світу довкола дошки — у матеріал землі чи води (surroundings.gdshaderinc).
static func apply(mat: ShaderMaterial, size: Vector2i) -> void:
	mat.set_shader_parameter("surround", true)
	mat.set_shader_parameter("board_size", Vector2(size))
	mat.set_shader_parameter("haze_color", Vector3(HAZE_COLOR.r, HAZE_COLOR.g, HAZE_COLOR.b))
	mat.set_shader_parameter("haze_range", Vector2(HAZE_START, HAZE_FULL))
	mat.set_shader_parameter("grade_params", Vector2(GRADE_LUMA, GRADE_SAT))
	mat.set_shader_parameter("line_color", Vector4(LINE_COLOR.r, LINE_COLOR.g, LINE_COLOR.b, LINE_ALPHA))
	mat.set_shader_parameter("line_frac", LINE_FRAC)


## Заслін: один квадрат кольору серпанку під землею, до SKIRT_REACH клітинок від дошки. Земля
## на краю кільця вже повністю в серпанку, тож шва між ними не видно.
static func skirt(size: Vector2i, y: float) -> MeshInstance3D:
	var plane := PlaneMesh.new()
	plane.size = Vector2(size) + Vector2.ONE * (2.0 * SKIRT_REACH)
	var mat := ShaderMaterial.new()
	mat.shader = _SKIRT_SHADER
	mat.set_shader_parameter("color", Vector3(HAZE_COLOR.r, HAZE_COLOR.g, HAZE_COLOR.b))
	var mi := MeshInstance3D.new()
	mi.name = "HazeSkirt"
	mi.mesh = plane
	mi.material_override = mat
	mi.position = Vector3((size.x - 1) * 0.5, y, (size.y - 1) * 0.5)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Квадів на клітинку для клітинки світу (координати дошки).
static func quads_for(cell: Vector2i, size: Vector2i, board_quads: int) -> int:
	var dt: int = maxi(maxi(-cell.x, cell.x - size.x + 1), maxi(-cell.y, cell.y - size.y + 1))
	if dt <= BAND_FINE:
		return board_quads
	return MID_QUADS if dt <= BAND_MID else FAR_QUADS


## Меш землі світу: клітинка за клітинкою, кожна — сітка n×n квадів своєї смуги, вершини відносно
## центру дошки (там стоїть вузол землі). Вершина дрібної клітинки на ребрі з грубшою сусідкою несе
## кінці грубого ребра (UV, UV2) і позначку COLOR.a = 1: шейдер бере висоту з того самого ребра,
## тож Т-з'єднання не дає щілини.
static func ground_mesh(size: Vector2i, ring: int, board_quads: int) -> ArrayMesh:
	var centre := Vector2(size - Vector2i.ONE) * 0.5
	var verts := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var lo := -ring
	for cy in range(lo, size.y + ring):
		for cx in range(lo, size.x + ring):
			var n: int = quads_for(Vector2i(cx, cy), size, board_quads)
			# Сусід поза світом — як сама клітинка: там ребро нічого не стикує.
			var side := func(d: Vector2i) -> int:
				var c := Vector2i(cx, cy) + d
				if c.x < lo or c.y < lo or c.x >= size.x + ring or c.y >= size.y + ring:
					return n
				return quads_for(c, size, board_quads)
			var up: int = side.call(Vector2i(0, -1))
			var down: int = side.call(Vector2i(0, 1))
			var left: int = side.call(Vector2i(-1, 0))
			var right: int = side.call(Vector2i(1, 0))
			var o := Vector2(cx - 0.5, cy - 0.5) - centre
			var base: int = verts.size()
			for j in n + 1:
				for i in n + 1:
					var f := Vector2(float(i) / n, float(j) / n)
					var p: Vector2 = o + f
					verts.append(Vector3(p.x, 0.0, p.y))
					var snap := 0.0
					if j == 0 and up < n:
						snap = _snap(f.x, up, o, Vector2(1, 0), Vector2.ZERO, uv, uv2)
					elif j == n and down < n:
						snap = _snap(f.x, down, o, Vector2(1, 0), Vector2(0, 1), uv, uv2)
					elif i == 0 and left < n:
						snap = _snap(f.y, left, o, Vector2(0, 1), Vector2.ZERO, uv, uv2)
					elif i == n and right < n:
						snap = _snap(f.y, right, o, Vector2(0, 1), Vector2(1, 0), uv, uv2)
					else:
						uv.append(p)
						uv2.append(p)
					colors.append(Color(0.0, 0.0, 0.0, snap))
			for j in n:
				for i in n:
					var a: int = base + j * (n + 1) + i
					indices.append_array([a, a + 1, a + n + 1, a + 1, a + n + 2, a + n + 1])
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	var tangents := PackedFloat32Array()
	for _v in verts.size():
		tangents.append_array([1.0, 0.0, 0.0, 1.0])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Кінці грубого ребра (m квадів) довкола частки s уздовж осі along; повертає позначку 1.
static func _snap(s: float, m: int, o: Vector2, along: Vector2, edge: Vector2, uv: PackedVector2Array, uv2: PackedVector2Array) -> float:
	var k: int = mini(floori(s * m), m - 1)
	var a: Vector2 = o + edge + along * (float(k) / m)
	uv.append(a)
	uv2.append(a + along / float(m))
	return 1.0


## Відстань (клітинки) від прямокутника дошки, евклідова: кути заокруглені, діагонального шва нема.
## Межа дошки — краї клітинок -0.5 і W-0.5; усередині 0.
static func board_distance(p: Vector2, size: Vector2i) -> float:
	var half := Vector2(size) * 0.5
	var q: Vector2 = (p - (half - Vector2(0.5, 0.5))).abs() - half
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length()


static func haze(d: float) -> float:
	return smoothstep(HAZE_START, HAZE_FULL, d)


static func grade(d: float) -> float:
	return haze(d)


## Дошка разом із кільцем однією сіткою (W+2m)×(H+2m): усередині — живі види дошки (підірваний
## міст теж), довкола — кільце автора. Без кільця — сама дошка.
static func world_board(board: Board, map: MapData) -> Board:
	var m: int = ring_of(map)
	if m == 0:
		return board
	var w := Board.create(board.width + 2 * m, board.height + 2 * m, board.ground_state)
	for y in w.height:
		for x in w.width:
			var p := Vector2i(x - m, y - m)
			w.set_kind(Vector2i(x, y), board.kind_at(p) if board.in_bounds(p) else map.outer_kind_at(p))
	return w


## Підтипи покриття світу, той самий порядок, що й world_board.
static func world_surface(map: MapData) -> PackedByteArray:
	var m: int = ring_of(map)
	if m == 0:
		return map.surface if map != null else PackedByteArray()
	var ow: int = map.width + 2 * m
	var out := PackedByteArray()
	out.resize(ow * (map.height + 2 * m))
	for i in out.size():
		var p := Vector2i(i % ow - m, i / ow - m)
		if p.x >= 0 and p.y >= 0 and p.x < map.width and p.y < map.height:
			out[i] = map.surface_at(p)
		elif i < map.outer_surface.size() and map.outer_surface[i] != MapData.OUTER_HOLE:
			out[i] = map.outer_surface[i]
	return out


## Ширина кільця карти; 0, коли кільця нема чи воно не тієї форми.
static func ring_of(map: MapData) -> int:
	if map == null or map.outer_margin <= 0:
		return 0
	var m: int = map.outer_margin
	return m if map.outer_tiles.size() == (map.width + 2 * m) * (map.height + 2 * m) else 0
