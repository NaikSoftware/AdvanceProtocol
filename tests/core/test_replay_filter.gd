extends GutTest
## Фільтр повтору: глядач бачить лише те, що його бік бачив би наживо, і все, що влучило
## в його власне. Туман у тестах виставляється явно (seen глядача), щоб випадок не залежав
## від ромбів огляду. Типи: 0 — стрілецьке відділення (30 AP), 2 — бронеавтомобіль (68 AP,
## дорога 10), 5 — середній танк (дальність 4), 11 — інженерна машина.

const W: int = 24
const H: int = 14
const ROAD_Y: int = 7

var journal: ReplayLog


func before_each() -> void:
	journal = ReplayLog.new()


func _state(players: int = 2) -> BattleState:
	var b: Board = Board.create(W, H, Terrain.GroundState.DRY)
	for x in W:
		b.set_kind(Vector2i(x, ROAD_Y), Terrain.Kind.ROAD)
	var s: BattleState = BattleState.create(b, players, 7)
	return s


## Якір глядача: живий юніт далеко від подій, щоб глядач не вибув.
func _anchor(s: BattleState, owner: int = 0) -> Unit:
	return s.add_unit(5, owner, Vector2i(0, 0), 0)


## Глядач 0 бачить рівно ці тайли (крім тих, що світить якір).
func _see(s: BattleState, tiles: Array[Vector2i]) -> void:
	s.vision[0].seen.fill(0)
	for t in tiles:
		s.vision[0].reveal(t)


