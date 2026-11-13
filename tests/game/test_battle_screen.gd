extends GutTest
## Task 2.10: збірка зрізу. Headless-перевірка обіцянок, які належать саме
## цьому файлу, а не жодному з Task 2.1–2.9 (ті вже покриті власними тестами):
## порядок старту (R1), початковий туман зі стану, а не з подій (R9),
## фог-правило §3.5 (жодного вузла без known_occupied_map), і порядок гейта
## передачі ходу (R7) — рекон і перебудова ДО того, як гейт закриється.

const BattleScreenScene := preload("res://game/battle/battle_screen.tscn")
const UnitModelFixture := preload("res://tests/fixtures/unit_model_fixture.gd")
const MatchServiceScript := preload("res://game/autoload/match_service.gd")

## Шпигун лише над submit(): рахує, скільки разів і якою командою сцена
## справді торкнулася core/, не покладаючись на побічні ефекти (AP, позицію),
## які інша команда могла б відтворити випадково.
class SpyMatchService extends MatchServiceScript:
	var submitted: Array[Command] = []
	func submit(command: Command) -> String:
		submitted.append(command)
		return super.submit(command)


func _map(width: int = 6, height: int = 6) -> MapData:
	var m := MapData.new()
	m.width = width
	m.height = height
	m.ground_state = Terrain.GroundState.DRY
	var tiles := PackedInt32Array()
	tiles.resize(width * height)
	tiles.fill(Terrain.Kind.FIELD)
	m.tiles = tiles
	return m


## Engine.max_fps — стан усього процесу: тест, що впав, не сміє лишити обмеження решті набору.
var _fps_before: int = 0


func before_each() -> void:
	_fps_before = Engine.max_fps
	# Інші екрани (меню) лишають своє обмеження; бій повертає саме його, тож старт — без обмеження.
	Engine.max_fps = 0


func after_each() -> void:
	Engine.max_fps = _fps_before
	WeatherRig.sun_ground = Vector2.ZERO
	UnitSilhouettes.reset_models()


func _screen() -> Node3D:
	var screen: Node3D = BattleScreenScene.instantiate()
	add_child_autofree(screen)
	return screen


# --- R1/R9: два кроки старту, туман зі стану ------------------------------

func test_setup_runs_start_populate_begin_in_order_and_primes_every_players_vision() -> void:
	var service: Node = MatchServiceScript.new()
	add_child_autofree(service)
	var m: MapData = _map()
	# Юніти поруч, обидва в межах ромба огляду один одного (ромб медіум-танка — 4).
	m.spawns = [
		{"type_id": 5, "owner": 0, "pos": Vector2i(2, 2), "facing": 0},
		{"type_id": 5, "owner": 1, "pos": Vector2i(3, 2), "facing": 0},
	] as Array[Dictionary]
	var screen: Node3D = _screen()

	screen.setup(m, 2, 1, service)

	# begin() відпрацював: перший хід активний, AP гравця 0 повне.
	assert_eq(service.state.turn_number, 1)
	assert_eq(service.state.active_player, 0)
	assert_eq(service.state.units.size(), 2, "populate() мусить додати обох юнітів ДО begin()")

	# R1/core/battle_state.gd:44 — БЕЗ start() vision гравця, чий хід ще не
	# настав, лишається порожньою: тут це навпаки, і саме це доводить, що
	# state.start() справді відпрацював для КОЖНОГО гравця.
	assert_true(service.state.vision[0].is_seen(Vector2i(2, 2)))
	assert_true(service.state.vision[1].is_seen(Vector2i(3, 2)))

	# R9: ворог гравця 0 видимий ЙОМУ від самого початку — вузол побудований
	# зі стану (known_occupied_map -> vision.seen), хоча TileRevealed
	# початкового ходу в потоці подій відсутній узагалі (state.start()
	# відкидає його, core/battle_state.gd:57-70).
	var enemy_id: int = service.state.unit_at(Vector2i(3, 2)).id
	assert_not_null(screen.unit_view_for(enemy_id), "ворог у ромбі огляду мусить мати вузол одразу після setup()")


# --- §3.5: жодного вузла без known_occupied_map ----------------------------

func test_enemy_unit_outside_known_occupied_map_has_no_node() -> void:
	var service: Node = MatchServiceScript.new()
	add_child_autofree(service)
	var m: MapData = _map(20, 20)
	m.spawns = [
		{"type_id": 2, "owner": 0, "pos": Vector2i(1, 1), "facing": 0},  # armoured car, ромб 3
		{"type_id": 5, "owner": 1, "pos": Vector2i(18, 18), "facing": 0},  # далеко поза будь-яким ромбом
	] as Array[Dictionary]
	var screen: Node3D = _screen()

	screen.setup(m, 2, 1, service)

	var enemy_id: int = service.state.unit_at(Vector2i(18, 18)).id
	assert_false(service.state.vision[0].is_seen(Vector2i(18, 18)), "передумова: клітинка нерозвідана")
	assert_null(screen.unit_view_for(enemy_id), "нерозвіданий ворог не мусить лишати жодного сліду на дошці")


func test_enemy_on_seen_ground_has_a_node_even_when_not_currently_visible() -> void:
	# Гейт — is_seen, не is_visible (§3.5): розвідка незворотна. Тут це
	# перевіряється напряму, підмінюючи сітку видимості так, щоб тайл
	# була seen, але НЕ visible просто зараз — саме та відмінність, яку
	# ловить is_seen() і яку прогледів би is_visible().
	var service: Node = MatchServiceScript.new()
	add_child_autofree(service)
	var m: MapData = _map(20, 20)
	m.spawns = [
		{"type_id": 2, "owner": 0, "pos": Vector2i(1, 1), "facing": 0},
		{"type_id": 5, "owner": 1, "pos": Vector2i(18, 18), "facing": 0},
	] as Array[Dictionary]
	var screen: Node3D = _screen()
	screen.setup(m, 2, 1, service)
	var enemy: Unit = service.state.unit_at(Vector2i(18, 18))

	var vision: Vision = service.state.vision[0]
	var index: int = Vector2i(18, 18).y * m.width + Vector2i(18, 18).x
	vision.seen[index] = 1
	vision.visible[index] = 0
	assert_false(vision.is_visible(enemy.pos), "передумова: не під наглядом просто зараз")
	assert_true(vision.is_seen(enemy.pos), "передумова: але вже розвідана")

	screen._rebuild_units_for_active_player()

	assert_not_null(screen.unit_view_for(enemy.id), "давно розвідана земля лишає ворога видимим — is_seen, не is_visible")


# --- R7: рекон і перебудова ДО того, як гейт закриється --------------------

func test_handover_rebuilds_units_and_recenters_camera_before_gate_lifts() -> void:
	var service: Node = MatchServiceScript.new()
	add_child_autofree(service)
	var m: MapData = _map()
	m.spawns = [
		{"type_id": 5, "owner": 0, "pos": Vector2i(1, 1), "facing": 0},
		{"type_id": 5, "owner": 1, "pos": Vector2i(4, 4), "facing": 0},
	] as Array[Dictionary]
	var screen: Node3D = _screen()
	screen.setup(m, 2, 1, service)

	var gate: Control = screen.get_node("%HandoverGate")
	var units_container: Node3D = screen.get_node("%Units")
	var camera: IsoCameraRig = screen.get_node("%CameraRig")

	var end_turn_button: Button = screen.get_node("%Hud").get_node("%EndTurnButton")
	end_turn_button.pressed.emit()

	assert_true(gate.visible, "перехід ходу мусить показати гейт")
	# До підтвердження вузли ще належать попередньому гравцеві — гейт
	# зобов'язаний ховати екран, поки триває саме це.
	var p1_unit_id: int = service.state.units_of(1)[0].id
	assert_null(screen.unit_view_for(p1_unit_id), "передумова: до confirmed дошка ще не перебудована під гравця 1")

	# Лямбда захоплює локальні змінні КОПІЄЮ значення на момент створення
	# (GDScript), тож будь-яке присвоєння всередині watcher() на зовнішні
	# bool/int не поширилося б назовні — Dictionary лишається тим самим
	# об'єктом за посиланням, і саме тому спостереження записується сюди.
	var observation: Dictionary = {"observed": false, "gate_was_visible": false}
	var watcher := func(_n: Node) -> void:
		observation["observed"] = true
		observation["gate_was_visible"] = gate.visible
	units_container.child_entered_tree.connect(watcher)

	var confirm_button: Button = gate.get_node("%ConfirmButton")
	confirm_button.pressed.emit()

	assert_true(observation["observed"], "перебудова мусить справді додати хоч один вузол юніта гравця 1")
	assert_true(observation["gate_was_visible"],
		"вузол юніта мусить з'явитися, ПОКИ гейт ще видимий — не після його закриття")
	assert_false(gate.visible, "після виконання confirmed гейт мусить закритися")

	assert_not_null(screen.unit_view_for(p1_unit_id), "після confirmed дошка мусить показувати юнітів гравця 1")
	assert_eq(camera.global_position, IsoCameraRig.cell_to_world(service.state.units_of(1)[0].pos),
		"камера мусить рецентруватися на перший юніт гравця, що заходить")
	# §3.5: дахи — одразу в стані нового гравця, без переходу через кадри після гейта.
	var props: PropLayer = (screen.get_node("%BoardView") as BoardView).props()
	for i in props._fade_target:
		assert_eq(float(props._fade_level.get(i, 0.0)), float(props._fade_target[i]), "дах %d ще в переході після гейта" % i)
	assert_false(props.is_processing(), "після гейта розчинення не доходить кадрами")


