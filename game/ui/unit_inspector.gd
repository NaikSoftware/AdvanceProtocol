class_name UnitInspector
extends PanelContainer
## Task 2.8: стати вибраного юніта і три числа броні. Усе, що тут показано,
## береться з UnitTypes (§3.6 — джерело істини для ростера) або з самого юніта;
## жодне число тут не виводиться й не переоцінюється — вигляд не рахує наслідків
## (§6 CLAUDE.md).
##
## §3.4: гравець мусить бачити, у який сектор піде постріл, ДО того як натисне
## «підтвердити», — тому highlight_sector() існує окремо від show_unit() і
## викликається з прев'ю, а не зі стану бою.

## Ключі перекладу секторів живуть тут, а не в HUD: підписи колонок броні і
## рядок «сектор» у прев'ю мусять називати той самий сектор тим самим словом,
## інакше гравець читає два різні тексти про одне влучання.
const SECTOR_KEYS: Dictionary = {
	UnitTypes.ArmourSector.FRONT: "hud_sector_front",
	UnitTypes.ArmourSector.SIDE: "hud_sector_side",
	UnitTypes.ArmourSector.REAR: "hud_sector_rear",
}

## Мапа класів у ключі перекладу тримається у вигляді, а не в core/: core/ не
## знає, що існує екран (§6), тож назвати клас словом — робота цього файлу.
const CLASS_KEYS: Dictionary = {
	UnitTypes.UnitClass.INFANTRY: "unit_class_infantry",
	UnitTypes.UnitClass.LIGHT_VEHICLE: "unit_class_light_vehicle",
	UnitTypes.UnitClass.TANK: "unit_class_tank",
	UnitTypes.UnitClass.ARTILLERY: "unit_class_artillery",
	UnitTypes.UnitClass.ENGINEER: "unit_class_engineer",
}

## Немає підсвіченого сектора. Не 0: FRONT — це теж сектор, і сплутати «фронт»
## з «нічого не вибрано» означало б показувати влучання в лоб на порожньому
## екрані.
const NO_SECTOR: int = -1

const MODULATE_NEUTRAL: Color = Color.WHITE
## Сектор, у який піде постріл, підсвічений теплим — той самий сигнал «сюди
## прилетить», що й у прицілі; нейтральні лишаються білими, щоб підсвічений
## читався з одного погляду на телефоні (§1.5).
const MODULATE_HIT: Color = Color("ff7a4a")

var _highlighted_sector: int = NO_SECTOR

@onready var _name_label: Label = %StatName
@onready var _class_label: Label = %StatClass
@onready var _hp_label: Label = %StatHp
@onready var _ap_label: Label = %StatAp
@onready var _attack_label: Label = %StatAttack
@onready var _range_label: Label = %StatRange
@onready var _vision_label: Label = %StatVision
## Індекс у масиві — це значення UnitTypes.ArmourSector, той самий порядок, що
## й у "armour" ростера, тож сектор із прев'ю індексує і число, і підсвітку без
## жодної проміжної мапи.
@onready var _armour_labels: Array[Label] = [
	%ArmourFront as Label, %ArmourSide as Label, %ArmourRear as Label,
]


func _ready() -> void:
	clear()


func show_unit(unit: Unit) -> void:
	var t: Dictionary = unit.type()
	_name_label.text = tr(t["name_key"])
	_class_label.text = tr(CLASS_KEYS[unit.unit_class()])
	# HP і AP — поточні проти максимуму: без другого числа «210» нічого не
	# каже про те, наскільки юніт побитий.
	_hp_label.text = "%d/%d" % [unit.hp, unit.max_hp()]
	_ap_label.text = "%d/%d" % [unit.ap, unit.max_ap()]
	_attack_label.text = str(int(t["attack"]))
	_range_label.text = str(int(t["attack_range"]))
	_vision_label.text = str(int(t["vision"]))
	var armour: Array = t["armour"]
	for sector in _armour_labels.size():
		_armour_labels[sector].text = str(int(armour[sector]))
	visible = true


func clear() -> void:
	visible = false
	highlight_sector(NO_SECTOR)


## sector — значення UnitTypes.ArmourSector або NO_SECTOR. Підсвічений завжди
## рівно один: попередній гаситься тут же, тож два сектори одночасно не
## показуються навіть після кількох прев'ю поспіль.
func highlight_sector(sector: int) -> void:
	_highlighted_sector = sector
	for i in _armour_labels.size():
		_armour_labels[i].modulate = MODULATE_HIT if i == sector else MODULATE_NEUTRAL


func highlighted_sector() -> int:
	return _highlighted_sector
