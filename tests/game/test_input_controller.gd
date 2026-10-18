extends GutTest
## Task 2.7: тап → намір → Command. Жива battle_screen.tscn з'являється лише в
## Task 2.10 (ручна перевірка «вибрав → пішов → вистрілив» відкладена туди,
## R25), тож тут — headless перевірка контролера як чистого об'єкта: власний
## MatchService на тест (той самий прийом, що й test_match_service.gd — окремий
## екземпляр, а не спільний автозавантажений синглтон, щоб тести не текли
## станом одне в одного), шпигун замість справжнього ZoneOverlay.

const MatchServiceScript := preload("res://game/autoload/match_service.gd")

## Шпигун замість справжнього ZoneOverlay: не тримає жодного BoardView (той
## вимагав би живої сцени й наштовхнувся б на ту саму MultiMesh-заглушку під
## headless, що й test_zone_overlay.gd, R4/R16), а лише запам'ятовує останній
## виклик. Тест звіряється з тим, ЩО порахував InputController (сам об'єкт
## Pathing.Zones), а не з тим, як воно намальоване — саме малювання вже
## покрите test_zone_overlay.gd.
class SpyZoneOverlay extends ZoneOverlay:
	var last_unit: Unit = null
	var last_zones: Pathing.Zones = null
	var show_for_calls: int = 0
	var clear_calls: int = 0

	func _init() -> void:
		pass  # навмисно НЕ super._init(board_view) — шпигуну дошка не потрібна

	func show_for(unit: Unit, zones: Pathing.Zones) -> void:
		last_unit = unit
		last_zones = zones
		show_for_calls += 1

	func clear() -> void:
		clear_calls += 1


var service: Node
var overlay: SpyZoneOverlay
var controller: InputController
var _selections: Array = []
var _previews: Array[Dictionary] = []
var _pending_cleared_count: int = 0


func before_each() -> void:
	service = MatchServiceScript.new()
	add_child_autofree(service)
	overlay = SpyZoneOverlay.new()
	controller = InputController.new(service, overlay)
	_selections = []
	_previews = []
	_pending_cleared_count = 0
	controller.selection_changed.connect(func(u: Unit) -> void: _selections.append(u))
	controller.action_preview.connect(func(p: Dictionary) -> void: _previews.append(p))
	controller.pending_cleared.connect(func() -> void: _pending_cleared_count += 1)


func _start(width: int = 20, height: int = 20) -> void:
	service.start_match(Board.create(width, height, Terrain.GroundState.DRY), 2, 1)


func _begin_and_drain() -> void:
	service.begin()
	service.take_events()


## Тап при вибраному юніті тепер ще й повертає його (TurnCommand) — у черзі може
## бути лише UnitTurned; будь-яка інша подія означала б, що прев'ю щось виконало.
func _only_turns_queued() -> bool:
	for e in service.take_events():
		if not e is Events.UnitTurned:
			return false
	return true


# --- Вибір ------------------------------------------------------------

func test_tap_on_own_unit_selects_it_and_shows_two_zones() -> void:
	_start()
	var u: Unit = service.state.add_unit(5, 0, Vector2i(5, 5), 0)  # medium tank, owner 0
	_begin_and_drain()

	controller.tap_cell(u.pos)

	assert_eq(_selections.size(), 1, "мусить прийти рівно один selection_changed")
	assert_eq(_selections[0], u)
	assert_eq(overlay.show_for_calls, 1, "вибір свого юніта мусить показати дві зони")
	assert_eq(overlay.last_unit, u)
	assert_eq(overlay.last_zones.origin, u.pos)


# --- Рух: прев'ю без дії -------------------------------------------------

func test_tap_on_zone_tile_sets_pending_move_and_submits_nothing() -> void:
	_start()
	var u: Unit = service.state.add_unit(5, 0, Vector2i(5, 5), 0)
	_begin_and_drain()
	controller.tap_cell(u.pos)

	var start_pos: Vector2i = u.pos
	var start_ap: int = u.ap
	var target := Vector2i(6, 5)  # сусідній тайл, точно в межах зони танка

	controller.tap_cell(target)

	assert_eq(u.pos, start_pos, "прев'ю не мусить рухати юніт")
	assert_eq(u.ap, start_ap, "прев'ю не мусить витрачати AP")
	assert_true(_only_turns_queued(), "прев'ю не мусить лишати подій у черзі")

	assert_eq(_previews.size(), 1)
	var p: Dictionary = _previews[0]
	assert_eq(p["type"], InputController.ActionType.MOVE)
	assert_eq(p["unit_id"], u.id)
	assert_eq(p["target"], target)
	assert_eq(p["ap_left"], start_ap - Rules.entry_cost_at(u, service.state.board, target))


func test_confirm_pending_submits_exactly_one_move_command_and_clears_pending() -> void:
	_start()
	var u: Unit = service.state.add_unit(5, 0, Vector2i(5, 5), 0)
	_begin_and_drain()
	controller.tap_cell(u.pos)
	var target := Vector2i(6, 5)
	controller.tap_cell(target)

	controller.confirm_pending()

	assert_eq(u.pos, target, "confirm_pending() мусить справді застосувати рух")
	assert_false(service.take_events().is_empty(), "команда мусить лишити події")

	# Другий confirm_pending() без нового прев'ю — no-op: pending уже порожній.
	var pos_after_first_confirm: Vector2i = u.pos
	controller.confirm_pending()
	assert_eq(u.pos, pos_after_first_confirm, "повторний confirm_pending() без прев'ю нічого не робить")
	assert_true(service.take_events().is_empty(), "повторний confirm_pending() не мусить нічого подавати")


