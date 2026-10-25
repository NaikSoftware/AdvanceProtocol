extends Node
## Бюджет кадру бою: справжній екран бою на карті, камера на заданих клітинках і зумах; друкує
## draw calls і трикутники кадру (Performance) і знімає кадр. Не входить у гру.
## Запуск (потрібне вікно, не --headless; вікно — за межами екрана):
##   $GODOT --path . --position 6000,0 res://tools/battle_budget.tscn -- <out_dir> <map>[@x,y@zoom] ...
## Без @… знімається центр дошки на MAX і MIN зумі. Рядок BUDGET <map> <cell> z<zoom> dc=… tris=….
## Кадри тримаються в пам'яті й пишуться в кінці: save_png блокує ~1 с і з'їв би наступні кадри.

const WINDOW: Vector2i = Vector2i(1600, 900)
const SETTLE_FRAMES: int = 90


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("battle_budget: очікую <out_dir> <map>[@x,y@zoom] ...")
		get_tree().quit(1)
		return
	var out: String = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	get_window().size = WINDOW
	var shots: Array = []
	for i in range(1, args.size()):
		var parts: PackedStringArray = args[i].split("@")
		var map: String = parts[0]
		var screen: BattleScreen = (load("res://game/battle/battle_screen.tscn") as PackedScene).instantiate()
		add_child(screen)
		screen.setup(load("res://maps/%s.tres" % map) as MapData, 2, 1)
		var board: Board = MatchService.state.board
		var rig: IsoCameraRig = screen.get_node("%CameraRig")
		var views: Array = []
		if parts.size() >= 3:
			var xy: PackedStringArray = parts[1].split(",")
			views.append([Vector2i(int(xy[0]), int(xy[1])), float(parts[2])])
		else:
			var mid := Vector2i(board.width / 2, board.height / 2)
			views.append([mid, IsoCameraRig.MAX_ZOOM])
			views.append([mid, IsoCameraRig.MIN_ZOOM])
		for v: Array in views:
			# center_on() скидає ціль зуму, тож спершу центр, потім зум.
			rig.center_on(v[0])
			rig.zoom_by(float(v[1]) / rig.zoom_level)
			for f in SETTLE_FRAMES:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var dc: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			var tris: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
			var name: String = "%s_%d_%d_z%d" % [map, v[0].x, v[0].y, int(v[1])]
			print("BUDGET %s %s z%d dc=%d tris=%d" % [map, v[0], int(v[1]), dc, tris])
			shots.append([name, get_viewport().get_texture().get_image()])
		screen.free()
		await get_tree().process_frame
	for s: Array in shots:
		(s[1] as Image).save_jpg("%s/%s.jpg" % [out, s[0]], 0.9)
	get_tree().quit()
