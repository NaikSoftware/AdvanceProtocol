extends GutTest

var state: BattleState

func before_each() -> void:
	var b: Board = Board.create(10, 10, Terrain.GroundState.DRY)
	for x in 10:
		b.set_kind(Vector2i(x, 5), Terrain.Kind.ROAD)
	state = BattleState.create(b, 2, 11)

func test_move_costs_ap_and_moves_the_unit() -> void:
	var u: Unit = state.add_unit(5, 0, Vector2i(0, 5), 2)
	var before: int = u.ap
	var cmd: MoveCommand = MoveCommand.create(u.id, Vector2i(3, 5), -1)
	assert_eq(cmd.validate(state), "")
	var events: Array = cmd.apply(state)
	assert_eq(u.pos, Vector2i(3, 5))
	assert_true(u.ap < before)
	assert_true(events[0] is Events.UnitMoved)

func test_an_objective_passed_mid_turn_is_remembered_without_waiting_for_the_next_turn() -> void:
	# §3.10: цілі підкоряються туману, отже позначатися побаченими мусять там само,
	# де оновлюється туман. Доти refresh_seen() викликався лише з begin_turn(), тож
	# ціль, побачена серед ходу, не памʼяталася — а якби юніт до наступного ходу
	# відійшов, не запамʼяталася б узагалі.
	var u: Unit = state.add_unit(5, 0, Vector2i(0, 5), 2)
	var idx: int = Objectives.add(state, Vector2i(6, 5), 1)
	state.start()
	assert_false(state.objectives[idx].seen_by[0], "передумова: ціль поза оглядом до ходу")

	MoveCommand.create(u.id, Vector2i(3, 5), -1).apply(state)

	assert_true(state.objectives[idx].seen_by[0],
		"ціль, побачену серед ходу, памʼятаємо одразу, а не з наступного begin_turn()")

func test_move_sets_explicit_facing() -> void:
	var u: Unit = state.add_unit(5, 0, Vector2i(0, 5), 2)
	MoveCommand.create(u.id, Vector2i(3, 5), 6).apply(state)
	assert_eq(u.facing, 6, "гравець сам вирішує, куди дивитись — це вхід у модель броні")

func test_move_without_facing_uses_last_step_direction() -> void:
	var u: Unit = state.add_unit(5, 0, Vector2i(0, 5), 0)
	MoveCommand.create(u.id, Vector2i(3, 5), -1).apply(state)
	assert_eq(u.facing, 2, "останній крок був на схід")

func test_cannot_move_beyond_ap() -> void:
	var u: Unit = state.add_unit(9, 0, Vector2i(0, 5), 2)   # арта, ap 24
	var cmd: MoveCommand = MoveCommand.create(u.id, Vector2i(9, 5), -1)
	assert_ne(cmd.validate(state), "", "недосяжна ціль має бути відхилена")

func test_cannot_move_onto_another_unit() -> void:
	# Ворог, ЯКОГО ВИДНО: планування бачить його тайл зайнятим, і ціль відхиляється.
	# start() тут обовʼязковий — без нього vision порожня, ворог невидимий, і хід на
	# його тайл став би законним (див. test_a_hidden_enemy_on_the_destination_...).
	#
	# Це опис правила, а не сторожа переходу на туманну зайнятість: видимий ворог
	# перекриває тайл і у visible_occupied_map(), і у всезнаючій occupied_map(), тож
	# тест однаково зелений за обох. Сторожами тут працюють тести з невидимим ворогом
	# нижче — саме вони й розрізняють ці дві карти.
	var a: Unit = state.add_unit(5, 0, Vector2i(0, 5), 2)
	state.add_unit(5, 1, Vector2i(2, 5), 2)
	state.start()
	assert_true(state.vision[0].is_visible(Vector2i(2, 5)), "передумова: ворога видно")
	assert_ne(MoveCommand.create(a.id, Vector2i(2, 5), -1).validate(state), "")

func test_cannot_move_someone_elses_unit() -> void:
	var theirs: Unit = state.add_unit(5, 1, Vector2i(0, 5), 2)
	state.active_player = 0
	assert_ne(MoveCommand.create(theirs.id, Vector2i(1, 5), -1).validate(state), "")

func test_unit_that_fired_cannot_move() -> void:
	# Прапорець виставляється НАПРЯМУ, а не через exhaust(): той заразом обнуляє AP,
	# і тест проходив би навіть із видаленою перевіркою has_fired — просто з іншим
	# кодом відмови (нуль AP не доносить нікуди, отже ERR_OUT_OF_RANGE). Тут AP
	# лишається повним, тож єдина можлива причина відмови — постріл, і код
	# перевіряється точний, а не «якийсь непорожній».
	var u: Unit = state.add_unit(5, 0, Vector2i(0, 5), 2)
	u.has_fired = true
	assert_eq(MoveCommand.create(u.id, Vector2i(1, 5), -1).validate(state), "ERR_ALREADY_FIRED")

