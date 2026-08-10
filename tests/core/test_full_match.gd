extends GutTest
## Задача 1.19 — наскрізний тест матчу. Це не юніт-тест жодного окремого модуля:
## це страховка, яка ловить регресії на стиках вісімнадцяти попередніх завдань.
## Матч грається виключно через Command'и (MoveCommand/FireCommand/EndTurnCommand/
## EngineerCommand) — жодного прямого встановлення hp/ap заради перемоги.
##
## Детермінізм: усі кидки йдуть через RandomNumberGenerator, зафіксований сідом у
## BattleState.create(). Замість підганяти сід під конкретний результат, кожна
## бойова асерція тут спирається на аналітичні межі Rules._damage_from_rolls()
## (той самий прийом, що й tests/core/test_retaliation.gd) — тобто тримається за
## БУДЬ-ЯКОГО кидка, а не лише "пощастило з сідом". Де кидок не впливає на
## бінарний результат (чи впала hp, чи спрацювала міна), він лишається не
## обмеженим, бо мінімальна шкода (§3.3 floor=10, міна 90+) завжди додатна.

const GUARD_MAX: int = 30

func _open_map() -> Board:
	## Проста рівнина 16x12 з дорожньою смугою вздовж y=6 — рівно той самий
	## flat-cost-10-за-тайл трюк, що й tests/core/test_move_command.gd.
	var b: Board = Board.create(16, 12, Terrain.GroundState.DRY)
	for x in 16:
		b.set_kind(Vector2i(x, 6), Terrain.Kind.ROAD)
	return b

func _bridge_map() -> Board:
	## Той самий острів, що й у брифі: єдиний прохід між західною і східною
	## половинами мапи — міст на (8,6), решта стовпця x=8 — вода.
	var b: Board = Board.create(16, 12, Terrain.GroundState.DRY)
	for x in 16:
		b.set_kind(Vector2i(x, 6), Terrain.Kind.ROAD)
	b.set_kind(Vector2i(8, 6), Terrain.Kind.BRIDGE)
	for y in 12:
		if y != 6:
			b.set_kind(Vector2i(8, y), Terrain.Kind.WATER)
	return b

func _count(events: Array, cls: Script) -> int:
	var n: int = 0
	for e in events:
		if is_instance_of(e, cls):
			n += 1
	return n

