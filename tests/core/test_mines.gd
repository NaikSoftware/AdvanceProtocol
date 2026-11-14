extends GutTest

var state: BattleState

func before_each() -> void:
	state = BattleState.create(Board.create(10, 10, Terrain.GroundState.DRY), 2, 5)

func test_mine_is_visible_only_to_owner() -> void:
	Mines.place(state, Vector2i(5, 5), 0)
	assert_true(Mines.is_known(state, Vector2i(5, 5), 0), "власник свої міни бачить")
	assert_false(Mines.is_known(state, Vector2i(5, 5), 1), "§3.11: для решти вона невидима")

func test_an_engineer_passing_near_reveals_the_mine_for_that_player_only() -> void:
	# Інженера тут не «підсунуто, щоб тест проходив»: до §3.11 розкривав будь-який
	# юніт, і в цій ролі стояло стрілецьке відділення (тип 0). Тепер шукати вміє
	# лише інженер, тож юніт замінено на тип 11 — сама перевірка (розкриття ведеться
	# на гравця, а не глобально) лишилась тою самою.
	state = BattleState.create(Board.create(10, 10, Terrain.GroundState.DRY), 3, 5)
	Mines.place(state, Vector2i(5, 5), 0)
	state.add_unit(11, 1, Vector2i(5, 6), 0)
	Mines.reveal_near(state, 1)
	assert_true(Mines.is_known(state, Vector2i(5, 5), 1))
	assert_false(Mines.is_known(state, Vector2i(5, 5), 2), "розкриття — на гравця, як і туман")

func test_only_an_engineer_finds_an_enemy_mine() -> void:
	# §3.11: без інженера попереду колона заходить у мінне поле наосліп. Стрілецьке
	# відділення стоїть УПРИТУЛ до міни й однаково її не бачить — попри те, що його
	# огляд (5) накриває тайл із запасом. Шукає клас, а не відстань.
	Mines.place(state, Vector2i(5, 5), 0)
	state.add_unit(0, 1, Vector2i(5, 6), 0)     # стрілецьке відділення, сусідній тайл
	state.add_unit(5, 1, Vector2i(4, 5), 0)     # середній танк, теж поруч
	Mines.reveal_near(state, 1)
	assert_false(Mines.is_known(state, Vector2i(5, 5), 1),
		"§3.11: чужу міну знаходить лише інженер")

func test_an_engineer_finds_a_mine_across_its_whole_vision() -> void:
	# §3.11: радіус — власний огляд інженера (3), а не один тайл, і міряється
	# ромбом. Три тайли — усередині; чотири — уже ні.
	Mines.place(state, Vector2i(5, 5), 0)
	var eng: Unit = state.add_unit(11, 1, Vector2i(5, 9), 0)   # |0|+|4| = 4 — задалеко
	Mines.reveal_near(state, 1)
	assert_false(Mines.is_known(state, Vector2i(5, 5), 1), "4 тайли — поза оглядом інженера")
	eng.pos = Vector2i(5, 8)                                   # |0|+|3| = 3 — рівно на межі
	Mines.reveal_near(state, 1)
	assert_true(Mines.is_known(state, Vector2i(5, 5), 1), "3 тайли — інженер бачить")

func test_engineer_search_uses_the_diamond_not_the_circle() -> void:
	# §3.11 через §3.1: (2, 2) від міни — це 2+2 = 4 > 3 поза ромбом, хоча
	# dist_sq 8 <= 9 і коло радіуса 3 цей тайл накрило б.
	Mines.place(state, Vector2i(5, 5), 0)
	assert_true(Rules.in_radius(Vector2i(7, 7), Vector2i(5, 5), 3), "передумова: у колі радіуса 3")
	var eng: Unit = state.add_unit(11, 1, Vector2i(7, 7), 0)
	Mines.reveal_near(state, 1)
	assert_false(Mines.is_known(state, Vector2i(5, 5), 1), "огляд — ромб, не коло")

	# Друга половина тримає ромб з протилежного боку: сам по собі assert_false вище
	# однаково істинний і для радіуса 1 (пошук до §3.11), тобто нічого не фіксує.
	# (7, 5) — два кроки по осі: усередині ромба 3 і поза колом радіуса 1.
	eng.pos = Vector2i(7, 5)
	Mines.reveal_near(state, 1)
	assert_true(Mines.is_known(state, Vector2i(5, 5), 1),
		"§3.11: радіус пошуку — власний огляд інженера (3), а не один тайл")

