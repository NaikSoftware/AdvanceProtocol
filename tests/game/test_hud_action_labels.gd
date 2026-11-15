extends GutTest
## Основна кнопка називає дію, що чекає підтвердження: слово й значок слідують за прев'ю.
## Прев'ю тут синтетичні: HUD лише підставляє слова до полів, які дає core/.

const HudScene := preload("res://game/ui/hud.tscn")
const ICONS := "res://assets/ui/icons/"
const LOCALES: Array[String] = ["uk", "en"]

var hud: Hud
var _orig_locale: String


func before_all() -> void:
	_orig_locale = TranslationServer.get_locale()


func after_each() -> void:
	TranslationServer.set_locale(_orig_locale)


func before_each() -> void:
	TranslationServer.set_locale("uk")
	hud = HudScene.instantiate()
	add_child_autofree(hud)


func _shot(extra: Dictionary = {}) -> Dictionary:
	var p: Dictionary = {"type": InputController.ActionType.SHOT, "unit_id": 1, "target_id": 2, "sector": 1,
		"min": 120, "max": 180, "armour_ignored": false, "in_cover": false}
	p.merge(extra, true)
	return p


func _drone(extra: Dictionary = {}) -> Dictionary:
	var p: Dictionary = {"type": InputController.ActionType.DRONE, "unit_id": 1, "target_id": 2,
		"min": 120, "max": 180}
	p.merge(extra, true)
	return p


func _engineer(action: int) -> Dictionary:
	var p: Dictionary = {"type": InputController.ActionType.ENGINEER, "unit_id": 1, "action": action,
		"target": Vector2i(4, 3)}
	if action == EngineerCommand.Action.REPAIR_UNIT:
		p["heal_min"] = 20
		p["heal_max"] = 43
	return p


func _move() -> Dictionary:
	return {"type": InputController.ActionType.MOVE, "unit_id": 1, "target": Vector2i(4, 5),
		"path": [Vector2i(4, 5)] as Array[Vector2i], "ap_left": 28}


func _word(root: Node) -> Label:
	return (root.get_node("%ConfirmButton") as Button).get_meta(&"group_word") as Label


## Ширина того, що Label справді малює: мінімальний розмір слідує за авто-перекладом.
func _text_w(word: Label, text: String) -> float:
	return word.get_theme_font(&"font").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, word.get_theme_font_size(&"font_size")).x


func _mark(root: Node) -> Texture2D:
	return ((root.get_node("%ConfirmButton") as Button).get_meta(&"group_mark") as TextureRect).texture


func _cases() -> Array:
	return [
		[_shot(), "hud_fire", "btn_fire.svg"],
		[_drone(), "hud_strike", "btn_drone.svg"],
		[_move(), "hud_move", "btn_move.svg"],
		[_engineer(EngineerCommand.Action.REPAIR_UNIT), "hud_repair", "btn_repair_unit.svg"],
		[_engineer(EngineerCommand.Action.CLEAR_MINE), "eng_clear_mine", "btn_mine_clear.svg"],
		[_engineer(EngineerCommand.Action.REPAIR_BRIDGE), "eng_repair_bridge", "btn_bridge_repair.svg"],
		[_engineer(EngineerCommand.Action.DEMOLISH_BRIDGE), "eng_demolish_bridge", "btn_bridge_demolish.svg"],
	]


func test_confirm_names_the_pending_action_in_both_locales() -> void:
	for locale: String in LOCALES:
		TranslationServer.set_locale(locale)
		for c: Array in _cases():
			hud.show_preview(c[0])
			assert_eq(_word(hud).text, c[1], "ключ у Label: %s %s" % [locale, c[1]])
			assert_eq(_mark(hud).resource_path, ICONS + c[2], "%s %s" % [locale, c[1]])
			var mark := (hud.get_node("%ConfirmButton") as Button).get_meta(&"group_mark") as TextureRect
			assert_eq(mark.custom_minimum_size, Vector2(16, 16), "один бокс значка: " + c[1])
			assert_eq((mark.get_parent() as HBoxContainer).get_theme_constant(&"separation"), 6, "один проміжок значок → слово: " + c[1])
	TranslationServer.set_locale("uk")
	hud.show_preview(_shot())
	assert_eq(_word(hud).get_minimum_size().x, _text_w(_word(hud), "Вогонь"), "Label малює переклад")
	TranslationServer.set_locale("en")
	assert_eq(tr("hud_strike"), "Strike")


func test_confirm_label_follows_a_locale_change() -> void:
	hud.show_preview(_shot())
	TranslationServer.set_locale("en")
	hud.notification(Node.NOTIFICATION_TRANSLATION_CHANGED)
	assert_eq(_word(hud).get_minimum_size().x, _text_w(_word(hud), "Fire"), "Label малює переклад")


