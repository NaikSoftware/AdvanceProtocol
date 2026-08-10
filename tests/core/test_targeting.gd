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
	# Хід — гравця 1, інакше запит зупинила б охорона observer != active_player, і
	# тест доводив би не те: перевіряти треба саме гілку «свій юніт».
	state.active_player = 1
	assert_eq(Targeting.threatened_units(state, gun.id, 1).size(), 0,
		"свої своїх не обстрілюють — прогнозувати нема чого")


func test_forecast_refuses_an_observer_who_is_not_the_active_player() -> void:
	# Антивитік. observer — це «хто дивиться на дошку», а дивиться рівно активний
	# гравець. Підставивши супротивника, викликач проскакував повз перевірку
	# e.owner == observer, читав ЧУЖУ мережу і отримував units_of(супротивника) —
	# живі юніти ворога на справжніх позиціях, тобто рівно те, що §3.13 забороняє.
	var mine: Unit = state.add_unit(5, 0, Vector2i(4, 4), 2)
	var theirs: Unit = state.add_unit(2, 1, Vector2i(6, 4), 2)
	state.start()
	state.begin_turn()

	assert_eq(state.active_player, 0, "передумова: хід мій")
	assert_has(_ids(Targeting.threatened_units(state, theirs.id, 0)), mine.id,
		"передумова: у чесний бік запит працює")
	assert_true(state.vision[1].is_visible(mine.pos),
		"передумова: мережа супротивника мій танк бачить — тільки охорона й тримає цей запит")

	assert_eq(Targeting.threatened_units(state, mine.id, 1).size(), 0,
		"§3.13: чужим observer не буває — мережу супротивника читати не можна")


func test_drone_forecast_refuses_an_observer_who_is_not_the_active_player() -> void:
	# Дзеркало попереднього тесту для дронового прогнозу — та сама діра.
	var squad: Unit = state.add_unit(1, 0, Vector2i(2, 2), 2)
	var theirs: Unit = state.add_unit(5, 1, Vector2i(5, 2), 2)
	state.start()
	state.begin_turn()

	assert_true(state.vision[1].is_visible(squad.pos), "передумова: мережа супротивника загін бачить")
	assert_true(UnitTypes.is_vehicle(theirs.unit_class()), "передумова: танк — законна ціль дрона")
	assert_eq(Targeting.drone_threatened_units(state, squad.id, 1).size(), 0,
		"§3.13: і дроновий прогноз не віддає чужу мережу")


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

	# Через validate(), а не лише через запит. firing_targets() перебирає
	# state.alive_units(), тож мертвої цілі він не побачив би й без перевірки
	# всередині check_shot() — сам по собі він цю умову не прикриває, і прибрана
	# перевірка живості лишила б FireCommand.validate() здатним прийняти труп.
	# Тому головне твердження тут — саме команда.
	assert_eq(FireCommand.create(other.id, victim.id).validate(state), "ERR_NO_SUCH_TARGET",
		"по мертвому не стріляють — і це має ловити сам check_shot()")
	assert_does_not_have(_ids(Targeting.firing_targets(state, other.id)), victim.id,
		"а оверлей не має його показувати")
	assert_eq(Targeting.threatened_units(state, victim.id, 0).size(), 0, "мертвий ворог не загрожує")
	assert_eq(Targeting.drone_threatened_units(state, victim.id, 0).size(), 0,
		"мертвий ворог не загрожує й дроном")


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


# --- §3.9 + §3.13: дрон має власне кільце і власні позначки ----------------------
#
# Тип 1 — штурмове відділення: гармата дальністю 3, огляд 5, два дрони.
# Дрон дістає на 5 (коло) і так само гейтиться ромбом огляду.

func test_enemy_squad_with_drones_threatens_a_tank_its_gun_cannot_reach() -> void:
	# Головний тест Job 1. Загін, намальований як загроза на 3, насправді дістає
	# дроном на 5 — і саме по танку, який він за §3.3.1 бʼє без відповіді.
	var squad: Unit = state.add_unit(1, 1, Vector2i(2, 2), 2)
	var my_eyes: Unit = state.add_unit(0, 0, Vector2i(2, 4), 2)   # огляд 5 — бачить загін
	var tank: Unit = state.add_unit(5, 0, Vector2i(7, 2), 2)
	state.start()
	state.begin_turn()

	assert_false(Rules.in_radius(squad.pos, tank.pos, squad.attack_range()),
		"передумова: звичайна гармата загону танк не дістає")
	assert_true(state.vision[0].is_visible(squad.pos), "передумова: загін видно")

	assert_does_not_have(_ids(Targeting.threatened_units(state, squad.id, 0)), tank.id,
		"звичайний прогноз танк не позначає — дальність 3")
	assert_has(_ids(Targeting.drone_threatened_units(state, squad.id, 0)), tank.id,
		"§3.13: дрон дістає на 5, і прогноз мусить це показати")
	assert_has(_ids(Targeting.threatened_units(state, squad.id, 0)), my_eyes.id,
		"а звичайне кільце лишається тим самим")


