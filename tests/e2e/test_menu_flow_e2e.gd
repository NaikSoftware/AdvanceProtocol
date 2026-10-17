extends GutTest
## Наскрізний сценарій меню: головне меню → новий матч → налаштування (2 гравці +
## болото) → бій (хід, кінець ходу, гейти) → пауза → налаштування-оверлей →
## зберегти й вийти → продовжити → здатися → результати → реванш → здатися → у меню →
## мова. Це порт tools/e2e_phase3.gd у headless GUT.
##
## Ввід — справжні кліки мишею у viewport (і по дошці, і по кнопках); жодного
## pressed.emit(). Екрани міняє справжній автозавантажений SceneRouter, матч веде
## справжній MatchService — їхній стан відновлюється в after_each.
##
## Справжніх user://save.json і settings.cfg тест НЕ чіпає. Відхилення від
## оригіналу, продиктовані цим (у production-коді шляхи не ін'єктуються скрізь):
##  - MainMenu вирішує видимість «Продовжити» і клік по ній з константи
##    MainMenu.SAVE_PATH, тож «Продовжити» перевіряється викликом
##    continue_saved(service, TEST_SAVE) і подальшим переходом у бій, а не кліком;
##  - SettingsScreen пише налаштування лише у справжній settings.cfg, тож мова en
##    перевіряється як save(TEST_CFG) + load(TEST_CFG) у свіжому інстансі
##    SettingsService, а не кліком по %LangEn і не другим процесом.

const E2E := preload("res://tests/e2e/e2e_helpers.gd")
const SettingsServiceScript := preload("res://game/autoload/settings_service.gd")
const MatchServiceScript := preload("res://game/autoload/match_service.gd")

var _pid: int = OS.get_process_id()
var TEST_SAVE: String = "user://e2e_save_%d.json" % _pid
var TEST_CFG: String = "user://e2e_settings_%d.cfg" % _pid

var _e2e: E2E
var _saved_locale: String = ""
var _saved_service: Dictionary = {}


func before_each() -> void:
	_e2e = E2E.new(self)
	_saved_locale = SettingsService.locale
	_saved_service = {
		"state": MatchService.state, "launch_mode": MatchService.launch_mode,
		"map_path": MatchService.map_path, "players": MatchService.players,
		"ground_state": MatchService.ground_state, "seed_value": MatchService.seed_value,
	}
	_e2e.ignore_runner_gui()


func after_each() -> void:
	_e2e.restore_runner_gui()
	var cur: Node = get_tree().current_scene
	if cur != null:
		cur.queue_free()
		get_tree().current_scene = null
	for k: String in _saved_service:
		MatchService.set(k, _saved_service[k])
	SettingsService.locale = _saved_locale
	SettingsService.apply_locale()
	for p in [TEST_SAVE, TEST_SAVE + ".map", TEST_CFG]:
		DirAccess.remove_absolute(p)


# --- Каркас ------------------------------------------------------------------

func _scene() -> Node:
	return get_tree().current_scene


func _await_scene(type: Variant) -> bool:
	return await _e2e.wait_until(func() -> bool: return is_instance_of(_scene(), type), "зміна сцени")


func _click(c: Control) -> void:
	assert_true(c.is_visible_in_tree(), "кнопка видима: %s" % c.name)
	_e2e.click_at(c.get_global_rect().get_center())
	await get_tree().process_frame


func _battle() -> BattleScreen:
	return _scene() as BattleScreen


func _hud() -> Hud:
	return _battle().get_node("%Hud")


func _gate() -> HandoverGate:
	return _battle().get_node("%HandoverGate") as HandoverGate


func _pause() -> PauseMenu:
	return _battle().get_node("%PauseMenu") as PauseMenu


func _idle() -> bool:
	var b: BattleScreen = _battle()
	return b != null and not b._event_player.is_playing()


## Бій створюється роутером, тож його шлях збереження (типово — справжній
## user://save.json) підміняємо одразу, до першої дії, що могла б його торкнутись.
func _redirect_save() -> void:
	_battle().save_path = TEST_SAVE


func _dict() -> String:
	return JSON.stringify(BattleSerializer.to_dict(MatchService.state), "", true)


func _confirm_gate() -> void:
	await _click(_gate().get_node("%ConfirmButton"))
	await _e2e.wait_until(func() -> bool: return not _gate().visible, "гейт зник")


func _find_settings() -> Node:
	for c in _battle().get_node("UI").get_children():
		if c is SettingsScreen:
			return c
	return null


