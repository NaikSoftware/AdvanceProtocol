extends GutTest
## Task 3.3 + 3.5: конфіг матчу доходить до бою; пауза, збереження,
## «Продовжити», кінець матчу й екран результату. Усе на ізольованих інстансах
## MatchService і тестових шляхах user:// — справжній save.json не чіпаємо.

const BattleScreenScene := preload("res://game/battle/battle_screen.tscn")
const MainMenuScene := preload("res://game/ui/main_menu.tscn")
const ResultsScene := preload("res://game/ui/results_screen.tscn")
const MatchServiceScript := preload("res://game/autoload/match_service.gd")
const TEST_SAVE: String = "user://test_save.json"
const MAP_PATH: String = "res://maps/skirmish_bridge.tres"


func after_each() -> void:
	for p in [TEST_SAVE, TEST_SAVE + ".map"]:
		DirAccess.remove_absolute(p)


func _service() -> Node:
	var s: Node = MatchServiceScript.new()
	add_child_autofree(s)
	return s


func _map() -> MapData:
	var m := MapData.new()
	m.width = 6
	m.height = 6
	var tiles := PackedInt32Array()
	tiles.resize(36)
	tiles.fill(Terrain.Kind.FIELD)
	m.tiles = tiles
	m.spawns = [
		{"type_id": 5, "owner": 0, "pos": Vector2i(2, 2), "facing": 0},
		{"type_id": 2, "owner": 1, "pos": Vector2i(3, 2), "facing": 0},
	] as Array[Dictionary]
	return m


func _screen() -> BattleScreen:
	var screen: BattleScreen = BattleScreenScene.instantiate()
	add_child_autofree(screen)
	screen.save_path = TEST_SAVE
	return screen


func _finish_all_processed_tweens() -> void:
	for t in Engine.get_main_loop().get_processed_tweens():
		if t.is_valid():
			t.custom_step(10.0)


# --- 3.3: конфіг -> бій -------------------------------------------------

func test_configured_seed_players_and_ground_land_in_state() -> void:
	var service: Node = _service()
	service.configure(MAP_PATH, 3, Terrain.GroundState.MUD, 777)
	var screen: BattleScreen = _screen()

	screen.launch(service)

	assert_eq(service.state.seed_value, 777)
	assert_eq(service.state.player_count, 3)
	assert_eq(service.state.board.ground_state, Terrain.GroundState.MUD)


func test_configure_without_seed_draws_a_random_one() -> void:
	var service: Node = _service()
	service.configure(MAP_PATH, 2, Terrain.GroundState.DRY)
	var first: int = service.seed_value
	service.configure(MAP_PATH, 2, Terrain.GroundState.DRY)
	assert_ne(service.seed_value, first, "новий матч — новий випадковий сід")


func test_rematch_keeps_map_players_ground_and_changes_seed() -> void:
	var service: Node = _service()
	service.configure(MAP_PATH, 3, Terrain.GroundState.FROZEN, 5)
	_screen().launch(service)

	service.rematch()

	assert_eq(service.map_path, MAP_PATH)
	assert_eq(service.players, 3)
	assert_eq(service.ground_state, Terrain.GroundState.FROZEN)
	assert_ne(service.seed_value, 5)
	assert_eq(service.launch_mode, MatchServiceScript.Launch.NEW)


# --- 3.5: збереження / продовжити ---------------------------------------

func test_save_then_continue_restores_identical_state() -> void:
	var a: Node = _service()
	var screen: BattleScreen = _screen()
	screen.setup(_map(), 2, 9, a)
	a.state.get_unit(1).hp = 77  # відмінність від свіжого матчу, яку збереження мусить пронести
	a.state.get_unit(1).ap = 10
	assert_eq(a.save_current(TEST_SAVE), OK)

	var b: Node = _service()
	var menu: MainMenu = MainMenuScene.instantiate()
	add_child_autofree(menu)
	assert_true(menu.continue_saved(b, TEST_SAVE))

	assert_eq(BattleSerializer.to_dict(b.state), BattleSerializer.to_dict(a.state))
	assert_eq(b.launch_mode, MatchServiceScript.Launch.RESUME)