## Власник: повторний тап по тайлу, куди вже прокладено шлях, — те саме, що Confirm.
func test_second_tap_on_pending_move_target_confirms_it() -> void:
	_start()
	var u: Unit = service.state.add_unit(5, 0, Vector2i(5, 5), 0)
	_begin_and_drain()
	controller.tap_cell(u.pos)
	var target := Vector2i(6, 5)
	controller.tap_cell(target)
	var ap_left: int = int(_previews[0]["ap_left"])
	controller.tap_cell(target)
	assert_eq(u.pos, target)
	assert_eq(u.ap, ap_left)
	assert_eq(_selections.back(), u, "юніт лишається вибраним, як після Confirm")
	assert_eq(_previews.size(), 1, "другий тап не будує нового прев'ю")
	assert_eq(overlay.last_zones.origin, target, "зони перераховано від нової позиції")


## Тап по іншому тайлу зони при відкладеному русі — лише нове прев'ю.
func test_tap_on_another_tile_with_pending_move_only_repreviews() -> void:
	_start()
	var u: Unit = service.state.add_unit(5, 0, Vector2i(5, 5), 0)
	_begin_and_drain()
	controller.tap_cell(u.pos)
	controller.tap_cell(Vector2i(6, 5))
	controller.tap_cell(Vector2i(4, 5))
	assert_eq(u.pos, Vector2i(5, 5))
	assert_eq(_previews.size(), 2)


## «Скасувати» HUD щось робить рівно тоді, коли є прев'ю або озброєно дрон; на час
## верби інженера скасування одне — у його панелі.
func test_has_cancelable_follows_pending_and_armed_modes() -> void:
	_start()
	var u: Unit = service.state.add_unit(5, 0, Vector2i(5, 5), 0)
	var eng: Unit = service.state.add_unit(ENGINEER_TYPE, 0, Vector2i(10, 10), 0)
	var sq: Unit = service.state.add_unit(1, 0, Vector2i(15, 15), 0)
	service.state.add_unit(5, 1, Vector2i(15, 18), 0)
	_begin_and_drain()
	assert_false(controller.has_cancelable(), "нічого не вибрано")
	controller.tap_cell(u.pos)
	assert_false(controller.has_cancelable(), "лише вибір — скасовувати нічого")
	controller.tap_cell(Vector2i(6, 5))
	assert_true(controller.has_cancelable(), "прев'ю руху")
	controller.cancel_pending()
	assert_false(controller.has_cancelable())
	controller.tap_cell(eng.pos)
	controller.arm_engineer(LAY)
	assert_false(controller.has_cancelable(), "озброєна верба — у панелі інженера своє «Скасувати»")
	controller.cancel_pending()
	assert_false(controller.has_cancelable())
	controller.tap_cell(sq.pos)
	controller.arm_drone()
	assert_true(controller.has_cancelable(), "озброєний дрон")
	controller.cancel_pending()
	assert_false(controller.has_cancelable())


func test_cancel_pending_clears_pending_and_submits_nothing() -> void:
	_start()
	var u: Unit = service.state.add_unit(5, 0, Vector2i(5, 5), 0)
	_begin_and_drain()
	controller.tap_cell(u.pos)
	controller.tap_cell(Vector2i(6, 5))

	controller.cancel_pending()

	assert_eq(u.pos, Vector2i(5, 5), "cancel_pending() не мусить рухати юніт")
	assert_true(_only_turns_queued())

	# confirm_pending() після cancel_pending() — теж no-op.
	controller.confirm_pending()
	assert_eq(u.pos, Vector2i(5, 5))
	assert_true(service.take_events().is_empty())


## Підсвітка шляху (task 2, PathOverlay) слухає рівно цей сигнал, щоб зняти
## намальований маршрут, коли гравець скасовує дію — без нього шлях лишався
## б на екрані для дії, якої вже нема.
func test_cancel_pending_emits_pending_cleared() -> void:
	_start()
	var u: Unit = service.state.add_unit(5, 0, Vector2i(5, 5), 0)
	_begin_and_drain()
	controller.tap_cell(u.pos)
	controller.tap_cell(Vector2i(6, 5))
	_pending_cleared_count = 0  # скинути емісію від select_unit() вище — цікавить лише cancel

	controller.cancel_pending()

	assert_eq(_pending_cleared_count, 1, "cancel_pending() мусить повідомити слухачів, що прев'ю знято")


## Той самий сигнал мусить прийти й після успішного підтвердження — юніт
## лишається вибраним (жодного selection_changed, input_controller.gd:174),
## тож це єдиний спосіб для PathOverlay дізнатись, що щойно намальований
## шлях уже пройдено і його треба зняти.
func test_confirm_pending_emits_pending_cleared_without_disturbing_preview_count() -> void:
	_start()
	var u: Unit = service.state.add_unit(5, 0, Vector2i(5, 5), 0)
	_begin_and_drain()
	controller.tap_cell(u.pos)
	controller.tap_cell(Vector2i(6, 5))
	assert_eq(_previews.size(), 1, "передумова: рівно одне прев'ю руху")
	_pending_cleared_count = 0  # скинути емісію від select_unit() вище — цікавить лише confirm

	controller.confirm_pending()

	assert_eq(_pending_cleared_count, 1, "confirm_pending() мусить повідомити слухачів, що прев'ю знято")
	assert_eq(_previews.size(), 1, "pending_cleared — окремий сигнал; action_preview не мусить отримати зайвий запис")


## select_unit() теж скидає _pending (input_controller.gd:72) — та сама
## гарантія мусить діяти й тут: перемикання вибору без жодної дії не лишає
## PathOverlay зі старим шляхом чужого юніта.
func test_select_unit_emits_pending_cleared_without_disturbing_preview_count() -> void:
	_start()
	var a: Unit = service.state.add_unit(5, 0, Vector2i(5, 5), 0)
	var b: Unit = service.state.add_unit(5, 0, Vector2i(10, 10), 0)
	_begin_and_drain()
	controller.tap_cell(a.pos)
	controller.tap_cell(Vector2i(6, 5))
	assert_eq(_previews.size(), 1, "передумова: рівно одне прев'ю руху для a")

	controller.tap_cell(b.pos)

	assert_eq(_previews.size(), 1, "action_preview не мусить отримати зайвий запис від select_unit()")
	assert_true(_pending_cleared_count >= 1, "select_unit() мусить повідомити, що старий pending знято")


