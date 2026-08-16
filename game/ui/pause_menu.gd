class_name PauseMenu
extends Control
## Task 3.5 (скелет): меню паузи. Оверлей поверх бою. §1.2/гейт передачі:
## пауза НЕ сміє показувати нічого, що належить неактивному гравцеві — тому це
## непрозорий scrim на всю дошку, а не напівпрозора панель збоку.
##
## Скелет будує оверлей і його кнопки; вбудова в battle_screen (кнопка паузи в
## HUD, інстанс цього оверлея, фактичне збереження через
## BattleSerializer.save_to) — крок інтеграції Task 3.5.

signal resume_requested

@onready var _resume_button: Button = %ResumeButton


func _ready() -> void:
	_resume_button.pressed.connect(_on_resume_pressed)
	%SaveQuitButton.pressed.connect(SceneRouter.goto_main_menu)
	%SettingsButton.pressed.connect(SceneRouter.goto_settings)
	%SurrenderButton.pressed.connect(SceneRouter.goto_results)


func _on_resume_pressed() -> void:
	visible = false
	resume_requested.emit()
