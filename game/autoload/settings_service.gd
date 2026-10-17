extends Node
## Task 3.4: налаштування гравця у user://settings.cfg (ConfigFile).
## Гучність і якість лише зберігаються — споживачі з'являться у Фазі 5.

const PATH: String = "user://settings.cfg"
const QUALITY_MAX: int = 2

var locale: String = "uk"
var music_volume: float = 0.8
var sfx_volume: float = 0.9
## 0 низька / 1 середня / 2 висока.
var quality: int = 1


func _ready() -> void:
	# Немає файлу — лишається мова, з якою стартував двигун, а не жорсткий "uk".
	locale = TranslationServer.get_locale().substr(0, 2)
	self.load()  # голе load() — глобальна функція двигуна


func save(path: String = PATH) -> Error:
	var cfg := ConfigFile.new()
	cfg.set_value("general", "locale", locale)
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.set_value("graphics", "quality", quality)
	return cfg.save(path)


## Відсутній або зіпсований файл — не помилка: лишаються типові значення.
func load(path: String = PATH) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) == OK:
		locale = str(cfg.get_value("general", "locale", locale))
		music_volume = clampf(float(cfg.get_value("audio", "music_volume", music_volume)), 0.0, 1.0)
		sfx_volume = clampf(float(cfg.get_value("audio", "sfx_volume", sfx_volume)), 0.0, 1.0)
		quality = clampi(int(cfg.get_value("graphics", "quality", quality)), 0, QUALITY_MAX)
	apply_locale()


func apply_locale() -> void:
	TranslationServer.set_locale(locale)