## Спільні MultiMesh смуг HP і плям-контакту після передачі ходу тримають рівно тих юнітів, яких знає
## гравець, що заходить: ні чужих (§3.5), ні вже звільнених.
func test_handover_batches_track_exactly_the_incoming_players_known_units() -> void:
	var service: Node = MatchServiceScript.new()
	add_child_autofree(service)
	var m: MapData = _map()
	m.spawns = [
		{"type_id": 5, "owner": 0, "pos": Vector2i(1, 1), "facing": 0},
		{"type_id": 0, "owner": 0, "pos": Vector2i(2, 1), "facing": 0},
		{"type_id": 5, "owner": 1, "pos": Vector2i(4, 4), "facing": 0},
	] as Array[Dictionary]
	var screen: Node3D = _screen()
	screen.setup(m, 2, 1, service)
	WeatherRig.unit_contact = 0.6
	screen.get_node("%Hud").get_node("%EndTurnButton").pressed.emit()
	screen.get_node("%HandoverGate").get_node("%ConfirmButton").pressed.emit()
	var known: int = service.state.known_occupied_map(service.state.active_player).size()
	assert_gt(known, 0, "передумова: гравець, що заходить, знає юнітів")
	assert_eq(screen._hp_bars.count(), known, "смуги HP — рівно відомі юніти")
	assert_eq(screen._contacts.count(), known, "плями-контакт — рівно відомі юніти")
	assert_not_null(screen._contacts.map, "плями-контакт знають карту: дорога слабшає пляму")
	assert_eq(screen._unit_views.size(), known)
	WeatherRig.unit_contact = 0.0


## §3.5: дим влучання висить кілька секунд; на передачі ходу його прибирають, щоб над
## тайлом, якого гравець, що заходить, не розвідав, не лишилось сліду цілі.
func test_handover_clears_lingering_battle_fx() -> void:
	var service: Node = MatchServiceScript.new()
	add_child_autofree(service)
	var m: MapData = _map()
	m.spawns = [
		{"type_id": 5, "owner": 0, "pos": Vector2i(1, 1), "facing": 0},
		{"type_id": 5, "owner": 1, "pos": Vector2i(4, 4), "facing": 0},
	] as Array[Dictionary]
	var screen: Node3D = _screen()
	screen.setup(m, 2, 1, service)
	var units: Node3D = screen.get_node("%Units")
	var hit: Node3D = BattleFx.spawn_hit(units, IsoCameraRig.cell_to_world(Vector2i(4, 4)), BattleFx.Weapon.SHELL, false)
	assert_false(hit.is_queued_for_deletion(), "передумова: дим ще висить")
	screen.get_node("%Hud").get_node("%EndTurnButton").pressed.emit()
	assert_true(screen.get_node("%HandoverGate").visible)
	assert_true(hit.is_queued_for_deletion(), "гейт прибрав дим попереднього ходу")


# --- Кінець ходу: рівно одна EndTurnCommand --------------------------------

func test_end_turn_button_submits_exactly_one_end_turn_command() -> void:
	var service := SpyMatchService.new()
	add_child_autofree(service)
	var m: MapData = _map()
	m.spawns = [
		{"type_id": 5, "owner": 0, "pos": Vector2i(1, 1), "facing": 0},
		{"type_id": 5, "owner": 1, "pos": Vector2i(4, 4), "facing": 0},
	] as Array[Dictionary]
	var screen: Node3D = _screen()
	screen.setup(m, 2, 1, service)

	var end_turn_button: Button = screen.get_node("%Hud").get_node("%EndTurnButton")
	end_turn_button.pressed.emit()

	assert_eq(service.submitted.size(), 1, "натискання кнопки мусить подати рівно одну команду")
	assert_true(service.submitted[0] is EndTurnCommand, "і саме EndTurnCommand — не будь-яку іншу")


## Сценарій власника дослівно: «дограв, убив усіх юнітів противника і гра
## крешнулась» на assert(err == "") у _on_end_turn_pressed(). Постріл убиває
## останній юніт гравця 1 → FireCommand кличе check_elimination()
## (core/commands/fire_command.gd:166) → winner виставлено ще ДО того, як
## гравець торкнувся кнопки → EndTurnCommand.validate() повертає ERR_MATCH_OVER.
##
## assert лишається на місці й не пом'якшується: він стереже розбіжність
## вигляду з правилами і спіймав цей баг рівно так, як мав. Правильний
## результат — щоб до нього не доходило, бо вигляд не пропонує відхиленої дії.
## Екран результату — Phase 3 (§10 CLAUDE.md); тут дошка просто завмирає.
func test_end_turn_after_the_last_enemy_dies_submits_nothing_and_does_not_crash() -> void:
	var service := SpyMatchService.new()
	add_child_autofree(service)
	var m: MapData = _map()
	m.spawns = [
		{"type_id": 5, "owner": 0, "pos": Vector2i(2, 2), "facing": 0},  # medium tank
		{"type_id": 2, "owner": 1, "pos": Vector2i(3, 2), "facing": 0},  # останній юніт гравця 1
	] as Array[Dictionary]
	var screen: Node3D = _screen()
	screen.setup(m, 2, 1, service)

	var shooter: Unit = service.state.units_of(0)[0]
	var victim: Unit = service.state.units_of(1)[0]
	victim.hp = 1  # §3.3: MIN_DAMAGE = 10, тож будь-яке влучання гарантовано вбиває

	screen.input_controller().tap_cell(shooter.pos)
	screen.input_controller().tap_cell(victim.pos)
	screen.input_controller().confirm_pending()
	# Тягнемо твіни вручну (той самий прийом, що й у test_event_player.gd):
	# без цього програвання смерті лишається в польоті, is_playing() ще true, і
	# кнопку кінця ходу блокував би R24, а не завершений матч — тест перевіряв би
	# не те.
	_finish_all_processed_tweens()

	assert_false(victim.is_alive(), "передумова: останній юніт гравця 1 знищений")
	assert_true(service.state.is_over(), "передумова: матч завершився ще на пострілі")
	var submitted_before: int = service.submitted.size()

	var end_turn_button: Button = screen.get_node("%Hud").get_node("%EndTurnButton")
	end_turn_button.pressed.emit()

	assert_eq(service.submitted.size(), submitted_before,
		"після завершення матчу натискання «завершити хід» не сміє дійти до core/ узагалі")


# --- Тап по дошці: екранна точка -> тайл -> InputController -----------
#
# game/ui/handover_gate.gd, крок 4 контракту: маршрутизація тапів дошки
# зобов'язана йти крізь _unhandled_input(), інакше STOP-фільтр гейта нічого
# не блокує. Тут перевіряється рівно та половина, що належить цьому файлу —
# резолв екранної точки в тайл і передача в InputController.tap_cell();
# те, що гейт справді ковтає ввід GUI-системою раніше за _unhandled_input, —
# уже доведено власними тестами game/ui/handover_gate.gd (STOP-фільтр,
# повнорозмірні anchors) і документованою поведінкою рушія, а не тут.

func test_screen_tap_resolves_through_camera_rig_to_the_tapped_cell() -> void:
	var service: Node = MatchServiceScript.new()
	add_child_autofree(service)
	var m: MapData = _map()
	m.spawns = [{"type_id": 5, "owner": 0, "pos": Vector2i(2, 2), "facing": 0}] as Array[Dictionary]
	var screen: Node3D = _screen()
	screen.setup(m, 2, 1, service)

	var unit: Unit = service.state.units_of(0)[0]
	var camera: IsoCameraRig = screen.get_node("%CameraRig")
	camera.center_on(unit.pos)
	var cam3d: Camera3D = camera.get_node("Yaw/Camera3D")
	var screen_pos: Vector2 = cam3d.unproject_position(IsoCameraRig.cell_to_world(unit.pos))

	var selections: Array = []
	screen.input_controller().selection_changed.connect(func(u: Unit) -> void: selections.append(u))

	screen._handle_tap_at_screen_position(screen_pos)

	assert_eq(selections.size(), 1, "тап по екранній точці юніта мусить дійти до InputController.tap_cell()")
	assert_eq(selections[0], unit)


# --- _ready(): запуск без ін'єкції --------------------------------------
#
# project.godot ставить цю сцену як run/main_scene, і жоден інший виклик
# .setup() у грі поки не існує (SceneRouter.goto_battle() лише міняє сцену,
# без точки ін'єкції MapData — Phase 3). Без цього тесту сцена, запущена
# напряму, лишається інертною: порожня дошка, порожні _unit_views, null
# _controller — і жоден тап по екрану нічого не робить.

func test_fallback_entry_starts_a_default_match_from_the_shipped_map() -> void:
	var screen: Node3D = _screen()
	# _ready() вмикає резерв лише за умови `current_scene == self`, а сцена, додана
	# дочірнім вузлом у тесті, головною ніколи не буває — тож перевіряємо тут
	# сам резервний вхід, а не гейт. Гейт перевіряє тест нижче.
	screen._start_fallback_match_if_not_injected()

	var board_view: Node3D = screen.get_node("%BoardView")
	assert_true(board_view.get_child_count() > 0, "резервний вхід мусить побудувати дошку")

	var units: Node3D = screen.get_node("%Units")
	assert_true(units.get_child_count() > 0, "резервний вхід мусить розставити юнітів на дошці")

	assert_not_null(screen.input_controller(), "резервний вхід мусить підняти InputController")


## Збереження зі шляхом до видаленої карти (фаза 5a прибрала старі п'ять) не мусить
## лишати порожню дошку — бій стартує на запасній «Річці».
func test_a_save_pointing_at_a_deleted_map_falls_back_to_river() -> void:
	var service: Node = MatchServiceScript.new()
	add_child_autofree(service)
	service.configure("res://maps/urban.tres", 2, 1)
	var screen: Node3D = _screen()

	screen.launch(service)

	assert_not_null(service.state, "бій стартував")
	if service.state == null:
		return
	assert_eq(service.state.board.width, 26)
	assert_eq(service.state.board.height, 22)


## Гейт — половина, що захищає решту сьогоднішнього набору: без нього кожен
## тест цього файла отримував би другий, фоновий матч на автозавантаженому
## MatchService поверх власного ізольованого екземпляра.
func test_ready_does_not_start_a_match_when_the_scene_is_not_the_current_one() -> void:
	var screen: Node3D = _screen()

	assert_null(screen.input_controller(),
		"сцена, додана дочірнім вузлом, не мусить піднімати резервний матч у _ready()")
	assert_eq(screen.get_node("%Units").get_child_count(), 0,
		"а отже й жодного юніта на дошці")


