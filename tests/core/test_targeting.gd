extends GutTest
## §3.13. Дві вибірки для двох оверлеїв. Типи юнітів беруться з ростера (§3.6):
## 0 — стрілецьке відділення (дальність 3, огляд 5), 2 — бронеавтомобіль (3/3),
## 5 — середній танк (4/4), 9 — гармата (дальність 5, огляд 3), 11 — інженер.

var state: BattleState


func before_each() -> void:
	state = BattleState.create(Board.create(12, 12, Terrain.GroundState.DRY), 2, 7)
	state.active_player = 0


func _ids(units: Array[Unit]) -> Array[int]:
	var out: Array[int] = []
	for u in units:
		out.append(u.id)
	return out


# --- §3.1: обвідна вогню — перетин кола дальності та ромба огляду ---------------

func test_target_in_the_range_circle_but_outside_the_vision_diamond_is_not_a_target() -> void:
	# Танк: дальність 4 (коло) і огляд 4 (ромб). Зсув (3, 2) лежить у колі
	# (9 + 4 = 13 <= 16) і поза ромбом (3 + 2 = 5 > 4). Якби огляд був колом —
	# ціль потрапила б у список, і оверлей збрехав би про постріл.
	assert_true(Rules.in_radius(Vector2i(4, 4), Vector2i(7, 6), 4), "передумова: у колі дальності 4")
	assert_false(Rules.in_vision_diamond(Vector2i(4, 4), Vector2i(7, 6), 4), "передумова: поза ромбом огляду 4")

	var tank: Unit = state.add_unit(5, 0, Vector2i(4, 4), 2)
	var near: Unit = state.add_unit(2, 1, Vector2i(6, 4), 2)
	var diagonal: Unit = state.add_unit(2, 1, Vector2i(7, 6), 2)
	state.start()
	state.begin_turn()

	var ids: Array[int] = _ids(Targeting.firing_targets(state, tank.id))
	assert_has(ids, near.id, "ціль у колі й у ромбі — стріляти можна")
	assert_does_not_have(ids, diagonal.id, "§3.1: у дальності, але поза оглядом — не ціль")


func test_threat_forecast_stops_at_the_vision_diamond_too() -> void:
	# Дзеркало попереднього тесту для другої функції: та сама діагональ, той самий
	# перетин двох форм, тільки очима оглянутого ворога.
	var enemy: Unit = state.add_unit(5, 1, Vector2i(4, 4), 2)
	var spotter: Unit = state.add_unit(0, 0, Vector2i(4, 7), 2)    # огляд 5 — бачить ворога
	var diagonal: Unit = state.add_unit(5, 0, Vector2i(7, 6), 2)   # зсув (3, 2) від ворога
	state.start()
	state.begin_turn()

	var ids: Array[int] = _ids(Targeting.threatened_units(state, enemy.id, 0))
	assert_has(ids, spotter.id, "зсув (0, 3): у колі 4 і в ромбі 4 — під загрозою")
	assert_does_not_have(ids, diagonal.id, "§3.1: у колі дальності, поза ромбом огляду — не позначається")


# --- §3.13: AP перевіряється у своєму юніті й НЕ перевіряється у ворожому -------

func test_own_unit_that_has_fired_can_shoot_nobody() -> void:
	var tank: Unit = state.add_unit(5, 0, Vector2i(4, 4), 2)
	state.add_unit(2, 1, Vector2i(6, 4), 2)
	state.start()
	state.begin_turn()
	assert_eq(Targeting.firing_targets(state, tank.id).size(), 1, "передумова: постріл законний")

	tank.exhaust()
	assert_eq(Targeting.firing_targets(state, tank.id).size(), 0, "§3.2: після пострілу — нічого")

	# exhaust() гасить і прапорець, і AP, тож сам по собі він не показує, ЯКА з
	# двох умов спрацювала. Розводимо їх: повний AP при піднятому has_fired —
	# стан, якого в грі не буває, але саме він ізолює перевірку прапорця.
	tank.ap = tank.max_ap()
	assert_eq(Targeting.firing_targets(state, tank.id).size(), 0, "§3.2: один постріл за хід, навіть із повним AP")


func test_own_unit_below_fire_cost_can_shoot_nobody() -> void:
	var tank: Unit = state.add_unit(5, 0, Vector2i(4, 4), 2)
	state.add_unit(2, 1, Vector2i(6, 4), 2)
	state.start()
	state.begin_turn()

	tank.has_fired = false
	tank.ap = tank.fire_cost() - 1
	assert_eq(Targeting.firing_targets(state, tank.id).size(), 0, "§3.2: не вистачає AP на постріл")


