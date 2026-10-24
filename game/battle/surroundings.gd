class_name Surroundings
extends RefCounted
## Світ довкола дошки (docs/art/surroundings-research.md):
## намальоване автором кільце outer:, тонка червона лінія на краю дошки, легке затемнення поза
## нею й імла далі. Суто вигляд: core/ кільця не бачить, юніт туди не ступає, дотик поза
## дошкою нічого не вибирає (Board.in_bounds).

## Обвідна імли за евклідовою відстанню від прямокутника дошки (клітинки): до 2 — нічого, клуби
## з'являються з 2.5 і зливаються до 11, а з `HAZE_CLOSED` (за пів клітинки до краю кільця) верх
## суцільний — край кільця видно на будь-якому віддаленні. Шейдери (surroundings.gdshaderinc)
## власних значень не мають: усі числа ставить `apply()`.
const HAZE_START: float = 2.5
const HAZE_FULL: float = 11.0
const HAZE_CLOSED: float = 11.5
## Колір імли, лінійний: холодний, світліший за мокру землю на 8–15 L*
## (docs/art/surroundings-research.md, P1 і M).
const HAZE_COLOR: Color = Color(0.10, 0.135, 0.155)
## Яскравість ×0.8 і насиченість ×0.65 — лише разом з імлою, тією самою кривою
## (`surround_grade`): біля краю земля поза дошкою та сама, що й на дошці, і межу позначає тільки
## лінія.
const GRADE_LUMA: float = 0.8
const GRADE_SAT: float = 0.65
## Межа гри: суцільна лінія 0.28 % висоти кадру (3 px на 1080p, 2–4 px), назовні від краю.
const LINE_COLOR: Color = Color(0.38, 0.015, 0.012)
const LINE_ALPHA: float = 0.9
const LINE_FRAC: float = 0.0028
## Відступ внутрішнього краю лінії від межі дошки, пікселів кадру: контур «лише рух» на крайній
## клітинці лежить за 0.06 клітинки від межі (`BoardView._CONTOUR_INSET`), а це біля верху кадру на
## найбільшому віддаленні менше за 1.5 px; з відступом 4 px між ними лишається ≥ 3 px землі
## (виміряно на River, зум 20).
const LINE_GAP_PX: float = 4.0
## Заслін у кольорі імли — до 48 клітинок від дошки: кут кадру 20:9 на найбільшому
## віддаленні сягає 34.8 клітинки.
const SKIRT_REACH: float = 48.0


## Густота меша кільця, квадів на клітинку (docs/art/surroundings-research.md): смугами, бо за
## густоти дошки кільце мало б 169 тис. трикутників — увесь бюджет кадру. Перша клітинка за краєм
## — як дошка, щоб на межі не було сходинки; до 6 клітинок — 2 (4 м), далі — 1 (8 м), там імла
## уже ≥ 50 % і гранування не видно. Смуга — за Чебишовим. Клітинки з водою чи берегом — як дошка
## на будь-якій відстані (`quads_for`).
const BAND_FINE: int = 1
const BAND_MID: int = 6
const MID_QUADS: int = 2
const FAR_QUADS: int = 1

## Шум імли: безшовний fBm 4 октави з посиленням 0.7, 512² на 256 м (0.5 м на тексель) —
## повтор у 32 клітинки довший за видиме кільце, найкрупніша октава 48 м. Сід сталий, тож межі
## 5–95 % значень (`FOG_NOISE_RANGE`) виміряно раз для цієї текстури.
const FOG_NOISE_SIZE: int = 512
const FOG_NOISE_SEED: int = 7331
const FOG_NOISE_RANGE: Vector2 = Vector2(0.275, 0.761)

## Межа трикутників кільця на карті: смуги дають 16.8 тис., решту беруть клітинки води й берега
## густоти дошки (River — 25.4 тис., Crossroads — 18.8 тис., Ridge — 17.7 тис.); дошка 26×22
## (56 тис.) разом із кільцем лишається в бюджеті кадру 150 тис.
const RING_TRIS_MAX: int = 26000

const _SKIRT_SHADER: Shader = preload("res://game/battle/shaders/haze_skirt.gdshader")

## Одна текстура на процес: її беруть усі матеріали світу. Генерується одразу, з міпами (~0.1 с
## раз на процес), а не в потоці, як `NoiseTexture2D`: інакше перші кадри бою малюють імлу без
## візерунка, і той проступає на очах. Міпи потрібні: шейдер бере крупні октави з міпа 3.
static var _fog_noise: ImageTexture