# --- Ріг камери: пан драгом, зум колесом/пінчем, драг ≠ тап ----------------
#
# Той самий прийом, що й тест тапу вище: подія йде НАПРЯМУ в _unhandled_input()
# (не крізь справжню доставку рушієм) — маршрутизація крізь Control-дерево й
# STOP-фільтр гейта вже задокументована і перевірена власними тестами
# handover_gate.gd, тут перевіряється лише те, що робить сам _unhandled_input(),
# отримавши подію.

func _mb(screen_pos: Vector2, pressed: bool, button_index: int = MOUSE_BUTTON_LEFT) -> InputEventMouseButton:
	var mb := InputEventMouseButton.new()
	mb.button_index = button_index
	mb.pressed = pressed
	mb.position = screen_pos
	if pressed and button_index == MOUSE_BUTTON_LEFT:
		mb.button_mask = MOUSE_BUTTON_MASK_LEFT
	return mb


func _mm(screen_pos: Vector2, relative: Vector2) -> InputEventMouseMotion:
	var mm := InputEventMouseMotion.new()
	mm.position = screen_pos
	mm.relative = relative
	mm.button_mask = MOUSE_BUTTON_MASK_LEFT
	return mm


func test_press_and_release_without_movement_still_selects_the_unit() -> void:
	var service: Node = MatchServiceScript.new()
	add_child_autofree(service)
	var m: MapData = _map()
	m.spawns = [{"type_id": 5, "owner": 0, "pos": Vector2i(2, 2), "facing": 0}] as Array[Dictionary]
	var screen: Node3D = _screen()
	screen.setup(m, 2, 1, service)

	var unit: Unit = service.state.units_of(0)[0]
	var camera: IsoCameraRig = screen.get_node("%CameraRig")
	camera.center_on(unit.pos)
	var cam3d: Camera3D = camera.get_node("Yaw/Camera3D")
	var screen_pos: Vector2 = cam3d.unproject_position(IsoCameraRig.cell_to_world(unit.pos))

	var selections: Array = []
	screen.input_controller().selection_changed.connect(func(u: Unit) -> void: selections.append(u))

	screen._unhandled_input(_mb(screen_pos, true))
	screen._unhandled_input(_mb(screen_pos, false))

	assert_eq(selections.size(), 1, "натиск-відпуск без зсуву — це тап, юніт мусить бути вибраний")
	assert_eq(selections[0], unit)


## Обов'язковий тест ТЗ: драг за порогом не мусить викликати tap_cell.
func test_drag_past_threshold_does_not_select_a_unit() -> void:
	var service: Node = MatchServiceScript.new()
	add_child_autofree(service)
	var m: MapData = _map(20, 20)
	m.spawns = [{"type_id": 5, "owner": 0, "pos": Vector2i(2, 2), "facing": 0}] as Array[Dictionary]
	var screen: Node3D = _screen()
	screen.setup(m, 2, 1, service)

	var unit: Unit = service.state.units_of(0)[0]
	var camera: IsoCameraRig = screen.get_node("%CameraRig")
	camera.center_on(unit.pos)
	var cam3d: Camera3D = camera.get_node("Yaw/Camera3D")
	var start_pos: Vector2 = cam3d.unproject_position(IsoCameraRig.cell_to_world(unit.pos))
	var end_pos: Vector2 = start_pos + Vector2(50, 0)  # свідомо за порогом ~10dp

	var selections: Array = []
	screen.input_controller().selection_changed.connect(func(u: Unit) -> void: selections.append(u))

	screen._unhandled_input(_mb(start_pos, true))
	screen._unhandled_input(_mm(end_pos, end_pos - start_pos))
	screen._unhandled_input(_mb(end_pos, false))

	assert_true(selections.is_empty(), "драг за порогом — це пан, а не тап: tap_cell не мусить викликатись узагалі")


## Порівняння через саму pan(): якби battle_screen сам щось робив із дельтою
## (крутив, масштабував, інвертував) перед тим, як віддати її pan(), фінальна
## позиція НЕ збіглася б з тим, куди привела б одна пряма pan(delta) на
## еталонному ризі. Дельта свідомо за порогом драга (менша лишилась би
## непроведеною зовсім — див. тест порога нижче) і доставлена ОДНИМ стрибком,
## що перетинає поріг: саме тоді _advance_drag() робить один pan() на всю
## накопичену дельту від натиску — рівно те, з чим тут звіряємось.
func test_drag_forwards_the_raw_screen_delta_to_pan_unmodified() -> void:
	var m: MapData = _map(20, 20)
	var delta := Vector2(30.0, -20.0)

	var ref_service: Node = MatchServiceScript.new()
	add_child_autofree(ref_service)
	var ref_screen: Node3D = _screen()
	ref_screen.setup(m, 2, 1, ref_service)
	var ref_camera: IsoCameraRig = ref_screen.get_node("%CameraRig")
	ref_camera.center_on(Vector2i(10, 10))
	ref_camera.pan(delta)
	var expected: Vector3 = ref_camera.global_position

	var service: Node = MatchServiceScript.new()
	add_child_autofree(service)
	var screen: Node3D = _screen()
	screen.setup(m, 2, 1, service)
	var camera: IsoCameraRig = screen.get_node("%CameraRig")
	camera.center_on(Vector2i(10, 10))
	var start_pos := Vector2(100, 100)

	screen._unhandled_input(_mb(start_pos, true))
	screen._unhandled_input(_mm(start_pos + delta, delta))
	screen._unhandled_input(_mb(start_pos + delta, false))

	assert_eq(camera.global_position, expected,
		"драг мусить пройти крізь pan() рівно з екранною дельтою, без жодного перетворення в battle_screen.gd")


## Регресія на блокері з рев'ю: раніше _advance_drag() пану вав БЕЗУМОВНО, ще
## до перетину порога — тремтіння пальця в межах «ще тапу» встигало зсунути
## камеру. Тепер порогу не досягнуто — камера не мусить зрушити НІ НА ПІКСЕЛЬ.
func test_pan_does_not_apply_before_the_drag_threshold_is_crossed() -> void:
	var service: Node = MatchServiceScript.new()
	add_child_autofree(service)
	var m: MapData = _map(20, 20)
	var screen: Node3D = _screen()
	screen.setup(m, 2, 1, service)
	var camera: IsoCameraRig = screen.get_node("%CameraRig")
	camera.center_on(Vector2i(10, 10))
	var before: Vector3 = camera.global_position

	var start_pos := Vector2(400, 400)
	screen._unhandled_input(_mb(start_pos, true))
	var jitter: Vector2 = start_pos + Vector2(3.0, -2.0)  # свідомо під порогом (~10dp)
	screen._unhandled_input(_mm(jitter, jitter - start_pos))

	assert_eq(camera.global_position, before,
		"рух під порогом — ще тап, а не пан: камера не сміє зрушити взагалі")


## Той самий репро, що знайшло рев'ю: тремтіння пальця під порогом, потім
## відпускання — мусить лишитись тапом, вибрати юніт САМЕ під точкою натиску,
## а не під точкою відпускання.
##
## Рев'ю показало, що попередня версія цього тесту не могла впасти взагалі:
## натиск лежав рівно в ЦЕНТРІ тайла, і тремтіння в кілька пікселів
## заокруглювалось у ТОЙ САМИЙ тайл незалежно від того, яку з двох точок
## бере _handle_tap_at_screen_position() — тест був зеленим і зі старою, і з
## новою поведінкою, нічого не стережучи. Тут натиск лежить впритул до межі
## тайла (0.49 замість 0.5 — ще на боці юніта) і на максимальному
## наближенні (MIN_ZOOM — найбільше пікселів на світову одиницю), а
## передумова (assert_ne нижче) доводить перед основною перевіркою, що
## press- і jitter-точки таки округлюються у РІЗНІ тайли — інакше сама
## передумова впала б голосно, а не мовчки пропустила тест.
func test_tap_resolves_from_the_press_position_not_the_release_position() -> void:
	var service: Node = MatchServiceScript.new()
	add_child_autofree(service)
	var m: MapData = _map(20, 20)
	m.spawns = [{"type_id": 5, "owner": 0, "pos": Vector2i(10, 10), "facing": 0}] as Array[Dictionary]
	var screen: Node3D = _screen()
	screen.setup(m, 2, 1, service)

	var unit: Unit = service.state.units_of(0)[0]
	var camera: IsoCameraRig = screen.get_node("%CameraRig")
	camera.center_on(unit.pos)
	var cam3d: Camera3D = camera.get_node("Yaw/Camera3D")
	camera.zoom_by(IsoCameraRig.MIN_ZOOM / camera.zoom_level)
	simulate(camera, 240, 1.0 / 60.0)
	assert_eq(camera.zoom_level, IsoCameraRig.MIN_ZOOM, "передумова: зум дійшов до MIN_ZOOM")
	camera.center_on(unit.pos)

	# Точка межі лежить на поверхні рельєфу, а не на площині y = 0 (тап б'є в землю).
	var boundary_point := Vector3(unit.pos.x + 0.49, TerrainHeight.ground_y(unit.pos.x + 0.49, unit.pos.y), unit.pos.y)
	var press_pos: Vector2 = cam3d.unproject_position(boundary_point)
	var jitter_pos: Vector2 = press_pos + Vector2(8.0, 0.0)  # свідомо під порогом (~10dp), але штовхає за межу

	assert_ne(camera.screen_point_to_cell(press_pos), camera.screen_point_to_cell(jitter_pos),
		"передумова: press і jitter мусять округлюватись у РІЗНІ клітинки, інакше тест нічого не стереже")
	assert_eq(camera.screen_point_to_cell(press_pos), unit.pos, "передумова: press усе ще на клітинці юніта")

	var selections: Array = []
	screen.input_controller().selection_changed.connect(func(u: Unit) -> void: selections.append(u))

	screen._unhandled_input(_mb(press_pos, true))
	screen._unhandled_input(_mm(jitter_pos, jitter_pos - press_pos))
	screen._unhandled_input(_mb(jitter_pos, false))

	assert_eq(selections.size(), 1, "тремтіння під порогом лишається тапом")
	assert_eq(selections[0], unit, "і мусить вибрати юніт під точкою НАТИСКУ, а не відпускання (сусідня клітинка)")


