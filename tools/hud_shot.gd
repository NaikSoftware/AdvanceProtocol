extends Node
## Знімає HUD справжнього екрана бою в заданих станах: той самий кадр можна отримати з HUD і без
## нього (чистий фон для макетів). Стани проходять крізь справжній шлях вводу —
## InputController.select_unit / tap_cell / arm_engineer / arm_drone / peek_cell, — тож на екрані
## рівно те, що побачить гравець, а не окрема розкладка, яку легко розвести з грою.
## Кадри пишуться наприкінці (save_png блокує ~1 с і зіпсував би таймінг). Не входить у гру.
##
## Запуск (вікно, не --headless; через tools/godot_run.sh):
##   tools/godot_run.sh --path . res://tools/hud_shot.tscn -- <out_dir> <map> <WxH> <locale> <states|all> [hud=on|off|both]
## states — через кому. Файл: <out_dir>/<map>_<WxH>_<state>[_nohud].png

const STATES: Array[String] = [
	"idle", "own_tank", "move_preview", "shot_preview", "enemy", "engineer", "engineer_armed",
	"drone", "drone_preview", "hold_enemy", "handover", "pause",
	"squad", "hold_enemy_squad", "engineer_pending", "mood",
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
			if not await _enter_state(st):
				failed.append(st)
				break
			(_screen.get_node("%Hud") as Control).visible = with_hud
			for f in STATE_FRAMES:
				await get_tree().process_frame
			var img: Image = get_viewport().get_texture().get_image()
			shots.append({"img": img, "path": "%s/%s_%dx%d_%s%s.png" % [out_dir, map_name, size.x, size.y, st, "" if with_hud else "_nohud"]})
	for s: Dictionary in shots:
		(s["img"] as Image).save_png(s["path"])
		print("HUD_SHOT ", s["path"], " ", (s["img"] as Image).get_size())
	if not failed.is_empty():
		print("HUD_SHOT FAILED states: ", failed)
	get_tree().quit(1 if not failed.is_empty() else 0)


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
				_ctrl.arm_engineer(EngineerCommand.Action.LAY_MINE)
		"drone", "drone_preview":
			_ctrl.select_unit(_state.get_unit(_ids["assault"]))
			_ctrl.arm_drone()
			if st == "drone_preview":
				_ctrl.tap_cell(enemy.pos)
		"hold_enemy":
			_ctrl.peek_cell(enemy.pos)
		"squad":
			_ctrl.select_unit(_state.get_unit(_ids["assault"]))
		"hold_enemy_squad":
			_ctrl.peek_cell(_state.get_unit(_ids["enemy_squad"]).pos)
		"engineer_pending":
			_ctrl.select_unit(_state.get_unit(_ids["engineer"]))
			_ctrl.arm_engineer(EngineerCommand.Action.REPAIR_UNIT)
			_ctrl.tap_cell(tank.pos)
		"mood":
			pass
		"handover":
			(_screen.get_node("%HandoverGate") as HandoverGate).show_for(1)
		"pause":
			(_screen.get_node("%PauseMenu") as Control).show()
		_:
			push_error("hud_shot: невідомий стан %s" % st)
			return false
	await _wait_idle()
	var ctrl_state: Dictionary = {"sel": _ctrl._selected_unit != null, "pending": not _ctrl._pending.is_empty(),
		"armed": _ctrl._drone_armed or _ctrl._armed_action >= 0}
	var ok: bool = true
	match st:
		"move_preview", "shot_preview", "drone_preview":
			ok = ctrl_state["pending"]
		"own_tank", "enemy", "engineer", "squad":
			ok = ctrl_state["sel"]
		"engineer_pending":
			ok = ctrl_state["pending"] and ctrl_state["armed"]
		"engineer_armed", "drone":
			ok = ctrl_state["armed"]
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
	(_screen.get_node("%PauseMenu") as Control).visible = false
	(_screen.get_node("%HandoverGate") as Control).visible = false
	_state.units.clear()
	_state.wrecks.clear()
	_state.mines.clear()
	var toward_enemy: int = Board.facing_towards(_site, _site + OFF_ENEMY_TANK)
	_ids["tank"] = _state.add_unit(MEDIUM_TANK, 0, _site + OFF_TANK, toward_enemy).id
	var eng_off: Vector2i = Vector2i(1, 0) if st == "engineer_pending" else OFF_ENGINEER
	_ids["engineer"] = _state.add_unit(ENGINEER, 0, _site + eng_off, toward_enemy).id
	if st == "engineer_pending":
		_state.get_unit(_ids["tank"]).hp -= 80
	_ids["assault"] = _state.add_unit(ASSAULT_SQUAD, 0, _site + OFF_ASSAULT, toward_enemy).id
	_ids["rifle"] = _state.add_unit(RIFLE_SQUAD, 0, _site + OFF_RIFLE, toward_enemy).id
	var back: int = Board.facing_towards(_site + OFF_ENEMY_TANK, _site)
	_ids["enemy_tank"] = _state.add_unit(MEDIUM_TANK, 1, _site + OFF_ENEMY_TANK, back).id
	_ids["enemy_car"] = _state.add_unit(ARMOURED_CAR, 1, _site + OFF_ENEMY_CAR, back).id
	var squad_type: int = ASSAULT_SQUAD if st == "hold_enemy_squad" else RIFLE_SQUAD
	_ids["enemy_squad"] = _state.add_unit(squad_type, 1, _site + OFF_ENEMY_SQUAD, back).id
	if st == "mood":
		_state.units.clear()
	_state.active_player = 0
	_state.refresh_vision_all()
	_screen.call("_rebuild_units_for_active_player", true)
	if st == "mood":
		_rig.center_on(Vector2i(_state.board.width / 2, _state.board.height / 2))
		_rig.zoom_by(16.0 / _rig.zoom_level)
	else:
		_rig.center_on(_site + Vector2i(1, 0))
		_rig.zoom_by(ZOOM / _rig.zoom_level)
	(_screen.get_node("%Hud") as Hud).refresh()


## Тап міг запустити поворот на місці: вводу не буде, доки гра не дограє подію.
func _wait_idle() -> void:
	var ep: EventPlayer = _screen.get("_event_player")
	for f in 240:
		await get_tree().process_frame
		if f > 2 and not ep.is_playing():
			return
