extends Node
## Кадри повтору ходів противників («запис із дрона») на справжній карті: гравець 0 ходить і стріляє,
## гравець 1 після гейта дивиться повтор. Розвідане гравця 1 — уся дошка, а біля центру поставлено
## сутичку обох сторін (танк, піхота, причіпна гармата чи інженер), щоб у кадрі були обидві сторони
## й обидва види юнітів: з моделлю й заступники.
## Запуск (потрібне вікно, не --headless):
##   tools/godot_run.sh --path . --rendering-method <mobile|gl_compatibility> --fixed-fps 30 res://tools/replay_look_shot.tscn -- <out_dir> <map> <zoom> [locale]
## --fixed-fps 30: кадр — рівно 1/30 с часу гри на будь-якому GPU, тож на повільному gl_compatibility
## повтор не проскакує за кілька кадрів, і кадри однаково лягають на такти.
## Кадри <out_dir>/<map>_<renderer>_z<zoom>_: _1 і _2 — на 5-му і 15-му кадрі повтору (такти руху), _3 і _4 — постріл
## останнього такту, через FIRE_AFTER і SMOKE_AFTER кадрів після початку його подій; пара з тим самим кадром (час
## спинено, зерно сховано): _on з грейдом, _off без нього. У лог іде
## BAR — середня різниця (0..255) пікселів смуг HP між _on і _off: смуга мусить лишитись у своєму кольорі;
## <tag>_live — та сама сутичка в живій грі до ходу, без повтору.
## WORLD — середня насиченість кадру без і з грейдом.

const EARLY_SHOTS: Array[int] = [5, 15]
const FIRE_AFTER: int = 4
const SMOKE_AFTER: int = 12
const PAIR_AT: int = 12
const MAX_FRAMES: int = 120
const E: int = 2
const W: int = 6

var _screen: BattleScreen
var _taken: Dictionary = {}


func _ready() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	if a.size() < 3:
		push_error("replay_look_shot: <out_dir> <map> <zoom> [locale]")
		get_tree().quit(1)
		return
	OS.low_processor_usage_mode = false
	TranslationServer.set_locale(a[3] if a.size() > 3 else "uk")
	DirAccess.make_dir_recursive_absolute(a[0])
	get_window().size = Vector2i(1280, 720)
	var method: String = RenderingServer.get_current_rendering_method()
	print("METHOD ", method)
	_screen = (load("res://game/battle/battle_screen.tscn") as PackedScene).instantiate()
	add_child(_screen)
	_screen.setup(load("res://maps/%s.tres" % a[1]) as MapData, 2, 7)
	var st: BattleState = MatchService.state
	var f: Vector2i = _free_near(st, Vector2i(st.board.width / 2, st.board.height / 2))
	var tank: Unit = st.add_unit(5, 0, _free_near(st, f + Vector2i(-2, 0)), E)
	var squad: Unit = st.add_unit(0, 0, _free_near(st, f + Vector2i(-3, 2)), E)
	var scout: Unit = st.add_unit(4, 0, _free_near(st, f + Vector2i(-5, 1)), E)
	st.add_unit(9, 0, _free_near(st, f + Vector2i(-4, -1)), E)
	var target: Unit = st.add_unit(8, 1, _free_in_range(st, tank.pos, 3), W)
	st.add_unit(1, 1, _free_near(st, f + Vector2i(2, 2)), W)
	st.add_unit(11, 1, _free_near(st, f + Vector2i(2, -2)), W)
	for y in st.board.height:
		for x in st.board.width:
			st.vision[1].reveal(Vector2i(x, y))
	st.refresh_vision(0)
	MatchService.replay_log.mark(1, st)
	_screen._rebuild_units_for_active_player()
	await _frames(20)
	(_screen.get_node("%CameraRig") as IsoCameraRig).set_zoom(float(a[2]))
	(_screen.get_node("%CameraRig") as IsoCameraRig).center_on(f)
	await _frames(5)
	var tag: String = "%s/%s_%s_z%s" % [a[0], a[1], "gl" if method == "gl_compatibility" else method, a[2]]
	_taken[tag + "_live"] = get_viewport().get_texture().get_image()
	var hud: CanvasItem = _screen.get_node("%Hud")
	var dc_hud: int = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	hud.visible = false
	await _frames(3)
	print("LIVE draw calls HUD shown %d hidden %d" % [dc_hud, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)])
	hud.visible = true
	_submit(MoveCommand.create(squad.id, _free_near(st, squad.pos + Vector2i(1, 0))))
	await _wait_events()
	_submit(MoveCommand.create(scout.id, _free_near(st, scout.pos + Vector2i(2, 1))))
	await _wait_events()
	_submit(FireCommand.create(tank.id, target.id))
	await _wait_events()
	_submit(EndTurnCommand.create())
	await _wait_events()
	var rig: IsoCameraRig = _screen.get_node("%CameraRig")
	rig.set_zoom(float(a[2]))
	((_screen.get_node("%HandoverGate") as Control).get_node("%ConfirmButton") as Button).pressed.emit()
	print("REPLAY ", _screen._replay_state != null, " zoom ", rig.zoom_level, " beats ", (_screen.get_node("%ReplayOverlay").get_node("%Progress") as Range).max_value)
	var progress: Range = _screen.get_node("%ReplayOverlay").get_node("%Progress")
	var frame: int = 0
	var fire_at: int = -1
	var t0: int = Time.get_ticks_msec()
	while _screen._replay_state != null and frame < MAX_FRAMES:
		await RenderingServer.frame_post_draw
		frame += 1
		if frame in EARLY_SHOTS:
			_taken["%s_%d" % [tag, EARLY_SHOTS.find(frame) + 1]] = get_viewport().get_texture().get_image()
		if fire_at < 0 and progress.value == progress.max_value and _screen._event_player.is_playing():
			fire_at = frame
		if fire_at >= 0 and frame - fire_at in [FIRE_AFTER, SMOKE_AFTER]:
			_taken["%s_%d" % [tag, 3 if frame - fire_at == FIRE_AFTER else 4]] = get_viewport().get_texture().get_image()
		if frame == PAIR_AT:
			await _pair(tag)
	print("LAST BEAT events from frame ", fire_at)
	print("FRAMES ", frame, " in ", Time.get_ticks_msec() - t0, " ms")
	for path: String in _taken:
		(_taken[path] as Image).save_png(path + ".png")
	get_tree().quit()


