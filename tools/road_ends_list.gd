extends SceneTree
## Перелік кінців асфальту на картах: глухі кінці ліній і місця зміни типу. Не входить у гру.
## Запуск: $GODOT --headless --path . -s tools/road_ends_list.gd
func _init() -> void:
	for map_name in ["river", "crossroads", "ridge"]:
		var m: MapData = load("res://maps/%s.tres" % map_name)
		var th: TerrainHeight = TerrainHeight.bake(m.to_board(), 0, m.name_key.hash(), m.surface)
		var rc: RoadCourse = th.roads
		if rc == null:
			continue
		for li in rc.lines.size():
			var pts: PackedVector2Array = rc.lines[li]
			var ty: PackedVector3Array = rc.types[li]
			for s in [0, pts.size() - 1]:
				if rc.is_free_end(pts[s]):
					print("END %s line %d pt %s type %s" % [map_name, li, pts[s], ty[s]])
			for i in pts.size() - 1:
				if (ty[i].x > 0.5) != (ty[i + 1].x > 0.5):
					print("JOIN %s line %d pt %s a=%s b=%s" % [map_name, li, pts[i], ty[i], ty[i + 1]])
	quit()
