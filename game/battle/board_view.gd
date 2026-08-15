class_name BoardView
extends Node3D
## Рендерить сітку тайлів: один MultiMeshInstance3D на вид тайлу (§3.13,
## Task 2.3), ніколи на тайл — так тримається бюджет ~100 draw calls (§8).
##
## §3.5: туман ховає ворожих юнітів і їхні міни, ніколи місцевість. Вона
## публічна з першого ходу й на повній яскравості, тож у BoardView свідомо
## немає ані apply_fog, ані будь-якого зв'язку з клітинковою видимістю —
## приглушений тайл сам був би підказкою, а контур зони руху, що огинає
## нерозвідану перешкоду, видав би її не гірше за сам тайл. Ховати юнітів —
## робота інших вузлів (Task 2.4, Task 2.10), не цього.

## LAYER_PATH — окремий шар для підсвітки шляху (§3.13-суміжна задача): шлях
## лежить УСЕРЕДИНІ зони руху, тобто малюється поверх її контурів, тож у
## нього власний шар, а не спільний з LAYER_ZONES.
enum { LAYER_ZONES, LAYER_TARGETS, LAYER_SELECTION, LAYER_PATH }
const _LAYER_COUNT: int = 4

## Пріоритет накладання шарів підсвітки: вибір цілі — найважливіший сигнал
## гравцю просто зараз, тож жоден нижчий шар не може його погасити.
const _LAYER_PRIORITY: Array[int] = [LAYER_SELECTION, LAYER_TARGETS, LAYER_ZONES]

## Тонкий проміжок між тайлами — щоб сітка читалась як сітка, а не суцільна
## плита; висота — щоб дно не збігалося із землею з z-fighting.
const _TILE_GAP: float = 0.05
const _TILE_HEIGHT: float = 0.05

## Геометрія риски контуру (§3.13, draw_contour нижче): тонка й коротка за
## задумом — вона мусить читатись як лінія на межі тайла, а не як ще один
## пофарбований тайл. _CONTOUR_INSET відсуває риску від самого краю тайла:
## без цього риска золотої зони й риска сусідньої червоної, що лежать на
## тому самому фізичному ребрі, збіглися б і z-fighting'нули — з відступом
## між ними лишається вузька смужка терену, і вони читаються як дві окремі
## риски, а не одна змішана.
const _CONTOUR_WIDTH: float = 0.12
const _CONTOUR_INSET: float = 0.06
const _CONTOUR_HEIGHT: float = 0.04
const _CONTOUR_LENGTH: float = 1.0 - _TILE_GAP - _CONTOUR_INSET * 2.0
## Трохи вище верху тайла (_TILE_HEIGHT — рівень верхньої грані BoxMesh
## тайла), щоб не z-fight'ити з нею, і вище шару підсвітки-заливки, що лежить
## на самій поверхні тайла.
const _CONTOUR_Y: float = _TILE_HEIGHT + 0.02
const _CONTOUR_OFFSET: float = 0.5 - _CONTOUR_WIDTH * 0.5 - _CONTOUR_INSET

## Нейтральні кольори-плейсхолдери, без прив'язки до жодної реальної армії чи
## місцевості (§2): це геометрія і колір, не арт-проходка.
const _BASE_COLORS: Dictionary = {
	Terrain.Kind.ROAD: Color("6b6558"),
	Terrain.Kind.FIELD: Color("7a9450"),
	Terrain.Kind.FOREST: Color("3f5c34"),
	Terrain.Kind.HILL: Color("8a7a55"),
	Terrain.Kind.MARSH: Color("5c6b45"),
	Terrain.Kind.WATER: Color("3a6b8a"),
	Terrain.Kind.BUILDING: Color("8a8378"),
	Terrain.Kind.RUBBLE: Color("6e6a63"),
	Terrain.Kind.BRIDGE: Color("847a63"),
	Terrain.Kind.BRIDGE_DESTROYED: Color("4a463f"),
}

## вид тайлу -> його MultiMeshInstance3D. Лише для видів, що реально є на дошці.
var _instances: Dictionary = {}
## клітинка -> індекс інстансу в мультимеші її виду.
var _index_by_cell: Dictionary = {}
## клітинка -> вид тайлу під нею.
var _kind_by_cell: Dictionary = {}
## шар -> (клітинка -> колір). Кожен шар зберігає власний стан незалежно від
## інших — це і є причина існування трьох шарів, а не одного.
var _layer_highlights: Array[Dictionary] = [{}, {}, {}, {}]

## шар контуру -> Array[Dictionary] сегментів {cell, dir, color}, які зараз
## намальовані draw_contour(). Читається тестами напряму — той самий прийом,
## що й _layer_highlights вище, і той самий привід: колір інстансу мультимешу
## не читається назад під headless (R4/R16), тож перевіряється те, ЩО туди
## подали, а не намальований піксель.
var _contour_segments: Dictionary = {}
## шар контуру -> MultiMeshInstance3D цього шару, щоб clear_contour() міг
## звільнити рівно свій вузол, не займаючи вузли інших шарів контуру.
var _contour_nodes: Dictionary = {}


