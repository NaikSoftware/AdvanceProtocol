extends GutTest
## Постріл орієнтує стрільця на ціль (§3.3/§3.3.1).
##
## УВЕСЬ сенс цього файлу — ПОРЯДОК трьох кроків, а не сам факт розвороту:
##
##   1. АТАКУВАЛЬНИК розвертається на ціль ПЕРЕД своїм пострілом. Наслідок
##      навмисний: відповідь прилітає йому вже в новий сектор (і геометрично —
##      завжди в лоб, бо прив'язка до 8 напрямків дає похибку щонайбільше 22.5°,
##      а поріг SIDE потребує більшого).
##   2. ЦІЛЬ отримує шкоду, і сектор ВХІДНОГО пострілу рахується від СТАРОЇ
##      орієнтації цілі. Ціль не розвертається передом до удару — інакше
##      флангування, найвиразніший хід у грі (§3.4), знецінилось би до нуля.
##   3. ТІЛЬКИ ПІСЛЯ застосування шкоди, і тільки якщо відповідь СПРАВДІ
##      відбувається, відповідач розвертається на початкового атакувальника.
##
## Розворот — НАСЛІДОК пострілу, ніколи не передумова: дуги вогню немає, він не
## коштує AP, не може «не вдатися» і не впливає на те, чи дозволено стріляти.

var state: BattleState

func before_each() -> void:
	state = BattleState.create(Board.create(16, 16, Terrain.GroundState.DRY), 2, 11)
	state.active_player = 0

# --- дрібні пошуковики по потоку подій ------------------------------------

func _turns_of(events: Array, unit_id: int) -> Array:
	var out: Array = []
	for e in events:
		if e is Events.UnitTurned and e.unit_id == unit_id:
			out.append(e)
	return out

func _first_damage_to(events: Array, unit_id: int) -> Events.DamageDealt:
	for e in events:
		if e is Events.DamageDealt and e.unit_id == unit_id:
			return e
	return null

func _shot_fired(events: Array) -> Events.ShotFired:
	for e in events:
		if e is Events.ShotFired:
			return e
	return null

func _shot_retaliated(events: Array) -> Events.ShotRetaliated:
	for e in events:
		if e is Events.ShotRetaliated:
			return e
	return null

func _index_where(events: Array, pred: Callable) -> int:
	for i in events.size():
		if pred.call(events[i]):
			return i
	return -1

# ---------------------------------------------------------------------------
# 1. ГОЛДЕН НА ПОРЯДОК.
#
# Два середні танки (#5: atk 95, ap 48, hp 400, дальність 4, fire_cost 20,
# броня 37/27/18). Ціль на (6,4) дивиться на СХІД — тобто кормою до
# атакувальника на (4,4), який дивиться на ЗАХІД, тобто від цілі.
#
# Вхідний постріл мусить лягти в КОРМУ:
#   dmg = 0.75*95 + roll(0,23) - (0.75*18 + roll(0,4)) = 57.75 + [0,23] - [0,4]
#   межі корми: [53, 80]; межі лоба:  [34, 66]
# На сіді 11 це рівно 69 — і 69 > 66, тобто число ЛЕЖИТЬ ПОЗА лобовими межами.
# Саме тому літерал тут щось доводить: якби порядок «поїхав» і ціль оберталась
# передом до удару, це значення стало б недосяжним.
const REAR_DAMAGE_ON_SEED_11: int = 69

func test_incoming_shot_is_resolved_against_the_targets_old_facing() -> void:
	var a: Unit = state.add_unit(5, 0, Vector2i(4, 4), 6)   # захід — спиною до цілі
	var t: Unit = state.add_unit(5, 1, Vector2i(6, 4), 2)   # схід — кормою до атакувальника
	state.begin_turn()
	state.refresh_vision(t.owner)  # §3.3.1: відповідач мусить бачити атакувальника

	var front: Vector2i = Rules.damage_bounds(a, t, 0, UnitTypes.ArmourSector.FRONT, 4)
	assert_true(REAR_DAMAGE_ON_SEED_11 > front.y,
		"передумова літерала: кормове значення мусить лежати поза лобовими межами %s" % front)

	var events: Array = FireCommand.create(a.id, t.id).apply(state)

	assert_eq(a.facing, 2, "крок 1: атакувальник розвернувся на ціль ЩЕ ДО свого пострілу")
	assert_eq(_shot_fired(events).sector, UnitTypes.ArmourSector.REAR,
		"крок 2: сектор вхідного пострілу — від СТАРОЇ орієнтації цілі")
	assert_eq(_first_damage_to(events, t.id).amount, REAR_DAMAGE_ON_SEED_11,
		"крок 2: шкода вхідного пострілу мусить лишитись кормовою до одиниці — флангування не знецінюється")
	assert_true(t.is_alive(), "передумова: 80 макс. шкоди << 400 hp — є кому відповідати")

