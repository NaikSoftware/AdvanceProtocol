extends Node
## Кадри кілець дальності: справжній екран бою, вибраний і оглянутий загін штурмовиків гравця 0
## з дронами (обидва кільця), поруч — вигорілий слід і колія, щоб видно було, чи не ховає їх смуга.
## Не входить у гру.
## Запуск (потрібне вікно):
##   tools/godot_run.sh --path . res://tools/ring_shot.tscn -- <out_dir> <map>[@x,y] ... [--zooms=12,6,20]
## @x,y — переставити загін на клітинку (схил, берег, будинок під кільцем); ще @sx,sy — клітинка
## вигорілого сліду (колія йде через неї вздовж X на ±2 клітинки), типово — поруч із загоном; ще @ux,uy —
## поставити туди інший юніт гравця 0 (юніт під кронами, через клітинку якого йде кільце).
## Кадри: «_norings» — до натиску, основний — з кільцями, «_nolines» — з кільцями, але без ліній під
## кронами. Рядок RINGDC <map> z<zoom> off=… on=… tris_off=… tris_on=…: медіана 9 кадрів без кілець і з
## ними в тому ж процесі. RINGMESH — час побудови сітки кільця дрона.
## Кадри тримаються в пам'яті й пишуться в кінці: save_png блокує ~1 с.

const WINDOW: Vector2i = Vector2i(1600, 900)


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("ring_shot: очікую <out_dir> <map>[@x,y] ...")
		get_tree().quit(1)
		return
	var out: String = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	get_window().size = WINDOW
	var zooms: Array[float] = [12.0, IsoCameraRig.MIN_ZOOM, IsoCameraRig.MAX_ZOOM]
	var maps: Array[String] = []
	for a in args.slice(1):
		if a.begins_with("--zooms="):
			zooms.assign(Array(a.trim_prefix("--zooms=").split(",")).map(func(x: String) -> float: return float(x)))
		else:
			maps.append(a)
	var shots: Array = []
	for spec: String in maps:
		var parts: PackedStringArray = spec.split("@")
		var map: String = parts[0]
		var screen: BattleScreen = (load("res://game/battle/battle_screen.tscn") as PackedScene).instantiate()
		add_child(screen)
		screen.setup(load("res://maps/%s.tres" % map) as MapData, 2, 1)
		var bv: BoardView = screen.get_node("%BoardView")
		var fog_clock: Timer = bv.get("_fog_clock")
		if fog_clock != null:
			fog_clock.stop()
		var state: BattleState = MatchService.state
		var squad: Unit = null
		for u: Unit in state.units_of(0):
			if u.drones_left > 0:
				squad = u
				break
		if squad == null:
			push_error("ring_shot: у гравця 0 на %s нема загону з дронами" % map)
			continue
		if parts.size() > 1:
			var xy: PackedStringArray = parts[1].split(",")
			var spot := Vector2i(int(xy[0]), int(xy[1]))
			var other: Unit = state.unit_at(spot)
			if other != null and other != squad:
				other.pos = squad.pos
			squad.pos = spot
			if parts.size() > 3:
				var uxy: PackedStringArray = parts[3].split(",")
				var cell := Vector2i(int(uxy[0]), int(uxy[1]))
				for u: Unit in state.units_of(0):
					if u != squad and state.unit_at(cell) == null:
						u.pos = cell
						break
			state.refresh_vision(0)
			screen.call("_rebuild_units_for_active_player")
		# Слід бою під кільцями: вигорілий круг і колія через нього.
		var scars: ScarMap = screen.get("_scars")
		var scorch: Vector2i = squad.pos + Vector2i(-1, 2)
		if parts.size() > 2:
			var sxy: PackedStringArray = parts[2].split(",")
			scorch = Vector2i(int(sxy[0]), int(sxy[1]))
		scars.stamp_scorch(scorch)
		scars.stamp_scuff(IsoCameraRig.cell_to_world(scorch - Vector2i(2, 0)), IsoCameraRig.cell_to_world(scorch + Vector2i(2, 0)))
		scars.show_for(state.vision[0])
		var controller: InputController = screen.get("_controller")
		controller.select_unit(squad)
		var rig: IsoCameraRig = screen.get_node("%CameraRig")
		for z: float in zooms:
			rig.center_on(squad.pos)
			rig.zoom_by(z / rig.zoom_level)
			await _settle()
			var off: Vector2i = await _median_frame()
			var name: String = "%s_z%d" % [map, int(z)]
			shots.append([name + "_norings", get_viewport().get_texture().get_image()])
			var t0: int = Time.get_ticks_usec()
			controller.peek_cell(squad.pos)
			print("RINGBUILD %s z%d %.1f ms" % [map, int(z), (Time.get_ticks_usec() - t0) / 1000.0])
			# Сама сітка кільця дрона — без огляду core/.
			var t1: int = Time.get_ticks_usec()
			var band: ArrayMesh = bv.call("_ring_grid_mesh", IsoCameraRig.cell_to_world(squad.pos),
				Vector2(5.0 - BoardView.RING_GRAD_W - BoardView.RING_INNER_MARGIN, 5.0 + BoardView.RING_OUTER))
			print("RINGMESH %s %.1f ms (%d tris)" % [map, (Time.get_ticks_usec() - t1) / 1000.0,
				(band.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3])
			var rings: Array = bv.circles(BoardView.LAYER_INSPECT)
			if rings.size() != 2:
				push_error("ring_shot: %d кілець замість 2 на %s" % [rings.size(), map])
			for f in 3:
				await get_tree().process_frame
			var on: Vector2i = await _median_frame()
			print("RINGDC %s z%d off=%d on=%d tris_off=%d tris_on=%d" % [map, int(z), off.x, on.x, off.y, on.y])
			shots.append([name, get_viewport().get_texture().get_image()])
			# Той самий кадр без ліній під кронами: що на кронах від ліній, а що — самого лісу.
			bv.forest().set_contour_edges(null)
			bv.forest().set_contour_rings(PackedVector4Array(), PackedColorArray())
			for f in 3:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			shots.append([name + "_nolines", get_viewport().get_texture().get_image()])
			# Лінії під кронами — назад: наступний зум знімається з ними.
			bv.call("_publish_contours")
			bv.call("_publish_circles")
			controller.end_peek()
		screen.free()
		await get_tree().process_frame
	for s: Array in shots:
		(s[1] as Image).save_png("%s/%s.png" % [out, s[0]])
	get_tree().quit()


## Камера доїхала й стоїть, прогрів ефектів скінчився.
func _settle() -> void:
	for f in 60:
		await get_tree().process_frame
	var cam: Camera3D = get_viewport().get_camera_3d()
	var still: int = 0
	var last: Transform3D = cam.global_transform
	for f in 600:
		await get_tree().process_frame
		still = still + 1 if cam.global_transform.is_equal_approx(last) else 0
		last = cam.global_transform
		if still >= 30:
			break
	# Прогрів ефектів (Units/Explosion…) ще секунду малює десятки викликів: міряти без нього.
	var warm: int = 0
	while get_node_or_null("BattleScreen/Units/Explosion") != null and warm < 900:
		warm += 1
		await get_tree().process_frame


func _median_frame() -> Vector2i:
	var dcs: Array[int] = []
	var tris: Array[int] = []
	for f in 9:
		await RenderingServer.frame_post_draw
		dcs.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		tris.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
	dcs.sort()
	tris.sort()
	return Vector2i(dcs[4], tris[4])
