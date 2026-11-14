extends Node
## Знімає HUD справжнього екрана бою в заданих станах: той самий кадр можна отримати з HUD і без
## нього (чистий фон для макетів). Стани проходять крізь справжній шлях вводу —
## InputController.select_unit / tap_cell / arm_engineer / arm_drone / peek_cell, — тож на екрані
## рівно те, що побачить гравець, а не окрема розкладка, яку легко розвести з грою.
## Кадри пишуться наприкінці (save_png блокує ~1 с і зіпсував би таймінг). Не входить у гру.
##
## Запуск (вікно, не --headless; через tools/godot_run.sh):
##   tools/godot_run.sh --path . res://tools/hud_shot.tscn -- <out_dir> <map> <WxH> <locale> <states|all> [hud=on|off|both] [--ui-dpi=N]
## states — через кому. Файл: <out_dir>/<map>_<WxH>_<state>[_nohud][_<locale>].png.
## --ui-dpi емулює телефон: 1496x672 при 243 дає логічні 985x442, 1600x720 при 320 — 800x360.

const STATES: Array[String] = [
	"idle", "own_tank", "move_preview", "shot_preview", "enemy", "engineer", "engineer_armed",
	"drone", "drone_preview", "hold_enemy", "handover", "pause",
	"squad", "hold_enemy_squad", "engineer_pending", "mood",
	"toast_drone", "toast_engineer", "own_tank_to_shot", "squad_shot", "shot_infantry",
	"hold_enemy_squad_spent", "handover_p1", "handover_p3",
	"squad_to_drone", "hold_cluster", "engineer_to_armed", "shot_cover", "shot_infantry_armour_ignored",
	"engineer_clear", "engineer_repair_bridge", "engineer_demolish_bridge", "hold_engineer",
	"handover_2p_hurt", "handover_3p", "handover_3p_eliminated",
	"handover_default",
]
const SETTLE_FRAMES: int = 90
const STATE_FRAMES: int = 20
const ZOOM: float = 9.0
const MEDIUM_TANK: int = 5
const ASSAULT_SQUAD: int = 1
const RIFLE_SQUAD: int = 0
const ARMOURED_CAR: int = 2
const ENGINEER: int = 11

## Розкладка відносно центру майданчика. Ворожий танк стоїть у трьох клітинках — у межах пострілу
## (дальність 4) і в огляді; штурмовий загін далі за ним у межах дрона (5).
const OFF_TANK := Vector2i(0, 0)
const OFF_ENGINEER := Vector2i(-1, 2)
const OFF_ASSAULT := Vector2i(-1, -1)
const OFF_RIFLE := Vector2i(-1, -2)
const OFF_ENEMY_TANK := Vector2i(3, 0)
const OFF_ENEMY_CAR := Vector2i(3, 2)
const OFF_ENEMY_SQUAD := Vector2i(2, -2)
## Клітинка, куди тапається рух: у зоні танка, не на лінії вогню.
const OFF_MOVE := Vector2i(-1, 1)

var _screen: BattleScreen = null
var _state: BattleState = null
var _ctrl: InputController = null
var _rig: IsoCameraRig = null
var _site: Vector2i = Vector2i.ZERO
var _ids: Dictionary = {}
## Проміжні кадри станів-переходів («до» дії): [{img, name}]. Цикл знімання дописує їх до основних.
var _mid: Array[Dictionary] = []
## Клітинки, куди розкладка ставить юнітів станів з особливим місцем (укриття, мости).
var _spot: Dictionary = {}
## Клітинка, чий вид змінено для кадра моста, і її справжній вид: наступний стан повертає його.
var _broken: Vector2i = Vector2i(-1, -1)
var _broken_kind: int = Terrain.Kind.FIELD


