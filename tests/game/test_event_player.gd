extends GutTest
## Task 2.6: EventPlayer програє впорядкований потік подій core/ так, як
## вирішив core/ — без власних розрахунків. Тут перевіряємо: повноту
## таблиці обробників (R6, проти списку, добутого з самого core/events.gd),
## збереження порядку, контракт is_playing()/playback_finished, легальний
## no-op для юніта поза туманом (R18) і поведінку повторного виклику play()
## під час програвання.
##
## Твіни прокручуються вручну через Tween.custom_step (той самий прийом, що
## й tests/game/test_unit_view.gd) — await на реальному сигналі тут не
## використовується, щоб тест не міг зависнути.

var player: EventPlayer


func before_each() -> void:
	player = EventPlayer.new()


func _unit(id: int, type_id: int = 5, owner: int = 0, pos: Vector2i = Vector2i(0, 0)) -> Unit:
	return Unit.create(id, type_id, owner, pos, 0)


func _spawn_view(id: int, type_id: int = 5, owner: int = 0, pos: Vector2i = Vector2i(0, 0)) -> UnitView:
	var scene := preload("res://game/battle/unit_view.tscn")
	var view: UnitView = scene.instantiate()
	add_child_autofree(view)
	view.bind(_unit(id, type_id, owner, pos))
	return view


## Прокручує вручну (Tween.custom_step, той самий прийом, що й
## test_unit_view.gd) усі твіни, які зараз обробляє дерево сцени —
## EventPlayer не віддає посилання на конкретний твін, а bind() сам собі
## заводить короткий _face_tween (навіть нульового повороту), тож "рівно
## один твін" — крихке припущення. Прокрутка до кінця байдужого твіна не
## шкодить: він і так має завершитись, просто раніше, ніж тест його чекав.
func _finish_all_processed_tweens() -> void:
	for t in Engine.get_main_loop().get_processed_tweens():
		if t.is_valid():
			t.custom_step(10.0)


# --- Ruling R6: повнота таблиці обробників ------------------------------

## Список імен класів подій, добутий безпосередньо з core/events.gd текстом
## файлу — навмисно НЕ з EventPlayer.HANDLERS.keys(), інакше порожня
## таблиця пройшла б тест мовчки (саме та діра, яку описує R6).
func _event_class_names_from_source() -> Array[String]:
	var source: String = FileAccess.get_file_as_string("res://core/events.gd")
	var rx := RegEx.new()
	rx.compile("\\nclass (\\w+) extends (\\w+):")
	var names: Array[String] = []
	for m in rx.search_all(source):
		var found: String = m.get_string(1)
		if found == "BattleEvent":
			continue
		names.append(found)
	return names


func test_handlers_table_covers_every_concrete_event_class_in_events_gd() -> void:
	var expected: Array[String] = _event_class_names_from_source()
	assert_true(expected.size() > 0, "розбір core/events.gd мусив знайти хоча б один клас — інакше сам тест зламаний")

	var missing: Array[String] = []
	for name in expected:
		if not EventPlayer.HANDLERS.has(name):
			missing.append(name)
	assert_eq(missing.size(), 0, "у EventPlayer.HANDLERS бракує обробників для: %s" % [missing])
	assert_eq(EventPlayer.HANDLERS.size(), expected.size(),
		"EventPlayer.HANDLERS мусить мати рівно по одному запису на кожен із %d конкретних класів events.gd, має %d" % [expected.size(), EventPlayer.HANDLERS.size()])


