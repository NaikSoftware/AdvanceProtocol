class_name PauseMenu
extends Control
## Task 3.5 (скелет): меню паузи. Оверлей поверх бою. §1.2/гейт передачі:
## пауза НЕ сміє показувати нічого, що належить неактивному гравцеві — тому це
## непрозорий scrim на всю дошку, а не напівпрозора панель збоку.
##
## Кнопки лише повідомляють сигналами; що робити — вирішує сцена бою, яка
## володіє станом (збереження, оверлей налаштувань). «Здатися» поки лишається
## як було — з'єднається, коли в core/ зʼявиться команда капітуляції.

signal resume_requested
signal settings_requested
signal save_quit_requested

@onready var _resume_button: Button = %ResumeButton


func _ready() -> void:
	_resume_button.pressed.connect(_on_resume_pressed)
	%SaveQuitButton.pressed.connect(save_quit_requested.emit)
	%SettingsButton.pressed.connect(settings_requested.emit)
	%SurrenderButton.pressed.connect(SceneRouter.goto_results)


func _on_resume_pressed() -> void:
	visible = false
	resume_requested.emit()
