extends Node
## Бюджет викликів малювання інтерфейсу бою: свій і ворожий середній танк за 3 клітинки, зум 9,
## три стани — idle, selected (вибрано свій), shot_preview (тап по ворогу). Друкує повні draw calls
## кадру й окремо канвас (інтерфейс), 3D і тіні; медіана 9 кадрів при завмерлій камері.
## Запуск (потрібне вікно, не --headless; міряти по одному):
##   tools/godot_run.sh --solo --path . res://tools/hud_budget.tscn -- <map> [--hide=<вузол,вузол>]
## --hide ховає вказані вузли Hud (за іменем) після входу в стан — так розкладають, звідки беруться
## виклики. Рядок: HUDDC <map> <state> total=… canvas=… 3d=… shadow=…
## Бюджет: selected <= база+4, shot_preview <= база+8 (база — той самий стан до перебудови інтерфейсу).
## Виміри total (база — коміт перед інтерфейсом):
##   карта       стан          база   до правки   після
##   river       idle          61     63          63
##   river       selected      64     73          66
##   river       shot_preview  67     102         74
##   crossroads  idle          67     69          69
##   crossroads  selected      71     78          72
##   crossroads  shot_preview  74     109         81

const ZOOM: float = 9.0
var _hide: PackedStringArray = PackedStringArray()

func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var map_name: String = args[0]
	for a in args:
		if a.begins_with("--hide="):
			_hide = a.substr(7).split(",")
	get_window().size = Vector2i(1600, 900)
	_run.call_deferred(map_name)

func _frames(n: int) -> void:
	for f in n:
		await get_tree().process_frame

func _med(label: String, map_name: String) -> void:
	var vp: RID = get_viewport().get_viewport_rid()
	var tot: Array[int] = []
	var can: Array[int] = []
	var d3: Array[int] = []
	var sh: Array[int] = []
	for f in 9:
		await RenderingServer.frame_post_draw
		tot.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		can.append(RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME))
		d3.append(RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME))
		sh.append(RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME))
	tot.sort()
	can.sort()
	d3.sort()
	sh.sort()
	print("HUDDC %s %s total=%d canvas=%d 3d=%d shadow=%d" % [map_name, label, tot[4], can[4], d3[4], sh[4]])

func _apply_hide(screen: Node) -> void:
	for n in _hide:
		var node: Node = screen.get_node("%Hud").find_child(n, true, false)
		if node is CanvasItem:
			(node as CanvasItem).visible = false
		else:
			print("HUDDC hide miss: ", n)

func _run(map_name: String) -> void:
	var screen: Node = (load("res://game/battle/battle_screen.tscn") as PackedScene).instantiate()
	add_child(screen)
	screen.call("setup", load("res://maps/%s.tres" % map_name), 2, 1)
	var state = screen.get("_match_service").state
	var ctrl = screen.call("input_controller")
	var rig: Node = screen.get_node("%CameraRig")
	var fog_clock = (screen.get_node("%BoardView")).get("_fog_clock")
	if fog_clock != null:
		fog_clock.stop()
	(screen.get_node("%HandoverGate") as Control).visible = false
	var board = state.board
	var offs: Array[Vector2i] = [Vector2i(0, 0), Vector2i(3, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(-1, 0), Vector2i(1, 1), Vector2i(-1, 1)]
	var centre := Vector2i(board.width / 2, board.height / 2)
	var best := Vector2i(-1, -1)
	var best_cost: int = 1 << 30
	for y in board.height:
		for x in board.width:
			var c := Vector2i(x, y)
			var ok := true
			for o in offs:
				var p: Vector2i = c + o
				if not board.in_bounds(p) or not board.kind_at(p) in [Terrain.Kind.ROAD, Terrain.Kind.FIELD]:
					ok = false
					break
			if not ok:
				continue
			var cost: int = (c - centre).length_squared()
			if cost < best_cost:
				best_cost = cost
				best = c
	await _frames(90)
	state.units.clear()
	state.wrecks.clear()
	state.mines.clear()
	var tank = state.add_unit(5, 0, best, Board.facing_towards(best, best + Vector2i(3, 0)))
	var enemy = state.add_unit(5, 1, best + Vector2i(3, 0), Board.facing_towards(best + Vector2i(3, 0), best))
	state.active_player = 0
	state.refresh_vision_all()
	screen.call("_rebuild_units_for_active_player", true)
	rig.center_on(best + Vector2i(1, 0))
	rig.zoom_by(ZOOM / rig.zoom_level)
	screen.get_node("%Hud").call("refresh")
	await _frames(60)
	await _med("idle", map_name)
	ctrl.select_unit(tank)
	await _frames(40)
	_apply_hide(screen)
	await _med("selected", map_name)
	ctrl.tap_cell(enemy.pos)
	await _frames(40)
	_apply_hide(screen)
	await _med("shot_preview", map_name)
	get_tree().quit()
