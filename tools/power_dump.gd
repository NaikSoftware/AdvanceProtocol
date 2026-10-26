extends SceneTree
## Вивантаження вихідних даних для tools/power_grid.py: константи правил PropLayer, клітини світу
## (дошка разом із кільцем), поле відстані до краю асфальту (те, що малює шейдер землі), будівлі, дрібні
## пропси, грядки, мости, клітини появи, наміри трас VillageLayout і для кожної житлової будівлі —
## місця, звідки гра (PropLayer._drop_target) дозволяє відвід. Власних правил у генератора нема: усе
## береться звідси.
## Запуск: $GODOT --headless --path . --script tools/power_dump.gd -- <out.json> <map>...

const FEED_RADIUS: float = 2.3
const FEED_STEP: float = 0.25


func _initialize() -> void:
	_run.call_deferred()


func _box(inst: Dictionary) -> AABB:
	return (inst["transform"] as Transform3D) * ((PropLayer.model(inst["model"]) as Dictionary)["aabb"] as AABB)


func _rect(b: AABB) -> Array:
	return [b.position.x, b.position.z, b.size.x, b.size.z]


## Сітка місць стовпа навколо точки: межі клітинок (k ± 0.01) уздовж осі з кроком FEED_STEP.
static func grid_near(c: Vector2, radius: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var lo := Vector2(c.x - radius, c.y - radius)
	var hi := Vector2(c.x + radius, c.y + radius)
	for k in range(floori(lo.x) - 1, ceili(hi.x) + 1):
		for o: float in [0.49, 0.51]:
			var x: float = k + o
			if x < lo.x or x > hi.x:
				continue
			for n in range(floori(lo.y / FEED_STEP), ceili(hi.y / FEED_STEP) + 1):
				out.append(Vector2(x, n * FEED_STEP))
	for k in range(floori(lo.y) - 1, ceili(hi.y) + 1):
		for o: float in [0.49, 0.51]:
			var y: float = k + o
			if y < lo.y or y > hi.y:
				continue
			for n in range(floori(lo.x / FEED_STEP), ceili(hi.x / FEED_STEP) + 1):
				out.append(Vector2(n * FEED_STEP, y))
	return out


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
		var pl = props._placer
		var ht: TerrainHeight = view._height
		var ring: int = view._ring
		var world: Board = Surroundings.world_board(board, m)
		var kinds: Array = []
		for y in world.height:
			var row: Array = []
			for x in world.width:
				row.append(world.kind_at(Vector2i(x, y)))
			kinds.append(row)
		var rc: RoadCourse = ht.roads
		var d: Array = []
		var rw: int = 0
		var rh: int = 0
		if rc != null:
			var grid: PackedFloat32Array = rc.d_grid()
			rw = (board.width + 2 * ring) * RoadCourse.PX
			rh = (board.height + 2 * ring) * RoadCourse.PX
			for v: float in grid:
				d.append(snappedf(v, 0.001))
		var buildings: Array = []
		var others: Array = []
		var bridges: Array = []
		var home_ids: Array[int] = []
		for i in props._instances.size():
			var inst: Dictionary = props._instances[i]
			var k: int = int(PropLayer.spec_of(inst["model"]).get("kind", -1))
			var rect: Array = _rect(_box(inst))
			if k == PropLayer.Kind.POLE:
				continue
			if k == PropLayer.Kind.STRUCTURE or k == PropLayer.Kind.RUIN:
				var home: bool = PropLayer.is_home(inst)
				buildings.append({"model": String(inst["model"]), "rect": rect, "home": home})
				if home:
					home_ids.append(i)
			elif k == PropLayer.Kind.BRIDGE:
				bridges.append({"rect": rect})
			else:
				others.append({"model": String(inst["model"]), "rect": rect})
		for gp: Dictionary in props._garden_plots:
			var gr: Rect2 = gp["rect"]
			others.append({"model": "garden", "rect": [gr.position.x, gr.position.y, gr.size.x, gr.size.y]})
		# Житлові будівлі: чи живить їх мережа і з яких місць можливий відвід (дві орієнтації траверси,
		# моделі опор 0.4 кВ і 10 кВ — для підстанції).
		var centres: Array[Vector2] = []
		var on_board: Array[bool] = []
		for i in home_ids:
			var bb: AABB = _box(props._instances[i])
			centres.append(Vector2(bb.get_center().x, bb.get_center().z))
			on_board.append(Rect2i(0, 0, board.width, board.height).has_point((props._instances[i]["cells"] as Array)[0]))
		var powered: Array[bool] = PropLayer.powered_homes(centres, on_board)
		var homes: Array = []
		for h in home_ids.size():
			var i: int = home_ids[h]
			var entry: Dictionary = {"rect": _rect(_box(props._instances[i])), "model": String(props._instances[i]["model"]),
					"on_board": on_board[h], "powered": powered[h], "f04": [], "f10": []}
			if powered[h]:
				for mdl: Array in [[&"infra_pole_concrete_04kv", "f04"], [&"infra_pole_concrete_10kv", "f10"]]:
					for q: Vector2 in grid_near(centres[h], FEED_RADIUS):
						if q.distance_to(centres[h]) > FEED_RADIUS:
							continue
						var lip := Vector2.INF
						for yaw: float in [0.0, PI * 0.5]:
							var cells: Array[Vector2i] = [Vector2i(roundi(q.x), roundi(q.y))]
							var pi: int = props._add(mdl[0], Transform3D(Basis(Vector3.UP, yaw), Vector3(q.x, pl.ground(q.x, q.y), q.y)), cells)
							var at: Vector3 = pl._drop_target(i, pi)
							props._instances.pop_back()
							if not at.is_finite():
								lip = Vector2.INF
								break
							lip = Vector2(at.x, at.z)
						if lip.is_finite():
							(entry[mdl[1]] as Array).append([snappedf(q.x, 0.01), snappedf(q.y, 0.01), snappedf(lip.x, 0.001), snappedf(lip.y, 0.001)])
			homes.append(entry)
		# Ґрунт світу на сітці 0.25 клітинки (дріт має висіти не нижче 6 м над ґрунтом і водою) і найнижчий
		# ізолятор опор.
		var gw: int = int((board.width + 2 * ring) / 0.25) + 1
		var gh: int = int((board.height + 2 * ring) / 0.25) + 1
		var ground: Array = []
		for gy in gh:
			for gx in gw:
				ground.append(snappedf(ht.at(-ring - 0.5 + gx * 0.25, -ring - 0.5 + gy * 0.25), 0.001))
		var low: float = 9.0
		for mdl: StringName in [&"infra_pole_concrete_04kv", &"infra_pole_concrete_10kv"]:
			for w: Vector3 in (PropLayer.model(mdl) as Dictionary)["wires"]:
				low = minf(low, w.y)
		var spawns: Array = []
		for c: Vector2i in props.spawn_cells:
			spawns.append([c.x, c.y])
		var routes: Array = []
		for r: Dictionary in VillageLayout.for_map(StringName(name)).get("routes", []):
			var axis: Array = []
			for p: Vector2 in r["axis"]:
				axis.append([p.x, p.y])
			routes.append({"kind": String(r["kind"]), "axis": axis, "side": float(r.get("side", 1.0)), "from": int(r.get("from", -1))})
		var pole10: AABB = (PropLayer.model(&"infra_pole_concrete_10kv") as Dictionary)["aabb"]
		result[name] = {
			"size": [board.width, board.height], "ring": ring,
			"consts": {
				"building": PropLayer.POLE_BUILDING_CLEAR, "home": PropLayer.POLE_HOME_CLEAR, "prop": PropLayer.POLE_PROP_CLEAR,
				"garden": PropLayer.POLE_GARDEN_CLEAR, "bridge": PropLayer.POLE_BRIDGE_CLEAR, "road_m": PropLayer.POLE_ROAD_CLEAR_M,
				"wet": PropLayer.POLE_WET_CLEAR, "unit_half": PropLayer.UNIT_HALF, "unit_pole": PropLayer.UNIT_POLE_CLEAR,
				"keep_out": PropLayer.KEEP_OUT, "pole_half": maxf(pole10.size.x, pole10.size.z) * 0.5,
				"span": PropLayer.SPAN[&"10kv"], "wire_low": low, "wire_sag": PropLayer.WIRE_SAG_RATIO,
				"water_level": TerrainHeight.WATER_LEVEL, "wire_clear_m": 6.0, "cabinet_offset": PropLayer.TRANSFORMER_OFFSET,
				"cabinet_w": PropLayer.TRANSFORMER_SIZE.x, "cabinet_d": PropLayer.TRANSFORMER_SIZE.z, "drop_direct": PropLayer.DROP_DIRECT, "drop_min": PropLayer.DROP_MIN,
				"drop_gap": PropLayer.DROP_GAP, "settle_r": PropLayer.SETTLEMENT_R, "px": RoadCourse.PX,
			},
			"wkinds": kinds, "road_d": {"w": rw, "h": rh, "v": d}, "ground": {"w": gw, "h": gh, "v": ground},
			"homes": homes, "buildings": buildings, "others": others, "bridges": bridges, "spawns": spawns, "routes": routes}
		view.free()
		await process_frame
	var f := FileAccess.open(args[0], FileAccess.WRITE)
	f.store_string(JSON.stringify(result))
	f.close()
	quit(0)