func test_retaliator_turns_towards_the_original_attacker() -> void:
	var a: Unit = state.add_unit(5, 0, Vector2i(4, 4), 6)
	var t: Unit = state.add_unit(5, 1, Vector2i(6, 4), 2)
	state.begin_turn()
	state.refresh_vision(t.owner)
	var events: Array = FireCommand.create(a.id, t.id).apply(state)

	assert_not_null(_shot_retaliated(events), "передумова: відповідь мусить статись")
	assert_eq(t.facing, 6, "крок 3: відповідач розвернувся на початкового атакувальника")

func test_retaliation_lands_in_the_new_sector_of_the_attacker() -> void:
	# Наслідок кроку 1, заради якого його й поставлено першим: атакувальник стояв
	# кормою до цілі (facing 6, ціль на сході), а відповідь усе одно приходить у
	# ЛОБ — бо на мить пострілу він уже розвернувся.
	var a: Unit = state.add_unit(5, 0, Vector2i(4, 4), 6)
	var t: Unit = state.add_unit(5, 1, Vector2i(6, 4), 2)
	state.begin_turn()
	state.refresh_vision(t.owner)
	assert_eq(Rules.armour_sector(a.facing, a.pos, t.pos), UnitTypes.ArmourSector.REAR,
		"передумова: до пострілу атакувальник підставляв цілі саме корму")
	var events: Array = FireCommand.create(a.id, t.id).apply(state)
	assert_eq(_shot_retaliated(events).sector, UnitTypes.ArmourSector.FRONT,
		"відповідь лягає в НОВИЙ сектор — розворот стався до пострілу, а не після")

# ---------------------------------------------------------------------------
# 2. НЕ ВІДПОВІВ — НЕ РОЗВЕРНУВСЯ. Чотири окремі гілки виходу з _retaliate().
#
# Найважливіша — остання: якби ціль крутилась від самого факту отриманої шкоди,
# її орієнтація вказувала б на невидимого стрільця. Безкарність невидимої атаки
# (§3.3.1) витекла б через канал, якого туман не фільтрує взагалі.

func test_engineer_that_cannot_retaliate_does_not_turn() -> void:
	# Стрілецьке відділення (#0) впритул до інженерного (#11, hp 200):
	# (0.75*15 + [0,3]) * 4 = [45, 57] << 200 hp — інженер живий, з AP і в
	# дальності, і все одно мовчить (§3.6), отже й не обертається.
	var a: Unit = state.add_unit(0, 0, Vector2i(4, 4), 6)
	var t: Unit = state.add_unit(11, 1, Vector2i(5, 4), 2)   # схід — кормою до атакувальника
	state.begin_turn()
	state.refresh_vision(t.owner)
	var ap_before: int = t.ap
	var events: Array = FireCommand.create(a.id, t.id).apply(state)

	assert_true(t.is_alive())
	assert_null(_shot_retaliated(events), "передумова: інженер не відповідає")
	assert_eq(t.facing, 2, "не відповів — не розвернувся")
	assert_eq(_turns_of(events, t.id).size(), 0, "і жодного UnitTurned на нього в потоці")
	assert_eq(t.ap, ap_before, "AP того, хто не відповідав, лишається як було")
	assert_false(t.has_fired)

func test_target_without_enough_ap_does_not_turn() -> void:
	var a: Unit = state.add_unit(5, 0, Vector2i(4, 4), 6)
	var t: Unit = state.add_unit(5, 1, Vector2i(6, 4), 2)
	state.begin_turn()
	state.refresh_vision(t.owner)
	t.ap = 19  # fire_cost = 20
	var events: Array = FireCommand.create(a.id, t.id).apply(state)

	assert_null(_shot_retaliated(events), "передумова: менше fire_cost AP — відповіді немає")
	assert_eq(t.facing, 2, "не відповів — не розвернувся")
	assert_eq(_turns_of(events, t.id).size(), 0)
	assert_eq(t.ap, 19, "розворот, якого не було, нічого не коштував")
	assert_false(t.has_fired)

