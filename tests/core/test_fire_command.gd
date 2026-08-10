extends GutTest

var state: BattleState

func before_each() -> void:
	state = BattleState.create(Board.create(12, 12, Terrain.GroundState.DRY), 2, 7)
	state.active_player = 0

func test_fire_deals_damage_and_zeroes_ap() -> void:
	var a: Unit = state.add_unit(5, 0, Vector2i(4, 4), 2)
	var t: Unit = state.add_unit(2, 1, Vector2i(6, 4), 2)
	state.begin_turn()
	var before: int = t.hp
	assert_eq(FireCommand.create(a.id, t.id).validate(state), "")
	FireCommand.create(a.id, t.id).apply(state)
	assert_true(t.hp < before)
	assert_eq(a.ap, 0, "§3.2: постріл обнуляє AP")
	assert_true(a.has_fired)

func test_fire_emits_shot_then_damage() -> void:
	var a: Unit = state.add_unit(5, 0, Vector2i(4, 4), 2)
	var t: Unit = state.add_unit(2, 1, Vector2i(6, 4), 2)
	state.begin_turn()
	var events: Array = FireCommand.create(a.id, t.id).apply(state)
	assert_true(events[0] is Events.ShotFired)
	assert_true(events[1] is Events.DamageDealt)

func test_out_of_range_is_rejected() -> void:
	var a: Unit = state.add_unit(5, 0, Vector2i(0, 0), 2)   # range 4
	var t: Unit = state.add_unit(2, 1, Vector2i(11, 11), 2)
	state.begin_turn()
	assert_eq(FireCommand.create(a.id, t.id).validate(state), "ERR_OUT_OF_RANGE")

func test_range_is_the_circle_and_not_the_vision_diamond() -> void:
	# §3.1: дальність міряється КОЛОМ (dist_sq <= r*r), огляд — ромбом. Дві форми
	# розходяться саме на діагоналях, тож пін потрібен на цілі, яка лежить у колі
	# й поза ромбом того самого радіуса.
	#
	# Гармата (#9: дальність 5, огляд 3) у (2,2), ціль у (5,6): зсув (3,4), тобто
	# 9 + 16 = 25 <= 25 у колі, але 3 + 4 = 7 > 5 у ромбі. Власного огляду гармати
	# (3) сюди не вистачає, тож законним постріл робить стрілецьке відділення —
	# §3.3.1: постріл гейтиться мережею власника, а не зором самого стрільця.
	var gun: Unit = state.add_unit(9, 0, Vector2i(2, 2), 2)
	var t: Unit = state.add_unit(5, 1, Vector2i(5, 6), 2)
	state.add_unit(0, 0, Vector2i(5, 4), 2)   # коригувальник: огляд 5, до цілі 2
	state.begin_turn()

	assert_true(Rules.in_radius(gun.pos, t.pos, gun.attack_range()), "передумова: у колі дальності 5")
	assert_false(Rules.in_vision_diamond(gun.pos, t.pos, gun.attack_range()),
		"передумова: поза ромбом того ж радіуса — саме тут дві форми розходяться")
	assert_true(state.vision[0].is_seen(t.pos), "передумова: коригувальник розвідав тайл цілі")

	assert_eq(FireCommand.create(gun.id, t.id).validate(state), "",
		"§3.1: дальність — коло; ромб огляду тут не при чому")


func test_invisible_target_cannot_be_shot() -> void:
	# §3.5: гейт — РОЗВІДАНА земля (seen), а не чийсь ромб просто зараз. Арта (огляд 3)
	# сама до (4,0) не дістає оком, ходів ще не було, тож цей тайл гравець 0 не
	# розвідував жодного разу — і саме тому пострілу немає. Над розвіданою землею
	# та сама геометрія дала б законний постріл: див.
	# test_a_tile_scouted_earlier_stays_shootable_with_nobody_watching().
	var a: Unit = state.add_unit(9, 0, Vector2i(0, 0), 2)   # арта, vision 3, range 5
	var t: Unit = state.add_unit(2, 1, Vector2i(4, 0), 2)
	state.begin_turn()
	assert_false(state.vision[0].is_seen(t.pos), "передумова: тайл цілі не розвідано")
	assert_eq(FireCommand.create(a.id, t.id).validate(state), "ERR_TARGET_NOT_VISIBLE",
		"§3.5: стріляти можна лише по землі, яку ти хоч раз розвідав")

