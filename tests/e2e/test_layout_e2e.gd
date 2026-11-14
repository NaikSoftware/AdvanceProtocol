extends GutTest
## Увесь HUD бою — плита верб, прев'ю ремонту, дрон із прев'ю й тостом причини, підпис
## «нижня межа» — влазить у кожен розмір LayoutProbe.SIZES,
## і дошка між смугами лишається досить високою й тапабельною. Стани наводяться
## справжніми тапами (click_at у SubViewport), а не викликами HUD напряму.

const E2E := preload("res://tests/e2e/e2e_helpers.gd")
const A := EngineerCommand.Action

const RIFLE: int = 0
const ASSAULT: int = 1
const MEDIUM_TANK: int = 5
const ENGINEER: int = 11
const E: int = 2

const ENG := Vector2i(4, 2)
const HURT := Vector2i(5, 2)
const SQUAD := Vector2i(2, 2)
const ENEMY_TANK := Vector2i(6, 2)  # 4 від загону — у дальності дрона (5)
const ENEMY_INF := Vector2i(4, 4)
const FAR := Vector2i(9, 4)

const LOCALES: Array[String] = ["en", "uk"]

var _e2e: E2E
var _orig_locale: String


## Кожен розмір LayoutProbe.SIZES × кожна мова: українські підписи довші, але
## англійські рвуть рядки інакше — влазити мусять обидві.
static func _sizes_by_locale() -> Array:
	var out: Array = []
	for size: Vector2i in LayoutProbe.SIZES:
		for locale: String in LOCALES:
			out.append([size, locale])
	return out


func before_each() -> void:
	_e2e = E2E.new(self)
	_orig_locale = TranslationServer.get_locale()


func after_each() -> void:
	TranslationServer.set_locale(_orig_locale)
	_e2e.restore_runner_gui()
	DirAccess.remove_absolute(_e2e.save_path)
	DirAccess.remove_absolute(_e2e.save_path + ".map")


func _spawn(type_id: int, owner: int, pos: Vector2i) -> Dictionary:
	return {"type_id": type_id, "owner": owner, "pos": pos, "facing": E}


## 10×5, усе розвідано обома гравцями, екран у SubViewport розміру size.
func _boot(size: Vector2i, spawns: Array, prepare: Callable = Callable()) -> void:
	await _e2e.boot(10, 5, spawns, {"viewport_size": size,
		"prepare": func(st: BattleState) -> void:
			for pl in st.player_count:
				st.vision[pl].seen.fill(1)
			if prepare.is_valid():
				prepare.call(st)})


func _node(path: String) -> Control:
	return _e2e.hud().get_node(path)


## Справжній тап по кнопці HUD — у центр її прямокутника у viewport екрана.
func _tap_button(b: Control) -> void:
	_e2e.click_at(b.get_global_rect().get_center(), _e2e.vp)
	await _e2e.settle()


func _tap(cell: Vector2i) -> void:
	_e2e.tap(cell)
	await _e2e.settle()


## Усе, що HUD малює на дошці й що ловить тап: плити стають за правилом стикування, тож жодна
## не накриває юніта, який бачить гравець (екранні прямокутники вузлів UnitView). 
func _board_plates() -> Array[Control]:
	var out: Array[Control] = []
	var panel: EngineerPanel = _e2e.engineer_panel()
	for c: Control in [_node("%PreviewPlate"), _node("%ActionRow"), _node("%DroneButton"), _node("%DroneStrip"),
			panel.plate() if panel.visible else null, panel.strip() if panel.visible else null]:
		if c != null and c.is_visible_in_tree():
			out.append(c)
	return out


func _assert_fits(size: Vector2i, where: String) -> void:
	var hud: Hud = _e2e.hud()
	assert_eq(LayoutProbe.overflowing(hud, size), [] as Array[String], where)
	assert_eq(LayoutProbe.small_targets(hud), [] as Array[String], where)
	var chrome: Array[Control] = [_node("%Chip"), _node("%PauseButton"), _node("%EndTurnButton")]
	var plates: Array[Control] = _board_plates()
	assert_eq(LayoutProbe.overlapping(chrome), [] as Array[String], where)
	for plate in plates:
		for corner in chrome:
			assert_false(plate.get_global_rect().intersects(corner.get_global_rect()),
				"%s налазить на %s: %s" % [plate.name, corner.name, where])
	# Чистота від юнітів: плита, що закриває видимого юніта, — дефект, а не запасний варіант.
	var rig: IsoCameraRig = _e2e.screen.get_node("%CameraRig")
	for id: int in _e2e.service.state.units:
		var view: UnitView = _e2e.screen.unit_view_for(id)
		if view == null:
			continue
		var box: Rect2 = UnitScreenBox.of(view, rig).grow(HudDocking.UNIT_MARGIN)
		for plate in plates:
			assert_false(plate.get_global_rect().intersects(box),
				"%s перекриває юніта %d (кластер %s): %s" % [plate.name, id, hud.cluster_name(), where])


