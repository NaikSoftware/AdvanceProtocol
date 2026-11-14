class_name PauseMenu
extends Control
## Меню паузи. Оверлей поверх бою. §1.2/гейт передачі:
## пауза НЕ сміє показувати нічого, що належить неактивному гравцеві — тому це
## непрозорий scrim на всю дошку з плитою карти (та сама, що на гейті, без юнітів),
## а не напівпрозора панель збоку.
##
## Кнопки лише повідомляють сигналами; що робити — вирішує сцена бою, яка
## володіє станом (збереження, оверлей налаштувань). «Здатися» спершу
## підміняє кнопки панеллю підтвердження в тій самій картці (без ОС-діалогів);
## surrender_requested летить лише з «Так».

signal settings_requested
signal save_quit_requested
signal surrender_requested

const _GROUND_LC_KEYS: Dictionary = {
	Terrain.GroundState.DRY: "ground_dry_lc",
	Terrain.GroundState.MUD: "ground_mud_lc",
	Terrain.GroundState.FROZEN: "ground_frozen_lc",
}

var _map_name_key: String = ""
var _ground_state: int = Terrain.GroundState.DRY

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


## Карта і ґрунт незмінні протягом матчу: сцена бою задає їх раз.
func set_context(map_path: String, name_key: String, ground_state: int) -> void:
	%Plate.texture = HandoverGate.plate_for(map_path)
	_map_name_key = name_key
	_ground_state = ground_state


## Відкриває паузу; turn — номер кола (BattleState.turn_number) для інфо-рядка.
func open(turn: int) -> void:
	%MapCaption.text = tr("hud_map").to_upper()
	%MapValue.text = tr(_map_name_key) if _map_name_key != "" else "-"
	%GroundIcon.texture = HandoverGate.ground_icon(_ground_state)
	%GroundIcon.modulate = HudKit.BONE
	%TurnCaption.text = tr("hud_turn")
	%TurnValue.text = str(turn)
	# «Ґрунт: %s» — значення виділене окремим підписом, тож беремо лише початок рядка.
	%GroundCaption.text = tr("hud_ground_line").get_slice(":", 0) + ":"
	%GroundValue.text = tr(_GROUND_LC_KEYS[_ground_state])
	show()


func _set_confirming(on: bool) -> void:
	for b: Control in [%ResumeButton, %SettingsButton, %SaveQuitButton, %SurrenderButton, %Divider, %InfoLine]:
		b.visible = not on
	%ConfirmBox.visible = on
	# Помилка збереження стосується лише того відкриття паузи, у якому сталася.
	%ErrorLabel.visible = false


## Збій збереження: лишаємось у паузі й кажемо про це (ключ перекладу).
func show_error(key: String) -> void:
	%ErrorLabel.text = key
	%ErrorLabel.visible = true


func _on_resume_pressed() -> void:
	visible = false
