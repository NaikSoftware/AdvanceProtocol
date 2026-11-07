extends Node
## Виклики малювання під час найгіршого вибуху: крок з клітинки (fx,fy) у (tx,ty) на карті; друкує базу кадру й максимум.
## Запуск (вікно): $GODOT --path . res://tools/crush_dc.tscn -- <map> <fx> <fy> <tx> <ty> <zoom>


func _ready() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	if a.size() < 6:
		get_tree().quit(1)
		return
	get_window().size = Vector2i(1600, 900)
	var screen: BattleScreen = (load("res://game/battle/battle_screen.tscn") as PackedScene).instantiate()
	add_child(screen)
	screen.setup(load("res://maps/%s.tres" % a[0]) as MapData, 2, 1)
	var props: PropLayer = (screen.get_node("%BoardView") as BoardView).props()
	# NOFX=1 — без мить ефектів: лише уламки.
	if OS.get_environment("NOFX") == "1":
		for c in props.topple_hit.get_connections():
			props.topple_hit.disconnect(c["callable"])
		for c in props.topple_landed.get_connections():
			props.topple_landed.disconnect(c["callable"])
	var rig: IsoCameraRig = screen.get_node("%CameraRig")
	var to := Vector2i(int(a[3]), int(a[4]))
	rig.center_on(to)
	rig.zoom_by(float(a[5]) / rig.zoom_level)
	for f in 240:
		await get_tree().process_frame
	var base: int = 0
	for f in 30:
		await RenderingServer.frame_post_draw
		base = maxi(base, int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)))
	props.topple_cell(to, Vector2i(int(a[1]), int(a[2])))
	var worst: int = 0
	for f in 240:
		await RenderingServer.frame_post_draw
		worst = maxi(worst, int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)))
	print("CRUSHDC base=%d worst=%d bursts_started falls_left=%d" % [base, worst, props.falling_count()])
	get_tree().quit()