func test_move_refreshes_vision() -> void:
	var u: Unit = state.add_unit(0, 0, Vector2i(0, 5), 2)
	state.begin_turn()
	var events: Array = MoveCommand.create(u.id, Vector2i(3, 5), -1).apply(state)
	var has_reveal: bool = false
	for e in events:
		if e is Events.TileRevealed:
			has_reveal = true
	assert_true(has_reveal, "§3.5: видимість перераховується після кожного руху")

func test_end_turn_switches_player_and_bumps_turn_number() -> void:
	state.add_unit(0, 0, Vector2i(1, 1), 0)
	state.add_unit(0, 1, Vector2i(8, 8), 0)
	state.active_player = 0
	EndTurnCommand.create().apply(state)
	assert_eq(state.active_player, 1)
	EndTurnCommand.create().apply(state)
	assert_eq(state.active_player, 0)
	assert_eq(state.turn_number, 2, "номер ходу росте, коли черга повертається до першого гравця")

func test_move_validate_rejects_when_match_is_over() -> void:
	var u: Unit = state.add_unit(5, 0, Vector2i(0, 5), 2)
	state.check_elimination()   # у гравця 1 нема юнітів — матч завершується перемогою гравця 0
	assert_true(state.is_over(), "передумова: матч має бути завершений")
	assert_eq(MoveCommand.create(u.id, Vector2i(1, 5), -1).validate(state), "ERR_MATCH_OVER")

func test_end_turn_validate_rejects_when_match_is_over() -> void:
	state.add_unit(5, 0, Vector2i(0, 5), 2)
	state.check_elimination()
	assert_true(state.is_over(), "передумова: матч має бути завершений")
	assert_eq(EndTurnCommand.create().validate(state), "ERR_MATCH_OVER")

func test_turn_in_place_emits_unit_turned_not_unit_moved_and_costs_no_ap() -> void:
	var u: Unit = state.add_unit(5, 0, Vector2i(0, 5), 2)
	var before: int = u.ap
	var events: Array = MoveCommand.create(u.id, Vector2i(0, 5), 6).apply(state)
	assert_eq(u.pos, Vector2i(0, 5), "поворот на місці не рухає юніт")
	assert_eq(u.facing, 6)
	assert_eq(u.ap, before, "порожній шлях не має коштувати AP")
	var has_turned: bool = false
	var has_moved: bool = false
	var has_blocked: bool = false
	for e in events:
		if e is Events.UnitTurned:
			has_turned = true
		if e is Events.UnitMoved:
			has_moved = true
		if e is Events.MoveBlocked:
			has_blocked = true
	assert_true(has_turned, "поворот на місці — це UnitTurned")
	assert_false(has_moved, "порожній шлях не повинен породжувати UnitMoved")
	# Друга половина розрізнення (перша — у test_a_blocked_first_step_...): навмисний
	# поворот і обрив на першому кроці дають однаковий UnitTurned, тож усе, чим вони
	# відрізняються, — наявність MoveBlocked. Тут її бути не сміє.
	assert_false(has_blocked, "нікого не блокували — обриву в потоці бути не може")

func test_moving_onto_an_enemy_mine_detonates_it() -> void:
	var u: Unit = state.add_unit(5, 0, Vector2i(0, 5), 2)
	Mines.place(state, Vector2i(2, 5), 1)
	var before: int = u.hp
	MoveCommand.create(u.id, Vector2i(3, 5), -1).apply(state)
	assert_true(u.hp < before, "§3.11: наїзд на нерозкриту міну — підрив")
	assert_eq(u.pos, Vector2i(2, 5),
		"міна спрацьовує одразу — юніт лишається на тайлі підриву, а не доходить до (3,5)")

func test_a_minefield_cannot_be_crossed_by_stopping_past_it() -> void:
	# Найважливіший тест цього завдання: якби детонував лише кінцевий тайл,
	# міну можна було б просто переїхати, і вся механіка заборони руху зникла б.
	var u: Unit = state.add_unit(5, 0, Vector2i(0, 5), 2)
	Mines.place(state, Vector2i(1, 5), 1)
	MoveCommand.create(u.id, Vector2i(4, 5), -1).apply(state)
	assert_eq(u.pos, Vector2i(1, 5), "рух обривається на міні, а не проходить крізь неї")
	assert_true(state.mines.is_empty(), "міна витрачена")

