extends GutTest
## §3.3.1: ціль, яка вижила після пострілу, стріляє у відповідь тим самим
## обміном. Числа нижче виведені вручну з ростеру (CLAUDE.md §3.6) і формули
## шкоди (§3.3) — див. звіт Task 1.14b.

var state: BattleState

func before_each() -> void:
	state = BattleState.create(Board.create(16, 16, Terrain.GroundState.DRY), 2, 11)
	state.active_player = 0

func _shot_retaliated(events: Array) -> Events.ShotRetaliated:
	for e in events:
		if e is Events.ShotRetaliated:
			return e
	return null

func _count_retaliations(events: Array) -> int:
	var n: int = 0
	for e in events:
		if e is Events.ShotRetaliated:
			n += 1
	return n

# ---------------------------------------------------------------------------
# 1. Surviving target fires back.
#
# Two medium tanks (#5: atk 95, ap 48, hp 400, range 4, fire_cost 20,
# armour 37/27/18) face each other head-on at distance 2 (dist_sq = 4).
# Opening shot: armour_sector = FRONT (both face each other exactly).
#   dmg = 0.75*95 + roll(0,23) - (0.75*37 + roll(0,9))
#       = 71.25 - 27.75 + [0,23] - [0,9] = 43.5 + [0,23] - [0,9]
#   range: [34, 66] after int() truncation — always << 400 hp, target survives.
# Retaliation shot is the mirror of the same formula (identical stats,
# identical FRONT sector) — also [34, 66], always << 400 hp.
func test_surviving_target_retaliates_and_damages_attacker() -> void:
	var a: Unit = state.add_unit(5, 0, Vector2i(4, 4), 2)   # схід
	var t: Unit = state.add_unit(5, 1, Vector2i(6, 4), 6)   # захід — дивиться просто на атакувальника
	state.begin_turn()
	state.refresh_vision(t.owner)
	var attacker_hp_before: int = a.hp
	var events: Array = FireCommand.create(a.id, t.id).apply(state)

	var retaliation: Events.ShotRetaliated = _shot_retaliated(events)
	assert_not_null(retaliation, "танк, що вижив (400 hp проти макс. 66 шкоди), мусить відповісти")
	assert_eq(retaliation.attacker_id, t.id, "у відповіді стріляє колишня ціль")
	assert_eq(retaliation.target_id, a.id, "відповідь летить у початкового атакувальника")
	assert_true(a.hp < attacker_hp_before, "початковий атакувальник мусить втратити hp від відповіді")

func test_shot_retaliated_precedes_its_damage_event() -> void:
	var a: Unit = state.add_unit(5, 0, Vector2i(4, 4), 2)
	var t: Unit = state.add_unit(5, 1, Vector2i(6, 4), 6)
	state.begin_turn()
	state.refresh_vision(t.owner)
	var events: Array = FireCommand.create(a.id, t.id).apply(state)
	var idx: int = -1
	for i in events.size():
		if events[i] is Events.ShotRetaliated:
			idx = i
			break
	assert_true(idx >= 0, "відповідь мусить статись")
	assert_true(events[idx + 1] is Events.DamageDealt,
		"за ShotRetaliated одразу йде DamageDealt від _resolve_damage")

# ---------------------------------------------------------------------------
# 2. A target that dies does not retaliate.
#
# Force a kill by dropping target hp to 1 before the shot; the damage floor
# alone (min 10) guarantees a kill, so the outcome is deterministic
# regardless of the roll.
func test_dead_target_does_not_retaliate() -> void:
	var a: Unit = state.add_unit(5, 0, Vector2i(4, 4), 2)
	var t: Unit = state.add_unit(4, 1, Vector2i(6, 4), 6)
	state.begin_turn()
	t.hp = 1
	var attacker_hp_before: int = a.hp
	var events: Array = FireCommand.create(a.id, t.id).apply(state)
	assert_false(t.is_alive())
	assert_null(_shot_retaliated(events), "мертва ціль не відповідає")
	assert_eq(a.hp, attacker_hp_before, "атакувальник не мусить постраждати")

