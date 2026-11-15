class_name PreviewPlate
extends HudBake
## Плита прев'ю над рядом дій (docs/ui/hud.md#action-previews): ряд цілі + один із вмістів —
## постріл, дрон, ремонт чи назва верби. Лише показує готові значення, які дає HUD із
## core/-прев'ю; сама нічого не рахує й не знає про правила.
##
## Вузли дітей отримують унікальні імена в сцені власника (HUD): тести й сцена бою читають
## %PreviewDamageValue тощо так само, як і раніше.

## Спільна ширина з рядом дій і смужкою озброєння: одна стала на всі три.
const WIDTH: float = HudDocking.CLUSTER_W
const BONE: Color = Color("e3dfd3")
const DIM: Color = Color("8f918a")
const HAIR: Color = Color("3a4043")
const _SIL_INFANTRY: Texture2D = preload("res://assets/ui/icons/sil_infantry.svg")
## Той самий малюнок дрона, що й на кнопках «Удар» і «Дрон»: на одному кластері — один дрон.
const _ICON_DRONE: Texture2D = preload("res://assets/ui/icons/btn_drone.svg")
const _ICON_REPAIR: Texture2D = preload("res://assets/ui/icons/repair_unit.svg")
## Поля вмісту (ліво, верх, право, низ) і проміжок між колонками — однакові в пострілі, дроні й ремонті.
const _BOX_MARGINS: Vector4 = Vector4(12, 6, 12, 7)
const _ROW_SEP: int = 10

var target_row: Control
var shot_box: Control
var drone_box: Control
var repair_box: Control
var armour_glyph: ArmourGlyph

var _tab: ColorRect
var _target_name: Label
var _target_caption: Label
var _sil: TextureRect
var _sector_caption: Label
var _sector_value: Label
var _note: Label
var _cover: PanelContainer
var _cover_label: Label
var _damage_caption: Label
var _damage_value: Label
var _drone_armour_caption: Label
var _drone_armour_value: Label
var _drone_damage_caption: Label
var _drone_damage_value: Label
var _hp_caption: Label
var _hp_value: Label
var _hp_max: Label
var _heal_caption: Label
var _heal_value: Label
var _target_hair: ColorRect


func _init() -> void:
	super()
	face.theme_type_variation = &"HudPlateSolid"
	face.custom_minimum_size = Vector2(WIDTH, 0.0)
	visible = false