func _ready() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	if a.size() < 5:
		push_error("hud_shot: <out_dir> <map> <WxH> <locale> <states|all> [hud=on|off|both]")
		get_tree().quit(1)
		return
	var out_dir: String = a[0]
	var map_name: String = a[1]
	var wh: PackedStringArray = a[2].split("x")
	var size := Vector2i(int(wh[0]), int(wh[1]))
	TranslationServer.set_locale(a[3])
	var states: Array[String] = []
	if a[4] == "all":
		states.assign(STATES)
	else:
		states.assign(a[4].split(","))
	var hud_mode: String = a[5].trim_prefix("hud=") if a.size() > 5 else "on"
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_window().size = size
	_screen = (load("res://game/battle/battle_screen.tscn") as PackedScene).instantiate()
	add_child(_screen)
	var map := load("res://maps/%s.tres" % map_name) as MapData
	if not _screen.setup(map, 2, 1):
		push_error("hud_shot: карта %s відхилена" % map_name)
		get_tree().quit(1)
		return
	_state = _screen.get("_match_service").state
	_ctrl = _screen.input_controller()
	_rig = _screen.get_node("%CameraRig")
	_site = _find_site(_state.board)
	if _site == Vector2i(-1, -1):
		push_error("hud_shot: на карті немає відкритого майданчика")
		get_tree().quit(1)
		return
	(_screen.get_node("%HandoverGate") as Control).visible = false

	print("HUD_SHOT ready site=", _site)
	# Перший кадр після setup() компілює шейдери ефектів: без розігріву він виходить напівпорожнім.
	for f in SETTLE_FRAMES:
		await get_tree().process_frame
	var shots: Array[Dictionary] = []
	var failed: Array[String] = []
	for st: String in states:
		for with_hud: bool in [true, false]:
			if (with_hud and hud_mode == "off") or (not with_hud and hud_mode == "on"):
				continue
			(_screen.get_node("%Hud") as Control).visible = with_hud
			_mid.clear()
			if not await _enter_state(st):
				failed.append(st)
				break
			for m: Dictionary in _mid:
				shots.append({"img": m["img"], "path": _shot_path(out_dir, map_name, size, m["name"], with_hud, a[3])})
			for f in STATE_FRAMES:
				await get_tree().process_frame
			var img: Image = get_viewport().get_texture().get_image()
			shots.append({"img": img, "path": _shot_path(out_dir, map_name, size, st, with_hud, a[3])})
	for s: Dictionary in shots:
		(s["img"] as Image).save_png(s["path"])
		print("HUD_SHOT ", s["path"], " ", (s["img"] as Image).get_size())
	if not failed.is_empty():
		print("HUD_SHOT FAILED states: ", failed)
	get_tree().quit(1 if not failed.is_empty() else 0)


## Лише для знімка гейта: команда з часткою share від max HP (0 — усі загинули).
func _set_team_share(player: int, share: float) -> void:
	for u: Unit in _state.units.values():
		if u.owner == player:
			u.hp = int(round(u.max_hp() * share))


func _add_third_player() -> void:
	_state.player_count = 3
	_state.eliminated.resize(3)
	_state.eliminated.fill(false)
	_state.add_unit(MEDIUM_TANK, 2, _site + Vector2i(5, 5), 0)
	_state.add_unit(RIFLE_SQUAD, 2, _site + Vector2i(6, 5), 0)


func _shot_path(out_dir: String, map_name: String, size: Vector2i, st: String, with_hud: bool, locale: String) -> String:
	return "%s/%s_%dx%d_%s%s%s.png" % [out_dir, map_name, size.x, size.y, st, "" if with_hud else "_nohud", "" if locale == "uk" else "_" + locale]


## Кадр посеред стану: перехід знімається до дії, а тоді після неї.
func _capture_mid(st_name: String) -> void:
	for f in STATE_FRAMES:
		await get_tree().process_frame
	_mid.append({"img": get_viewport().get_texture().get_image(), "name": st_name})


