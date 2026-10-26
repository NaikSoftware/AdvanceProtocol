extends Node
## Перший скрол у бою: час кожного кадру при русі камери справжніми подіями дотику, два проходи
## підряд (перший — те, що бачить гравець, другий — для порівняння). Не входить у гру.
## Запуск (вікно, не --headless; вікно — за межами екрана):
##   $GODOT --path . --position 6000,0 --disable-vsync res://tools/scroll_hitch.tscn -- <map> [--wait=N] [--gate] [--nowarm]
## --gate: бій починається як у грі (launch, гейт, confirmed); --nowarm: без об'їзду дошки за гейтом.
## Друкує HITCH <map> pass=<n> frames=<k> median=<мс> max=<мс> over33=<k> top=[…] pipelines=<нових компіляцій>.
## Вимір чесний лише на тихій машині: чужі процеси на тому ж GPU додають десятки мс до будь-якого кадру.

const WINDOW: Vector2i = Vector2i(1600, 900)
const LEG_FRAMES: int = 70
const STEP_PX: float = 14.0
const PIPELINE_MONITORS: Array[String] = ["PIPELINE_COMPILATIONS_CANVAS", "PIPELINE_COMPILATIONS_MESH", "PIPELINE_COMPILATIONS_SURFACE", "PIPELINE_COMPILATIONS_DRAW", "PIPELINE_COMPILATIONS_SPECIALIZATION"]


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var map: String = args[0]
	var wait: int = 120
	for a in args:
		if a.begins_with("--wait="):
			wait = int(a.get_slice("=", 1))
	get_window().size = WINDOW
	var screen: BattleScreen = (load("res://game/battle/battle_screen.tscn") as PackedScene).instantiate()
	add_child(screen)
	if args.has("--gate"):
		screen.set("_board_warmed", args.has("--nowarm"))
		MatchService.configure("res://maps/%s.tres" % map, 2, 1)
		screen.launch(MatchService)
		for f in wait:
			await get_tree().process_frame
		(screen.get("_gate") as Node).call("_on_confirm_pressed")
	else:
		screen.setup(load("res://maps/%s.tres" % map) as MapData, 2, 1)
		for f in wait:
			await get_tree().process_frame
	var legs: Array[Vector2] = [Vector2(-STEP_PX, 0), Vector2(0, STEP_PX), Vector2(STEP_PX, 0), Vector2(0, -STEP_PX)]
	for pass_no in 2:
		var times: Array[float] = []
		var comp0: int = _compilations()
		var last: int = Time.get_ticks_usec()
		# Справжні події дотику: _input екрана бою знімає обмеження частоти кадрів, як у гравця.
		var pos := Vector2(800, 450)
		_touch(pos, true)
		for leg in legs:
			for f in LEG_FRAMES:
				pos += leg
				var drag := InputEventScreenDrag.new()
				drag.index = 0
				drag.position = pos
				drag.relative = leg
				Input.parse_input_event(drag)
				await get_tree().process_frame
				var now: int = Time.get_ticks_usec()
				times.append((now - last) / 1000.0)
				last = now
		_touch(pos, false)
		var sorted: Array[float] = times.duplicate()
		sorted.sort()
		sorted.reverse()
		var over: int = sorted.filter(func(t: float) -> bool: return t > 33.0).size()
		var top: Array[String] = []
		for i in 5:
			top.append("%.1f@%d" % [sorted[i], times.find(sorted[i])])
		print("HITCH %s pass=%d frames=%d median=%.1f max=%.1f over33=%d top=%s pipelines=%d" % [map, pass_no + 1, times.size(), sorted[sorted.size() / 2], sorted[0], over, top, _compilations() - comp0])
		for f in 30:
			await get_tree().process_frame
	get_tree().quit()


func _touch(pos: Vector2, pressed: bool) -> void:
	var t := InputEventScreenTouch.new()
	t.index = 0
	t.position = pos
	t.pressed = pressed
	Input.parse_input_event(t)


func _compilations() -> int:
	var n: int = 0
	for m in PIPELINE_MONITORS:
		if ClassDB.class_has_integer_constant("Performance", m):
			n += int(Performance.get_monitor(ClassDB.class_get_integer_constant("Performance", m)))
	return n
