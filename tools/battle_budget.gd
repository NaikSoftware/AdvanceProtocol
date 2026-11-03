extends Node
## Бюджет кадру бою: справжній екран бою на карті, камера на заданих клітинках і зумах; друкує
## draw calls і трикутники кадру (Performance) і знімає кадр. Не входить у гру.
## Запуск (потрібне вікно, не --headless; вікно — за межами екрана):
##   $GODOT --path . --position 6000,0 res://tools/battle_budget.tscn -- <out_dir> [--shadows] <map>[@x,y@zoom] ...
## --diag: розкладає трикутники кадру за шарами дошки (рядки DIAG).
## --shadows: будівлі й руїни кидають справжню тінь сонця — щоб зміряти, скільки це коштує.
## Без @… знімається центр дошки на MAX і MIN зумі. <map>@fadeseq@<модель>@zoom — 12 кадрів розчинення
## даху: юніт стає за будівлею й іде геть. <map>@yard@<садиба>@zoom — танк і піхота гравця 0
## у дворі садиби з макету карти (VillageLayout), камера на хаті. <map>@sel@zoom — вибраний перший юніт гравця 0
## із контурами зон руху поверх пропсів. <map>@behind@<модель>@zoom — той самий юніт за першою
## такою будівлею (з боку від камери), вибраний: розчинення даху й контур зони поверх сліду. <map>@top@x,y,size — ортографічний погляд згори на
## клітинку x,y (size клітинок у кадрі) з межами будівель (червоні) й огорож (блакитні) і найменшим
## проміжком між будівлями та між будівлею й огорожею в метрах. Рядок BUDGET <map> <cell> z<zoom> dc=… tris=…
## shadow_dc=… canvas_dc=…: медіана 9 кадрів, коли камера вже стала (shadow_dc — прохід тіней, canvas_dc — інтерфейс).
## Годинник імли зупинено, тож кадри до й після правки збігаються піксель у піксель (дощ на Річці — ні).
## Паралельні запуски Godot спотворюють лічильник на ±10 викликів: міряти по одному.
## --diag: після кожного кадру ховає по черзі групи вузлів (ліс, діти BoardView, пропси, рослини, юніти,
## інтерфейс, 3D-діти екрана) і друкує, скільки кожна коштує: рядок DIAG <map> <cell> z<zoom> <група>(<вузлів>)
## dc=… tris=… surfs=… inst=… vis=… (vis — скільки екземплярів MultiMesh у кадрі). Базу беруть перед кожною групою.
## --only=<підрядок> лишає в --diag групи з таким підрядком в імені.
## <map>@forest@x,y@zoom — танк гравця 0 проламав ліс на x,y і сусідню клітинку, піхота — у стоячому
## лісі поруч; камера на танку.
## Кадри тримаються в пам'яті й пишуться в кінці: save_png блокує ~1 с і з'їв би наступні кадри.