# ---------------------------------------------------------------------------
# 3. A retaliator without enough AP does not retaliate.
#
# Medium tank target has fire_cost 20; drop its ap to 19 before the shot.
func test_retaliator_without_enough_ap_does_not_retaliate() -> void:
	var a: Unit = state.add_unit(5, 0, Vector2i(4, 4), 2)
	var t: Unit = state.add_unit(5, 1, Vector2i(6, 4), 6)
	state.begin_turn()
	t.ap = 19  # fire_cost = 20
	var attacker_hp_before: int = a.hp
	var events: Array = FireCommand.create(a.id, t.id).apply(state)
	assert_null(_shot_retaliated(events), "менше fire_cost AP — відповіді не буде")
	assert_eq(a.hp, attacker_hp_before)
	assert_eq(t.ap, 19, "AP цілі, що не відповіла, лишається як було")

# ---------------------------------------------------------------------------
# 4. An attacker outside the retaliator's range is not hit back.
#
# Field gun (#9: range 5) fires at a tank destroyer (#6: range 4, hp 400,
# armour front 45) at distance exactly 5 (dist_sq = 25): within the gun's
# range (25 <= 25) but outside the tank destroyer's own range (25 > 16).
#   dmg = 0.75*200 + roll(0,50) - (0.75*45 + roll(0,11)) + roll(0,100)
#       = 150 - 33.75 + [0,50] - [0,11] + [0,100] = 116.25 + [-11,150]
#   bounds: [105, 266] — always << 400 hp, target survives but can't reach back.
func test_attacker_outside_retaliators_range_is_not_hit_back() -> void:
	var a: Unit = state.add_unit(9, 0, Vector2i(0, 0), 2)
	var t: Unit = state.add_unit(6, 1, Vector2i(5, 0), 6)
	state.begin_turn()
	# Предмет тесту — дальність, не зір, тож обмеження зором прибирається з дороги явно:
	# §3.5 обмежує постріл за `seen` (розвідана земля), тож заливається саме seen.
	state.vision[0].seen.fill(1)
	assert_eq(Rules.distance_sq(a.pos, t.pos), 25)
	assert_eq(FireCommand.create(a.id, t.id).validate(state), "")
	var attacker_hp_before: int = a.hp
	var events: Array = FireCommand.create(a.id, t.id).apply(state)
	assert_true(t.is_alive(), "266 макс. шкоди << 400 hp")
	assert_null(_shot_retaliated(events), "5^2=25 > дальність цілі 4^2=16 — не дістає")
	assert_eq(a.hp, attacker_hp_before)