# --- Ціль: прев'ю пострілу --------------------------------------------------

func test_tap_enemy_within_range_sets_pending_shot_with_sector_and_bounds() -> void:
	_start()
	var u: Unit = service.state.add_unit(5, 0, Vector2i(5, 5), 0)
	var enemy: Unit = service.state.add_unit(5, 1, Vector2i(6, 5), 0)
	_begin_and_drain()
	controller.tap_cell(u.pos)

	var expected: Dictionary = FireCommand.preview(service.state, u.id, enemy.id)
	controller.tap_cell(enemy.pos)

	assert_true(_only_turns_queued(), "прев'ю пострілу не мусить нічого подавати")
	assert_eq(_previews.size(), 1)
	var p: Dictionary = _previews[0]
	assert_eq(p["type"], InputController.ActionType.SHOT)
	assert_eq(p["unit_id"], u.id)
	assert_eq(p["target_id"], enemy.id)
	assert_eq(p["sector"], expected["sector"])
	assert_eq(p["min"], expected["min"])
	assert_eq(p["max"], expected["max"])


func test_confirm_pending_submits_exactly_one_fire_command() -> void:
	_start()
	var u: Unit = service.state.add_unit(5, 0, Vector2i(5, 5), 0)
	var enemy: Unit = service.state.add_unit(5, 1, Vector2i(6, 5), 0)
	_begin_and_drain()
	controller.tap_cell(u.pos)
	controller.tap_cell(enemy.pos)

	controller.confirm_pending()

	assert_true(u.has_fired, "confirm_pending() мусить справді провести постріл")
	assert_false(service.take_events().is_empty())


# --- Зняття вибору ------------------------------------------------------

func test_tap_outside_board_clears_selection() -> void:
	_start()
	var u: Unit = service.state.add_unit(5, 0, Vector2i(5, 5), 0)
	_begin_and_drain()
	controller.tap_cell(u.pos)
	assert_eq(_selections.back(), u, "передумова: юніт вибраний")

	controller.tap_cell(Vector2i(-1, -1))

	assert_eq(_selections.back(), null, "тап поза дошкою знімає вибір")
	assert_eq(overlay.clear_calls, 1)


func test_tap_on_already_selected_unit_clears_selection() -> void:
	_start()
	var u: Unit = service.state.add_unit(5, 0, Vector2i(5, 5), 0)
	_begin_and_drain()
	controller.tap_cell(u.pos)
	assert_eq(_selections.back(), u, "передумова: юніт вибраний")

	controller.tap_cell(u.pos)

	assert_eq(_selections.back(), null, "повторний тап по вибраному юніту знімає вибір")
	assert_eq(overlay.clear_calls, 1)


# --- R24: блокування вводу під час програвання ---------------------------

func test_taps_ignored_while_playback_is_running() -> void:
	_start()
	var u: Unit = service.state.add_unit(5, 0, Vector2i(5, 5), 0)
	_begin_and_drain()
	var playing_controller := InputController.new(service, overlay, func() -> bool: return true)

	playing_controller.tap_cell(u.pos)

	assert_eq(overlay.show_for_calls, 0, "тап під час програвання не мусить нічого вибирати")


func test_select_unit_ignored_while_playback_is_running() -> void:
	_start()
	var u: Unit = service.state.add_unit(5, 0, Vector2i(5, 5), 0)
	_begin_and_drain()
	var playing_controller := InputController.new(service, overlay, func() -> bool: return true)

	playing_controller.select_unit(u)

	assert_eq(overlay.show_for_calls, 0, "select_unit() під час програвання теж мусить бути no-op — R24 каже «кожен тап»")


# --- Матч завершено: ввід не приймається взагалі -------------------------
#
# Баг власника: «дограв, убив усіх юнітів противника і гра крешнулась» на
# assert у battle_screen.gd. Корінь — не кнопка кінця ходу: core/ залежить від
# state.is_over() УСІ команди (move/fire/drone/engineer/end_turn), тож після
# перемоги вигляд і далі пропонує дію, яку правила вже відхиляють, і кожен
# підтверджений намір падає на assert. Відповідь та сама, що й у R24: після
# завершення матчу вигляд перестає приймати ввід — не гасить кожну кнопку
# окремо.

func test_selection_and_taps_are_ignored_once_the_match_is_over() -> void:
	_start()
	var u: Unit = service.state.add_unit(5, 0, Vector2i(5, 5), 0)
	_begin_and_drain()
	# Гравець 1 не має жодного юніта — перший же кінець ходу вибиває його й
	# завершує матч (core/battle_state.gd, check_elimination). Справжній шлях
	# ядра, не підставлений winner.
	service.submit(EndTurnCommand.create())
	service.take_events()
	assert_true(service.state.is_over(), "передумова: матч справді завершився")
	assert_eq(service.state.active_player, 0, "передумова: хід не передався — EndTurnCommand вийшов раніше")

	controller.select_unit(u)
	controller.tap_cell(u.pos)
	controller.tap_cell(Vector2i(6, 5))

	assert_eq(overlay.show_for_calls, 0, "після завершення матчу вибір не мусить нічого рахувати й малювати")
	assert_true(_selections.is_empty(), "жодного selection_changed після завершення матчу")
	assert_true(_previews.is_empty(), "жодного прев'ю дії, яку core/ уже відхиляє")
	assert_true(service.take_events().is_empty(), "і жодної команди в ядро")


# --- Рев'ю: _zones мусять описувати ПОТОЧНИЙ стан, не стан на момент вибору --
#
# Знахідка рев'ю: до фіксу _zones рахувалися рівно один раз, у select_unit(),
# і ніколи не оновлювалися після confirm_pending() — хоча MoveCommand і
# FireCommand щойно змінили позицію й AP того самого юніта. §3.2 називає цей
# сценарій прямо: «Movement is spent, not committed. A unit may move in as
# many separate steps as its AP allows» — це не рідкісний край, а звичайний
# хід «рух-рух» чи «рух-постріл» одним юнітом.