func test_several_partial_moves_cost_the_same_as_one_direct_move() -> void:
	# §3.2, «рух витрачається, а не фіксується»: два часткові кроки мусять коштувати
	# рівно стільки ж AP, скільки один прямий хід на ту саму сумарну відстань.
	# Медіум танк (id 5): max_ap 48, cross_country 12; на дорозі penalty 0, тож
	# entry_cost = max(10, 10+0-12) = 10 за тайл — підлога зрізає cross_country
	# повністю, і кожен тайл коштує однаково незалежно від того, скільки їх лишилось.
	# Два кроки по 2 тайли: 20 + 20 = 40 AP, як і прямий хід на 4 тайли.
	var u: Unit = state.add_unit(5, 0, Vector2i(0, 5), 2)
	MoveCommand.create(u.id, Vector2i(2, 5), -1).apply(state)
	MoveCommand.create(u.id, Vector2i(4, 5), -1).apply(state)
	assert_eq(u.pos, Vector2i(4, 5))
	assert_eq(u.ap, 8, "48 - (20 + 20) = 8 — точно як один прямий хід на 4 тайли")

func test_partial_moves_leave_enough_ap_to_fire() -> void:
	# Суть правила: зони — про сумарно витрачений AP, а не про кількість окремих
	# рухів. 48 - (10 + 10) = 28 AP лишається, це >= fire_cost 20 — золота зона,
	# і постріл після двох часткових рухів мусить лишатись легальним.
	var u: Unit = state.add_unit(5, 0, Vector2i(0, 5), 2)
	var target: Unit = state.add_unit(0, 1, Vector2i(4, 5), 0)
	state.begin_turn()
	MoveCommand.create(u.id, Vector2i(1, 5), -1).apply(state)
	MoveCommand.create(u.id, Vector2i(2, 5), -1).apply(state)
	assert_eq(u.ap, 28, "48 - (10 + 10) = 28")
	var fire: FireCommand = FireCommand.create(u.id, target.id)
	assert_eq(fire.validate(state), "")
	var before_hp: int = target.hp
	fire.apply(state)
	assert_true(target.hp < before_hp, "постріл після часткових рухів дійсно влучає")

func test_partial_moves_into_the_red_zone_forecloses_firing() -> void:
	# 48 - (20 + 10) = 18 AP лишається, це < fire_cost 20 — червона зона: постріл
	# має бути відхилений, і причина мусить бути саме нестача AP, з точним кодом.
	var u: Unit = state.add_unit(5, 0, Vector2i(0, 5), 2)
	var target: Unit = state.add_unit(0, 1, Vector2i(9, 9), 0)
	MoveCommand.create(u.id, Vector2i(2, 5), -1).apply(state)
	MoveCommand.create(u.id, Vector2i(3, 5), -1).apply(state)
	assert_eq(u.ap, 18, "48 - (20 + 10) = 18")
	assert_eq(FireCommand.create(u.id, target.id).validate(state), "ERR_NOT_ENOUGH_AP")

func test_firing_after_partial_moves_forecloses_further_movement() -> void:
	# §3.2: постріл — єдине, що завершує активність юніта, незалежно від того,
	# скількома окремими кроками він до цього рухався. На відміну від
	# test_unit_that_fired_cannot_move (де прапорець виставлений напряму через
	# u.exhaust()), тут has_fired виникає зі справжнього FireCommand.apply() після
	# двох часткових рухів, і перевіряється точний код відмови, а не лише його
	# непорожність.
	var u: Unit = state.add_unit(5, 0, Vector2i(0, 5), 2)
	var target: Unit = state.add_unit(0, 1, Vector2i(4, 5), 0)
	state.begin_turn()
	MoveCommand.create(u.id, Vector2i(1, 5), -1).apply(state)
	MoveCommand.create(u.id, Vector2i(2, 5), -1).apply(state)
	FireCommand.create(u.id, target.id).apply(state)
	assert_eq(MoveCommand.create(u.id, Vector2i(3, 5), -1).validate(state), "ERR_ALREADY_FIRED")