func test_resume_builds_view_from_loaded_state_behind_the_gate() -> void:
	var a: Node = _service()
	_screen().setup(_map(), 2, 9, a)
	a.save_current(TEST_SAVE)
	var b: Node = _service()
	b.load_saved(TEST_SAVE)
	var before: Dictionary = BattleSerializer.to_dict(b.state)

	var screen: BattleScreen = _screen()
	screen.resume(b)

	assert_eq(BattleSerializer.to_dict(b.state), before, "відновлення не починає новий матч і нічого не змінює")
	assert_true(screen.get_node("%HandoverGate").visible,
		"Продовжити віддає пристрій невідомо кому — спершу гейт (§3.5)")
	assert_null(screen.unit_view_for(1), "до підтвердження гейта юнітів на дошці немає")
	screen.get_node("%HandoverGate").confirmed.emit()
	assert_not_null(screen.unit_view_for(1))


func test_continue_without_or_with_broken_save_fails_without_crashing() -> void:
	var menu: MainMenu = MainMenuScene.instantiate()
	add_child_autofree(menu)
	var b: Node = _service()
	assert_false(menu.continue_saved(b, TEST_SAVE), "файлу нема")

	var f := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	f.store_string("[1]")
	f.close()
	assert_false(menu.continue_saved(b, TEST_SAVE), "JSON, але не словник")
	assert_eq(b.launch_mode, MatchServiceScript.Launch.NONE)
	assert_false((menu.get_node("%ContinueButton") as Button).visible,
		"невдале завантаження ховає «Продовжити»")


func test_rematch_after_continue_reuses_saved_map_path() -> void:
	var a: Node = _service()
	a.configure(MAP_PATH, 2, Terrain.GroundState.MUD, 3)
	_screen().launch(a)
	a.save_current(TEST_SAVE)

	var b: Node = _service()
	assert_true(b.load_saved(TEST_SAVE))
	b.rematch()

	assert_eq(b.map_path, MAP_PATH)
	assert_eq(b.ground_state, Terrain.GroundState.MUD)


# --- 3.5: пауза ----------------------------------------------------------

func test_pause_button_opens_overlay_and_resume_closes_it() -> void:
	var service: Node = _service()
	var screen: BattleScreen = _screen()
	screen.setup(_map(), 2, 1, service)
	var pause: Control = screen.get_node("%PauseMenu")
	assert_false(pause.visible)

	(screen.get_node("%Hud").get_node("%PauseButton") as Button).pressed.emit()
	assert_true(pause.visible)
	assert_eq(pause.get_node("Scrim").color.a, 1.0, "scrim непрозорий: пауза не показує нічого з дошки")

	(pause.get_node("%ResumeButton") as Button).pressed.emit()
	assert_false(pause.visible)


func test_save_and_quit_writes_the_save_and_leaves_to_menu() -> void:
	var service: Node = _service()
	var screen: BattleScreen = _screen()
	screen.setup(_map(), 2, 4, service)
	watch_signals(screen)

	(screen.get_node("%PauseMenu").get_node("%SaveQuitButton") as Button).pressed.emit()

	assert_signal_emitted(screen, "left_to_menu")
	var loaded: BattleState = BattleSerializer.load_from(TEST_SAVE)
	assert_not_null(loaded)
	assert_eq(BattleSerializer.to_dict(loaded), BattleSerializer.to_dict(service.state))


func test_settings_from_pause_opens_over_the_battle_and_back_keeps_it() -> void:
	var service: Node = _service()
	var screen: BattleScreen = _screen()
	screen.setup(_map(), 2, 1, service)

	(screen.get_node("%PauseMenu").get_node("%SettingsButton") as Button).pressed.emit()
	var settings: SettingsScreen = screen.find_child("SettingsScreen", true, false) as SettingsScreen
	assert_not_null(settings, "налаштування відкриті поверх бою, сцена бою жива")
	assert_true(settings.overlay)

	settings.get_node("%BackButton").pressed.emit()
	await wait_process_frames(2)
	assert_null(screen.find_child("SettingsScreen", true, false))
	assert_eq(service.state.turn_number, 1)