func test_enemy_threat_ignores_the_enemys_ap_and_fired_flag() -> void:
	# §3.13: AP ворога — це залишок дій, яких гравець міг не бачити (відповідь на
	# чужому ході, за ширмою передачі пристрою). До свого ходу ворог однаково
	# матиме повний AP, тож прогноз загрози не має права на це дивитися.
	var enemy: Unit = state.add_unit(5, 1, Vector2i(4, 4), 2)
	var mine: Unit = state.add_unit(5, 0, Vector2i(6, 4), 2)
	state.start()
	state.begin_turn()

	enemy.exhaust()
	var ids: Array[int] = _ids(Targeting.threatened_units(state, enemy.id, 0))
	assert_has(ids, mine.id, "§3.13: AP оглянутого ворога навмисно не перевіряється")


# --- §3.13: прогноз рахується ОДНИМ юнітом, а не мережею його власника ----------

func test_threat_does_not_widen_when_the_enemy_has_a_spotter() -> void:
	# Антивитік, найважливіший тест файлу. Гармата (дальність 5, огляд 3) дістає
	# мій танк за 5 тайлів, але сама його не бачить. Її власник бачить — його
	# піхота стоїть поруч із моїм танком. Якби прогноз брав state.vision[owner],
	# позначка на танку видала б існування розвідника, якого я не знайшов.
	var gun: Unit = state.add_unit(9, 1, Vector2i(2, 2), 2)
	state.add_unit(0, 1, Vector2i(7, 4), 2)                     # ворожий коригувальник, огляд 5
	var my_eyes: Unit = state.add_unit(0, 0, Vector2i(2, 5), 2) # моя піхота бачить гармату
	var far_tank: Unit = state.add_unit(5, 0, Vector2i(7, 2), 2)
	state.start()
	state.begin_turn()

	assert_true(Rules.in_radius(gun.pos, far_tank.pos, gun.attack_range()), "передумова: танк у дальності гармати")
	assert_false(Rules.in_vision_diamond(gun.pos, far_tank.pos, gun.vision()), "передумова: гармата його не бачить")
	assert_true(state.vision[1].is_visible(far_tank.pos), "передумова: МЕРЕЖА супротивника танк бачить")

	var ids: Array[int] = _ids(Targeting.threatened_units(state, gun.id, 0))
	assert_has(ids, my_eyes.id, "у дальності та у власному ромбі гармати — під загрозою")
	assert_does_not_have(ids, far_tank.id,
		"§3.13: прогноз рахується власним оглядом гармати; мережа власника — прихована інформація")


func test_invisible_enemy_cannot_be_inspected() -> void:
	# §3.13: «юніт, якого ти не бачиш, оглянути не можна». Стрілецьке відділення
	# бачить на 5, моя гармата — лише на 3, тож на манхеттенській відстані 4 воно
	# тримає мене на прицілі, а я його не бачу взагалі.
	var enemy: Unit = state.add_unit(0, 1, Vector2i(4, 4), 2)
	var my_gun: Unit = state.add_unit(9, 0, Vector2i(6, 6), 2)
	state.start()
	state.begin_turn()

	assert_true(Rules.in_radius(enemy.pos, my_gun.pos, enemy.attack_range()), "передумова: гармата у дальності 3")
	assert_true(Rules.in_vision_diamond(enemy.pos, my_gun.pos, enemy.vision()), "передумова: і у ромбі огляду 5")
	assert_false(state.vision[0].is_visible(enemy.pos), "передумова: я цього ворога не бачу")
	assert_eq(Targeting.threatened_units(state, enemy.id, 0).size(), 0, "§3.13: туман діє і на огляд ворога")

	# А щойно ворог стає видимим — прогноз зʼявляється.
	state.add_unit(0, 0, Vector2i(4, 8), 2)   # моя піхота, огляд 5
	state.start()
	assert_true(state.vision[0].is_visible(enemy.pos), "передумова: тепер бачу")
	assert_has(_ids(Targeting.threatened_units(state, enemy.id, 0)), my_gun.id)


func test_own_units_are_never_a_threat_to_their_owner() -> void:
	var gun: Unit = state.add_unit(9, 1, Vector2i(2, 2), 2)
	state.add_unit(0, 1, Vector2i(3, 2), 2)
	state.start()
	assert_eq(Targeting.threatened_units(state, gun.id, 1).size(), 0,
		"свої своїх не обстрілюють — прогнозувати нема чого")


# --- §3.6: інженер без зброї -----------------------------------------------------