func test_zones_predict_whether_firing_is_legal_after_the_move() -> void:
	# Звʼязує обіцянку UI (Pathing.compute_zones) із фактичною поведінкою команд:
	# золота зона мусить означати рівно "після ходу лишиться AP на постріл", а
	# червона — рівно "не лишиться".
	#
	# Зайнятість береться саме та, з якої зони будує сам MoveCommand
	# (visible_occupied_map), а не всезнаюча occupied_map() — і геометрія навмисно
	# підібрана так, щоб ця різниця мала зуби. Невидимий ворог сидить на (5,5), тобто
	# на дорозі МІЖ стартом і червоним тайлом (6,5). За всезнаючою картою (6,5) із зон
	# просто випав би — обхід полем коштує 89 AP при наявних 68, — і UI намалював би
	# контур, що вигинається навколо ворога, якого гравець не бачить. §3.5: сама форма
	# зони не має права бути доносом.
	#
	# Транспортер (тип 3): ap 68, fire_cost 18, огляд 3, дорога по 10.
	var u: Unit = state.add_unit(3, 0, Vector2i(0, 5), 2)
	var target: Unit = state.add_unit(0, 1, Vector2i(5, 5), 6)
	state.start()
	assert_false(state.vision[0].is_visible(Vector2i(5, 5)),
		"передумова: ворога на (5,5) з (0,5) не видно — 5 кроків проти огляду 3")

	var occupied: Dictionary = state.visible_occupied_map(u.owner)
	occupied.erase(u.pos)
	var zones: Pathing.Zones = Pathing.compute_zones(state.board, u, occupied)
	var gold: Vector2i = Vector2i(2, 5)   # 2 тайли дороги = 20 AP, лишається 48 >= 18
	var red: Vector2i = Vector2i(6, 5)    # 6 тайлів дороги = 60 AP, лишається 8 < 18
	assert_true(zones.move_and_fire.has(gold), "передумова: (2,5) — золота зона")
	assert_true(zones.move_only.has(red), "передумова: (6,5) — червона зона")

	MoveCommand.create(u.id, gold, -1).apply(state)
	assert_eq(u.pos, gold, "передумова: до золотого тайла ворог не дотягується")
	assert_eq(FireCommand.create(u.id, target.id).validate(state), "",
		"золота зона: постріл лишається легальним після ходу")

	# Червона половина — на чистій дошці: тут перевіряється ціна ходу, а не обрив,
	# тож дорогу ніхто не займає.
	var b2: Board = Board.create(10, 10, Terrain.GroundState.DRY)
	for x in 10:
		b2.set_kind(Vector2i(x, 5), Terrain.Kind.ROAD)
	var state2: BattleState = BattleState.create(b2, 2, 11)
	var u2: Unit = state2.add_unit(3, 0, Vector2i(0, 5), 2)
	var target2: Unit = state2.add_unit(0, 1, Vector2i(6, 8), 0)
	state2.start()
	MoveCommand.create(u2.id, red, -1).apply(state2)
	assert_eq(u2.pos, red, "передумова: дорога вільна, юніт справді доїхав до червоного тайла")
	assert_true(state2.vision[0].is_visible(Vector2i(6, 8)),
		"передумова: ціль видно й вона в дальності — відмова буде саме через AP")
	assert_eq(FireCommand.create(u2.id, target2.id).validate(state2), "ERR_NOT_ENOUGH_AP",
		"червона зона: рух зʼїв AP, потрібний на постріл")

func _index_of_tile_revealed(events: Array, player: int, tile: Vector2i) -> int:
	for i in events.size():
		var e: Variant = events[i]
		if e is Events.TileRevealed and e.player == player and tile in e.tiles:
			return i
	return -1

func _index_of_mine_revealed(events: Array, player: int, tile: Vector2i) -> int:
	for i in events.size():
		var e: Variant = events[i]
		if e is Events.MineRevealed and e.player == player and e.pos == tile:
			return i
	return -1

func test_mine_revealed_comes_after_the_tile_it_sits_on_is_revealed() -> void:
	# §3.5/§6: вигляд програє список подій по порядку, тож порядок — це контракт,
	# а не косметика. Сапер їде дорогою і з нової позиції вперше бачить і тайл
	# (7,5), і міну на ньому. Розкриття міни мусить іти ПІСЛЯ TileRevealed цього
	# тайла — інакше вигляд один крок малює міну на клітинці, що ще в тумані.
	# Кінцевий стан однаковий за будь-якого порядку, тому перевіряти треба саме
	# індекси подій.
	var eng: Unit = state.add_unit(11, 0, Vector2i(0, 5), 2)   # сапер, огляд 3
	Mines.place(state, Vector2i(7, 5), 1)
	state.begin_turn()
	assert_false(Mines.is_known(state, Vector2i(7, 5), 0),
		"передумова: з (0,5) до міни 7 тайлів — сапер її ще не бачить")
	var events: Array = MoveCommand.create(eng.id, Vector2i(4, 5), -1).apply(state)
	assert_eq(eng.pos, Vector2i(4, 5), "передумова: 4 тайли дороги по 15 AP — 60 з 68")
	var tile_at: int = _index_of_tile_revealed(events, 0, Vector2i(7, 5))
	var mine_at: int = _index_of_mine_revealed(events, 0, Vector2i(7, 5))
	assert_true(tile_at >= 0, "передумова: тайл міни розкрито саме цим рухом")
	assert_true(mine_at >= 0, "передумова: міна знайдена саме цим рухом")
	assert_true(tile_at < mine_at,
		"MineRevealed не має випереджати TileRevealed свого тайла (%d проти %d)" % [mine_at, tile_at])

