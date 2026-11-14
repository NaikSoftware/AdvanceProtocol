class_name TightLine
extends Container
## Підпис у рядку заданої висоти (CSS line-height), а не у висоті, яку дає шрифт: шрифт вищий за кегль,
## і стеком таких підписів картка виходила на пів десятка dp вищою за макет. Текст центрується в
## рядку, як це робить line-height; Label сам нижче своєї мінімальної висоти не стискається.

var line_height: float = 0.0


static func wrap(label: Label, parent: Node, p_line_height: float) -> TightLine:
	var t := TightLine.new()
	t.line_height = p_line_height
	t.size_flags_horizontal = label.size_flags_horizontal
	t.size_flags_vertical = label.size_flags_vertical
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.add_child(label)
	parent.add_child(t)
	return t


func _get_minimum_size() -> Vector2:
	var w: float = 0.0
	for c in get_children():
		if c is Control:
			w = maxf(w, (c as Control).get_combined_minimum_size().x)
	return Vector2(w, line_height)


func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		for c in get_children():
			var l := c as Control
			if l != null:
				var m: Vector2 = l.get_combined_minimum_size()
				fit_child_in_rect(l, Rect2(0.0, floorf((line_height - m.y) * 0.5), maxf(size.x, m.x), m.y))
	elif what == NOTIFICATION_THEME_CHANGED:
		update_minimum_size()
