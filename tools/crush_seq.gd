extends Node
## Знімає падіння опори чи паркану справжнім екраном бою в реальному часі: кадри тримаються в пам'яті й
## пишуться в кінці (save_png блокує ~1 с). Не входить у гру.
## Запуск (вікно, не --headless):
##   $GODOT --path . res://tools/crush_seq.tscn -- <out_dir> <map> <zoom> <pole|fence|gate> <секунд> <кадрів/с> [напрям x,y]
## Валить ближчу до центру опору з дротом, паркан чи ворота: клітинка, з якої «в'їжджає» техніка, — сусідня проти напряму.

const WINDOW: Vector2i = Vector2i(1600, 900)
const SETTLE_FRAMES: int = 120
const CROP: Vector2i = Vector2i(640, 560)


func _ready() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	if a.size() < 6:
		push_error("crush_seq: <out_dir> <map> <zoom> <pole|fence|gate> <sec> <fps> [x,y]")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(a[0])
	get_window().size = WINDOW
	var screen: BattleScreen = (load("res://game/battle/battle_screen.tscn") as PackedScene).instantiate()
	add_child(screen)
	var map := load("res://maps/%s.tres" % a[1]) as MapData
	screen.setup(map, 2, 1)
	var props: PropLayer = (screen.get_node("%BoardView") as BoardView).props()
	var travel := Vector2i(1, 0)
	if a.size() > 6:
		travel = Vector2i(int(a[6].get_slice(",", 0)), int(a[6].get_slice(",", 1)))
	var centre := Vector2(map.width, map.height) * 0.5
	var cell := Vector2i(-1, -1)
	var at := Vector3.ZERO
	var best: float = INF
	for i in props._instances.size():
		var inst: Dictionary = props._instances[i]
		var c: Vector2i = (inst["cells"] as Array)[0]
		var kind: int = int(PropLayer.spec_of(inst["model"]).get("kind", -1))
		var ok: bool = false
		match a[3]:
			"pole":
				ok = kind == PropLayer.Kind.POLE and props._has_wire(i)
			"fence":
				ok = kind == PropLayer.Kind.FIELD_FENCE or kind == PropLayer.Kind.GARDEN_FENCE
		if ok and c.x >= 0 and c.y >= 0 and c.x < map.width and c.y < map.height:
			var d: float = Vector2(c).distance_to(centre)
			if d < best:
				best = d
				cell = c
				at = (inst["transform"] as Transform3D).origin
	if a[3] == "gate" and not props._gates.is_empty():
		var g: Dictionary = props._gates[0]
		cell = props._gate_cells(g)[1]
		at = Vector3((g["mid"] as Vector2).x, 0.0, (g["mid"] as Vector2).y)
	print("CRUSH cell=%s at=%s travel=%s" % [cell, at, travel])
	var rig: IsoCameraRig = screen.get_node("%CameraRig")
	for f in SETTLE_FRAMES:
		await get_tree().process_frame
	rig.center_on(cell)
	rig.zoom_by(float(a[2]) / rig.zoom_level)
	for f in SETTLE_FRAMES:
		await get_tree().process_frame
	var cam: Camera3D = get_viewport().get_camera_3d()
	var frames: Array[Image] = []
	var dt: float = 1.0 / float(a[5])
	var secs: float = float(a[4])
	var t0: int = Time.get_ticks_usec()
	var next: float = 0.0
	var fired := false
	while true:
		await RenderingServer.frame_post_draw
		var el: float = float(Time.get_ticks_usec() - t0) / 1e6
		if not fired and el >= 0.4:
			fired = true
			props.topple_cell(cell, cell - travel)
		if el >= next:
			var img: Image = get_viewport().get_texture().get_image()
			var k: float = float(img.get_width()) / get_viewport().get_visible_rect().size.x
			var base: Vector2 = cam.unproject_position(props.to_global(at))
			var pos := Vector2i(int(base.x * k) - CROP.x / 2, int(base.y * k) - CROP.y * 2 / 3)
			pos = pos.clamp(Vector2i.ZERO, img.get_size() - CROP)
			frames.append(img.get_region(Rect2i(pos, CROP)))
			next += dt
		if el >= secs:
			break
	print("CRUSH %s z%s frames=%d" % [a[1], a[2], frames.size()])
	for i in frames.size():
		frames[i].save_png("%s/f_%04d.png" % [a[0], i])
	get_tree().quit()