func test_full_hud_fits_every_size(p = use_parameters(_sizes_by_locale())) -> void:
	var size: Vector2i = p[0]
	TranslationServer.set_locale(p[1])
	await _boot(size, [_spawn(ENGINEER, 0, ENG), _spawn(MEDIUM_TANK, 0, HURT), _spawn(RIFLE, 1, FAR)],
		func(st: BattleState) -> void: st.unit_at(HURT).hp = 300)
	await _tap(ENG)
	var panel: EngineerPanel = _e2e.engineer_panel()
	assert_true(panel.is_visible_in_tree(), "панель інженера: %s" % size)
	_assert_fits(size, "інженер %s" % size)
	var repair: Button = panel.button_for(A.REPAIR_UNIT)
	assert_eq(LayoutProbe.clipped(_e2e.hud(), [repair] as Array[Control], size), [] as Array[String], "«Ремонт» видно: %s" % size)
	await _tap_button(repair)
	await _tap(HURT)
	assert_true(_node("%PreviewRepairBox").is_visible_in_tree(), "прев'ю ремонту: %s" % size)
	assert_true((_node("%PreviewPlate") as Control).is_visible_in_tree(), "плита-хост показана: діти під SubViewport самі цього не доводять")
	# Golden T9: повний AP інженера — межі [20, 43].
	assert_eq((_node("%PreviewHealValue") as Label).text, "20–43")
	_assert_fits(size, "ремонт %s" % size)


## Найтісніші стани нижнього рядка: озброєний дрон із прев'ю, з причиною відмови,
## і огляд ворога з рядком «нижня межа».
func test_drone_and_threat_floor_fit_every_size(p = use_parameters(_sizes_by_locale())) -> void:
	var size: Vector2i = p[0]
	TranslationServer.set_locale(p[1])
	await _boot(size, [_spawn(ASSAULT, 0, SQUAD), _spawn(MEDIUM_TANK, 1, ENEMY_TANK), _spawn(ASSAULT, 1, ENEMY_INF)])
	await _tap(SQUAD)
	var drone: Control = _node("%DroneButton")
	assert_true(drone.is_visible_in_tree(), "кнопка дрона: %s" % size)
	_assert_fits(size, "загін %s" % size)
	await _tap_button(drone)
	assert_true(_node("%DroneStrip").is_visible_in_tree(), "смужка озброєного дрона: %s" % size)
	_assert_fits(size, "дрон озброєно %s" % size)
	await _tap(ENEMY_TANK)
	assert_eq((_node("%PreviewDroneDamageValue") as Label).text, "120–180")
	_assert_fits(size, "дрон, прев'ю %s" % size)
	# Без settle(): він гасить усі твіни, а тост живе 2 с.
	_e2e.tap(ENEMY_INF)
	assert_true(_node("%Toast").is_visible_in_tree(), "причина: %s" % size)
	assert_eq((_node("%ToastLabel") as Label).text, tr("ERR_DRONE_CANNOT_TARGET_INFANTRY"))
	_assert_fits(size, "дрон, причина %s" % size)
	# Зняти режим і вибір, тоді огляд ворожого танка: лише кільце гармати, тож рядка
	# «нижня межа» немає (§3.13) — він з'являється тільки з дроновим кільцем, нижче.
	await _tap_button(_node("%CancelButton"))
	await _tap(SQUAD)
	assert_false(_node("%DroneButton").is_visible_in_tree(), "вибір знято: %s" % size)
	_e2e.long_press(ENEMY_TANK)
	await _e2e.settle()
	assert_false(_node("%ThreatFloorLabel").is_visible_in_tree(), "кільце гармати — без нижньої межі: %s" % size)
	_assert_fits(size, "огляд ворога %s" % size)
	_e2e.release(ENEMY_TANK)
	# Найтісніше: вибраний загін тапає ворожий загін із дронами (прев'ю пострілу), а
	# довгий натиск на нього дає довший рядок «нижня межа» (дрон) — в одному нижньому рядку.
	await _tap(SQUAD)
	await _tap(ENEMY_INF)
	_e2e.long_press(ENEMY_INF)
	await _e2e.settle()
	assert_true(_node("%ThreatFloorLabel").is_visible_in_tree(), "нижня межа з вибором: %s" % size)
	assert_eq((_node("%ThreatFloorLabel") as Label).text, tr("hud_threat_floor_drone"))
	assert_true(_node("%PreviewShotBox").is_visible_in_tree(), "прев'ю пострілу: %s" % size)
	assert_true((_node("%PreviewPlate") as Control).is_visible_in_tree(), "плита-хост показана: діти під SubViewport самі цього не доводять")
	_assert_fits(size, "огляд ворога + постріл %s" % size)
	_e2e.release(ENEMY_INF)


