extends Node
## Бюджет кадру бою: справжній екран бою на карті, камера на заданих клітинках і зумах; друкує
## draw calls і трикутники кадру (Performance) і знімає кадр. Не входить у гру.
## Запуск (потрібне вікно, не --headless; вікно — за межами екрана):
##   $GODOT --path . --position 6000,0 res://tools/battle_budget.tscn -- <out_dir> [--shadows] <map>[@x,y@zoom] ...
## --shadows: будівлі й руїни кидають справжню тінь сонця — щоб зміряти, скільки це коштує.
## Без @… знімається центр дошки на MAX і MIN зумі. <map>@sel@zoom — вибраний перший юніт гравця 0
## із контурами зон руху поверх пропсів. <map>@behind@<модель>@zoom — той самий юніт за першою
## такою будівлею (з боку від камери), вибраний: розчинення даху й контур зони поверх сліду. <map>@top@x,y,size — ортографічний погляд згори на
## клітинку x,y (size клітинок у кадрі) з межами будівель (червоні) й огорож (блакитні) і найменшим
## проміжком між будівлями та між будівлею й огорожею в метрах. Рядок BUDGET <map> <cell> z<zoom> dc=… tris=….
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
	var shadows: bool = args.has("--shadows")
	# --noshadows: пропси без тіні сонця — щоб зміряти, скільки коштує прохід тіней.
	var no_shadows: bool = args.has("--noshadows")
	for i in range(1, args.size()):
		if args[i] == "--shadows" or args[i] == "--noshadows":
			continue
		var parts: PackedStringArray = args[i].split("@")
		var map: String = parts[0]
		var screen: BattleScreen = (load("res://game/battle/battle_screen.tscn") as PackedScene).instantiate()
		add_child(screen)
		screen.setup(load("res://maps/%s.tres" % map) as MapData, 2, 1)
		var board: Board = MatchService.state.board
		if no_shadows:
			var bv: BoardView = screen.get_node("%BoardView")
			bv.structure_shadows = false
			bv.rebuild_tiles(board)
		if shadows:
			var props: PropLayer = (screen.get_node("%BoardView") as BoardView).props()
			for mmi: MultiMeshInstance3D in props.find_children("*", "MultiMeshInstance3D", false, false):
				var k: int = int(PropLayer.spec_of(StringName(mmi.name))["kind"])
				if k == PropLayer.Kind.STRUCTURE or k == PropLayer.Kind.RUIN:
					mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var rig: IsoCameraRig = screen.get_node("%CameraRig")
		var views: Array = []
		if parts.size() >= 3 and parts[1] == "top":
			var a: PackedStringArray = parts[2].split(",")
			var name: String = "%s_top_%s_%s" % [map, a[0], a[1]]
			shots.append([name, await _top_down(screen, Vector2(float(a[0]), float(a[1])), float(a[2]), name)])
			screen.free()
			await get_tree().process_frame
			continue
		if parts.size() >= 4 and parts[1] == "behind":
			# Юніт за будівлею з боку, протилежного камері: дах чи вежа мусять розчинитися, а
			# контур зони — лягти поверх сліду будівлі.
			var target := Vector2i(-1, -1)
			for inst in (screen.get_node("%BoardView") as BoardView).props().all_instances():
				var c: Vector2i = (inst["cells"] as Array)[0]
				if String(inst["model"]) == parts[2] and board.in_bounds(c - Vector2i.ONE):
					target = c
					break
			if target == Vector2i(-1, -1):
				push_error("battle_budget: нема %s на дошці" % parts[2])
			else:
				var unit: Unit = MatchService.state.units_of(0)[0]
				unit.pos = target - Vector2i.ONE
				screen.call("_rebuild_units_for_active_player")
				(screen.get("_controller") as InputController).select_unit(unit)
				views.append([unit.pos, float(parts[3])])
		elif parts.size() >= 3 and parts[1] == "sel":
			var unit: Unit = MatchService.state.units_of(0)[0]
			(screen.get("_controller") as InputController).select_unit(unit)
			views.append([unit.pos, float(parts[2])])
		elif parts.size() >= 3:
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


## Погляд згори: межі будівель і огорож, найменші проміжки — числом у кадрі й у виводі.
func _top_down(screen: BattleScreen, at: Vector2, span: float, name: String) -> Image:
	var props: PropLayer = (screen.get_node("%BoardView") as BoardView).props()
	var houses: Array[Rect2] = []
	var fences: Array[Rect2] = []
	var window := Rect2(at - Vector2.ONE * span * 0.5, Vector2.ONE * span)
	for inst in props.all_instances():
		var spec: Dictionary = PropLayer.spec_of(inst["model"])
		var box: AABB = (inst["transform"] as Transform3D) * ((PropLayer.model(inst["model"]) as Dictionary)["aabb"] as AABB)
		var r := Rect2(box.position.x, box.position.z, box.size.x, box.size.z)
		if not window.intersects(r):
			continue
		var k: int = int(spec["kind"])
		if k == PropLayer.Kind.STRUCTURE or k == PropLayer.Kind.RUIN:
			houses.append(r)
		elif k == PropLayer.Kind.GARDEN_FENCE:
			fences.append(r)
	var hh: float = INF
	for i in houses.size():
		for j in range(i + 1, houses.size()):
			hh = minf(hh, _gap(houses[i], houses[j]))
	var hf: float = INF
	for h in houses:
		for f in fences:
			hf = minf(hf, _gap(h, f))
	var lines := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mat.vertex_color_use_as_albedo = true
	if not houses.is_empty() or not fences.is_empty():
		lines.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	for pair: Array in [[houses, Color.RED], [fences, Color.CYAN]]:
		for r: Rect2 in pair[0]:
			var c: Array = [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
			for k in 4:
				for v: Vector2 in [c[k], c[(k + 1) % 4]]:
					lines.surface_set_color(pair[1])
					lines.surface_add_vertex(Vector3(v.x, 5.0, v.y))
	if not houses.is_empty() or not fences.is_empty():
		lines.surface_end()
	if not houses.is_empty() or not fences.is_empty():
		var outline := MeshInstance3D.new()
		outline.mesh = lines
		screen.add_child(outline)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = span
	cam.position = Vector3(at.x, 60.0, at.y)
	cam.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	cam.far = 200.0
	screen.add_child(cam)
	cam.make_current()
	var label := Label.new()
	label.text = "%s: будівля–будівля %.1f м, будівля–огорожа %.1f м" % [name, hh * 8.0, hf * 8.0]
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", Color.YELLOW)
	label.position = Vector2(20, 860)
	add_child(label)
	print("TOPDOWN %s house_gap_m=%.2f fence_gap_m=%.2f houses=%d fences=%d" % [name, hh * 8.0, hf * 8.0, houses.size(), fences.size()])
	for f in SETTLE_FRAMES:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	label.free()
	return img


## Найменша відстань між двома прямокутниками в XZ, клітинки (0 — перетинаються).
func _gap(a: Rect2, b: Rect2) -> float:
	var dx: float = maxf(0.0, maxf(b.position.x - a.end.x, a.position.x - b.end.x))
	var dz: float = maxf(0.0, maxf(b.position.y - a.end.y, a.position.y - b.end.y))
	return sqrt(dx * dx + dz * dz)