func test_confirm_move_then_tap_computes_zone_from_new_position_and_ap() -> void:
	_start()
	var u: Unit = service.state.add_unit(5, 0, Vector2i(5, 5), 0)  # medium tank, ap 48, cc 12
	_begin_and_drain()
	controller.tap_cell(u.pos)
	controller.tap_cell(Vector2i(6, 5))  # вхід у поле коштує max(10,10+10-12)=10
	controller.confirm_pending()
	assert_eq(u.pos, Vector2i(6, 5), "передумова: юніт справді пересунувся")
	assert_eq(u.ap, 38, "передумова: 48 - 10")

	# Сам факт другого show_for() — доказ, що зони перераховані, а не лишились
	# із моменту select_unit(): без фіксу цей лічильник застряг би на 1.
	assert_eq(overlay.show_for_calls, 2, "confirm_pending() мусить перерахувати зони того самого юніта")
	assert_eq(overlay.last_zones.origin, Vector2i(6, 5), "нові зони мусять мати початком НОВУ позицію, а не стару")

	controller.tap_cell(Vector2i(7, 5))  # ще один крок від нової позиції, cost 10

	assert_eq(_previews.size(), 2)
	var p: Dictionary = _previews[1]
	assert_eq(p["target"], Vector2i(7, 5))
	assert_eq(p["ap_left"], 28, "38 - 10, порахований від НОВОЇ позиції й АП, а не від 48 - 20 крізь стару")
	assert_eq(p["path"], [Vector2i(7, 5)] as Array[Vector2i],
		"шлях зі свіжих зон — один крок від (6,5); зі старих зон вийшло б два кроки крізь клітинку, де юніт уже стоїть")


func test_confirm_shot_then_tap_does_not_reach_stale_zone_tiles() -> void:
	_start()
	var u: Unit = service.state.add_unit(5, 0, Vector2i(5, 5), 0)  # medium tank, ap 48, fire_cost 20
	# Інженер ніколи не відповідає (§3.6/§3.3.1) — атакувальник гарантовано
	# лишається живим, тож перевіряється рівно нульовий AP, а не смерть.
	var target: Unit = service.state.add_unit(11, 1, Vector2i(6, 5), 0)  # engineer vehicle
	_begin_and_drain()
	controller.tap_cell(u.pos)
	# Передумова: (7,5) — усередині ЗІ старого AP=48 зони (2 тайли, cost 20).
	assert_true(overlay.last_zones.can_reach(Vector2i(7, 5)), "передумова: клітинка в зоні до пострілу")
	controller.tap_cell(target.pos)

	controller.confirm_pending()

	assert_true(u.has_fired, "передумова: постріл справді стався")
	assert_eq(u.ap, 0, "exhaust() обнуляє AP (§3.2)")
	assert_true(u.is_alive(), "передумова: інженер не відповідає — атакувальник живий")
	assert_false(overlay.last_zones.can_reach(Vector2i(7, 5)),
		"нульовий AP не мусить лишати в силі клітину зі старої, дозаданої зони")

	var previews_before: int = _previews.size()
	controller.tap_cell(Vector2i(7, 5))

	assert_eq(_previews.size(), previews_before,
		"тап по клітинці поза (тепер порожньою) зоною — no-op; жодного прев'ю з від'ємним ap_left")


func test_unit_that_dies_to_retaliation_clears_selection_cleanly() -> void:
	_start()
	var u: Unit = service.state.add_unit(2, 0, Vector2i(5, 5), 0)  # armoured car
	u.hp = 1  # §3.3 MIN_DAMAGE=10 — будь-яка відповідь гарантовано вбиває
	var target: Unit = service.state.add_unit(8, 1, Vector2i(6, 5), 0)  # heavy tank, відповідає
	_begin_and_drain()
	controller.tap_cell(u.pos)
	controller.tap_cell(target.pos)

	controller.confirm_pending()

	assert_false(u.is_alive(), "передумова: важкий танк відповів і вбив")
	assert_eq(_selections.back(), null, "смерть вибраного юніта мусить зняти вибір, а не лишити висячий Unit")
	assert_true(overlay.clear_calls > 0, "оверлей мусить бути очищений, коли обʼєкта вибору більше нема")


# --- R5: фог-безпечне планування ------------------------------------------

## Броньований автомобіль (id=2): AP 68, cross_country 5, тому вхід у звичайне
## поле (penalty 10) коштує max(10, 10+10-5)=15, і чотири тайли по прямій
## (60 AP) лишаються в межах зони. Його ромб огляду — лише 3, тож тайл на
## відстані Менхеттена 4 йому НЕ видна: жодна розвідка її не торкалася.
## Ворог, що стоїть саме там, — точний тест R5: known_occupied_map(active)
## не знає про нього (тайл ніколи не seen), тож зона мусить включати його
## тайл. occupied_map() (всезнаюча) натомість виключила б цей тайл
## цілком — Pathing ніколи не кладе зайнятий тайл в cost-мапу, тож
## can_reach() впав би на false, і контур зони обійшов би ворога, виказавши
## його самою формою дірки. Якщо хтось підмінить known_occupied_map() на
## occupied_map() у input_controller.gd, цей тест мусить впасти.
func test_zone_uses_known_occupancy_not_true_occupancy() -> void:
	_start()
	var u: Unit = service.state.add_unit(2, 0, Vector2i(5, 5), 0)  # armoured car, owner 0
	var enemy: Unit = service.state.add_unit(5, 1, Vector2i(5, 9), 0)  # Манхеттен 4, поза ромбом 3
	_begin_and_drain()

	assert_false(service.state.vision[0].is_seen(enemy.pos), "передумова: ворожа клітинка нерозвідана")

	controller.tap_cell(u.pos)

	assert_not_null(overlay.last_zones)
	assert_true(overlay.last_zones.can_reach(enemy.pos),
		"зона мусить включати клітинку невидимого ворога — вона порахована проти known_occupied_map(), не occupied_map()")


