extends GutTest
## Наскрізна регресія бою: справжня battle_screen.tscn, ізольований MatchService,
## ввід — реальні події миші, надіслані у viewport (екранна точка = unproject
## центру клітинки), кнопки HUD і гейта. Усі очікувані числа — golden: порахо-
## вані окремо від гри з формули §3.3 і сіда RNG та зафіксовані тут. Якщо вони
## поїхали — змінилися правила бою, і це має бути свідоме рішення, а не побічка.
##
## Відкривальний гейт тут не перевіряється: setup() його не показує, він покритий у
## tests/game/test_match_flow.gd::test_new_match_starts_behind_the_gate.
## Дронів і мін тут навмисно немає: UI для них ще не існує.

const BattleScreenScene := preload("res://game/battle/battle_screen.tscn")
const MatchServiceScript := preload("res://game/autoload/match_service.gd")
const E2E := preload("res://tests/e2e/e2e_helpers.gd")
var _test_save: String = "user://test_e2e_save_%d.json" % OS.get_process_id()

# Типи з core/unit_types.gd
const RIFLE: int = 0
const ARMOURED_CAR: int = 2
const MEDIUM_TANK: int = 5
const HEAVY_TANK: int = 8
const FIELD_GUN: int = 9
const ENGINEER: int = 11

const N: int = 0
const E: int = 2
const S: int = 4
const W: int = 6

## Усі golden-шкоди порахованi з RandomNumberGenerator із цим сідом; розклад кидків — у коментарях тестів.
const SEED: int = 7


## Пише всі події, які сцена забрала з черги, — щоб перевіряти ПОРЯДОК подій
## (хто повернувся до пострілу, хто після шкоди), а не лише кінцевий стан.
class RecService extends MatchServiceScript:
	var events: Array[Events.BattleEvent] = []
	func take_events() -> Array[Events.BattleEvent]:
		var e: Array[Events.BattleEvent] = super.take_events()
		events.append_array(e)
		return e


var _e2e: E2E
var _service: RecService
var _screen: BattleScreen


func before_each() -> void:
	_e2e = E2E.new(self)


func after_each() -> void:
	_e2e.restore_runner_gui()
	DirAccess.remove_absolute(_test_save)
	DirAccess.remove_absolute(_test_save + ".map")


# --- Каркас ------------------------------------------------------------------

func _spawn(type_id: int, owner: int, pos: Vector2i, facing: int = N) -> Dictionary:
	return {"type_id": type_id, "owner": owner, "pos": pos, "facing": facing}


## tiles: {Vector2i: Terrain.Kind}; решта — FIELD.
func _boot(width: int, height: int, spawns: Array, tiles: Dictionary = {},
		ground: int = Terrain.GroundState.DRY, seed_value: int = SEED) -> void:
	var m := MapData.new()
	m.width = width
	m.height = height
	var t := PackedInt32Array()
	t.resize(width * height)
	t.fill(Terrain.Kind.FIELD)
	for p: Vector2i in tiles:
		t[p.y * width + p.x] = tiles[p]
	m.tiles = t
	var typed: Array[Dictionary] = []
	for s: Dictionary in spawns:
		typed.append(s)
	m.spawns = typed
	# таблиця рухів піднімає матч у циклі — не тримаємо десяток екранів одразу
	if is_instance_valid(_screen):
		_screen.free()
	if is_instance_valid(_service):
		_service.free()
	_service = RecService.new()
	add_child_autofree(_service)
	_screen = BattleScreenScene.instantiate()
	add_child_autofree(_screen)
	_screen.save_path = _test_save
	_screen.setup(m, 2, seed_value, _service, ground)
	_e2e.ignore_runner_gui([_screen])
	await _settle()


## Твіни камери й подій гасимо вручну, доки програвач не скаже, що закінчив.
func _settle() -> void:
	await _e2e.wait_until(func() -> bool: return not _screen._event_player.is_playing(), "програвання подій")


