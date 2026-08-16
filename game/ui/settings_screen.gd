class_name SettingsScreen
extends Control
## Task 3.4 (скелет): екран налаштувань. Мова застосовується миттєво
## (TranslationServer.set_locale — Control-и самі перекладаються на зміну
## локалі). Гучність і якість поки лише візуальні; збереження через
## SettingsService (user://settings.cfg) — крок логіки Task 3.4, не цей скелет.

@onready var _uk_button: Button = %LangUk
@onready var _en_button: Button = %LangEn


func _ready() -> void:
	_sync_language_buttons()
	_uk_button.pressed.connect(_on_language_pressed.bind("uk"))
	_en_button.pressed.connect(_on_language_pressed.bind("en"))
	%BackButton.pressed.connect(SceneRouter.goto_main_menu)


func _sync_language_buttons() -> void:
	var locale: String = TranslationServer.get_locale()
	_uk_button.button_pressed = locale.begins_with("uk")
	_en_button.button_pressed = locale.begins_with("en")


func _on_language_pressed(locale: String) -> void:
	TranslationServer.set_locale(locale)
	_sync_language_buttons()