# ---------------------------------------------------------------------------
# Головний тест: цілий матч від begin_turn() до MatchEnded, лише через команди.
#
# Медіум танк (#5: atk95 ap48 hp400 range4 fire_cost20 armour 37/27/18 cc12
# vision4) переслідує бронеавтомобіль (#2: atk60 ap68 hp250 range3 fire_cost18
# armour 27/18/10 cc5 vision3) уздовж дороги (penalty0 -> entry_cost
# max(10,10-12)=10 за тайл для танка).
#
# Геометрія навмисно фіксована на весь бій: танк доїжджає до (5,6) двома
# частковими рухами й більше не рухається; бронеавтомобіль стоїть на (8,6) й
# ніколи не рухається. dist_sq = 3*3 = 9 — усередині дальності обох (16 і 9) і
# зору обох (16 і 9, точно на межі). Обидва дивляться один на одного впритул,
# тож сектор броні — завжди FRONT для обох напрямків, весь бій:
#   - постріл танка по бронеавтомобілю (FRONT, armour 27):
#       dmg = 0.75*95 + [0,23] - (0.75*27 + [0,6]) = 51 + [0,23] - [0,6]
#       межі: [45, 74] за постріл.
#   - відповідь бронеавтомобіля по танку (FRONT, armour 37):
#       dmg = 0.75*60 + [0,15] - (0.75*37 + [0,9]) = 17.25 + [0,15] - [0,9]
#       межі: [10, 32] (нижня межа 8.25 зрізається підлогою §3.3 MIN_DAMAGE=10).
# 250 hp / 45 (гірший випадок за постріл) -> не більш ніж 6 пострілів гарантовано
# добивають ціль, хай там що покаже кидок. За ці 6 обмінів танк отримує щонайбільше
# 6*32 = 192 — далеко нижче 400 hp, тож танк гарантовано доживає до кінця
# незалежно від жодного кидка. Це і є детермінізм: не сід підібраний під
# результат, а сценарій вибраний так, щоб результат не залежав від сіда.
func test_a_whole_match_runs_through_commands_only() -> void:
	var s: BattleState = BattleState.create(_open_map(), 2, 2024)
	var tank: Unit = s.add_unit(5, 0, Vector2i(3, 6), 2)   # гравець 0, дивиться на схід
	var enemy: Unit = s.add_unit(2, 1, Vector2i(8, 6), 6)  # гравець 1, дивиться на захід
	s.start()   # праймить видимість обох гравців ДО першого begin_turn() — §BattleState.start()

	var log: Array[Events.BattleEvent] = []

	# --- Хід 1, гравець 0: begin_turn -> два часткові рухи (§3.2: "рух
	# витрачається, а не фіксується") -> без пострілу цього ходу -> EndTurn.
	log.append_array(s.begin_turn())
	log.append_array(MoveCommand.create(tank.id, Vector2i(4, 6), 2).apply(s))
	log.append_array(MoveCommand.create(tank.id, Vector2i(5, 6), 2).apply(s))
	assert_eq(tank.pos, Vector2i(5, 6), "два часткові рухи довезли танк рівно туди, куди й прямий")
	assert_eq(tank.ap, 28, "48 - (10 + 10) = 28")
	assert_true(tank.ap >= tank.fire_cost(), "золота зона: після двох часткових рухів постріл ще можливий")

	# Фог per-player: (3,6) — стартовий тайл танка, гравець 0 його бачив від
	# самого початку ходу. Бронеавтомобіль нерухомий на (8,6), зір 3 (r²=9);
	# (3,6) лежить на dist_sq=25 від нього — поза межею зору назавжди. Це не
	# нульовий стан BattleState.create() (перевіряємо ПІСЛЯ реального
	# begin_turn() гравця 1 нижче) — це справжній розрахунок туману, який
	# показує, що дослідження гравця 0 не просочується в туман гравця 1.
	assert_true(s.vision[0].is_seen(Vector2i(3, 6)), "гравець 0 бачив свій стартовий тайл")

	log.append_array(EndTurnCommand.create().apply(s))
	assert_eq(s.active_player, 1)
	# EndTurnCommand.apply() уже викликав begin_turn(1) усередині себе — зір
	# гравця 1 тепер порахований по-справжньому (не нульовий дефолт).
	assert_false(s.vision[1].is_seen(Vector2i(3, 6)),
		"§3.5: тайл, бачений гравцем 0, не мусить ставати видимим гравцю 1")
	assert_false(s.vision[1].is_visible(Vector2i(3, 6)))

	# --- Хід 1, гравець 1: жодного руху по суті (поворот на місці — це теж
	# команда, а не порожній хід) -> EndTurn.
	log.append_array(MoveCommand.create(enemy.id, enemy.pos, 6).apply(s))
	log.append_array(EndTurnCommand.create().apply(s))
	assert_eq(s.active_player, 0)
	assert_eq(s.turn_number, 2, "хід повернувся до гравця 0 — номер ходу зріс")

	# --- Гравець 0 стріляє, доки бронеавтомобіль живий. Кожен цикл: постріл
	# (якщо валідний) -> EndTurn; якщо не хід гравця 0 — просто EndTurn.
	# guard — запобіжник від нескінченного циклу, а не спосіб проігнорувати
	# застряглий матч (CLAUDE.md: якщо впирається в guard, зупинитись і
	# розібратись чому, а не піднімати ліміт).
	var guard: int = 0
	var shots_fired: int = 0
	var total_retaliations: int = 0
	while enemy.is_alive() and guard < GUARD_MAX:
		guard += 1
		if s.active_player != 0:
			log.append_array(EndTurnCommand.create().apply(s))
			continue
		var cmd: FireCommand = FireCommand.create(tank.id, enemy.id)
		if cmd.validate(s) == "":
			var shot_events: Array[Events.BattleEvent] = cmd.apply(s)
			shots_fired += 1
			log.append_array(shot_events)
			# Термінація обміну доведена СТРУКТУРНО в
			# tests/core/test_retaliation.gd (_retaliate() ніде не викликає
			# apply() рекурсивно — рекурсія неможлива за побудовою графа
			# викликів, не лише "не трапляється" через AP чи дальність). Це тут
			# — не те місце, де це доводиться, а живий контроль на реальному
			# сценарії: обмін пострілами мусить завершуватись, а не ланцюжити.
			var retaliations_here: int = _count(shot_events, Events.ShotRetaliated)
			total_retaliations += retaliations_here
			assert_true(retaliations_here <= 1,
				"обмін пострілами мусить завершуватись — не ланцюг взаємних відповідей")
		# Постріл, що щойно був, міг добити ворога і завершити матч сам по собі
		# (MatchEnded уже emitted з FireCommand._resolve_damage()); apply()
		# тепер несе той самий інваріант validate(), що й решта команд, тож
		# EndTurnCommand більше не можна викликати на вже завершеному матчі.
		if not s.is_over():
			log.append_array(EndTurnCommand.create().apply(s))

	assert_true(guard < GUARD_MAX,
		"матч мусив завершитись задовго до guard — гірший випадок: 6 пострілів по 45 шкоди на 250 hp")
	assert_false(enemy.is_alive(), "танк мав дотиснути бронеавтомобіль — гірший випадок гарантує це до guard")
	assert_true(tank.is_alive(), "гірший випадок відповідей (6*32=192) << 400 hp — танк мусив дожити")
	assert_true(shots_fired <= 6, "гірша межа 45 шкоди/постріл на 250 hp -> не більш ніж 6 пострілів")
	# Без цього `<= 1` вище проходить так само на нулі, як і на одиниці — а
	# геометрія цього сценарію вже один раз випадково потрапляла в мертву зону
	# "дальність без зору" (див. звіт задачі 1.19) і давала нуль відповідей,
	# мовчки знецінюючи перевірку термінації. total_retaliations >= 1 фіксує,
	# що обмін дійсно стався бодай раз, а не лише "ніколи не перевищив ліміт".
	assert_true(total_retaliations >= 1,
		"цей сценарій мав спричинити принаймні одну відповідь: інакше `<= 1` вище " +
		"проходить на нулі й перевіряє порожнечу")

	assert_true(s.is_over())
	assert_eq(s.winner, 0)

	var eliminated_idx: int = -1
	var ended_idx: int = -1
	var eliminated_count: int = 0
	var ended_count: int = 0
	for i in log.size():
		if log[i] is Events.PlayerEliminated:
			eliminated_count += 1
			if eliminated_idx < 0:
				eliminated_idx = i
		if log[i] is Events.MatchEnded:
			ended_count += 1
			if ended_idx < 0:
				ended_idx = i
	assert_eq(eliminated_count, 1, "гравець 1 вибуває рівно один раз")
	assert_eq(ended_count, 1, "матч завершується рівно один раз")
	assert_true(eliminated_idx >= 0 and ended_idx >= 0)
	assert_true(eliminated_idx < ended_idx, "PlayerEliminated мусить передувати MatchEnded у потоці подій")