func _hud() -> Hud:
	return _screen.get_node("%Hud")


func _gate() -> Node:
	return _screen.get_node("%HandoverGate")


func _press(button: Button) -> void:
	assert_false(button.disabled, "кнопка мусить бути натискною: %s" % button.name)
	button.pressed.emit()


func _px(cell: Vector2i) -> Vector2:
	var rig: IsoCameraRig = _screen.get_node("%CameraRig")
	return rig.unproject(IsoCameraRig.cell_to_world(cell))


## Справжній тап: миша вниз/вгору в центрі клітинки через viewport.
func _tap(cell: Vector2i) -> void:
	_e2e.click_at(_px(cell))


func _confirm() -> void:
	_press(_hud().get_node("%ConfirmButton"))
	await _settle()


func _end_turn() -> void:
	_press(_hud().get_node("%EndTurnButton"))
	await _settle()


func _confirm_gate() -> void:
	_press(_gate().get_node("%ConfirmButton"))
	await _settle()


## Вибрати юніт, тапнути ціль, підтвердити.
func _act(from: Vector2i, to: Vector2i) -> void:
	_tap(from)
	_tap(to)
	await _confirm()


func _unit(id: int) -> Unit:
	return _service.state.get_unit(id)


func _events_of(cls: Variant) -> Array[Events.BattleEvent]:
	var out: Array[Events.BattleEvent] = []
	for e in _service.events:
		if is_instance_of(e, cls):
			out.append(e)
	return out


func _index_of(pred: Callable) -> int:
	for i in _service.events.size():
		if pred.call(_service.events[i]):
			return i
	return -1


# --- 1. Рух по місцевості ------------------------------------------------------

## Броньовик: cross_country 5, AP 68. cost = max(10, 10 + penalty - 5).
## Штрафи: дорога 0, поле 10, ліс 20; MUD +10 до не-доріг, FROZEN -5 (мін. 0).
## DRY:    дорога 10, поле 15, ліс 25
## MUD:    дорога 10, поле 25, ліс 35   (поле 10+20-5, ліс 10+30-5)
## FROZEN: дорога 10, поле 10, ліс 20   (поле max(10, 10+5-5), ліс 10+15-5)
func test_movement_cost_per_terrain_and_ground_state() -> void:
	var table: Array = [
		[Terrain.GroundState.DRY, Terrain.Kind.ROAD, 10],
		[Terrain.GroundState.DRY, Terrain.Kind.FIELD, 15],
		[Terrain.GroundState.DRY, Terrain.Kind.FOREST, 25],
		[Terrain.GroundState.MUD, Terrain.Kind.ROAD, 10],
		[Terrain.GroundState.MUD, Terrain.Kind.FIELD, 25],
		[Terrain.GroundState.MUD, Terrain.Kind.FOREST, 35],
		[Terrain.GroundState.FROZEN, Terrain.Kind.ROAD, 10],
		[Terrain.GroundState.FROZEN, Terrain.Kind.FIELD, 10],
		[Terrain.GroundState.FROZEN, Terrain.Kind.FOREST, 20],
	]
	for row: Array in table:
		await _boot(6, 3, [_spawn(ARMOURED_CAR, 0, Vector2i(1, 1)), _spawn(RIFLE, 1, Vector2i(5, 0))],
			{Vector2i(2, 1): row[1]}, row[0])
		await _act(Vector2i(1, 1), Vector2i(2, 1))
		var car: Unit = _unit(1)
		var label: String = "ground %d, tile %d" % [row[0], row[1]]
		assert_eq(car.pos, Vector2i(2, 1), label)
		assert_eq(car.ap, 68 - int(row[2]), "AP після входу: " + label)
		assert_eq(car.facing, E, "обличчя з останнього кроку: " + label)


