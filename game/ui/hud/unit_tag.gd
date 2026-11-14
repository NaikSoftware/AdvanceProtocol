class_name UnitTag
extends PanelContainer
## Компактний тег вибраного юніта (spec §2): силует класу · назва · AP n/max (лише свій) · для
## загону пипси дронів. Без класу словом, HP і характеристик. Лише показує готове: усе з Unit і
## UnitTypes. Де стати — вирішує TagPlacement; тут тільки вузли й лідер.
##
## Ввід: тег, усі діти й лідер — MOUSE_FILTER_IGNORE. Тег стоїть усередині зони руху власного
## юніта, тож тап по ньому мусить лягти на клітинку дошки під ним, а не зникнути в панелі.

const HEIGHT: float = 30.0
const LEADER_COLOR: Color = Color(0.8902, 0.8745, 0.8275, 0.8)
const _ICON_AP: Texture2D = preload("res://assets/ui/icons/ap.svg")

var name_label: Label
var ap_value: Label
var ap_max: Label
var pips: DronePips

var _sil: TextureRect
var _ap_box: HBoxContainer
var _pip_box: HBoxContainer
var _leader: PackedVector2Array = PackedVector2Array()


func _init() -> void:
	name = "UnitTag"
	theme_type_variation = &"HudPlateSolid"
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	custom_minimum_size = Vector2(0.0, HEIGHT)
	visible = false
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 10)
	add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	margin.add_child(row)
	_sil = HudKit.icon(HudKit.SILHOUETTES[UnitTypes.UnitClass.TANK], Vector2(26.0, 13.0))
	row.add_child(_sil)
	row.add_child(HudKit.gap(6.0))
	name_label = HudKit.label(&"HudName")
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(name_label)

	_ap_box = HBoxContainer.new()
	_ap_box.add_theme_constant_override("separation", 0)
	row.add_child(_ap_box)
	_ap_box.add_child(_sep())
	_ap_box.add_child(HudKit.icon(_ICON_AP, Vector2(13.0, 13.0)))
	_ap_box.add_child(HudKit.gap(4.0))
	ap_value = HudKit.label(&"HudNumberTag")
	ap_value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_ap_box.add_child(ap_value)
	ap_max = HudKit.label(&"HudNumberDim13")
	ap_max.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_ap_box.add_child(ap_max)

	_pip_box = HBoxContainer.new()
	_pip_box.add_theme_constant_override("separation", 0)
	row.add_child(_pip_box)
	_pip_box.add_child(_sep())
	pips = DronePips.new()
	pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_pip_box.add_child(pips)
	HudKit.ignore_input(self)


## show_ap — лише свій юніт активного гравця: AP ворога — прихований залишок його дій.
## Лічильник дронів публічний (§3.9), тож показується завжди, поки в типу є дрони.
func show_unit(unit: Unit, show_ap: bool) -> void:
	name_label.text = tr(String(unit.type()["name_key"]))
	_sil.texture = HudKit.SILHOUETTES[unit.unit_class()]
	_ap_box.visible = show_ap
	ap_value.text = str(unit.ap)
	ap_max.text = "/%d" % unit.max_ap()
	var drones: int = int(unit.type()["drones"])
	_pip_box.visible = drones > 0
	pips.set_counts(unit.drones_left, drones)
	reset_size()
	visible = true


## Лідер — від краю тега до смуги + моделі юніта, у координатах батька тега; пустий — без лідера.
func set_leader(from_parent: Vector2, to_parent: Vector2) -> void:
	_leader = PackedVector2Array([from_parent - position, to_parent - position])
	queue_redraw()


func clear_leader() -> void:
	if not _leader.is_empty():
		_leader = PackedVector2Array()
		queue_redraw()


func has_leader() -> bool:
	return not _leader.is_empty()


func _draw() -> void:
	if _leader.is_empty():
		return
	draw_line(_leader[0], _leader[1], LEADER_COLOR, 1.0)
	draw_rect(Rect2(_leader[1] - Vector2(2.5, 2.5), Vector2(5.0, 5.0)), LEADER_COLOR)


func _sep() -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.add_child(HudKit.gap(8.0))
	box.add_child(HudKit.divider(14.0))
	box.add_child(HudKit.gap(8.0))
	return box