## Камера й ввід не залежать від карти, тож ці тести ставлять малу дошку:
## збірка «Річки» триває ~11 с на кожен тест.
func test_mouse_wheel_up_zooms_in_and_clamps_at_min_zoom() -> void:
	var screen: Node3D = _screen()
	screen.setup(_map(), 2, 1)
	var camera: IsoCameraRig = screen.get_node("%CameraRig")

	for i in 100:
		screen._unhandled_input(_mb(Vector2.ZERO, true, MOUSE_BUTTON_WHEEL_UP))
	simulate(camera, 120, 1.0 / 60.0)

	assert_eq(camera.zoom_level, IsoCameraRig.MIN_ZOOM,
		"колесо вгору мусить доходити до zoom_by() і клемпитись там же, де й сам ріг (test_iso_camera_rig.gd)")


func test_mouse_wheel_down_zooms_out_and_clamps_at_max_zoom() -> void:
	var screen: Node3D = _screen()
	screen.setup(_map(), 2, 1)
	var camera: IsoCameraRig = screen.get_node("%CameraRig")

	for i in 100:
		screen._unhandled_input(_mb(Vector2.ZERO, true, MOUSE_BUTTON_WHEEL_DOWN))
	simulate(camera, 120, 1.0 / 60.0)

	assert_eq(camera.zoom_level, IsoCameraRig.MAX_ZOOM,
		"колесо вниз мусить доходити до zoom_by() і клемпитись зверху")


## Лишається на випадок платформ, де рушій усе ж генерує цю подію (§ коментар
## над _on_magnify_gesture() у battle_screen.gd) — основний мобільний шлях
## перевіряють тести щипка нижче, зібраного напряму з ScreenTouch/ScreenDrag.
func test_magnify_gesture_zooms_in_and_clamps_at_min_zoom() -> void:
	var screen: Node3D = _screen()
	screen.setup(_map(), 2, 1)
	var camera: IsoCameraRig = screen.get_node("%CameraRig")

	for i in 100:
		var mg := InputEventMagnifyGesture.new()
		mg.factor = 3.0  # розведення пальців — наближення
		screen._unhandled_input(mg)
	simulate(camera, 120, 1.0 / 60.0)

	assert_eq(camera.zoom_level, IsoCameraRig.MIN_ZOOM,
		"пінч розведенням пальців (factor>1) мусить наближати й теж клемпитись знизу")


## Регресія на блокері з рев'ю: Control-дерево (MOUSE_FILTER_STOP гейта)
## зупиняє InputEventMouse*/ScreenTouch/ScreenDrag, але НЕ InputEventMagnifyGesture
## — той не належить до типів, які GUI-система вважає "вхідними для елемента".
## Без явної перевірки видимості гейта в _on_magnify_gesture() зум крізь
## видимий гейт передачі ходу проходив би без жодної перешкоди.
func test_magnify_gesture_is_ignored_while_the_handover_gate_is_visible() -> void:
	var service: Node = MatchServiceScript.new()
	add_child_autofree(service)
	var m: MapData = _map()
	m.spawns = [
		{"type_id": 5, "owner": 0, "pos": Vector2i(1, 1), "facing": 0},
		{"type_id": 5, "owner": 1, "pos": Vector2i(4, 4), "facing": 0},
	] as Array[Dictionary]
	var screen: Node3D = _screen()
	screen.setup(m, 2, 1, service)
	var gate: Control = screen.get_node("%HandoverGate")
	gate.show_for(1)
	assert_true(gate.visible, "передумова: гейт на екрані")
	var camera: IsoCameraRig = screen.get_node("%CameraRig")
	var before: float = camera.zoom_level

	var mg := InputEventMagnifyGesture.new()
	mg.factor = 3.0
	screen._unhandled_input(mg)
	simulate(camera, 30, 1.0 / 60.0)

	assert_eq(camera.zoom_level, before, "жест зуму крізь видимий гейт не сміє нічого міняти")


func test_screen_drag_pans_without_calling_tap_cell() -> void:
	var service: Node = MatchServiceScript.new()
	add_child_autofree(service)
	var m: MapData = _map(20, 20)
	m.spawns = [{"type_id": 5, "owner": 0, "pos": Vector2i(2, 2), "facing": 0}] as Array[Dictionary]
	var screen: Node3D = _screen()
	screen.setup(m, 2, 1, service)
	var camera: IsoCameraRig = screen.get_node("%CameraRig")
	camera.center_on(Vector2i(10, 10))
	var before: Vector3 = camera.global_position

	var selections: Array = []
	screen.input_controller().selection_changed.connect(func(u: Unit) -> void: selections.append(u))

	var start_pos := Vector2(200, 200)
	var st := InputEventScreenTouch.new()
	st.position = start_pos
	st.pressed = true
	screen._unhandled_input(st)

	var end_pos: Vector2 = start_pos + Vector2(0, 60)  # за порогом
	var sd := InputEventScreenDrag.new()
	sd.position = end_pos
	sd.relative = end_pos - start_pos
	screen._unhandled_input(sd)

	var st_up := InputEventScreenTouch.new()
	st_up.position = end_pos
	st_up.pressed = false
	screen._unhandled_input(st_up)

	assert_true(selections.is_empty(), "палець, що поїхав за поріг, — пан; tap_cell не мусить викликатись")
	assert_false(camera.global_position.is_equal_approx(before), "ScreenDrag мусить рухати камеру так само, як мишиний драг")


# --- Мультитач: другий палець не рве жест першого, а стартує щипок --------
#
# Блокер з рев'ю: InputEventScreenTouch/ScreenDrag.index ніде не читався.
# Репро: палець A вниз -> драг 100px -> палець B вниз -> палець A вгору давав
# спрацьований ТАП попри драг, і _pointer_down=false лишав пан мертвим до
# наступного свіжого натиску. Тести нижче ведуть стан по index явно.

func _st(pos: Vector2, pressed: bool, index: int) -> InputEventScreenTouch:
	var st := InputEventScreenTouch.new()
	st.position = pos
	st.pressed = pressed
	st.index = index
	return st


func _sd(pos: Vector2, relative: Vector2, index: int) -> InputEventScreenDrag:
	var sd := InputEventScreenDrag.new()
	sd.position = pos
	sd.relative = relative
	sd.index = index
	return sd


func test_second_finger_down_mid_drag_does_not_turn_the_first_fingers_release_into_a_tap() -> void:
	var service: Node = MatchServiceScript.new()
	add_child_autofree(service)
	var m: MapData = _map(20, 20)
	m.spawns = [{"type_id": 5, "owner": 0, "pos": Vector2i(2, 2), "facing": 0}] as Array[Dictionary]
	var screen: Node3D = _screen()
	screen.setup(m, 2, 1, service)

	var selections: Array = []
	screen.input_controller().selection_changed.connect(func(u: Unit) -> void: selections.append(u))

	var a_start := Vector2(200, 200)
	screen._unhandled_input(_st(a_start, true, 0))
	var a_mid: Vector2 = a_start + Vector2(100, 0)  # впевнено за порогом
	screen._unhandled_input(_sd(a_mid, a_mid - a_start, 0))

	# Другий палець лягає ПОВЕРХ уже активного жесту першого — сам собою
	# стартує щипок (перевірено окремо нижче), не мусить чіпати стан першого.
	screen._unhandled_input(_st(Vector2(600, 200), true, 1))

	screen._unhandled_input(_st(a_mid, false, 0))

	assert_true(selections.is_empty(),
		"палець A вже перетнув поріг драга до того, як прийшов палець B — його відпускання не сміє раптом стати тапом")


func test_pinch_between_two_touches_zooms_and_second_finger_release_resumes_single_finger_drag() -> void:
	var service: Node = MatchServiceScript.new()
	add_child_autofree(service)
	var m: MapData = _map(20, 20)
	var screen: Node3D = _screen()
	screen.setup(m, 2, 1, service)
	var camera: IsoCameraRig = screen.get_node("%CameraRig")
	camera.center_on(Vector2i(10, 10))

	var a := Vector2(500, 300)
	var b := Vector2(700, 300)
	screen._unhandled_input(_st(a, true, 0))
	screen._unhandled_input(_st(b, true, 1))
	assert_almost_eq(camera.zoom_level, 12.0, 0.001, "передумова: другий палець сам по собі ще не міняє ціль зуму, лише запамʼятовує стартову відстань")

	# Пальці розходяться — щипок наближення, зібраний напряму з двох
	# ScreenTouch/ScreenDrag за index (Android не шле InputEventMagnifyGesture
	# без окремо увімкненого налаштування — цей шлях і є основним на мобільній).
	var b_far: Vector2 = b + Vector2(100, 0)
	screen._unhandled_input(_sd(b_far, b_far - b, 1))
	simulate(camera, 120, 1.0 / 60.0)

	assert_true(camera.zoom_level < 12.0, "розведення пальців мусить наближати (зменшувати zoom_level)")

	# Один палець (B) відпускається — жест переходить назад у звичайний
	# одно-пальцевий пан ВІД ПОТОЧНОЇ позиції пальця A, не ламається.
	screen._unhandled_input(_st(b_far, false, 1))
	var before_resume: Vector3 = camera.global_position
	var a_far: Vector2 = a + Vector2(0, 80)  # за порогом
	screen._unhandled_input(_sd(a_far, a_far - a, 0))

	assert_false(camera.global_position.is_equal_approx(before_resume),
		"після завершення щипка один палець, що лишився, мусить одразу вести звичайний пан")


