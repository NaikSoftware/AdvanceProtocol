extends GutTest
## Підписи паузи вже перекладені, тож після зміни мови (налаштування поверх паузи) вони пишуться наново.

const PauseScene := preload("res://game/ui/pause_menu.tscn")

var _orig_locale: String


func before_each() -> void:
	_orig_locale = TranslationServer.get_locale()


func after_each() -> void:
	TranslationServer.set_locale(_orig_locale)


func test_info_lines_follow_a_language_change_while_open() -> void:
	TranslationServer.set_locale("uk")
	var menu: PauseMenu = PauseScene.instantiate()
	add_child_autofree(menu)
	menu.set_context("", "map_river")
	menu.open(7)
	assert_eq((menu.get_node("%MapValue") as Label).text, "Річка")

	TranslationServer.set_locale("en")
	menu.notification(Node.NOTIFICATION_TRANSLATION_CHANGED)

	assert_eq((menu.get_node("%MapValue") as Label).text, "River")
	assert_eq((menu.get_node("%TurnValue") as Label).text, "7", "номер кола переживає перепис")
	assert_eq((menu.get_node("%MapCaption") as Label).text, "MAP")


func test_empty_map_shows_a_dash() -> void:
	var menu: PauseMenu = PauseScene.instantiate()
	add_child_autofree(menu)
	menu.set_context("", "")
	menu.open(1)
	assert_eq((menu.get_node("%MapValue") as Label).text, "-")


func test_pause_shows_no_ground_state() -> void:
	for lang in ["uk", "en"]:
		TranslationServer.set_locale(lang)
		var menu: PauseMenu = PauseScene.instantiate()
		add_child_autofree(menu)
		menu.set_context("", "map_river")
		menu.open(2)
		assert_eq(_ground_text_or_icon(menu), [] as Array[String], "пауза, мова %s" % lang)
		assert_eq((menu.get_node("%TurnValue") as Label).text, "2")


## Стан ґрунту не показується ніде в інтерфейсі: ні вузла, ні підпису, ні значка.
static func _ground_text_or_icon(root: Node) -> Array[String]:
	var found: Array[String] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if "ground" in String(n.name).to_lower():
			found.append(String(n.name))
		var text: String = (n as Label).text if n is Label else ""
		if n is Button:
			text = (n as Button).text
		for w in ["ґрунт", "ground", "багно", "мерзлота", "mud", "frozen"]:
			if w in text.to_lower():
				found.append("%s: %s" % [n.name, text])
		if n is TextureRect and (n as TextureRect).texture != null and "ground" in (n as TextureRect).texture.resource_path:
			found.append("%s: %s" % [n.name, (n as TextureRect).texture.resource_path])
	return found
