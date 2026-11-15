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


## Ставить HP і записує тіла, як після влучання.
func _hit(u: Unit, hp: int) -> Array[Events.BattleEvent]:
	var before: int = u.hp
	u.hp = hp
	return Casualties.record(state, u, before)


## Фігура падає, щойно втрачено її чверть: ceil(4 · hp / max_hp).
func test_figures_follow_hp_by_quarters() -> void:
	var cases: Dictionary = {100: 4, 76: 4, 75: 3, 51: 3, 50: 2, 26: 2, 25: 1, 1: 1, 0: 0}
	for hp: int in cases:
		assert_eq(Casualties.figures(hp, 100), cases[hp], "hp %d" % hp)


## Боєць лягає на тайлі, де відділення стояло, і лишається там, коли воно йде далі.
func test_a_fallen_figure_stays_where_the_squad_stood() -> void:
	var sq: Unit = state.add_unit(0, 1, Vector2i(3, 3), 2)
	var ev: Array[Events.BattleEvent] = _hit(sq, 70)
	assert_eq(ev.size(), 1)
	assert_true(ev[0] is Events.FiguresFell)
	assert_eq(state.bodies.size(), 1)
	var b: Casualties.Body = state.bodies[0]
	assert_eq(b.pos, Vector2i(3, 3))
	assert_eq(b.facing, 2)
	assert_eq([b.first, b.count], [3, 1], "лягає останнє місце")
	sq.pos = Vector2i(5, 3)
	sq.facing = 4
	_hit(sq, 40)
	assert_eq(state.bodies[0].pos, Vector2i(3, 3), "перше тіло не рушило з відділенням")
	assert_eq(state.bodies[1].pos, Vector2i(5, 3))
	assert_eq([state.bodies[1].first, state.bodies[1].count, state.bodies[1].facing], [2, 1, 4])
	sq.pos = Vector2i(7, 3)
	_hit(sq, 0)
	assert_eq(_lying(sq.id), Casualties.SQUAD_FIGURES, "без лікування — рівно чотири тіла")
	assert_eq(state.bodies[2].pos, Vector2i(7, 3))
	assert_eq([state.bodies[2].first, state.bodies[2].count], [0, 2])


## Кожна втрачена фігура лишає тіло, і після лікування теж: тіл тоді понад чотири. Влучання без
## нової втрати тіла не кладе.
func test_every_lost_figure_leaves_a_body_also_after_repair() -> void:
	var sq: Unit = state.add_unit(1, 0, Vector2i(2, 2), 0)
	assert_true(_hit(sq, 80).is_empty(), "80 з 100 — усі четверо стоять")
	_hit(sq, 60)
	assert_eq(_lying(sq.id), 1)
	sq.hp = 100  # лікування інженером: фігура знову стоїть, тіло лишається
	_hit(sq, 60)
	assert_eq(_lying(sq.id), 2, "та сама втрата після лікування — нове тіло")
	_hit(sq, 0)
	assert_eq(_lying(sq.id), 5, "тіл понад чотири — їх лишило лікування")
	var seqs: Array = state.bodies.map(func(b: Casualties.Body) -> int: return b.seq)
	assert_eq(seqs, [0, 1, 2], "записи одного юніта розрізняються номером — тіла не лягають одне на одне")


func test_vehicles_and_engineers_leave_no_bodies() -> void:
	for type_id: int in [5, 2, 11]:
		var u: Unit = state.add_unit(type_id, 0, Vector2i(type_id, 8), 0)
		assert_true(_hit(u, 0).is_empty(), "тип %d" % type_id)
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
	assert_eq(_lying(t.id), Casualties.figures(30, 100) - Casualties.figures(t.hp, t.max_hp()))
	assert_eq((events[i_dmg + 1] as Events.FiguresFell).body.pos, Vector2i(5, 4))