func test_movement_in_several_steps_spends_only_what_is_entered() -> void:
	# Ряд y=1: дорога(2), поле(3), ліс(4), ліс(5). Вода над стартом — непрохідна.
	await _boot(7, 3, [_spawn(ARMOURED_CAR, 0, Vector2i(1, 1)), _spawn(RIFLE, 1, Vector2i(6, 0))], {
		Vector2i(2, 1): Terrain.Kind.ROAD, Vector2i(4, 1): Terrain.Kind.FOREST,
		Vector2i(5, 1): Terrain.Kind.FOREST, Vector2i(1, 0): Terrain.Kind.WATER})
	var car: Unit = _unit(1)
	await _act(Vector2i(1, 1), Vector2i(2, 1))
	assert_eq(car.ap, 58, "дорога 10")
	# юніт лишається вибраним: повторний тап по ньому зняв би вибір
	_tap(Vector2i(3, 1))
	await _confirm()
	assert_eq(car.ap, 43, "поле 15 — окремий крок того ж ходу (рух витрачається, не фіксується)")
	_tap(Vector2i(4, 1))
	await _confirm()
	assert_eq(car.ap, 18, "ліс 25")
	assert_eq(car.pos, Vector2i(4, 1))
	# Ліс 25 > 18: клітинка поза зоною — тап не створює прев'ю, кнопка лишається вимкненою.
	_tap(Vector2i(5, 1))
	assert_true((_hud().get_node("%ConfirmButton") as Button).disabled, "поза зоною AP")
	assert_eq(car.pos, Vector2i(4, 1))
	assert_eq(car.ap, 18)


# --- 2. Сектори броні ------------------------------------------------------------

## Постріл середнього танка (атака 95) по середньому (броня 37/27/18), дистанція 2.
## Кидки сіда 7: атака 11 (межа 0..23), броня: front 1 (0..9), side 6 (0..6), rear 1 (0..4).
## dmg = int(0.75*95 + 11 - (0.75*armour + r_armour)):
##   front 71.25+11-(27.75+1)=53.5 -> 53;  side 82.25-(20.25+6)=56;  rear 82.25-(13.5+1)=67.75 -> 67
## Прев'ю (межі без кидків): front 34..66, side 45..74, rear 53..80.
## Відповідь: ціль (на AP, бачить, у радіусі) б'є в ЛОБ атакувальника (він щойно
## розвернувся до неї): кидки 4 (0..23) і 1 (0..9): int(71.25+4-(27.75+1)) = 46.
func _sector_case(attacker_cell: Vector2i, attacker_facing_after: int, sector: int,
		lo: int, hi: int, dmg: int, target_facing_after: int) -> void:
	var target_cell := Vector2i(4, 3)
	await _boot(9, 7, [
		_spawn(MEDIUM_TANK, 0, attacker_cell, E),
		_spawn(MEDIUM_TANK, 1, target_cell, N)])
	var attacker: Unit = _unit(1)
	var target: Unit = _unit(2)

	_tap(attacker_cell)
	_tap(target_cell)
	# прев'ю до підтвердження: сектор і межі, жодних змін стану
	assert_eq((_hud().get_node("%PreviewSectorValue") as Label).text,
		tr(UnitInspector.SECTOR_KEYS[sector]))
	assert_eq((_hud().get_node("%PreviewDamageValue") as Label).text, "%d–%d" % [lo, hi])
	assert_eq(target.hp, 400)
	assert_eq(attacker.facing, E, "прев'ю не повертає")
	await _confirm()

	assert_eq(target.hp, 400 - dmg, "golden-шкода")
	assert_eq(attacker.hp, 400 - 46, "відповідь у лоб")
	assert_eq(attacker.ap, 0, "постріл обнуляє AP")
	assert_true(attacker.has_fired)
	assert_eq(attacker.facing, attacker_facing_after, "стрілець розвернувся на ціль")
	assert_eq(target.facing, target_facing_after, "ціль розвернулась на нападника після відповіді")
	assert_eq(target.ap, 0, "відповідач витратив AP")
	# Порядок: розворот стрільця -> постріл -> шкода цілі -> (лише тоді) розворот цілі.
	var turn_att: int = _index_of(func(e: Events.BattleEvent) -> bool: return e is Events.UnitTurned and e.unit_id == 1)
	var shot: int = _index_of(func(e: Events.BattleEvent) -> bool: return e is Events.ShotFired)
	var dmg_t: int = _index_of(func(e: Events.BattleEvent) -> bool: return e is Events.DamageDealt and e.unit_id == 2)
	var turn_tgt: int = _index_of(func(e: Events.BattleEvent) -> bool: return e is Events.UnitTurned and e.unit_id == 2)
	assert_true(turn_att >= 0 and turn_att < shot, "стрілець повертається ПЕРЕД пострілом")
	assert_true(shot < dmg_t)
	if target_facing_after != N:
		assert_true(turn_tgt > dmg_t, "ціль повертається ПІСЛЯ шкоди, ніколи до")
	else:
		assert_eq(turn_tgt, -1, "ціль уже дивилась на нападника — події повороту нема")
	var shot_ev: Events.ShotFired = _events_of(Events.ShotFired)[0]
	assert_eq(shot_ev.sector, sector)
	var retort: Events.ShotRetaliated = _events_of(Events.ShotRetaliated)[0]
	assert_eq(retort.sector, UnitTypes.ArmourSector.FRONT)


