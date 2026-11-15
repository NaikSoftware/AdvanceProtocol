extends GutTest
## Панель верб інженера. Доступність і причина — лише з EngineerCommand.action_status() (§3.13);
## панель нічого не виводить сама. Причина йде сигналом refused() у тост HUD.

const PanelScene := preload("res://game/ui/engineer_panel.tscn")
const HudScene := preload("res://game/ui/hud.tscn")
const MatchServiceScript := preload("res://game/autoload/match_service.gd")

const ENGINEER: int = 11
const A := EngineerCommand.Action

## Golden: підписи кнопок англійською, у порядку EngineerCommand.Action. Без ціни: кожна верба
## коштує той самий fire_cost — окремий рядок ціни нічого не додає.
const EN_LABELS: Array[String] = [
	"Lay mine", "Clear mine", "Repair bridge", "Demolish bridge", "Repair unit",
]
const VERBS: Array[int] = [A.LAY_MINE, A.CLEAR_MINE, A.REPAIR_BRIDGE, A.DEMOLISH_BRIDGE, A.REPAIR_UNIT]

var _service: Node
var _orig_locale: String


func before_each() -> void:
	_orig_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	_service = MatchServiceScript.new()
	add_child_autofree(_service)
	_service.start_match(Board.create(8, 8, Terrain.GroundState.DRY), 2, 1)


func after_each() -> void:
	TranslationServer.set_locale(_orig_locale)


func _engineer() -> Unit:
	var e: Unit = _service.state.add_unit(ENGINEER, 0, Vector2i(3, 3), 0)
	_service.begin()
	_service.take_events()
	return e


func _panel() -> EngineerPanel:
	var p: EngineerPanel = PanelScene.instantiate()
	# Без теми HUD кнопки й шрифти дефолтні, і розміри плити нічого не означають.
	p.theme = load("res://game/ui/theme/hud_theme.tres")
	add_child_autofree(p)
	return p


func test_five_buttons_without_ap_cost_in_one_plate() -> void:
	var e: Unit = _engineer()
	var p: EngineerPanel = _panel()
	p.show_for(_service.state, e)
	var labels: Array[String] = []
	for a: int in VERBS:
		labels.append(p.button_for(a).text)
	assert_eq(labels, EN_LABELS)
	var order: Array[String] = []
	for b in p.plate().get_node("Box").get_children():
		if b is Button:
			order.append((b as Button).text)
	assert_eq(order, EN_LABELS, "рівно п'ять кнопок, у порядку Action")
	assert_eq(p.active_size(), Vector2(269, 148), "сітка 2 × 3: 2 × 133 + 3 × 48, роздільники й краї по 1 dp")
	assert_eq((p.plate().get_node("Box") as GridContainer).columns, 2, "дві колонки, а не стовпчик із п'яти рядків")
	for a: int in VERBS:
		assert_eq(p.button_for(a).size, Vector2(133, 48), "клітинка 133 × 48: %s" % EN_LABELS[a])


## Заливка сітки щільніша за тихі кнопки (0,88 проти 0,65), щоб лінії дошки не перетинали клітинки,
## а порожня шоста клітинка не має ні заливки, ні роздільників: інакше вона читається мертвою кнопкою.
func test_grid_fill_is_dense_and_skips_the_empty_cell() -> void:
	var e: Unit = _engineer()
	var p: EngineerPanel = _panel()
	p.show_for(_service.state, e)
	await get_tree().process_frame
	assert_eq(EngineerPanel.GRID_FILL_ALPHA, 0.88)
	var empty := Rect2(135, 99, 133, 48)
	assert_eq(p.face_rects(), [Rect2(0, 0, 269, 99), Rect2(0, 99, 135, 49)] as Array[Rect2],
		"два прямокутники без накладання: верхні два ряди й ліва клітинка третього")
	for r: Rect2 in p.face_rects() + p.hair_rects():
		assert_false(r.intersects(empty), "порожня клітинка без заливки й роздільників: %s" % r)
	assert_eq(p.hair_rects(), [Rect2(134, 1, 1, 97), Rect2(1, 49, 267, 1), Rect2(1, 98, 133, 1)] as Array[Rect2],
		"роздільники лише між заповненими клітинками")
	assert_eq(p.active_size(), Vector2(269, 148), "розмір плити для стикування не змінюється")
	# Смужка озброєння лишається тихою, як кнопки ряду.
	assert_almost_eq((p.strip().get_theme_stylebox(&"panel") as StyleBoxFlat).bg_color.a, 0.65, 0.001)