const WINDOW: Vector2i = Vector2i(1600, 900)
const SETTLE_FRAMES: int = 90
## --only=<підрядок>: --diag міряє лише групи, чиє ім'я його містить (повний прогін не вкладається в хвилини).
var _only: String = ""
## Скільки з draw calls кадру — прохід тіней (медіана останнього _median_frame).
var shadow_dc: int = 0
var canvas_dc: int = 0


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
	# --fencemask: до кожного кадру ще кадр «_nofence» без парканів дворів (маска для виміру їхнього кольору).
	var fence_mask: bool = args.has("--fencemask")
	for a in args:
		if a.begins_with("--only="):
			_only = a.trim_prefix("--only=")
	for i in range(1, args.size()):
		if args[i].begins_with("--only="):
			continue
		if args[i] in ["--shadows", "--noshadows", "--stdmat", "--diag", "--fencemask"]:
			continue
		var parts: PackedStringArray = args[i].split("@")
		var map: String = parts[0]
		var screen: BattleScreen = (load("res://game/battle/battle_screen.tscn") as PackedScene).instantiate()
		add_child(screen)
		screen.setup(load("res://maps/%s.tres" % map) as MapData, 2, 1)
		var board: Board = MatchService.state.board
		# Годинник імли стоїть: кадри до й після правки мусять збігатися піксель у піксель.
		var fog_clock: Timer = (screen.get_node("%BoardView") as BoardView).get("_fog_clock")
		if fog_clock != null:
			fog_clock.stop()
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
		if parts.size() >= 4 and parts[1] == "veg":
			# Рослинність: crush — кущ до й після наїзду; tree — юніт під кроною дерева на луці;
			# reed — юніт на березі під очеретом; wind — 4 кадри дерева з кроком 0,5 с (вітру немає).
			var veg: VegetationLayer = (screen.get_node("%BoardView") as BoardView).vegetation()
			var what: String = parts[2]
			var unit: Unit = MatchService.state.units_of(0)[0]
			var spot := Vector2i(-1, -1)
			var at := Vector2i(-1, -1)
			for pl: Dictionary in veg.placements:
				var c: Vector2i = pl["cell"]
				if what == "crush" and pl["kind"] == "bush" and board.kind_at(c) == Terrain.Kind.FIELD \
						and MatchService.state.unit_at(c) == null:
					at = c
				elif what in ["tree", "wind"] and pl["kind"] == "tree" and pl["group"] == "meadow" \
						and board.kind_at(c) in [Terrain.Kind.FIELD, Terrain.Kind.HILL]:
					at = c
					spot = c
				elif what == "reed" and pl["kind"] == "reed":
					var q := Vector2(pl["pos"].x, pl["pos"].z)
					for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
						var n: Vector2i = c + d
						var r := Rect2(Vector2(n) - Vector2(0.5, 0.5), Vector2.ONE)
						if board.in_bounds(n) and board.kind_at(n) in [Terrain.Kind.FIELD, Terrain.Kind.MARSH, Terrain.Kind.HILL] \
								and VegetationLayer._rect_dist(r, q) < VegetationLayer.crown_of(pl["node"]):
							at = n
							spot = n
				if at.x >= 0:
					break
			if at.x < 0:
				push_error("battle_budget: нема рослини для %s" % what)
			else:
				if what == "tree":
					# Юніт — на сусідній клітинці за деревом (далі від камери): крона між ним і камерою.
					var fwd: Vector3 = -rig.get_viewport().get_camera_3d().global_basis.z
					var step := Vector2i(int(signf(fwd.x)), 0) if absf(fwd.x) > absf(fwd.z) else Vector2i(0, int(signf(fwd.z)))
					if step != Vector2i.ZERO and board.in_bounds(at + step) and board.kind_at(at + step) in [Terrain.Kind.FIELD, Terrain.Kind.HILL]:
						spot = at + step
				if spot.x >= 0:
					var other: Unit = MatchService.state.unit_at(spot)
					if other != null and other != unit:
						other.pos = unit.pos
					unit.pos = spot
					screen.call("_rebuild_units_for_active_player")
				rig.center_on(at)
				rig.zoom_by(float(parts[3]) / rig.zoom_level)
				for f in SETTLE_FRAMES:
					await get_tree().process_frame
				var frames: int = 4 if what == "wind" else 1
				for k in frames:
					if k > 0:
						await get_tree().create_timer(0.5).timeout
					await RenderingServer.frame_post_draw
					shots.append(["%s_veg_%s_%d_%d_%d" % [map, what, at.x, at.y, k], get_viewport().get_texture().get_image()])
				if what == "crush":
					# Напряму в шар дошки: екран бою показує зім'ятість лише на розвіданому гравцем.
					var crushed: Array[Vector2i] = [at]
					(screen.get_node("%BoardView") as BoardView).set_crushed_cells(crushed)
					for f in SETTLE_FRAMES:
						await get_tree().process_frame
					await RenderingServer.frame_post_draw
					shots.append(["%s_veg_crush_%d_%d_after" % [map, at.x, at.y], get_viewport().get_texture().get_image()])
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
		elif parts.size() >= 5 and parts[1] == "place":
			# Модель, якої розстановка карт ще не ставить, — на клітинку x,y із поворотом rot (0..3; 0 — торець +X до камери):
			# вільне місце обирає той, хто знімає. <map>@place@<модель>@x,y@zoom[@rot]
			var pxy: PackedStringArray = parts[3].split(",")
			var pc := Vector2i(int(pxy[0]), int(pxy[1]))
			var pl: PropLayer = (screen.get_node("%BoardView") as BoardView).props()
			for child in pl.get_children():
				child.free()
			pl._nodes.clear()
			pl._fade_nodes.clear()
			pl._fade_level.clear()
			pl._fade_target.clear()
			pl._slots.clear()
			pl._node_model.clear()
			var fp: Vector2i = (PropLayer.model(StringName(parts[2])) as Dictionary)["footprint"]
			var rot: int = int(parts[5]) if parts.size() > 5 else 0
			var size_r: Vector2i = fp if rot % 2 == 0 else Vector2i(fp.y, fp.x)
			var centre := Vector2(pc) + Vector2(size_r - Vector2i.ONE) * 0.5
			var cells: Array[Vector2i] = []
			for dy in size_r.y:
				for dx in size_r.x:
					cells.append(pc + Vector2i(dx, dy))
			pl._add(StringName(parts[2]), Transform3D(Basis(Vector3.UP, rot * PI * 0.5), Vector3(centre.x, 0.0, centre.y)), cells)
			pl._build_nodes(not board.in_bounds(pc))                       # за краєм дошки — будівля кільця (з серпанком, без тіні)
			pl._apply()
			views.append([pc + size_r / 2, float(parts[4])])
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
			# Прогрів ефектів (Units/Explosion, Hit, Muzzle…) малює десятки викликів ще секунду після старту
			# й сам прибирається: міряти треба кадр без нього, інакше лічильник на ~25 завищений.
			var warm: int = 0
			while screen.get_node_or_null("Units/Explosion") != null and warm < 900:
				warm += 1
				await get_tree().process_frame
			if warm >= 900:
				push_warning("прогрів ефектів не скінчився за 900 кадрів, лічильник завищений")
			await RenderingServer.frame_post_draw
			var m: Vector2i = await _median_frame()
			var dc: int = m.x
			var tris: int = m.y
			var zl: String = str(int(v[1])) if is_equal_approx(v[1], roundf(v[1])) else "%.1f" % v[1]
			var name: String = "%s_%d_%d_z%s" % [map, v[0].x, v[0].y, zl]
			print("BUDGET %s %s z%d dc=%d tris=%d shadow_dc=%d canvas_dc=%d" % [map, v[0], int(v[1]), dc, tris, shadow_dc, canvas_dc])
			shots.append([name, get_viewport().get_texture().get_image()])
			if fence_mask:
				# Той самий кадр без парканів дворів: різниця двох кадрів — маска парканів, щоб міряти їхній колір.
				var fence: Node3D = (screen.get_node("%BoardView") as BoardView).props().get_node_or_null("infra_fence_yard")
				if fence != null:
					fence.visible = false
					for f in 3:
						await get_tree().process_frame
					await RenderingServer.frame_post_draw
					shots.append([name + "_nofence", get_viewport().get_texture().get_image()])
					fence.visible = true
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
	var shadow: Array[int] = []
	var canvas: Array[int] = []
	var vp: RID = get_viewport().get_viewport_rid()
	for f in 9:
		await RenderingServer.frame_post_draw
		shadow.append(RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME))
		canvas.append(RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME))
		dcs.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		tris.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
	dcs.sort()
	tris.sort()
	shadow.sort()
	canvas.sort()
	shadow_dc = shadow[4]
	canvas_dc = canvas[4]
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
	# Пропси: по іменах вузлів шару (кожен MultiMesh — окремий виклик, а часом і окремий у тіні).
	var props: Node = bv.get_node_or_null("Props")
	if props != null:
		for n: Node in props.find_children("*", "GeometryInstance3D", true, false):
			var g: String = "prop_" + String(n.name).rstrip("0123456789@")
			if not groups.has(g):
				groups[g] = []
			(groups[g] as Array).append(n)
	var veg: Node = bv.get_node_or_null("Vegetation")
	if veg != null:
		for n: Node in veg.find_children("*", "GeometryInstance3D", true, false):
			var g: String = "veg_" + String(n.name).rstrip("0123456789@")
			if not groups.has(g):
				groups[g] = []
			(groups[g] as Array).append(n)
	var hud: Node = screen.get_node_or_null("UI")
	if hud != null:
		for n: Node in hud.find_children("*", "CanvasItem", true, false):
			if (n as CanvasItem).visible and (n as CanvasItem).is_visible_in_tree() and (n is Label or n is Button or n is ColorRect or n is Panel or n is PanelContainer or n is TextureRect):
				var g: String = "ui_" + String(n.name)
				if not groups.has(g):
					groups[g] = []
				(groups[g] as Array).append(n)
	# Юніти: по іменах візуальних вузлів усередині, а не одним блоком.
	var units: Node = screen.get_node_or_null("Units")
	if units != null:
		for n: Node in units.find_children("*", "GeometryInstance3D", true, false):
			var g: String = "unit_" + String(n.name).rstrip("0123456789@")
			if not groups.has(g):
				groups[g] = []
			(groups[g] as Array).append(n)
	for n: Node in screen.get_children():
		if n != bv and n is Node3D:
			var g: String = "screen_" + String(n.name)
			if not groups.has(g):
				groups[g] = []
			(groups[g] as Array).append(n)
	groups["ALL_forest"] = [forest] if forest != null else []
	var ui: Array = []
	for n: Node in screen.get_children():
		if n is CanvasItem or n is CanvasLayer:
			ui.append(n)
	groups["ALL_ui"] = ui
	var wr: Node = screen.get_node_or_null("WeatherRig")
	if wr != null:
		groups["ALL_sun"] = [wr.get_node("Sun")]
		groups["ALL_rain"] = [wr.get_node("Rain")]
	groups["ALL_both"] = ui.duplicate()
	groups["ALL_3D_but_cam"] = []
	for n: Node in screen.get_children():
		if n is Node3D and not n is Camera3D and n.name != "CameraRig":
			(groups["ALL_3D_but_cam"] as Array).append(n)
			(groups["ALL_both"] as Array).append(n)
	for g: String in groups:
		if not _only.is_empty() and not g.contains(_only):
			continue
		# Базу міряємо перед кожною групою: після ховання/повернення вузла лічильник сам дрейфує
		# (кеш тіней, видимість шарів), і одна база на кадр дає накопичену похибку.
		var base: Vector2i = await _median_frame()
		var was: Array[bool] = []
		groups[g] = (groups[g] as Array).filter(func(n: Variant) -> bool: return is_instance_valid(n))
		for n in groups[g]:
			was.append(n.visible)
			n.visible = false
		var m: Vector2i = await _median_frame()
		var dc: int = m.x
		var tris: int = m.y
		var surfs: int = 0
		var insts: int = 0
		for n in groups[g]:
			if n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh.mesh != null:
				surfs += (n as MultiMeshInstance3D).multimesh.mesh.get_surface_count()
				insts += (n as MultiMeshInstance3D).multimesh.instance_count
			elif n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
				surfs += (n as MeshInstance3D).mesh.get_surface_count()
		# Скільки екземплярів MultiMesh потрапляє в кадр (з запасом 80 px): вузол без жодного
		# малюється даремно — його AABB охоплює всю карту.
		var vis: int = 0
		var cam: Camera3D = get_viewport().get_camera_3d()
		var rect: Rect2 = get_viewport().get_visible_rect().grow(80.0)
		for n in groups[g]:
			if n is MultiMeshInstance3D:
				var mm: MultiMesh = (n as MultiMeshInstance3D).multimesh
				for i in mm.instance_count:
					var wp: Vector3 = (n as Node3D).global_transform * mm.get_instance_transform(i).origin
					if not cam.is_position_behind(wp) and rect.has_point(cam.unproject_position(wp)):
						vis += 1
		print("DIAG %s %s(%d) dc=%d tris=%d surfs=%d inst=%d vis=%d" % [tag, g, (groups[g] as Array).size(), base.x - dc, base.y - tris, surfs, insts, vis])
		for i in was.size():
			groups[g][i].visible = was[i]


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
