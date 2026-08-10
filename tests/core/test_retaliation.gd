extends GutTest
## §3.3.1: ціль, яка вижила після пострілу, стріляє у відповідь тим самим
## обміном. Числа нижче виведені вручну з ростеру (CLAUDE.md §3.6) і формули
## шкоди (§3.3) — див. звіт задачі 1.14b.

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
	state.refresh_vision(t.owner)  # §3.3.1: відповідач мусить бачити атакувальника власним зором
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
	state.vision[0].visible.fill(1)  # дальність, не зір, — предмет цього тесту
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
# відділеннями (#0, огляд 5), по одному на гравця: §3.3.1 гейтить і постріл, і
# відповідь на МЕРЕЖУ власника, а не на зір самого стрільця.
#
# Обидва дивляться на схід (facing 2), тож перший постріл лягає в REAR цілі, а
# відповідь — у FRONT атакувальника:
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
	assert_true(state.vision[t.owner].is_visible(a.pos), "передумова: мережа відповідача атакувальника бачить")
	assert_eq(FireCommand.create(a.id, t.id).validate(state), "", "передумова: постріл законний")

	var attacker_hp_before: int = a.hp
	var events: Array = FireCommand.create(a.id, t.id).apply(state)
	assert_true(t.is_alive(), "80 макс. шкоди << 400 hp — є кому відповідати")
	assert_not_null(_shot_retaliated(events), "§3.1: дальність відповіді — коло, а не ромб")
	assert_true(a.hp < attacker_hp_before, "відповідь мусить дійти")

# ---------------------------------------------------------------------------
# 5. An engineer never retaliates, even with AP and range to spare.
#
# Rifle squad (#0, INFANTRY) fires at an adjacent engineer squad (#11,
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
# 7. Retaliation damage feeds the retaliator's own class veterancy pool.
func test_retaliation_damage_feeds_retaliators_class_pool() -> void:
	var a: Unit = state.add_unit(5, 0, Vector2i(4, 4), 2)
	var t: Unit = state.add_unit(5, 1, Vector2i(6, 4), 6)
	state.begin_turn()
	state.refresh_vision(t.owner)
	assert_eq(state.veterancy[1].xp[UnitTypes.UnitClass.TANK], 0)
	FireCommand.create(a.id, t.id).apply(state)
	assert_true(state.veterancy[1].xp[UnitTypes.UnitClass.TANK] > 0,
		"шкода від відповіді йде в пул власника-відповідача (гравець 1), а не стрільця")

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
# 10. §3.3.1 (revised): the retaliator must SEE the original attacker.
#
# This is a deliberate departure from the reference (class_1.java), which
# gates its counter-attack on AP, range and class alone and does not check
# vision at all — see CLAUDE.md §3.3.1/§4. Do not "correct" this back toward
# the reference.
#
# Same medium-tank pair as case 1 (dist_sq 4, well inside range 4 and vision
# 4, AP and class both satisfied) — everything but vision qualifies. For this
# class, vision radius (4) equals attack range (4), so an honestly-recomputed
# vision snapshot can never show "in range but unseen": any tile within the
# unit's own range is, by construction, also within its own vision the moment
# that vision is (re)computed. The only way to reach "in range, not seen" is
# a vision snapshot that was never (re)computed for the defender in the first
# place — precisely the state before that player's first turn. We construct
# it explicitly and say so, matching tests/core/test_drone_command.gd's
# test_invisible_target_is_rejected precedent.
func test_retaliator_that_cannot_see_the_attacker_does_not_retaliate() -> void:
	var a: Unit = state.add_unit(5, 0, Vector2i(4, 4), 2)
	var t: Unit = state.add_unit(5, 1, Vector2i(6, 4), 6)
	state.begin_turn()
	# Навмисно НЕ викликаємо state.refresh_vision(t.owner): для цього класу
	# (зір 4 == дальність 4) "у дальності, але не видно" ніколи не виникає з
	# чесно перерахованого зору — лише з того, що зір гравця 1 ще жодного разу
	# не рахувався (стан до його першого ходу). Гасимо явно, а не покладаємось
	# на дефолтний нуль BattleState.create(), щоб тест не зламався мовчки, якщо
	# дефолт колись зміниться.
	state.vision[t.owner].visible.fill(0)
	assert_false(state.vision[t.owner].is_visible(a.pos), "передумова: відповідач не бачить атакувальника")
	assert_true(t.ap >= t.fire_cost() and Rules.in_radius(t.pos, a.pos, t.attack_range()),
		"передумова: AP і дальність цілком дозволяли б відповідь")
	var attacker_hp_before: int = a.hp
	var events: Array = FireCommand.create(a.id, t.id).apply(state)
	assert_true(t.is_alive())
	assert_null(_shot_retaliated(events), "§3.3.1: без зору на атакувальника відповіді немає")
	assert_eq(a.hp, attacker_hp_before)

