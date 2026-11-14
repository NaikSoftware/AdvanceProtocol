class_name HoldCard
extends PanelContainer
## Картка довгого натиску на будь-якого ВИДИМОГО юніта, свого чи ворожого (spec §2, «Hold card»):
## вкладка кольору власника на всю висоту · назва, клас, силует · атака / дальність / огляд ·
## глиф броні (нічого не світиться) і таблиця Лоб/Борт/Корма · ряд дронів · підпис «щонайменше».
## Усе — з UnitTypes і самого юніта. Ніколи AP: ворожий залишок дій прихований (overlays.md).
##
## Підпис «щонайменше» показується рівно тоді, коли Targeting.inspection повернув is_floor: тут
## ця умова не виводиться. Інженер не має зброї — під АТАКА й ДАЛЬНІСТЬ стоїть «—», а не 0 і 1,
## які видали б неіснуючу зброю.
##
## Ввід: уся картка ігнорує вказівник — вона з'являється під натиском і не має його перехоплювати.

const WIDTH: float = 226.0
const _ICON_DRONE: Texture2D = preload("res://assets/ui/icons/drone.svg")
const _DASH: String = "—"

var name_label: Label
var class_label: Label
var attack_value: Label
var range_value: Label
var vision_value: Label
var armour_glyph: ArmourGlyph
var armour_rows: Array[Label] = []
var armour_none_row: Control
var armour_table_row: Control
var drones_row: Control
var drone_pips: DronePips
var drone_count: Label
var floor_label: Label

var _tab: ColorRect
var _sil: TextureRect
var _floor_box: Control
## Підписи, що йдуть крізь tr(): [Label, ключ, ВЕЛИКИМИ?]. Перекладаються при кожному показі, бо мову
## можуть змінити між двома натисками.
var _words: Array[Array] = []


func _init() -> void:
	name = "HoldCard"
	theme_type_variation = &"HudPlateSolid"
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	custom_minimum_size = Vector2(WIDTH, 0.0)
	visible = false
	var shell := HBoxContainer.new()
	shell.add_theme_constant_override("separation", 0)
	add_child(shell)
	_tab = ColorRect.new()
	_tab.custom_minimum_size = Vector2(4.0, 0.0)
	shell.add_child(_tab)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 0)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shell.add_child(body)
	_build_head(body)
	body.add_child(_hair())
	_build_stats(body)
	body.add_child(_hair())
	_build_armour(body)
	_build_drones(body)
	_build_floor(body)
	HudKit.ignore_input(self)


## is_floor — Targeting.inspection()["is_floor"] як є.
func show_unit(unit: Unit, is_floor: bool) -> void:
	var t: Dictionary = unit.type()
	var cls: int = unit.unit_class()
	_tab.color = UnitView.PLAYER_COLORS[unit.owner % UnitView.PLAYER_COLORS.size()]
	name_label.text = tr(String(t["name_key"]))
	class_label.text = tr(HudKit.CLASS_KEYS[cls]).to_upper()
	_sil.texture = HudKit.SILHOUETTES[cls]
	var unarmed: bool = cls == UnitTypes.UnitClass.ENGINEER
	attack_value.text = _DASH if unarmed else str(int(t["attack"]))
	range_value.text = _DASH if unarmed else str(int(t["attack_range"]))
	vision_value.text = str(int(t["vision"]))
	for v: Label in [attack_value, range_value]:
		v.theme_type_variation = &"HudDim" if unarmed else &"HudNumberStat"
	# Піхота броні не має: рядок «Броня немає» замість глифа й таблиці з трьох нулів.
	var infantry: bool = cls == UnitTypes.UnitClass.INFANTRY
	armour_none_row.visible = infantry
	armour_table_row.visible = not infantry
	var armour: Array = t["armour"]
	for i in armour_rows.size():
		armour_rows[i].text = str(int(armour[i]))
	armour_glyph.set_turret(cls == UnitTypes.UnitClass.TANK)
	var drones: int = int(t["drones"])
	drones_row.visible = drones > 0
	drone_pips.set_counts(unit.drones_left, drones)
	drone_count.text = "×%d" % unit.drones_left
	for w: Array in _words:
		(w[0] as Label).text = tr(String(w[1])).to_upper() if bool(w[2]) else tr(String(w[1]))
	floor_label.text = tr("hud_threat_floor_drone")
	_floor_box.visible = is_floor
	reset_size()
	visible = true


func hide_card() -> void:
	visible = false