## Рев'ю, головна поломка 3: підняття другого пальця запускало СВІЖИЙ
## одно-пальцевий натиск (_begin_pointer_press() без жодного переміщення), і
## коли останній палець теж піднімався, не перетнувши поріг драга — а щипок
## завжди й закінчується саме так — виклик ішов у обробку тапу. Рецензент
## відтворив це на юніті під двома пальцями: розвели, підняли другий, підняли
## перший — юніт вибрався сам, хоча гравець тапав по дошці, а не по юніту
## навмисно. Гірше: на вже вибраному юніті це підставило б хід/постріл, яких
## гравець не задавав, а кнопка підтвердження потім спокійно виконала б.
func test_pinch_ending_by_lifting_both_fingers_does_not_select_a_unit() -> void:
	var service: Node = MatchServiceScript.new()
	add_child_autofree(service)
	var m: MapData = _map(20, 20)
	m.spawns = [{"type_id": 5, "owner": 0, "pos": Vector2i(2, 2), "facing": 0}] as Array[Dictionary]
	var screen: Node3D = _screen()
	screen.setup(m, 2, 1, service)

	var unit: Unit = service.state.units_of(0)[0]
	var camera: IsoCameraRig = screen.get_node("%CameraRig")
	camera.center_on(unit.pos)
	var cam3d: Camera3D = camera.get_node("Yaw/Camera3D")
	var unit_screen_pos: Vector2 = cam3d.unproject_position(IsoCameraRig.cell_to_world(unit.pos))

	var selections: Array = []
	screen.input_controller().selection_changed.connect(func(u: Unit) -> void: selections.append(u))

	# Два пальці на тайлі юніта, розводимо (щипок), піднімаємо ОБИДВА —
	# жоден не перетинає поріг драга, бо щипок завжди закінчується саме так.
	var a: Vector2 = unit_screen_pos
	var b: Vector2 = unit_screen_pos + Vector2(20.0, 0.0)
	screen._unhandled_input(_st(a, true, 0))
	screen._unhandled_input(_st(b, true, 1))
	var b_far: Vector2 = b + Vector2(40.0, 0.0)
	screen._unhandled_input(_sd(b_far, b_far - b, 1))
	screen._unhandled_input(_st(b_far, false, 1))  # другий палець угору — резюмує одно-пальцевий жест
	screen._unhandled_input(_st(a, false, 0))  # перший палець угору, без жодного руху після цього

	assert_true(selections.is_empty(),
		"завершення щипка НЕ сміє вибирати юніт, під яким воно закінчилось — щипок закінчується без жодного тапу")


## Рев'ю, дрібний блокер: третій дотик (долоня чи великий палець при
## передачі пристрою з рук у руки — реальний сценарій, §1 CLAUDE.md) не
## сміє додаватись у стан жесту взагалі. Стара версія додавала його в
## _touch_positions, і коли БУДЬ-ЯКИЙ з трьох пальців потім підіймався,
## erase() зменшував розмір словника й код читав це як кінець щипка —
## лишаючи двох СПРАВЖНІХ пальців, що фізично все ще притиснуті, без
## жодного господаря (ні пан, ні зум) аж до підняття геть усіх.
func test_third_finger_does_not_disturb_an_active_pinch_or_hang_the_camera() -> void:
	var service: Node = MatchServiceScript.new()
	add_child_autofree(service)
	var m: MapData = _map(20, 20)
	var screen: Node3D = _screen()
	screen.setup(m, 2, 1, service)
	var camera: IsoCameraRig = screen.get_node("%CameraRig")
	camera.center_on(Vector2i(10, 10))

	var a := Vector2(400, 300)
	var b := Vector2(600, 300)
	screen._unhandled_input(_st(a, true, 0))
	screen._unhandled_input(_st(b, true, 1))

	# Долоня — третій дотик, поки перші два вже щипають; торкається й
	# одразу підноситься, як випадковий контакт.
	var c := Vector2(500, 500)
	screen._unhandled_input(_st(c, true, 2))
	screen._unhandled_input(_st(c, false, 2))

	# Щипок перших двох пальців мусить і далі працювати, як ні в чому не бувало.
	var b_far: Vector2 = b + Vector2(100.0, 0.0)
	screen._unhandled_input(_sd(b_far, b_far - b, 1))
	simulate(camera, 120, 1.0 / 60.0)
	assert_true(camera.zoom_level < 12.0, "третій, ігнорований палець не сміє зіпсувати щипок перших двох")

	# І підняття СПРАВЖНЬОГО пальця (не третього-ігнорованого) мусить
	# коректно резюмувати одно-пальцевий пан, а не лишити камеру мертвою.
	screen._unhandled_input(_st(b_far, false, 1))
	var before_resume: Vector3 = camera.global_position
	var a_far: Vector2 = a + Vector2(0.0, 80.0)
	screen._unhandled_input(_sd(a_far, a_far - a, 0))
	assert_false(camera.global_position.is_equal_approx(before_resume),
		"після третього пальця й завершення щипка палець, що лишився, усе ще мусить вести пан")


# --- dp-поріг: 10 логічних px, без поправки на content_scale_factor ------
#
# Task 4.1: UiScale робить логічний px ≈ dp, тож поріг ~10dp — це рівно
# 10 логічних px за будь-якого фактора. Ділення на фактор (як було) після
# появи UiScale давало б на телефоні ~6 px — тремтіння пальця ставало б паном.

func test_drag_threshold_is_ten_logical_px_at_any_content_scale_factor() -> void:
	var screen: Node3D = _screen()
	screen.setup(_map(), 2, 1)
	var window: Window = screen.get_window()
	var original_factor: float = window.content_scale_factor

	window.content_scale_factor = 1.627
	var threshold_scaled: float = screen._drag_threshold_px()
	window.content_scale_factor = 1.0
	var threshold_at_1x: float = screen._drag_threshold_px()
	window.content_scale_factor = original_factor

	assert_eq(threshold_scaled, 10.0)
	assert_eq(threshold_at_1x, 10.0)


## Регресія на блокері з рев'ю: типове значення `true` синтезує ще й
## InputEventMouseMotion/MouseButton поверх кожного ScreenTouch/ScreenDrag —
## обидва потоки доходили б до _unhandled_input(), і пан застосовувався б
## двічі за один рух пальця. project.godot вимикає це явно.
func test_touch_to_mouse_emulation_is_disabled_project_wide() -> void:
	assert_false(ProjectSettings.get_setting("input_devices/pointing/emulate_mouse_from_touch", true),
		"кожен дотик не сміє синтезувати ще й мишачу подію — battle_screen.gd веде окремі, повні шляхи для миші й дотику")


## Явна перевірка (не лише побічний ефект іншого тесту, як просило рев'ю):
## гейт передачі ходу — єдине місце, де рецентрування лишається телепортом,
## і симуляція кадрів ПІСЛЯ confirmed не сміє зрушити камеру ще далі —
## інакше десь у цьому шляху лишився б fly_to()/Tween.
func test_gate_recenter_never_animates_even_across_later_frames() -> void:
	var service: Node = MatchServiceScript.new()
	add_child_autofree(service)
	var m: MapData = _map()
	m.spawns = [
		{"type_id": 5, "owner": 0, "pos": Vector2i(1, 1), "facing": 0},
		{"type_id": 5, "owner": 1, "pos": Vector2i(4, 4), "facing": 0},
	] as Array[Dictionary]
	var screen: Node3D = _screen()
	screen.setup(m, 2, 1, service)
	var camera: IsoCameraRig = screen.get_node("%CameraRig")

	var end_turn_button: Button = screen.get_node("%Hud").get_node("%EndTurnButton")
	end_turn_button.pressed.emit()
	var gate: Control = screen.get_node("%HandoverGate")
	var confirm_button: Button = gate.get_node("%ConfirmButton")
	confirm_button.pressed.emit()

	var target: Vector3 = IsoCameraRig.cell_to_world(service.state.units_of(1)[0].pos)
	assert_eq(camera.global_position, target, "передумова: рецентрування вже на цілі одразу після confirmed")

	simulate(camera, 60, 1.0 / 60.0)

	assert_eq(camera.global_position, target,
		"кадри ПІСЛЯ confirmed не сміють зрушити камеру ще далі — гейтове рецентрування не анімоване")


func test_handover_gate_sits_as_the_last_child_of_a_full_rect_canvas_layer() -> void:
	# game/ui/handover_gate.gd, крок 5 контракту: гейт мусить бути прямим
	# нащадком CanvasLayer, останнім серед сусідніх вузлів над дошкою — інакше він
	# або не отримує вхід першим, або показує дошку навколо/поверх себе.
	var screen: Node3D = _screen()
	var gate: Control = screen.get_node("%HandoverGate")
	assert_true(gate.get_parent() is CanvasLayer, "гейт мусить бути прямим нащадком CanvasLayer")
	var siblings: Array[Node] = gate.get_parent().get_children()
	assert_eq(siblings[siblings.size() - 1], gate, "гейт мусить бути останнім сиблінгом — над рештою UI, коли видимий")
## Гасить усі живі твіни миттєво (реального часу headless-тест не чекає).
func _finish_all_processed_tweens() -> void:
	for t in Engine.get_main_loop().get_processed_tweens():
		if t.is_valid():
			t.custom_step(10.0)


# --- Скарга власника: тап по ворогові для пострілу мусить позначити ЦІЛЬ ---
#
# Раніше прев'ю пострілу було видно лише в нижній панелі HUD (сектор і межі
# шкоди), а на самій дошці ціль не позначалась ніяк. Приціл малює вигляд із
# готового прев'ю InputController — жодного перерахунку дальності, видимості
# чи шкоди тут немає й не сміє з'явитись (§6 CLAUDE.md).

func _crosshair_visible(screen: Node3D, unit_id: int) -> bool:
	var view: Node3D = screen.unit_view_for(unit_id)
	assert_not_null(view, "передумова: вузол юніта %d мусить бути на дошці" % unit_id)
	return view._crosshair.visible


## Танки стоять поруч: обидва в ромбі огляду один одного і в межах пострілу,
## тож тап по ворогові справді дає прев'ю пострілу, а не no-op.
func _screen_with_two_adjacent_tanks(service: Node) -> Node3D:
	var m: MapData = _map()
	m.spawns = [
		{"type_id": 5, "owner": 0, "pos": Vector2i(2, 2), "facing": 0},
		{"type_id": 5, "owner": 1, "pos": Vector2i(3, 2), "facing": 0},
	] as Array[Dictionary]
	var screen: Node3D = _screen()
	screen.setup(m, 2, 1, service)
	return screen


