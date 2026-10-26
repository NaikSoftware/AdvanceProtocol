extends SceneTree
## Вивантаження вихідних даних для tools/power_grid.py: клітинки світу (дошка разом із кільцем),
## дороги, будівлі, дрібні пропси, мости, клітинки появи й наміри трас з VillageLayout.
## Запуск: $GODOT --headless --path . --script tools/power_dump.gd -- <out.json> <map>...


func _initialize() -> void:
	_run.call_deferred()


func _box(inst: Dictionary) -> AABB:
	return (inst["transform"] as Transform3D) * ((PropLayer.model(inst["model"]) as Dictionary)["aabb"] as AABB)


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var result: Dictionary = {}
	for mi in range(1, args.size()):
		var name: String = args[mi]
		var m: MapData = load("res://maps/%s.tres" % name)
		var view: BoardView = (load("res://game/battle/board_view.tscn") as PackedScene).instantiate()
		root.add_child(view)
		view.ring_map = m
		view.surface = m.surface
		view.relief_seed = m.name_key.hash()
		var board: Board = m.to_board()
		view.build(board)
		await process_frame
		var props: PropLayer = view.props()
		var ht: TerrainHeight = view._height
		var ring: int = view._ring
		var world: Board = Surroundings.world_board(board, m)
		var kinds: Array = []
		for y in world.height:
			var row: Array = []
			for x in world.width:
				row.append(world.kind_at(Vector2i(x, y)))
			kinds.append(row)
		var roads: Array = []
		if ht.roads != null:
			for li in ht.roads.lines.size():
				var pts: Array = []
				for k in ht.roads.lines[li].size():
					var p: Vector2 = ht.roads.lines[li][k] - Vector2(ring, ring)
					pts.append([p.x, p.y, float(ht.roads.halfs[li][k]) / 8.0])
				roads.append(pts)
		var buildings: Array = []
		var others: Array = []
		var bridges: Array = []
		for inst: Dictionary in props.all_instances():
			var s: Dictionary = PropLayer.spec_of(inst["model"])
			var k: int = int(s.get("kind", -1))
			var b: AABB = _box(inst)
			var rect: Array = [b.position.x, b.position.z, b.size.x, b.size.z]
			if k == PropLayer.Kind.POLE:
				continue
			if k == PropLayer.Kind.STRUCTURE or k == PropLayer.Kind.RUIN:
				buildings.append({"model": String(inst["model"]), "kind": "ruin" if k == PropLayer.Kind.RUIN else "structure",
						"yard": inst.get("yard", false), "rect": rect})
			elif k == PropLayer.Kind.BRIDGE:
				bridges.append({"rect": rect})
			else:
				others.append({"model": String(inst["model"]), "rect": rect})
		# Житлові будівлі: для 72 напрямків від центру — де кінчається дах (кромка за мешем) і яка там
		# висота; за цим генератор вирішує, чи можливий відвід (так само, як PropLayer._eave_attach).
		var homes: Array = []
		for inst: Dictionary in props.all_instances():
			var c: Vector2i = (inst["cells"] as Array)[0]
			if not PropLayer.is_home(inst, Rect2i(0, 0, board.width, board.height).has_point(c)):
				continue
			var info: Dictionary = PropLayer.model(inst["model"])
			var xf: Transform3D = (inst["transform"] as Transform3D) * (info["local"] as Transform3D)
			var tm: TriangleMesh = PropLayer.triangles_of(inst["model"])
			var bb: AABB = _box(inst)
			var centre := Vector2(bb.get_center().x, bb.get_center().z)
			var lips: Array = []
			for a in 72:
				var dir := Vector2.from_angle(float(a) * TAU / 72.0)
				var found: Array = [-1.0, 0.0, 0.0]
				var sx: float = 0.7
				while sx >= 0.0:
					var q: Vector2 = centre + dir * sx
					var top: float = PropLayer.roof_y(tm, xf, q.x, q.y)
					if top != -INF and top - ht.at(q.x, q.y) >= PropLayer.DROP_ROOF_MIN:
						found = [sx, top, ht.at(q.x, q.y)]
						break
					sx -= 0.02
				lips.append(found)
			homes.append({"rect": [bb.position.x, bb.position.z, bb.size.x, bb.size.z], "model": String(inst["model"]), "lips": lips})
		for gp: Dictionary in props._garden_plots:
			var gr: Rect2 = gp["rect"]
			others.append({"model": "garden", "rect": [gr.position.x, gr.position.y, gr.size.x, gr.size.y]})
		var spawns: Array = []
		for c: Vector2i in props.spawn_cells:
			spawns.append([c.x, c.y])
		var routes: Array = []
		for r: Dictionary in VillageLayout.for_map(StringName(name)).get("routes", []):
			var axis: Array = []
			for p: Vector2 in r["axis"]:
				axis.append([p.x, p.y])
			routes.append({"kind": String(r["kind"]), "axis": axis, "side": float(r.get("side", 1.0)), "from": int(r.get("from", -1))})
		result[name] = {"size": [board.width, board.height], "ring": ring, "wkinds": kinds, "roads": roads,
				"homes": homes, "buildings": buildings, "others": others, "bridges": bridges, "spawns": spawns, "routes": routes}
		view.free()
		await process_frame
	var f := FileAccess.open(args[0], FileAccess.WRITE)
	f.store_string(JSON.stringify(result))
	f.close()
	quit(0)