func _count_mine_revealed(events: Array) -> int:
	var n: int = 0
	for e in events:
		if e is Events.MineRevealed:
			n += 1
	return n

func test_a_stationary_engineer_searches_at_the_start_of_its_owners_turn() -> void:
	# §3.11: пошук — властивість присутності, а не руху. Доки єдиним викликачем
	# Mines.reveal_near() був MoveCommand, інженер, який нікуди не пішов, не знаходив
	# нічого — ворожа міна за три тайли від нього, всередині його ж ромба огляду,
	# лишалася невидимою весь матч. Інженер тут навмисно НЕ рухається.
	Mines.place(state, Vector2i(5, 8), 1)
	state.add_unit(11, 0, Vector2i(5, 5), 0)   # інженер, огляд 3: |0| + |3| = 3, рівно на межі
	state.active_player = 0
	var events: Array = state.begin_turn()
	assert_true(Mines.is_known(state, Vector2i(5, 8), 0),
		"§3.11: інженер шукає на початку свого ходу, навіть не зрушивши з місця")

	var tile_at: int = -1
	var mine_at: int = -1
	for i in events.size():
		var e: Variant = events[i]
		if tile_at < 0 and e is Events.TileRevealed and e.player == 0 and Vector2i(5, 8) in e.tiles:
			tile_at = i
		if mine_at < 0 and e is Events.MineRevealed and e.pos == Vector2i(5, 8):
			mine_at = i
	assert_true(tile_at >= 0, "передумова: тайл міни розкрито цим же початком ходу")
	assert_true(mine_at >= 0, "початок ходу мусить випустити MineRevealed")
	assert_true(tile_at < mine_at,
		"MineRevealed не має випереджати TileRevealed свого тайла (%d проти %d)" % [mine_at, tile_at])

	assert_eq(_count_mine_revealed(state.begin_turn()), 0,
		"уже відома міна не породжує події вдруге")

func test_the_start_of_turn_sweep_searches_only_for_the_active_player() -> void:
	# §3.11 через §3.5: розкриття ведеться на гравця, як і туман. Інженер гравця 0
	# стоїть упритул до міни, але хід іде гравця 1 — не має розкритись нікому:
	# ні тому, чий хід не йде, ні тому, у кого інженера немає взагалі.
	state = BattleState.create(Board.create(10, 10, Terrain.GroundState.DRY), 3, 5)
	Mines.place(state, Vector2i(5, 8), 2)
	state.add_unit(11, 0, Vector2i(5, 5), 0)   # інженер гравця 0
	state.add_unit(0, 1, Vector2i(1, 1), 0)    # у гравця 1 — саме піхота, не інженер
	state.active_player = 1
	var events: Array = state.begin_turn()
	assert_false(Mines.is_known(state, Vector2i(5, 8), 0),
		"за гравця, чий хід не йде, ніхто не шукає")
	assert_false(Mines.is_known(state, Vector2i(5, 8), 1),
		"чужий інженер не шукає за тебе")
	assert_eq(_count_mine_revealed(events), 0)

func test_driving_onto_an_unknown_mine_detonates_it() -> void:
	Mines.place(state, Vector2i(5, 5), 0)
	var u: Unit = state.add_unit(5, 1, Vector2i(5, 5), 0)
	var before: int = u.hp
	var events: Array = Mines.step_on(state, u)
	assert_true(u.hp < before)
	assert_null(Mines.mine_at(state, Vector2i(5, 5)), "міна одноразова")
	var triggered: bool = false
	for e in events:
		if e is Events.MineTriggered:
			triggered = true
	assert_true(triggered)