# ---------------------------------------------------------------------------
# 4b. The retaliator's reach is the range CIRCLE, not a vision diamond.
#
# §3.1: дальність — коло (dist_sq <= r*r), огляд — ромб (|dx| + |dy| <= r).
# Дві форми розходяться рівно на діагоналях, тож пін вимагає обміну, у якому
# атакувальник лежить у колі відповідача й поза ромбом того самого радіуса.
#
# Два середні танки (#5: atk 95, hp 400, range 4, vision 4, armour 37/27/18) із
# зсувом (3, 2): 9 + 4 = 13 <= 16 у колі, але 3 + 2 = 5 > 4 у ромбі. Обидва зі
# зсувом бачать один одного не самі, а коригувальниками — стрілецькими
# відділеннями (#0, огляд 5), по одному на гравця: §3.3.1 пов'язує і постріл, і
# вогонь у відповідь з МЕРЕЖЕЮ власника, а не з зором самого стрільця.
#
# Обидва дивляться на схід (facing 2). Ціль до пострілу не обертається (§3.3),
# тож перший постріл лягає в її REAR — сектор рахується від СТАРОЇ орієнтації.
# Відповідь лягає у FRONT атакувальника, і причина саме та, що він РОЗВЕРНУВСЯ
# на ціль перед своїм пострілом (2 -> 3, на південний схід), а не та, що він
# випадково дивився туди й раніше: розворот на ціль гарантує лоб завжди. Числа
# від цього не змінились — обидва напрямки дають FRONT, — а от причина інша:
#   постріл:  0.75*95 + roll(0,23) - (0.75*18 + roll(0,4)) = 57.75 + [0,23] - [0,4]
#             bounds: [53, 80]
#   відповідь: 0.75*95 + roll(0,23) - (0.75*37 + roll(0,9)) = 43.5 + [0,23] - [0,9]
#             bounds: [34, 66]
# Обидва боки << 400 hp — і атакувальник, і ціль виживають обмін.
func test_retaliators_reach_is_the_circle_and_not_a_vision_diamond() -> void:
	var a: Unit = state.add_unit(5, 0, Vector2i(4, 4), 2)   # схід
	var t: Unit = state.add_unit(5, 1, Vector2i(7, 6), 2)   # схід
	state.add_unit(0, 0, Vector2i(7, 8), 2)                 # мій коригувальник на ціль
	state.add_unit(0, 1, Vector2i(4, 7), 2)                 # їхній коригувальник на атакувальника
	state.begin_turn()
	state.refresh_vision(t.owner)

	assert_true(Rules.in_radius(t.pos, a.pos, t.attack_range()), "передумова: у колі дальності 4")
	assert_false(Rules.in_vision_diamond(t.pos, a.pos, t.attack_range()),
		"передумова: поза ромбом того ж радіуса — саме тут дві форми розходяться")
	assert_true(state.vision[t.owner].is_seen(a.pos), "передумова: відповідач тайл атакувальника розвідав")
	assert_eq(FireCommand.create(a.id, t.id).validate(state), "", "передумова: постріл законний")

	var attacker_hp_before: int = a.hp
	var events: Array = FireCommand.create(a.id, t.id).apply(state)
	assert_true(t.is_alive(), "80 макс. шкоди << 400 hp — є кому відповідати")
	assert_not_null(_shot_retaliated(events), "§3.1: дальність відповіді — коло, а не ромб")
	assert_true(a.hp < attacker_hp_before, "відповідь мусить дійти")

# ---------------------------------------------------------------------------
# 5. An engineer never retaliates, even with AP and range to spare.
#
# Rifle squad (#0, INFANTRY) fires at an adjacent engineer vehicle (#11,
# hp 200) — close assault (dist_sq = 1 <= 2) quadruples the hit, but
# infantry ignores armour entirely:
#   dmg = (0.75*15 + roll(0,3)) * 4 = (11.25 + [0,3]) * 4 = 45 + 4*[0,3]
#   bounds: [45, 57] — well below 200 hp, engineer survives with full AP
#   and the attacker inside its (range 1) reach, yet must not answer.
func test_engineer_never_retaliates() -> void:
	var a: Unit = state.add_unit(0, 0, Vector2i(4, 4), 2)
	var t: Unit = state.add_unit(11, 1, Vector2i(5, 4), 6)
	state.begin_turn()
	assert_eq(t.unit_class(), UnitTypes.UnitClass.ENGINEER)
	var attacker_hp_before: int = a.hp
	var events: Array = FireCommand.create(a.id, t.id).apply(state)
	assert_true(t.is_alive())
	assert_true(t.ap >= t.fire_cost(), "AP і дальність цілком дозволяли б відповідь")
	assert_null(_shot_retaliated(events), "§3.6/§3.3.1: інженер не має зброї — ніколи не відповідає")
	assert_eq(a.hp, attacker_hp_before)

# ---------------------------------------------------------------------------
# 6. The retaliator's own AP is zeroed and it is marked as having fired.
func test_retaliators_ap_is_zeroed_and_marked_fired() -> void:
	var a: Unit = state.add_unit(5, 0, Vector2i(4, 4), 2)
	var t: Unit = state.add_unit(5, 1, Vector2i(6, 4), 6)
	state.begin_turn()
	state.refresh_vision(t.owner)
	FireCommand.create(a.id, t.id).apply(state)
	assert_eq(t.ap, 0, "§3.2/§3.3.1: відповідь обнуляє AP відповідача")
	assert_true(t.has_fired)