func test_target_out_of_its_own_range_does_not_turn() -> void:
	# Гармата (#9: дальність 5) по винищувачу танків (#6: дальність 4, hp 400)
	# з відстані рівно 5: постріл законний, відповідь не дістає.
	var a: Unit = state.add_unit(9, 0, Vector2i(0, 0), 6)
	var t: Unit = state.add_unit(6, 1, Vector2i(5, 0), 2)   # схід — кормою до атакувальника
	state.begin_turn()
	# Предмет тесту — дальність ВІДПОВІДІ, тож гейт знання атакувальника
	# прибирається з дороги явно (§3.5 гейтить постріл на seen).
	state.vision[0].seen.fill(1)
	state.refresh_vision(t.owner)
	var ap_before: int = t.ap
	var events: Array = FireCommand.create(a.id, t.id).apply(state)

	assert_true(t.is_alive(), "передумова: 266 макс. шкоди << 400 hp")
	assert_null(_shot_retaliated(events), "передумова: 25 > 4^2 — не дістає")
	assert_eq(t.facing, 2, "не відповів — не розвернувся")
	assert_eq(_turns_of(events, t.id).size(), 0)
	assert_eq(t.ap, ap_before)
	assert_false(t.has_fired)

func test_target_that_cannot_see_the_attacker_does_not_turn() -> void:
	# КРИТИЧНА гілка. Ціль отримує шкоду від стрільця, якого її власник ніколи не
	# розвідував. Якби розворот чіплявся до шкоди, а не до відповіді, орієнтація
	# цілі показала б УСІМ, звідки прилетіло, — а туман подій не фільтрує (§6,
	# «known debt»). Безкарність невидимої атаки (§3.3.1) витекла б повз туман.
	var a: Unit = state.add_unit(5, 0, Vector2i(4, 4), 6)
	var t: Unit = state.add_unit(5, 1, Vector2i(6, 4), 2)
	state.begin_turn()
	# Навмисно НЕ рахуємо зір гравця 1: його seen порожній, тайла атакувальника
	# він не розвідував ЖОДНОГО разу. Гасимо обидві сітки явно, а не покладаємось
	# на дефолт BattleState.create() — щоб тест не зламався мовчки, якщо дефолт
	# колись зміниться. Той самий прийом, що й у test_retaliation.gd, case 10.
	state.vision[t.owner].visible.fill(0)
	state.vision[t.owner].seen.fill(0)
	assert_true(t.ap >= t.fire_cost() and Rules.in_radius(t.pos, a.pos, t.attack_range()),
		"передумова: AP і дальність цілком дозволяли б відповідь — не пускає саме зір")
	var ap_before: int = t.ap
	var events: Array = FireCommand.create(a.id, t.id).apply(state)

	assert_true(t.is_alive())
	assert_null(_shot_retaliated(events), "передумова: без зору на атакувальника відповіді немає")
	assert_eq(t.facing, 2,
		"§3.3.1: розворот чіпляється до ВІДПОВІДІ, а не до шкоди — інакше орієнтація цілі видала б невидимого стрільця")
	assert_eq(_turns_of(events, t.id).size(), 0)
	assert_eq(t.ap, ap_before)
	assert_false(t.has_fired)

# ---------------------------------------------------------------------------
# 3. Обидва розвороти живуть у ПОТОЦІ ПОДІЙ. Вигляд не сміє домальовувати
# поворот сам — інакше він відтворював би правило, а це заборонено (§6).

func test_both_turns_are_reported_as_events_in_step_order() -> void:
	var a: Unit = state.add_unit(5, 0, Vector2i(4, 4), 6)
	var t: Unit = state.add_unit(5, 1, Vector2i(6, 4), 2)
	state.begin_turn()
	state.refresh_vision(t.owner)
	var events: Array = FireCommand.create(a.id, t.id).apply(state)

	var a_turns: Array = _turns_of(events, a.id)
	var t_turns: Array = _turns_of(events, t.id)
	assert_eq(a_turns.size(), 1, "розворот атакувальника мусить бути в потоці подій")
	assert_eq(a_turns[0].facing, 2)
	assert_eq(t_turns.size(), 1, "розворот відповідача мусить бути в потоці подій")
	assert_eq(t_turns[0].facing, 6)

	var i_a_turn: int = _index_where(events, func(e: Events.BattleEvent) -> bool:
		return e is Events.UnitTurned and e.unit_id == a.id)
	var i_shot: int = _index_where(events, func(e: Events.BattleEvent) -> bool:
		return e is Events.ShotFired)
	var i_dmg: int = _index_where(events, func(e: Events.BattleEvent) -> bool:
		return e is Events.DamageDealt and e.unit_id == t.id)
	var i_t_turn: int = _index_where(events, func(e: Events.BattleEvent) -> bool:
		return e is Events.UnitTurned and e.unit_id == t.id)
	var i_retal: int = _index_where(events, func(e: Events.BattleEvent) -> bool:
		return e is Events.ShotRetaliated)

	assert_lt(i_a_turn, i_shot, "крок 1 передує пострілу")
	assert_lt(i_shot, i_dmg, "крок 2 — шкода по цілі")
	assert_lt(i_dmg, i_t_turn, "крок 3 настає ПІСЛЯ застосування шкоди")
	assert_lt(i_t_turn, i_retal, "і передує самій відповіді")

