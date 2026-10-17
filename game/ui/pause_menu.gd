class_name PauseMenu
extends Control
## Task 3.5 (скелет): меню паузи. Оверлей поверх бою. §1.2/гейт передачі:
## пауза НЕ сміє показувати нічого, що належить неактивному гравцеві — тому це
## непрозорий scrim на всю дошку, а не напівпрозора панель збоку.
##
## Кнопки лише повідомляють сигналами; що робити — вирішує сцена бою, яка
## володіє станом (збереження, оверлей налаштувань). «Здатися» спершу
## підміняє кнопки панеллю підтвердження в тій самій картці (без ОС-діалогів);
## surrender_requested летить лише з «Так».

signal resume_requested
signal settings_requested
signal save_quit_requested
signal surrender_requested

@onready var _resume_button: Button = %ResumeButton


func _ready() -> void:
	_resume_button.pressed.connect(_on_resume_pressed)
	%SaveQuitButton.pressed.connect(save_quit_requested.emit)
	%SettingsButton.pressed.connect(settings_requested.emit)
	%SurrenderButton.pressed.connect(_set_confirming.bind(true))
	%ConfirmCancelButton.pressed.connect(_set_confirming.bind(false))
	%ConfirmYesButton.pressed.connect(surrender_requested.emit)
	# Повторне відкриття паузи завжди починається зі звичайних кнопок.
	visibility_changed.connect(_set_confirming.bind(false))


func _set_confirming(on: bool) -> void:
	for b: Control in [%ResumeButton, %SettingsButton, %SaveQuitButton, %SurrenderButton]:
		b.visible = not on
	%ConfirmBox.visible = on


## Збій збереження: лишаємось у паузі й кажемо про це (ключ перекладу).
func show_error(key: String) -> void:
	%ErrorLabel.text = key
	%ErrorLabel.visible = true


func _on_resume_pressed() -> void:
	%ErrorLabel.visible = false
	visible = false
	resume_requested.emit()
