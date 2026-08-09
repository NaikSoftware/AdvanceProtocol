class_name Board
extends RefCounted
## Сітка тайлів. Логічні координати цілі (x, y); ізометрію дає камера, не дані (§3.1).

const DIRS_4: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
]

## Індекс у цьому масиві — це значення facing. Порядок фіксований назавжди:
## 0 N, 1 NE, 2 E, 3 SE, 4 S, 5 SW, 6 W, 7 NW.
const DIRS_8: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1),
]

var width: int = 0
var height: int = 0
var ground_state: int = Terrain.GroundState.DRY
var tiles: PackedInt32Array = PackedInt32Array()

static func create(p_width: int, p_height: int, p_ground_state: int) -> Board:
	var b := Board.new()
	b.width = p_width
	b.height = p_height
	b.ground_state = p_ground_state
	b.tiles.resize(p_width * p_height)
	b.tiles.fill(Terrain.Kind.FIELD)
	return b

func in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < width and p.y < height

func _index(p: Vector2i) -> int:
	assert(in_bounds(p), "board access out of bounds: %v" % p)
	return p.y * width + p.x

func kind_at(p: Vector2i) -> int:
	return tiles[_index(p)]

func set_kind(p: Vector2i, kind: int) -> void:
	tiles[_index(p)] = kind

func penalty_at(p: Vector2i) -> int:
	if not in_bounds(p):
		return Terrain.IMPASSABLE
	return Terrain.penalty(kind_at(p), ground_state)

func is_passable(p: Vector2i) -> bool:
	return penalty_at(p) < Terrain.IMPASSABLE

func neighbours4(p: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in DIRS_4:
		var n: Vector2i = p + d
		if in_bounds(n):
			out.append(n)
	return out

static func facing_towards(from: Vector2i, to: Vector2i) -> int:
	var v: Vector2i = to - from
	if v == Vector2i.ZERO:
		return 0
	var best: int = 0
	var best_dot: float = -INF
	var vf := Vector2(v).normalized()
	for i in DIRS_8.size():
		var d := Vector2(DIRS_8[i]).normalized()
		var dot: float = vf.dot(d)
		if dot > best_dot:
			best_dot = dot
			best = i
	return best