# --- §3.5: маршрут будується з того, що гравець бачить, і йде по одному тайлу ---
#
# Спільна геометрія цих тестів. Транспортер (тип 3): ap 68, cross 7, огляд 3; на
# дорозі entry_cost = max(10, 10+0-7) = 10, тобто рівно 6 тайлів ходу. Ворог стоїть
# на (5,5) — за 5 тайлів від старту, а це поза ромбом огляду 3, отже його не видно
# доти, доки транспортер не підійде на три тайли. Саме ця пара чисел (досяжність 6
# проти огляду 3) і робить «ворог зʼявився з туману» можливим станом гри.

func test_a_hidden_enemy_on_the_path_halts_the_mover_one_tile_short() -> void:
	var u: Unit = state.add_unit(3, 0, Vector2i(0, 5), 2)
	state.add_unit(0, 1, Vector2i(5, 5), 6)
	state.start()
	assert_false(state.vision[0].is_visible(Vector2i(5, 5)),
		"передумова: ворога на (5,5) з (0,5) не видно — 5 тайлів проти огляду 3")

	var cmd: MoveCommand = MoveCommand.create(u.id, Vector2i(6, 5), -1)
	assert_eq(cmd.validate(state), "", "крізь порожню НА ВИГЛЯД землю планувати можна")
	cmd.apply(state)

	assert_eq(u.pos, Vector2i(4, 5), "рух спиняється НА тайлі перед тим, що виявився зайнятим")
	assert_eq(u.ap, 28, "68 − 4×10: платиться рівно за ті тайли, у які юніт увійшов")

func test_a_halt_names_itself_instead_of_leaving_the_view_to_infer_it() -> void:
	# Недоїзд мусить бути подією, а не арифметикою вигляду «наказ проти довжини
	# UnitMoved.path». Та сама причина, що й у ShotRetaliated: розрізняти події за
	# сусідами по списку в цьому проєкті заборонено.
	#
	# Тайл у події не додає гравцеві знання: юніт спинився ортогонально поруч із ним,
	# а найменший огляд у грі — ромб 3, тож (5,5) і так усередині його огляду. Id того,
	# хто там стоїть, подія навмисно не несе.
	var u: Unit = state.add_unit(3, 0, Vector2i(0, 5), 2)
	state.add_unit(0, 1, Vector2i(5, 5), 6)
	state.start()

	var events: Array = MoveCommand.create(u.id, Vector2i(6, 5), -1).apply(state)

	var blocked: Events.MoveBlocked = null
	for e in events:
		if e is Events.MoveBlocked:
			blocked = e
	assert_not_null(blocked, "обірваний хід мусить мати власну подію")
	assert_eq(blocked.unit_id, u.id)
	assert_eq(blocked.pos, Vector2i(5, 5),
		"названо тайл, у який не ввійшли, а не той, на якому спинились")
	assert_true(state.vision[0].is_visible(Vector2i(5, 5)),
		"і цей тайл у підсумковому стані видимий — подія не випереджає око")

func test_a_hidden_enemy_on_the_destination_makes_the_move_legal_but_short() -> void:
	# §3.5: помилки «там хтось стоїть» тут бути не може — вона повідомляла б рівно те,
	# чого гравець не має знати. Команда законна, а розплата — недоїзд.
	var u: Unit = state.add_unit(3, 0, Vector2i(0, 5), 2)
	state.add_unit(0, 1, Vector2i(5, 5), 6)
	state.start()

	var cmd: MoveCommand = MoveCommand.create(u.id, Vector2i(5, 5), -1)
	assert_eq(cmd.validate(state), "", "тайл під невидимим ворогом лишається законною ціллю")
	cmd.apply(state)

	assert_eq(u.pos, Vector2i(4, 5), "приїхав на тайл раніше, ніж збирався")
	assert_eq(u.ap, 28, "68 − 4×10")

