class_name HudKit
extends RefCounted
## Спільне для тега юніта й картки утримання: ключі підписів, силуети класів і дрібні фабрики
## вузлів. Клас називається словом і значком тут, а не в core/: core/ не знає, що існує екран (§6).

const BONE: Color = Color("e3dfd3")
const DIM: Color = Color("8f918a")
const HAIR: Color = Color("3a4043")

## Сектор у прев'ю й рядок таблиці броні картки мусять називати той самий сектор тим самим словом.
const SECTOR_KEYS: Dictionary = {
	UnitTypes.ArmourSector.FRONT: "hud_sector_front",
	UnitTypes.ArmourSector.SIDE: "hud_sector_side",
	UnitTypes.ArmourSector.REAR: "hud_sector_rear",
}

const CLASS_KEYS: Dictionary = {
	UnitTypes.UnitClass.INFANTRY: "unit_class_infantry",
	UnitTypes.UnitClass.LIGHT_VEHICLE: "unit_class_light_vehicle",
	UnitTypes.UnitClass.TANK: "unit_class_tank",
	UnitTypes.UnitClass.ARTILLERY: "unit_class_artillery",
	UnitTypes.UnitClass.ENGINEER: "unit_class_engineer",
}

const SILHOUETTES: Dictionary = {
	UnitTypes.UnitClass.INFANTRY: preload("res://assets/ui/icons/sil_infantry.svg"),
	UnitTypes.UnitClass.LIGHT_VEHICLE: preload("res://assets/ui/icons/sil_light_vehicle.svg"),
	UnitTypes.UnitClass.TANK: preload("res://assets/ui/icons/sil_tank.svg"),
	UnitTypes.UnitClass.ARTILLERY: preload("res://assets/ui/icons/sil_artillery.svg"),
	UnitTypes.UnitClass.ENGINEER: preload("res://assets/ui/icons/sil_engineer.svg"),
}


static func label(variation: StringName, text: String = "") -> Label:
	var l := Label.new()
	l.theme_type_variation = variation
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Іконка у квадраті side × side; dim — приглушений колір, як у решти HUD.
static func icon(tex: Texture2D, size: Vector2, dim: bool = true) -> TextureRect:
	var t := TextureRect.new()
	t.texture = tex
	t.custom_minimum_size = size
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if dim:
		t.modulate = DIM
	return t


static func gap(width: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(width, 0.0)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func divider(height: float) -> ColorRect:
	var d := ColorRect.new()
	d.color = HAIR
	d.custom_minimum_size = Vector2(1.0, height)
	d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return d


## Усе піддерево ігнорує вказівник: тап по тегу чи картці лягає на клітинку дошки під ними.
static func ignore_input(root: Control) -> void:
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for n in root.find_children("*", "Control", true, false):
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE


## Значок і підпис кнопки — одна група по центру. Рідний Button при центрованому тексті притискає
## значок до краю, а при центрованому значку малює його поверх тексту, тож групу будує сама кнопка:
## значок + проміжок + підпис. Колір підпису й значка веде стан кнопки (вимкнена — приглушена).
static func group_content(button: Button, icon_px: float) -> void:
	var tex: Texture2D = button.icon
	var key: String = button.text
	button.icon = null
	button.text = ""
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(center)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(button.get_theme_constant(&"h_separation")))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(row)
	var mark := icon(tex, Vector2(icon_px, icon_px), false)
	row.add_child(mark)
	# Кнопка без підпису (пауза) — лише значок: порожній підпис із проміжком зсунув би його з центру.
	var word: Label = null
	if not key.is_empty():
		word = Label.new()
		word.text = key
		word.mouse_filter = Control.MOUSE_FILTER_IGNORE
		word.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		word.add_theme_font_override("font", button.get_theme_font(&"font"))
		word.add_theme_font_size_override("font_size", button.get_theme_font_size(&"font_size"))
		row.add_child(word)
	var tint := func() -> void:
		if word != null:
			word.add_theme_color_override("font_color", button.get_theme_color(&"font_disabled_color" if button.disabled else &"font_color"))
		mark.modulate = button.get_theme_color(&"icon_disabled_color" if button.disabled else &"icon_normal_color")
	tint.call()
	button.draw.connect(tint)
	button.set_meta(&"group_mark", mark)
	button.set_meta(&"group_word", word)


## Міняє підпис і значок кнопки, зібраної group_content(): група лишається однією, по центру.
## text — ключ локалізації, як і в group_content(): Label сам перекладає його й при зміні мови.
static func retitle_group(button: Button, text: String, tex: Texture2D, icon_px: float = 20.0, gap: int = 8) -> void:
	var word: Label = button.get_meta(&"group_word")
	if word != null:
		word.text = text
	var mark := button.get_meta(&"group_mark") as TextureRect
	mark.texture = tex
	mark.custom_minimum_size = Vector2(icon_px, icon_px)
	(mark.get_parent() as HBoxContainer).add_theme_constant_override("separation", gap)