## Майданчик, де кожна клітинка розкладки й широкого поля навколо — дорога чи поле: інакше танк
## стояв би в лісі чи під будинком, а зони й постріл показували б не те, що задумано. Бере той, де
## найменше сторонніх клітинок, а з рівних — найближчий до центру дошки.
func _find_site(board: Board) -> Vector2i:
	var offs: Array[Vector2i] = [OFF_TANK, OFF_ENGINEER, OFF_ASSAULT, OFF_RIFLE, OFF_ENEMY_TANK,
		OFF_ENEMY_CAR, OFF_ENEMY_SQUAD, OFF_MOVE, Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1), Vector2i(-2, 0)]
	var centre := Vector2i(board.width / 2, board.height / 2)
	var best := Vector2i(-1, -1)
	var best_cost: int = 1 << 30
	for y in board.height:
		for x in board.width:
			var c := Vector2i(x, y)
			var ok: bool = true
			for o: Vector2i in offs:
				var p: Vector2i = c + o
				if not board.in_bounds(p) or not board.kind_at(p) in [Terrain.Kind.ROAD, Terrain.Kind.FIELD]:
					ok = false
					break
			if not ok:
				continue
			var bad: int = 0
			for dy in range(-3, 5):
				for dx in range(-4, 6):
					var q: Vector2i = c + Vector2i(dx, dy)
					if not board.in_bounds(q) or not board.kind_at(q) in [Terrain.Kind.ROAD, Terrain.Kind.FIELD]:
						bad += 1
			var cost: int = bad * 1000 + (c - centre).length_squared()
			if cost < best_cost:
				best_cost = cost
				best = c
	return best