func _cols(x0: int, x1: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for x in range(x0, x1 + 1):
		for y in H:
			out.append(Vector2i(x, y))
	return out


## Хід 0 → знімок глядача перед його кінцем ходу → хід переходить далі.
func _open(s: BattleState, seen: Array[Vector2i]) -> void:
	s.start()
	s.active_player = 0
	s.begin_turn()
	_see(s, seen)
	journal.mark(0, s)
	_play(s, EndTurnCommand.create())


func _play(s: BattleState, c: Command) -> void:
	assert_eq(c.validate(s), "", "команда мусить бути дозволена")
	c.apply(s)
	journal.record(c)


func _end(s: BattleState) -> void:
	_play(s, EndTurnCommand.create())


func _build() -> ReplayFilter.Result:
	var r: ReplayFilter.Result = ReplayFilter.build(journal, 0)
	if r != null:
		_check_no_leak(r, 0)
	return r


func _all(r: ReplayFilter.Result) -> Array[Events.BattleEvent]:
	var out: Array[Events.BattleEvent] = []
	for b in r.beats:
		out.append_array(b.events)
	return out


func _of(events: Array[Events.BattleEvent], unit_id: int) -> Array[Events.BattleEvent]:
	var out: Array[Events.BattleEvent] = []
	for e in events:
		if _unit_of(e) == unit_id:
			out.append(e)
	return out


func _unit_of(e: Events.BattleEvent) -> int:
	for k in ["unit_id"]:
		if k in e:
			return e.get(k)
	return -1


func _has(events: Array[Events.BattleEvent], type: Variant) -> bool:
	return events.any(func(e: Events.BattleEvent) -> bool: return is_instance_of(e, type))


## Спільна перевірка на витік для КОЖНОГО результату: заборонені типи, чужі TileRevealed
## і UnitFound, кадр камери поза розвіданим, і події про юніти, яких на екрані немає.
func _check_no_leak(r: ReplayFilter.Result, viewer: int) -> void:
	var on: Dictionary = {}
	for id in r.start.units:
		var u: Unit = r.start.units[id]
		if u.is_alive() and r.start.can_see_unit(viewer, u):
			on[id] = true
	assert_eq_deep(r.on_screen_start, on)
	for b in r.beats:
		assert_false(b.events.is_empty(), "порожній такт")
		var blast_at: Array[Vector2i] = []
		for e in b.events:
			assert_false(e is Events.ApChanged or e is Events.MinePlaced or e is Events.MineRevealed
					or e is Events.TurnStarted or e is Events.TurnEnded or e is Events.PlayerEliminated
					or e is Events.MatchEnded, "заборонена подія: " + e.describe())
			if e is Events.TileRevealed:
				assert_eq(e.player, viewer, "чужий TileRevealed")
			elif e is Events.UnitFound:
				assert_eq(e.player, viewer, "чужий UnitFound")
			elif e is Events.MineTriggered:
				blast_at.append(e.pos)
			if e is ReplayFilter.Appeared:
				assert_false(on.has(e.unit_id), "Appeared юніта, що вже на екрані")
				on[e.unit_id] = true
			elif e is ReplayFilter.Vanished:
				assert_true(on.has(e.unit_id), "Vanished юніта, якого на екрані немає")
				on.erase(e.unit_id)
			elif e is Events.ShotFired or e is Events.ShotRetaliated or e is Events.DroneLaunched:
				assert_true(on.has(e.attacker_id) or on.has(e.target_id), "постріл між невидимими")
			elif e is Events.UnitMoved or e is Events.UnitTurned or e is Events.MoveBlocked \
					or e is Events.DamageDealt or e is Events.UnitDestroyed or e is Events.UnitRepaired:
				assert_true(on.has(e.unit_id), "подія про юніт поза екраном: " + e.describe())
				if e is Events.UnitDestroyed:
					on.erase(e.unit_id)
		assert_true(b.after.vision[viewer].is_seen(b.focus) or blast_at.has(b.focus),
				"кадр у тумані: %s" % b.focus)
		assert_eq_deep(b.on_screen, on)


# --- рух ---------------------------------------------------------------------------

func test_move_on_seen_ground_is_shown_whole() -> void:
	var s: BattleState = _state()
	_anchor(s)
	var car: Unit = s.add_unit(2, 1, Vector2i(12, ROAD_Y), 6)
	_open(s, _cols(0, W - 1))
	_play(s, MoveCommand.create(car.id, Vector2i(8, ROAD_Y)))
	_end(s)
	var r: ReplayFilter.Result = _build()
	assert_not_null(r)
	assert_eq(r.beats.size(), 1)
	var ev: Array[Events.BattleEvent] = r.beats[0].events
	assert_eq(ev.size(), 1, "лише рух: AP і огляд противника не показуються")
	assert_true(ev[0] is Events.UnitMoved)
	assert_eq(ev[0].path, [Vector2i(11, 7), Vector2i(10, 7), Vector2i(9, 7), Vector2i(8, 7)] as Array[Vector2i])
	assert_eq(r.beats[0].focus, Vector2i(12, ROAD_Y), "камера — звідки рух почався")
	assert_eq(r.beats[0].actor, 1)
	assert_eq(r.beats[0].turn, 1)


func test_move_from_fog_appears_at_the_fog_edge() -> void:
	var s: BattleState = _state()
	_anchor(s)
	var car: Unit = s.add_unit(2, 1, Vector2i(12, ROAD_Y), 6)
	_open(s, _cols(0, 9))
	_play(s, MoveCommand.create(car.id, Vector2i(8, ROAD_Y)))
	_end(s)
	var r: ReplayFilter.Result = _build()
	assert_not_null(r)
	var ev: Array[Events.BattleEvent] = r.beats[0].events
	assert_eq(ev.size(), 2)
	assert_true(ev[0] is ReplayFilter.Appeared)
	assert_eq(ev[0].unit_id, car.id)
	assert_eq(ev[0].pos, Vector2i(9, ROAD_Y), "з'являється на першому розвіданому тайлі")
	assert_eq(ev[0].facing, Board.facing_towards(Vector2i(10, 7), Vector2i(9, 7)))
	assert_true(ev[1] is Events.UnitMoved)
	assert_eq(ev[1].path, [Vector2i(8, 7)] as Array[Vector2i], "шлях — без тайла появи")
	assert_eq(r.beats[0].focus, Vector2i(9, ROAD_Y))


func test_move_into_fog_vanishes_at_the_edge() -> void:
	var s: BattleState = _state()
	_anchor(s)
	var car: Unit = s.add_unit(2, 1, Vector2i(12, ROAD_Y), 6)
	_open(s, _cols(10, W - 1))
	_play(s, MoveCommand.create(car.id, Vector2i(8, ROAD_Y)))
	_end(s)
	var r: ReplayFilter.Result = _build()
	assert_not_null(r)
	var ev: Array[Events.BattleEvent] = r.beats[0].events
	assert_eq(ev.size(), 2)
	assert_true(ev[0] is Events.UnitMoved)
	assert_eq(ev[0].path, [Vector2i(11, 7), Vector2i(10, 7)] as Array[Vector2i])
	assert_eq(ev[0].facing, Board.facing_towards(Vector2i(11, 7), Vector2i(10, 7)))
	assert_true(ev[1] is ReplayFilter.Vanished)
	assert_eq(ev[1].unit_id, car.id)


func test_move_entirely_in_fog_makes_no_beat() -> void:
	var s: BattleState = _state()
	_anchor(s)
	var hidden: Unit = s.add_unit(2, 1, Vector2i(12, ROAD_Y), 6)
	var shown: Unit = s.add_unit(2, 1, Vector2i(4, 3), 6)
	_open(s, _cols(0, 6))
	_play(s, MoveCommand.create(hidden.id, Vector2i(8, ROAD_Y)))
	_play(s, MoveCommand.create(shown.id, Vector2i(3, 3)))
	_end(s)
	var r: ReplayFilter.Result = _build()
	assert_not_null(r)
	assert_eq(r.beats.size(), 1, "хід у тумані не дає такту")
	assert_eq(_of(_all(r), hidden.id).size(), 0)
	assert_eq(r.beats[0].events[0].unit_id, shown.id)


## Обрив показує тайл, у який не в'їхали: на нерозвіданих уламках він доніс би, що там є.
func test_move_blocked_shows_only_when_the_viewer_knows_the_blocker() -> void:
	for seen_from in [9, 8]:
		before_each()
		var s: BattleState = _state()
		_anchor(s)
		s.wrecks.append(Wrecks.Wreck.new(Vector2i(8, ROAD_Y), 2, 0, 99, 0))
		var car: Unit = s.add_unit(2, 1, Vector2i(12, ROAD_Y), 6)
		_open(s, _cols(seen_from, W - 1))
		_play(s, MoveCommand.create(car.id, Vector2i(6, ROAD_Y)))
		_end(s)
		var r: ReplayFilter.Result = _build()
		assert_not_null(r)
		var ev: Array[Events.BattleEvent] = r.beats[0].events
		assert_eq(ev[0].path, [Vector2i(11, 7), Vector2i(10, 7), Vector2i(9, 7)] as Array[Vector2i])
		assert_eq(_has(ev, Events.MoveBlocked), seen_from == 8, "уламки на (8,7) розвідано: %s" % (seen_from == 8))


# --- укриття -------------------------------------------------------------------------

func test_squad_ending_hidden_in_building_shows_no_move_even_over_two_commands() -> void:
	var s: BattleState = _state()
	_anchor(s)
	s.board.set_kind(Vector2i(12, 6), Terrain.Kind.BUILDING)
	var squad: Unit = s.add_unit(0, 1, Vector2i(12, 3), 4)
	_open(s, _cols(0, W - 1))
	_play(s, MoveCommand.create(squad.id, Vector2i(12, 4)))
	_play(s, MoveCommand.create(squad.id, Vector2i(12, 6)))
	_end(s)
	var r: ReplayFilter.Result = _build()
	assert_not_null(r)
	assert_eq(r.beats.size(), 1, "лише зникнення на першому ході")
	var ev: Array[Events.BattleEvent] = r.beats[0].events
	assert_eq(ev.size(), 1)
	assert_true(ev[0] is ReplayFilter.Vanished)
	assert_eq(ev[0].unit_id, squad.id)
	assert_eq(r.beats[0].focus, Vector2i(12, 3), "зникає там, де стояв на початку")


func test_squad_crossing_a_building_is_hidden_only_inside() -> void:
	var s: BattleState = _state()
	_anchor(s)
	s.board.set_kind(Vector2i(12, 4), Terrain.Kind.BUILDING)
	var squad: Unit = s.add_unit(0, 1, Vector2i(12, 3), 4)
	_open(s, _cols(0, W - 1))
	_play(s, MoveCommand.create(squad.id, Vector2i(12, 6)))
	_end(s)
	var r: ReplayFilter.Result = _build()
	assert_not_null(r)
	var ev: Array[Events.BattleEvent] = r.beats[0].events
	assert_eq(ev.size(), 3)
	assert_true(ev[0] is ReplayFilter.Vanished, "входить у будинок — зникає")
	assert_true(ev[1] is ReplayFilter.Appeared, "виходить — знову видно")
	assert_eq(ev[1].pos, Vector2i(12, 5))
	assert_true(ev[2] is Events.UnitMoved)
	assert_eq(ev[2].path, [Vector2i(12, 6)] as Array[Vector2i])


func test_squad_found_in_building_on_its_way_stays_visible() -> void:
	var s: BattleState = _state()
	_anchor(s)
	s.board.set_kind(Vector2i(12, 4), Terrain.Kind.BUILDING)
	s.add_unit(2, 0, Vector2i(13, 4), 0)
	var squad: Unit = s.add_unit(0, 1, Vector2i(12, 3), 4)
	_open(s, _cols(0, W - 1))
	_play(s, MoveCommand.create(squad.id, Vector2i(12, 6)))
	_end(s)
	var r: ReplayFilter.Result = _build()
	assert_not_null(r)
	var ev: Array[Events.BattleEvent] = r.beats[0].events
	assert_true(ev[0] is Events.UnitMoved, "знайдений сусідом — видно весь шлях")
	assert_eq(ev[0].path.size(), 3)
	var found: Array[Events.BattleEvent] = ev.filter(func(e: Events.BattleEvent) -> bool: return e is Events.UnitFound)
	assert_eq(found.size(), 1)
	assert_eq(found[0].at_step, 0)


func test_squad_leaving_cover_later_in_span_is_shown_from_that_move() -> void:
	var s: BattleState = _state()
	_anchor(s)
	s.board.set_kind(Vector2i(12, 4), Terrain.Kind.BUILDING)
	var squad: Unit = s.add_unit(0, 1, Vector2i(12, 3), 4)
	_open(s, _cols(0, W - 1))
	_play(s, MoveCommand.create(squad.id, Vector2i(12, 4)))
	_play(s, MoveCommand.create(squad.id, Vector2i(12, 6)))
	_end(s)
	var r: ReplayFilter.Result = _build()
	assert_not_null(r)
	assert_eq(r.beats.size(), 2)
	assert_eq(r.beats[0].events.size(), 1)
	assert_true(r.beats[0].events[0] is ReplayFilter.Vanished)
	var ev: Array[Events.BattleEvent] = r.beats[1].events
	assert_true(ev[0] is ReplayFilter.Appeared)
	assert_eq(ev[0].pos, Vector2i(12, 5), "з'являється на виході, не в будинку")
	assert_true(ev[1] is Events.UnitMoved)
	assert_eq(ev[1].path, [Vector2i(12, 6)] as Array[Vector2i])


func test_squad_turning_before_it_hides_is_not_shown_mid_route() -> void:
	var s: BattleState = _state()
	_anchor(s)
	s.board.set_kind(Vector2i(12, 6), Terrain.Kind.BUILDING)
	var squad: Unit = s.add_unit(0, 1, Vector2i(12, 3), 4)
	_open(s, _cols(0, W - 1))
	_play(s, MoveCommand.create(squad.id, Vector2i(12, 4)))
	_play(s, TurnCommand.create(squad.id, Vector2i(14, 4)))
	_play(s, MoveCommand.create(squad.id, Vector2i(12, 6)))
	_end(s)
	var r: ReplayFilter.Result = _build()
	assert_not_null(r)
	assert_eq(r.beats.size(), 1, "поворот посеред прихованого маршруту не показується")
	assert_true(r.beats[0].events[0] is ReplayFilter.Vanished)
	assert_true(r.on_screen_start.has(squad.id), "на початку загін намальований")
	for b in r.beats:
		assert_false(b.on_screen.has(squad.id), "після зникнення загону на екрані немає")
	var mid: BattleState = r.beats[0].after
	assert_true(mid.can_see_unit(0, mid.get_unit(squad.id)),
			"передумова: стан посеред маршруту загін бачить — малювати з нього не можна")


# --- постріли ------------------------------------------------------------------------

func test_shot_at_viewer_unit_from_fog_is_shown_with_shooter_appeared() -> void:
	var s: BattleState = _state()
	_anchor(s)
	# Бронеавтомобіль бачить на 3, танк б'є на 4: стрілець у тумані без підтасовки.
	var mine: Unit = s.add_unit(2, 0, Vector2i(5, ROAD_Y), 2)
	var shooter: Unit = s.add_unit(5, 1, Vector2i(9, ROAD_Y), 2)
	_open(s, _cols(0, 7))
	_play(s, FireCommand.create(shooter.id, mine.id))
	_end(s)
	var r: ReplayFilter.Result = _build()
	assert_not_null(r)
	assert_eq(r.beats.size(), 1)
	var ev: Array[Events.BattleEvent] = r.beats[0].events
	assert_true(ev[0] is ReplayFilter.Appeared, "влучання відкриває стрільця до пострілу")
	assert_eq(ev[0].unit_id, shooter.id)
	assert_eq(ev[0].pos, Vector2i(9, ROAD_Y))
	assert_eq(ev[0].facing, Board.facing_towards(Vector2i(9, 7), Vector2i(5, 7)), "уже розвернутий на ціль")
	assert_true(ev[1] is Events.ShotFired)
	assert_true(_has(ev, Events.DamageDealt))
	assert_eq(r.beats[0].focus, Vector2i(9, ROAD_Y))


func test_viewer_retaliation_is_shown() -> void:
	var s: BattleState = _state()
	_anchor(s)
	var mine: Unit = s.add_unit(5, 0, Vector2i(5, ROAD_Y), 2)
	var shooter: Unit = s.add_unit(5, 1, Vector2i(9, ROAD_Y), 6)
	_open(s, _cols(0, W - 1))
	_play(s, FireCommand.create(shooter.id, mine.id))
	_end(s)
	var r: ReplayFilter.Result = _build()
	assert_not_null(r)
	var ev: Array[Events.BattleEvent] = r.beats[0].events
	assert_false(_has(ev, ReplayFilter.Appeared), "стрілець і так був видимий")
	var answer: Array[Events.BattleEvent] = ev.filter(func(e: Events.BattleEvent) -> bool: return e is Events.ShotRetaliated)
	assert_eq(answer.size(), 1)
	assert_eq(answer[0].attacker_id, mine.id)
	var hit_back: Array[Events.BattleEvent] = _of(ev, shooter.id).filter(
			func(e: Events.BattleEvent) -> bool: return e is Events.DamageDealt)
	assert_eq(hit_back.size(), 1, "шкода від відповіді видна")


func test_three_players_visible_shooter_into_fog_keeps_no_target_events() -> void:
	var s: BattleState = _state(3)
	_anchor(s)
	# Перший постріл (відділення, слабкий) лишає ціль живою — вона розвертається й відповідає;
	# другий (танк) добиває. Ціль дивиться геть від обох стрільців, тож поворот справді є.
	var a1: Unit = s.add_unit(0, 1, Vector2i(10, ROAD_Y), 2)
	var a2: Unit = s.add_unit(5, 1, Vector2i(9, ROAD_Y), 2)
	var b: Unit = s.add_unit(5, 2, Vector2i(13, ROAD_Y), 2)
	# До знімка: повторний прогін стартує зі знімка і мусить мати те саме HP.
	b.hp = int(FireCommand.preview(s, a1.id, b.id)["max"]) + 1
	_open(s, _cols(0, 10))
	_play(s, FireCommand.create(a1.id, b.id))
	assert_true(b.is_alive(), "передумова: перший постріл не вбиває")
	assert_lte(b.hp, int(FireCommand.preview(s, a2.id, b.id)["min"]), "передумова: другий добиває")
	_play(s, FireCommand.create(a2.id, b.id))
	_end(s)
	var raw: Array[Events.BattleEvent] = []
	for en in journal.rerun(0):
		raw.append_array(en["events"])
	assert_true(_of(raw, b.id).any(func(e: Events.BattleEvent) -> bool: return e is Events.UnitTurned),
			"передумова: прогін розвернув ціль")
	assert_true(_of(raw, b.id).any(func(e: Events.BattleEvent) -> bool: return e is Events.UnitDestroyed),
			"передумова: прогін знищив ціль")
	var r: ReplayFilter.Result = _build()
	assert_not_null(r)
	var ev: Array[Events.BattleEvent] = _all(r)
	assert_true(_has(ev, Events.ShotFired), "постріл іде в туман")
	assert_eq(_of(ev, b.id).size(), 0, "ціль у тумані: ні шкоди, ні повороту, ні загибелі")
	assert_false(_has(ev, Events.WreckLeft), "уламки в тумані не показуються")
	assert_true(_has(ev, Events.ShotRetaliated), "відповідь із туману у видимого — видно")
	assert_eq(r.beats[0].focus, Vector2i(10, ROAD_Y), "камера — на видимому стрільці")


func test_three_players_unseen_shooter_on_visible_unit_has_no_shooter_appeared() -> void:
	var s: BattleState = _state(3)
	_anchor(s)
	var a: Unit = s.add_unit(5, 1, Vector2i(13, ROAD_Y), 2)
	var b: Unit = s.add_unit(5, 2, Vector2i(9, ROAD_Y), 6)
	_open(s, _cols(0, 10))
	_play(s, FireCommand.create(a.id, b.id))
	_end(s)
	_end(s)
	var r: ReplayFilter.Result = _build()
	assert_not_null(r)
	var ev: Array[Events.BattleEvent] = _all(r)
	assert_false(_has(ev, ReplayFilter.Appeared), "влучання відкрило стрільця боку цілі, не глядачеві")
	assert_true(_has(ev, Events.ShotFired))
	assert_eq(_of(ev, a.id).size(), 0, "про невидимого стрільця — нічого")
	var on_b: Array[Events.BattleEvent] = _of(ev, b.id)
	assert_true(on_b.any(func(e: Events.BattleEvent) -> bool: return e is Events.DamageDealt))
	assert_true(on_b.any(func(e: Events.BattleEvent) -> bool: return e is Events.UnitTurned), "ціль розвертається")
	assert_eq(r.beats[0].focus, Vector2i(9, ROAD_Y), "камера — на цілі, не на стрільці")


## Бійці, що впали від влучання на розвіданому глядачем, падають і на повторі; на нерозвіданому — нічого.
## Видимість — з копії стану після команди: тіла з прогону несуть біти показу кінця проміжку.
func test_figures_fall_in_replay_only_where_the_viewer_sees_the_tile() -> void:
	for seen_target: bool in [true, false]:
		journal = ReplayLog.new()
		var s: BattleState = _state(3)
		_anchor(s)
		var target_x: int = 9 if seen_target else 13
		var shooter_x: int = 13 if seen_target else 9
		var a: Unit = s.add_unit(5, 1, Vector2i(shooter_x, ROAD_Y), 2)
		var b: Unit = s.add_unit(0, 2, Vector2i(target_x, ROAD_Y), 6)
		b.hp = 30  # дві фігури: будь-яке влучання (щонайменше 10) валить одну
		# Танк глядача по діагоналі від цілі: у дальності відділення (8 ≤ 9), але тайла цілі не бачить (ромб 4 > 3).
		var c: Unit = s.add_unit(5, 0, Vector2i(target_x - 2, ROAD_Y + 2), 0)
		_open(s, _cols(0, 10))
		_play(s, FireCommand.create(a.id, b.id))
		_end(s)
		if not seen_target:
			# Пізніший такт того самого проміжку: ціль стріляє в танк глядача, і влучання відкриває її тайл.
			# Об'єкт тіла з прогону вже має біт глядача; рішення — з копії стану після пострілу, де його нема.
			assert_false(s.vision[0].is_seen(b.pos), "передумова: тайл цілі ще нерозвіданий")
			_play(s, FireCommand.create(b.id, c.id))
			assert_true(s.vision[0].is_seen(b.pos), "передумова: влучання відкрило тайл цілі")
		_end(s)
		var raw: Array[Events.BattleEvent] = []
		for en in journal.rerun(0):
			raw.append_array(en["events"])
		assert_true(_has(raw, Events.FiguresFell), "передумова: прогін повалив бійця")
		var r: ReplayFilter.Result = _build()
		var ev: Array[Events.BattleEvent] = _all(r) if r != null else [] as Array[Events.BattleEvent]
		# перше падіння (запис 0) — від пострілу по цілі; відповідь танка глядача пізніше валить її вже на видноті
		var first_fall: bool = ev.any(func(e: Events.BattleEvent) -> bool:
				return e is Events.FiguresFell and (e as Events.FiguresFell).body.unit_id == b.id and (e as Events.FiguresFell).body.seq == 0)
		assert_eq(first_fall, seen_target, "падіння на %s тайлі" % ("розвіданому" if seen_target else "нерозвіданому"))


func test_ap_changed_never_kept() -> void:
	var s: BattleState = _state()
	_anchor(s)
	var mine: Unit = s.add_unit(5, 0, Vector2i(5, ROAD_Y), 2)
	var shooter: Unit = s.add_unit(5, 1, Vector2i(10, ROAD_Y), 6)
	_open(s, _cols(0, W - 1))
	_play(s, MoveCommand.create(shooter.id, Vector2i(9, ROAD_Y)))
	_play(s, FireCommand.create(shooter.id, mine.id))
	_end(s)
	var r: ReplayFilter.Result = _build()
	assert_not_null(r)
	assert_eq(r.beats.size(), 2)
	assert_false(_has(_all(r), Events.ApChanged))


func test_viewer_unit_killed_in_span_is_alive_in_start_and_destroyed_in_beats() -> void:
	var s: BattleState = _state()
	_anchor(s)
	var mine: Unit = s.add_unit(2, 0, Vector2i(5, ROAD_Y), 2)
	mine.hp = 10
	var shooter: Unit = s.add_unit(5, 1, Vector2i(9, ROAD_Y), 6)
	_open(s, _cols(0, W - 1))
	_play(s, FireCommand.create(shooter.id, mine.id))
	_end(s)
	var r: ReplayFilter.Result = _build()
	assert_not_null(r)
	assert_true(r.start.get_unit(mine.id).is_alive(), "на початку відрізка ще живий")
	var ev: Array[Events.BattleEvent] = _all(r)
	assert_true(_of(ev, mine.id).any(func(e: Events.BattleEvent) -> bool: return e is Events.UnitDestroyed))
	assert_true(_has(ev, Events.WreckLeft))
	assert_false(r.beats[0].after.get_unit(mine.id).is_alive())


# --- міни й мости ---------------------------------------------------------------------

func test_bridge_demolished_under_viewer_unit_by_unseen_engineer_shows_collapse_not_engineer() -> void:
	var s: BattleState = _state()
	_anchor(s)
	s.board.set_kind(Vector2i(8, ROAD_Y), Terrain.Kind.BRIDGE)
	var mine: Unit = s.add_unit(2, 0, Vector2i(8, ROAD_Y), 2)
	var eng: Unit = s.add_unit(11, 1, Vector2i(9, ROAD_Y), 6)
	# Наживо сусід інженера завжди в ромбі машини; туман тут виставлено штучно.
	_open(s, _cols(0, 8))
	_play(s, EngineerCommand.create(eng.id, EngineerCommand.Action.DEMOLISH_BRIDGE, Vector2i(8, ROAD_Y)))
	_end(s)
	var r: ReplayFilter.Result = _build()
	assert_not_null(r)
	var ev: Array[Events.BattleEvent] = r.beats[0].events
	assert_true(ev[0] is Events.BridgeChanged, "обвал під своєю машиною — видно")
	assert_true(_of(ev, mine.id).any(func(e: Events.BattleEvent) -> bool: return e is Events.UnitDestroyed))
	assert_eq(_of(ev, eng.id).size(), 0, "інженера влучання не відкриває")
	assert_false(_has(ev, ReplayFilter.Appeared))
	assert_eq(r.beats[0].focus, Vector2i(8, ROAD_Y))


func test_bridge_demolished_by_unseen_engineer_without_viewer_loss_is_not_shown() -> void:
	var s: BattleState = _state()
	_anchor(s)
	s.board.set_kind(Vector2i(8, ROAD_Y), Terrain.Kind.BRIDGE)
	s.wrecks.append(Wrecks.Wreck.new(Vector2i(8, ROAD_Y), 2, 0, 99, 0))
	var eng: Unit = s.add_unit(11, 1, Vector2i(9, ROAD_Y), 6)
	_open(s, _cols(0, 8))
	_play(s, EngineerCommand.create(eng.id, EngineerCommand.Action.DEMOLISH_BRIDGE, Vector2i(8, ROAD_Y)))
	_end(s)
	assert_null(_build(), "ні обвалу, ні уламків, що зникли з мосту")


func test_enemy_on_viewer_mine_in_fog_shows_blast_without_unit() -> void:
	var s: BattleState = _state()
	_anchor(s)
	Mines.place(s, Vector2i(8, ROAD_Y), 0)
	var car: Unit = s.add_unit(2, 1, Vector2i(11, ROAD_Y), 6)
	# Наживо своя міна лежить на розвіданому; туман тут виставлено штучно.
	_open(s, _cols(0, 5))
	_play(s, MoveCommand.create(car.id, Vector2i(6, ROAD_Y)))
	_end(s)
	var r: ReplayFilter.Result = _build()
	assert_not_null(r)
	var ev: Array[Events.BattleEvent] = r.beats[0].events
	assert_eq(ev.size(), 1)
	assert_true(ev[0] is Events.MineTriggered)
	assert_eq(ev[0].pos, Vector2i(8, ROAD_Y))
	assert_eq(r.beats[0].focus, Vector2i(8, ROAD_Y))


func test_viewer_mine_cleared_by_unseen_engineer_is_not_shown() -> void:
	var s: BattleState = _state()
	_anchor(s)
	Mines.place(s, Vector2i(8, ROAD_Y), 0)
	Mines.place(s, Vector2i(8, 2), 0)
	var unseen: Unit = s.add_unit(11, 1, Vector2i(9, ROAD_Y), 6)
	var seen: Unit = s.add_unit(11, 1, Vector2i(8, 1), 4)
	var tiles: Array[Vector2i] = _cols(0, 8)
	_open(s, tiles)
	_play(s, EngineerCommand.create(unseen.id, EngineerCommand.Action.CLEAR_MINE, Vector2i(8, ROAD_Y)))
	_play(s, EngineerCommand.create(seen.id, EngineerCommand.Action.CLEAR_MINE, Vector2i(8, 2)))
	_end(s)
	var r: ReplayFilter.Result = _build()
	assert_not_null(r)
	assert_eq(r.beats.size(), 1, "лише видимий інженер")
	assert_true(r.beats[0].events[0] is Events.MineCleared)
	assert_eq(r.beats[0].events[0].pos, Vector2i(8, 2))


func test_mine_laying_is_never_shown() -> void:
	var s: BattleState = _state()
	_anchor(s)
	var eng: Unit = s.add_unit(11, 1, Vector2i(9, ROAD_Y), 6)
	_open(s, _cols(0, W - 1))
	_play(s, EngineerCommand.create(eng.id, EngineerCommand.Action.LAY_MINE, Vector2i(8, ROAD_Y)))
	_end(s)
	assert_null(_build())


# --- відрізок у часі ------------------------------------------------------------------

func test_three_players_span_holds_both_turns_in_order() -> void:
	var s: BattleState = _state(3)
	_anchor(s)
	var a: Unit = s.add_unit(2, 1, Vector2i(12, 3), 6)
	var b: Unit = s.add_unit(2, 2, Vector2i(12, 11), 6)
	_open(s, _cols(0, W - 1))
	_play(s, MoveCommand.create(a.id, Vector2i(10, 3)))
	_end(s)
	_play(s, MoveCommand.create(b.id, Vector2i(10, 11)))
	_end(s)
	var r: ReplayFilter.Result = _build()
	assert_not_null(r)
	assert_eq(r.beats.size(), 2)
	assert_eq(r.beats[0].actor, 1)
	assert_eq(r.beats[0].events[0].unit_id, a.id)
	assert_eq(r.beats[1].actor, 2)
	assert_eq(r.beats[1].events[0].unit_id, b.id)
	assert_eq(r.beats[1].turn, 1)


func test_burn_out_at_opponents_turn_start_carries_that_turn() -> void:
	var s: BattleState = _state()
	_anchor(s)
	# Догорає на початку ходу 1 гравця 1: годинник 1 * 2 + 1.
	s.wrecks.append(Wrecks.Wreck.new(Vector2i(12, 3), 2, 0, 3, 0))
	s.add_unit(2, 1, Vector2i(20, 12), 6)
	_open(s, _cols(0, W - 1))
	_end(s)
	var r: ReplayFilter.Result = _build()
	assert_not_null(r)
	assert_true(r.beats[0].events[0] is Events.WreckRemoved)
	assert_eq(r.beats[0].actor, 1, "мітка — того, чий хід почався, а не глядача")


func test_three_players_concede_mid_span_is_labelled_with_the_one_who_conceded() -> void:
	var s: BattleState = _state(3)
	_anchor(s)
	var gone: Unit = s.add_unit(2, 1, Vector2i(12, 3), 6)
	var b: Unit = s.add_unit(2, 2, Vector2i(12, 11), 6)
	# Догорає на початку ходу 1 гравця 2: годинник 1 * 3 + 2 — у тій самій команді здачі.
	s.wrecks.append(Wrecks.Wreck.new(Vector2i(5, 5), 2, 0, 5, 0))
	_open(s, _cols(0, W - 1))
	_play(s, ConcedeCommand.create())
	_play(s, MoveCommand.create(b.id, Vector2i(10, 11)))
	_end(s)
	var r: ReplayFilter.Result = _build()
	assert_not_null(r, "вибув суперник, а не матч скінчився")
	assert_eq(r.beats.size(), 3, "здача ділиться на два такти на передачі ходу")
	assert_true(_of(r.beats[0].events, gone.id).any(func(e: Events.BattleEvent) -> bool: return e is Events.UnitDestroyed))
	assert_false(_has(r.beats[0].events, Events.WreckRemoved), "такт не тягнеться через два ходи")
	assert_eq(r.beats[0].actor, 1, "загибель від здачі — у ході того, хто здався")
	assert_true(r.beats[1].events[0] is Events.WreckRemoved)
	assert_eq(r.beats[1].actor, 2, "догоряння — уже в ході наступного")
	assert_eq(r.beats[2].actor, 2)


func test_first_player_first_turn_has_no_replay() -> void:
	var s: BattleState = _state()
	_anchor(s)
	s.add_unit(2, 1, Vector2i(12, 3), 6)
	s.start()
	s.begin_turn()
	journal.mark(1, s)
	assert_null(ReplayFilter.build(journal, 0), "без знімка глядача — без повтору")
	journal.mark(0, s)
	assert_null(ReplayFilter.build(journal, 0), "порожній відрізок — без повтору")


func test_match_ended_in_span_gives_null() -> void:
	var s: BattleState = _state()
	var mine: Unit = s.add_unit(2, 0, Vector2i(5, ROAD_Y), 2)
	mine.hp = 10
	var shooter: Unit = s.add_unit(5, 1, Vector2i(9, ROAD_Y), 6)
	_open(s, _cols(0, W - 1))
	_play(s, FireCommand.create(shooter.id, mine.id))
	assert_true(s.is_over(), "передумова: глядач вибув")
	assert_null(_build())


func test_nothing_visible_gives_null() -> void:
	var s: BattleState = _state()
	_anchor(s)
	var car: Unit = s.add_unit(2, 1, Vector2i(12, ROAD_Y), 6)
	_open(s, _cols(0, 5))
	_play(s, MoveCommand.create(car.id, Vector2i(8, ROAD_Y)))
	_end(s)
	assert_null(_build())


func test_events_after_viewers_turn_started_are_cut() -> void:
	var s: BattleState = _state()
	var anchor: Unit = _anchor(s)
	var car: Unit = s.add_unit(2, 1, Vector2i(12, ROAD_Y), 6)
	# Догорає на початку ходу 2 глядача: годинник 2 * 2 + 0.
	s.wrecks.append(Wrecks.Wreck.new(Vector2i(12, 3), 2, 0, 4, 1))
	_open(s, _cols(0, W - 1))
	_play(s, MoveCommand.create(car.id, Vector2i(10, ROAD_Y)))
	_end(s)
	_play(s, MoveCommand.create(anchor.id, Vector2i(1, 0)))
	var r: ReplayFilter.Result = _build()
	assert_not_null(r)
	assert_eq(r.beats.size(), 1, "лише хід противника")
	assert_false(_has(_all(r), Events.WreckRemoved), "догоряння на початку ходу глядача — уже живий хід")
	assert_eq(_of(_all(r), anchor.id).size(), 0, "свій хід глядача не програється")


# --- додаткові рядки таблиці ------------------------------------------------------------

func test_move_blocked_on_a_mine_is_never_shown() -> void:
	var s: BattleState = _state()
	_anchor(s)
	Mines.place(s, Vector2i(8, ROAD_Y), 0)
	# Інженер знаходить міну дорогою (ромб 3) і спиняється перед нею: обрив тут — знахідка міни.
	var eng: Unit = s.add_unit(11, 1, Vector2i(12, ROAD_Y), 6)
	_open(s, _cols(0, W - 1))
	_play(s, MoveCommand.create(eng.id, Vector2i(7, ROAD_Y)))
	_end(s)
	var raw: Array[Events.BattleEvent] = journal.rerun(0)[1]["events"]
	assert_true(_has(raw, Events.MoveBlocked), "передумова: прогін спинився перед міною")
	var r: ReplayFilter.Result = _build()
	assert_not_null(r)
	var ev: Array[Events.BattleEvent] = r.beats[0].events
	assert_eq(ev[0].path, [Vector2i(11, 7), Vector2i(10, 7), Vector2i(9, 7)] as Array[Vector2i])
	assert_false(_has(ev, Events.MoveBlocked), "обрив перед міною доносить, що її знайшли")


func test_bridge_collapse_under_visible_third_side_unit_shows_without_engineer() -> void:
	var s: BattleState = _state(3)
	_anchor(s)
	s.add_unit(5, 2, Vector2i(23, 13), 0)
	s.board.set_kind(Vector2i(8, ROAD_Y), Terrain.Kind.BRIDGE)
	var car: Unit = s.add_unit(2, 2, Vector2i(8, ROAD_Y), 2)
	var eng: Unit = s.add_unit(11, 1, Vector2i(9, ROAD_Y), 6)
	_open(s, _cols(0, 8))
	_play(s, EngineerCommand.create(eng.id, EngineerCommand.Action.DEMOLISH_BRIDGE, Vector2i(8, ROAD_Y)))
	_end(s)
	_end(s)
	var r: ReplayFilter.Result = _build()
	assert_not_null(r)
	var ev: Array[Events.BattleEvent] = r.beats[0].events
	assert_true(ev[0] is Events.BridgeChanged, "обвал під видимим чужим юнітом — видно")
	assert_true(_of(ev, car.id).any(func(e: Events.BattleEvent) -> bool: return e is Events.UnitDestroyed))
	assert_eq(_of(ev, eng.id).size(), 0)
	assert_false(_has(ev, ReplayFilter.Appeared))


func test_bridge_beat_from_visible_engineer_focuses_the_bridge() -> void:
	var s: BattleState = _state()
	_anchor(s)
	s.board.set_kind(Vector2i(8, ROAD_Y), Terrain.Kind.BRIDGE)
	var eng: Unit = s.add_unit(11, 1, Vector2i(9, ROAD_Y), 6)
	_open(s, _cols(0, W - 1))
	_play(s, EngineerCommand.create(eng.id, EngineerCommand.Action.DEMOLISH_BRIDGE, Vector2i(8, ROAD_Y)))
	_end(s)
	var r: ReplayFilter.Result = _build()
	assert_not_null(r)
	assert_eq(r.beats[0].events.size(), 1)
	assert_true(r.beats[0].events[0] is Events.BridgeChanged)
	assert_eq(r.beats[0].focus, Vector2i(8, ROAD_Y), "кадр — тайл першої показаної події, міст")


func test_eliminated_viewer_gets_no_replay() -> void:
	var s: BattleState = _state(3)
	var mine: Unit = s.add_unit(2, 0, Vector2i(5, ROAD_Y), 2)
	mine.hp = 10
	var shooter: Unit = s.add_unit(5, 1, Vector2i(9, ROAD_Y), 6)
	s.add_unit(5, 2, Vector2i(23, 13), 0)
	_open(s, _cols(0, W - 1))
	_play(s, FireCommand.create(shooter.id, mine.id))
	assert_false(s.is_over(), "передумова: у грі на трьох матч триває")
	_end(s)
	_end(s)
	assert_null(_build(), "у вибулого гравця ходу немає — і повтору теж")


func test_forest_broken_shows_only_on_seen_ground() -> void:
	var s: BattleState = _state()
	_anchor(s)
	# Вода з обох боків лишає танкові один шлях — крізь два тайли лісу.
	for x in range(8, 15):
		s.board.set_kind(Vector2i(x, 2), Terrain.Kind.WATER)
		s.board.set_kind(Vector2i(x, 4), Terrain.Kind.WATER)
	s.board.set_kind(Vector2i(12, 3), Terrain.Kind.FOREST)
	s.board.set_kind(Vector2i(11, 3), Terrain.Kind.FOREST)
	var tank: Unit = s.add_unit(5, 1, Vector2i(13, 3), 6)
	_open(s, _cols(0, 11))
	_play(s, MoveCommand.create(tank.id, Vector2i(10, 3)))
	_end(s)
	var raw_broken: int = 0
	for en in journal.rerun(0):
		for e in en["events"]:
			if e is Events.ForestBroken:
				raw_broken += 1
	assert_eq(raw_broken, 2, "без фільтра падають обидва тайли лісу")
	var r: ReplayFilter.Result = _build()
	assert_not_null(r)
	var ev: Array[Events.BattleEvent] = r.beats[0].events
	var broken: Array[Events.BattleEvent] = ev.filter(func(e: Events.BattleEvent) -> bool: return e is Events.ForestBroken)
	assert_eq(broken.size(), 1, "ліс у тумані падає непомітно")
	assert_eq(broken[0].pos, Vector2i(11, 3))
	assert_true(ev[0] is ReplayFilter.Appeared)
	assert_true(ev[1] is Events.ForestBroken, "ліс падає на тайлі появи, до решти шляху")
	assert_true(ev[2] is Events.UnitMoved)


func test_turn_in_place_shows_only_a_visible_unit() -> void:
	var s: BattleState = _state()
	_anchor(s)
	var seen: Unit = s.add_unit(2, 1, Vector2i(4, 3), 6)
	var unseen: Unit = s.add_unit(2, 1, Vector2i(15, 3), 6)
	_open(s, _cols(0, 10))
	_play(s, TurnCommand.create(unseen.id, Vector2i(15, 4)))
	_play(s, TurnCommand.create(seen.id, Vector2i(4, 4)))
	_end(s)
	var raw_turned: Array[int] = []
	for en in journal.rerun(0):
		for e in en["events"]:
			if e is Events.UnitTurned:
				raw_turned.append(e.unit_id)
	assert_true(raw_turned.has(unseen.id), "без фільтра повертаються обидва")
	assert_true(raw_turned.has(seen.id))
	var r: ReplayFilter.Result = _build()
	assert_not_null(r)
	assert_eq(r.beats.size(), 1)
	assert_eq(r.beats[0].events.size(), 1)
	assert_true(r.beats[0].events[0] is Events.UnitTurned)
	assert_eq(r.beats[0].events[0].unit_id, seen.id)
	assert_eq(r.beats[0].focus, Vector2i(4, 3))


func test_build_is_null_when_the_rerun_diverges_from_the_log() -> void:
	var s: BattleState = _state()
	var a: Unit = _anchor(s)
	s.start()
	s.active_player = 0
	s.begin_turn()
	journal.mark(0, s)
	journal.record(MoveCommand.create(a.id, Vector2i(20, 0)))  # далеко за межами AP: не проходить
	assert_ne(MoveCommand.create(a.id, Vector2i(20, 0)).validate(s), "")
	assert_null(ReplayFilter.build(journal, 0))


func test_visible_enemy_on_viewer_mine_shows_move_and_blast() -> void:
	var s: BattleState = _state()
	_anchor(s)
	Mines.place(s, Vector2i(8, ROAD_Y), 0)
	var car: Unit = s.add_unit(2, 1, Vector2i(11, ROAD_Y), 6)
	_open(s, _cols(0, W - 1))
	_play(s, MoveCommand.create(car.id, Vector2i(6, ROAD_Y)))
	_end(s)
	var r: ReplayFilter.Result = _build()
	assert_not_null(r)
	var ev: Array[Events.BattleEvent] = r.beats[0].events
	assert_eq(ev.size(), 3)
	assert_true(ev[0] is Events.UnitMoved)
	assert_eq(ev[0].path, [Vector2i(10, 7), Vector2i(9, 7), Vector2i(8, 7)] as Array[Vector2i])
	assert_true(ev[1] is Events.MineTriggered, "вибух — після того, як доїхав")
	assert_true(ev[2] is Events.DamageDealt)


func test_drone_at_viewer_vehicle_from_fog_shows_squad_appeared() -> void:
	var s: BattleState = _state()
	_anchor(s)
	var mine: Unit = s.add_unit(2, 0, Vector2i(5, ROAD_Y), 2)
	var squad: Unit = s.add_unit(1, 1, Vector2i(10, ROAD_Y), 2)
	_open(s, _cols(0, 8))
	_play(s, DroneCommand.create(squad.id, mine.id))
	_end(s)
	var r: ReplayFilter.Result = _build()
	assert_not_null(r)
	var ev: Array[Events.BattleEvent] = r.beats[0].events
	assert_true(ev[0] is ReplayFilter.Appeared, "удар дрона відкриває загін, як і постріл")
	assert_eq(ev[0].unit_id, squad.id)
	assert_true(ev[1] is Events.DroneLaunched)
	assert_true(_of(ev, mine.id).any(func(e: Events.BattleEvent) -> bool: return e is Events.DamageDealt))
	assert_eq(r.beats[0].focus, Vector2i(10, ROAD_Y))


func test_move_blocked_by_unseen_unit_or_hidden_squad_is_not_shown() -> void:
	for hidden_squad in [false, true]:
		before_each()
		var s: BattleState = _state(3)
		_anchor(s)
		var mover: Unit
		if hidden_squad:
			s.board.set_kind(Vector2i(8, ROAD_Y), Terrain.Kind.BUILDING)
			s.add_unit(0, 2, Vector2i(8, ROAD_Y), 0)
			mover = s.add_unit(0, 1, Vector2i(11, ROAD_Y), 6)
			_open(s, _cols(0, W - 1))
			_play(s, MoveCommand.create(mover.id, Vector2i(8, ROAD_Y)))
		else:
			s.add_unit(5, 2, Vector2i(8, ROAD_Y), 0)
			mover = s.add_unit(2, 1, Vector2i(12, ROAD_Y), 6)
			_open(s, _cols(9, W - 1))
			_play(s, MoveCommand.create(mover.id, Vector2i(6, ROAD_Y)))
		_end(s)
		_end(s)
		assert_true(_has(journal.rerun(0)[1]["events"], Events.MoveBlocked), "передумова: прогін урвав хід")
		var r: ReplayFilter.Result = _build()
		assert_not_null(r)
		var ev: Array[Events.BattleEvent] = r.beats[0].events
		assert_true(ev[0] is Events.UnitMoved)
		assert_eq(ev[0].path[ev[0].path.size() - 1], Vector2i(9, ROAD_Y))
		assert_false(_has(ev, Events.MoveBlocked), "обрив показав би невидимого, загін у будинку: %s" % hidden_squad)