func test_shot_preview_marks_exactly_the_target_and_nobody_else() -> void:
	var service: Node = MatchServiceScript.new()
	add_child_autofree(service)
	var screen: Node3D = _screen_with_two_adjacent_tanks(service)
	var shooter: Unit = service.state.units_of(0)[0]
	var target: Unit = service.state.units_of(1)[0]

	screen.input_controller().tap_cell(shooter.pos)
	assert_false(_crosshair_visible(screen, target.id), "передумова: сам вибір стрільця ще нічого не прицілює")

	screen.input_controller().tap_cell(target.pos)

	assert_true(_crosshair_visible(screen, target.id), "прев'ю пострілу мусить поставити приціл на ціль")
	assert_false(_crosshair_visible(screen, shooter.id), "і ні на кого більше — стрілець не ціль")


func test_cancel_pending_clears_the_crosshair() -> void:
	var service: Node = MatchServiceScript.new()
	add_child_autofree(service)
	var screen: Node3D = _screen_with_two_adjacent_tanks(service)
	var shooter: Unit = service.state.units_of(0)[0]
	var target: Unit = service.state.units_of(1)[0]

	screen.input_controller().tap_cell(shooter.pos)
	screen.input_controller().tap_cell(target.pos)
	assert_true(_crosshair_visible(screen, target.id), "передумова: приціл стоїть")

	screen.input_controller().cancel_pending()

	assert_false(_crosshair_visible(screen, target.id), "скасування прев'ю мусить зняти приціл")


func test_selecting_another_unit_clears_the_crosshair() -> void:
	var service: Node = MatchServiceScript.new()
	add_child_autofree(service)
	var screen: Node3D = _screen_with_two_adjacent_tanks(service)
	var shooter: Unit = service.state.units_of(0)[0]
	var target: Unit = service.state.units_of(1)[0]

	screen.input_controller().tap_cell(shooter.pos)
	screen.input_controller().tap_cell(target.pos)
	assert_true(_crosshair_visible(screen, target.id), "передумова: приціл стоїть")

	screen.input_controller().select_unit(null)

	assert_false(_crosshair_visible(screen, target.id), "новий вибір мусить зняти приціл попереднього прев'ю")


## Прев'ю РУХУ — теж action_preview, але воно нікого не прицілює: приціл
## належить рівно ActionType.SHOT.
func test_move_preview_does_not_mark_anyone() -> void:
	var service: Node = MatchServiceScript.new()
	add_child_autofree(service)
	var screen: Node3D = _screen_with_two_adjacent_tanks(service)
	var shooter: Unit = service.state.units_of(0)[0]
	var target: Unit = service.state.units_of(1)[0]

	screen.input_controller().tap_cell(shooter.pos)
	screen.input_controller().tap_cell(Vector2i(2, 3))  # порожній тайл в зоні руху

	assert_false(_crosshair_visible(screen, target.id), "прев'ю руху не сміє прицілювати ворога")
	assert_false(_crosshair_visible(screen, shooter.id), "ані самого юніта, що рухається")


# --- Панель характеристик їде за юнітом (скарга власника) -------------------

## Проводка, а не сама поведінка: те, що панель уміє ставати на місце, стереже
## tests/game/test_hud.gd, а те, що ріг повідомляє про рух, —
## tests/game/test_iso_camera_rig.gd. Тут перевіряється рівно один рядок
## setup(): що сцена бою справді звела ці двоє докупи. Без нього обидві
## половини лишаються зеленими, а на екрані панель стоїть як стояла.
##
## Перевіряється САМЕ З'ЄДНАННЯ, а не зсув панелі в пікселях — і це свідомий
## відкат від першої, нестабільної версії цього тесту. Та рухала камеру й
## порівнювала позицію до/після, але під headless юніт проєктується за межі
## екрана, панель у обох замірах упирається в той самий кут клемпа, і результат
## залежав від того, чи встиг крокнути твін fly_to() із setup(). Тест то
## зеленів, то ні, тобто не стеріг нічого. Поведінку (панель справді їде за
## юнітом і не накриває ні його, ні кнопки) тримає tests/game/test_hud.gd на
## ригу, яким сам і керує; тут лишається рівно те, чого немає більше ніде —
## факт, що сцена бою звела ріг із HUD.
func test_inspector_follows_the_camera_because_setup_wires_it() -> void:
	var service: Node = MatchServiceScript.new()
	add_child_autofree(service)
	var m: MapData = _map(12, 12)
	m.spawns = [
		{"type_id": 5, "owner": 0, "pos": Vector2i(2, 2), "facing": 0},
	] as Array[Dictionary]
	var screen: Node3D = _screen()
	screen.setup(m, 2, 1, service)

	var rig: IsoCameraRig = screen.get_node("%CameraRig")
	var hud: Node = screen.get_node("%Hud")
	var wired_to_hud: bool = false
	for connection in rig.view_changed.get_connections():
		if (connection["callable"] as Callable).get_object() == hud:
			wired_to_hud = true
			break

	assert_true(wired_to_hud,
		"setup() мусить підписати HUD на рух камери — без цього рядка обидві половини лишаються зеленими, а на екрані панель стоїть як стояла")


# --- Уламки: лише над розвіданим тим, хто зараз перед екраном (§3.5, §3.14) ---

func _first_tile(state: BattleState, seen_by: int, unseen_by: int) -> Vector2i:
	for y in state.board.height:
		for x in state.board.width:
			var p := Vector2i(x, y)
			if state.vision[seen_by].is_seen(p) and not state.vision[unseen_by].is_seen(p) and state.unit_at(p) == null:
				return p
	return Vector2i(-1, -1)


func _two_tanks_in_corners(service: Node) -> Node3D:
	var m: MapData = _map()
	m.spawns = [
		{"type_id": 5, "owner": 0, "pos": Vector2i(0, 0), "facing": 0},
		{"type_id": 5, "owner": 1, "pos": Vector2i(5, 5), "facing": 0},
	] as Array[Dictionary]
	var screen: Node3D = _screen()
	screen.setup(m, 2, 1, service)
	return screen


func test_a_kill_leaves_a_wreck_under_the_fireball() -> void:
	var service: Node = MatchServiceScript.new()
	add_child_autofree(service)
	var m: MapData = _map()
	m.spawns = [
		{"type_id": 5, "owner": 0, "pos": Vector2i(2, 2), "facing": 0},
		{"type_id": 2, "owner": 1, "pos": Vector2i(3, 2), "facing": 0},
		{"type_id": 5, "owner": 1, "pos": Vector2i(5, 5), "facing": 0},
	] as Array[Dictionary]
	var screen: Node3D = _screen()
	screen.setup(m, 2, 1, service)
	var layer: WreckLayer = screen.get_node("%WreckLayer")
	var victim: Unit = service.state.unit_at(Vector2i(3, 2))
	victim.hp = 1
	victim.facing = 6
	screen.input_controller().tap_cell(Vector2i(2, 2))
	screen.input_controller().tap_cell(victim.pos)
	screen.input_controller().confirm_pending()
	# Кожна анімація починається лише після попередньої: постріл, потім знищення.
	for _i in 4:
		_finish_all_processed_tweens()
	assert_false(victim.is_alive(), "передумова: бронеавто знищене")
	assert_false(screen._event_player.is_playing(), "передумова: пакет подій доіграно")
	assert_not_null(layer.wreck_at(Vector2i(3, 2)), "уламки — на тайлі знищеної техніки")
	assert_eq(layer.wreck_count(), 1)
	assert_eq(layer.fire_count(), 1, "щойно знищена техніка горить")
	assert_null(screen.unit_view_for(victim.id))
	var f: Vector3 = -layer.wreck_at(Vector2i(3, 2)).basis.z
	assert_eq(Vector2i(roundi(f.x), roundi(f.z)), Board.DIRS_8[6], "уламки лежать так, як стояв юніт")
	var scars: ScarMap = screen._scars
	assert_eq(scars.image().get_pixel(3 * 32 + 16, 2 * 32 + 16).r8, 255, "під уламками — випалена пляма")
	assert_eq(scars.mask().get_pixel(3, 2).r8, 255)


func test_handover_redraws_wrecks_from_the_incoming_players_seen() -> void:
	var service: Node = MatchServiceScript.new()
	add_child_autofree(service)
	var screen: Node3D = _two_tanks_in_corners(service)
	var state: BattleState = service.state
	var p0_only: Vector2i = _first_tile(state, 0, 1)
	var p1_only: Vector2i = _first_tile(state, 1, 0)
	assert_ne(p0_only, Vector2i(-1, -1), "передумова: є тайл, розвіданий лише гравцем 0")
	assert_ne(p1_only, Vector2i(-1, -1), "передумова: є тайл, розвіданий лише гравцем 1")
	state.wrecks.append(Wrecks.Wreck.new(p0_only, 5, 0, state.turn_clock() + 100))
	state.wrecks.append(Wrecks.Wreck.new(p1_only, 5, 0, state.turn_clock() + 100))
	var layer: WreckLayer = screen.get_node("%WreckLayer")
	screen._rebuild_wrecks()
	assert_not_null(layer.wreck_at(p0_only), "передумова: гравець 0 бачить свої уламки")

	screen.get_node("%Hud").get_node("%EndTurnButton").pressed.emit()
	_finish_all_processed_tweens()
	var gate: Control = screen.get_node("%HandoverGate")
	assert_true(gate.visible)
	assert_null(layer.wreck_at(p1_only), "за гейтом ще світ гравця 0 — розвідане гравця 1 не малюється")
	assert_not_null(layer.wreck_at(p0_only))

	gate.get_node("%ConfirmButton").pressed.emit()
	assert_eq(layer.wreck_count(), 1)
	assert_not_null(layer.wreck_at(p1_only))
	assert_null(layer.wreck_at(p0_only), "уламки над нерозвіданим гравцем 1 — донос про чужий бій")
	var scars: ScarMap = screen._scars
	assert_eq(scars.mask().get_pixel(p0_only.x, p0_only.y).r8, 0, "і пляма під ними схована маскою")
	assert_eq(scars.mask().get_pixel(p1_only.x, p1_only.y).r8, 255)
	assert_eq(scars.image().get_pixel(p1_only.x * 32 + 16, p1_only.y * 32 + 16).r8, 255)