# ---------------------------------------------------------------------------
# 7. Retaliation damage is credited to the retaliator's owner.
func test_retaliation_damage_is_credited_to_the_retaliators_owner() -> void:
	var a: Unit = state.add_unit(5, 0, Vector2i(4, 4), 2)
	var t: Unit = state.add_unit(5, 1, Vector2i(6, 4), 6)
	state.begin_turn()
	state.refresh_vision(t.owner)
	assert_eq(state.damage_dealt[1], 0)
	FireCommand.create(a.id, t.id).apply(state)
	assert_true(state.damage_dealt[1] > 0,
		"шкода від відповіді йде на рахунок власника-відповідача (гравець 1), а не стрільця")

# ---------------------------------------------------------------------------
# 8. A drone strike also provokes retaliation when the target can reach.
#
# Assault squad (#1) drone-strikes a heavy tank (#8: atk 121, hp 350,
# range 4) at distance 3 (dist_sq = 9, within both drone range 5 and the
# tank's own range 4). Drone damage is 120 + roll(0,60) — floor 120 — so
# the heavy tank (350 hp) always survives to answer.
# Retaliation (tank -> infantry, armour 0/0/0):
#   dmg = 0.75*121 + roll(0,30) - 0 = 90.75 + [0,30]
#   then /4 for TANK-vs-INFANTRY (§3.3): [22, 30] — assault squad (100 hp)
#   survives too, so no chain is even superficially at stake here.
func test_drone_strike_provokes_retaliation_when_target_can_reach() -> void:
	var a: Unit = state.add_unit(1, 0, Vector2i(2, 2), 2)
	var t: Unit = state.add_unit(8, 1, Vector2i(5, 2), 6)
	state.begin_turn()
	state.refresh_vision(t.owner)
	assert_eq(Rules.distance_sq(a.pos, t.pos), 9)
	assert_eq(DroneCommand.create(a.id, t.id).validate(state), "")
	var assault_hp_before: int = a.hp
	var events: Array = DroneCommand.create(a.id, t.id).apply(state)
	assert_true(t.is_alive(), "120..180 шкоди << 350 hp важкого танка")
	var retaliation: Events.ShotRetaliated = _shot_retaliated(events)
	assert_not_null(retaliation, "танк дістає до дрон-відділення (dist_sq 9 <= 16) і відповідає")
	assert_eq(retaliation.attacker_id, t.id)
	assert_eq(retaliation.target_id, a.id)
	assert_true(a.hp < assault_hp_before)

# ---------------------------------------------------------------------------
# 9. THE hard constraint: a retaliation never provokes a further one.
#
# Two medium tanks well inside each other's range (dist_sq = 4, both live
# far above the ~34-66 per-shot damage from case 1) — if retaliation were
# implemented by recursively invoking FireCommand.apply(), this is exactly
# the configuration that would loop them into mutual annihilation. Assert
# there is exactly one ShotRetaliated in the whole exchange.
func test_retaliation_never_triggers_a_further_retaliation() -> void:
	var a: Unit = state.add_unit(5, 0, Vector2i(4, 4), 2)
	var t: Unit = state.add_unit(5, 1, Vector2i(6, 4), 6)
	state.begin_turn()
	state.refresh_vision(t.owner)
	var events: Array = FireCommand.create(a.id, t.id).apply(state)
	assert_eq(_count_retaliations(events), 1, "рівно одна відповідь — не ланцюг")
	assert_true(a.is_alive())
	assert_true(t.is_alive())
	assert_eq(a.ap, 0)
	assert_eq(t.ap, 0)
	assert_true(a.has_fired)
	assert_true(t.has_fired)