func _build_head(body: VBoxContainer) -> void:
	var m := _margin(12, 8, 12, 7)
	body.add_child(m)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	m.add_child(row)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	name_label = HudKit.label(&"HudHoldName")
	# Лівий відступ 12 + вкладка 4 = 16 dp від краю картки: назві лишається 226 − 2 (рамка) − 16 − 12 − 40 − 6 = 150 dp,
	# і назва «Штурмове відділення» стоїть в одному рядку; довша переноситься, а не обрізається.
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	TightLine.wrap(name_label, col, 16.0)
	class_label = HudKit.label(&"HudCaption")
	TightLine.wrap(class_label, col, 11.0)
	row.add_child(HudKit.gap(6.0))
	_sil = HudKit.icon(HudKit.SILHOUETTES[UnitTypes.UnitClass.TANK], Vector2(40.0, 20.0))
	_sil.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(_sil)


func _build_stats(body: VBoxContainer) -> void:
	var m := _margin(12, 7, 12, 7)
	body.add_child(m)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	m.add_child(row)
	attack_value = _stat(row, "hud_attack", 0.85)
	range_value = _stat(row, "hud_range", 1.15)
	vision_value = _stat(row, "hud_vision", 1.0)


## Три рівні колонки: підпис і число над ним вирівняні праворуч по краю колонки (одна система з
## таблицею броні); права колонка закінчується на правому полі картки.
func _stat(row: HBoxContainer, key: String, ratio: float) -> Label:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_stretch_ratio = ratio
	row.add_child(col)
	var cap := HudKit.label(&"HudCaptionStats")
	_words.append([cap, key, true])
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	TightLine.wrap(cap, col, 11.0)
	var value := HudKit.label(&"HudNumberStat")
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	TightLine.wrap(value, col, 17.0)
	return value


func _build_armour(body: VBoxContainer) -> void:
	armour_table_row = _margin(14, 6, 12, 6)
	body.add_child(armour_table_row)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	armour_table_row.add_child(row)
	armour_glyph = ArmourGlyph.new()
	armour_glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(armour_glyph)
	var table := VBoxContainer.new()
	table.add_theme_constant_override("separation", 0)
	table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(table)
	for sector: int in [UnitTypes.ArmourSector.FRONT, UnitTypes.ArmourSector.SIDE, UnitTypes.ArmourSector.REAR]:
		var line := HBoxContainer.new()
		line.custom_minimum_size = Vector2(0.0, 17.0)
		table.add_child(line)
		var word := HudKit.label(&"HudDim")
		_words.append([word, HudKit.SECTOR_KEYS[sector], false])
		word.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		TightLine.wrap(word, line, 17.0)
		var value := HudKit.label(&"HudNumber")
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		TightLine.wrap(value, line, 17.0)
		armour_rows.append(value)
	armour_none_row = _margin(14, 0, 12, 0)
	armour_none_row.custom_minimum_size = Vector2(0.0, 34.0)
	body.add_child(armour_none_row)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 0)
	armour_none_row.add_child(line)
	var word := HudKit.label(&"HudDim")
	_words.append([word, "hud_armour", false])
	word.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	word.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(word)
	var none := HudKit.label(&"HudLabel")
	_words.append([none, "hud_armour_none", false])
	none.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(none)


func _build_drones(body: VBoxContainer) -> void:
	drones_row = VBoxContainer.new()
	drones_row.add_theme_constant_override("separation", 0)
	body.add_child(drones_row)
	drones_row.add_child(_hair())
	var m := _margin(12, 0, 12, 0)
	m.custom_minimum_size = Vector2(0.0, 28.0)
	drones_row.add_child(m)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	m.add_child(row)
	row.add_child(HudKit.icon(_ICON_DRONE, Vector2(16.0, 16.0)))
	var word := HudKit.label(&"HudDim")
	_words.append([word, "hud_drones", false])
	word.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(word)
	drone_pips = DronePips.new()
	drone_pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(drone_pips)
	var grow := Control.new()
	grow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(grow)
	drone_count = HudKit.label(&"HudNumber")
	drone_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(drone_count)


func _build_floor(body: VBoxContainer) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	body.add_child(box)
	_floor_box = box
	box.add_child(_hair())
	var m := _margin(12, 6, 12, 6)
	box.add_child(m)
	floor_label = HudKit.label(&"HudFloorCaption")
	floor_label.name = "ThreatFloorLabel"
	floor_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	floor_label.custom_minimum_size = Vector2(WIDTH - 12.0 - 12.0 - 4.0, 0.0)
	m.add_child(floor_label)


func _margin(l: int, t: int, r: int, b: int) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", l)
	m.add_theme_constant_override("margin_top", t)
	m.add_theme_constant_override("margin_right", r)
	m.add_theme_constant_override("margin_bottom", b)
	return m


func _hair() -> ColorRect:
	var d := ColorRect.new()
	d.color = HudKit.HAIR
	d.custom_minimum_size = Vector2(0.0, 1.0)
	return d