func test_a_seen_enemy_puts_the_ground_behind_it_out_of_range() -> void:
	# Той самий ворог на тому самому тайлі — різниця рівно одна: у гравця 0 є
	# спостерігач, який його бачить. Стрілецьке відділення (огляд 5) на (5,1) світить
	# (5,5) за 4 тайли ромба. Обхід по полю коштує 89 AP при 68 наявних, тож видимий
	# ворог перетворює (6,5) на недосяжний тайл — і про це гравцеві кажуть ЗАЗДАЛЕГІДЬ,
	# а не після недоїзду. Це і є «око — зброя»: бачити ворога означає планувати чесно.
	#
	# Як і test_cannot_move_onto_another_unit, це опис правила, а не сторож туманної
	# зайнятості: ворога видно, отже обидві карти кажуть про нього те саме.
	var u: Unit = state.add_unit(3, 0, Vector2i(0, 5), 2)
	state.add_unit(0, 1, Vector2i(5, 5), 6)
	state.add_unit(0, 0, Vector2i(5, 1), 4)
	state.start()
	assert_true(state.vision[0].is_visible(Vector2i(5, 5)),
		"передумова: спостерігач на (5,1) бачить (5,5)")

	assert_eq(MoveCommand.create(u.id, Vector2i(6, 5), -1).validate(state), "ERR_OUT_OF_RANGE",
		"видимий ворог справді перекриває дорогу вже на етапі планування")

func test_a_seen_enemy_is_routed_around_at_planning_time() -> void:
	# Дві дорожні смуги, щоб обхід був по кишені: прямо (0,5)→(4,5) — 4 тайли по 10,
	# в обхід зайнятого (2,5) — 6 тайлів по 10. Ворога видно (2 тайли проти огляду 3),
	# отже юніт мусить ПРИЙТИ куди просили, заплативши за гак, а не спинитися перед ним.
	#
	# Знову ж таки: ворога видно, тож обидві карти зайнятості дають той самий гак —
	# тест описує форму обходу, а не пришпилює вибір карти.
	var b: Board = Board.create(10, 10, Terrain.GroundState.DRY)
	for x in 10:
		b.set_kind(Vector2i(x, 4), Terrain.Kind.ROAD)
		b.set_kind(Vector2i(x, 5), Terrain.Kind.ROAD)
	var s: BattleState = BattleState.create(b, 2, 11)
	var u: Unit = s.add_unit(3, 0, Vector2i(0, 5), 2)
	s.add_unit(0, 1, Vector2i(2, 5), 6)
	s.start()
	assert_true(s.vision[0].is_visible(Vector2i(2, 5)), "передумова: ворога видно")

	var cmd: MoveCommand = MoveCommand.create(u.id, Vector2i(4, 5), -1)
	assert_eq(cmd.validate(s), "")
	var events: Array = cmd.apply(s)

	assert_eq(u.pos, Vector2i(4, 5), "видимий ворог обходиться, а не спиняє хід")
	assert_eq(u.ap, 8, "68 − 6×10: заплачено за гак, а не за пряму")
	var moved: Events.UnitMoved = events[0]
	assert_eq(moved.path.size(), 6, "шість тайлів обходу")
	assert_false(Vector2i(2, 5) in moved.path, "крізь ворога не проїжджають")

func test_ap_pays_for_the_tiles_entered_not_for_the_ones_planned() -> void:
	# Пряме твердження §3.2 про обірваний хід: 6 запланованих тайлів коштували б 60,
	# але юніт увійшов у 4 — і платить 40. Інакше туман став би податком.
	#
	# Що саме він ловить, точно: списання за НАКАЗАНИЙ тайл, тобто zones.cost_to(target).
	# Варіант zones.cost_to(u.pos) — тобто за тайл, де юніт СПРАВДІ став, — він не
	# ловить і не може: шлях будується по ланцюжку батьків Дейкстри, тож кожен його
	# префікс і сам є найдешевшим маршрутом до свого кінця, а отже сума покрокових
	# вартостей дорівнює cost_to() кінцевої точки тотожно. Це не діра в тесті, а
	# рівність двох записів одного числа; покроково воно рахується тому, що не
	# потребує окремої обіцянки «цей тайл досяжний» (див. коментар у move_command.gd
	# про cost_to() = −1), а не тому, що дає інший результат.
	var u: Unit = state.add_unit(3, 0, Vector2i(0, 5), 2)
	state.add_unit(0, 1, Vector2i(5, 5), 6)
	state.start()
	var before: int = u.ap
	var events: Array = MoveCommand.create(u.id, Vector2i(6, 5), -1).apply(state)

	var moved: Events.UnitMoved = events[0]
	assert_eq(moved.path.size(), 4, "передумова: пройдено 4 тайли з 6 запланованих")
	assert_eq(before - u.ap, 40, "списано рівно 4×10, а не 60 за нездійснений план")