## Міна тепер рве будь-кого, хто на неї в'їхав (§3.11), — і відділення лишає тіла.
func test_a_mine_leaves_bodies() -> void:
	Mines.place(state, Vector2i(6, 6), 0)
	var sq: Unit = state.add_unit(0, 1, Vector2i(6, 6), 0)
	Mines.step_on(state, sq)
	assert_eq(_lying(sq.id), Casualties.SQUAD_FIGURES - Casualties.figures(sq.hp, sq.max_hp()))
	assert_gt(_lying(sq.id), 0)


func test_conceding_lays_every_squad_down() -> void:
	var sq: Unit = state.add_unit(0, 0, Vector2i(1, 1), 0)
	_hit(sq, 30)
	ConcedeCommand.create().apply(state)
	assert_eq(_lying(sq.id), Casualties.SQUAD_FIGURES)


## Тіло на прогоні йде в річку разом з ним — і від інженера, і від міни на мосту.
func test_a_demolished_span_takes_its_bodies_into_the_river() -> void:
	state.board.set_kind(Vector2i(4, 4), Terrain.Kind.BRIDGE)
	var sq: Unit = state.add_unit(0, 1, Vector2i(4, 4), 0)
	_hit(sq, 40)
	sq.pos = Vector2i(4, 5)
	var other: Unit = state.add_unit(0, 1, Vector2i(6, 6), 0)
	_hit(other, 40)
	EngineerCommand.demolish_bridge(state, Vector2i(4, 4))
	assert_eq(_lying(sq.id), 0, "тіла з прогону — у річці")
	# номер наступного запису не повторює забраного з мостом
	_hit(sq, 0)
	assert_eq(state.bodies.filter(func(b: Casualties.Body) -> bool: return b.unit_id == sq.id)[0].seq, 0)
	var keep: Unit = state.add_unit(0, 1, Vector2i(9, 9), 0)
	_hit(keep, 60)
	state.board.set_kind(Vector2i(9, 9), Terrain.Kind.BRIDGE)
	keep.pos = Vector2i(9, 10)
	_hit(keep, 40)
	EngineerCommand.demolish_bridge(state, Vector2i(9, 9))
	_hit(keep, 0)
	var seqs: Array = state.bodies.filter(func(b: Casualties.Body) -> bool: return b.unit_id == keep.id).map(func(b: Casualties.Body) -> int: return b.seq)
	assert_eq(seqs, [1, 2], "після мосту — max + 1, а не повтор 1")
	assert_eq(_lying(other.id), 2, "тіла деінде лишаються")
	state.board.set_kind(Vector2i(8, 8), Terrain.Kind.BRIDGE)
	var crossing: Unit = state.add_unit(0, 0, Vector2i(8, 8), 0)
	_hit(crossing, 40)
	Mines.place(state, Vector2i(8, 8), 1)
	Mines.step_on(state, crossing)
	assert_eq(state.board.kind_at(Vector2i(8, 8)), Terrain.Kind.BRIDGE_DESTROYED)
	assert_eq(_lying(crossing.id), 0, "міна на мосту — той самий шлях")


## Показане гравцеві тіло лишається показаним: відділення, що повернулося в свій незнайдений
## будинок на тому самому тайлі, тілом себе не виказує — але й тіла не ховає.
func test_a_shown_body_stays_shown_and_a_hidden_squad_hides_new_ones() -> void:
	state = BattleState.create(Board.create(8, 8, Terrain.GroundState.DRY), 3, 7)
	state.board.set_kind(Vector2i(2, 2), Terrain.Kind.BUILDING)
	state.vision[2].seen[2 * 8 + 2] = 1
	var sq: Unit = state.add_unit(0, 1, Vector2i(2, 2), 0)
	state.refresh_vision(1)
	assert_false(state.can_see_unit(2, sq), "передумова: гравець 2 відділення не знайшов")
	var body: Casualties.Body = (_hit(sq, 60)[0] as Events.FiguresFell).body
	assert_false(body.shown_to(2), "відділення ховається на тому самому тайлі — тіло його виказало б")
	assert_true(body.shown_to(1), "своєму власникові — видно")
	sq.pos = Vector2i(3, 2)
	Casualties.reveal(state, 2)
	assert_true(body.shown_to(2), "відділення пішло — тіло видно")
	sq.pos = Vector2i(2, 2)
	Casualties.reveal(state, 2)
	assert_true(body.shown_to(2), "повернулося в будинок — показане лишається")
	var second: Casualties.Body = (_hit(sq, 30)[0] as Events.FiguresFell).body
	assert_false(second.shown_to(2), "нове тіло при незнайденому відділенні — ні")
	sq.found_by |= 1 << 2
	Casualties.reveal(state, 2)
	assert_true(second.shown_to(2), "знайдене — тіло видно")