func _surrender() -> void:
	await _click(_hud().get_node("%PauseButton"))
	await _click(_pause().get_node("%SurrenderButton"))
	await _click(_pause().get_node("%ConfirmYesButton"))


## Тап по юніту, тап по досяжній сусідній клітинці, підтвердити в HUD.
func _move_one_unit() -> bool:
	var battle: BattleScreen = _battle()
	var rig: IsoCameraRig = battle.get_node("%CameraRig")
	await _e2e.wait_until(_idle, "програвання подій")
	var state: BattleState = MatchService.state
	var viewport_rect: Rect2 = get_viewport().get_visible_rect().grow(-120.0)
	for u in state.units_of(state.active_player):
		var occ: Dictionary = state.known_occupied_map(u.owner)
		occ.erase(u.pos)
		var zones: Pathing.Zones = Pathing.compute_zones(state.board, u, occ)
		var upos: Vector2 = rig.unproject(IsoCameraRig.cell_to_world(u.pos))
		if not viewport_rect.has_point(upos):
			continue
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var cell: Vector2i = u.pos + d
			if occ.has(cell) or not state.board.in_bounds(cell) or not zones.can_reach(cell):
				continue
			var cpos: Vector2 = rig.unproject(IsoCameraRig.cell_to_world(cell))
			if not viewport_rect.has_point(cpos):
				continue
			var start: Vector2i = u.pos
			_e2e.click_at(upos)
			assert_eq(battle.input_controller()._selected_unit, u, "тап вибрав юніт")
			_e2e.click_at(cpos)
			assert_false(battle.input_controller()._pending.is_empty(), "тап по клітинці дав прев'ю руху")
			await _click(_hud().get_node("%ConfirmButton"))
			await _e2e.wait_until(func() -> bool: return u.pos != start and _idle(), "юніт дійшов")
			return u.pos == cell
	return false


# --- Сценарій ------------------------------------------------------------------

