extends Node
## Знімає потік мирного диму справжнім екраном бою в реальному часі: обрізка навколо шлейфу, кадри
## тримаються в пам'яті й пишуться в кінці (save_png блокує ~1 с). Не входить у гру.
## Запуск (вікно, не --headless):
##   $GODOT --path . --position 6000,0 res://tools/smoke_seq.tscn -- <out_dir> <map> <zoom> <hearth> <секунд> <кадрів/с>
## Друкує SMOKE-рядок із числом кадрів і справжнім fps рендера.

const WINDOW: Vector2i = Vector2i(1600, 900)
const SETTLE_FRAMES: int = 120
const CROP: Vector2i = Vector2i(560, 620)


func _ready() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	if a.size() < 6:
		push_error("smoke_seq: <out_dir> <map> <zoom> <hearth> <sec> <fps>")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(a[0])
	get_window().size = WINDOW
	var screen: BattleScreen = (load("res://game/battle/battle_screen.tscn") as PackedScene).instantiate()
	add_child(screen)
	screen.setup(load("res://maps/%s.tres" % a[1]) as MapData, 2, 1)
	var layer: WreckLayer = screen.get("_wreck_layer")
	var pts: Array[Vector3] = layer.hearth_points()
	var p: Vector3 = layer.to_global(pts[int(a[3]) % pts.size()])
	var rig: IsoCameraRig = screen.get_node("%CameraRig")
	# Екран спершу сам наводить камеру на перший юніт; наводимо вдруге, коли він затих.
	for f in SETTLE_FRAMES:
		await get_tree().process_frame
	rig.center_on(Vector2i(roundi(p.x), roundi(p.z)))
	rig.zoom_by(float(a[2]) / rig.zoom_level)
	for f in SETTLE_FRAMES:
		await get_tree().process_frame
	var cam: Camera3D = get_viewport().get_camera_3d()
	var frames: Array[Image] = []
	var dt: float = 1.0 / float(a[5])
	var t0: int = Time.get_ticks_usec()
	var next: float = 0.0
	var rendered: int = 0
	var secs: float = float(a[4])
	while true:
		await RenderingServer.frame_post_draw
		rendered += 1
		var el: float = float(Time.get_ticks_usec() - t0) / 1e6
		if el >= next:
			# Вікно може змінити розмір під час запуску: кроп рахуємо щокадру з живого зображення.
			var img: Image = get_viewport().get_texture().get_image()
			var k: float = float(img.get_width()) / get_viewport().get_visible_rect().size.x
			var base: Vector2 = cam.unproject_position(p)
			var top: Vector2 = cam.unproject_position(p + Vector3(0, WreckLayer.HEARTH_HEIGHT, 0))
			var pos := Vector2i(int(base.x * k) - CROP.x / 2, int((base.y + top.y) * 0.5 * k) - CROP.y / 2)
			pos = pos.clamp(Vector2i.ZERO, img.get_size() - CROP)
			frames.append(img.get_region(Rect2i(pos, CROP)))
			next += dt
		if el >= secs:
			break
	print("SMOKE %s z%s h%s frames=%d render_fps=%.1f img=%s" % [a[1], a[2], a[3], frames.size(), rendered / secs, get_viewport().get_texture().get_size()])
	for i in frames.size():
		frames[i].save_png("%s/f_%04d.png" % [a[0], i])
	get_tree().quit()
