class_name SettingsScreen
extends Control
## Task 3.4: екран налаштувань. Мова застосовується миттєво (Control-и самі
## перекладаються на зміну локалі); кожна зміна одразу пишеться в
## SettingsService → user://settings.cfg, окремої кнопки «Зберегти» немає.
##
## overlay = true — екран відкритий поверх бою з паузи: «Назад» лише закриває
## його, а не веде в меню, тож матч, що чекає під ним, не губиться.

var overlay: bool = false
## Запис налаштувань; змінна, щоб тест не писав у справжній user://settings.cfg.
## Є незбережена зміна повзунка (клавіатура/геймпад не дають drag_ended).
var _dirty: bool = false
var _persist: Callable = func() -> void: SettingsService.save()

@onready var _uk_button: Button = %LangUk
@onready var _en_button: Button = %LangEn
@onready var _music: HSlider = %MusicSlider
@onready var _sfx: HSlider = %SfxSlider
@onready var _quality: Array[Button] = [%QLow, %QMed, %QHigh]


func _ready() -> void:
	_sync_from_service()
	_uk_button.pressed.connect(_on_language_pressed.bind("uk"))
	_en_button.pressed.connect(_on_language_pressed.bind("en"))
	_music.value_changed.connect(func(v: float) -> void:
		_dirty = true
		SettingsService.music_volume = v)
	# Диск — лише по відпусканню: value_changed іде на кожен піксель драгу.
	_music.drag_ended.connect(_on_slider_released)
	_sfx.value_changed.connect(func(v: float) -> void:
		_dirty = true
		SettingsService.sfx_volume = v)
	_sfx.drag_ended.connect(_on_slider_released)
	for i in _quality.size():
		_quality[i].pressed.connect(_on_quality_pressed.bind(i))
	%BackButton.pressed.connect(_on_back_pressed)


func _sync_from_service() -> void:
	_music.set_value_no_signal(SettingsService.music_volume)
	_sfx.set_value_no_signal(SettingsService.sfx_volume)
	_quality[SettingsService.quality].button_pressed = true
	_sync_language_buttons()


func _sync_language_buttons() -> void:
	var locale: String = TranslationServer.get_locale()
	_uk_button.button_pressed = locale.begins_with("uk")
	_en_button.button_pressed = locale.begins_with("en")


func _on_language_pressed(locale: String) -> void:
	SettingsService.locale = locale
	SettingsService.apply_locale()
	SettingsService.save()
	_sync_language_buttons()


func _on_quality_pressed(level: int) -> void:
	SettingsService.quality = level
	SettingsService.save()


func _on_slider_released(_changed: bool) -> void:
	if _dirty:
		_dirty = false
		_persist.call()


func _on_back_pressed() -> void:
	# Клавіатурна зміна повзунка не дає drag_ended — зберігаємо при виході,
	# але лише якщо є що зберігати (зайвий запис на кожен вихід не потрібен).
	if _dirty:
		_persist.call()
	if overlay:
		queue_free()
	else:
		SceneRouter.goto_main_menu()