func test_enemy_squad_with_no_drones_left_poses_no_drone_threat() -> void:
	# §3.9: боєкомплект не поповнюється до кінця матчу, тож загін без дронів
	# прогнозується на своїй звичайній дальності й не далі.
	var squad: Unit = state.add_unit(1, 1, Vector2i(2, 2), 2)
	state.add_unit(0, 0, Vector2i(2, 4), 2)
	var tank: Unit = state.add_unit(5, 0, Vector2i(7, 2), 2)
	state.start()
	state.begin_turn()
	assert_has(_ids(Targeting.drone_threatened_units(state, squad.id, 0)), tank.id, "передумова: дрони є")

	squad.drones_left = 0
	assert_eq(Targeting.drone_threatened_units(state, squad.id, 0).size(), 0,
		"§3.9: дронів немає — дронової загрози немає")


func test_a_rifle_squad_never_carries_a_drone_threat() -> void:
	# Той самий загін, але тип 0: дронів нуль від народження (§3.6).
	var rifles: Unit = state.add_unit(0, 1, Vector2i(2, 2), 2)
	state.add_unit(0, 0, Vector2i(2, 4), 2)
	state.add_unit(5, 0, Vector2i(7, 2), 2)
	state.start()
	state.begin_turn()

	assert_eq(Targeting.drone_threatened_units(state, rifles.id, 0).size(), 0,
		"§3.6: дрони лише у штурмового відділення")


func test_drone_forecast_never_marks_the_observers_infantry() -> void:
	# §3.9: по піхоті дрон не працює, і саме це — головна контргра проти нього.
	# Піхота стоїть упритул, тобто в дальності обох дій; звичайне кільце її бере.
	var squad: Unit = state.add_unit(1, 1, Vector2i(2, 2), 2)
	var my_infantry: Unit = state.add_unit(0, 0, Vector2i(2, 4), 2)
	state.start()
	state.begin_turn()

	assert_true(Rules.in_radius(squad.pos, my_infantry.pos, DroneCommand.RANGE),
		"передумова: піхота в дальності дрона")
	assert_has(_ids(Targeting.threatened_units(state, squad.id, 0)), my_infantry.id,
		"передумова: звичайним пострілом вона під загрозою")
	assert_does_not_have(_ids(Targeting.drone_threatened_units(state, squad.id, 0)), my_infantry.id,
		"§3.9: дрон по піхоті не працює — позначки бути не може")


func test_drone_forecast_ignores_the_enemys_ap_and_fired_flag() -> void:
	# §3.13: AP ворога — прихований залишок дій, до свого ходу він однаково буде
	# з повним AP. На відміну від боєкомплекту, який публічний і не поповнюється.
	var squad: Unit = state.add_unit(1, 1, Vector2i(2, 2), 2)
	state.add_unit(0, 0, Vector2i(2, 4), 2)
	var tank: Unit = state.add_unit(5, 0, Vector2i(7, 2), 2)
	state.start()
	state.begin_turn()

	squad.exhaust()
	assert_has(_ids(Targeting.drone_threatened_units(state, squad.id, 0)), tank.id,
		"§3.13: AP і has_fired оглянутого ворога навмисно не перевіряються")


func test_drone_forecast_stops_at_the_vision_diamond_too() -> void:
	# §3.1: дальність — коло, огляд — ромб, і дрон гейтиться перетином, як усе інше.
	# Зсув (3, 4): 9 + 16 = 25 <= 25 у колі, 3 + 4 = 7 > 5 поза ромбом.
	var squad: Unit = state.add_unit(1, 1, Vector2i(2, 2), 2)
	state.add_unit(0, 0, Vector2i(2, 4), 2)
	var straight: Unit = state.add_unit(5, 0, Vector2i(2, 7), 2)    # зсув (0, 5)
	var diagonal: Unit = state.add_unit(5, 0, Vector2i(5, 6), 2)    # зсув (3, 4)
	state.start()
	state.begin_turn()

	assert_true(Rules.in_radius(squad.pos, diagonal.pos, DroneCommand.RANGE), "передумова: у колі дальності 5")
	assert_false(Rules.in_vision_diamond(squad.pos, diagonal.pos, squad.vision()), "передумова: поза ромбом огляду 5")

	var ids: Array[int] = _ids(Targeting.drone_threatened_units(state, squad.id, 0))
	assert_has(ids, straight.id, "по прямій рівно 5 — у перетині обох форм")
	assert_does_not_have(ids, diagonal.id, "§3.1: у колі, але поза ромбом — не позначається")