# --- 3.5: кінець матчу ---------------------------------------------------

func _finish_match(service: Node, screen: BattleScreen) -> void:
	var shooter: Unit = service.state.units_of(0)[0]
	var victim: Unit = service.state.units_of(1)[0]
	victim.hp = 1
	screen.input_controller().tap_cell(shooter.pos)
	screen.input_controller().tap_cell(victim.pos)
	screen.input_controller().confirm_pending()
	# Твіни програвача зʼявляються між кадрами — підганяємо їх поки черга не спорожніє.
	for i in 6:
		_finish_all_processed_tweens()
		await wait_process_frames(1)


func test_match_ended_deletes_save_and_goes_to_results() -> void:
	var service: Node = _service()
	var screen: BattleScreen = _screen()
	screen.setup(_map(), 2, 1, service)
	service.save_current(TEST_SAVE)
	assert_true(FileAccess.file_exists(TEST_SAVE))
	watch_signals(screen)

	await _finish_match(service, screen)

	assert_true(service.state.is_over())
	assert_signal_emitted(screen, "match_finished")
	assert_false(FileAccess.file_exists(TEST_SAVE), "завершений матч не можна продовжити")
	assert_false(FileAccess.file_exists(TEST_SAVE + ".map"))


# --- 3.5: екран результату -----------------------------------------------

func _result_state() -> BattleState:
	var s: BattleState = BattleState.create(Board.create(6, 6, Terrain.GroundState.DRY), 3, 1)
	s.add_unit(5, 0, Vector2i(0, 0), 0)  # id1 tank p0
	s.add_unit(5, 0, Vector2i(1, 0), 0)  # id2 tank p0, мертвий
	s.add_unit(0, 1, Vector2i(2, 0), 0)  # id3 rifle p1
	s.add_unit(0, 2, Vector2i(3, 0), 0)  # id4 rifle p2, мертвий
	s.add_unit(0, 2, Vector2i(4, 0), 0)  # id5 rifle p2, мертвий
	s.get_unit(2).hp = 0
	s.get_unit(4).hp = 0
	s.get_unit(5).hp = 0
	# Танк p0: поріг 1000 -> рівень 1, лишок 250 => завдано 1250.
	s.experience[0].add_damage(UnitTypes.UnitClass.TANK, 1250)
	# Піхота p1: 150 -> L1, 375 -> L2, лишок 25 => 150+375+25 = 550.
	s.experience[1].add_damage(UnitTypes.UnitClass.INFANTRY, 550)
	Objectives.add(s, Vector2i(5, 5), 0)
	Objectives.add(s, Vector2i(5, 4), 0)
	Objectives.add(s, Vector2i(5, 3), 1)
	s.objectives[1].intact = false  # зруйнована не рахується
	s.winner = 0
	return s


func test_summary_numbers_from_constructed_state() -> void:
	var rows: Array[Dictionary] = ResultsScreen.summarize(_result_state())

	assert_eq(rows.size(), 3)
	assert_eq(rows[0]["losses"], 1)
	assert_eq(rows[1]["losses"], 0)
	assert_eq(rows[2]["losses"], 2)
	assert_eq(rows[0]["damage"], 1250)
	assert_eq(rows[1]["damage"], 550)
	assert_eq(rows[2]["damage"], 0)
	assert_eq(rows[0]["objectives"], 1)
	assert_eq(rows[1]["objectives"], 1)
	assert_eq(rows[2]["objectives"], 0)
	assert_eq(rows[0]["levels"][UnitTypes.UnitClass.TANK], 1)
	assert_eq(rows[1]["levels"][UnitTypes.UnitClass.INFANTRY], 2)