## Підказка озброєної верби (що тапнути) влазить на кожен розмір обома мовами — для
## кожної з п'яти верб. Сусіди інженера дають ціль кожній: поранений танк, зруйнований
## і цілий міст, своя міна.
func test_engineer_hint_fits_every_size(p = use_parameters(_sizes_by_locale())) -> void:
	var size: Vector2i = p[0]
	TranslationServer.set_locale(p[1])
	var broken := ENG + Vector2i.LEFT
	var bridge := ENG + Vector2i.UP
	var mine := ENG + Vector2i.DOWN
	await _e2e.boot(10, 5, [_spawn(ENGINEER, 0, ENG), _spawn(MEDIUM_TANK, 0, HURT), _spawn(RIFLE, 1, FAR)],
		{"viewport_size": size, "tiles": {broken: Terrain.Kind.BRIDGE_DESTROYED, bridge: Terrain.Kind.BRIDGE},
		"prepare": func(st: BattleState) -> void:
			for pl in st.player_count:
				st.vision[pl].seen.fill(1)
			st.unit_at(HURT).hp = 300
			Mines.place(st, mine, 0)})
	await _tap(ENG)
	var panel: EngineerPanel = _e2e.engineer_panel()
	var hint: Label = panel.strip().hint_label
	for a: int in EngineerPanel.LABEL_KEYS:
		var where: String = "верба %d %s %s" % [a, size, p[1]]
		var b: Button = panel.button_for(a)
		await _tap_button(b)
		assert_true(hint.is_visible_in_tree(), where)
		assert_eq(LayoutProbe.clipped(_e2e.hud(), [hint] as Array[Control], size), [] as Array[String], where)
		_assert_fits(size, where)
		await _tap_button(panel.strip().cancel_button)


## На PHONE_SMALL, з відкритою панеллю інженера, тап у центр смуги дошки вибирає
## юніт, що там стоїть. Дошка заповнена своїми загонами — під центром завжди хтось є.
func test_board_still_tappable_on_phone(p = use_parameters(LOCALES)) -> void:
	TranslationServer.set_locale(p)
	var size: Vector2i = LayoutProbe.PHONE_SMALL
	# Інженер не перший: камера стає на перший юніт гравця, і центр смуги не має
	# припасти на самого інженера (повторний тап зняв би вибір).
	var eng_pos := Vector2i(3, 2)
	var spawns: Array = [_spawn(RIFLE, 1, FAR)]
	for y in 5:
		for x in 10:
			var c := Vector2i(x, y)
			if c != FAR:
				spawns.append(_spawn(ENGINEER if c == eng_pos else RIFLE, 0, c))
	await _boot(size, spawns)
	await _tap(eng_pos)
	assert_true(_e2e.engineer_panel().is_visible_in_tree(), "панель інженера відкрита")
	var centre := Vector2(size.x * 0.5, size.y * 0.5)
	var rig: IsoCameraRig = _e2e.screen.get_node("%CameraRig")
	var cell: Vector2i = rig.screen_point_to_cell(centre)
	var unit: Unit = _e2e.service.state.unit_at(cell)
	assert_not_null(unit, "під центром смуги %s — тайл %s" % [centre, cell])
	assert_ne(cell, eng_pos, "центр — не сам інженер")
	_e2e.click_at(centre, _e2e.vp)
	await _e2e.settle()
	assert_eq(_e2e.screen.input_controller()._selected_unit, unit, "тап у %s вибрав юніт на %s" % [centre, cell])
