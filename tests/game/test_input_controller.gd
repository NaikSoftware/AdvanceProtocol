extends GutTest
## Task 2.7: тап → намір → Command. Жива battle_screen.tscn з'являється лише в
## Task 2.10 (ручна перевірка «вибрав → пішов → вистрілив» відкладена туди,
## R25), тож тут — headless перевірка контролера як чистого обʼєкта: власний
## MatchService на тест (той самий прийом, що й test_match_service.gd — окремий
## інстанс, а не спільний автозавантажений синглтон, щоб тести не текли
## станом одне в одного), шпигун замість справжнього ZoneOverlay.

const MatchServiceScript := preload("res://game/autoload/match_service.gd")

## Шпигун замість справжнього ZoneOverlay: не тримає жодного BoardView (той
## вимагав би живої сцени й наштовхнувся б на ту саму MultiMesh-заглушку під
## headless, що й test_zone_overlay.gd, R4/R16), а лише запам'ятовує останній
## виклик. Тест звіряється з тим, ЩО порахував InputController (сам обʼєкт
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
	var target := Vector2i(6, 5)  # сусідня клітинка, точно в межах зони танка

	controller.tap_cell(target)

	assert_eq(u.pos, start_pos, "прев'ю не мусить рухати юніт")
	assert_eq(u.ap, start_ap, "прев'ю не мусить витрачати AP")
	assert_true(service.take_events().is_empty(), "прев'ю не мусить лишати подій у черзі")

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


func test_cancel_pending_clears_pending_and_submits_nothing() -> void:
	_start()
	var u: Unit = service.state.add_unit(5, 0, Vector2i(5, 5), 0)
	_begin_and_drain()
	controller.tap_cell(u.pos)
	controller.tap_cell(Vector2i(6, 5))

	controller.cancel_pending()

	assert_eq(u.pos, Vector2i(5, 5), "cancel_pending() не мусить рухати юніт")
	assert_true(service.take_events().is_empty())

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

	assert_true(service.take_events().is_empty(), "прев'ю пострілу не мусить нічого подавати")
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


# --- Ревʼю: _zones мусять описувати ПОТОЧНИЙ стан, не стан на момент вибору --
#
# Знахідка ревʼю: до фіксу _zones рахувалися рівно один раз, у select_unit(),
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
	var target: Unit = service.state.add_unit(11, 1, Vector2i(6, 5), 0)  # engineer squad
	_begin_and_drain()
	controller.tap_cell(u.pos)
	# Передумова: (7,5) — усередині ЗІ старого AP=48 зони (2 клітинки, cost 20).
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
## (60 AP) лишаються в межах зони. Його ромб огляду — лише 3, тож клітинка на
## відстані Менхеттена 4 йому НЕ видна: жодна розвідка її не торкалася.
## Ворог, що стоїть саме там, — точний тест R5: known_occupied_map(active)
## не знає про нього (тайл ніколи не seen), тож зона мусить включати його
## клітинку. occupied_map() (всезнаюча) натомість виключила б цю клітинку
## цілком — Pathing ніколи не кладе зайняту клітинку в cost-мапу, тож
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
