extends Node
## Бюджет кадру бою: справжній екран бою на карті, камера на заданих клітинках і зумах; друкує
## draw calls і трикутники кадру (Performance) і знімає кадр. Не входить у гру.
## Запуск (потрібне вікно, не --headless; вікно — за межами екрана):
##   $GODOT --path . --position 6000,0 res://tools/battle_budget.tscn -- <out_dir> [--shadows] <map>[@x,y@zoom] ...
## --shadows: будівлі й руїни кидають справжню тінь сонця — щоб зміряти, скільки це коштує.
## Без @… знімається центр дошки на MAX і MIN зумі. <map>@fadeseq@<модель>@zoom — 12 кадрів розчинення
## даху: юніт стає за будівлею й іде геть. <map>@yard@<садиба>@zoom — танк і піхота гравця 0
## у дворі садиби з макету карти (VillageLayout), камера на хаті. <map>@sel@zoom — вибраний перший юніт гравця 0
## із контурами зон руху поверх пропсів. <map>@behind@<модель>@zoom — той самий юніт за першою
## такою будівлею (з боку від камери), вибраний: розчинення даху й контур зони поверх сліду. <map>@top@x,y,size — ортографічний погляд згори на
## клітинку x,y (size клітинок у кадрі) з межами будівель (червоні) й огорож (блакитні) і найменшим
## проміжком між будівлями та між будівлею й огорожею в метрах. Рядок BUDGET <map> <cell> z<zoom> dc=… tris=….
## --diag: після кожного кадру ховає по черзі групи вузлів (ліс за класами, діти BoardView, 3D-діти
## екрана) і друкує, скільки кожна коштує: рядок DIAG <map> <cell> z<zoom> <група>(<вузлів>) dc=… tris=….
## <map>@forest@x,y@zoom — танк гравця 0 проламав ліс на x,y і сусідню клітинку, піхота — у стоячому
## лісі поруч; камера на танку.
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
	# --stdmat: будинки з імпортованим матеріалом GLB, без prop_fade — щоб порівняти фактуру.
	var std_mat: bool = args.has("--stdmat")
	var diag: bool = args.has("--diag")
	for i in range(1, args.size()):
		if args[i] in ["--shadows", "--noshadows", "--stdmat", "--diag"]:
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
		if std_mat:
			for mmi: MultiMeshInstance3D in (screen.get_node("%BoardView") as BoardView).props().find_children("*", "MultiMeshInstance3D", false, false):
				if String(mmi.name).begins_with("house"):
					mmi.material_override = null
		var rig: IsoCameraRig = screen.get_node("%CameraRig")
		var views: Array = []
		if parts.size() >= 3 and parts[1] == "top":
			var a: PackedStringArray = parts[2].split(",")
			var name: String = "%s_top_%s_%s" % [map, a[0], a[1]]
			shots.append([name, await _top_down(screen, Vector2(float(a[0]), float(a[1])), float(a[2]), name)])
			screen.free()
			await get_tree().process_frame
			continue
		if parts.size() >= 4 and parts[1] == "fadeseq":
			# Послідовність розчинення: юніт стає за першою такою будівлею (з боку від камери) —
			# кадри кожні 3 кадри гри (~0.05 с), поки дах стає напівпрозорим; юніт іде — так само назад.
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
				var home: Vector2i = unit.pos
				rig.center_on(target)
				rig.zoom_by(float(parts[3]) / rig.zoom_level)
				for f in SETTLE_FRAMES:
					await get_tree().process_frame
				var seq: int = 0
				for spot: Vector2i in [target - Vector2i.ONE, home]:
					unit.pos = spot
					screen.call("_rebuild_units_for_active_player")
					for k in 6:
						await RenderingServer.frame_post_draw
						shots.append(["%s_fadeseq_%02d" % [map, seq], get_viewport().get_texture().get_image()])
						seq += 1
						for f in 3:
							await get_tree().process_frame
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
		elif parts.size() >= 4 and parts[1] == "forest":
			# Танк гравця 0 заїхав у ліс на x,y: його клітинка й сусідня вздовж ряду проламані
			# (правда; глядач бачить їх, бо стоїть поруч), відділення піхоти — у стоячому лісі
			# за дві клітинки. Камера — на танку: просіка, повалені стовбури й розчинення крон.
			var a: PackedStringArray = parts[2].split(",")
			var c := Vector2i(int(a[0]), int(a[1]))
			var state: BattleState = MatchService.state
			var lane: Array[Vector2i] = [c]
			for d: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
				if board.kind_at(c + d) == Terrain.Kind.FOREST:
					lane.append(c + d)
					break
			var inf := Vector2i(-1, -1)
			for r in range(2, 5):
				for dy in range(-r, r + 1):
					for dx in range(-r, r + 1):
						var q: Vector2i = c + Vector2i(dx, dy)
						if inf.x < 0 and board.in_bounds(q) and board.kind_at(q) == Terrain.Kind.FOREST and not lane.has(q) \
								and state.unit_at(q) == null and absi(dx) + absi(dy) >= 2:
							inf = q
			for w: Array in [[UnitTypes.UnitClass.TANK, c], [UnitTypes.UnitClass.INFANTRY, inf]]:
				for u: Unit in state.units_of(0):
					if u.unit_class() == w[0] and (w[1] as Vector2i).x >= 0:
						var other: Unit = state.unit_at(w[1])
						if other != null and other != u:
							other.pos = u.pos
						u.pos = w[1]
						break
			for q: Vector2i in lane:
				state.broken_forest[q] = true
			state.refresh_vision(0)
			screen.call("_rebuild_units_for_active_player")
			views.append([c, float(parts[3])])
		elif parts.size() >= 4 and parts[1] == "yard":
			# Танк і відділення піхоти гравця 0 у дворі садиби №parts[2] з макету карти: танк — на
			# клітинці двору без хати й сараю, піхота — на іншій, поруч із хатою; камера — на хаті.
			var home: Dictionary = VillageLayout.for_map(StringName(map))["homes"][int(parts[2])]
			var hc: Vector2i = home["house"]
			# Спершу клітинки двору, потім прохідні за ≤ 2 клітинки від нього (у дворі буває лише одна вільна).
			var spots: Array = (home["cells"] as Array).filter(func(c: Vector2i) -> bool:
				return c != hc and c != home.get("shed", Vector2i(-99, -99)))
			var near: Array = []
			for c: Vector2i in home["cells"]:
				for dy in range(-2, 3):
					for dx in range(-2, 3):
						var n: Vector2i = c + Vector2i(dx, dy)
						if not (home["cells"] as Array).has(n) and not near.has(n) and board.in_bounds(n) \
								and board.kind_at(n) in [Terrain.Kind.FIELD, Terrain.Kind.HILL, Terrain.Kind.ROAD]:
							near.append(n)
			# Юніт, для якого хата — серед клітинок, що розчиняються (REVEAL_OFFSETS), сховав би її: такі
			# місця — останніми; далі — ближчі до хати.
			var key := func(c: Vector2i) -> int:
				return (100 if PropLayer.REVEAL_OFFSETS.has(hc - c) else 0) + c.distance_squared_to(hc)
			var by_key := func(a: Vector2i, b: Vector2i) -> bool: return key.call(a) < key.call(b)
			spots.sort_custom(by_key)
			near.sort_custom(by_key)
			spots.append_array(near)
			# Юніт не стоїть на пропсі: його слід (півкорпусу довкола центру клітинки) — щонайменше на
			# 0.15 клітинки від кожного пропса (паркан з кутами кільця, причеп, тюк, колода, будівля).
			var fences: Array[Rect2] = []
			for inst in (screen.get_node("%BoardView") as BoardView).props().all_instances():
				if int(PropLayer.spec_of(inst["model"])["kind"]) != PropLayer.Kind.BRIDGE:
					var fb: AABB = (inst["transform"] as Transform3D) * ((PropLayer.model(inst["model"]) as Dictionary)["aabb"] as AABB)
					fences.append(Rect2(fb.position.x, fb.position.z, fb.size.x, fb.size.z))
			var want: Array = [[UnitTypes.UnitClass.INFANTRY, 0.22], [UnitTypes.UnitClass.TANK, 0.38]]
			var taken: Array[Vector2i] = []
			for w: Array in want:
				var spot := Vector2i(-1, -1)
				for c: Vector2i in spots:
					var foot := Rect2(Vector2(c) - Vector2.ONE * float(w[1]), Vector2.ONE * 2.0 * float(w[1])).grow(0.15)
					if not taken.has(c) and not fences.any(func(r: Rect2) -> bool: return foot.intersects(r)):
						spot = c
						break
				if spot.x < 0:
					continue
				taken.append(spot)
				for u: Unit in MatchService.state.units_of(0):
					if u.unit_class() == w[0]:
						var other: Unit = MatchService.state.unit_at(spot)
						if other != null and other != u:
							other.pos = u.pos
						u.pos = spot
						break
			screen.call("_rebuild_units_for_active_player")
			views.append([home["house"], float(parts[3])])
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
			# Камера, що ще доїжджає (кут дошки, клемп зуму), щокадру перемальовує каскади тіні:
			# лічильник тоді на десятки викликів більший, ніж у кадрі, на який дивиться гравець.
			var cam: Camera3D = get_viewport().get_camera_3d()
			var still: int = 0
			var last: Transform3D = cam.global_transform
			for f in 600:
				await get_tree().process_frame
				still = still + 1 if cam.global_transform.is_equal_approx(last) else 0
				last = cam.global_transform
				if still >= 30:
					break
			await RenderingServer.frame_post_draw
			var m: Vector2i = await _median_frame()
			var dc: int = m.x
			var tris: int = m.y
			var zl: String = str(int(v[1])) if is_equal_approx(v[1], roundf(v[1])) else "%.1f" % v[1]
			var name: String = "%s_%d_%d_z%s" % [map, v[0].x, v[0].y, zl]
			print("BUDGET %s %s z%d dc=%d tris=%d" % [map, v[0], int(v[1]), dc, tris])
			shots.append([name, get_viewport().get_texture().get_image()])
			if diag:
				await _diag(screen, "%s %s z%d" % [map, v[0], int(v[1])], Vector2i(dc, tris))
		screen.free()
		await get_tree().process_frame
	for s: Array in shots:
		(s[1] as Image).save_jpg("%s/%s.jpg" % [out, s[0]], 0.9)
	get_tree().quit()