func test_engineer_has_no_targets() -> void:
	var eng: Unit = state.add_unit(11, 0, Vector2i(4, 4), 2)
	var enemy: Unit = state.add_unit(2, 1, Vector2i(5, 4), 2)
	state.start()
	state.begin_turn()

	assert_true(Rules.in_radius(eng.pos, enemy.pos, eng.attack_range()), "передумова: сусідній тайл — у «дальності» 1")
	assert_true(state.vision[0].is_visible(enemy.pos), "передумова: ворог видимий")
	assert_eq(Targeting.firing_targets(state, eng.id).size(), 0, "§3.6: у інженера немає зброї")


func test_enemy_engineer_threatens_nobody() -> void:
	var eng: Unit = state.add_unit(11, 1, Vector2i(4, 4), 2)
	state.add_unit(5, 0, Vector2i(5, 4), 2)
	state.start()
	state.begin_turn()

	assert_true(state.vision[0].is_visible(eng.pos), "передумова: інженера видно")
	assert_eq(Targeting.threatened_units(state, eng.id, 0).size(), 0, "§3.6: інженер нікому не загрожує")


# --- мертві ----------------------------------------------------------------------

func test_a_destroyed_unit_is_never_returned() -> void:
	var shooter: Unit = state.add_unit(5, 0, Vector2i(4, 4), 2)
	var other: Unit = state.add_unit(5, 0, Vector2i(4, 5), 2)
	var victim: Unit = state.add_unit(2, 1, Vector2i(6, 4), 2)
	state.add_unit(2, 1, Vector2i(11, 11), 2)   # щоб матч не скінчився і не змазав причину
	state.start()
	state.begin_turn()

	victim.hp = 1
	FireCommand.create(shooter.id, victim.id).apply(state)
	assert_false(victim.is_alive(), "передумова: ціль знищено")
	assert_false(state.is_over(), "передумова: матч триває")

	assert_does_not_have(_ids(Targeting.firing_targets(state, other.id)), victim.id, "по мертвому не стріляють")
	assert_eq(Targeting.threatened_units(state, victim.id, 0).size(), 0, "мертвий ворог не загрожує")


# --- збіг з FireCommand.validate() -----------------------------------------------

func test_firing_targets_agrees_with_fire_command_validate() -> void:
	var tank: Unit = state.add_unit(5, 0, Vector2i(4, 4), 2)
	state.add_unit(2, 1, Vector2i(6, 4), 2)
	state.add_unit(2, 1, Vector2i(7, 6), 2)
	state.add_unit(2, 1, Vector2i(11, 11), 2)
	state.add_unit(5, 0, Vector2i(3, 4), 2)
	state.start()
	state.begin_turn()

	var ids: Array[int] = _ids(Targeting.firing_targets(state, tank.id))
	for u in state.alive_units():
		var legal: bool = FireCommand.create(tank.id, u.id).validate(state) == ""
		assert_eq(ids.has(u.id), legal, "оверлей і validate() мусять збігатися для юніта %d" % u.id)


func test_a_unit_of_the_idle_player_has_no_targets() -> void:
	var theirs: Unit = state.add_unit(5, 1, Vector2i(4, 4), 2)
	state.add_unit(5, 0, Vector2i(6, 4), 2)
	state.start()
	state.begin_turn()

	assert_eq(state.active_player, 0, "передумова: хід не їхній")
	assert_eq(Targeting.firing_targets(state, theirs.id).size(), 0,
		"не свій хід — стріляти не можна, і оверлей це повторює")


# --- чистота ---------------------------------------------------------------------

func test_queries_do_not_touch_the_state() -> void:
	var tank: Unit = state.add_unit(5, 0, Vector2i(4, 4), 2)
	var enemy: Unit = state.add_unit(5, 1, Vector2i(6, 4), 2)
	state.start()
	state.begin_turn()

	var rng_state: int = state.rng.state
	var before: Array = [tank.ap, tank.hp, tank.has_fired, enemy.ap, enemy.hp, enemy.has_fired]

	var first: Array[int] = _ids(Targeting.firing_targets(state, tank.id))
	var first_threat: Array[int] = _ids(Targeting.threatened_units(state, enemy.id, 0))
	var second: Array[int] = _ids(Targeting.firing_targets(state, tank.id))
	var second_threat: Array[int] = _ids(Targeting.threatened_units(state, enemy.id, 0))

	assert_eq(first, second, "запит детермінований")
	assert_eq(first_threat, second_threat, "запит детермінований")
	assert_eq([tank.ap, tank.hp, tank.has_fired, enemy.ap, enemy.hp, enemy.has_fired], before, "запит нічого не мутує")
	assert_eq(state.rng.state, rng_state, "запит не чіпає RNG матчу")