## Ставить свіжий склад і доводить екран до стану; false — стан недосяжний (причина в журналі).
func _enter_state(st: String) -> bool:
	print("HUD_SHOT state ", st)
	_reset_cast(st)
	for f in 5:
		await get_tree().process_frame
	var tank: Unit = _state.get_unit(_ids["tank"])
	var enemy: Unit = _state.get_unit(_ids["enemy_tank"])
	match st:
		"idle":
			pass
		"own_tank":
			_ctrl.select_unit(tank)
		"move_preview":
			_ctrl.select_unit(tank)
			_ctrl.tap_cell(_site + OFF_MOVE)
		"shot_preview":
			_ctrl.select_unit(tank)
			_ctrl.tap_cell(enemy.pos)
		"enemy":
			_ctrl.select_unit(enemy)
		"engineer", "engineer_armed":
			_ctrl.select_unit(_state.get_unit(_ids["engineer"]))
			if st == "engineer_armed":
				_press_verb(EngineerCommand.Action.LAY_MINE)
		"drone", "drone_preview":
			_ctrl.select_unit(_state.get_unit(_ids["assault"]))
			_ctrl.arm_drone()
			if st == "drone_preview":
				_ctrl.tap_cell(enemy.pos)
		"hold_enemy":
			_press(enemy.pos)
			_ctrl.peek_cell(enemy.pos)
		"squad":
			_ctrl.select_unit(_state.get_unit(_ids["assault"]))
		"hold_enemy_squad":
			_press(_state.get_unit(_ids["enemy_squad"]).pos)
			_ctrl.peek_cell(_state.get_unit(_ids["enemy_squad"]).pos)
		"engineer_pending":
			_ctrl.select_unit(_state.get_unit(_ids["engineer"]))
			_press_verb(EngineerCommand.Action.REPAIR_UNIT)
			_ctrl.tap_cell(tank.pos)
		"mood":
			pass
		"toast_drone":
			# Дрон не б'є піхоту: тап по ворожому піхотному загону в режимі дрона — відмова правил.
			_ctrl.select_unit(_state.get_unit(_ids["assault"]))
			_ctrl.arm_drone()
			_ctrl.tap_cell(_state.get_unit(_ids["enemy_squad"]).pos)
		"toast_engineer":
			# Кнопка верби й тап по далекій клітинці: ERR_NOT_ADJACENT.
			_ctrl.select_unit(_state.get_unit(_ids["engineer"]))
			_press_verb(EngineerCommand.Action.LAY_MINE)
			_ctrl.tap_cell(enemy.pos)
		"own_tank_to_shot":
			# Одна сесія: вибір → тап по ворогові. Тег не мусить стрибнути, поки його місце законне.
			_ctrl.select_unit(tank)
			await _wait_idle()
			await _capture_mid("own_tank_pre_shot")
			var before: Rect2 = _tag_rect()
			_ctrl.tap_cell(enemy.pos)
			await _wait_idle()
			print("HUD_SHOT tag_rect own_tank=", before, " shot_preview=", _tag_rect())
		"engineer_to_armed":
			# Вибір → озброєння верби з кнопки панелі: тег мусить лишитися на місці.
			_ctrl.select_unit(_state.get_unit(_ids["engineer"]))
			await _wait_idle()
			await _capture_mid("engineer_pre_armed")
			var eng_before: Rect2 = _tag_rect()
			_press_verb(EngineerCommand.Action.LAY_MINE)
			await _wait_idle()
			print("HUD_SHOT tag_rect engineer=", eng_before, " armed=", _tag_rect())
		"squad_to_drone":
			# Той самий юніт без кільця й із ним: тег не мусить стрибнути, поки його місце законне.
			_ctrl.select_unit(_state.get_unit(_ids["assault"]))
			await _wait_idle()
			var squad_before: Rect2 = _tag_rect()
			_ctrl.arm_drone()
			await _wait_idle()
			print("HUD_SHOT tag_rect squad=", squad_before, " drone=", _tag_rect())
		"hold_cluster":
			# Утримання власного юніта, поки видно плиту прев'ю: після відпускання плита мусить повернутись.
			_ctrl.select_unit(tank)
			_ctrl.tap_cell(_site + OFF_MOVE)
			await _wait_idle()
			_press(tank.pos)
			_ctrl.peek_cell(tank.pos)
		"shot_cover":
			# Танк проти піхоти в будівлі: на плиті «УКРИТТЯ ½».
			_ctrl.select_unit(tank)
			_ctrl.tap_cell(_state.get_unit(_ids["enemy_squad"]).pos)
		"engineer_clear":
			_ctrl.select_unit(_state.get_unit(_ids["engineer"]))
			_press_verb(EngineerCommand.Action.CLEAR_MINE)
			_ctrl.tap_cell(_spot["target"])
		"engineer_repair_bridge", "engineer_demolish_bridge":
			_ctrl.select_unit(_state.get_unit(_ids["engineer"]))
			_press_verb(EngineerCommand.Action.REPAIR_BRIDGE if st == "engineer_repair_bridge" else EngineerCommand.Action.DEMOLISH_BRIDGE)
			_ctrl.tap_cell(_spot["target"])
		"hold_engineer":
			_press(_state.get_unit(_ids["engineer"]).pos)
			_ctrl.peek_cell(_state.get_unit(_ids["engineer"]).pos)
		"shot_infantry_armour_ignored", "squad_shot":
			# Стрілецький загін поруч із ворожим танком: піхота по техніці, «броня не діє».
			_state.get_unit(_ids["rifle"]).pos = enemy.pos + Vector2i(-1, 0)
			_state.refresh_vision_all()
			_screen.call("_rebuild_units_for_active_player", true)
			(_screen.get_node("%Hud") as Hud).refresh()
			_ctrl.select_unit(_state.get_unit(_ids["rifle"]))
			_ctrl.tap_cell(enemy.pos)
		"shot_infantry":
			_ctrl.select_unit(tank)
			_ctrl.tap_cell(_state.get_unit(_ids["enemy_squad"]).pos)
		"hold_enemy_squad_spent":
			_state.get_unit(_ids["enemy_squad"]).drones_left = 0
			(_screen.get_node("%Hud") as Hud).refresh()
			_press(_state.get_unit(_ids["enemy_squad"]).pos)
			_ctrl.peek_cell(_state.get_unit(_ids["enemy_squad"]).pos)
		"handover":
			(_screen.get_node("%HandoverGate") as HandoverGate).show_for(1, _state.turn_number, _state)
		"handover_p1":
			(_screen.get_node("%HandoverGate") as HandoverGate).show_for(0, _state.turn_number, _state)
		"handover_p3":
			(_screen.get_node("%HandoverGate") as HandoverGate).show_for(2, _state.turn_number, _state)
		"handover_2p_hurt":
			_set_team_share(0, 0.7)
			_set_team_share(1, 0.45)
			(_screen.get_node("%HandoverGate") as HandoverGate).show_for(1, _state.turn_number, _state)
		"handover_3p", "handover_3p_eliminated":
			_add_third_player()
			_set_team_share(0, 0.8)
			_set_team_share(1, 0.4)
			if st == "handover_3p_eliminated":
				_set_team_share(1, 0.0)
				_state.eliminated[1] = true
			(_screen.get_node("%HandoverGate") as HandoverGate).show_for(2, _state.turn_number, _state)
		"handover_default":
			# Карта без власної плити: запасна default.webp. Контекст лишається — знімати останнім.
			var gate := _screen.get_node("%HandoverGate") as HandoverGate
			gate.set_context("res://maps/_none.tres", gate.get("_map_name_key"))
			gate.show_for(1, _state.turn_number)
		"pause":
			(_screen.get_node("%PauseMenu") as PauseMenu).open(_state.turn_number)
		_:
			push_error("hud_shot: невідомий стан %s" % st)
			return false
	await _wait_idle()
	var ctrl_state: Dictionary = {"sel": _ctrl._selected_unit != null, "pending": not _ctrl._pending.is_empty(),
		"armed": _ctrl._drone_armed or _ctrl._armed_action >= 0}
	var ok: bool = true
	match st:
		"move_preview", "shot_preview", "drone_preview", "own_tank_to_shot", "squad_shot", "shot_infantry":
			ok = ctrl_state["pending"]
		"shot_cover":
			ok = ctrl_state["pending"] and bool(_preview().get("in_cover", false))
		"shot_infantry_armour_ignored":
			ok = ctrl_state["pending"] and bool(_preview().get("armour_ignored", false))
		"engineer_clear", "engineer_repair_bridge", "engineer_demolish_bridge":
			ok = ctrl_state["pending"] and int(_preview().get("type", -1)) == InputController.ActionType.ENGINEER
		"hold_engineer", "hold_enemy_squad", "hold_enemy_squad_spent":
			ok = ((_screen.get_node("%Hud") as Hud).hold_card() as Control).visible
		"own_tank", "enemy", "engineer", "squad":
			ok = ctrl_state["sel"]
		"engineer_pending":
			ok = ctrl_state["pending"] and ctrl_state["armed"]
		"engineer_armed", "drone", "engineer_to_armed":
			ok = ctrl_state["armed"]
		"hold_cluster":
			ok = ((_screen.get_node("%Hud") as Hud).hold_card() as Control).visible
		"toast_drone", "toast_engineer":
			ok = ((_screen.get_node("%Hud") as Hud).get("_toast") as Control).visible
	if not ok:
		push_error("hud_shot: стан %s не досягнуто (%s)" % [st, ctrl_state])
	return ok