## §3.11: міна рве того, хто на неї в'їхав, хоч би чия вона була. Стояти на міні не
## може ніхто, і власник теж.
func test_an_own_mine_detonates_under_its_owner() -> void:
	Mines.place(state, Vector2i(5, 5), 0)
	var u: Unit = state.add_unit(5, 0, Vector2i(5, 5), 0)
	var before: int = u.hp
	var events: Array = Mines.step_on(state, u)
	assert_true(u.hp < before, "своя міна рве й свого")
	assert_null(Mines.mine_at(state, Vector2i(5, 5)), "міна одноразова")
	assert_true(events.size() > 0 and events[0] is Events.MineTriggered)

func test_in_three_players_a_mine_detonates_under_any_other_player() -> void:
	state = BattleState.create(Board.create(10, 10, Terrain.GroundState.DRY), 3, 5)
	Mines.place(state, Vector2i(5, 5), 2)
	Mines.place(state, Vector2i(7, 7), 2)
	var u: Unit = state.add_unit(5, 1, Vector2i(5, 5), 0)
	var before: int = u.hp
	Mines.step_on(state, u)
	assert_true(u.hp < before)
	assert_null(Mines.mine_at(state, Vector2i(5, 5)))
	var other: Mines.Mine = Mines.mine_at(state, Vector2i(7, 7))
	assert_eq(other.known_to, [false, false, true] as Array[bool], "інші міни своїх знань не міняють")

func _bridge_with_mine(pos: Vector2i, owner: int) -> void:
	state.board.set_kind(pos, Terrain.Kind.BRIDGE)
	Mines.place(state, pos, owner)

func _has(events: Array, cls: Variant) -> bool:
	for e in events:
		if is_instance_of(e, cls):
			return true
	return false

## Міна на мосту підриває міст разом із тим, хто на нього в'їхав: тайл стає
## BRIDGE_DESTROYED тим самим шляхом, що й від підриву інженером, і юніт іде в річку
## без уламків.
func test_a_mine_on_a_bridge_destroys_the_bridge_and_the_unit() -> void:
	_bridge_with_mine(Vector2i(5, 5), 0)
	state.add_unit(0, 1, Vector2i(9, 9), 0)
	var u: Unit = state.add_unit(5, 1, Vector2i(5, 5), 0)
	var events: Array = Mines.step_on(state, u)
	assert_eq(state.board.kind_at(Vector2i(5, 5)), Terrain.Kind.BRIDGE_DESTROYED)
	assert_false(u.is_alive(), "юніт іде в річку разом із мостом")
	assert_null(Mines.mine_at(state, Vector2i(5, 5)))
	assert_true(events[0] is Events.MineTriggered, "спершу вибух, потім міст")
	assert_true(_has(events, Events.BridgeChanged))
	assert_true(_has(events, Events.UnitDestroyed))
	assert_false(_has(events, Events.WreckLeft), "техніка в річці уламків не лишає")
	assert_eq(state.wrecks.size(), 0)

func test_a_mined_bridge_takes_a_wreck_on_it_along() -> void:
	_bridge_with_mine(Vector2i(5, 5), 0)
	state.wrecks.append(Wrecks.Wreck.new(Vector2i(5, 5), 5, 0, 99, 1))
	state.add_unit(0, 1, Vector2i(9, 9), 0)
	var u: Unit = state.add_unit(0, 1, Vector2i(5, 5), 0)   # піхота стоїть і на уламках
	var events: Array = Mines.step_on(state, u)
	assert_null(Wrecks.wreck_at(state, Vector2i(5, 5)), "уламки падають у річку з мостом")
	assert_true(_has(events, Events.WreckRemoved))

func test_clearing_removes_the_mine() -> void:
	Mines.place(state, Vector2i(5, 5), 0)
	Mines.clear(state, Vector2i(5, 5))
	assert_null(Mines.mine_at(state, Vector2i(5, 5)))

func test_mine_can_kill_and_end_the_match() -> void:
	Mines.place(state, Vector2i(5, 5), 0)
	state.add_unit(0, 0, Vector2i(1, 1), 0)
	var u: Unit = state.add_unit(2, 1, Vector2i(5, 5), 0)
	u.hp = 10
	var events: Array = Mines.step_on(state, u)
	assert_false(u.is_alive())
	var ended: bool = false
	for e in events:
		if e is Events.MatchEnded:
			ended = true
	assert_true(ended)
