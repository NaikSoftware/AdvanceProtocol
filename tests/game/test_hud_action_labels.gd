extends GutTest
## Основна кнопка називає дію, що чекає підтвердження: слово й значок слідують за прев'ю.
## Прев'ю тут синтетичні: HUD лише підставляє слова до полів, які дає core/.

const HudScene := preload("res://game/ui/hud.tscn")
const ICONS := "res://assets/ui/icons/"
const LOCALES: Array[String] = ["uk", "en"]

var hud: Hud


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


func _mark(root: Node) -> Texture2D:
	return ((root.get_node("%ConfirmButton") as Button).get_meta(&"group_mark") as TextureRect).texture


func _cases() -> Array:
	return [
		[_shot(), "hud_fire", "fire.svg"],
		[_drone(), "hud_strike", "drone.svg"],
		[_move(), "hud_move", "move.svg"],
		[_engineer(EngineerCommand.Action.REPAIR_UNIT), "hud_repair", "repair_unit.svg"],
		[_engineer(EngineerCommand.Action.CLEAR_MINE), "eng_clear_mine", "mine_clear.svg"],
		[_engineer(EngineerCommand.Action.REPAIR_BRIDGE), "eng_repair_bridge", "bridge_repair.svg"],
		[_engineer(EngineerCommand.Action.DEMOLISH_BRIDGE), "eng_demolish_bridge", "bridge_demolish.svg"],
	]


func test_confirm_names_the_pending_action_in_both_locales() -> void:
	for locale: String in LOCALES:
		TranslationServer.set_locale(locale)
		for c: Array in _cases():
			hud.show_preview(c[0])
			assert_eq(_word(hud).text, tr(c[1]), "%s %s" % [locale, c[1]])
			assert_eq(_mark(hud).resource_path, ICONS + c[2], "%s %s" % [locale, c[1]])
	TranslationServer.set_locale("uk")
	hud.show_preview(_shot())
	assert_eq(_word(hud).text, "Вогонь")
	TranslationServer.set_locale("en")
	assert_eq(tr("hud_strike"), "Strike")


func test_confirm_label_follows_a_locale_change() -> void:
	hud.show_preview(_shot())
	TranslationServer.set_locale("en")
	hud.notification(Node.NOTIFICATION_TRANSLATION_CHANGED)
	assert_eq(_word(hud).text, "Fire")


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
		assert_eq(word.text, tr(c[1]), where)
		assert_true(button.get_global_rect().grow(-6.0).encloses(word.get_global_rect()), "підпис не виходить за кнопку: " + where)
		assert_lte(word.get_minimum_size().x, word.size.x, "підпис не стиснуто: " + where)
		assert_eq(LayoutProbe.overflowing(root, p[0]), [] as Array[String], where)


func _fit_cases() -> Array:
	var out: Array = []
	for size: Vector2i in LayoutProbe.SIZES:
		for locale: String in LOCALES:
			out.append([size, locale])
	return out
