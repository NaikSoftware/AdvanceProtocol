class_name Vision
extends RefCounted
## Туман війни (§3.5). Один екземпляр на гравця; visible завжди з нуля.

var width: int = 0
var height: int = 0
var visible: PackedByteArray = PackedByteArray()
var seen: PackedByteArray = PackedByteArray()

static func create(p_width: int, p_height: int) -> Vision:
	var v := Vision.new()
	v.width = p_width
	v.height = p_height
	v.visible.resize(p_width * p_height)
	v.seen.resize(p_width * p_height)
	return v

func _index(p: Vector2i) -> int:
	return p.y * width + p.x

func _in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < width and p.y < height

func is_visible(p: Vector2i) -> bool:
	return _in_bounds(p) and visible[_index(p)] == 1

func is_seen(p: Vector2i) -> bool:
	return _in_bounds(p) and seen[_index(p)] == 1

func recompute(board: Board, units: Array[Unit], player: int) -> Array[Vector2i]:
	visible.fill(0)
	var revealed: Array[Vector2i] = []
	for u in units:
		if u.owner != player or not u.is_alive():
			continue
		var r: int = u.vision()
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var p: Vector2i = u.pos + Vector2i(dx, dy)
				if not board.in_bounds(p):
					continue
				if not Rules.in_radius(u.pos, p, r):
					continue
				var i: int = _index(p)
				visible[i] = 1
				if seen[i] == 0:
					seen[i] = 1
					revealed.append(p)
	return revealed