func test_long_labels_fit_the_primary_button_at_every_size(p = use_parameters(_fit_cases())) -> void:
	TranslationServer.set_locale(p[1])
	var root: Control = await LayoutProbe.mount(self, HudScene, p[0])
	var h := root as Hud
	for c: Array in _cases():
		h.show_preview(c[0])
		await LayoutProbe.settle(self)
		var button := root.get_node("%ConfirmButton") as Button
		var word: Label = _word(root)
		var where: String = "%s %s %s" % [p[0], p[1], c[1]]
		assert_eq(word.text, c[1], where)
		assert_eq(button.size.x, 136.0, "довгий підпис не розпирає кнопку: " + where)
		_assert_clear_inside_border(button, where)
		assert_eq(LayoutProbe.overflowing(root, p[0]), [] as Array[String], where)


## «Скасувати» 104 dp: значок × і слово лишають ≥ 7 dp повітря від внутрішнього краю рамки.
func test_cancel_keeps_clearance_inside_its_border(p = use_parameters(_fit_cases())) -> void:
	TranslationServer.set_locale(p[1])
	var root: Control = await LayoutProbe.mount(self, HudScene, p[0])
	(root as Hud).show_preview(_shot())
	await LayoutProbe.settle(self)
	var button := root.get_node("%CancelButton") as Button
	var where: String = "%s %s" % [p[0], p[1]]
	assert_eq(button.size.x, 104.0, where)
	_assert_clear_inside_border(button, where)
	_assert_clear_inside_border(root.get_node("%EndTurnButton") as Button, "End turn " + where)


## «Скасувати» смужки озброєння стоїть на тих самих пікселях, що й «Скасувати» ряду дій.
func test_armed_strip_cancel_matches_the_row_cancel(p = use_parameters(_fit_cases())) -> void:
	TranslationServer.set_locale(p[1])
	var root: Control = await LayoutProbe.mount(self, HudScene, p[0])
	var h := root as Hud
	h.show_preview(_shot())
	await LayoutProbe.settle(self)
	var row_btn := root.get_node("%CancelButton") as Button
	var strip := root.get_node("%DroneStrip") as ArmedStrip
	strip.visible = true
	await LayoutProbe.settle(self)
	var where: String = "%s %s" % [p[0], p[1]]
	var row_off: Vector2 = row_btn.get_meta(&"group_mark").get_global_rect().position - row_btn.get_global_rect().position
	var strip_off: Vector2 = strip.cancel_button.get_meta(&"group_mark").get_global_rect().position - strip.cancel_button.get_global_rect().position
	assert_eq(strip.cancel_button.size, row_btn.size, "той самий прямокутник: " + where)
	assert_eq(strip_off, row_off, "× на тому самому місці: " + where)
	var row_w: Vector2 = row_btn.get_meta(&"group_word").get_global_rect().position - row_btn.get_global_rect().position
	var strip_w: Vector2 = strip.cancel_button.get_meta(&"group_word").get_global_rect().position - strip.cancel_button.get_global_rect().position
	assert_eq(strip_w, row_w, "слово на тому самому місці: " + where)


## Повітря від внутрішнього краю рамки до значка й до підпису, з обох боків, і по вертикалі — у межах
## малюнка 40 dp, а не всієї тап-цілі 48: нижні 8 dp тап-цілі плити не мають.
func _assert_clear_inside_border(button: Button, where: String) -> void:
	var box: StyleBox = button.get_theme_stylebox(&"normal")
	var border: float = float((box as StyleBoxFlat).border_width_left) if box is StyleBoxFlat else 0.0
	var visual: Rect2 = button.get_global_rect().grow_individual(box.get_expand_margin(SIDE_LEFT), box.get_expand_margin(SIDE_TOP),
		box.get_expand_margin(SIDE_RIGHT), box.get_expand_margin(SIDE_BOTTOM))
	assert_eq(visual.size.y, 40.0, "малюнок 40 dp: " + where)
	var inner: Rect2 = visual.grow(-border)
	var mark := button.get_meta(&"group_mark") as TextureRect
	var word := button.get_meta(&"group_word") as Label
	assert_eq(mark.size, Vector2(16, 16), "значок 16 dp: " + where)
	assert_eq(word.position.x - mark.get_rect().end.x, 6.0, "проміжок значок → слово 6 dp: " + where)
	# Label авто-перекладає ключ і має ширину свого тексту: його прямокутник — те, що він малює.
	assert_eq(word.size.x, word.get_minimum_size().x, "підпис не обрізаний: " + where)
	assert_gte(mark.get_global_rect().position.x - inner.position.x, 7.0, "значок → рамка ≥ 7 dp: " + where)
	assert_gte(inner.end.x - word.get_global_rect().end.x, 7.0, "підпис → рамка ≥ 7 dp: " + where)
	# CenterContainer кладе групу на цілий dp, тож центр може відставати на пів dp.
	assert_almost_eq(word.get_global_rect().get_center().y, visual.get_center().y, 0.5, "підпис по центру малюнка: " + where)
	assert_gte(word.get_theme_font_size(&"font_size"), 11, where)


func _fit_cases() -> Array:
	var out: Array = []
	for size: Vector2i in LayoutProbe.SIZES:
		for locale: String in LOCALES:
			out.append([size, locale])
	return out