# --- §3.5: розвідка незворотна ----------------------------------------------------
#
# Спільна геометрія наступної пари. Гармата (#9: дальність 5, огляд 3) стоїть на
# (5,10); ворожий середній танк — на (5,5), тобто dist_sq 25 <= 25 у колі дальності
# і 5 > 3 поза власним оком гармати. Стрілецьке відділення (#0, огляд 5) на (5,1)
# накриває (5,5) ромбом 4 і потім ЙДЕ ГЕТЬ: 3 тайли поля по 10 AP з наявних 30, і
# з (2,1) до танка вже 3 + 4 = 7 > 5. Після цього танка не бачить НІХТО з гравця 0.
#
# Різниця між двома тестами рівно одна — чи було відділення на дошці. Це і є ціна
# правила: розвідка купується один раз і не повертається.

func test_a_tile_scouted_earlier_stays_shootable_with_nobody_watching() -> void:
	var gun: Unit = state.add_unit(9, 0, Vector2i(5, 10), 0)
	var t: Unit = state.add_unit(5, 1, Vector2i(5, 5), 0)
	var scout: Unit = state.add_unit(0, 0, Vector2i(5, 1), 4)
	state.start()
	state.begin_turn()
	assert_true(state.vision[0].is_seen(t.pos), "передумова: розвідник накрив тайл танка")

	MoveCommand.create(scout.id, Vector2i(2, 1), -1).apply(state)
	assert_eq(scout.pos, Vector2i(2, 1), "передумова: 3 тайли поля по 10 — рівно 30 AP")
	assert_false(state.vision[0].is_visible(t.pos),
		"передумова: за танком більше не стежить ніхто — ані розвідник, ані гармата (5 > 3)")
	assert_true(state.vision[0].is_seen(t.pos), "§3.5: розвідане лишається розвіданим")

	var before: int = t.hp
	assert_eq(FireCommand.create(gun.id, t.id).validate(state), "",
		"§3.5: по ворогові на давно розвіданій землі стріляти можна без жодного ока поруч")
	FireCommand.create(gun.id, t.id).apply(state)
	assert_true(t.hp < before, "і постріл справді доходить")
	assert_true(t.is_alive(), "макс. ~300 шкоди проти 400 hp — танк виживає, це не предмет тесту")

func test_the_same_shot_is_illegal_over_ground_nobody_ever_scouted() -> void:
	# Та сама пара, без розвідника. Єдина причина відмови — (5,5) не бачив ніхто й
	# ніколи: саме на такій землі §3.3.1 і лишає безкарність.
	var gun: Unit = state.add_unit(9, 0, Vector2i(5, 10), 0)
	var t: Unit = state.add_unit(5, 1, Vector2i(5, 5), 0)
	state.start()
	state.begin_turn()

	assert_true(Rules.in_radius(gun.pos, t.pos, gun.attack_range()), "передумова: у колі дальності 5")
	assert_false(state.vision[0].is_seen(t.pos), "передумова: землі під танком не розвідували")
	assert_eq(FireCommand.create(gun.id, t.id).validate(state), "ERR_TARGET_NOT_VISIBLE",
		"§3.5: нерозвідана земля — єдине, що лишилося непроглядним")


func test_friendly_fire_is_rejected() -> void:
	var a: Unit = state.add_unit(5, 0, Vector2i(4, 4), 2)
	var f: Unit = state.add_unit(5, 0, Vector2i(5, 4), 2)
	state.begin_turn()
	assert_eq(FireCommand.create(a.id, f.id).validate(state), "ERR_FRIENDLY_FIRE")

func test_engineer_cannot_fire() -> void:
	var e: Unit = state.add_unit(11, 0, Vector2i(4, 4), 2)
	var t: Unit = state.add_unit(2, 1, Vector2i(5, 4), 2)
	state.begin_turn()
	assert_eq(FireCommand.create(e.id, t.id).validate(state), "ERR_NO_WEAPON", "§3.6: інженер не має зброї")