func test_armour_front_sector() -> void:
	await _sector_case(Vector2i(4, 1), S, UnitTypes.ArmourSector.FRONT, 34, 66, 53, N)


func test_armour_side_sector() -> void:
	await _sector_case(Vector2i(6, 3), W, UnitTypes.ArmourSector.SIDE, 45, 74, 56, E)


func test_armour_rear_sector() -> void:
	await _sector_case(Vector2i(4, 5), N, UnitTypes.ArmourSector.REAR, 53, 80, 67, S)


# --- 3. Відповідний вогонь ---------------------------------------------------------

func test_retaliation_ap_cost_is_for_attackers_turn_only() -> void:
	await _boot(9, 7, [_spawn(MEDIUM_TANK, 0, Vector2i(4, 1), E), _spawn(MEDIUM_TANK, 1, Vector2i(4, 3), N)])
	await _act(Vector2i(4, 1), Vector2i(4, 3))
	var attacker: Unit = _unit(1)
	var target: Unit = _unit(2)
	assert_eq(attacker.ap, 0)
	assert_eq(target.ap, 0, "відповідь коштує AP до кінця ходу атакувальника")
	# Стрілець більше нічого не може: рух відхиляється правилами.
	assert_eq(_service.submit(MoveCommand.create(1, Vector2i(4, 0), -1)), "ERR_ALREADY_FIRED")
	await _settle()

	await _end_turn()
	assert_true(_gate().visible)
	await _confirm_gate()
	assert_eq(_service.state.active_player, 1)
	assert_eq(target.ap, 48, "власний хід відповідача — AP знову повне")
	assert_false(target.has_fired)


func test_engineer_never_retaliates() -> void:
	# Танк (95) по сапері (броня front 10), сід 7: кидки 11 (0..23) і 1 (0..2):
	# int(71.25 + 11 - (7.5 + 1)) = 73 -> 200 - 73 = 127.
	# Впритул: радіус сапера 1, тож лише так відсутність відповіді — наслідок правила, а не дальності.
	await _boot(9, 7, [_spawn(MEDIUM_TANK, 0, Vector2i(4, 2), E), _spawn(ENGINEER, 1, Vector2i(4, 3), N)])
	await _act(Vector2i(4, 2), Vector2i(4, 3))
	var eng: Unit = _unit(2)
	assert_eq(eng.hp, 127)
	assert_eq(eng.ap, 68, "сапер не витрачає AP на відповідь")
	assert_eq(eng.facing, N, "і не повертається")
	assert_eq(_unit(1).hp, 400)
	assert_eq(_events_of(Events.ShotRetaliated).size(), 0)