# ---------------------------------------------------------------------------
# 10. Гармата на граничній дальності більше не б'є безкарно (§3.3.1).
#
# Дві польові гармати (#9: атака 200, дальність 5, огляд 3, hp 200, лоб 15) на
# відстані рівно 5 (dist_sq 25). Огляд цілі (3) до атакувальника не дістає, і за
# старим правилом відповіді не було. Тепер влучання відкриває стрільця, а умова
# відповіді — лише дальність, клас і AP, як в оригіналі.
#
# Обидва постріли FRONT, бонусів немає: межі [135, 188] < 200 hp — обидві
# сторони переживають обмін.
func test_artillery_at_max_range_is_answered_by_a_gun_that_never_saw_it() -> void:
	var a: Unit = state.add_unit(9, 0, Vector2i(0, 0), 2)   # схід
	var t: Unit = state.add_unit(9, 1, Vector2i(5, 0), 6)   # захід — лоб до атакувальника
	state.begin_turn()
	# Огляд гармати (3) не дістає до 5 і для самого атакувальника, а предмет тесту —
	# знання ЦІЛІ, тож знання гравця 0 форсується явно.
	state.vision[0].seen.fill(1)
	state.refresh_vision(t.owner)
	assert_false(state.vision[t.owner].is_seen(a.pos),
		"передумова: ромб огляду 3 до (0,0) не дістає — гравець 1 цього тайла не розвідував")
	var attacker_hp_before: int = a.hp
	var events: Array = FireCommand.create(a.id, t.id).apply(state)
	assert_true(t.is_alive(), "188 макс. шкоди < 200 hp")
	assert_not_null(_shot_retaliated(events), "§3.3.1: влучання відкрило гармату — відповідь є")
	assert_true(a.hp < attacker_hp_before)

func test_retaliation_adds_to_the_retaliators_tally() -> void:
	var a: Unit = state.add_unit(5, 0, Vector2i(4, 4), 2)
	var t: Unit = state.add_unit(5, 1, Vector2i(6, 4), 6)
	state.begin_turn()
	state.refresh_vision(t.owner)
	var a_before: int = a.hp
	var t_before: int = t.hp
	FireCommand.create(a.id, t.id).apply(state)
	assert_true(a.hp < a_before, "передумова: відповідь була")
	assert_eq(state.damage_dealt[1], a_before - a.hp, "шкода відповіді — гравцю-відповідачу")
	assert_eq(state.damage_dealt[0], t_before - t.hp)

# ---------------------------------------------------------------------------
# §3.3.1: відповідь коштує AP лише до кінця ходу АТАКУВАЛЬНИКА. У грі на трьох
# наступний хід — іншого суперника, і відповідач мусить мати чим відповісти й
# йому, якщо до першої відповіді мав >= fire_cost.
#
# Важкий танк (#8: ap 40, fire_cost 20, hp 350, огляд 4, дальність 4) гравця 0 на
# (5,5); середні танки (#5: atk 95) гравця 1 на (5,2)/(4,2) і гравця 2 на (5,8) —
# у ромбі огляду й у радіусі. Шкода середнього (до ~66 у лоб, до ~95+ у борт) не
# вбиває 350 hp ні з першого, ні з другого пострілу.

func _three_player_heavy() -> Dictionary:
	var s: BattleState = BattleState.create(Board.create(16, 16, Terrain.GroundState.DRY), 3, 11)
	var heavy: Unit = s.add_unit(8, 0, Vector2i(5, 5), 0)
	var p1: Unit = s.add_unit(5, 1, Vector2i(5, 2), 4)
	var p1b: Unit = s.add_unit(5, 1, Vector2i(4, 2), 4)
	var p2: Unit = s.add_unit(5, 2, Vector2i(5, 8), 0)
	s.start()
	s.active_player = 1
	s.begin_turn()
	return {"state": s, "heavy": heavy, "p1": p1, "p1b": p1b, "p2": p2}