## Кожна верба в клітинці: значок, проміжок 6 і назва без обрізання, ≥ 7 dp повітря від краю клітинки
## з обох боків — обома мовами, приглушені теж (вони такі самі за шириною, але іншим шрифтом).
func test_every_verb_fits_its_cell_with_air_on_both_sides() -> void:
	var e: Unit = _engineer()
	var p: EngineerPanel = _panel()
	for locale: String in ["uk", "en"]:
		TranslationServer.set_locale(locale)
		p.show_for(_service.state, e)
		for a: int in VERBS:
			for variation: StringName in [EngineerPanel.AVAILABLE_VARIATION, EngineerPanel.UNAVAILABLE_VARIATION]:
				var b: Button = p.button_for(a)
				b.theme_type_variation = variation
				var box: StyleBox = b.get_theme_stylebox(&"normal")
				var font: Font = b.get_theme_font(&"font")
				var text_w: float = font.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, b.get_theme_font_size(&"font_size")).x
				var icon_w: float = float(b.get_theme_constant(&"icon_max_width"))
				var gap: float = float(b.get_theme_constant(&"h_separation"))
				var where: String = "%s %s %s" % [locale, b.text, variation]
				assert_eq(icon_w, 16.0, "значок 16 dp: " + where)
				assert_eq(gap, 6.0, "один проміжок 6 dp: " + where)
				assert_gte(box.content_margin_left, 7.0, "значок → край клітинки: " + where)
				assert_gte(133.0 - box.content_margin_left - icon_w - gap - text_w, 7.0, "назва → край клітинки: " + where)
				assert_gte(b.get_theme_font_size(&"font_size"), 11, where)


func test_unavailable_button_reports_the_reason_on_press() -> void:
	var e: Unit = _engineer()
	var p: EngineerPanel = _panel()
	p.show_for(_service.state, e)
	var chosen: Array[int] = []
	p.action_chosen.connect(func(a: int) -> void: chosen.append(a))
	var reasons: Array[String] = []
	p.refused.connect(func(r: String) -> void: reasons.append(r))

	var clear: Button = p.button_for(A.CLEAR_MINE)
	assert_false(clear.disabled, "недоступна кнопка лишається натискною — на телефоні нема наведення")
	assert_eq(clear.theme_type_variation, EngineerPanel.UNAVAILABLE_VARIATION, "приглушена: dim, 500")
	clear.pressed.emit()
	assert_eq(reasons, [EngineerCommand.action_status(_service.state, e.id, A.CLEAR_MINE)["reason"]] as Array[String],
		"причина — ключ із core/, текст покаже тост")
	assert_eq(chosen, [] as Array[int], "недоступна верба нічого не озброює")

	var lay: Button = p.button_for(A.LAY_MINE)
	assert_eq(lay.theme_type_variation, EngineerPanel.AVAILABLE_VARIATION)
	lay.pressed.emit()
	assert_eq(chosen, [A.LAY_MINE] as Array[int])
	assert_eq(reasons.size(), 1, "доступна верба причини не дає")


func test_engineer_panel_relabels_on_locale_change() -> void:
	var e: Unit = _engineer()
	var p: EngineerPanel = _panel()
	p.show_for(_service.state, e)
	TranslationServer.set_locale("uk")
	await get_tree().process_frame
	assert_eq(p.button_for(A.LAY_MINE).text, "Поставити міну")
	TranslationServer.set_locale("en")
	await get_tree().process_frame
	assert_eq(p.button_for(A.LAY_MINE).text, EN_LABELS[0])