func test_drone_forecast_does_not_widen_when_the_enemy_has_a_spotter() -> void:
	# Антивитік для дрона. Танк стоїть у дальності дрона, але поза ромбом самого
	# загону; ворожий коригувальник поруч із танком підсвічує його для МЕРЕЖІ.
	# Якби прогноз брав state.vision[owner], позначка видала б розвідника.
	var squad: Unit = state.add_unit(1, 1, Vector2i(2, 2), 2)
	state.add_unit(0, 0, Vector2i(2, 4), 2)                        # мої очі на загін
	state.add_unit(0, 1, Vector2i(5, 8), 2)                        # ворожий коригувальник
	var diagonal: Unit = state.add_unit(5, 0, Vector2i(5, 6), 2)   # зсув (3, 4) від загону
	state.start()
	state.begin_turn()

	assert_true(state.vision[1].is_visible(diagonal.pos), "передумова: МЕРЕЖА супротивника танк бачить")
	assert_does_not_have(_ids(Targeting.drone_threatened_units(state, squad.id, 0)), diagonal.id,
		"§3.13: прогноз рахується власним ромбом загону, не мережею власника")


func test_invisible_enemy_squad_carries_no_drone_forecast() -> void:
	# §3.13: «юніт, якого ти не бачиш, оглянути не можна» — туман діє і тут.
	var squad: Unit = state.add_unit(1, 1, Vector2i(2, 2), 2)
	var tank: Unit = state.add_unit(5, 0, Vector2i(7, 2), 2)       # огляд 4 < 5 до загону
	state.start()
	state.begin_turn()

	assert_false(state.vision[0].is_visible(squad.pos), "передумова: загону не видно")
	assert_eq(Targeting.drone_threatened_units(state, squad.id, 0).size(), 0, "туман діє і на дронове кільце")

	state.add_unit(0, 0, Vector2i(2, 4), 2)                        # моя піхота, огляд 5
	state.start()
	assert_true(state.vision[0].is_visible(squad.pos), "передумова: тепер бачу")
	assert_has(_ids(Targeting.drone_threatened_units(state, squad.id, 0)), tank.id)


func test_own_squad_is_never_a_drone_threat_to_its_owner() -> void:
	var squad: Unit = state.add_unit(1, 1, Vector2i(2, 2), 2)
	state.add_unit(5, 1, Vector2i(4, 2), 2)
	state.add_unit(5, 0, Vector2i(9, 9), 2)
	state.start()
	# Як і у звичайному прогнозі: хід має бути гравця 1, інакше запит зупиняє
	# охорона observer != active_player, а не гілка «свій юніт».
	state.active_player = 1
	assert_eq(Targeting.drone_threatened_units(state, squad.id, 1).size(), 0,
		"свої своїх не бомблять — прогнозувати нема чого")


# --- збіг з DroneCommand.validate() ----------------------------------------------

func test_drone_targets_agrees_with_drone_command_validate() -> void:
	var squad: Unit = state.add_unit(1, 0, Vector2i(2, 2), 2)
	state.add_unit(5, 1, Vector2i(7, 2), 2)     # танк рівно на 5 — законна ціль
	state.add_unit(2, 1, Vector2i(4, 2), 2)     # бронеавтомобіль зблизька
	state.add_unit(0, 1, Vector2i(3, 2), 2)     # піхота — дроном не можна
	# Зсув (3, 4) від загону: у колі дальності 5, але поза ВЛАСНИМ ромбом загону.
	# Ціллю він усе одно є — свій постріл гейтиться мережею власника (§3.3.1), а
	# другий загін у (3, 3) накриває цей тайл (3 + 2 = 5). Тобто цей рядок — не
	# виняток, а протилежне: приклад того, як коригувальник відкриває діагональ.
	state.add_unit(5, 1, Vector2i(5, 6), 2)
	state.add_unit(11, 1, Vector2i(2, 6), 2)    # інженер — теж «техніка» (§3.9)
	state.add_unit(1, 0, Vector2i(3, 3), 2)     # свій — не ціль, і водночас коригувальник
	state.start()
	state.begin_turn()

	var ids: Array[int] = _ids(Targeting.drone_targets(state, squad.id))
	assert_true(ids.size() > 0, "передумова: хоч одна законна ціль є")
	for u in state.alive_units():
		var legal: bool = DroneCommand.create(squad.id, u.id).validate(state) == ""
		assert_eq(ids.has(u.id), legal, "оверлей і validate() мусять збігатися для юніта %d" % u.id)


