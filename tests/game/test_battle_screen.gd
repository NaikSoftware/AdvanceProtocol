extends GutTest
## Task 2.10: збірка зрізу. Headless-перевірка обіцянок, які належать саме
## цьому файлу, а не жодному з Task 2.1–2.9 (ті вже покриті власними тестами):
## порядок старту (R1), початковий туман зі стану, а не з подій (R9),
## фог-правило §3.5 (жодного вузла без known_occupied_map), і порядок гейта
## передачі ходу (R7) — рекон і перебудова ДО того, як гейт закриється.

const BattleScreenScene := preload("res://game/battle/battle_screen.tscn")
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
	# перевіряється напряму, підмінюючи сітку видимості так, щоб клітинка
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
	# обʼєктом за посиланням, і саме тому спостереження записується сюди.
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


# --- Тап по дошці: екранна точка -> клітинка -> InputController -----------
#
# game/ui/handover_gate.gd, крок 4 контракту: маршрутизація тапів дошки
# зобов'язана йти крізь _unhandled_input(), інакше STOP-фільтр гейта нічого
# не блокує. Тут перевіряється рівно та половина, що належить цьому файлу —
# резолв екранної точки в клітинку і передача в InputController.tap_cell();
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
	# _ready() гейтить резерв на `current_scene == self`, а сцена, додана
	# дочірнім вузлом у тесті, головною ніколи не буває — тож перевіряємо тут
	# сам резервний вхід, а не гейт. Гейт перевіряє тест нижче.
	screen._start_fallback_match_if_not_injected()

	var board_view: Node3D = screen.get_node("%BoardView")
	assert_true(board_view.get_child_count() > 0, "резервний вхід мусить побудувати дошку")

	var units: Node3D = screen.get_node("%Units")
	assert_true(units.get_child_count() > 0, "резервний вхід мусить розставити юнітів на дошці")

	assert_not_null(screen.input_controller(), "резервний вхід мусить підняти InputController")


## Гейт — половина, що захищає решту сьогоднішнього набору: без нього кожен
## тест цього файла отримував би другий, фоновий матч на автозавантаженому
## MatchService поверх власного ізольованого інстансу.
func test_ready_does_not_start_a_match_when_the_scene_is_not_the_current_one() -> void:
	var screen: Node3D = _screen()

	assert_null(screen.input_controller(),
		"сцена, додана дочірнім вузлом, не мусить піднімати резервний матч у _ready()")
	assert_eq(screen.get_node("%Units").get_child_count(), 0,
		"а отже й жодного юніта на дошці")


func test_handover_gate_sits_as_the_last_child_of_a_full_rect_canvas_layer() -> void:
	# game/ui/handover_gate.gd, крок 5 контракту: гейт мусить бути прямим
	# нащадком CanvasLayer, останнім серед сиблінгів над дошкою — інакше він
	# або не отримує вхід першим, або показує дошку навколо/поверх себе.
	var screen: Node3D = _screen()
	var gate: Control = screen.get_node("%HandoverGate")
	assert_true(gate.get_parent() is CanvasLayer, "гейт мусить бути прямим нащадком CanvasLayer")
	var siblings: Array[Node] = gate.get_parent().get_children()
	assert_eq(siblings[siblings.size() - 1], gate, "гейт мусить бути останнім сиблінгом — над рештою UI, коли видимий")
