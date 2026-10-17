extends Node
## Наскрізний драйвер критерію завершення Фази 3: меню → налаштування матчу →
## бій → пауза → збереження → «Продовжити» → здатися → реванш → мова.
## Керує грою ЛИШЕ синтетичним вводом (миша), станом користується тільки для
## перевірок. Запуск (у вікні, не --headless):
##   $GODOT --path . res://tools/e2e_phase3.tscn -- <out_dir>
## Другий процес (`--check-locale`) драйвер породжує сам на кроці 8.
## Резервує user://save.json(.map) і user://settings.cfg та відновлює в кінці.

const TIMEOUT_S: float = 300.0
const USER_FILES: Array[String] = ["save.json", "save.json.map", "settings.cfg"]
const BACKUP_DIR: String = "user://e2e_backup"

var _out: String = ""
var _fails: int = 0
var _elapsed: float = 0.0
var _finished: bool = false


func _ready() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	_out = a[0] if a.size() > 0 else "user://e2e_out"
	if "--check-locale" in a:
		print("E2E_LOCALE:%s/%s" % [SettingsService.locale, TranslationServer.get_locale()])
		get_tree().quit()
		return
	# Попередній запуск міг обірватися з відібраними файлами — повертаємо їх першими.
	if DirAccess.dir_exists_absolute(BACKUP_DIR):
		_restore()
	print("E2E start")
	DirAccess.make_dir_recursive_absolute(_out)
	# Зміна сцени звільняє current_scene — драйвер мусить пережити перехід.
	get_tree().current_scene = null
	_run.call_deferred()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed > TIMEOUT_S and not _finished:
		_finished = true
		print("FAIL  TIMEOUT after %ds" % int(TIMEOUT_S))
		_restore()
		get_tree().quit(2)


# --- Допоміжне -----------------------------------------------------------

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _until(cond: Callable, timeout: float = 15.0) -> bool:
	var t: float = 0.0
	while t < timeout:
		if cond.call():
			return true
		await _wait(0.05)
		t += 0.05
	return cond.call()


func _check(step: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_fails += 1
	print("%s  %s%s" % ["PASS" if ok else "FAIL", step, ("  -- " + detail) if detail != "" else ""])


func _shot(name: String) -> void:
	await _wait(0.4)
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [_out, name])


func _scene() -> Node:
	return get_tree().current_scene


func _centre(c: Control) -> Vector2:
	return c.get_global_rect().get_center()


func _event(p: Vector2, pressed: bool) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = p
	ev.global_position = p
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	return ev


## Тап у viewport-координатах (stretch=canvas_items, тож це ті самі, що й get_global_rect).
func _tap(p: Vector2, settle: bool = true) -> void:
	var vp: Viewport = get_viewport()
	var mv := InputEventMouseMotion.new()
	mv.position = p
	mv.global_position = p
	vp.push_input(mv, true)
	await get_tree().process_frame
	vp.push_input(_event(p, true), true)
	await _wait(0.06)
	vp.push_input(_event(p, false), true)
	if settle:
		await _wait(0.15)


func _click(c: Control, settle: bool = true) -> void:
	await _tap(_centre(c), settle)


func _backup() -> void:
	DirAccess.make_dir_recursive_absolute(BACKUP_DIR)
	for f in USER_FILES:
		var src: String = "user://" + f
		if FileAccess.file_exists(src):
			DirAccess.copy_absolute(src, "%s/%s" % [BACKUP_DIR, f])
		DirAccess.remove_absolute(src)


func _restore() -> void:
	for f in USER_FILES:
		DirAccess.remove_absolute("user://" + f)
		var bak: String = "%s/%s" % [BACKUP_DIR, f]
		if FileAccess.file_exists(bak):
			DirAccess.copy_absolute(bak, "user://" + f)
			DirAccess.remove_absolute(bak)
	DirAccess.remove_absolute(BACKUP_DIR)


func _dict() -> String:
	return JSON.stringify(BattleSerializer.to_dict(MatchService.state), "", true)


func _battle() -> BattleScreen:
	return _scene() as BattleScreen


func _hud() -> Node:
	return _battle().get_node("UI/Hud")


func _gate() -> HandoverGate:
	return _battle().get_node("UI/HandoverGate") as HandoverGate


func _pause() -> PauseMenu:
	return _battle().get_node("UI/PauseMenu") as PauseMenu


func _event_idle() -> bool:
	return not _battle()._event_player.is_playing()


func _confirm_gate() -> void:
	await _click(_gate().get_node("%ConfirmButton"))
	await _until(func() -> bool: return not _gate().visible)
	await _wait(0.3)


