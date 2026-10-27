extends Node
## Знімає вибух (куля знищення або влучання снаряда) справжнім екраном бою в реальному часі:
## обрізка навколо точки, кадри лежать у пам'яті й пишуться в кінці (save_png блокує ~1 с).
## Не входить у гру. Запуск (вікно, не --headless):
##   $GODOT --path . --position 6000,0 res://tools/blast_seq.tscn -- <out_dir> <map> <zoom> <секунд> <кадрів/с> <boom|shell>

const WINDOW: Vector2i = Vector2i(1600, 900)
const SETTLE_FRAMES: int = 120
const CROP: Vector2i = Vector2i(700, 700)


func _ready() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	if a.size() < 6:
		push_error("blast_seq: <out_dir> <map> <zoom> <sec> <fps> <boom|shell>")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(a[0])
	get_window().size = WINDOW
	var screen: BattleScreen = (load("res://game/battle/battle_screen.tscn") as PackedScene).instantiate()
	add_child(screen)
	var map := load("res://maps/%s.tres" % a[1]) as MapData
	screen.setup(map, 2, 1)
	var cell := Vector2i(map.width / 2, map.height / 2)
	var p: Vector3 = IsoCameraRig.cell_to_world(cell)
	var rig: IsoCameraRig = screen.get_node("%CameraRig")
	for f in SETTLE_FRAMES:
		await get_tree().process_frame
	rig.center_on(cell)
	rig.zoom_by(float(a[2]) / rig.zoom_level)
	for f in SETTLE_FRAMES:
		await get_tree().process_frame
	var cam: Camera3D = get_viewport().get_camera_3d()
	var units: Node = screen.get("_units")
	# Мить стартує перед першим кадром запису, щоб кадр 0 був початком вибуху.
	if a[5] == "shell":
		BattleFx.spawn_hit(units, p, BattleFx.Weapon.SHELL, false)
	else:
		BattleFx.spawn_explosion(units, p, BattleFx.fireball_size(UnitTypes.UnitClass.TANK))
	var frames: Array[Image] = []
	var dt: float = 1.0 / float(a[4])
	var t0: int = Time.get_ticks_usec()
	var next: float = 0.0
	var rendered: int = 0
	var secs: float = float(a[3])
	while true:
		await RenderingServer.frame_post_draw
		rendered += 1
		var el: float = float(Time.get_ticks_usec() - t0) / 1e6
		if el >= next:
			var img: Image = get_viewport().get_texture().get_image()
			var k: float = float(img.get_width()) / get_viewport().get_visible_rect().size.x
			var base: Vector2 = cam.unproject_position(p)
			var pos := Vector2i(int(base.x * k) - CROP.x / 2, int(base.y * k) - CROP.y * 2 / 3)
			pos = pos.clamp(Vector2i.ZERO, img.get_size() - CROP)
			frames.append(img.get_region(Rect2i(pos, CROP)))
			next += dt
		if el >= secs:
			break
	print("BLAST %s z%s frames=%d render_fps=%.1f" % [a[1], a[2], frames.size(), rendered / secs])
	for i in frames.size():
		frames[i].save_png("%s/f_%04d.png" % [a[0], i])
	get_tree().quit()
