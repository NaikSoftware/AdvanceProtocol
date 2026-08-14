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

enum { LAYER_ZONES, LAYER_TARGETS, LAYER_SELECTION }
const _LAYER_COUNT: int = 3

## Пріоритет накладання шарів підсвітки: вибір цілі — найважливіший сигнал
## гравцю просто зараз, тож жоден нижчий шар не може його погасити.
const _LAYER_PRIORITY: Array[int] = [LAYER_SELECTION, LAYER_TARGETS, LAYER_ZONES]

## Тонкий проміжок між тайлами — щоб сітка читалась як сітка, а не суцільна
## плита; висота — щоб дно не збігалося із землею з z-fighting.
const _TILE_GAP: float = 0.05
const _TILE_HEIGHT: float = 0.05

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
var _layer_highlights: Array[Dictionary] = [{}, {}, {}]


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