## Склад розкладається заново на кожен стан: попередній міг витратити AP чи повернути танк.
## Відступи від типового складу — лише для станів, що без них недосяжні, аби решта кадрів не
## зсувалася: ворожий штурмовий загін із дронами (hold_enemy_squad), пошкоджений танк поруч з
## інженером (engineer_pending), порожня дошка для тла екрана передачі ходу (mood).
func _reset_cast(st: String) -> void:
	_ctrl.select_unit(null)
	_ctrl.end_peek()
	(_screen.get_node("%Hud") as Hud).call("_hide_toast")
	(_screen.get_node("%PauseMenu") as Control).visible = false
	(_screen.get_node("%HandoverGate") as Control).visible = false
	# Стани гейта на трьох гравців змінюють кількість гравців: повертаємо двох.
	_state.player_count = 2
	_state.eliminated.resize(2)
	_state.eliminated.fill(false)
	_state.units.clear()
	_state.wrecks.clear()
	_state.mines.clear()
	# Розвідка попереднього стану не мусить просочитися в наступний: ворожа машина, що колись була в огляді, лишалась би видимою.
	for v: Vision in _state.vision:
		v.seen.fill(0)
		v.visible.fill(0)
	_spot.clear()
	if _broken != Vector2i(-1, -1):
		_state.board.set_kind(_broken, _broken_kind)
		_broken = Vector2i(-1, -1)
	var toward_enemy: int = Board.facing_towards(_site, _site + OFF_ENEMY_TANK)
	_ids["tank"] = _state.add_unit(MEDIUM_TANK, 0, _site + OFF_TANK, toward_enemy).id
	var eng_off: Vector2i = Vector2i(0, 1) if st == "engineer_pending" else OFF_ENGINEER
	_ids["engineer"] = _state.add_unit(ENGINEER, 0, _site + eng_off, toward_enemy).id
	if st == "engineer_pending":
		_state.get_unit(_ids["tank"]).hp -= 80
	_ids["assault"] = _state.add_unit(ASSAULT_SQUAD, 0, _site + OFF_ASSAULT, toward_enemy).id
	_ids["rifle"] = _state.add_unit(RIFLE_SQUAD, 0, _site + OFF_RIFLE, toward_enemy).id
	var back: int = Board.facing_towards(_site + OFF_ENEMY_TANK, _site)
	_ids["enemy_tank"] = _state.add_unit(MEDIUM_TANK, 1, _site + OFF_ENEMY_TANK, back).id
	_ids["enemy_car"] = _state.add_unit(ARMOURED_CAR, 1, _site + OFF_ENEMY_CAR, back).id
	var squad_type: int = ASSAULT_SQUAD if st in ["hold_enemy_squad", "hold_enemy_squad_spent"] else RIFLE_SQUAD
	_ids["enemy_squad"] = _state.add_unit(squad_type, 1, _site + OFF_ENEMY_SQUAD, back).id
	if st == "mood":
		_state.units.clear()
	var focus: Vector2i = _site + Vector2i(1, 0)
	match st:
		"shot_cover":
			focus = _place_cover_case()
		"engineer_clear":
			var mine_cell: Vector2i = _state.get_unit(_ids["engineer"]).pos + Vector2i(1, 0)
			Mines.place(_state, mine_cell, 0)
			_spot["target"] = mine_cell
		"engineer_repair_bridge", "engineer_demolish_bridge":
			focus = _place_bridge_case(st == "engineer_repair_bridge")
	_state.active_player = 0
	_state.refresh_vision_all()
	_screen.call("_rebuild_units_for_active_player", true)
	if st == "mood":
		_rig.center_on(Vector2i(_state.board.width / 2, _state.board.height / 2))
		_rig.zoom_by(16.0 / _rig.zoom_level)
	else:
		_rig.center_on(focus)
		_rig.zoom_by(ZOOM / _rig.zoom_level)
	(_screen.get_node("%Hud") as Hud).refresh()


