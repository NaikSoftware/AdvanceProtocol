extends Node
## Знімає справжній хід техніки крізь лінію опор чи двір паркану: машину ставимо за три клітинки до цілі й
## віддаємо MoveCommand, далі все робить гра. Кадри — в пам'яті, PNG пишуться в кінці. Не входить у гру.
## Запуск (вікно, не --headless):
##   $GODOT --path . res://tools/crush_move.tscn -- <out_dir> <map> <zoom> <pole|yard> <секунд> <кадрів/с> [вид паркану двору 1..4]

const WINDOW: Vector2i = Vector2i(1600, 900)
const SETTLE_FRAMES: int = 120
const CROP: Vector2i = Vector2i(720, 600)


func _ready() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	if a.size() < 6:
		push_error("crush_move: <out_dir> <map> <zoom> <pole|yard> <sec> <fps> [kind]")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(a[0])
	get_window().size = WINDOW
	var screen: BattleScreen = (load("res://game/battle/battle_screen.tscn") as PackedScene).instantiate()
	add_child(screen)
	var map := load("res://maps/%s.tres" % a[1]) as MapData
	screen.setup(map, 2, 1)
	var props: PropLayer = (screen.get_node("%BoardView") as BoardView).props()
	var service: Node = screen.get("_match_service")
	var state: BattleState = service.state
	var want_kind: int = int(a[6]) if a.size() > 6 else 1
	var board: Board = state.board
	var centre := Vector2(map.width, map.height) * 0.5
	var target := Vector2i(-1, -1)
	var start := Vector2i.ZERO
	var at := Vector3.ZERO
	var best: float = INF
	for i in props._instances.size():
		var inst: Dictionary = props._instances[i]
		var kind: int = int(PropLayer.spec_of(inst["model"]).get("kind", -1))
		var ok: bool = false
		if a[3] == "pole":
			ok = kind == PropLayer.Kind.POLE and props._has_wire(i)
		else:
			ok = kind == PropLayer.Kind.GARDEN_FENCE and PropLayer.fence_kind_of(inst["model"]) == want_kind
		var c: Vector2i = (inst["cells"] as Array)[0]
		if not ok or c.x < 4 or c.y < 1 or c.x >= map.width - 2 or c.y >= map.height - 1:
			continue
		var run: bool = true
		for k in range(-3, 2):
			run = run and board.in_bounds(c + Vector2i(k, 0)) and board.kind_at(c + Vector2i(k, 0)) == Terrain.Kind.FIELD
		if run and Vector2(c).distance_to(centre) < best:
			best = Vector2(c).distance_to(centre)
			target = c
			at = (inst["transform"] as Transform3D).origin
	start = target - Vector2i(2, 0)
	var unit: Unit = null
	for u: Unit in state.units_of(0):
		if u.unit_class() in [UnitTypes.UnitClass.TANK, UnitTypes.UnitClass.LIGHT_VEHICLE] and (unit == null or u.ap > unit.ap):
			unit = u
	print("CRUSHMOVE target=%s start=%s unit=%s ap=%s" % [target, start, unit.id if unit != null else -1, unit.ap if unit != null else -1])
	if unit == null or target.x < 0:
		get_tree().quit(1)
		return
	unit.pos = start
	print("CRUSHMOVE active=%s owner=%s class=%s" % [state.active_player, unit.owner, unit.unit_class()])
	print("CRUSHMOVE blocked=%s" % [state.known_blocked_map(0).keys().slice(0, 8)])
	var zz: Pathing.Zones = Pathing.compute_zones(board, unit, {}, {})
	for k in range(-1, 3):
		print("CRUSHMOVE reach %s=%s kind=%s" % [start + Vector2i(k, 0), zz.can_reach(start + Vector2i(k, 0)), board.kind_at(start + Vector2i(k, 0))])
	state.refresh_vision(0)
	screen.call("_rebuild_units_for_active_player", true)
	var rig: IsoCameraRig = screen.get_node("%CameraRig")
	for f in SETTLE_FRAMES:
		await get_tree().process_frame
	rig.center_on(target)
	rig.zoom_by(float(a[2]) / rig.zoom_level)
	for f in SETTLE_FRAMES:
		await get_tree().process_frame
	var cam: Camera3D = get_viewport().get_camera_3d()
	var frames: Array[Image] = []
	var dt: float = 1.0 / float(a[5])
	var t0: int = Time.get_ticks_usec()
	var next: float = 0.0
	var fired := false
	while true:
		await RenderingServer.frame_post_draw
		var el: float = float(Time.get_ticks_usec() - t0) / 1e6
		if not fired:
			fired = true
			print("CRUSHMOVE submit=%s" % service.submit(MoveCommand.create(unit.id, target)))
		if el >= next:
			var img: Image = get_viewport().get_texture().get_image()
			var k: float = float(img.get_width()) / get_viewport().get_visible_rect().size.x
			var base: Vector2 = cam.unproject_position(props.to_global(at))
			var pos := Vector2i(int(base.x * k) - CROP.x / 2, int(base.y * k) - CROP.y * 2 / 3)
			pos = pos.clamp(Vector2i.ZERO, img.get_size() - CROP)
			frames.append(img.get_region(Rect2i(pos, CROP)))
			next += dt
		if el >= float(a[4]):
			break
	print("CRUSHMOVE %s z%s frames=%d falls=%d" % [a[1], a[2], frames.size(), props.falling_count()])
	for i in frames.size():
		frames[i].save_png("%s/f_%04d.png" % [a[0], i])
	get_tree().quit()
