class_name UnitTag
extends HudBake
## Компактний тег вибраного юніта (spec §2): силует класу · назва · для загону пипси дронів. AP
## не пишемо ніде: запас ходу показують зони руху. Без класу словом, HP і характеристик. Лише показує готове: усе з Unit і
## UnitTypes. Де стати — вирішує TagPlacement; тут тільки вузли й лідер.
##
## Ввід: тег, усі діти й лідер — MOUSE_FILTER_IGNORE. Тег стоїть усередині зони руху власного
## юніта, тож тап по ньому мусить лягти на клітинку дошки під ним, а не зникнути в панелі.

const HEIGHT: float = 26.0
const LEADER_COLOR: Color = Color(0.8902, 0.8745, 0.8275, 0.8)

var name_label: Label
var pips: DronePips

var _sil: TextureRect
var _tab: ColorRect
var _pip_box: HBoxContainer
var _leader: PackedVector2Array = PackedVector2Array()
var _shown: String = ""


func _init() -> void:
	super()
	name = "UnitTag"
	face.theme_type_variation = &"HudPlateSolid"
	face.custom_minimum_size = Vector2(0.0, HEIGHT)
	visible = false
	var shell := HBoxContainer.new()
	shell.add_theme_constant_override("separation", 0)
	face.add_child(shell)
	# Смужка кольору гравця — лише на чужому тезі: свій юніт активного гравця читається без неї.
	_tab = ColorRect.new()
	_tab.custom_minimum_size = Vector2(4.0, 0.0)
	shell.add_child(_tab)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_right", 7)
	shell.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	margin.add_child(row)
	_sil = HudKit.icon(HudKit.SILHOUETTES[UnitTypes.UnitClass.TANK], Vector2(22.0, 11.0))
	row.add_child(_sil)
	row.add_child(HudKit.gap(5.0))
	name_label = HudKit.label(&"HudName")
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(name_label)

	_pip_box = HBoxContainer.new()
	_pip_box.add_theme_constant_override("separation", 0)
	row.add_child(_pip_box)
	_pip_box.add_child(_sep())
	pips = DronePips.new()
	pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_pip_box.add_child(pips)
	HudKit.ignore_input(self)


## own — свій юніт активного гравця: чужий тег натомість має смужку кольору власника.
## Лічильник дронів публічний (§3.9), тож показується завжди, поки в типу є дрони.
func show_unit(unit: Unit, own: bool) -> void:
	name_label.text = tr(String(unit.type()["name_key"]))
	_sil.texture = HudKit.SILHOUETTES[unit.unit_class()]
	_tab.visible = not own
	_tab.color = UnitView.PLAYER_COLORS[unit.owner % UnitView.PLAYER_COLORS.size()]
	var drones: int = int(unit.type()["drones"])
	_pip_box.visible = drones > 0
	pips.set_counts(unit.drones_left, drones)
	update_minimum_size()
	reset_size()
	# Запікаємо лише коли змінилося те, що видно: тег оновлюється й від руху камери.
	var shown: String = "%s|%d|%d|%d|%s|%d" % [name_label.text, drones, unit.drones_left, unit.unit_class(), own, unit.owner]
	if shown != _shown:
		_shown = shown
		request_bake()
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
	super._draw()
	if _leader.is_empty():
		return
	draw_line(_leader[0], _leader[1], LEADER_COLOR, 1.0)
	# Квадрат — теж «лінія» (5 × 5): дві лінії поспіль склеюються в один виклик, лінія з rect — ні.
	draw_line(_leader[1] - Vector2(2.5, 0.0), _leader[1] + Vector2(2.5, 0.0), LEADER_COLOR, 5.0)


func _sep() -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.add_child(HudKit.gap(7.0))
	box.add_child(HudKit.divider(12.0))
	box.add_child(HudKit.gap(7.0))
	return box