## Чекає, поки бій зʼявиться й досягне стабільного стану (сцена + кадр).
func _await_scene(type: Variant) -> bool:
	var ok: bool = await _until(func() -> bool: return is_instance_of(_scene(), type))
	await _wait(0.6)
	return ok


# --- Сценарій ------------------------------------------------------------

func _run() -> void:
	_backup()
	SettingsService.locale = "uk"
	SettingsService.apply_locale()
	await _flow()
	_finished = true
	_restore()
	print("E2E %s (%d fail)" % ["OK" if _fails == 0 else "FAILED", _fails])
	get_tree().quit(0 if _fails == 0 else 1)


func _flow() -> void:
	# 1. Головне меню, без збереження.
	SceneRouter.goto_main_menu()
	var ok: bool = await _await_scene(MainMenu)
	var menu: MainMenu = _scene() as MainMenu
	await _shot("01_main_menu")
	_check("1 main menu shown, Continue hidden without save", ok and not (menu.get_node("%ContinueButton") as Control).visible)
	if not ok:
		return

	# 2. Новий матч → налаштування → 2 гравці + болото → Старт.
	await _click(menu.get_node("%NewMatchButton"))
	ok = await _await_scene(MatchSetup)
	var setup: Node = _scene()
	if ok:
		await _click(setup.get_node("SafeArea/Center/Card/Body/PlayersRow/P2"))
		await _click(setup.get_node("%Mud"))
	await _shot("02_match_setup")
	if ok:
		await _click(setup.get_node("%StartButton"))
		ok = await _await_scene(BattleScreen)
	var st: BattleState = MatchService.state
	await _shot("03_battle_started")
	var seed0: int = st.seed_value if st != null else -1
	_check("2 setup 2 players + mud reaches battle",
		ok and st != null and st.player_count == 2 and st.board.ground_state == Terrain.GroundState.MUD,
		"players=%s ground=%s" % [st.player_count if st else "-", st.board.ground_state if st else "-"])
	if not ok or st == null:
		return
	var map0: String = MatchService.map_path

	# 3. Хід: вибір юніта, переміщення, кінець ходу туди й назад.
	if _gate().visible:
		await _confirm_gate()
	var moved: bool = await _move_one_unit()
	await _shot("05_after_move")
	await _click(_hud().get_node("%EndTurnButton"))
	var g1: bool = await _until(func() -> bool: return _gate().visible, 20.0)
	var p1: int = MatchService.state.active_player
	await _shot("06_gate_player2")
	await _confirm_gate()
	await _shot("07_player2_turn")
	await _click(_hud().get_node("%EndTurnButton"))
	var g2: bool = await _until(func() -> bool: return _gate().visible, 20.0)
	var p0: int = MatchService.state.active_player
	await _confirm_gate()
	var d1: String = _dict()
	await _shot("08_back_to_player1")
	_check("3 move, end turn, gate, end turn, gate", moved and g1 and g2 and p1 == 1 and p0 == 0 and not _gate().visible,
		"moved=%s gate1=%s gate2=%s p1=%d p0=%d" % [moved, g1, g2, p1, p0])

	# 4. Пауза → Налаштування (оверлей) → Назад: той самий матч.
	await _click(_hud().get_node("%PauseButton"))
	await _shot("09_pause")
	await _click(_pause().get_node("%SettingsButton"))
	await _until(func() -> bool: return _find_settings() != null)
	var ov: Node = _find_settings()
	var opened: bool = ov != null  # лямбда захоплює за значенням — присвоєння в ній не видно ззовні
	await _wait(0.4)
	await _shot("10_settings_overlay")
	if ov != null:
		await _click(ov.get_node("%BackButton"))
	await _wait(0.3)
	await _shot("11_pause_again")
	_check("4 settings overlay open/close keeps same match",
		opened and _find_settings() == null and _scene() is BattleScreen and _dict() == d1 and _pause().visible,
		"ov=%s closed=%s battle=%s same=%s pause=%s" % [opened, _find_settings() == null, _scene() is BattleScreen, _dict() == d1, _pause().visible])

	# 5. Зберегти й вийти → меню з «Продовжити» → гейт → той самий стан.
	await _click(_pause().get_node("%SaveQuitButton"))
	ok = await _await_scene(MainMenu)
	menu = _scene() as MainMenu
	var cont_visible: bool = ok and (menu.get_node("%ContinueButton") as Control).visible
	await _shot("12_menu_with_continue")
	if cont_visible:
		await _click(menu.get_node("%ContinueButton"))
		ok = await _await_scene(BattleScreen)
	var gate_up: bool = ok and _gate().visible
	await _shot("13_continue_gate")
	if gate_up:
		await _confirm_gate()
	await _shot("14_continued_battle")
	_check("5 save&quit, Continue, state equals recorded", cont_visible and gate_up and _dict() == d1,
		"continue_visible=%s gate=%s" % [cont_visible, gate_up])
	if not (cont_visible and ok):
		return

	# 6. Здатися → результати з переможцем, збереження видалене.
	var seed_before: int = MatchService.state.seed_value
	var surrendering: int = MatchService.state.active_player
	await _click(_hud().get_node("%PauseButton"))
	await _click(_pause().get_node("%SurrenderButton"))
	ok = await _await_scene(ResultsScreen)
	await _shot("15_results")
	var res: Node = _scene()
	var winner_text: String = (res.get_node("%Winner") as Label).text if ok else ""
	var save_gone: bool = not FileAccess.file_exists(MatchService.SAVE_PATH)
	_check("6 surrender -> results with opponent as winner, save deleted",
		ok and MatchService.state.winner == 1 - surrendering and save_gone,
		"winner=%d expected=%d label='%s' save_gone=%s" % [MatchService.state.winner, 1 - surrendering, winner_text, save_gone])
	if not ok:
		return

	# 7. Реванш: нова партія, інший сід, та сама карта/гравці.
	await _click(res.get_node("%RematchButton"))
	ok = await _await_scene(BattleScreen)
	await _shot("16_rematch_battle")
	st = MatchService.state
	_check("7 rematch: new seed, same map and players", ok and st.seed_value != seed_before and MatchService.map_path == map0 and st.player_count == 2 and seed_before != seed0 - 1,
		"seed %d -> %d map=%s" % [seed_before, st.seed_value if st else -1, MatchService.map_path])
	if not ok:
		return

	# 6b. Здатися ще раз, «У меню»: Continue сховано.
	if _gate().visible:
		await _confirm_gate()
	await _click(_hud().get_node("%PauseButton"))
	await _click(_pause().get_node("%SurrenderButton"))
	ok = await _await_scene(ResultsScreen)
	if ok:
		await _click(_scene().get_node("%ToMenuButton"))
		ok = await _await_scene(MainMenu)
	menu = _scene() as MainMenu
	await _shot("17_menu_after_results")
	_check("6b results -> menu, Continue hidden, no save file",
		ok and not (menu.get_node("%ContinueButton") as Control).visible and not FileAccess.file_exists(MatchService.SAVE_PATH))

	# 8. Мова en зберігається між процесами.
	await _click(menu.get_node("%SettingsButton"))
	ok = await _await_scene(SettingsScreen)
	if ok:
		await _click(_scene().get_node("%LangEn"))
	await _wait(0.3)
	await _shot("18_settings_english")
	var in_proc: bool = TranslationServer.get_locale().begins_with("en")
	if ok:
		await _click(_scene().get_node("%BackButton"))
		ok = await _await_scene(MainMenu)
	menu = _scene() as MainMenu
	await _shot("19_menu_english")
	# Вихід із гри — справжня кнопка; кадр завершується, але синхронний код ще виконується.
	await _tap(_centre(menu.get_node("%QuitButton")), false)
	var out: Array = []
	var args: PackedStringArray = ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"res://tools/e2e_phase3.tscn", "--", _out, "--check-locale"]
	OS.execute(OS.get_executable_path(), args, out, true)
	var text: String = "".join(PackedStringArray(out))
	_check("8 locale en persisted across processes", in_proc and ok and "E2E_LOCALE:en/en" in text,
		"child said: %s" % text.strip_edges().replace("\n", " | "))


func _find_settings() -> Node:
	for c in _battle().get_node("UI").get_children():
		if c is SettingsScreen:
			return c
	return null


## Тап по юніту, тап по досяжній сусідній клітинці, підтвердити в HUD.
func _move_one_unit() -> bool:
	var battle: BattleScreen = _battle()
	var rig: IsoCameraRig = battle.get_node("%CameraRig")
	await _wait(1.5)  # політ камери до першого юніта
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
			await _tap(upos)
			var sel_ok: bool = battle.input_controller()._selected_unit == u
			await _shot("04_unit_selected")
			await _tap(cpos)
			var pend: bool = not battle.input_controller()._pending.is_empty()
			await _shot("04b_move_preview")
			if not (sel_ok and pend):
				print("  (select=%s pending=%s)" % [sel_ok, pend])
				return false
			await _click(_hud().get_node("%ConfirmButton"))
			await _until(func() -> bool: return u.pos != start and _event_idle(), 10.0)
			await _wait(0.4)
			return u.pos == cell
	return false