# ---------------------------------------------------------------------------
# Міна, закладена одним гравцем, підриває юніт іншого — через команди, без
# прямого читання/запису внутрішніх полів міни. Бронеавтомобіль (250 hp) явно
# переживає підрив (90..180 шкоди), тож перевірка "hp впала" не залежить від
# кидка, а сам підрив (90 + rand(0,90)) завжди додатний — детерміновано, що hp
# зменшиться, недетерміновано лише наскільки.
func test_mine_laid_by_one_player_is_triggered_by_the_other() -> void:
	var s: BattleState = BattleState.create(Board.create(10, 10, Terrain.GroundState.DRY), 2, 7)
	var engineer: Unit = s.add_unit(11, 0, Vector2i(4, 4), 0)
	# Юніт гравця 1 мусить існувати ДО EndTurnCommand: воно викликає
	# check_elimination() як частину завершення ходу гравця 0, і якщо в
	# гравця 1 на той момент іще нема жодного юніта, check_elimination
	# помилково зарахує його вибулим і завершить матч раніше часу.
	var enemy: Unit = s.add_unit(2, 1, Vector2i(1, 3), 2)
	s.start()
	s.begin_turn()
	var lay: EngineerCommand = EngineerCommand.create(engineer.id, EngineerCommand.Action.LAY_MINE, Vector2i(4, 3))
	assert_eq(lay.validate(s), "")
	lay.apply(s)
	assert_not_null(Mines.mine_at(s, Vector2i(4, 3)))
	assert_true(Mines.is_known(s, Vector2i(4, 3), 0), "власник бачить свою міну")
	assert_false(Mines.is_known(s, Vector2i(4, 3), 1), "§3.11: для іншого гравця вона невидима")

	# Хід переходить до гравця 1, чиїм юнітом і підриватимемось — MoveCommand
	# відхиляє чужого юніта (ERR_NOT_YOUR_UNIT), так само як і в бою.
	EndTurnCommand.create().apply(s)

	# Заходимо на міну з іншого боку колонки x=4, а не через (4,4): там сидить
	# інженер, і зайнятий тайл зробив би шлях недосяжним ще до самої міни —
	# це перевірка обриву руху на міні, а не на сусідові.
	var before_hp: int = enemy.hp
	var events: Array[Events.BattleEvent] = MoveCommand.create(enemy.id, Vector2i(5, 3), -1).apply(s)

	assert_true(enemy.hp < before_hp, "§3.11: наїзд на нерозкриту міну підриває юніт")
	assert_eq(enemy.pos, Vector2i(4, 3), "рух обривається на міні, а не проходить крізь неї")
	assert_null(Mines.mine_at(s, Vector2i(4, 3)), "міна одноразова")
	assert_true(_count(events, Events.MineTriggered) == 1)

