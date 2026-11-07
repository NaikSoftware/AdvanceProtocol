extends Node
## Знімає справжній хід техніки крізь лінію опор чи двір паркану: машину ставимо за три клітинки до цілі й
## віддаємо MoveCommand, далі все робить гра. Кадри — в пам'яті, PNG пишуться в кінці. Не входить у гру.
## Запуск (вікно, не --headless):
##   $GODOT --path . res://tools/crush_move.tscn -- <out_dir> <map> <zoom> <pole|field|yard> <секунд> <кадрів/с> [вид паркану двору 1..4]

const WINDOW: Vector2i = Vector2i(1600, 900)
const SETTLE_FRAMES: int = 120
const CROP: Vector2i = Vector2i(720, 600)


func _ready() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	if a.size() < 6:
		push_error("crush_move: <out_dir> <map> <zoom> <pole|field|yard> <sec> <fps> [kind]")
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
	var unit: Unit = null
	for u: Unit in state.units_of(0):
		if u.unit_class() in [UnitTypes.UnitClass.TANK, UnitTypes.UnitClass.LIGHT_VEHICLE] and (unit == null or u.ap > unit.ap):
			unit = u
	var spawn: Vector2i = unit.pos
	for i in props._instances.size():
		var inst: Dictionary = props._instances[i]
		var kind: int = int(PropLayer.spec_of(inst["model"]).get("kind", -1))
		var ok: bool = false
		if a[3] == "pole":
			ok = kind == PropLayer.Kind.POLE and props._has_wire(i)
		elif a[3] == "field":
			ok = kind == PropLayer.Kind.FIELD_FENCE
		else:
			ok = kind == PropLayer.Kind.GARDEN_FENCE and (PropLayer.fence_kind_of(inst["model"]) == want_kind or (want_kind < 0 and PropLayer.fence_kind_of(inst["model"]) >= 1))
		var c: Vector2i = (inst["cells"] as Array)[0]
		if not ok or not board.in_bounds(c) or Vector2(c).distance_to(centre) >= best:
			continue
		# Машина стартує за дві клітинки з одного з чотирьох боків; ціль мусить бути досяжною.
		for d: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
			var st: Vector2i = c + d * 2
			if not board.in_bounds(st) or board.kind_at(st) != Terrain.Kind.FIELD or board.kind_at(c + d) != Terrain.Kind.FIELD:
				continue
			unit.pos = st
			if (Pathing.compute_zones(board, unit, {}, {}) as Pathing.Zones).can_reach(c):
				best = Vector2(c).distance_to(centre)
				target = c
				start = st
				at = (inst["transform"] as Transform3D).origin
				break
	unit.pos = spawn
	print("CRUSHMOVE target=%s start=%s unit=%s ap=%s" % [target, start, unit.id if unit != null else -1, unit.ap if unit != null else -1])
	if unit == null or target.x < 0:
		get_tree().quit(1)
		return
	unit.pos = start
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
