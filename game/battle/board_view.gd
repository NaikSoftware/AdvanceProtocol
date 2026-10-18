class_name BoardView
extends Node3D
## Рендерить дошку: одну суцільну землю (GroundSurface, Phase 5a) і поверх неї
## контури та кола оверлеїв — так тримається бюджет ~100 draw calls (§8).
##
## §3.5: туман ховає ворожих юнітів і їхні міни, ніколи місцевість. Вона
## публічна з першого ходу й на повній яскравості, тож у BoardView свідомо
## немає ані apply_fog, ані будь-якого зв'язку з тайловою видимістю —
## приглушений тайл сам був би підказкою, а контур зони руху, що огинає
## нерозвідану перешкоду, видав би її не гірше за сам тайл. Ховати юнітів —
## робота інших вузлів (Task 2.4, Task 2.10), не цього.

## LAYER_PATH — окремий шар для контуру шляху (§3.13): шлях лежить УСЕРЕДИНІ
## зони руху, тобто малюється поверх її контурів, тож у нього власний шар.
## LAYER_INSPECT — кільця оглянутого юніта (Task 14): окремо від LAYER_TARGETS, бо
## режими верби й дрона замінюють свої тайли, а кільце вибраного юніта живе поруч.
enum { LAYER_ZONES, LAYER_PATH, LAYER_TARGETS, LAYER_INSPECT }

## Геометрія риски контуру (§3.13, draw_contour нижче): тонка й коротка за
## задумом — вона мусить читатись як лінія на межі тайла, а не як ще один
## пофарбований тайл. _CONTOUR_INSET відсуває риску від самого краю тайла:
## без цього риска золотої зони й риска сусідньої червоної, що лежать на
## тому самому фізичному ребрі, збіглися б і z-fighting'нули — з відступом
## між ними лишається вузька смужка місцевості, і вони читаються як дві окремі
## риски, а не одна змішана.
const _CONTOUR_WIDTH: float = 0.12
const _CONTOUR_INSET: float = 0.06
const _CONTOUR_HEIGHT: float = 0.04
## 0.95 — колишня ширина плитки (до суцільної землі): риски лишились тієї самої
## довжини, тож кути сусідніх рисок, як і раніше, не сходяться.
const _CONTOUR_LENGTH: float = 0.95 - _CONTOUR_INSET * 2.0
## Над землею (y = 0) і над маркерами мін (MineLayer.MARKER_Y = 0.06), щоб не
## z-fight'ити ні з тим, ні з іншим.
const _CONTOUR_Y: float = 0.07
const _CONTOUR_OFFSET: float = 0.5 - _CONTOUR_WIDTH * 0.5 - _CONTOUR_INSET

## тайл -> вид тайлу під ним.
var _kind_by_cell: Dictionary = {}
## шар контуру -> Array[Dictionary] сегментів {cell, dir, color}, які зараз
## намальовані draw_contour(). Читається тестами напряму — той самий прийом,
## що й решта стану вигляду: колір екземпляра мультимешу
## не читається назад під headless (R4/R16), тож перевіряється те, ЩО туди
## подали, а не намальований піксель.
var _contour_segments: Dictionary = {}
## шар контуру -> MultiMeshInstance3D цього шару, щоб clear_contour() міг
## звільнити рівно свій вузол, не займаючи вузли інших шарів контуру.
var _contour_nodes: Dictionary = {}
## шар -> Array[Dictionary] кіл {center: Vector2i, radius: int, color: Color}
## (draw_circles) і їхні вузли — той самий прийом, що й у контурів.
var _circles: Dictionary = {}
var _circle_nodes: Dictionary = {}


func build(board: Board) -> void:
	# free(), не queue_free(): відкладене звільнення лишає щойно відкріплений
	# вузол «сиротою» до наступного кадру, а тести це фіксують як витік.
	for child in get_children():
		child.free()
	_kind_by_cell.clear()
	# Вузли контуру щойно звільнені циклом free() вище (вони теж діти цього
	# Node3D) — без цього _contour_nodes лишав би посилання на вже мертві
	# вузли, і наступний clear_contour() спробував би звільнити їх удруге.
	_contour_segments.clear()
	_contour_nodes.clear()
	_circles.clear()
	_circle_nodes.clear()

	for y in board.height:
		for x in board.width:
			_kind_by_cell[Vector2i(x, y)] = board.kind_at(Vector2i(x, y))

	var ground := GroundSurface.new()
	ground.name = "Ground"
	# Відступ поза дошкою — Task 9 (оточення); поки земля рівно під дошкою.
	ground.build(board, 0)
	add_child(ground)