func _pair(tag: String) -> void:
	var overlay: ReplayOverlay = _screen.get_node("%ReplayOverlay")
	var grain: CanvasItem = overlay.get_node("Grain")
	var scale: float = Engine.time_scale
	Engine.time_scale = 0.0
	grain.visible = false
	await _frames(3)
	var on: Image = get_viewport().get_texture().get_image()
	overlay._grade(false)
	await _frames(3)
	var off: Image = get_viewport().get_texture().get_image()
	var gpu_off: float = await _gpu_ms()
	overlay._grade(true)
	var gpu_on: float = await _gpu_ms()
	var dc_on: int = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	overlay.visible = false
	await _frames(3)
	var dc_off: int = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	overlay.visible = true
	print("GPU ms grade off %.3f on %.3f; draw calls overlay shown %d hidden %d" % [gpu_off, gpu_on, dc_on, dc_off])
	grain.visible = true
	Engine.time_scale = scale
	_taken[tag + "_on"] = on
	_taken[tag + "_off"] = off
	var bar := Vector2.ZERO
	var sat := Vector2.ZERO
	var n: int = 0
	for y in range(0, off.get_height(), 2):
		for x in range(0, off.get_width(), 2):
			var c: Color = off.get_pixel(x, y)
			var g: Color = on.get_pixel(x, y)
			sat += Vector2(c.s, g.s)
			for owner in UnitView.PLAYER_COLORS.size():
				var o: Color = UnitView.hp_fill_color(owner)
				if absf(c.r - o.r) + absf(c.g - o.g) + absf(c.b - o.b) < 0.06:
					bar += Vector2(absf(c.r - g.r) + absf(c.g - g.g) + absf(c.b - g.b), 1.0)
	n = off.get_width() * off.get_height() / 4
	print("BAR mean |on-off| per channel %.1f over %d px" % [bar.x / maxf(bar.y, 1.0) / 3.0 * 255.0, int(bar.y)])
	print("WORLD saturation off %.3f on %.3f" % [sat.x / n, sat.y / n])


## Середній час кадру на GPU за 20 кадрів, при спиненому часі.
func _gpu_ms() -> float:
	var vp: RID = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	await _frames(3)
	var sum: float = 0.0
	for i in 20:
		await RenderingServer.frame_post_draw
		sum += RenderingServer.viewport_get_measured_render_time_gpu(vp)
	return sum / 20.0


## Вільна клітинка поля чи дороги в радіусі зброї r від from, якомога далі вздовж +X.
func _free_in_range(st: BattleState, from: Vector2i, r: int) -> Vector2i:
	for dx in range(r, 0, -1):
		for ady in r + 1:
			for dy in [ady, -ady]:
				var c := from + Vector2i(dx, dy)
				if dx * dx + dy * dy <= r * r and st.board.in_bounds(c) and st.unit_at(c) == null \
						and st.board.kind_at(c) in [Terrain.Kind.FIELD, Terrain.Kind.ROAD]:
					return c
	return _free_near(st, from + Vector2i(r, 0))


func _submit(cmd: Command) -> void:
	var err: String = MatchService.submit(cmd)
	print("SUBMIT ", cmd.get_script().get_global_name(), " -> ", err if err != "" else "ok")


func _wait_events() -> void:
	await _frames(10)
	while _screen._event_player.is_playing():
		await get_tree().process_frame
	await _frames(10)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw


## Найближча до p вільна клітинка поля чи дороги.
func _free_near(st: BattleState, p: Vector2i) -> Vector2i:
	for r in 8:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var c := p + Vector2i(dx, dy)
				if maxi(absi(dx), absi(dy)) != r or not st.board.in_bounds(c) or st.unit_at(c) != null:
					continue
				if st.board.kind_at(c) in [Terrain.Kind.FIELD, Terrain.Kind.ROAD]:
					return c
	return p
