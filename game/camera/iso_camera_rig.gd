class_name IsoCameraRig
extends Node3D
## Фіксований ізометричний ріг: панорама і зум по площині дошки, кут камери
## не змінюється (§1 non-goals — вільної камери нема). Ноду-власника фокусу —
## сам корінь рига, дочірній Yaw несе поворот на 45°, лише щоб дати камері
## погляд; жодна з цих обертань не потрапляє у клітинкові координати.

const MIN_ZOOM: float = 6.0
const MAX_ZOOM: float = 20.0
## §3.13/§1: панорама обмежена межами дошки з полем в 2 тайли — гравець не
## може завести камеру за край карти навіть на максимальному зумі.
const BOARD_MARGIN: float = 2.0
## R13: єдине джерело правди для 45° — сцена бере його звідси в _ready(),
## а pan() крутить дельту тим самим числом, щоб кут не роз'їхався у двох
## місцях.
const YAW_DEGREES: float = 45.0

@onready var _yaw: Node3D = $Yaw
@onready var _camera: Camera3D = $Yaw/Camera3D

var zoom_level: float = 12.0
## Остання дійсна клітинка дошки (board_size - 1), не її розмір: cell_to_world
## кладе клітинку (19, 19) двадцятитайлової дошки у світові 19, а не 20 —
## межа панорами міряється від фактичного краю геометрії (R12), а не від
## кількості клітинок.
var _max_cell: Vector2i = Vector2i.ZERO

func _ready() -> void:
	_yaw.rotation_degrees.y = YAW_DEGREES
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = zoom_level

## §3.1: логічні координати цілі, світові — (x, 0, y). 45° дає камера, а не
## ці дані, тому функція лишається чистим переносом без жодного повороту.
static func cell_to_world(cell: Vector2i) -> Vector3:
	return Vector3(cell.x, 0.0, cell.y)

static func world_to_cell(point: Vector3) -> Vector2i:
	return Vector2i(roundi(point.x), roundi(point.z))

func set_bounds(board_size: Vector2i) -> void:
	_max_cell = board_size - Vector2i.ONE

## R13: delta — це палець гравця на екрані, не світові осі. Ріг сам повертає
## її на свій yaw, інакше 45° довелось би рахувати вдруге в контролері вводу
## (Task 2.7) — а це і є те просочування кута назовні, яке забороняє §3.1.
func pan(delta: Vector2) -> void:
	var world_delta: Vector3 = Vector3(delta.x, 0.0, delta.y).rotated(Vector3.UP, deg_to_rad(YAW_DEGREES))
	global_position = _clamp_to_bounds(global_position + world_delta)

func center_on(cell: Vector2i) -> void:
	global_position = _clamp_to_bounds(cell_to_world(cell))

func zoom_by(factor: float) -> void:
	zoom_level = clampf(zoom_level * factor, MIN_ZOOM, MAX_ZOOM)
	_camera.size = zoom_level

func _clamp_to_bounds(pos: Vector3) -> Vector3:
	var min_edge: float = -BOARD_MARGIN
	var max_x: float = float(_max_cell.x) + BOARD_MARGIN
	var max_z: float = float(_max_cell.y) + BOARD_MARGIN
	return Vector3(
		clampf(pos.x, min_edge, max_x),
		pos.y,
		clampf(pos.z, min_edge, max_z)
	)