func test_a_shooter_already_facing_its_target_reports_no_turn() -> void:
	# Розворот — це подія «юніт повернувся», а не тик кожного пострілу: коли
	# повертати нема куди, потік про це мовчить.
	var a: Unit = state.add_unit(5, 0, Vector2i(4, 4), 2)   # уже дивиться на ціль
	var t: Unit = state.add_unit(5, 1, Vector2i(6, 4), 6)   # уже дивиться на атакувальника
	state.begin_turn()
	state.refresh_vision(t.owner)
	var events: Array = FireCommand.create(a.id, t.id).apply(state)
	assert_eq(_turns_of(events, a.id).size(), 0)
	assert_eq(_turns_of(events, t.id).size(), 0)
	assert_eq(a.facing, 2)
	assert_eq(t.facing, 6)

# ---------------------------------------------------------------------------
# 4. Розворот не коштує AP і не витрачає постріл. Обидві сторони входять в обмін
# рівно з fire_cost AP — мінімумом, за якого дія ще законна. Якби розворот
# знімав бодай одне очко або ставив has_fired, той чи той постріл зник би.

func test_turning_costs_no_ap_and_does_not_consume_the_shot() -> void:
	var a: Unit = state.add_unit(5, 0, Vector2i(4, 4), 6)
	var t: Unit = state.add_unit(5, 1, Vector2i(6, 4), 2)
	state.begin_turn()
	state.refresh_vision(t.owner)
	a.ap = a.fire_cost()
	t.ap = t.fire_cost()

	assert_eq(FireCommand.create(a.id, t.id).validate(state), "",
		"розворот — наслідок пострілу, а не його передумова: він не додає вимог до AP")
	var events: Array = FireCommand.create(a.id, t.id).apply(state)

	assert_not_null(_shot_fired(events), "постріл мусить статись при рівно fire_cost AP")
	assert_not_null(_shot_retaliated(events), "і відповідь теж — розворот відповідача не з'їв його AP")
	assert_eq(a.facing, 2)
	assert_eq(t.facing, 6)
	assert_eq(a.ap, 0, "AP обнулив exhaust() (§3.2), а не розворот")
	assert_eq(t.ap, 0)
	assert_true(a.has_fired)
	assert_true(t.has_fired)

# ---------------------------------------------------------------------------
# 5. §3.9: удар дроном орієнтує штурмовий загін так само, як звичайний постріл —
# щоб правило формулювалось одним реченням без винятку. Сьогодні це числово
# інертно, бо броня піхоти 0/0/0; перша ж ненульова броня піхоти зробить його
# значущим і мусить зламати цей тест.

func test_drone_strike_turns_the_squad_and_is_numerically_inert_today() -> void:
	var a: Unit = state.add_unit(1, 0, Vector2i(2, 2), 6)   # захід — спиною до цілі
	var t: Unit = state.add_unit(8, 1, Vector2i(5, 2), 6)   # важкий танк, hp 350
	state.begin_turn()
	state.refresh_vision(t.owner)

	var dist_sq: int = Rules.distance_sq(t.pos, a.pos)
	var level: int = state.experience[t.owner].level_of(t.unit_class())
	var rear: Vector2i = Rules.damage_bounds(t, a, level, UnitTypes.ArmourSector.REAR, dist_sq)
	var front: Vector2i = Rules.damage_bounds(t, a, level, UnitTypes.ArmourSector.FRONT, dist_sq)
	assert_eq(rear, front,
		"броня штурмового загону 0/0/0 — розворот не рухає числа. Коли піхота отримає ненульову броню, цей тест мусить упасти і рішення §3.9 треба переглянути свідомо")

	assert_eq(DroneCommand.create(a.id, t.id).validate(state), "")
	var events: Array = DroneCommand.create(a.id, t.id).apply(state)

	assert_eq(a.facing, 2, "§3.9: дрон орієнтує загін на ціль так само, як звичайний постріл")
	assert_eq(_turns_of(events, a.id).size(), 1, "і повідомляє про це подією")
	assert_not_null(_shot_retaliated(events), "передумова: 120..180 шкоди << 350 hp — танк відповідає")
	var back: Events.DamageDealt = _first_damage_to(events, a.id)
	assert_not_null(back)
	assert_true(back.amount >= front.x and back.amount <= front.y,
		"межі шкоди у відповіді ті самі, що й були: %d поза [%d, %d]" % [back.amount, front.x, front.y])
