extends GutTest
## Тіла бійців (Casualties): косметика в стані, правила їх не читають.

var state: BattleState


func before_each() -> void:
	state = BattleState.create(Board.create(12, 12, Terrain.GroundState.DRY), 2, 7)
	state.active_player = 0


func _lying(unit_id: int) -> int:
	var n: int = 0
	for b in state.bodies:
		if b.unit_id == unit_id:
			n += b.count
	return n


## Фігура падає, щойно втрачено її чверть: ceil(4 · hp / max_hp).
func test_figures_follow_hp_by_quarters() -> void:
	var cases: Dictionary = {100: 4, 76: 4, 75: 3, 51: 3, 50: 2, 26: 2, 25: 1, 1: 1, 0: 0}
	for hp: int in cases:
		assert_eq(Casualties.figures(hp, 100), cases[hp], "hp %d" % hp)


## Боєць лягає на тайлі, де відділення стояло, і лишається там, коли воно йде далі.
func test_a_fallen_figure_stays_where_the_squad_stood() -> void:
	var sq: Unit = state.add_unit(0, 1, Vector2i(3, 3), 2)
	sq.hp = 70
	var ev: Array[Events.BattleEvent] = Casualties.record(state, sq)
	assert_eq(ev.size(), 1)
	assert_true(ev[0] is Events.FiguresFell)
	assert_eq(state.bodies.size(), 1)
	var b: Casualties.Body = state.bodies[0]
	assert_eq(b.pos, Vector2i(3, 3))
	assert_eq(b.facing, 2)
	assert_eq([b.first, b.count], [3, 1], "лягає останнє місце")
	sq.pos = Vector2i(5, 3)
	sq.facing = 4
	sq.hp = 40
	Casualties.record(state, sq)
	assert_eq(state.bodies[0].pos, Vector2i(3, 3), "перше тіло не рушило з відділенням")
	assert_eq(state.bodies[1].pos, Vector2i(5, 3))
	assert_eq([state.bodies[1].first, state.bodies[1].count, state.bodies[1].facing], [2, 1, 4])
	sq.pos = Vector2i(7, 3)
	sq.hp = 0
	Casualties.record(state, sq)
	assert_eq(_lying(sq.id), Casualties.SQUAD_FIGURES, "у знищеного відділення рівно чотири тіла")
	assert_eq(state.bodies[2].pos, Vector2i(7, 3))
	assert_eq([state.bodies[2].first, state.bodies[2].count], [0, 2])


## Без нової втрати — без нового тіла; лікування фігуру ставить, а тіло лишає, і нові тіла
## лягають лише понад ті, що вже лежать.
func test_no_body_without_a_new_loss_and_none_twice_after_repair() -> void:
	var sq: Unit = state.add_unit(1, 0, Vector2i(2, 2), 0)
	sq.hp = 80
	assert_true(Casualties.record(state, sq).is_empty(), "80 з 100 — усі четверо стоять")
	sq.hp = 60
	Casualties.record(state, sq)
	sq.hp = 100
	assert_true(Casualties.record(state, sq).is_empty())
	sq.hp = 60
	assert_true(Casualties.record(state, sq).is_empty(), "та сама втрата вдруге — тіло вже лежить")
	sq.hp = 0
	Casualties.record(state, sq)
	assert_eq(_lying(sq.id), Casualties.SQUAD_FIGURES)


func test_vehicles_and_engineers_leave_no_bodies() -> void:
	for type_id: int in [5, 2, 9, 11]:
		var u: Unit = state.add_unit(type_id, 0, Vector2i(type_id, 8), 0)
		u.hp = 0
		assert_true(Casualties.record(state, u).is_empty(), "тип %d" % type_id)
	assert_true(state.bodies.is_empty())


## Постріл, що скидає фігуру, кладе тіло в стан і віддає подію одразу після шкоди.
func test_a_shot_leaves_the_body_in_state_and_in_events() -> void:
	var a: Unit = state.add_unit(5, 0, Vector2i(4, 4), 2)
	var t: Unit = state.add_unit(0, 1, Vector2i(5, 4), 6)
	# 30 HP: найменша шкода (10) однаково переходить межу чверті
	t.hp = 30
	state.begin_turn()
	var events: Array = FireCommand.create(a.id, t.id).apply(state)
	var i_dmg: int = events.find_custom(func(e: Events.BattleEvent) -> bool: return e is Events.DamageDealt)
	assert_true(events[i_dmg + 1] is Events.FiguresFell, "тіло — одразу після шкоди")
	assert_eq(_lying(t.id), Casualties.SQUAD_FIGURES - Casualties.figures(t.hp, t.max_hp()))
	assert_eq((events[i_dmg + 1] as Events.FiguresFell).body.pos, Vector2i(5, 4))


func test_a_mine_leaves_bodies() -> void:
	Mines.place(state, Vector2i(6, 6), 0)
	var sq: Unit = state.add_unit(0, 1, Vector2i(6, 6), 0)
	Mines.step_on(state, sq)
	assert_eq(_lying(sq.id), Casualties.SQUAD_FIGURES - Casualties.figures(sq.hp, sq.max_hp()))
	assert_gt(_lying(sq.id), 0)


func test_conceding_lays_every_squad_down() -> void:
	var sq: Unit = state.add_unit(0, 0, Vector2i(1, 1), 0)
	sq.hp = 30
	Casualties.record(state, sq)
	ConcedeCommand.create().apply(state)
	assert_eq(_lying(sq.id), Casualties.SQUAD_FIGURES)


func test_bodies_round_trip_through_a_save() -> void:
	state.add_unit(5, 1, Vector2i(9, 9), 0)
	var sq: Unit = state.add_unit(1, 0, Vector2i(3, 4), 5)
	sq.hp = 40
	Casualties.record(state, sq)
	var d: Dictionary = JSON.parse_string(JSON.stringify(BattleSerializer.to_dict(state)))
	var b: BattleState = BattleSerializer.from_dict(d)
	assert_not_null(b)
	if b == null:
		return
	assert_eq(b.bodies.size(), 1)
	var body: Casualties.Body = b.bodies[0]
	assert_eq([body.unit_id, body.pos, body.owner, body.type_id, body.facing, body.first, body.count],
		[sq.id, Vector2i(3, 4), 0, 1, 5, 2, 2])


func test_a_save_without_bodies_loads_with_none() -> void:
	state.add_unit(5, 1, Vector2i(9, 9), 0)
	state.add_unit(0, 0, Vector2i(3, 4), 5)
	var d: Dictionary = JSON.parse_string(JSON.stringify(BattleSerializer.to_dict(state)))
	d.erase("bodies")
	var b: BattleState = BattleSerializer.from_dict(d)
	assert_not_null(b)
	if b != null:
		assert_true(b.bodies.is_empty())


func test_a_bad_body_is_rejected() -> void:
	state.add_unit(5, 1, Vector2i(9, 9), 0)
	var sq: Unit = state.add_unit(0, 0, Vector2i(3, 4), 5)
	sq.hp = 40
	Casualties.record(state, sq)
	var good: Dictionary = JSON.parse_string(JSON.stringify(BattleSerializer.to_dict(state)))
	for bad: Array in [["type_id", 5], ["count", 3], ["first", 4], ["x", 12], ["owner", 2], ["facing", 8]]:
		var d: Dictionary = good.duplicate(true)
		d["bodies"][0][bad[0]] = bad[1]
		assert_null(BattleSerializer.from_dict(d), "%s = %s" % bad)
	assert_not_null(BattleSerializer.from_dict(good), "передумова: справжнє збереження відкривається")