func test_a_retaliator_answers_the_next_opponent_in_a_three_player_game() -> void:
	var f: Dictionary = _three_player_heavy()
	var s: BattleState = f["state"]
	var heavy: Unit = f["heavy"]
	assert_eq(_count_retaliations(FireCommand.create(f["p1"].id, heavy.id).apply(s)), 1,
		"передумова: важкий відповідає гравцю 1")
	assert_eq(heavy.ap, 0, "передумова: відповідь забрала AP на хід атакувальника")
	EndTurnCommand.create().apply(s)
	assert_eq(s.active_player, 2, "передумова: хід гравця 2, а не власника танка")
	assert_eq(heavy.ap, 40, "після ходу атакувальника AP повертається до стану перед відповіддю")
	var events: Array = FireCommand.create(f["p2"].id, heavy.id).apply(s)
	assert_eq(_count_retaliations(events), 1, "важкий відповідає й гравцю 2")

func test_a_retaliator_still_cannot_answer_twice_in_the_same_attackers_turn() -> void:
	var f: Dictionary = _three_player_heavy()
	var s: BattleState = f["state"]
	var heavy: Unit = f["heavy"]
	assert_eq(_count_retaliations(FireCommand.create(f["p1"].id, heavy.id).apply(s)), 1, "передумова")
	var events: Array = FireCommand.create(f["p1b"].id, heavy.id).apply(s)
	assert_eq(_count_retaliations(events), 0, "другий постріл того самого ходу — без відповіді")

func test_concede_also_returns_the_retaliators_ap() -> void:
	var f: Dictionary = _three_player_heavy()
	var s: BattleState = f["state"]
	var heavy: Unit = f["heavy"]
	FireCommand.create(f["p1"].id, heavy.id).apply(s)
	ConcedeCommand.create().apply(s)
	assert_eq(s.active_player, 2, "передумова: хід перейшов до гравця 2")
	assert_eq(heavy.ap, 40, "хід атакувальника скінчився здачею — і AP так само повертається")

func test_the_ap_returned_is_what_the_retaliator_had_not_a_refill() -> void:
	# Повне AP (40) не відрізняє повернення від поповнення. 25 — частковий залишок
	# власного ходу (>= fire_cost 20, тож відповідь можлива): повернутися мусить
	# рівно 25, а не max_ap.
	var f: Dictionary = _three_player_heavy()
	var s: BattleState = f["state"]
	var heavy: Unit = f["heavy"]
	heavy.ap = 25
	assert_eq(_count_retaliations(FireCommand.create(f["p1"].id, heavy.id).apply(s)), 1, "передумова: 25 >= 20 — відповідає")
	EndTurnCommand.create().apply(s)
	assert_eq(s.active_player, 2, "передумова")
	assert_eq(heavy.ap, 25, "повертається залишок перед відповіддю, а не повний запас")

func test_a_spent_unit_that_did_not_retaliate_stays_spent_on_the_next_opponents_turn() -> void:
	# Юніт гравця 0, що витратив усе на власному ході й ні на що не відповідав, на
	# ході гравця 2 лишається з 0: pass_turn() повертає лише відповідачам.
	var f: Dictionary = _three_player_heavy()
	var s: BattleState = f["state"]
	var spent: Unit = s.add_unit(5, 0, Vector2i(14, 14), 0)
	spent.ap = 0
	EndTurnCommand.create().apply(s)
	assert_eq(s.active_player, 2, "передумова")
	assert_eq(spent.ap, 0, "без відповіді нема чого повертати")

func test_a_retaliator_killed_later_that_turn_keeps_no_stale_record() -> void:
	# Відповів, а тоді загинув від другого пострілу того самого ходу: запис про AP
	# мертвого юніта не має пережити кінець ходу (і потрапити у збереження).
	var f: Dictionary = _three_player_heavy()
	var s: BattleState = f["state"]
	var heavy: Unit = f["heavy"]
	assert_eq(_count_retaliations(FireCommand.create(f["p1"].id, heavy.id).apply(s)), 1, "передумова")
	heavy.hp = 1
	FireCommand.create(f["p1b"].id, heavy.id).apply(s)
	assert_false(heavy.is_alive(), "передумова: другий постріл добиває")
	EndTurnCommand.create().apply(s)
	assert_eq(heavy.ap_before_retaliation, -1, "мертвий відповідач без застарілого запису")