func build(board: Board) -> void:
	# free(), не queue_free(): відкладене звільнення лишає щойно відкріплений
	# вузол «сиротою» до наступного кадру, а тести це фіксують як витік.
	for child in get_children():
		child.free()
	_instances.clear()
	_index_by_cell.clear()
	_kind_by_cell.clear()
	for layer in _LAYER_COUNT:
		_layer_highlights[layer].clear()
	# Вузли контуру щойно звільнені циклом free() вище (вони теж діти цього
	# Node3D) — без цього _contour_nodes лишав би посилання на вже мертві
	# вузли, і наступний clear_contour() спробував би звільнити їх удруге.
	_contour_segments.clear()
	_contour_nodes.clear()

	var cells_by_kind: Dictionary = {}
	for y in board.height:
		for x in board.width:
			var cell := Vector2i(x, y)
			var kind: int = board.kind_at(cell)
			if not cells_by_kind.has(kind):
				cells_by_kind[kind] = [] as Array[Vector2i]
			cells_by_kind[kind].append(cell)
			_kind_by_cell[cell] = kind

	for kind in cells_by_kind:
		var cells: Array[Vector2i] = cells_by_kind[kind]
		var mmi := _build_kind_instance(kind, cells)
		add_child(mmi)
		_instances[kind] = mmi
		for i in cells.size():
			_index_by_cell[cells[i]] = i


func highlight_tiles(tiles: Array[Vector2i], color: Color, layer: int) -> void:
	for cell in tiles:
		if not _kind_by_cell.has(cell):
			continue
		_layer_highlights[layer][cell] = color
		_repaint_cell(cell)


func clear_highlights(layer: int) -> void:
	var cells: Array = _layer_highlights[layer].keys()
	_layer_highlights[layer].clear()
	for cell in cells:
		_repaint_cell(cell)


## Малює контур шару з тонких рисок, а не заливкою тайлів (§3.13: «контур,
## не заливка» — і зони руху, і шлях мусять лишати терен та бойові сліди під
## собою видимими). Кожен сегмент — {cell: Vector2i, dir: Vector2i, color:
## Color}: тонка риска вздовж ребра `cell` з боку `dir`, а не перефарбування
## всього тайла. Замінює попередній контур цього шару, як і highlight_tiles
## заміняє — §3.2 «перемальовується після кожної дії» означає заміну.
##
## Один MultiMeshInstance3D на шар (не на сегмент) — ті самі draw-call міркування,
## що й у _build_kind_instance(): дошка складається з десятків сегментів
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
		# Меш за замовчуванням довгий уздовж X, тонкий уздовж Z — правильна
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
	# Той самий матеріал, що й тайли: читає use_colors, сам лишається білим.
	mmi.material_override = _tile_material()
	add_child(mmi)
	_contour_nodes[layer] = mmi


func clear_contour(layer: int) -> void:
	_contour_segments[layer] = []
	if _contour_nodes.has(layer):
		var node: Node = _contour_nodes[layer]
		if is_instance_valid(node):
			node.free()
		_contour_nodes.erase(layer)


func contour_segments(layer: int) -> Array:
	return _contour_segments.get(layer, [])


func _build_kind_instance(kind: int, cells: Array[Vector2i]) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _tile_mesh()
	mm.instance_count = cells.size()
	var base_color: Color = _BASE_COLORS.get(kind, Color.WHITE)
	for i in cells.size():
		var origin: Vector3 = IsoCameraRig.cell_to_world(cells[i]) + Vector3(0.0, _TILE_HEIGHT * 0.5, 0.0)
		mm.set_instance_transform(i, Transform3D(Basis(), origin))
		mm.set_instance_color(i, base_color)

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Tiles%d" % kind
	mmi.multimesh = mm
	mmi.material_override = _tile_material()
	return mmi


func _tile_mesh() -> Mesh:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.0 - _TILE_GAP, _TILE_HEIGHT, 1.0 - _TILE_GAP)
	return mesh


## Одна риска: довга й тонка коробка. За замовчуванням довга вздовж X, тонка
## вздовж Z — правильно для ребра, що дивиться вздовж Z; для ребра вздовж X
## draw_contour() довертає інстанс на 90° навколо Y (один спільний меш на
## всі напрямки дешевший за два різні мешi в тому самому MultiMesh).
func _contour_mesh() -> Mesh:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(_CONTOUR_LENGTH, _CONTOUR_HEIGHT, _CONTOUR_WIDTH)
	return mesh


func _tile_material() -> StandardMaterial3D:
	# Колір іде з інстансу мультимешу (use_colors), матеріал лише вмикає його
	# читання — сам він лишається білим, щоб не домішувати власний тон.
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	return mat


func _repaint_cell(cell: Vector2i) -> void:
	var kind: int = _kind_by_cell[cell]
	var mmi: MultiMeshInstance3D = _instances[kind]
	var index: int = _index_by_cell[cell]
	mmi.multimesh.set_instance_color(index, _resolve_color(cell, kind))


func _resolve_color(cell: Vector2i, kind: int) -> Color:
	for layer in _LAYER_PRIORITY:
		if _layer_highlights[layer].has(cell):
			return _layer_highlights[layer][cell]
	return _BASE_COLORS.get(kind, Color.WHITE)