func test_burnt_out_wreck_disappears_when_its_turn_comes() -> void:
	var service: Node = MatchServiceScript.new()
	add_child_autofree(service)
	var screen: Node3D = _two_tanks_in_corners(service)
	var state: BattleState = service.state
	var p := Vector2i(1, 0)
	assert_true(state.vision[0].is_seen(p), "передумова: тайл розвіданий гравцем 0")
	# Догоряє на наступному ході (годинник +1).
	state.wrecks.append(Wrecks.Wreck.new(p, 5, 0, state.turn_clock() + 1))
	var layer: WreckLayer = screen.get_node("%WreckLayer")
	layer.rebuild(state, 0)
	assert_not_null(layer.wreck_at(p))

	screen.get_node("%Hud").get_node("%EndTurnButton").pressed.emit()
	_finish_all_processed_tweens()
	assert_null(layer.wreck_at(p), "WreckRemoved прибирає уламки, щойно їх показано")
	assert_eq(layer.column_count(), 0)


## Бій зі збереження: уламки вже в стані, і «Продовжити» малює їх із нього.
func test_resume_draws_wrecks_already_in_state_only_on_seen_ground() -> void:
	var service: Node = MatchServiceScript.new()
	add_child_autofree(service)
	_two_tanks_in_corners(service)
	var state: BattleState = service.state
	state.wrecks.append(Wrecks.Wreck.new(_first_tile(state, 0, 1), 5, 0, state.turn_clock() + 100))
	state.wrecks.append(Wrecks.Wreck.new(_first_tile(state, 1, 0), 5, 0, state.turn_clock() + 100))
	var screen: Node3D = _screen()
	screen.resume(service)
	var gate: Control = screen.get_node("%HandoverGate")
	gate.get_node("%ConfirmButton").pressed.emit()
	var layer: WreckLayer = screen.get_node("%WreckLayer")
	assert_eq(layer.wreck_count(), 1)
	assert_not_null(layer.wreck_at(_first_tile(state, 0, 1)))


# --- §8: спокійний екран не крутить кадри даремно -------------------------

## Спливла секунда спокою — таймер, а не реальний час: тест не чекає.
func _idle_for_a_second(screen: Node3D) -> void:
	var timer: Timer = screen._idle_timer
	assert_almost_eq(timer.wait_time, BattleScreen.IDLE_AFTER_S, 0.0001)
	timer.timeout.emit()


func test_battle_caps_the_frame_rate_when_idle() -> void:
	var screen: Node3D = _screen()
	screen._input(InputEventScreenTouch.new())
	assert_eq(Engine.max_fps, 0)
	assert_false(screen._idle_timer.is_stopped(), "натиск заводить відлік спокою")
	_idle_for_a_second(screen)
	assert_eq(Engine.max_fps, BattleScreen.IDLE_FPS)


func test_input_uncaps_the_frame_rate() -> void:
	var screen: Node3D = _screen()
	_idle_for_a_second(screen)
	assert_eq(Engine.max_fps, BattleScreen.IDLE_FPS, "передумова: екран у спокої")
	screen._input(InputEventScreenTouch.new())
	assert_eq(Engine.max_fps, 0)


## Натиск знімає лише обмеження спокою: обмеження, що було до бою, лишається.
func test_input_returns_the_cap_from_before_the_battle() -> void:
	Engine.max_fps = 45
	# Не autofree: той звільняє екран уже після after_each, і _exit_tree повернув би 45 наступним тестам.
	var screen: Node3D = BattleScreenScene.instantiate()
	add_child(screen)
	_idle_for_a_second(screen)
	assert_eq(Engine.max_fps, BattleScreen.IDLE_FPS, "передумова: екран у спокої")
	screen._input(InputEventScreenTouch.new())
	assert_eq(Engine.max_fps, 45)
	remove_child(screen)
	screen.free()


func test_camera_motion_keeps_the_frame_rate_uncapped() -> void:
	var screen: Node3D = _screen()
	var rig: IsoCameraRig = screen.get_node("%CameraRig")
	screen._input(InputEventScreenTouch.new())
	rig.set_process(true)
	_idle_for_a_second(screen)
	assert_eq(Engine.max_fps, 0, "камера ще їде — кадр без обмеження")
	assert_false(screen._idle_timer.is_stopped(), "відлік спокою почався знову")
	rig.set_process(false)
	_idle_for_a_second(screen)
	assert_eq(Engine.max_fps, BattleScreen.IDLE_FPS)


func test_leaving_battle_restores_the_previous_cap() -> void:
	Engine.max_fps = 45
	var screen: Node3D = BattleScreenScene.instantiate()
	add_child(screen)
	_idle_for_a_second(screen)
	assert_eq(Engine.max_fps, BattleScreen.IDLE_FPS, "передумова: бій обмежив кадри")
	remove_child(screen)
	screen.free()
	assert_eq(Engine.max_fps, 45)


## Дим і дощ — один вітер: нахил стовпа на екрані бою має той самий горизонтальний
## напрям, що й знос крапель.
func test_smoke_leans_the_same_way_as_the_rain() -> void:
	var service: Node = MatchServiceScript.new()
	add_child_autofree(service)
	var screen: Node3D = _two_tanks_in_corners(service)
	var rain: Vector3 = (screen.get_node("WeatherRig") as WeatherRig).rain_velocity()
	var lean: Vector3 = (screen.get_node("%WreckLayer") as WreckLayer).column_lean()
	assert_ne(lean, Vector3.ZERO, "передумова: у типовому вигляді вітер є")
	assert_eq(lean.normalized(), Vector3(rain.x, 0.0, rain.z).normalized())


## Перше вбивство матчу не сміє зависнути на компіляції шейдерів: екран бою на старті один
## раз малює кожен матеріал ефектів, невидимо малим, і прибирає його.
func test_setup_warms_up_every_fx_material_once() -> void:
	var service: Node = MatchServiceScript.new()
	add_child_autofree(service)
	var screen: Node3D = _two_tanks_in_corners(service)
	var units: Node3D = screen.get_node("%Units")
	var layer: WreckLayer = screen.get_node("%WreckLayer")
	var warm: Array[Node] = units.find_children("Explosion*", "", false, false)
	assert_eq(warm.size(), 1, "куля розігріву")
	# Розігрів мусить бути невидимим: жодного спалаху чи світла біля юніта гравця.
	assert_eq((warm[0].get_node("Light") as OmniLight3D).light_energy, 0.0)
	assert_eq((warm[0] as Node3D).scale, Vector3.ONE * 0.0001)
	var ball := (warm[0].get_node("Ball") as MeshInstance3D).material_override as ShaderMaterial
	assert_lt(float(ball.get_shader_parameter("size")), 0.001)
	assert_true(layer.is_warming(), "стовп, вогонь і обгорілий матеріал теж малюються раз")
	_finish_all_processed_tweens()
	assert_false(layer.is_warming())
	assert_eq(layer.column_count(), 0)



## Бій зі збереження теж не застигає на першому вбивстві: розігрів — на першому гейті.
func test_resume_warms_up_fx_on_the_first_gate_confirm() -> void:
	var service: Node = MatchServiceScript.new()
	add_child_autofree(service)
	_two_tanks_in_corners(service)
	var screen: Node3D = _screen()
	screen.resume(service)
	var units: Node3D = screen.get_node("%Units")
	assert_eq(units.find_children("Explosion*", "", false, false).size(), 0, "за гейтом камера ще ніде")
	screen.get_node("%HandoverGate").get_node("%ConfirmButton").pressed.emit()
	assert_eq(units.find_children("Explosion*", "", false, false).size(), 1)
	assert_true((screen.get_node("%WreckLayer") as WreckLayer).is_warming())
	_finish_all_processed_tweens()
	screen._on_gate_confirmed()
	assert_false((screen.get_node("%WreckLayer") as WreckLayer).is_warming(), "розігрів — лише раз")



# --- Об'їзд дошки за гейтом (_warm_board) ---------------------------------

## Кадрів з запасом: 12 точок об'їзду, по три кадри розчинення лісу й рослин, кадр на юнітів, три
## кадри під гейтом, прибирання.
const WARM_FRAMES: int = 45


func _launched_with_warm_up() -> Array:
	var service: Node = MatchServiceScript.new()
	add_child_autofree(service)
	service.configure("res://maps/river.tres", 2, 1)
	var screen: Node3D = _screen()
	screen.warm_board_in_headless = true
	screen.launch(service)
	return [screen, service]


func _resumed_with_warm_up() -> Array:
	var service: Node = MatchServiceScript.new()
	add_child_autofree(service)
	_two_tanks_in_corners(service)
	var screen: Node3D = _screen()
	screen.warm_board_in_headless = true
	screen.resume(service)
	return [screen, service]


## У %Units лежать ще й миті ефектів, тож рахуємо лише вигляди юнітів.
func _unit_view_nodes(screen: Node3D) -> int:
	return screen.get_node("%Units").get_children().filter(func(n: Node) -> bool: return n is UnitView).size()


func _camera_at_first_unit(screen: Node3D, service: Node) -> bool:
	var rig: IsoCameraRig = screen.get_node("%CameraRig")
	var cell: Vector2i = screen._first_unit_cell(service.state.active_player)
	return rig.global_position.is_equal_approx(rig._clamp_to_bounds(IsoCameraRig.cell_to_world(cell)))


func _assert_confirmed_mid_warm_up(pair: Array) -> void:
	var screen: Node3D = pair[0]
	var service: Node = pair[1]
	var gate: Control = screen.get_node("%HandoverGate")
	await wait_frames(3)
	assert_true(gate.visible, "об'їзд іде під гейтом")
	assert_eq(_unit_view_nodes(screen), 0, "юнітів під гейтом ще нема")
	gate.get_node("%ConfirmButton").pressed.emit()
	await wait_frames(WARM_FRAMES)
	assert_false(gate.visible)
	assert_true(_camera_at_first_unit(screen, service), "камера на першому юніті гравця")
	var units: Node3D = screen.get_node("%Units")
	var views: Dictionary = screen._unit_views
	assert_gt(views.size(), 0)
	for uid: int in views:
		assert_true(is_instance_valid(views[uid]), "вигляд юніта цілий")
		assert_eq((views[uid] as Node).get_parent(), units)