func _ready() -> void:
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 0)
	face.add_child(body)

	target_row = HBoxContainer.new()
	target_row.name = "PreviewTargetRow"
	target_row.custom_minimum_size = Vector2(0.0, 24.0)
	target_row.add_theme_constant_override("separation", 0)
	body.add_child(target_row)
	_own(target_row)
	_tab = ColorRect.new()
	_tab.custom_minimum_size = Vector2(4.0, 24.0)
	_tab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target_row.add_child(_tab)
	target_row.add_child(_gap(8.0))
	_target_name = _label("PreviewTargetName", &"HudName", target_row)
	_target_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var grow := Control.new()
	grow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target_row.add_child(grow)
	_target_caption = _label("", &"HudCaption", target_row)
	_target_caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	target_row.add_child(_gap(10.0))
	_target_hair = ColorRect.new()
	_target_hair.color = HAIR
	_target_hair.custom_minimum_size = Vector2(0.0, 1.0)
	_target_hair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(_target_hair)

	# Постріл: глиф / силует піхоти · сектор · роздільник · шкода.
	shot_box = _box("PreviewShotBox", body, _BOX_MARGINS, 0.0)
	var srow := _row(shot_box, _ROW_SEP)
	var holder := Control.new()
	holder.custom_minimum_size = ArmourGlyph.SIZE
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	srow.add_child(holder)
	armour_glyph = ArmourGlyph.new()
	armour_glyph.name = "ArmourGlyph"
	holder.add_child(armour_glyph)
	_sil = _icon(_SIL_INFANTRY, ArmourGlyph.SIZE.x)
	_sil.custom_minimum_size = Vector2(ArmourGlyph.SIZE.x, ArmourGlyph.SIZE.x * 0.5)
	_sil.position = Vector2(0.0, (ArmourGlyph.SIZE.y - ArmourGlyph.SIZE.x * 0.5) * 0.5)
	_sil.size = _sil.custom_minimum_size
	_sil.modulate = DIM
	_sil.visible = false
	holder.add_child(_sil)
	var sv := VBoxContainer.new()
	sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sv.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	sv.add_theme_constant_override("separation", 0)
	sv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	srow.add_child(sv)
	_sector_caption = _label("", &"HudCaption", sv)
	_sector_value = _label("PreviewSectorValue", &"HudSector", sv)
	_note = _label("PreviewArmourNote", &"HudFloorCaption", sv)
	# Плита фіксованої спільної ширини: довші англійські підписи переносяться, а не розпирають її.
	for l: Label in [_sector_caption, _note]:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 60.0
	_cover = PanelContainer.new()
	_cover.name = "PreviewCoverMarker"
	var outline := StyleBoxFlat.new()
	outline.bg_color = Color(0, 0, 0, 0)
	outline.set_border_width_all(1)
	outline.border_color = BONE
	outline.content_margin_left = 5.0
	outline.content_margin_right = 5.0
	_cover.add_theme_stylebox_override("panel", outline)
	_cover.custom_minimum_size = Vector2(0.0, 16.0)
	_cover.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sv.add_child(_cover)
	_own(_cover)
	_cover_label = _label("", &"HudCaption", _cover)
	_cover_label.add_theme_color_override("font_color", BONE)
	srow.add_child(_divider(ArmourGlyph.SIZE.y))
	var dv := _column(srow)
	_damage_caption = _label("", &"HudCaption", dv)
	_damage_value = _label("PreviewDamageValue", &"HudNumberBig", dv)

	# Дрон: значок · «броня не діє» · роздільник · шкода.
	drone_box = _box("PreviewDroneBox", body, _BOX_MARGINS, 0.0)
	var drow := _row(drone_box, _ROW_SEP)
	drow.add_child(_icon(_ICON_DRONE, ArmourGlyph.SIZE.x))
	var dav := _column(drow)
	dav.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_drone_armour_caption = _label("", &"HudCaption", dav)
	_drone_armour_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_drone_armour_caption.custom_minimum_size.x = 60.0
	_drone_armour_value = _label("PreviewDroneArmour", &"HudSector", dav)
	drow.add_child(_divider(ArmourGlyph.SIZE.y))
	var ddv := _column(drow)
	_drone_damage_caption = _label("", &"HudCaption", ddv)
	_drone_damage_value = _label("PreviewDroneDamageValue", &"HudNumberBig", ddv)

	# Ремонт: значок · міцність цілі · роздільник · межі ремонту.
	repair_box = _box("PreviewRepairBox", body, _BOX_MARGINS, 0.0)
	var rrow := _row(repair_box, _ROW_SEP)
	rrow.add_child(_icon(_ICON_REPAIR, ArmourGlyph.SIZE.x))
	var rv := _column(rrow)
	rv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hp_caption = _label("", &"HudCaption", rv)
	var hrow := _baseline_row(rv)
	_hp_value = _label("PreviewHpValue", &"HudSector", hrow)
	_hp_max = _label("PreviewHpMax", &"HudNumberDim15", hrow)
	rrow.add_child(_divider(ArmourGlyph.SIZE.y))
	var hv := _column(rrow)
	_heal_caption = _label("", &"HudCaption", hv)
	_heal_value = _label("PreviewHealValue", &"HudNumberBig", hv)

	_retranslate()
	clear()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _damage_caption != null:
		_retranslate()


func _retranslate() -> void:
	_target_caption.text = tr("hud_target").to_upper()
	_sector_caption.text = tr("hud_armour_sector").to_upper()
	_note.text = tr("hud_armour_ignored_note")
	_cover_label.text = tr("hud_cover_half").to_upper()
	_damage_caption.text = tr("hud_damage").to_upper()
	_drone_armour_caption.text = tr("hud_armour").to_upper()
	_drone_armour_value.text = tr("hud_armour_ignored")
	_drone_damage_caption.text = tr("hud_damage").to_upper()
	_hp_caption.text = tr("hud_hp").to_upper()
	_heal_caption.text = tr("hud_heal").to_upper()
	_changed()