func test_the_mine_tile_is_paid_for_and_the_tiles_beyond_it_are_not() -> void:
	# Обидва обриви — заблокований тайл і міна — платять за однаковим правилом, але з
	# протилежних боків: у зайнятий тайл юніт НЕ входить і за нього не платить, у
	# замінований входить (там і підривається) — отже платить.
	var u: Unit = state.add_unit(5, 0, Vector2i(0, 5), 2)   # медіум: ap 48, дорога по 10
	Mines.place(state, Vector2i(2, 5), 1)
	state.start()
	var events: Array = MoveCommand.create(u.id, Vector2i(4, 5), -1).apply(state)

	assert_eq(u.pos, Vector2i(2, 5), "передумова: підрив спиняє хід на своєму тайлі")
	assert_eq(u.ap, 28, "48 − 2×10: тайл підриву оплачений, решта плану — ні")

	# Мінний обрив власної MoveBlocked не дістає, і це рішення, а не недогляд:
	# MineTriggered уже називає той самий юніт і той самий тайл, та ще й причину.
	# Друга подія про те саме лише змусила б вигляд гадати, котру з них слухати.
	var mine_at: int = -1
	for i in events.size():
		assert_false(events[i] is Events.MoveBlocked,
			"обрив на міні описує MineTriggered — дублювати його не треба")
		if events[i] is Events.MineTriggered and events[i].pos == Vector2i(2, 5):
			mine_at = i
	assert_true(mine_at >= 0, "…але сам MineTriggered на тайлі підриву бути мусить")
	assert_eq(events[mine_at].unit_id, u.id, "і він називає того, хто спинився")

func test_a_blocker_standing_on_a_mine_stops_the_move_without_setting_it_off() -> void:
	# Зіткнення двох правил на одному тайлі. Виграє зайнятість: юніт, який не може
	# туди вʼїхати, не може там і підірватися — міна лишається лежати цілою.
	var u: Unit = state.add_unit(3, 0, Vector2i(0, 5), 2)
	state.add_unit(0, 1, Vector2i(5, 5), 6)
	Mines.place(state, Vector2i(5, 5), 1)
	state.start()
	var before: int = u.hp

	MoveCommand.create(u.id, Vector2i(6, 5), -1).apply(state)

	assert_eq(u.pos, Vector2i(4, 5), "спиняє зайнятість, а не міна")
	assert_eq(u.hp, before, "на тайл, у який не ввійшов, юніт не підривається")
	assert_eq(state.mines.size(), 1, "міна лишається на місці — вона не спрацювала")

func test_a_blocked_first_step_turns_in_place_instead_of_moving() -> void:
	# Обрив на першому ж кроці: юніт нікуди не зрушив, і потік подій має сказати саме
	# це — UnitTurned, а не UnitMoved з порожнім шляхом.
	#
	# Стан навмисно НЕ праймлений (без start()/begin_turn()): у грі сусідній тайл
	# завжди в межах огляду будь-якого юніта, тож блокування на першому кроці
	# досяжне лише через порожній кеш видимості. Правило все одно мусить його
	# витримати — цикл ходу не має права припускати, що перший крок точно відбудеться.
	var u: Unit = state.add_unit(3, 0, Vector2i(0, 5), 2)
	state.add_unit(0, 1, Vector2i(1, 5), 6)
	assert_false(state.vision[0].is_visible(Vector2i(1, 5)),
		"передумова: видимість не праймлена, сусід невидимий")
	var before: int = u.ap

	var events: Array = MoveCommand.create(u.id, Vector2i(2, 5), 6).apply(state)

	assert_eq(u.pos, Vector2i(0, 5), "юніт не зрушив")
	assert_eq(u.ap, before, "нічого не пройдено — нічого не списано")
	assert_eq(u.facing, 6, "поворот усе одно відбувся")
	assert_true(events[0] is Events.UnitTurned, "порожній шлях — це UnitTurned")
	var blocked: Events.MoveBlocked = null
	for e in events:
		assert_false(e is Events.UnitMoved, "порожнього UnitMoved бути не може")
		if e is Events.MoveBlocked:
			blocked = e
	# Заголовок тут байт-у-байт такий самий, як у навмисного повороту на місці
	# (test_turn_in_place_...), тож єдине, чим вигляд може їх розрізнити, — оця подія.
	assert_not_null(blocked, "обрив на першому кроці мусить назвати себе")
	assert_eq(blocked.unit_id, u.id)
	assert_eq(blocked.pos, Vector2i(1, 5), "названо тайл, у який не ввійшли")