## §3.11, рішення власника: знайдена ворожа міна — перешкода, і контур зони
## мусить її обгинати рівно так, як MoveCommand її об'їжджає. Невідома міна в
## зону потрапляє — інакше форма контуру виказала б її (§3.5).
func test_zone_excludes_a_known_enemy_mine_but_not_an_unknown_one() -> void:
	_start()
	var u: Unit = service.state.add_unit(5, 0, Vector2i(5, 5), 0)  # medium tank, owner 0
	Mines.place(service.state, Vector2i(5, 6), 1)
	Mines.place(service.state, Vector2i(6, 5), 1)
	Mines.mine_at(service.state, Vector2i(5, 6)).known_to[0] = true
	_begin_and_drain()

	controller.tap_cell(u.pos)

	assert_not_null(overlay.last_zones)
	assert_false(overlay.last_zones.can_reach(Vector2i(5, 6)), "відома ворожа міна — не в зоні")
	assert_true(overlay.last_zones.can_reach(Vector2i(6, 5)), "невідома міна не видна формою зони")


# --- Task 8: режим ENGINEER -------------------------------------------------
# Допустимі тайли беруться лише з EngineerCommand.action_status() (§3.13) —
# контролер їх не виводить сам.

const ENGINEER_TYPE: int = 11
const LAY := EngineerCommand.Action.LAY_MINE


func _engineer_at(pos: Vector2i) -> Unit:
	_start()
	var e: Unit = service.state.add_unit(ENGINEER_TYPE, 0, pos, 0)
	_begin_and_drain()
	controller.tap_cell(e.pos)
	return e


func test_arm_engineer_emits_valid_tiles() -> void:
	_engineer_at(Vector2i(5, 5))
	var got: Array = []
	controller.targets_changed.connect(func(t: Array[Vector2i]) -> void: got.append(t))
	controller.arm_engineer(LAY)
	assert_eq(got.size(), 1)
	assert_eq(got[0], [Vector2i(5, 4), Vector2i(6, 5), Vector2i(5, 6), Vector2i(4, 5)] as Array[Vector2i])


func test_arm_engineer_without_tiles_refuses_with_reason() -> void:
	var e: Unit = _engineer_at(Vector2i(5, 5))
	e.ap = 29  # fire_cost 30
	var reasons: Array[String] = []
	var targets: Array = []
	controller.action_refused.connect(func(r: String) -> void: reasons.append(r))
	controller.targets_changed.connect(func(t: Array[Vector2i]) -> void: targets.append(t))
	controller.arm_engineer(LAY)
	assert_eq(reasons, ["ERR_NOT_ENOUGH_AP"] as Array[String])
	assert_eq(targets.size(), 0, "нічого не озброєно — контур цілей не показується")
	controller.tap_cell(Vector2i(5, 4))
	assert_ne(int(_previews.back()["type"]) if not _previews.is_empty() else -1,
		InputController.ActionType.ENGINEER, "без озброєння тап по сусідньому тайлі — не прев'ю верби")


## Власник: міна ставиться одразу на тап по допустимому тайлі — без прев'ю й Confirm.
func test_lay_mine_tap_on_valid_tile_lays_it_at_once() -> void:
	var e: Unit = _engineer_at(Vector2i(5, 5))
	controller.arm_engineer(LAY)
	controller.tap_cell(Vector2i(6, 5))
	assert_eq(_previews.size(), 0, "жодного прев'ю — дія вже виконана")
	assert_eq(service.state.mines.size(), 1)
	assert_eq(service.state.mines[0].pos, Vector2i(6, 5))
	assert_eq(e.ap, 0)
	assert_false(controller.has_cancelable(), "нічого не озброєно й не чекає")


## Решта верб — як раніше: тап лише показує прев'ю.
func test_other_verbs_still_preview_first() -> void:
	var e: Unit = _engineer_at(Vector2i(5, 5))
	service.state.board.set_kind(Vector2i(6, 5), Terrain.Kind.BRIDGE_DESTROYED)
	controller.arm_engineer(EngineerCommand.Action.REPAIR_BRIDGE)
	controller.tap_cell(Vector2i(6, 5))
	assert_eq(_previews, [{"type": InputController.ActionType.ENGINEER, "unit_id": e.id,
		"action": EngineerCommand.Action.REPAIR_BRIDGE, "target": Vector2i(6, 5)}] as Array[Dictionary])
	assert_eq(service.state.board.kind_at(Vector2i(6, 5)), Terrain.Kind.BRIDGE_DESTROYED)


func test_tap_outside_tiles_is_noop_in_engineer_mode() -> void:
	var e: Unit = _engineer_at(Vector2i(5, 5))
	controller.arm_engineer(LAY)
	var sel_before: int = _selections.size()
	controller.tap_cell(Vector2i(8, 5))  # поза тайлами; без режиму це було б прев'ю руху
	controller.tap_cell(Vector2i(-1, -1))  # поза дошкою; без режиму — зняття вибору
	assert_eq(_previews.size(), 0)
	assert_eq(_selections.size(), sel_before)
	controller.tap_cell(Vector2i(5, 4))
	assert_eq(service.state.mines.size(), 1, "режим досі озброєний")
	assert_eq(service.state.mines[0].pos, Vector2i(5, 4))
	assert_eq(service.state.mines[0].owner, e.owner)


func test_selecting_another_unit_disarms() -> void:
	_engineer_at(Vector2i(5, 5))
	var other: Unit = service.state.add_unit(5, 0, Vector2i(9, 9), 0)
	controller.arm_engineer(LAY)
	var targets: Array = []
	controller.targets_changed.connect(func(t: Array[Vector2i]) -> void: targets.append(t))
	controller.tap_cell(other.pos)
	assert_eq(_selections.back(), other)
	assert_eq(targets, [[] as Array[Vector2i]])
	controller.tap_cell(Vector2i(9, 8))
	assert_eq(int(_previews.back()["type"]), InputController.ActionType.MOVE, "режим знятий — звичайний тап")