## Числа світу довкола дошки — у матеріал землі чи води (surroundings.gdshaderinc).
static func apply(mat: ShaderMaterial, size: Vector2i) -> void:
	mat.set_shader_parameter("surround", true)
	mat.set_shader_parameter("board_size", Vector2(size))
	mat.set_shader_parameter("haze_color", Vector3(HAZE_COLOR.r, HAZE_COLOR.g, HAZE_COLOR.b))
	mat.set_shader_parameter("haze_range", Vector2(HAZE_START, HAZE_FULL))
	mat.set_shader_parameter("haze_closed", HAZE_CLOSED)
	mat.set_shader_parameter("fog_noise", fog_noise())
	mat.set_shader_parameter("fog_noise_range", FOG_NOISE_RANGE)
	mat.set_shader_parameter("grade_params", Vector2(GRADE_LUMA, GRADE_SAT))
	mat.set_shader_parameter("line_color",
			Vector4(LINE_COLOR.r, LINE_COLOR.g, LINE_COLOR.b, LINE_ALPHA))
	mat.set_shader_parameter("line_frac", LINE_FRAC)
	mat.set_shader_parameter("line_gap_px", LINE_GAP_PX)


static func fog_noise() -> ImageTexture:
	if _fog_noise == null:
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.seed = FOG_NOISE_SEED
		# Хвиля найкрупнішої октави — 96 текселів, тобто 48 м.
		n.frequency = 1.0 / 96.0
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.fractal_octaves = 4
		n.fractal_gain = 0.7
		var img: Image = n.get_seamless_image(FOG_NOISE_SIZE, FOG_NOISE_SIZE, false, false, 0.1, true)
		img.generate_mipmaps()
		_fog_noise = ImageTexture.create_from_image(img)
	return _fog_noise


## Заслін: один квадрат суцільної імли під землею, до `SKIRT_REACH` клітинок від дошки. Земля
## на краю кільця вже під суцільною імлою, тож шва між ними не видно.
static func skirt(size: Vector2i, y: float) -> MeshInstance3D:
	var plane := PlaneMesh.new()
	plane.size = Vector2(size) + Vector2.ONE * (2.0 * SKIRT_REACH)
	var mat := ShaderMaterial.new()
	mat.shader = _SKIRT_SHADER
	apply(mat, size)
	var mi := MeshInstance3D.new()
	mi.name = "HazeSkirt"
	mi.mesh = plane
	mi.material_override = mat
	mi.position = Vector3((size.x - 1) * 0.5, y, (size.y - 1) * 0.5)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Квадів на клітинку для клітинки світу (координати дошки). Клітинка з `fine` (вода чи берег,
## `TerrainHeight.bank_cells`) — як дошка: грубий квад над руслом закривав би воду прямими
## ребрами, а вершинні маски берега на ньому не мали б форми.
static func quads_for(cell: Vector2i, size: Vector2i, board_quads: int,
		fine: Dictionary = {}) -> int:
	var dt: int = maxi(maxi(-cell.x, cell.x - size.x + 1), maxi(-cell.y, cell.y - size.y + 1))
	if dt <= BAND_FINE or fine.has(cell):
		return board_quads
	return MID_QUADS if dt <= BAND_MID else FAR_QUADS


## Меш землі світу: клітинка за клітинкою, кожна — n×n квадів своєї смуги, вершини відносно
## центру дошки (там стоїть вузол землі). Вершина дрібної клітинки на ребрі з грубшою сусідкою несе
## кінці грубого ребра (UV, UV2) і позначку COLOR.a = 1: шейдер бере висоту з того самого ребра,
## тож Т-з'єднання не дає щілини.
static func ground_mesh(size: Vector2i, ring: int, board_quads: int,
		fine: Dictionary = {}) -> ArrayMesh:
	var centre := Vector2(size - Vector2i.ONE) * 0.5
	var verts := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var lo := -ring
	for cy in range(lo, size.y + ring):
		for cx in range(lo, size.x + ring):
			var n: int = quads_for(Vector2i(cx, cy), size, board_quads, fine)
			# Сусід поза світом — як сама клітинка: там ребро нічого не стикує.
			var side := func(d: Vector2i) -> int:
				var c := Vector2i(cx, cy) + d
				if c.x < lo or c.y < lo or c.x >= size.x + ring or c.y >= size.y + ring:
					return n
				return quads_for(c, size, board_quads, fine)
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


## Дошка разом із кільцем одним `Board` (W+2m)×(H+2m): усередині — живі види дошки (підірваний
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
