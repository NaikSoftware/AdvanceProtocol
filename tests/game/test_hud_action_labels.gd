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
			assert_eq(((hud.get_node("%ConfirmButton") as Button).get_meta(&"group_mark") as TextureRect).custom_minimum_size, Vector2(18, 18), "один бокс значка: " + c[1])
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
		assert_true(button.get_global_rect().grow(-6.0).encloses(word.get_global_rect()), "підпис не виходить за кнопку: " + where)
		assert_eq(button.size.x, 147.0, "довгий підпис не розпирає кнопку: " + where)
		var border := button.get_theme_stylebox(&"normal") as StyleBoxFlat
		var min_clear: float = 7.0 + minf(border.border_width_left, border.border_width_right)
		var mark := button.get_meta(&"group_mark") as TextureRect
		var left: float = mark.get_global_rect().position.x - button.get_global_rect().position.x
		var right: float = button.get_global_rect().end.x - word.get_global_rect().end.x
		assert_gte(left, min_clear, "значок → рамка ≥ 7 dp всередині рамки: " + where)
		assert_gte(right, min_clear, "підпис → рамка ≥ 7 dp всередині рамки: " + where)
		assert_eq(LayoutProbe.overflowing(root, p[0]), [] as Array[String], where)


## «Скасувати» вужче за основну на 4 dp: значок × і слово лишають ≥ 7 dp повітря від внутрішнього краю рамки.
func test_cancel_keeps_clearance_inside_its_border(p = use_parameters(_fit_cases())) -> void:
	TranslationServer.set_locale(p[1])
	var root: Control = await LayoutProbe.mount(self, HudScene, p[0])
	(root as Hud).show_preview(_shot())
	await LayoutProbe.settle(self)
	var button := root.get_node("%CancelButton") as Button
	var edge: float = 1.0  # край плити «Скасувати» — 1 dp
	var mark := button.get_meta(&"group_mark") as TextureRect
	var word := button.get_meta(&"group_word") as Label
	var rect: Rect2 = button.get_global_rect()
	var where: String = "%s %s" % [p[0], p[1]]
	assert_eq(button.size.x, 122.0, where)
	assert_gte(mark.get_global_rect().position.x - rect.position.x - edge, 7.0, "× → рамка: " + where)
	assert_gte(rect.end.x - word.get_global_rect().end.x - edge, 7.0, "слово → рамка: " + where)


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


func _fit_cases() -> Array:
	var out: Array = []
	for size: Vector2i in LayoutProbe.SIZES:
		for locale: String in LOCALES:
			out.append([size, locale])
	return out