## Малює контур шару з тонких рисок, а не заливкою тайлів (§3.13: «контур,
## не заливка» — і зони руху, і шлях мусять лишати місцевість та бойові сліди під
## собою видимими). Кожен сегмент — {cell: Vector2i, dir: Vector2i, color:
## Color}: тонка риска вздовж ребра `cell` з боку `dir`, а не перефарбування
## всього тайла. Замінює попередній контур цього шару —
## §3.2 «перемальовується після кожної дії» означає заміну.
##
## Один MultiMeshInstance3D на шар (не на сегмент) — ті самі draw-call міркування,
## що й у суцільної землі: дошка складається з десятків сегментів
## контуру за раз, і кожен окремим вузлом уже помітно проти бюджету §8.
func draw_contour(segments: Array[Dictionary], layer: int) -> void:
	clear_contour(layer)
	var kept: Array[Dictionary] = []
	for seg in segments:
		if _kind_by_cell.has(seg["cell"]):
			kept.append(seg)
	_contour_segments[layer] = kept
	if kept.is_empty():
		return

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _contour_mesh()
	mm.instance_count = kept.size()
	for i in kept.size():
		var seg: Dictionary = kept[i]
		var cell: Vector2i = seg["cell"]
		var dir: Vector2i = seg["dir"]
		var center: Vector3 = IsoCameraRig.cell_to_world(cell) + Vector3(0.0, _CONTOUR_Y, 0.0)
		var offset := Vector3(dir.x, 0.0, dir.y) * _CONTOUR_OFFSET
		# Меш типово довгий уздовж X, тонкий уздовж Z — правильна
		# орієнтація для ребра, що дивиться вздовж Z (dir.y != 0). Ребро, що
		# дивиться вздовж X (dir.x != 0), повертається на 90° навколо Y.
		var orientation := Basis()
		if dir.x != 0:
			orientation = orientation.rotated(Vector3.UP, PI * 0.5)
		mm.set_instance_transform(i, Transform3D(orientation, center + offset))
		mm.set_instance_color(i, seg["color"])

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Contour%d" % layer
	mmi.multimesh = mm
	mmi.material_override = _contour_material()
	add_child(mmi)
	_contour_nodes[layer] = mmi


## Перебудова тайлів після зміни виду (міст підірвано чи відновлено, BridgeChanged).
## build() знімає й контури, а зони й цілі в цю мить досі правдиві — тож
## малюємо їх наново тими самими сегментами.
func rebuild_tiles(board: Board) -> void:
	var kept: Dictionary = _contour_segments.duplicate()
	var kept_circles: Dictionary = _circles.duplicate()
	build(board)
	for layer: int in kept:
		var segs: Array[Dictionary] = []
		segs.assign(kept[layer])
		draw_contour(segs, layer)
	for layer: int in kept_circles:
		var circles: Array[Dictionary] = []
		circles.assign(kept_circles[layer])
		draw_circles(circles, layer)


## Кільце дальності (§3.13, docs/ui/overlays.md): одне геометричне коло, не контур
## тайлів — радіус у тайлах (тайл — 1.0 світу), центр у середині тайла. Радіус
## приходить готовим із core/ (Targeting.inspection); тут лише геометрія малювання.
## Сплющений тор — один вузол і один draw call на коло (§8). Замінює кола шару.
func draw_circles(circles: Array[Dictionary], layer: int) -> void:
	for node: Node in _circle_nodes.get(layer, []):
		if is_instance_valid(node):
			node.free()
	_circles[layer] = circles
	var nodes: Array[Node] = []
	for c in circles:
		var r: float = float(c["radius"])
		var torus := TorusMesh.new()
		torus.inner_radius = r - _CONTOUR_WIDTH * 0.5
		torus.outer_radius = r + _CONTOUR_WIDTH * 0.5
		torus.rings = 96
		torus.ring_segments = 4
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = c["color"]
		var mi := MeshInstance3D.new()
		mi.name = "Circle%d_%d" % [layer, nodes.size()]
		mi.mesh = torus
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = IsoCameraRig.cell_to_world(c["center"]) + Vector3(0.0, _CONTOUR_Y, 0.0)
		# Тор товщиною _CONTOUR_WIDTH сплющено до висоти риски контуру.
		mi.scale = Vector3(1.0, _CONTOUR_HEIGHT / _CONTOUR_WIDTH, 1.0)
		add_child(mi)
		nodes.append(mi)
	_circle_nodes[layer] = nodes


func circles(layer: int) -> Array:
	return _circles.get(layer, [])


## Вид тайла, який зараз намальовано (-1 — тайла немає).
func kind_at(cell: Vector2i) -> int:
	return _kind_by_cell.get(cell, -1)


func clear_contour(layer: int) -> void:
	_contour_segments[layer] = []
	if _contour_nodes.has(layer):
		var node: Node = _contour_nodes[layer]
		if is_instance_valid(node):
			node.free()
		_contour_nodes.erase(layer)


func contour_segments(layer: int) -> Array:
	return _contour_segments.get(layer, [])


## Одна риска: довга й тонка коробка. Типово довга вздовж X, тонка
## вздовж Z — правильно для ребра, що дивиться вздовж Z; для ребра вздовж X
## draw_contour() довертає екземпляр на 90° навколо Y (один спільний меш на
## всі напрямки дешевший за два різні меші в тому самому MultiMesh).
func _contour_mesh() -> Mesh:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(_CONTOUR_LENGTH, _CONTOUR_HEIGHT, _CONTOUR_WIDTH)
	return mesh


func _contour_material() -> StandardMaterial3D:
	# Колір іде з екземпляра мультимешу (use_colors), матеріал лише вмикає його
	# читання — сам він лишається білим, щоб не домішувати власний тон.
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	return mat