func test_targets_cleared_after_laying() -> void:
	_engineer_at(Vector2i(5, 5))
	controller.arm_engineer(LAY)
	var targets: Array = []
	controller.targets_changed.connect(func(t: Array[Vector2i]) -> void: targets.append(t))
	controller.tap_cell(Vector2i(6, 5))
	assert_eq(targets.back(), [] as Array[Vector2i])


func test_tap_on_invalid_tile_in_engineer_mode_reports_its_reason() -> void:
	_engineer_at(Vector2i(5, 5))
	controller.arm_engineer(LAY)
	var reasons: Array[String] = []
	controller.action_refused.connect(func(r: String) -> void: reasons.append(r))
	controller.tap_cell(Vector2i(8, 5))
	assert_eq(reasons, ["ERR_NOT_ADJACENT"] as Array[String])
	assert_eq(_previews.size(), 0)


# --- Task 10: дрон ---------------------------------------------------------

## Загін P0 на (5,5); танк P1 на (8,5) (у межах і звичайного пострілу, дальність 3);
## стрілецький P1 на (5,8).
func _squad_scene() -> Array[Unit]:
	_start()
	var sq: Unit = service.state.add_unit(1, 0, Vector2i(5, 5), 0)
	var tank: Unit = service.state.add_unit(5, 1, Vector2i(8, 5), 0)
	var inf: Unit = service.state.add_unit(0, 1, Vector2i(5, 8), 0)
	_begin_and_drain()
	controller.tap_cell(sq.pos)
	return [sq, tank, inf]


func test_arm_drone_emits_ring_and_marks() -> void:
	var u: Array[Unit] = _squad_scene()
	var got: Array = []
	controller.drone_armed.connect(func(center: Vector2i, radius: int, marks: Dictionary) -> void:
		got.append([center, radius, marks]))
	controller.arm_drone()
	assert_eq(got.size(), 1)
	assert_eq(got[0][0], u[0].pos, "коло з центром у тайлі загону")
	assert_eq(got[0][1], DroneCommand.RANGE)
	assert_eq(got[0][2], {u[1].id: "", u[2].id: "ERR_DRONE_CANNOT_TARGET_INFANTRY"})


func test_drone_tap_on_infantry_refused_with_reason() -> void:
	var u: Array[Unit] = _squad_scene()
	var reasons: Array[String] = []
	controller.action_refused.connect(func(r: String) -> void: reasons.append(r))
	controller.arm_drone()
	controller.tap_cell(u[2].pos)
	assert_eq(reasons, ["ERR_DRONE_CANNOT_TARGET_INFANTRY"] as Array[String])
	assert_eq(_previews.size(), 0)


func test_drone_tap_on_vehicle_sets_preview_120_180() -> void:
	var u: Array[Unit] = _squad_scene()
	controller.arm_drone()
	controller.tap_cell(u[1].pos)
	assert_eq(_previews, [{"type": InputController.ActionType.DRONE, "unit_id": u[0].id,
		"target_id": u[1].id, "min": 120, "max": 180}] as Array[Dictionary])
	controller.confirm_pending()
	assert_eq(u[0].drones_left, 1)
	assert_eq(u[0].ap, 0)


func test_plain_tap_on_enemy_still_previews_shot() -> void:
	var u: Array[Unit] = _squad_scene()
	controller.tap_cell(u[1].pos)
	assert_eq(_previews.size(), 1)
	assert_eq(int(_previews[0]["type"]), InputController.ActionType.SHOT)


func test_arm_drone_without_drones_refused() -> void:
	var u: Array[Unit] = _squad_scene()
	u[0].drones_left = 0
	var reasons: Array[String] = []
	var armed: Array = []
	controller.action_refused.connect(func(r: String) -> void: reasons.append(r))
	controller.drone_armed.connect(func(_c: Vector2i, radius: int, _m: Dictionary) -> void: armed.append(radius))
	controller.arm_drone()
	assert_eq(reasons, ["ERR_NO_DRONES_LEFT"] as Array[String])
	assert_eq(armed.size(), 0)
	u[0].drones_left = 2
	u[0].ap = 9  # fire_cost 10
	controller.arm_drone()
	assert_eq(reasons.back(), "ERR_NOT_ENOUGH_AP")
	assert_eq(armed.size(), 0)


## Рішення контролера: озброєння дрона знімає відкладений рух.
func test_arming_drone_clears_pending_move() -> void:
	var u: Array[Unit] = _squad_scene()
	controller.tap_cell(Vector2i(5, 4))
	assert_eq(int(_previews.back()["type"]), InputController.ActionType.MOVE)
	var cleared_before: int = _pending_cleared_count
	controller.arm_drone()
	assert_eq(_pending_cleared_count, cleared_before + 1)
	controller.confirm_pending()
	assert_eq(u[0].pos, Vector2i(5, 5), "рух не відбувся")


## Fix round 1 (рішення): у режимі DRONE тап по порожньому, невідомому чи поза
## дошкою тайлу знімає режим, як «Скасувати», а загін лишається вибраним.
func test_drone_tap_on_empty_or_off_board_disarms_and_keeps_selection() -> void:
	for cell: Vector2i in [Vector2i(5, 3), Vector2i(-1, -1)]:
		before_each()
		var u: Array[Unit] = _squad_scene()
		controller.arm_drone()
		var targets: Array = []
		controller.targets_changed.connect(func(t: Array[Vector2i]) -> void: targets.append(t))
		var sel_before: int = _selections.size()
		controller.tap_cell(cell)
		assert_eq(targets, [[] as Array[Vector2i]], "режим знято: %s" % cell)
		assert_eq(_selections.size(), sel_before, "вибір не змінився: %s" % cell)
		assert_eq(_previews.size(), 0)
		controller.tap_cell(u[1].pos)
		assert_eq(int(_previews.back()["type"]), InputController.ActionType.SHOT, "далі — звичайний постріл")


# --- Огляд дальності довгим натиском (§3.13, docs/ui/overlays.md) -----------

var _inspections: Array[Dictionary] = []


func _watch_inspections() -> void:
	_inspections = []
	controller.inspected.connect(func(i: Dictionary) -> void: _inspections.append(i))