## Піхота ворога в будівлі, наш танк за 2–3 клітинки від неї на дорозі чи полі, найближче до майданчика.
## Загін у будівлі видно, лише коли знайдено: позначаємо знайденим для гравця 0, як після сусідства.
func _place_cover_case() -> Vector2i:
	var board: Board = _state.board
	var best: Array[Vector2i] = []
	var best_cost: int = 1 << 30
	for y in board.height:
		for x in board.width:
			var b := Vector2i(x, y)
			if board.kind_at(b) != Terrain.Kind.BUILDING or _state.unit_at(b) != null:
				continue
			for dy in range(-3, 4):
				for dx in range(-3, 4):
					var t: Vector2i = b + Vector2i(dx, dy)
					var d2: int = dx * dx + dy * dy
					if d2 < 4 or d2 > 9 or not board.in_bounds(t) or _state.unit_at(t) != null \
							or not board.kind_at(t) in [Terrain.Kind.ROAD, Terrain.Kind.FIELD]:
						continue
					var cost: int = (t - _site).length_squared()
					if cost < best_cost:
						best_cost = cost
						best = [t, b]
	if best.is_empty():
		push_error("hud_shot: на карті немає будівлі поруч із відкритим місцем для танка")
		return _site
	var tank: Unit = _state.get_unit(_ids["tank"])
	tank.pos = best[0]
	tank.facing = Board.facing_towards(best[0], best[1])
	var squad: Unit = _state.get_unit(_ids["enemy_squad"])
	squad.pos = best[1]
	squad.found_by |= 1
	return (best[0] + best[1]) / 2