# ---------------------------------------------------------------------------
# §3.8: підрив мосту — найважча дія в грі, бо перекроює прохідність мапи.
# Перевіряємо не лише вид тайла, а й наслідок для Pathing: після підриву
# єдиного мосту через водну перешкоду східна половина мапи стає недосяжною
# із західної.
#
# tank.ap встановлено вручну в нереалістично велике число — це єдине пряме
# втручання в поле юніта в усьому файлі, і воно навмисно НЕ впливає на бій
# чи перемогу: це чистий Pathing-запит (яку територію взагалі покриває
# Dijkstra), а не спроба змусити команду прийняти нелегальний хід. Жоден
# реальний юніт у ростері не має достатньо AP, щоб чесно дійти до
# протилежного краю 16-клітинної мапи за один хід, а тестувати "неможливо
# дістатись" саме означає прибрати межу AP з рівняння.
func test_demolished_bridge_cuts_the_map_in_two() -> void:
	var s: BattleState = BattleState.create(_bridge_map(), 2, 5)
	var engineer: Unit = s.add_unit(11, 0, Vector2i(7, 6), 2)
	s.add_unit(5, 1, Vector2i(12, 6), 6)
	s.start()
	s.begin_turn()

	assert_true(s.board.is_passable(Vector2i(8, 6)), "передумова: міст ще цілий")
	var demolish: EngineerCommand = EngineerCommand.create(
		engineer.id, EngineerCommand.Action.DEMOLISH_BRIDGE, Vector2i(8, 6))
	assert_eq(demolish.validate(s), "")
	var events: Array[Events.BattleEvent] = demolish.apply(s)
	assert_true(_count(events, Events.BridgeChanged) == 1)
	assert_eq(s.board.kind_at(Vector2i(8, 6)), Terrain.Kind.BRIDGE_DESTROYED)
	assert_false(s.board.is_passable(Vector2i(8, 6)))

	var tank: Unit = s.add_unit(5, 0, Vector2i(6, 6), 2)
	tank.ap = 10_000  # див. коментар вище — лише для покриття Pathing, не для бою.
	var zones: Pathing.Zones = Pathing.compute_zones(s.board, tank, s.occupied_map())
	assert_false(zones.can_reach(Vector2i(12, 6)),
		"§3.8: підрив переправи перекроює карту — східний берег недосяжний")