## Показ іде разом з оглядом: тіло на нерозвіданому з'являється, щойно тайл розвідано.
func test_refresh_vision_reveals_bodies_on_newly_seen_ground() -> void:
	var sq: Unit = state.add_unit(0, 1, Vector2i(10, 10), 0)
	var body: Casualties.Body = (_hit(sq, 40)[0] as Events.FiguresFell).body
	assert_false(body.shown_to(0))
	state.add_unit(5, 0, Vector2i(9, 10), 0)
	state.refresh_vision(0)
	assert_true(body.shown_to(0))


func _saved() -> Dictionary:
	return JSON.parse_string(JSON.stringify(BattleSerializer.to_dict(state)))


func test_bodies_round_trip_through_a_save() -> void:
	state.add_unit(5, 1, Vector2i(9, 9), 0)
	var sq: Unit = state.add_unit(1, 0, Vector2i(3, 4), 5)
	state.refresh_vision(0)
	_hit(sq, 40)
	var b: BattleState = BattleSerializer.from_dict(_saved())
	assert_not_null(b)
	if b == null:
		return
	assert_eq(b.bodies.size(), 1)
	var body: Casualties.Body = b.bodies[0]
	assert_eq([body.unit_id, body.pos, body.owner, body.type_id, body.facing, body.first, body.count, body.revealed_to, body.seq],
		[sq.id, Vector2i(3, 4), 0, 1, 5, 2, 2, state.bodies[0].revealed_to, 0])
	assert_true(body.shown_to(0))


func test_a_save_without_bodies_loads_with_none() -> void:
	state.add_unit(5, 1, Vector2i(9, 9), 0)
	state.add_unit(0, 0, Vector2i(3, 4), 5)
	var d: Dictionary = _saved()
	d.erase("bodies")
	var b: BattleState = BattleSerializer.from_dict(d)
	assert_not_null(b)
	if b != null:
		assert_true(b.bodies.is_empty())


func test_a_bad_body_is_rejected() -> void:
	state.add_unit(5, 1, Vector2i(9, 9), 0)
	var sq: Unit = state.add_unit(0, 0, Vector2i(3, 4), 5)
	_hit(sq, 40)
	state.board.set_kind(Vector2i(6, 6), Terrain.Kind.WATER)
	state.board.set_kind(Vector2i(7, 6), Terrain.Kind.BRIDGE_DESTROYED)
	var good: Dictionary = _saved()
	for bad: Array in [["type_id", 5], ["type_id", 1], ["owner", 1], ["unit_id", 99], ["count", 3], ["first", 4],
			["x", 12], ["owner", 2], ["facing", 8], ["revealed_to", 4], ["seq", -1]]:
		var d: Dictionary = good.duplicate(true)
		d["bodies"][0][bad[0]] = bad[1]
		assert_null(BattleSerializer.from_dict(d), "%s = %s" % bad)
	for p: Vector2i in [Vector2i(6, 6), Vector2i(7, 6)]:
		var d: Dictionary = good.duplicate(true)
		d["bodies"][0]["x"] = p.x
		d["bodies"][0]["y"] = p.y
		assert_null(BattleSerializer.from_dict(d), "тіло у воді чи на підірваному мосту: %s" % p)
	# понад чотири тіла на юніта — законно (лікування)
	var many: Dictionary = good.duplicate(true)
	for i in 3:
		many["bodies"].append(good["bodies"][0].duplicate())
	assert_not_null(BattleSerializer.from_dict(many), "8 тіл одного юніта")
	assert_not_null(BattleSerializer.from_dict(good), "передумова: справжнє збереження відкривається")