# --- 4. Невидимий нападник -----------------------------------------------------------

## Танк (огляд 4, дальність 4) стріляє з (1,3) по гарматі (огляд 3, дальність 5) на (5,3):
## манхеттен 4 -> гармата його не бачить (тайл не розвіданий), хоч дістала б.
## Постріл: int(71.25 + 11) = 82 (броня гармати збоку 0, кидок броні 0 -> без кидка) -> 118.
func test_unseen_attacker_is_not_retaliated_against() -> void:
	await _boot(9, 7, [_spawn(MEDIUM_TANK, 0, Vector2i(1, 3), E), _spawn(FIELD_GUN, 1, Vector2i(5, 3), N)])
	await _act(Vector2i(1, 3), Vector2i(5, 3))
	var gun: Unit = _unit(2)
	assert_eq(gun.hp, 200 - 82)
	assert_eq(gun.ap, 24, "не відповіла — AP цілий")
	assert_eq(gun.facing, N, "невидимий нападник не повертає ціль (це був би витік)")
	assert_eq(_unit(1).hp, 400, "безкарний постріл")
	assert_eq(_events_of(Events.ShotRetaliated).size(), 0)


## Те саме, але стрілецький загін гравця 1 на (3,5) розвідує (1,3) (манхеттен 4 <= 5):
## тепер гармата бачить нападника і б'є у відповідь у лоб танка:
## кидки 16 (0..50), 8 (0..9), 73 (0..100): int(150 + 16 - (27.75 + 8) + 73) = 203 -> 400-203=197.
func test_scouted_attacker_is_retaliated_against() -> void:
	await _boot(9, 7, [_spawn(MEDIUM_TANK, 0, Vector2i(1, 3), E), _spawn(FIELD_GUN, 1, Vector2i(5, 3), N),
		_spawn(RIFLE, 1, Vector2i(3, 5))])
	await _act(Vector2i(1, 3), Vector2i(5, 3))
	assert_eq(_unit(2).hp, 200 - 82)
	assert_eq(_unit(1).hp, 400 - 203)
	assert_eq(_unit(2).ap, 0)
	assert_eq(_unit(2).facing, W, "відповідач розвернувся на нападника")


# --- 5. Хід крізь туман -----------------------------------------------------------------

func test_walk_stops_before_enemy_the_planner_could_not_see() -> void:
	var road: Dictionary = {}
	for x in 8:
		road[Vector2i(x, 1)] = Terrain.Kind.ROAD
	# Броньовик (огляд 3) на (0,1); стрілець гравця 1 на (4,1) — манхеттен 4, не розвіданий.
	await _boot(8, 3, [_spawn(ARMOURED_CAR, 0, Vector2i(0, 1), E), _spawn(RIFLE, 1, Vector2i(4, 1))], road)
	assert_null(_screen.unit_view_for(2), "невидимий ворог не має вузла")

	_tap(Vector2i(0, 1))
	_tap(Vector2i(6, 1))
	assert_eq((_hud().get_node("%PreviewApValue") as Label).text, "8", "план: 6 доріг по 10, лишається 8")
	await _confirm()

	var car: Unit = _unit(1)
	assert_eq(car.pos, Vector2i(3, 1), "зупинився на тайлі ПЕРЕД невидимим ворогом")
	assert_eq(car.ap, 38, "AP лише за 3 фактично пройдені тайли: 68-30")
	assert_eq(car.facing, E)
	var blocked: Events.MoveBlocked = _events_of(Events.MoveBlocked)[0]
	assert_eq(blocked.pos, Vector2i(4, 1))
	assert_eq(_unit(2).pos, Vector2i(4, 1), "ворога ніхто не зсунув")
	assert_not_null(_screen.unit_view_for(2), "тепер тайл розвіданий — вузол зʼявився")


