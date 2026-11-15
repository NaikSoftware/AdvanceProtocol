class_name BaselineRow
extends Container
## Ряд підписів різного кегля на спільній базовій лінії, без проміжків: «28» і «/48» читаються
## одним числом. HBox із вирівнюванням по низу розводить базові лінії на різницю спуску шрифтів,
## а по верху — на різницю підйому; тут кожному підпису береться власний підйом шрифту.
## Діти — лише Label; усе, що вони знають про шрифт, береться з теми, тож рахується в дереві.

## Права порожнеча глифа цифри перед «/»: без підтяжки між «320» і «/400» лишається щілина, якої
## немає в макеті.
const TUCK: float = 1.0


func _ascent(l: Label) -> float:
	return l.get_theme_font(&"font").get_ascent(l.get_theme_font_size(&"font_size"))


func _get_minimum_size() -> Vector2:
	var w: float = 0.0
	var above: float = 0.0
	var below: float = 0.0
	for c in get_children():
		var l := c as Label
		if l == null or not l.visible:
			continue
		var m: Vector2 = l.get_combined_minimum_size()
		w += m.x - (TUCK if w > 0.0 else 0.0)
		above = maxf(above, _ascent(l))
		below = maxf(below, m.y - _ascent(l))
	return Vector2(w, above + below)


func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		var above: float = 0.0
		for c in get_children():
			if c is Label and (c as Label).visible:
				above = maxf(above, _ascent(c as Label))
		var x: float = 0.0
		for c in get_children():
			var l := c as Label
			if l == null or not l.visible:
				continue
			var m: Vector2 = l.get_combined_minimum_size()
			fit_child_in_rect(l, Rect2(x - (TUCK if x > 0.0 else 0.0), above - _ascent(l), m.x, m.y))
			x += m.x - (TUCK if x > 0.0 else 0.0)
	elif what == NOTIFICATION_THEME_CHANGED:
		update_minimum_size()