## Медіана draw calls і трикутників за 9 кадрів: лічильник окремого кадру стрибає (тіні й зонд
## оновлюються не щокадру), і один кадр бреше на десятки викликів.
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


## Скільки коштує кожна група вузлів: сховати, виміряти, повернути.
func _diag(screen: BattleScreen, tag: String, all: Vector2i) -> void:
	var bv: BoardView = screen.get_node("%BoardView")
	var groups: Dictionary = {}
	var forest: Node = bv.forest()
	if forest != null:
		for n: Node in forest.get_children():
			var g: String = "forest_" + String(n.name)
			if not groups.has(g):
				groups[g] = []
			(groups[g] as Array).append(n)
	for n: Node in bv.get_children():
		if n != forest and n is Node3D:
			var g: String = "board_" + String(n.name).rstrip("0123456789@")
			if not groups.has(g):
				groups[g] = []
			(groups[g] as Array).append(n)
	for n: Node in screen.get_children():
		if n != bv and n is Node3D:
			var g: String = "screen_" + String(n.name)
			if not groups.has(g):
				groups[g] = []
			(groups[g] as Array).append(n)
	for g: String in groups:
		var was: Array[bool] = []
		for n: Node3D in groups[g]:
			was.append(n.visible)
			n.visible = false
		var m: Vector2i = await _median_frame()
		var dc: int = m.x
		var tris: int = m.y
		print("DIAG %s %s(%d) dc=%d tris=%d" % [tag, g, (groups[g] as Array).size(), all.x - dc, all.y - tris])
		for i in was.size():
			(groups[g][i] as Node3D).visible = was[i]


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