func test_menu_to_battle_to_menu_flow() -> void:
	SettingsService.locale = "uk"
	SettingsService.apply_locale()

	# 1. Головне меню, без збереження.
	SceneRouter.goto_main_menu()
	assert_true(await _await_scene(MainMenu))
	var menu: MainMenu = _scene() as MainMenu
	var probe: Node = MatchServiceScript.new()
	add_child_autofree(probe)
	assert_false(menu.continue_saved(probe, TEST_SAVE), "1: без збереження продовжувати нічого")
	assert_false((menu.get_node("%ContinueButton") as Control).visible, "1: «Продовжити» сховано")
	assert_null(probe.state)

	# 2. Новий матч → налаштування → 2 гравці + болото → Старт.
	await _click(menu.get_node("%NewMatchButton"))
	assert_true(await _await_scene(MatchSetup), "2: екран налаштувань")
	var setup: MatchSetup = _scene() as MatchSetup
	setup.save_path = TEST_SAVE  # Старт стирає старе збереження — лише тестове
	await _click(setup.get_node("%P2"))
	await _click(setup.get_node("%Mud"))
	await _click(setup.get_node("%StartButton"))
	assert_true(await _await_scene(BattleScreen), "2: бій")
	_redirect_save()
	var st: BattleState = MatchService.state
	assert_not_null(st)
	assert_eq(st.player_count, 2, "2: два гравці")
	assert_eq(st.board.ground_state, Terrain.GroundState.MUD, "2: болото")
	var seed0: int = st.seed_value
	var map0: String = MatchService.map_path
	assert_ne(map0, "")

	# 3. Хід: вибір юніта, переміщення, кінець ходу туди й назад.
	assert_true(_gate().visible, "3: новий матч починається за гейтом")
	await _confirm_gate()
	assert_true(await _move_one_unit(), "3: юніт переміщено тапами")
	await _click(_hud().get_node("%EndTurnButton"))
	await _e2e.wait_until(func() -> bool: return _gate().visible, "гейт гравця 2")
	assert_eq(MatchService.state.active_player, 1)
	await _confirm_gate()
	await _click(_hud().get_node("%EndTurnButton"))
	await _e2e.wait_until(func() -> bool: return _gate().visible, "гейт гравця 1")
	assert_eq(MatchService.state.active_player, 0)
	await _confirm_gate()
	assert_false(_gate().visible)
	var d1: String = _dict()

	# 4. Пауза → Налаштування (оверлей) → Назад: той самий матч.
	await _click(_hud().get_node("%PauseButton"))
	assert_true(_pause().visible)
	await _click(_pause().get_node("%SettingsButton"))
	assert_not_null(_find_settings(), "4: оверлей налаштувань відкрито")
	await _click(_find_settings().get_node("%BackButton"))
	await _e2e.wait_until(func() -> bool: return _find_settings() == null, "оверлей закрито")
	assert_true(_scene() is BattleScreen, "4: бій на місці")
	assert_eq(_dict(), d1, "4: стан матчу не змінився")
	assert_true(_pause().visible, "4: пауза знову видна")

	# 5. Зберегти й вийти → меню → продовжити → гейт → той самий стан.
	await _click(_pause().get_node("%SaveQuitButton"))
	assert_true(await _await_scene(MainMenu), "5: меню після «Зберегти й вийти»")
	assert_true(FileAccess.file_exists(TEST_SAVE), "5: збереження записано")
	menu = _scene() as MainMenu
	MatchService.state = null  # «новий процес»: пам'ять про матч — лише у файлі
	assert_true(menu.continue_saved(MatchService, TEST_SAVE), "5: «Продовжити» відновлює матч")
	SceneRouter.goto_battle()  # те, що робить _on_continue_pressed після continue_saved()
	assert_true(await _await_scene(BattleScreen), "5: бій відновлено")
	_redirect_save()
	assert_true(_gate().visible, "5: після «Продовжити» — гейт")
	await _confirm_gate()
	assert_eq(_dict(), d1, "5: стан дорівнює збереженому")

	# 6. Здатися → результати з переможцем, збереження видалене.
	var seed_before: int = MatchService.state.seed_value
	var surrendering: int = MatchService.state.active_player
	await _click(_hud().get_node("%PauseButton"))
	await _click(_pause().get_node("%SurrenderButton"))
	assert_true(_pause().get_node("%ConfirmBox").visible, "6: спершу підтвердження")
	await _click(_pause().get_node("%ConfirmYesButton"))
	assert_true(await _await_scene(ResultsScreen), "6: екран результатів")
	var res: ResultsScreen = _scene() as ResultsScreen
	assert_eq(MatchService.state.winner, 1 - surrendering, "6: переможець — суперник")
	assert_string_contains((res.get_node("%Winner") as Label).text, str(2 - surrendering))
	assert_false(FileAccess.file_exists(TEST_SAVE), "6: збереження видалене")

	# 7. Реванш: нова партія, інший сід, та сама карта/гравці/ґрунт.
	await _click(res.get_node("%RematchButton"))
	assert_true(await _await_scene(BattleScreen), "7: бій реваншу")
	_redirect_save()
	st = MatchService.state
	assert_ne(st.seed_value, seed_before, "7: новий сід")
	assert_eq(MatchService.map_path, map0, "7: та сама карта")
	assert_eq(st.player_count, 2)
	assert_eq(st.board.ground_state, Terrain.GroundState.MUD)
	assert_true(seed0 >= 0)

	# 8. Здатися ще раз, «У меню»: «Продовжити» сховано, файлу нема.
	await _confirm_gate()
	await _surrender()
	assert_true(await _await_scene(ResultsScreen), "8: результати")
	await _click(_scene().get_node("%ToMenuButton"))
	assert_true(await _await_scene(MainMenu), "8: меню")
	menu = _scene() as MainMenu
	assert_false(FileAccess.file_exists(TEST_SAVE), "8: файлу збереження нема")
	var probe2: Node = MatchServiceScript.new()
	add_child_autofree(probe2)
	assert_false(menu.continue_saved(probe2, TEST_SAVE))
	assert_false((menu.get_node("%ContinueButton") as Control).visible, "8: «Продовжити» сховано")

	# 9. Мова en зберігається між запусками (див. шапку: через тестовий cfg).
	SettingsService.locale = "en"
	SettingsService.apply_locale()
	await _click(menu.get_node("%SettingsButton"))
	assert_true(await _await_scene(SettingsScreen), "9: екран налаштувань")
	assert_true((_scene().get_node("%LangEn") as Button).button_pressed, "9: en вибрана в інтерфейсі")
	assert_true(TranslationServer.get_locale().begins_with("en"))
	await _click(_scene().get_node("%BackButton"))
	assert_true(await _await_scene(MainMenu), "9: назад у меню")
	assert_eq(SettingsService.save(TEST_CFG), OK)
	var fresh: Node = SettingsServiceScript.new()
	fresh.locale = "uk"
	fresh.load(TEST_CFG)
	assert_eq(fresh.locale, "en", "9: свіжий сервіс читає en зі збереженого файлу")
	fresh.free()