# --- 8. Цикл ходів ---------------------------------------------------------------------------

func test_turn_cycle_gate_fog_and_ap_restore() -> void:
	await _boot(10, 3, [_spawn(RIFLE, 0, Vector2i(0, 1), E), _spawn(RIFLE, 1, Vector2i(9, 1), W)])
	assert_null(_screen.unit_view_for(2), "ворога (манхеттен 9 > 5) не видно")
	await _act(Vector2i(0, 1), Vector2i(1, 1))
	assert_eq(_unit(1).ap, 20, "піхота: поле = 10")

	await _end_turn()
	assert_true(_gate().visible, "передача ходу — завжди за гейтом")
	assert_eq(_service.state.active_player, 1)
	assert_null(_screen.unit_view_for(2), "до підтвердження гейта нічого про гравця 1 не показано")

	await _confirm_gate()
	assert_false(_gate().visible)
	assert_not_null(_screen.unit_view_for(2), "свої юніти гравця 1")
	assert_null(_screen.unit_view_for(1), "гравець 1 ніколи не розвідував (1,1): манхеттен 8")
	var rig: IsoCameraRig = _screen.get_node("%CameraRig")
	assert_almost_eq(rig.global_position.x, 9.0, 0.001, "камера на першому юніті гравця, що заходить")
	assert_almost_eq(rig.global_position.z, 1.0, 0.001)
	assert_eq(_service.state.turn_number, 1)

	await _end_turn()
	assert_true(_gate().visible)
	await _confirm_gate()
	assert_eq(_service.state.active_player, 0)
	assert_eq(_service.state.turn_number, 2, "коло завершене — новий номер ходу")
	assert_eq(_unit(1).ap, 30, "AP відновлено до максимуму")
	assert_eq(_unit(1).pos, Vector2i(1, 1))
	assert_null(_screen.unit_view_for(2))


## Два важкі танки (атака 121) по саперу (200 HP, броня front 10), обидва вогонь з півночі
## -> лоб. Кидки сіда 7 (межі 0..30, 0..2): постріл 1 -> 90, 2 -> 85, 3 -> 82
## (int(90.75 + r - (7.5 + r2))). 200 -> 110 -> 25 -> третій постріл (82) добиває:
## застосовується лише 25 (min(dmg, hp)).
func test_play_to_elimination_ends_match() -> void:
	await _boot(8, 6, [_spawn(HEAVY_TANK, 0, Vector2i(3, 1), E), _spawn(HEAVY_TANK, 0, Vector2i(4, 1), E),
		_spawn(ENGINEER, 1, Vector2i(3, 3), N)])
	watch_signals(_screen)
	var eng: Unit = _unit(3)

	await _act(Vector2i(3, 1), Vector2i(3, 3))
	assert_eq(eng.hp, 110)
	await _act(Vector2i(4, 1), Vector2i(3, 3))
	assert_eq(eng.hp, 25)
	assert_false(_service.state.is_over())

	await _end_turn()
	await _confirm_gate()
	await _end_turn()
	await _confirm_gate()
	assert_eq(_service.state.turn_number, 2)
	assert_eq(_unit(1).ap, 40, "важкий танк знову на ногах")

	await _act(Vector2i(3, 1), Vector2i(3, 3))
	assert_false(eng.is_alive())
	assert_true(_service.state.is_over())
	assert_eq(_service.state.winner, 0)
	assert_signal_emitted(_screen, "match_finished")
	assert_true((_hud().get_node("%EndTurnButton") as Button).disabled, "після кінця матчу ходу не завершити")
	assert_eq(_events_of(Events.ShotRetaliated).size(), 0, "сапер за весь бій жодного разу не відповів")