func test_drone_targets_follows_the_commands_own_gates() -> void:
	# Кожен гейт дії окремо: боєкомплект, has_fired/AP і чий зараз хід.
	var squad: Unit = state.add_unit(1, 0, Vector2i(2, 2), 2)
	state.add_unit(5, 1, Vector2i(5, 2), 2)
	state.start()
	state.begin_turn()
	assert_eq(Targeting.drone_targets(state, squad.id).size(), 1, "передумова: удар законний")

	squad.drones_left = 0
	assert_eq(Targeting.drone_targets(state, squad.id).size(), 0, "§3.9: боєкомплект скінчився")

	squad.drones_left = 2
	squad.has_fired = false
	squad.ap = squad.fire_cost() - 1
	assert_eq(Targeting.drone_targets(state, squad.id).size(), 0, "§3.2: не вистачає AP на удар")

	# exhaust() гасить і прапорець, і AP, тож сам по собі він не показує, ЯКА з двох
	# умов спрацювала. Розводимо їх, як у тесті звичайного пострілу вище: повний AP
	# при піднятому has_fired — стан, якого в грі не буває, але лише він ізолює прапорець.
	squad.exhaust()
	squad.ap = squad.max_ap()
	assert_eq(Targeting.drone_targets(state, squad.id).size(), 0,
		"§3.2: одна дія за хід, навіть із повним AP")

	squad.refill_ap()
	state.active_player = 1
	assert_eq(Targeting.drone_targets(state, squad.id).size(), 0, "не свій хід — удару немає")


func test_a_rifle_squad_has_no_drone_targets() -> void:
	var rifles: Unit = state.add_unit(0, 0, Vector2i(2, 2), 2)
	state.add_unit(5, 1, Vector2i(5, 2), 2)
	state.start()
	state.begin_turn()
	assert_eq(Targeting.drone_targets(state, rifles.id).size(), 0, "§3.6: у стрілецького відділення дронів немає")


# --- чистота ---------------------------------------------------------------------

func test_queries_do_not_touch_the_state() -> void:
	var tank: Unit = state.add_unit(5, 0, Vector2i(4, 4), 2)
	var enemy: Unit = state.add_unit(5, 1, Vector2i(6, 4), 2)
	var squad: Unit = state.add_unit(1, 0, Vector2i(4, 6), 2)
	var enemy_squad: Unit = state.add_unit(1, 1, Vector2i(6, 6), 2)
	state.start()
	state.begin_turn()

	var rng_state: int = state.rng.state
	var before: Array = [tank.ap, tank.hp, tank.has_fired, enemy.ap, enemy.hp, enemy.has_fired,
		squad.drones_left, enemy_squad.drones_left]

	var first: Array[int] = _ids(Targeting.firing_targets(state, tank.id))
	var first_threat: Array[int] = _ids(Targeting.threatened_units(state, enemy.id, 0))
	var first_drone: Array[int] = _ids(Targeting.drone_targets(state, squad.id))
	var first_drone_threat: Array[int] = _ids(Targeting.drone_threatened_units(state, enemy_squad.id, 0))
	var second: Array[int] = _ids(Targeting.firing_targets(state, tank.id))
	var second_threat: Array[int] = _ids(Targeting.threatened_units(state, enemy.id, 0))
	var second_drone: Array[int] = _ids(Targeting.drone_targets(state, squad.id))
	var second_drone_threat: Array[int] = _ids(Targeting.drone_threatened_units(state, enemy_squad.id, 0))

	assert_eq(first, second, "запит детермінований")
	assert_eq(first_threat, second_threat, "запит детермінований")
	assert_eq(first_drone, second_drone, "дроновий запит детермінований")
	assert_eq(first_drone_threat, second_drone_threat, "дроновий прогноз детермінований")
	assert_eq([tank.ap, tank.hp, tank.has_fired, enemy.ap, enemy.hp, enemy.has_fired,
		squad.drones_left, enemy_squad.drones_left], before, "запит нічого не мутує")
	assert_eq(state.rng.state, rng_state, "запит не чіпає RNG матчу")