func test_second_shot_in_a_turn_is_rejected() -> void:
	var a: Unit = state.add_unit(5, 0, Vector2i(4, 4), 2)
	var t: Unit = state.add_unit(2, 1, Vector2i(6, 4), 2)
	state.begin_turn()
	FireCommand.create(a.id, t.id).apply(state)
	assert_eq(FireCommand.create(a.id, t.id).validate(state), "ERR_ALREADY_FIRED")

func test_kill_emits_destruction_and_checks_victory() -> void:
	var a: Unit = state.add_unit(9, 0, Vector2i(4, 4), 2)
	var t: Unit = state.add_unit(2, 1, Vector2i(6, 4), 6)
	state.begin_turn()
	t.hp = 1
	var events: Array = FireCommand.create(a.id, t.id).apply(state)
	var destroyed: bool = false
	var ended: bool = false
	for e in events:
		if e is Events.UnitDestroyed:
			destroyed = true
		if e is Events.MatchEnded:
			ended = true
	assert_true(destroyed)
	assert_true(ended, "останній юніт супротивника — кінець матчу")

func test_damage_feeds_the_attackers_class_pool() -> void:
	var a: Unit = state.add_unit(5, 0, Vector2i(4, 4), 2)
	var t: Unit = state.add_unit(2, 1, Vector2i(6, 4), 2)
	state.begin_turn()
	FireCommand.create(a.id, t.id).apply(state)
	assert_true(state.experience[0].xp[UnitTypes.UnitClass.TANK] > 0)

func test_preview_reports_sector_and_bounds() -> void:
	var a: Unit = state.add_unit(5, 0, Vector2i(4, 4), 2)
	var t: Unit = state.add_unit(2, 1, Vector2i(6, 4), 2)   # дивиться на схід, атака зі заходу
	var p: Dictionary = FireCommand.preview(state, a.id, t.id)
	assert_eq(p["sector"], UnitTypes.ArmourSector.REAR)
	assert_eq(p["min"], 61, "нижня межа — нульовий кидок атаки і максимальний кидок броні")
	assert_eq(p["max"], 86, "верхня межа — максимальний кидок атаки і нульовий кидок броні")

func test_preview_bounds_bracket_every_real_roll() -> void:
	var a: Unit = state.add_unit(5, 0, Vector2i(4, 4), 2)
	var t: Unit = state.add_unit(2, 1, Vector2i(6, 4), 2)
	var p: Dictionary = FireCommand.preview(state, a.id, t.id)
	var sector: int = Rules.armour_sector(t.facing, t.pos, a.pos)
	var dist_sq: int = Rules.distance_sq(a.pos, t.pos)
	var level: int = state.experience[a.owner].level_of(a.unit_class())
	var seen_min: int = p["max"]
	var seen_max: int = p["min"]
	for s in 400:
		var rng := RandomNumberGenerator.new()
		rng.seed = s
		var dmg: int = Rules.compute_damage(rng, a, t, level, sector, dist_sq)
		assert_true(dmg >= p["min"] and dmg <= p["max"],
			"%d поза межами прев'ю [%d, %d]" % [dmg, p["min"], p["max"]])
		seen_min = mini(seen_min, dmg)
		seen_max = maxi(seen_max, dmg)
	assert_eq(seen_min, p["min"], "нижня межа має бути реально досяжною, не лише теоретичною")
	assert_eq(seen_max, p["max"], "верхня межа має бути реально досяжною, не лише теоретичною")

func test_preview_does_not_disturb_the_rng() -> void:
	var a: Unit = state.add_unit(5, 0, Vector2i(4, 4), 2)
	var t: Unit = state.add_unit(2, 1, Vector2i(6, 4), 2)
	var before: int = Rules.roll(state.rng, 1000)
	state.rng.seed = state.seed_value
	Rules.roll(state.rng, 1000)
	FireCommand.preview(state, a.id, t.id)
	var after: int = Rules.roll(state.rng, 1000)
	state.rng.seed = state.seed_value
	Rules.roll(state.rng, 1000)
	assert_eq(after, Rules.roll(state.rng, 1000), "прев'ю не має споживати кидки")