## Усе розвідано обома гравцями — інспекцію гейтить лише seen (§3.5).
func _begin_all_seen() -> void:
	_begin_and_drain()
	for p in service.state.player_count:
		service.state.vision[p].seen.fill(1)


## Тап більше ніколи не показує кільця: ні вибір, ні тап по ворогу, ні по порожньому.
func test_a_tap_never_emits_an_inspection() -> void:
	_start()
	var car: Unit = service.state.add_unit(2, 0, Vector2i(10, 7), 0)
	var tank: Unit = service.state.add_unit(5, 1, Vector2i(10, 10), 0)
	_begin_all_seen()
	_watch_inspections()

	controller.tap_cell(tank.pos)
	controller.tap_cell(car.pos)
	controller.tap_cell(tank.pos)
	controller.tap_cell(Vector2i(11, 7))
	controller.tap_cell(Vector2i(0, 0))

	assert_eq(_inspections, [] as Array[Dictionary])


func test_peek_on_enemy_shows_its_inspection_and_end_clears() -> void:
	_start()
	var car: Unit = service.state.add_unit(2, 0, Vector2i(10, 7), 0)  # броньовик, 3 від танка
	service.state.add_unit(0, 0, Vector2i(10, 2), 0)  # 8 від танка
	var tank: Unit = service.state.add_unit(5, 1, Vector2i(10, 10), 0)
	_begin_all_seen()
	tank.ap = 0  # §3.13: AP ворога не перевіряється
	_watch_inspections()

	controller.peek_cell(tank.pos)

	assert_eq(_inspections.size(), 1)
	var i: Dictionary = _inspections[0]
	assert_eq(i, Targeting.inspection(service.state, tank.id, 0))
	assert_eq(i["center"], Vector2i(10, 10))
	assert_eq(i["radius"], 4)
	assert_eq(i["drone_radius"], 0)
	assert_eq(i["marked"], [car.id])
	assert_true(i["is_floor"])
	assert_eq(_selections.size(), 0, "огляд — не вибір")

	controller.end_peek()

	assert_eq(_inspections.size(), 2)
	assert_eq(_inspections[1], {}, "відпускання знімає огляд")


func test_peek_on_empty_ground_shows_selected_unit_ring() -> void:
	_start()
	var car: Unit = service.state.add_unit(2, 0, Vector2i(10, 7), 0)
	service.state.add_unit(5, 1, Vector2i(10, 10), 0)
	_begin_all_seen()
	controller.tap_cell(car.pos)
	_watch_inspections()

	controller.peek_cell(Vector2i(3, 3))

	assert_eq(_inspections, [Targeting.inspection(service.state, car.id, 0)] as Array[Dictionary])
	assert_eq(_inspections[0]["radius"], 3)


func test_peek_on_empty_ground_without_selection_shows_nothing() -> void:
	_start()
	service.state.add_unit(2, 0, Vector2i(10, 7), 0)
	_begin_all_seen()
	_watch_inspections()

	controller.peek_cell(Vector2i(3, 3))
	controller.end_peek()

	assert_eq(_inspections, [] as Array[Dictionary], "нічого не показано — нічого й знімати")


## Під пальцем ворог, вибрано свого — кільце ворога; вибір і прев'ю лишаються як були.
func test_peek_changes_no_selection_and_no_pending() -> void:
	_start()
	var car: Unit = service.state.add_unit(2, 0, Vector2i(10, 7), 0)
	var tank: Unit = service.state.add_unit(5, 1, Vector2i(10, 10), 0)
	_begin_all_seen()
	controller.tap_cell(car.pos)
	controller.tap_cell(Vector2i(11, 7))
	var facing: int = car.facing
	var sel: int = _selections.size()
	var prev: int = _previews.size()
	var cleared: int = _pending_cleared_count
	service.take_events()
	_watch_inspections()

	controller.peek_cell(tank.pos)
	controller.end_peek()

	assert_eq(_inspections[0]["marked"], [car.id], "кільце ворога під пальцем")
	assert_eq(_selections.size(), sel)
	assert_eq(_previews.size(), prev)
	assert_eq(_pending_cleared_count, cleared)
	assert_eq(car.facing, facing, "огляд не повертає")
	assert_true(service.take_events().is_empty(), "огляд нічого не подає")
	controller.tap_cell(Vector2i(11, 7))
	assert_eq(car.pos, Vector2i(11, 7), "відкладений рух пережив огляд")


func test_own_unit_peek_at_zero_ap_has_ring_and_no_marks() -> void:
	_start()
	var car: Unit = service.state.add_unit(2, 0, Vector2i(10, 7), 0)
	service.state.add_unit(5, 1, Vector2i(10, 10), 0)
	_begin_all_seen()
	car.ap = 0
	_watch_inspections()

	controller.peek_cell(car.pos)

	assert_eq(_inspections[0]["radius"], 3)
	assert_eq(_inspections[0]["marked"], [], "AP 0 — стріляти нікуди")
	assert_false(_inspections[0]["is_floor"])


func test_peek_on_unseen_enemy_is_empty_ground() -> void:
	_start()
	var car: Unit = service.state.add_unit(2, 0, Vector2i(0, 0), 0)
	var enemy: Unit = service.state.add_unit(5, 1, Vector2i(19, 19), 0)
	_begin_and_drain()
	assert_false(service.state.vision[0].is_seen(enemy.pos), "передумова: земля не розвідана")
	controller.tap_cell(car.pos)
	_watch_inspections()

	controller.peek_cell(enemy.pos)

	assert_eq(_inspections, [Targeting.inspection(service.state, car.id, 0)] as Array[Dictionary],
		"невидимий ворог — як порожня земля: кільце вибраного")


