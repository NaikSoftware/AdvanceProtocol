class_name DroneButton
extends Button
## Task 10: дроновий удар (§3.9) — окрема дія поруч із «Підтвердити», а не
## перемикач режиму пострілу. Видима лише для типу з дронами; текст — залишок.
## Без дронів кнопка лишається натискною: тап — єдиний спосіб на телефоні
## дізнатися причину відмови (та сама логіка, що й сірі верби інженера).

var _unit: Unit = null


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_relabel()


## null або тип без дронів — кнопку сховано.
func show_for(unit: Unit) -> void:
	_unit = unit if unit != null and int(unit.type()["drones"]) > 0 else null
	visible = _unit != null
	_relabel()


func _relabel() -> void:
	if _unit != null:
		text = tr("hud_drone_strike") % _unit.drones_left