func _assert_finished_warm_up_leaves_no_units(pair: Array) -> void:
	var screen: Node3D = pair[0]
	await wait_frames(WARM_FRAMES)
	assert_true((screen.get_node("%HandoverGate") as Control).visible, "гейт стоїть")
	assert_eq(screen._unit_views.size(), 0, "після об'їзду під гейтом юнітів нема")
	assert_eq(_unit_view_nodes(screen), 0)


func test_launch_confirm_in_the_middle_of_the_warm_up_leaves_camera_and_units_right() -> void:
	await _assert_confirmed_mid_warm_up(_launched_with_warm_up())


func test_resume_confirm_in_the_middle_of_the_warm_up_leaves_camera_and_units_right() -> void:
	await _assert_confirmed_mid_warm_up(_resumed_with_warm_up())


func test_warm_up_shows_forest_fade_under_the_gate() -> void:
	# Матеріали розчинення лісу (прохід глибини й колір) компілюються за гейтом, а не на першому
	# юніті під кроною: під час об'їзду розчинена крона показується, поки гейт закриває екран.
	var pair: Array = _launched_with_warm_up()
	var screen: Node3D = pair[0]
	var gate: Control = screen.get_node("%HandoverGate")
	var forest: ForestLayer = (screen.get_node("%BoardView") as BoardView).forest()
	var seen: Dictionary = {"fade": false}
	forest.child_entered_tree.connect(func(n: Node) -> void:
		if String(n.name).begins_with("Fade_") and gate.visible:
			seen["fade"] = true)
	await wait_frames(WARM_FRAMES)
	assert_true(seen["fade"], "розчинення лісу показано за гейтом")


func test_warm_up_shows_vegetation_fade_under_the_gate() -> void:
	# Те саме для рослин (кущ, дерево, очерет): розчинений екземпляр показується, поки стоїть гейт.
	var pair: Array = _launched_with_warm_up()
	var screen: Node3D = pair[0]
	var gate: Control = screen.get_node("%HandoverGate")
	var veg: VegetationLayer = (screen.get_node("%BoardView") as BoardView).vegetation()
	var seen: Dictionary = {"fade": false}
	veg.child_entered_tree.connect(func(n: Node) -> void:
		if String(n.name).ends_with("_faded") and gate.visible:
			seen["fade"] = true)
	await wait_frames(WARM_FRAMES)
	assert_true(seen["fade"], "розчинення рослин показано за гейтом")


func test_launch_warm_up_that_runs_to_the_end_leaves_no_units_under_the_gate() -> void:
	await _assert_finished_warm_up_leaves_no_units(_launched_with_warm_up())


func test_resume_warm_up_that_runs_to_the_end_leaves_no_units_under_the_gate() -> void:
	await _assert_finished_warm_up_leaves_no_units(_resumed_with_warm_up())


func test_confirm_after_a_finished_warm_up_builds_the_units_once() -> void:
	var pair: Array = _launched_with_warm_up()
	var screen: Node3D = pair[0]
	await wait_frames(WARM_FRAMES)
	screen.get_node("%HandoverGate").get_node("%ConfirmButton").pressed.emit()
	assert_true(_camera_at_first_unit(screen, pair[1]))
	assert_eq(_unit_view_nodes(screen), screen._unit_views.size())
	assert_gt(screen._unit_views.size(), 0)


## Вирв нема: снаряд гаубиці по піхоті грає розрив, але карта шрамів лишається порожньою —
## єдиний слід на ґрунті лишає підбита техніка.
func test_a_shell_on_infantry_leaves_no_ground_mark() -> void:
	var service: Node = MatchServiceScript.new()
	add_child_autofree(service)
	var m: MapData = _map()
	m.spawns = [
		{"type_id": 10, "owner": 0, "pos": Vector2i(1, 1), "facing": 0},
		{"type_id": 0, "owner": 1, "pos": Vector2i(2, 2), "facing": 0},
	] as Array[Dictionary]
	var screen: Node3D = _screen()
	screen.setup(m, 2, 1, service)
	var gun: Unit = service.state.units_of(0)[0]
	var squad: Unit = service.state.units_of(1)[0]
	screen._event_player.play([Events.ShotFired.new(gun.id, squad.id, UnitTypes.ArmourSector.FRONT)] as Array[Events.BattleEvent])
	_finish_all_processed_tweens()
	var data: PackedByteArray = (screen._scars as ScarMap).image().get_data()
	assert_eq(data.count(0), data.size(), "жодного шраму від розриву")


## §3.5: після підтвердження гейта дах над юнітом гравця, що заходить, уже розчинений (рівень 1.0,
## вузол «_fade» видно) — без жодного тіку переходу; після наступної передачі, де юніта під дахом
## нема, — уже суцільний.
func test_handover_draws_roof_fade_of_the_incoming_player_at_once() -> void:
	var service: Node = MatchServiceScript.new()
	add_child_autofree(service)
	var m: MapData = _map(8, 8)
	for c: Vector2i in [Vector2i(2, 2), Vector2i(3, 2), Vector2i(2, 3), Vector2i(3, 3)]:
		m.tiles[c.y * m.width + c.x] = Terrain.Kind.BUILDING
	m.spawns = [
		{"type_id": 5, "owner": 0, "pos": Vector2i(7, 7), "facing": 0},
		{"type_id": 5, "owner": 1, "pos": Vector2i(2, 2), "facing": 0},
	] as Array[Dictionary]
	var screen: Node3D = _screen()
	screen.setup(m, 2, 1, service)
	var props: PropLayer = (screen.get_node("%BoardView") as BoardView).props()
	var gate: Control = screen.get_node("%HandoverGate")
	(screen.get_node("%Hud").get_node("%EndTurnButton") as Button).pressed.emit()
	(gate.get_node("%ConfirmButton") as Button).pressed.emit()
	var faded: Array = props._fade_target.keys().filter(func(i: int) -> bool: return props._fade_target[i] == 1.0)
	assert_false(faded.is_empty(), "передумова: дах над юнітом гравця 1")
	for i: int in faded:
		assert_eq(float(props._fade_level[i]), 1.0, "дах розчинений одразу після гейта")
		assert_true((props._fade_nodes[props._instances[i]["model"]] as MultiMeshInstance3D).visible)
	assert_false(props.is_processing())
	(screen.get_node("%Hud").get_node("%EndTurnButton") as Button).pressed.emit()
	(gate.get_node("%ConfirmButton") as Button).pressed.emit()
	for i: int in faded:
		assert_eq(float(props._fade_level.get(i, 0.0)), 0.0, "у гравця 0 дах суцільний одразу")
	assert_false(props.is_processing())


func test_handover_forest_shows_only_what_incoming_player_knows() -> void:
	# §3.5: ліс гравця, що заходить, — його проломи (known_broken_map), а розчинення крон — лише
	# над юнітами, яких він знає (known_occupied_map). Проломи й юніти попереднього гравця, яких
	# новий не бачив, через ліс не видно.
	var service: Node = MatchServiceScript.new()
	add_child_autofree(service)
	var m: MapData = _map(10, 10)
	for y in range(1, 9):
		for x in range(1, 9):
			m.tiles[y * 10 + x] = Terrain.Kind.FOREST
	m.spawns = [
		{"type_id": 5, "owner": 0, "pos": Vector2i(1, 1), "facing": 0},
		{"type_id": 5, "owner": 1, "pos": Vector2i(8, 8), "facing": 0},
	] as Array[Dictionary]
	var screen: Node3D = _screen()
	screen.setup(m, 2, 1, service)
	var state: BattleState = service.state
	state.broken_forest = {Vector2i(1, 1): true, Vector2i(2, 1): true, Vector2i(8, 8): true}
	(screen.get_node("%Hud").get_node("%EndTurnButton") as Button).pressed.emit()
	(screen.get_node("%HandoverGate").get_node("%ConfirmButton") as Button).pressed.emit()
	assert_eq(state.active_player, 1, "передумова: хід гравця 1")
	var forest: ForestLayer = (screen.get_node("%BoardView") as BoardView).forest()
	var known: Dictionary = state.known_broken_map(1)
	assert_false(known.has(Vector2i(2, 1)), "передумова: пролам гравця 0 гравцеві 1 невідомий")
	assert_eq(forest._broken.keys().size(), known.size(), "проломи лісу — рівно ті, що знає гравець 1")
	for c: Vector2i in known:
		assert_true(forest._broken.has(c), "пролам %s, який знає гравець 1, у лісі є" % c)
	var shown: Dictionary = state.known_occupied_map(1)
	assert_eq(forest._reveal.size(), shown.size(), "розчинення — лише над юнітами, яких знає гравець 1")
	for c: Vector2i in forest._reveal:
		assert_true(shown.has(c), "розчинення над %s, якого гравець 1 не знає" % c)


## WreckLeft несе власника: нове згарище малюється набором власника (4 — набір 1), а не набору 0.
func test_wreck_left_draws_the_wreck_in_its_owners_set() -> void:
	var service: Node = MatchServiceScript.new()
	add_child_autofree(service)
	var screen: Node3D = _two_tanks_in_corners(service)
	var row: Dictionary = {"hull": Vector3(0.5, 0.2, 0.9), "barrel": 0.7, "wheel": 0.05, "extras": [&"turret"]}
	UnitSilhouettes.use_models({Vector2i(1, 5): UnitModelFixture.mesh(row.hull)})
	UnitSilhouettes.use_set_specs({1: {5: row}})
	var pos: Vector2i = _first_tile(service.state, 0, 1)
	screen._on_wreck_left(pos, 5, 0, 4)
	var layer: WreckLayer = screen.get_node("%WreckLayer")
	assert_eq(layer.flame_size(pos), Vector2(WreckLayer.flame_width(5, 1), WreckLayer.flame_height(5, 1)))
	assert_ne(WreckLayer.flame_width(5, 1), WreckLayer.flame_width(5, 0), "передумова: набори різняться")