# ---------------------------------------------------------------------------
# §3.10 + §3.3.1: вибуття від ВІДПОВІДІ. Атакувальник має 1 hp, а мінімальна
# шкода — 10 (§3.3), тож відповідь танка, який вижив (400 hp), убиває його
# напевно, хай що випаде на кубиках.

func _has_event(events: Array, cls: Variant) -> bool:
	for e in events:
		if is_instance_of(e, cls):
			return true
	return false

func _eliminated_players(events: Array) -> Array[int]:
	var out: Array[int] = []
	for e in events:
		if e is Events.PlayerEliminated:
			out.append(e.player)
	return out

func test_attacker_last_unit_killed_by_retaliation_ends_two_player_match() -> void:
	var a: Unit = state.add_unit(5, 0, Vector2i(4, 4), 2)
	var t: Unit = state.add_unit(5, 1, Vector2i(6, 4), 6)
	state.begin_turn()
	state.refresh_vision(t.owner)
	a.hp = 1

	var events: Array = FireCommand.create(a.id, t.id).apply(state)

	assert_not_null(_shot_retaliated(events), "передумова: ціль відповіла")
	assert_false(a.is_alive(), "відповідь добила останній юніт атакувальника")
	assert_eq(_eliminated_players(events), [0] as Array[int], "вибув той, хто стріляв")
	var ended: Events.MatchEnded = null
	for e in events:
		if e is Events.MatchEnded:
			ended = e
	assert_not_null(ended, "§3.10: на двох — кінець матчу тим самим обміном")
	assert_eq(ended.winner, 1, "переміг захисник")
	assert_eq(state.winner, 1)
	assert_eq(EndTurnCommand.create().validate(state), "ERR_MATCH_OVER", "після кінця матчу ходів більше немає")

func test_active_player_eliminated_by_retaliation_in_three_player_match_passes_on() -> void:
	state = BattleState.create(Board.create(16, 16, Terrain.GroundState.DRY), 3, 11)
	state.active_player = 0
	var a: Unit = state.add_unit(5, 0, Vector2i(4, 4), 2)
	var t: Unit = state.add_unit(5, 1, Vector2i(6, 4), 6)
	var bystander: Unit = state.add_unit(5, 2, Vector2i(14, 14), 6)
	state.begin_turn()
	state.refresh_vision(t.owner)
	a.hp = 1

	var events: Array = FireCommand.create(a.id, t.id).apply(state)

	assert_false(a.is_alive())
	assert_eq(_eliminated_players(events), [0] as Array[int], "вибув активний гравець — на власному ході")
	assert_false(_has_event(events, Events.MatchEnded), "на трьох матч триває: живі ще двоє")
	assert_false(state.is_over())
	# Пінуємо нинішню поведінку: хід сам не переходить — вибулий лишається активним,
	# доки не натисне «Кінець ходу». Діяти він не може (юнітів немає), а сам кінець
	# ходу йому дозволено.
	assert_eq(state.active_player, 0, "хід не передається автоматично")
	assert_eq(state.units_of(0).size(), 0, "діяти вибулому нічим")
	assert_eq(EndTurnCommand.create().validate(state), "", "вибулий може (і мусить) закінчити хід")

	EndTurnCommand.create().apply(state)
	assert_eq(state.active_player, 1, "хід переходить до наступного живого")
	EndTurnCommand.create().apply(state)
	assert_eq(state.active_player, 2)
	var turn_before: int = state.turn_number
	EndTurnCommand.create().apply(state)
	assert_eq(state.active_player, 1, "вибулого гравця 0 коло пропускає")
	assert_eq(state.turn_number, turn_before + 1, "коло замкнулося — новий хід")
	assert_true(bystander.is_alive() and t.is_alive())
