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
	menu.set_context("", "map_river", Terrain.GroundState.DRY)
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
	menu.set_context("", "", Terrain.GroundState.DRY)
	menu.open(1)
	assert_eq((menu.get_node("%MapValue") as Label).text, "-")