func test_results_screen_shows_winner_and_rows_for_every_player() -> void:
	var service: Node = _service()
	service.state = _result_state()
	var screen: ResultsScreen = ResultsScene.instantiate()
	screen.match_service = service
	add_child_autofree(screen)

	var table: GridContainer = screen.get_node("%Table")
	assert_eq(table.columns, 4, "підпис + 3 гравці")
	assert_string_contains((screen.get_node("%Winner") as Label).text, "1")


# --- 3.3: екран налаштувань -> сервіс ------------------------------------

func test_setup_screen_choice_reaches_the_service() -> void:
	var setup: MatchSetup = (load("res://game/ui/match_setup.tscn") as PackedScene).instantiate()
	add_child_autofree(setup)
	(setup.get_node("%Mud") as Button).button_pressed = true
	var service: Node = _service()

	assert_true(setup.configure_from_choice(service))

	assert_eq(service.map_path, MAP_PATH)
	assert_eq(service.players, 2)
	assert_eq(service.ground_state, Terrain.GroundState.MUD)
	assert_eq(service.launch_mode, MatchServiceScript.Launch.NEW)


# --- Здача з паузи ---------------------------------------------------------

func _map3() -> MapData:
	var m: MapData = _map()
	m.spawns = [
		{"type_id": 5, "owner": 0, "pos": Vector2i(1, 1), "facing": 0},
		{"type_id": 5, "owner": 1, "pos": Vector2i(4, 1), "facing": 0},
		{"type_id": 5, "owner": 2, "pos": Vector2i(1, 4), "facing": 0},
	] as Array[Dictionary]
	return m


func _surrender(screen: BattleScreen) -> void:
	(screen.get_node("%PauseMenu").get_node("%SurrenderButton") as Button).pressed.emit()
	for i in 6:
		_finish_all_processed_tweens()
		await wait_process_frames(1)


func test_surrender_in_two_player_match_ends_it_and_goes_to_results() -> void:
	var service: Node = _service()
	var screen: BattleScreen = _screen()
	screen.setup(_map(), 2, 1, service)
	service.save_current(TEST_SAVE)
	watch_signals(screen)

	await _surrender(screen)

	assert_true(service.state.is_over())
	assert_eq(service.state.winner, 1)
	assert_signal_emitted(screen, "match_finished")
	assert_false(FileAccess.file_exists(TEST_SAVE))
	assert_false(screen.get_node("%PauseMenu").visible)


func test_surrender_in_three_player_match_hands_over_to_next_player() -> void:
	var service: Node = _service()
	var screen: BattleScreen = _screen()
	screen.setup(_map3(), 3, 1, service)
	watch_signals(screen)

	await _surrender(screen)

	assert_false(service.state.is_over())
	assert_eq(service.state.active_player, 1)
	assert_signal_not_emitted(screen, "match_finished")
	assert_true(screen.get_node("%HandoverGate").visible)
	assert_false(screen.get_node("%PauseMenu").visible)


# --- Налаштування: 3 гравці лише на карті з 3 спавнами -----------------------

func test_three_players_offered_only_when_map_has_three_owners() -> void:
	var setup: MatchSetup = (load("res://game/ui/match_setup.tscn") as PackedScene).instantiate()
	add_child_autofree(setup)
	var map: MapData = load(MAP_PATH)
	var owners: Dictionary = {}
	for s in map.spawns:
		owners[int(s["owner"])] = true
	assert_eq(owners.has(2), false, "передумова: поставна карта без спавнів третього")

	assert_true((setup.get_node("%P3") as Button).disabled)
	(setup.get_node("%P3") as Button).button_pressed = true
	assert_false(setup.configure_from_choice(_service()), "3 гравці на карті без третього — не стартує")


func test_start_removes_the_old_save() -> void:
	# delete_save стирає і файл, і сайдкар
	var service: Node = _service()
	service.state = BattleState.create(Board.create(2, 2, 0), 2, 1)
	service.map_path = MAP_PATH
	service.save_current(TEST_SAVE)
	service.delete_save(TEST_SAVE)
	assert_false(FileAccess.file_exists(TEST_SAVE))
	assert_false(FileAccess.file_exists(TEST_SAVE + ".map"))