## HANDLERS покриває всі 23 імені (перевірено вище), але саме розгалуження
## в _dispatch — окремий, вручну веденний if/elif (Godot не дає рефлексії
## імені для анонімних вкладених класів core/events.gd). Ця перевірка ловить
## розсинхрон між ними: по одному екземпляру кожного з 23 конкретних класів
## (той самий набір, що й tests/core/test_events.gd) мусить пройти через
## play() без застрягання на "необроблений тип" — жодна подія тут не
## посилається на існуючий юніт, тож усі обробники відпрацюють як no-op,
## і единий провал буде саме пропущена гілка диспетчеризації.
func test_dispatch_handles_every_concrete_event_instance_without_falling_through() -> void:
	var all_events: Array[Events.BattleEvent] = [
		Events.UnitMoved.new(1, [Vector2i(0, 0)], 0),
		Events.UnitTurned.new(1, 3),
		Events.MoveBlocked.new(1, Vector2i(2, 0)),
		Events.ShotFired.new(1, 2, UnitTypes.ArmourSector.FRONT),
		Events.ShotRetaliated.new(2, 1, UnitTypes.ArmourSector.SIDE),
		Events.DroneLaunched.new(1, 2, 1),
		Events.DamageDealt.new(2, 40, 60),
		Events.UnitDestroyed.new(2, Vector2i(3, 3)),
		Events.TileRevealed.new(0, [Vector2i(1, 1), Vector2i(1, 2)]),
		Events.MinePlaced.new(Vector2i(4, 4), 0),
		Events.MineCleared.new(Vector2i(4, 4)),
		Events.MineTriggered.new(Vector2i(5, 5), 3),
		Events.MineRevealed.new(Vector2i(5, 5), 1),
		Events.BridgeChanged.new(Vector2i(6, 6), true),
		Events.UnitRepaired.new(4, 20, 80),
		Events.ObjectiveCaptured.new(0, 1),
		Events.ObjectiveDestroyed.new(1),
		Events.ExperienceGained.new(0, UnitTypes.UnitClass.TANK, 2),
		Events.ApChanged.new(1, 30),
		Events.TurnEnded.new(0),
		Events.TurnStarted.new(1, 5),
		Events.PlayerEliminated.new(2),
		Events.MatchEnded.new(0),
	]
	assert_eq(all_events.size(), EventPlayer.HANDLERS.size(), "перевіряємо рівно стільки ж екземплярів, скільки записів у HANDLERS")
	await player.play(all_events)
	assert_false(player.is_playing(), "порожній лукап без жодного видимого юніта все одно доводить масив до кінця")


func test_every_event_type_has_a_handler() -> void:
	for name in EventPlayer.HANDLERS.keys():
		assert_true(player.has_method(EventPlayer.HANDLERS[name]),
			"подія %s не має обробника — вона мовчки зникне з екрана" % name)


# --- is_playing() / playback_finished контракт ---------------------------

func test_is_playing_false_before_and_after_empty_playback() -> void:
	assert_false(player.is_playing(), "до play() програвання не йде")
	var empty: Array[Events.BattleEvent] = []
	await player.play(empty)
	assert_false(player.is_playing(), "після завершення play() програвання не йде")


func test_is_playing_true_during_animated_playback_and_signal_fires_after() -> void:
	var view: UnitView = _spawn_view(1)
	player = EventPlayer.new(func(unit_id: int) -> UnitView:
		return view if unit_id == 1 else null)

	var events: Array[Events.BattleEvent] = [
		Events.UnitMoved.new(1, [Vector2i(1, 0)], 0),
	]

	# Масив, не bool: лямбда в GDScript захоплює локальні змінні ЗА ЗНАЧЕННЯМ
	# (копія на момент створення), тож `finished_signal_seen = true` всередині
	# лямбди змінило б лише її власну копію. Array/Dictionary — посилання,
	# тож мутація вмісту видна й зовні лямбди.
	var finished_signal_seen: Array[bool] = [false]
	player.playback_finished.connect(func(): finished_signal_seen[0] = true)

	player.play(events)  # не await — хочемо перевірити стан ПІД час програвання
	assert_true(player.is_playing(), "is_playing() мусить бути true від входу в play() до playback_finished")
	assert_false(finished_signal_seen[0], "сигнал ще не мав прийти — твін ще не прокручений")

	_finish_all_processed_tweens()

	assert_true(finished_signal_seen[0], "playback_finished мусить прийти по завершенню програвання")
	assert_false(player.is_playing(), "is_playing() мусить стати false не пізніше playback_finished — вікна, де воно false, а анімація ще йде, бути не може")


# --- Порядок програвання ---------------------------------------------------

## Порядок доводимо на побічному ефекті, чутливому до послідовності:
## DamageDealt без відомого максимуму бере hp_left+amount за максимум,
## UnitRepaired без відомого максимуму бере hp_left. Якщо ушкодження
## відіграється першим (як у масиві), другий виклик (ремонт) успадковує вже
## встановлений максимум — підсумкове відношення інше, ніж було б при
## переставлених подіях. Так тест ловить перестановку, а не лише «щось
## відбулось».
func test_play_preserves_event_order() -> void:
	var view: UnitView = _spawn_view(1)
	player = EventPlayer.new(func(unit_id: int) -> UnitView:
		return view if unit_id == 1 else null)

	var events: Array[Events.BattleEvent] = [
		Events.DamageDealt.new(1, 50, 50),   # -> максимум зафіксовано як 100
		Events.UnitRepaired.new(1, 20, 70),  # -> використовує вже відомий максимум 100
	]
	await player.play(events)

	assert_almost_eq(view._hp_bar.scale.x, 0.7, 0.001,
		"у правильному порядку ремонт після ушкодження мусить дати 70/100, а не 70/70")


