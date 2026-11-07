extends Node
## Туман і падіння (§3.5): ворожа машина (гравець 1) валить опору й паркан на землі, якої гравець 0 не розвідав.
## Кадри: A_* — екран гравця 1 під час ходу, B_* — екран гравця 0 після повного кола (передача ходу туди й назад).
## На B не мусить бути ні падіння, ні пилу, ні змін у дротах. Кадри — в пам'яті, PNG пишуться в кінці.
## Запуск (вікно): $GODOT --path . res://tools/crush_fog.tscn -- <out_dir> <map> <zoom> <fps>

const WINDOW: Vector2i = Vector2i(1600, 900)
const CROP: Vector2i = Vector2i(720, 600)

var _frames: Array[Image] = []
var _names: Array[String] = []
var _cam: Camera3D
var _focus: Vector3
var _props: PropLayer


func _ready() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	if a.size() < 4:
		push_error("crush_fog: <out_dir> <map> <zoom> <fps>")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(a[0])
	get_window().size = WINDOW
	var screen: BattleScreen = (load("res://game/battle/battle_screen.tscn") as PackedScene).instantiate()
	add_child(screen)
	var map := load("res://maps/%s.tres" % a[1]) as MapData
	screen.setup(map, 2, 1)
	_props = (screen.get_node("%BoardView") as BoardView).props()
	var service: Node = screen.get("_match_service")
	var state: BattleState = service.state
	var board: Board = state.board
	var seen0: Vision = state.vision[0]
	var enemy: Unit = null
	for u: Unit in state.units_of(1):
		if u.unit_class() in [UnitTypes.UnitClass.TANK, UnitTypes.UnitClass.LIGHT_VEHICLE] and (enemy == null or u.ap > enemy.ap):
			enemy = u
	var spawn: Vector2i = enemy.pos
	var ap0: int = enemy.ap
	# Дві цілі: опора з дротом і паркан двору; обидві — на землі, якої гравець 0 не бачив.
	var plans: Array = []
	for want in ["pole", "fence"]:
		var best: float = INF
		var found: Array = []
		for i in _props._instances.size():
			var inst: Dictionary = _props._instances[i]
			var kind: int = int(PropLayer.spec_of(inst["model"]).get("kind", -1))
			var ok: bool = (kind == PropLayer.Kind.POLE and _props._has_wire(i)) if want == "pole" else (kind == PropLayer.Kind.GARDEN_FENCE or kind == PropLayer.Kind.FIELD_FENCE)
			if not ok:
				continue
			var o := Vector2i(roundi((inst["transform"] as Transform3D).origin.x), roundi((inst["transform"] as Transform3D).origin.z))
			for dx in range(-1, 2):
				for dz in range(-1, 2):
					var c: Vector2i = o + Vector2i(dx, dz)
					if not board.in_bounds(c) or seen0.is_seen(c) or board.kind_at(c) != Terrain.Kind.FIELD:
						continue
					for d: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
						var st: Vector2i = c + d * 2
						if not board.in_bounds(st) or seen0.is_seen(st) or board.kind_at(st) != Terrain.Kind.FIELD or board.kind_at(c + d) != Terrain.Kind.FIELD:
							continue
						if not (_props.band_hits(c + d, c)["inst"] as Array).has(i):
							continue
						enemy.pos = st
						if (Pathing.compute_zones(board, enemy, {}, {}) as Pathing.Zones).can_reach(c):
							var dist: float = float(c.distance_squared_to(Vector2i(board.width, board.height) / 2))
							if dist < best:
								best = dist
								found = [c, st, (inst["transform"] as Transform3D).origin, i]
		enemy.pos = spawn
		plans.append(found)
	print("CRUSHFOG plans=%s" % [plans])
	if plans[0].is_empty() or plans[1].is_empty():
		get_tree().quit(1)
		return
	var spans0: int = _props.wire_spans()
	var rig: IsoCameraRig = screen.get_node("%CameraRig")
	_cam = get_viewport().get_camera_3d()
	for f in 120:
		await get_tree().process_frame
	# Кінець ходу гравця 0 → гейт → підтвердження: на екрані гравець 1.
	(screen.get_node("%Hud").get_node("%EndTurnButton") as Button).pressed.emit()
	await _wait(screen, 20)
	(screen.get_node("%HandoverGate").get_node("%ConfirmButton") as Button).pressed.emit()
	await _wait(screen, 20)
	var fps: float = float(a[3])
	for k in 2:
		var plan: Array = plans[k]
		enemy.pos = plan[1]
		enemy.ap = ap0
		state.refresh_vision(1)
		screen.call("_rebuild_units_for_active_player", true)
		_focus = plan[2]
		rig.center_on(plan[0])
		rig.zoom_by(float(a[2]) / rig.zoom_level)
		await _wait(screen, 90)
		print("CRUSHFOG submit=%s" % service.submit(MoveCommand.create(enemy.id, plan[0])))
		await _record(screen, "A%d" % k, 4.0, fps)
	# Назад до гравця 0: повне коло.
	(screen.get_node("%Hud").get_node("%EndTurnButton") as Button).pressed.emit()
	await _wait(screen, 20)
	(screen.get_node("%HandoverGate").get_node("%ConfirmButton") as Button).pressed.emit()
	await _wait(screen, 20)
	for k in 2:
		_focus = (plans[k] as Array)[2]
		rig.center_on((plans[k] as Array)[0])
		await _wait(screen, 60)
		await _record(screen, "B%d" % k, 1.5, fps)
	print("CRUSHFOG P0 view: falling=%d broken=%d spans=%d/%d fx_nodes=%d" % [_props.falling_count(), _props._broken.size(), _props.wire_spans(), spans0,
			get_tree().get_nodes_in_group(BattleFx.GROUP).size()])
	for i in _frames.size():
		_frames[i].save_png("%s/%s_%03d.png" % [a[0], _names[i], i])
	get_tree().quit()


func _wait(screen: BattleScreen, frames: int) -> void:
	for f in frames:
		await get_tree().process_frame
	while (screen.get("_event_player") as EventPlayer).is_playing():
		await get_tree().process_frame


func _record(screen: BattleScreen, tag: String, secs: float, fps: float) -> void:
	var t0: int = Time.get_ticks_usec()
	var next: float = 0.0
	while true:
		await RenderingServer.frame_post_draw
		var el: float = float(Time.get_ticks_usec() - t0) / 1e6
		if el >= next:
			var img: Image = get_viewport().get_texture().get_image()
			var k: float = float(img.get_width()) / get_viewport().get_visible_rect().size.x
			var base: Vector2 = _cam.unproject_position(_props.to_global(_focus))
			var pos := Vector2i(int(base.x * k) - CROP.x / 2, int(base.y * k) - CROP.y * 2 / 3).clamp(Vector2i.ZERO, img.get_size() - CROP)
			_frames.append(img.get_region(Rect2i(pos, CROP)))
			_names.append(tag)
			next += 1.0 / fps
		if el >= secs:
			break