func test_the_walk_reveals_the_ground_it_passes_not_only_the_ground_it_ends_on() -> void:
	# §3.5: туман оновлюється НА КОЖНОМУ кроці. Сапер (огляд 3) їде дорогою; міна на
	# (1,2) лежить за 3 тайли ромба від (1,5) — тобто видима рівно з ПЕРШОГО кроку — і
	# за 6 тайлів від кінцевої (4,5), тобто з кінця шляху не видна взагалі. Якщо
	# перерахунок робити раз, після ходу, цю міну не знайде ніхто й ніколи.
	#
	# Перевіряються обидві половини контракту (§6): і стан (міна відома), і порядок
	# подій — MineRevealed не має випереджати TileRevealed свого тайла, і на середині
	# шляху так само, як і в кінці.
	var eng: Unit = state.add_unit(11, 0, Vector2i(0, 5), 2)   # сапер: ap 68, дорога по 15
	Mines.place(state, Vector2i(1, 2), 1)
	state.begin_turn()
	assert_false(Mines.is_known(state, Vector2i(1, 2), 0), "передумова: з (0,5) міни не видно")

	var events: Array = MoveCommand.create(eng.id, Vector2i(4, 5), -1).apply(state)

	assert_eq(eng.pos, Vector2i(4, 5), "передумова: 4 тайли по 15 — 60 з 68")
	assert_false(state.vision[0].is_visible(Vector2i(1, 2)),
		"передумова: з кінцевої (4,5) тайл міни вже поза оглядом")
	assert_true(Mines.is_known(state, Vector2i(1, 2), 0),
		"міну, повз яку проїхали, знайдено — огляд працює дорогою, а не лише в кінці")
	var tile_at: int = _index_of_tile_revealed(events, 0, Vector2i(1, 2))
	var mine_at: int = _index_of_mine_revealed(events, 0, Vector2i(1, 2))
	assert_true(tile_at >= 0, "тайл міни розкрито саме цим рухом")
	assert_true(mine_at >= 0, "міну знайдено саме цим рухом")
	assert_true(tile_at < mine_at,
		"MineRevealed не має випереджати TileRevealed свого тайла (%d проти %d)" % [mine_at, tile_at])

func test_a_unit_seen_from_the_middle_of_the_walk_is_seen_from_that_moment() -> void:
	# Той самий контракт, але про юніта, а не про міну: ворог на (5,5) входить в огляд
	# на другому кроці (з (2,5) до нього рівно 3), і TileRevealed його тайла мусить
	# стояти в потоці РАНІШЕ за туман наступних кроків — тобто прибути тоді, коли він
	# справді зʼявився, а не однією купою в кінці ходу.
	var u: Unit = state.add_unit(3, 0, Vector2i(0, 5), 2)
	state.add_unit(0, 1, Vector2i(5, 5), 6)
	state.start()

	var events: Array = MoveCommand.create(u.id, Vector2i(6, 5), -1).apply(state)

	var enemy_tile_at: int = _index_of_tile_revealed(events, 0, Vector2i(5, 5))
	var later_tile_at: int = _index_of_tile_revealed(events, 0, Vector2i(7, 5))
	assert_true(enemy_tile_at >= 0, "тайл ворога розкрито цим рухом")
	assert_true(later_tile_at >= 0, "передумова: (7,5) видно лише з кінцевої (4,5)")
	assert_true(enemy_tile_at < later_tile_at,
		"туман другого кроку мусить прийти раніше за туман четвертого (%d проти %d)"
			% [enemy_tile_at, later_tile_at])
	assert_true(state.vision[0].is_visible(Vector2i(5, 5)), "і в стані ворог теж видимий")

func test_a_unit_killed_by_a_mine_stops_contributing_vision() -> void:
	# Пришпилює те, що відхилений фінд рев'ю намагався б "полагодити" —
	# обгорнути виклики видимості/розкриття міни в if u.is_alive(): це саме
	# та зміна, яку не можна вносити, бо вона лишає видимість мертвого юніта
	# на дошці. refresh_vision() після смерті — обов'язковий виклик, не зайвий.
	var u: Unit = state.add_unit(0, 0, Vector2i(0, 5), 2)   # піхота, vision 5
	u.hp = 90   # гарантована смерть: міна тепер завдає 90 + rand(0, 90), капується по hp юніта
	state.refresh_vision(0)
	assert_true(state.vision[0].is_visible(Vector2i(5, 5)),
		"передумова: юніт бачить (5,5) з (0,5) — vision 5, dist_sq точно на межі")
	Mines.place(state, Vector2i(1, 5), 1)
	MoveCommand.create(u.id, Vector2i(3, 5), -1).apply(state)
	assert_false(u.is_alive(), "передумова: міна гарантовано вбиває при hp <= 90")
	assert_false(state.vision[0].is_visible(Vector2i(5, 5)),
		"мертвий юніт не має продовжувати світити видимість")
