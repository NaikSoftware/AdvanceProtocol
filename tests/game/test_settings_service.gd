extends GutTest
## Task 3.4: налаштування переживають збереження. Тестовий шлях, не справжній
## user://settings.cfg — прогін тестів не мусить чіпати налаштування гравця.

const SettingsScript := preload("res://game/autoload/settings_service.gd")
const TEST_PATH: String = "user://test_settings.cfg"

var _orig_locale: String = ""


func before_all() -> void:
	_orig_locale = TranslationServer.get_locale()


func after_all() -> void:
	TranslationServer.set_locale(_orig_locale)


func after_each() -> void:
	DirAccess.remove_absolute(TEST_PATH)


func test_round_trip_restores_every_field() -> void:
	var a: Node = autofree(SettingsScript.new())
	a.locale = "en"
	a.music_volume = 0.25
	a.sfx_volume = 0.5
	a.quality = 2
	assert_eq(a.save(TEST_PATH), OK)

	var b: Node = autofree(SettingsScript.new())
	b.load(TEST_PATH)

	assert_eq(b.locale, "en")
	assert_eq(b.music_volume, 0.25)
	assert_eq(b.sfx_volume, 0.5)
	assert_eq(b.quality, 2)


func test_load_without_file_keeps_defaults() -> void:
	var s: Node = autofree(SettingsScript.new())
	s.load(TEST_PATH)
	assert_eq(s.music_volume, 0.8)
	assert_eq(s.sfx_volume, 0.9)
	assert_eq(s.quality, 1)


func test_load_applies_locale_to_translation_server() -> void:
	var a: Node = autofree(SettingsScript.new())
	a.locale = "en"
	a.save(TEST_PATH)
	TranslationServer.set_locale("uk")

	var b: Node = autofree(SettingsScript.new())
	b.load(TEST_PATH)

	assert_eq(TranslationServer.get_locale(), "en")


func test_load_clamps_out_of_range_values() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "music_volume", 7.0)
	cfg.set_value("graphics", "quality", 99)
	cfg.save(TEST_PATH)

	var s: Node = autofree(SettingsScript.new())
	s.load(TEST_PATH)

	assert_eq(s.music_volume, 1.0)
	assert_eq(s.quality, 2)