# ---------------------------------------------------------------------------
# 11. The case the rule exists for: artillery at max range takes no return
# fire, because the gun sits outside the target's sight even though it sits
# inside the target's own range.
#
# Two field guns (#9: atk 200, range 5, vision 3, hp 200, armour front 15)
# face each other at distance exactly 5 (dist_sq = 25) — reachable by
# perfectly honest play, no fog hack needed:
#   - attacker's shot: 25 <= 5^2 = 25, in range.
#   - target's own range is also 5, so 25 <= 25 — in range to retaliate.
#   - target's own vision is 3, so 25 > 3^2 = 9 — NOT visible. That mismatch
#     (range 5, vision 3) is exactly CLAUDE.md §3.3.1's own example: "two guns
#     at range 5 do not trade, because neither sees the other."
#
# Opening shot, FRONT sector (target faces the attacker), artillery-vs-
# artillery (no TANK bonus, no minimum-range halving at dist_sq 25, target
# not a light vehicle):
#   dmg = 0.75*200 + roll(0,50) - (0.75*15 + roll(0,3))
#       = 150 - 11.25 + [0,50] - [0,3] = 138.75 + [0,50] - [0,3]
#   bounds: [135, 188] — always < 200 hp, target survives to (fail to) reply.
func test_artillery_at_max_range_takes_no_return_fire_because_target_cannot_see_it() -> void:
	var a: Unit = state.add_unit(9, 0, Vector2i(0, 0), 2)   # схід
	var t: Unit = state.add_unit(9, 1, Vector2i(5, 0), 6)   # захід — лоб до атакувальника
	state.begin_turn()
	# Гарматний зір (3) не дістає до відстані 5 і для самого атакувальника —
	# те саме, чому у case 4 (test_attacker_outside_retaliators_range...)
	# зір гравця 0 форсується вручну: предмет цього тесту — зір ЦІЛІ, не
	# зір атакувальника, тож той гейт треба прибрати з дороги явно.
	state.vision[0].visible.fill(1)
	state.refresh_vision(t.owner)  # зір гравця 1 чесно порахований — і все одно не дістає до 25
	assert_eq(Rules.distance_sq(a.pos, t.pos), 25)
	assert_eq(FireCommand.create(a.id, t.id).validate(state), "")
	assert_true(Rules.in_radius(t.pos, a.pos, t.attack_range()), "передумова: у межах дальності цілі")
	assert_false(state.vision[t.owner].is_visible(a.pos), "передумова: поза зором цілі (3^2=9 < 25)")
	var attacker_hp_before: int = a.hp
	var events: Array = FireCommand.create(a.id, t.id).apply(state)
	assert_true(t.is_alive(), "188 макс. шкоди < 200 hp")
	assert_null(_shot_retaliated(events), "§3.3.1: гармата поза зором цілі — відповіді немає")
	assert_eq(a.hp, attacker_hp_before)