## Розрахунок гармати: знищена гармата (польова, гаубиця) лишає двох бійців; поранена — нікого. Косметика, без HP.
func test_a_destroyed_gun_leaves_its_two_crew() -> void:
	for type_id: int in [9, 10]:
		var gun: Unit = state.add_unit(type_id, 0, Vector2i(type_id, 3), 3)
		assert_true(_hit(gun, gun.max_hp() / 2).is_empty(), "поранена гармата розрахунку не кладе")
		var ev: Array[Events.BattleEvent] = _hit(gun, 0)
		assert_eq(ev.size(), 1, "тип %d" % type_id)
		var body: Casualties.Body = (ev[0] as Events.FiguresFell).body
		assert_eq([body.unit_id, body.pos, body.type_id, body.facing, body.first, body.count],
				[gun.id, Vector2i(type_id, 3), type_id, 3, 0, Casualties.CREW_FIGURES])
		assert_eq(_lying(gun.id), 2)
		assert_true(_hit(gun, 0).is_empty(), "мертву гармату вдруге не кладемо")


## Постріл, що знищує гармату: тіла розрахунку — між шкодою й загибеллю, до уламків.
func test_a_shot_that_kills_a_gun_lays_the_crew_before_the_wreck() -> void:
	var a: Unit = state.add_unit(5, 0, Vector2i(4, 4), 2)
	var gun: Unit = state.add_unit(10, 1, Vector2i(5, 4), 6)
	gun.hp = 10
	state.begin_turn()
	var events: Array = FireCommand.create(a.id, gun.id).apply(state)
	var i_dmg: int = events.find_custom(func(e: Events.BattleEvent) -> bool: return e is Events.DamageDealt)
	assert_true(events[i_dmg + 1] is Events.FiguresFell, "розрахунок — одразу після шкоди")
	assert_true(events[i_dmg + 2] is Events.UnitDestroyed)
	assert_eq(_lying(gun.id), 2)


## Показ тіл розрахунку — за тими самими правилами: лише розвіданий тайл.
func test_crew_bodies_follow_the_reveal_rules_and_a_save() -> void:
	var gun: Unit = state.add_unit(9, 1, Vector2i(10, 10), 2)
	var body: Casualties.Body = (_hit(gun, 0)[0] as Events.FiguresFell).body
	assert_false(body.shown_to(0), "нерозвіданий тайл — тіл не видно")
	state.add_unit(5, 0, Vector2i(9, 10), 0)
	state.refresh_vision(0)
	assert_true(body.shown_to(0), "тайл розвідано — тіла видно")
	var b: BattleState = BattleSerializer.from_dict(_saved())
	assert_not_null(b)
	if b != null:
		assert_eq(b.bodies.size(), 1)
		assert_eq([b.bodies[0].type_id, b.bodies[0].first, b.bodies[0].count, b.bodies[0].revealed_to],
				[9, 0, 2, body.revealed_to])


## Розрахунок гармати лягає разом: двоє з першого місця, інакше збереження відкидається.
func test_a_crew_body_must_be_both_figures_from_the_first_slot() -> void:
	state.add_unit(5, 1, Vector2i(9, 9), 0)
	var gun: Unit = state.add_unit(9, 0, Vector2i(3, 4), 5)
	_hit(gun, 0)
	var good: Dictionary = _saved()
	assert_not_null(BattleSerializer.from_dict(good), "двоє з першого місця — законно")
	for bad: Array in [["count", 1], ["count", 3], ["first", 1], ["first", 2]]:
		var d: Dictionary = good.duplicate(true)
		d["bodies"][0][bad[0]] = bad[1]
		assert_null(BattleSerializer.from_dict(d), "%s = %s" % bad)