## Інженер стоїть поруч із мостом: для «ремонту» міст у стані зламано (картинка дошки лишається цілою,
## кадр потрібен заради плити дії), для «підриву» — цілий.
func _place_bridge_case(broken: bool) -> Vector2i:
	var board: Board = _state.board
	var best_cost: int = 1 << 30
	var found: Array[Vector2i] = []
	for y in board.height:
		for x in board.width:
			var br := Vector2i(x, y)
			if board.kind_at(br) != Terrain.Kind.BRIDGE:
				continue
			for d: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
				var e: Vector2i = br + d
				if board.in_bounds(e) and _state.unit_at(e) == null and board.kind_at(e) in [Terrain.Kind.ROAD, Terrain.Kind.FIELD]:
					var cost: int = (e - _site).length_squared()
					if cost < best_cost:
						best_cost = cost
						found = [e, br]
	var eng: Unit = _state.get_unit(_ids["engineer"])
	if found.is_empty():
		# Карта без мосту (Перехрестя): клітинка поруч з інженером стає мостом лише в стані — плиті дії цього досить.
		found = [eng.pos, eng.pos + Vector2i(1, 0)]
		_broken = found[1]
		_broken_kind = board.kind_at(found[1])
		board.set_kind(found[1], Terrain.Kind.BRIDGE)
	eng.pos = found[0]
	eng.facing = Board.facing_towards(found[0], found[1])
	_spot["target"] = found[1]
	if broken:
		if _broken == Vector2i(-1, -1):
			_broken = found[1]
			_broken_kind = Terrain.Kind.BRIDGE
		board.set_kind(found[1], Terrain.Kind.BRIDGE_DESTROYED)
	return found[0]


func _preview() -> Dictionary:
	return (_screen.get_node("%Hud") as Hud).get("_last_preview")


func _tag_rect() -> Rect2:
	var tag: Control = (_screen.get_node("%Hud") as Hud).get("_tag")
	return tag.get_rect() if tag.visible else Rect2()


## Палець лежить на клітинці юніта, як у грі: картка утримання обходить точку натиску.
func _press(cell: Vector2i) -> void:
	(_screen.get_node("%Hud") as Hud).note_press(_rig.unproject(IsoCameraRig.cell_to_world(cell)))


## Тап міг запустити поворот на місці: вводу не буде, доки гра не дограє подію.
func _wait_idle() -> void:
	var ep: EventPlayer = _screen.get("_event_player")
	for f in 240:
		await get_tree().process_frame
		if f > 2 and not ep.is_playing():
			return


## Верба береться з кнопки панелі, як у грі: лише так панель запам'ятовує вибрану дію, і смужка
## озброєння отримує назву та значок (прямий arm_engineer лишив би їх порожніми).
func _press_verb(action: int) -> void:
	var panel := (_screen.get_node("%Hud") as Hud).get_node("%EngineerPanel") as EngineerPanel
	panel.button_for(action).pressed.emit()
	# Знімок тапає по клітинці в той самий кадр: захист від подвійного тапу по плиті верб тут зайвий
	# (плита ставить його сама, тож скидати треба після натискання).
	_ctrl.tap_guard_ms = 0