## Пряме доведення порядку через журнал резолюцій лукапа: масив із різними
## unit_id мусить дати той самий порядок звернень до лукапа.
func test_play_resolves_units_in_array_order_not_reshuffled() -> void:
	var view_a: UnitView = _spawn_view(1)
	var view_b: UnitView = _spawn_view(2)
	var resolved_order: Array[int] = []
	player = EventPlayer.new(func(unit_id: int) -> UnitView:
		resolved_order.append(unit_id)
		if unit_id == 1:
			return view_a
		if unit_id == 2:
			return view_b
		return null)

	var events: Array[Events.BattleEvent] = [
		Events.DamageDealt.new(2, 10, 90),
		Events.DamageDealt.new(1, 10, 90),
		Events.DamageDealt.new(2, 10, 80),
	]
	await player.play(events)

	assert_eq(resolved_order, [2, 1, 2], "порядок звернень до лукапа мусить точно повторювати порядок масиву подій")


## Доводить, що play() справді ЧЕКАЄ анімацію (не лише запускає її) —
## наступна подія в масиві не має торкнутись свого юніта, поки твін
## попередньої не прокручено вручну.
func test_play_awaits_animation_before_dispatching_next_event() -> void:
	var view: UnitView = _spawn_view(1)
	var resolved_order: Array[int] = []
	player = EventPlayer.new(func(unit_id: int) -> UnitView:
		resolved_order.append(unit_id)
		return view if unit_id == 1 else null)

	var events: Array[Events.BattleEvent] = [
		Events.UnitMoved.new(1, [Vector2i(1, 0)], 0),
		Events.UnitTurned.new(1, 2),
	]
	player.play(events)  # не await — перевіряємо проміжний стан

	assert_eq(resolved_order, [1], "другу подію не можна торкати, поки перша анімація не завершилась")

	_finish_all_processed_tweens()

	assert_eq(resolved_order, [1, 1], "після завершення твіна наступна подія в черзі мусить розв'язатись")
	assert_false(player.is_playing(), "по завершенню обох подій програвання закінчено")


# --- R18: юніт поза туманом — легальний no-op -----------------------------

func test_event_naming_unknown_unit_id_is_skipped_without_error_and_rest_still_plays() -> void:
	var view: UnitView = _spawn_view(2)
	# Лукап навмисно не знає unit_id=1 — імітує ворога поза `seen` (§3.5):
	# core/ однаково шле подію, вузла для неї просто нема.
	player = EventPlayer.new(func(unit_id: int) -> UnitView:
		return view if unit_id == 2 else null)

	var events: Array[Events.BattleEvent] = [
		Events.DamageDealt.new(1, 10, 90),  # юніт поза туманом — має тихо пропуститись
		Events.DamageDealt.new(2, 30, 70),  # цей мусить все одно відіграти
	]
	await player.play(events)

	assert_almost_eq(view._hp_bar.scale.x, 0.7, 0.001, "подія для видимого юніта після пропущеної мусить все одно застосуватись")


func test_no_lookup_injected_is_also_a_legal_no_op() -> void:
	# Конструктор без аргументів (як у brief-тесті) — Callable за замовчуванням
	# невалідний; жодна подія, що звертається до юніта, не має кинути помилку.
	var events: Array[Events.BattleEvent] = [
		Events.DamageDealt.new(1, 10, 90),
		Events.UnitTurned.new(1, 3),
	]
	await player.play(events)
	assert_false(player.is_playing(), "порожній лукап не має завадити програванню завершитись")


# --- Повторний виклик play() під час програвання --------------------------

## Рішення: реентрантний виклик — помилка виклику (наступний коментар у
## самому event_player.gd пояснює чому), а не легітимна черга. Тут
## перевіряємо релізну (без assert) поведінку: другий виклик тихо
## ігнорується, перше програвання не переривається і завершується штатно.
func test_reentrant_play_call_is_ignored_and_first_playback_completes() -> void:
	var view: UnitView = _spawn_view(1)
	player = EventPlayer.new(func(unit_id: int) -> UnitView:
		return view if unit_id == 1 else null)

	var first_events: Array[Events.BattleEvent] = [
		Events.UnitMoved.new(1, [Vector2i(1, 0)], 0),
	]
	var second_events: Array[Events.BattleEvent] = [
		Events.UnitTurned.new(1, 5),
	]

	player.play(first_events)  # не await — лишається "у польоті"
	assert_true(player.is_playing())

	player.play(second_events)  # реентрантний виклик — має бути проігнорований
	assert_true(player.is_playing(), "перше програвання мусить лишитись активним після проігнорованого другого виклику")

	_finish_all_processed_tweens()

	assert_false(player.is_playing(), "перше програвання таки завершується штатно")