func test_own_squad_peek_splits_gun_and_drone() -> void:
	_start()
	var squad: Unit = service.state.add_unit(1, 0, Vector2i(10, 10), 0)
	var inf: Unit = service.state.add_unit(0, 1, Vector2i(10, 13), 0)  # 3 — гармата; дрон піхоту не б'є
	var tank: Unit = service.state.add_unit(5, 1, Vector2i(10, 15), 0)  # 5 — лише дрон
	_begin_all_seen()
	_watch_inspections()

	controller.peek_cell(squad.pos)

	assert_eq(_inspections[0]["radius"], 3)
	assert_eq(_inspections[0]["drone_radius"], DroneCommand.RANGE)
	assert_eq(_inspections[0]["marked"], [inf.id])
	assert_eq(_inspections[0]["drone_marked"], [tank.id])


## battle_screen на TurnStarted кличе select_unit(null) до показу гейта.
func test_peek_cleared_by_handover_deselect() -> void:
	_start()
	var tank: Unit = service.state.add_unit(5, 1, Vector2i(10, 10), 0)
	service.state.add_unit(2, 0, Vector2i(10, 7), 0)
	_begin_all_seen()
	_watch_inspections()
	controller.peek_cell(tank.pos)

	controller.select_unit(null)

	assert_eq(_inspections.size(), 2)
	assert_eq(_inspections[-1], {})


# --- Тап повертає вибраного юніта (TurnCommand, §3.4) ------------------------

func _turned_events() -> Array[Events.BattleEvent]:
	var out: Array[Events.BattleEvent] = []
	for e in service.take_events():
		if e is Events.UnitTurned:
			out.append(e)
	return out


func test_tap_with_selection_turns_unit_toward_cell_without_spending_ap() -> void:
	_start()
	var u: Unit = service.state.add_unit(5, 0, Vector2i(5, 5), 0)
	_begin_and_drain()
	controller.tap_cell(u.pos)
	var ap: int = u.ap
	var target := Vector2i(5, 15)  # поза зоною — лише поворот
	assert_ne(u.facing, Board.facing_towards(u.pos, target), "передумова")

	controller.tap_cell(target)

	assert_eq(u.facing, Board.facing_towards(u.pos, target))
	assert_eq(u.ap, ap)
	assert_eq(_turned_events().size(), 1)
	assert_eq(_selections.size(), 1, "вибір лишився")


func test_tap_at_zero_ap_does_not_turn_and_taps_keep_their_meaning() -> void:
	_start()
	var car: Unit = service.state.add_unit(2, 0, Vector2i(5, 5), 0)
	var tank: Unit = service.state.add_unit(5, 1, Vector2i(5, 7), 0)
	_begin_all_seen()
	controller.tap_cell(car.pos)
	car.ap = 0
	var facing: int = car.facing

	controller.tap_cell(Vector2i(9, 9))
	controller.tap_cell(tank.pos)

	assert_eq(car.facing, facing)
	assert_eq(_turned_events().size(), 0)
	assert_eq(_previews.size(), 0, "на 0 AP пострілу немає")
	controller.tap_cell(car.pos)
	assert_eq(_selections.back(), null, "тап по своєму тайлу й далі знімає вибір")


func test_tap_on_enemy_turns_and_previews_shot_with_unchanged_numbers() -> void:
	_start()
	var car: Unit = service.state.add_unit(2, 0, Vector2i(5, 5), 0)
	var tank: Unit = service.state.add_unit(5, 1, Vector2i(7, 5), 0)
	_begin_all_seen()
	controller.tap_cell(car.pos)
	var want: Dictionary = FireCommand.preview(service.state, car.id, tank.id)
	assert_ne(car.facing, Board.facing_towards(car.pos, tank.pos), "передумова")

	controller.tap_cell(tank.pos)

	assert_eq(car.facing, Board.facing_towards(car.pos, tank.pos))
	assert_eq(_previews.size(), 1)
	assert_eq(_previews[0]["sector"], want["sector"])
	assert_eq(_previews[0]["min"], want["min"])
	assert_eq(_previews[0]["max"], want["max"])


func test_tap_on_own_tile_or_other_own_unit_does_not_turn() -> void:
	_start()
	var u: Unit = service.state.add_unit(5, 0, Vector2i(5, 5), 0)
	var other: Unit = service.state.add_unit(5, 0, Vector2i(5, 9), 0)
	_begin_and_drain()
	controller.tap_cell(u.pos)
	var facing: int = u.facing

	controller.tap_cell(other.pos)
	controller.tap_cell(u.pos)
	controller.tap_cell(u.pos)

	assert_eq(u.facing, facing)
	assert_eq(_turned_events().size(), 0)


func test_tap_in_engineer_or_drone_mode_does_not_turn() -> void:
	_start()
	var eng: Unit = service.state.add_unit(ENGINEER_TYPE, 0, Vector2i(5, 5), 0)
	var sq: Unit = service.state.add_unit(1, 0, Vector2i(10, 10), 0)
	service.state.add_unit(5, 1, Vector2i(10, 13), 0)
	_begin_and_drain()
	controller.tap_cell(eng.pos)
	controller.arm_engineer(LAY)
	var eng_facing: int = eng.facing
	controller.tap_cell(Vector2i(5, 15))
	assert_eq(eng.facing, eng_facing, "верба інженера")

	controller.tap_cell(sq.pos)
	controller.arm_drone()
	var sq_facing: int = sq.facing
	controller.tap_cell(Vector2i(17, 17))
	assert_eq(sq.facing, sq_facing, "озброєний дрон")
	assert_eq(_turned_events().size(), 0)


func test_pending_move_survives_the_turn_and_second_tap_confirms() -> void:
	_start()
	var u: Unit = service.state.add_unit(5, 0, Vector2i(5, 5), 0)
	_begin_and_drain()
	controller.tap_cell(u.pos)
	var target := Vector2i(5, 7)

	controller.tap_cell(target)

	assert_eq(u.facing, Board.facing_towards(Vector2i(5, 5), target), "перший тап повертає")
	assert_eq(_previews.size(), 1)
	assert_eq(_previews[0]["type"], InputController.ActionType.MOVE)
	assert_true(controller.has_cancelable(), "відкладений рух лишився")

	controller.tap_cell(target)

	assert_eq(u.pos, target, "другий тап підтверджує")
