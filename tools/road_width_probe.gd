extends SceneTree
## Ширина намальованого асфальту вздовж ліній і на розвилках (м), з растра RoadCourse. Не входить у гру.
## Запуск: $GODOT --headless --path . -s tools/road_width_probe.gd -- <map>

func _px(img: Image, rc: RoadCourse, p: Vector2) -> Color:
	var i: int = clampi(roundi((p.x + 0.5 + rc._margin) * RoadCourse.PX - 0.5), 0, img.get_width() - 1)
	var j: int = clampi(roundi((p.y + 0.5 + rc._margin) * RoadCourse.PX - 0.5), 0, img.get_height() - 1)
	return img.get_pixel(i, j)


## Ширина асфальту впоперек осі в точці c (метри): кроки по 0.125 м, d < 0 і вага асфальту > 0.5.
func _across(rc: RoadCourse, c: Vector2, dir: Vector2) -> float:
	var nrm := Vector2(-dir.y, dir.x)
	var f: Image = rc.rasterise()[0]
	var t: Image = rc.rasterise()[1]
	var w: float = 0.0
	for k in range(-60, 61):
		var p: Vector2 = c + nrm * (k * 0.0156)
		if _px(f, rc, p).r < 0.0 and _px(t, rc, p).r > 0.5:
			w += 0.125
	return w


func _init() -> void:
	var name: String = OS.get_cmdline_user_args()[0]
	var m: MapData = load("res://maps/%s.tres" % name)
	var rc: RoadCourse = TerrainHeight.bake(m.to_board(), 0, m.name_key.hash(), m.surface).roads
	for li in rc.lines.size():
		var pts: PackedVector2Array = rc.lines[li]
		var plain: Array[float] = []
		var near: Array[float] = []
		for i in range(1, pts.size() - 1, 3):
			var dir: Vector2 = (pts[i + 1] - pts[i - 1]).normalized()
			var w: float = _across(rc, pts[i], dir)
			if rc.near_node(pts[i]) < 1.6:
				near.append(w)
			else:
				plain.append(w)
		plain.sort()
		near.sort()
		print("WIDTH %s line %d plain n=%d min %.1f med %.1f max %.1f | near-node n=%d max %.1f" % [name, li, plain.size(),
				plain[0] if plain.size() > 0 else 0.0, plain[plain.size() / 2] if plain.size() > 0 else 0.0,
				plain[-1] if plain.size() > 0 else 0.0, near.size(), near[-1] if near.size() > 0 else 0.0])
	quit()