# ---------------------------------------------------------------------------
# Стан матчу переживає збереження/відновлення мідмеч — через ту саму пару
# команд, що й решта тестів, до і після серіалізації.
func test_state_survives_a_save_load_mid_match() -> void:
	var s: BattleState = BattleState.create(_open_map(), 2, 99)
	var tank: Unit = s.add_unit(5, 0, Vector2i(2, 6), 2)
	s.add_unit(2, 1, Vector2i(12, 6), 6)
	s.start()
	s.begin_turn()
	MoveCommand.create(tank.id, Vector2i(5, 6), 2).apply(s)

	var restored: BattleState = BattleSerializer.from_dict(BattleSerializer.to_dict(s))
	assert_eq(restored.get_unit(tank.id).pos, Vector2i(5, 6))
	assert_eq(restored.get_unit(tank.id).ap, tank.ap)
	assert_eq(restored.get_unit(tank.id).has_fired, tank.has_fired)
	assert_eq(restored.active_player, s.active_player)
	assert_eq(EndTurnCommand.create().validate(restored), "")

# ---------------------------------------------------------------------------
# BattleState.start(): a defender can retaliate during player 0's very first
# turn — before player 1 has ever had a begin_turn() of their own to compute
# an honest vision grid. Without start(), vision[1] is still the all-zero
# grid BattleState.create() built, FireCommand._retaliate() gates the
# counter-shot on state.vision[target.owner].is_seen(...), and this shot
# would go answered by nobody. This is the exact defect fixed by priming
# every player's vision once, up front, via start().
#
# Two medium tanks (#5: atk 95, ap 48, hp 400, range 4, fire_cost 20, armour
# 37/27/18) face each other head-on at distance 2 (dist_sq = 4), same
# geometry as tests/core/test_retaliation.gd case 1 — well inside both
# units' range (16) and vision (16), so both survive the opening exchange
# (bounds [34, 66] per shot, both floors well under 400 hp) and the only
# thing gating the retaliation is whether player 1's vision was ever primed.
func test_defender_can_retaliate_during_player_zeros_opening_turn() -> void:
	var s: BattleState = BattleState.create(Board.create(16, 16, Terrain.GroundState.DRY), 2, 11)
	var a: Unit = s.add_unit(5, 0, Vector2i(4, 4), 2)   # схід
	var t: Unit = s.add_unit(5, 1, Vector2i(6, 4), 6)   # захід — дивиться просто на атакувальника
	s.start()   # без цього виклику vision[1] лишається нульовою — тест провалиться
	s.active_player = 0
	s.begin_turn()   # player 1's begin_turn() has NEVER run at this point

	var attacker_hp_before: int = a.hp
	var events: Array = FireCommand.create(a.id, t.id).apply(s)

	var retaliated: bool = false
	for e in events:
		if e is Events.ShotRetaliated:
			retaliated = true
	assert_true(retaliated,
		"BattleState.start() мусив праймити зір гравця 1 ще до його першого ходу — інакше він не бачить атакувальника")
	assert_true(a.hp < attacker_hp_before, "відповідь мусила завдати шкоди атакувальнику")