func clear() -> void:
	visible = false
	for c: Control in [target_row, _target_hair, shot_box, drone_box, repair_box]:
		c.visible = false
	_changed()


## Ряд цілі: язичок у кольорі власника цілі, назва, підпис «ЦІЛЬ».
func show_target(target_name: String, color: Color) -> void:
	_tab.color = color
	_target_name.text = target_name
	target_row.visible = true
	_target_hair.visible = true
	_changed()


## sector/sector_word — з core-прев'ю; infantry_target: ціль без броні (силует замість корпуса);
## turret: чи малювати башту на корпусі.
func show_shot(sector: int, sector_word: String, damage: String, infantry_target: bool, turret: bool,
		armour_ignored: bool, in_cover: bool) -> void:
	_sector_value.text = sector_word
	_damage_value.text = damage
	armour_glyph.visible = not infantry_target
	_sil.visible = infantry_target
	armour_glyph.set_turret(turret)
	armour_glyph.set_sector(sector)
	# Нотатка «броня не діє» — лише там, де є броня, яку не враховано.
	_note.visible = armour_ignored and not infantry_target
	_cover.visible = in_cover
	shot_box.visible = true
	visible = true
	_changed()


func show_drone(damage: String) -> void:
	_drone_damage_value.text = damage
	drone_box.visible = true
	visible = true
	_changed()


func show_repair(hp: int, max_hp: int, heal: String) -> void:
	_hp_value.text = str(hp)
	_hp_max.text = "/%d" % max_hp
	_heal_value.text = heal
	repair_box.visible = true
	visible = true
	_changed()


## Мінімальний розмір хоста перераховується одразу (HUD читає його в тому ж кадрі), а запікання
## чекає, поки розкладка вмісту осяде.
func _changed() -> void:
	update_minimum_size()
	request_bake()


# --- будівельні дрібниці -------------------------------------------------------

func _box(box_name: String, parent: Control, margins: Vector4, min_h: float) -> MarginContainer:
	var m := MarginContainer.new()
	m.name = box_name
	m.add_theme_constant_override("margin_left", int(margins.x))
	m.add_theme_constant_override("margin_top", int(margins.y))
	m.add_theme_constant_override("margin_right", int(margins.z))
	m.add_theme_constant_override("margin_bottom", int(margins.w))
	m.custom_minimum_size = Vector2(0.0, min_h)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(m)
	_own(m)
	return m


func _row(parent: Control, separation: int) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", separation)
	h.alignment = BoxContainer.ALIGNMENT_BEGIN
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(h)
	return h


func _baseline_row(parent: Control) -> BaselineRow:
	var r := BaselineRow.new()
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r


func _column(parent: Control) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	# Підписи лівої й правої колонки на одній лінії в кожному стані, тож колонки не центруються по висоті.
	v.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(v)
	return v


## Унікальне ім'я в сцені власника (HUD): %Name тут працює так само, як для вузлів .tscn.
func _own(n: Node) -> void:
	if owner != null:
		n.owner = owner
		n.unique_name_in_owner = true


func _label(label_name: String, variation: StringName, parent: Control) -> Label:
	var l := Label.new()
	l.theme_type_variation = variation
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if label_name != "":
		l.name = label_name
	parent.add_child(l)
	if label_name != "":
		_own(l)
	return l


func _icon(tex: Texture2D, side: float) -> TextureRect:
	var t := TextureRect.new()
	t.texture = tex
	t.custom_minimum_size = Vector2(side, side)
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# SVG білий сам по собі: колір задає токен, як у макеті.
	t.modulate = HudKit.BONE
	return t


func _gap(width: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(width, 0.0)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _divider(height: float) -> ColorRect:
	var d := ColorRect.new()
	d.color = HAIR
	d.custom_minimum_size = Vector2(1.0, height)
	d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return d


func _expander(parent: Control) -> void:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)