func _hud_cases() -> Array:
	var out: Array = []
	for size: Vector2i in LayoutProbe.SIZES:
		for locale: String in ["en", "uk"]:
			out.append([size, locale])
	return out


func test_panel_fits_phone_without_overlapping_chrome(p = use_parameters(_hud_cases())) -> void:
	TranslationServer.set_locale(p[1])
	var size: Vector2i = p[0]
	var hud: Hud = await LayoutProbe.mount(self, HudScene, size)
	var e: Unit = _engineer()
	hud.bind(_service.state)
	hud.show_selection(e)
	await LayoutProbe.settle(self)
	var panel: EngineerPanel = hud.get_node("%EngineerPanel")
	var where: String = "%s %s" % p
	assert_true(panel.is_visible_in_tree(), where)
	assert_eq(panel.size, Vector2(269, 148), where)
	assert_eq(LayoutProbe.overflowing(hud, size), [] as Array[String], where)
	assert_eq(LayoutProbe.small_targets(hud), [] as Array[String], where)
	var rect := Rect2(panel.position, panel.size)
	assert_eq(rect.end, Vector2(size.x - 24.0, size.y - 12.0), "%s: плита внизу праворуч" % where)
	for n: String in ["%Chip", "%PauseButton", "%EndTurnButton"]:
		assert_false(rect.intersects((hud.get_node(n) as Control).get_global_rect()), "%s: %s" % [where, n])
	if size == LayoutProbe.PHONE_SMALL:
		assert_eq(rect.position.y, 200.0, "800 × 360: верх плити 200, сітка займає 148 із 360")


func test_armed_panel_collapses_to_strip_with_cancel() -> void:
	var e: Unit = _engineer()
	var p: EngineerPanel = _panel()
	p.show_for(_service.state, e)
	var cancels: Array[int] = [0]
	p.cancel_pressed.connect(func() -> void: cancels[0] += 1)
	p.button_for(A.LAY_MINE).pressed.emit()
	p.set_armed(true)
	assert_false(p.plate().visible)
	assert_true(p.strip().visible)
	assert_eq(p.strip().title_label.text, "Lay mine")
	var cancel: Button = p.strip().cancel_button
	assert_true(cancel.custom_minimum_size.y >= 48.0 and cancel.custom_minimum_size.x >= 48.0)
	cancel.pressed.emit()
	assert_eq(cancels[0], 1)
	p.set_armed(false)
	assert_true(p.plate().visible)
	assert_false(p.strip().visible)


func test_armed_verb_shows_the_same_hint_and_its_own_name() -> void:
	var p: EngineerPanel = _panel()
	p.show_for(_service.state, _engineer())
	for i in VERBS.size():
		p._chosen = VERBS[i]  # верба вибрана; доступність тут не важить
		p.set_armed(true)
		assert_eq(p.strip().title_label.text, EN_LABELS[i])
		assert_eq(p.strip().hint_label.text, "Tap a tile", "одна підказка на всі верби")
		assert_eq(p.active_size().x, HudDocking.CLUSTER_W, "смужка спільної ширини")
		assert_eq(p.active_size().x, 252.0, "спільна ширина — 252 dp")
		p.set_armed(false)


func test_strip_armed_cell_swallows_taps_and_has_no_action() -> void:
	var p: EngineerPanel = _panel()
	p.show_for(_service.state, _engineer())
	p.set_armed(true)
	assert_eq(p.strip().armed_cell.mouse_filter, Control.MOUSE_FILTER_STOP, "тап по клітинці не доходить до дошки")
	assert_eq(p.strip().cancel_button.get_signal_connection_list("pressed").size(), 1, "єдина дія смужки — «Скасувати»")
