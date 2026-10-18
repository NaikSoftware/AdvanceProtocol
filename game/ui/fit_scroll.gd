class_name FitScroll
extends ScrollContainer
## Прокрутка, що займає рівно висоту свого вмісту, поки та влазить у батька, і
## лише понад це прокручує. Звичайний ScrollContainer має мінімум 0 і в
## центрованому VBox сплющився б — а розтягнутий відірвав би футер від картки.
## Висота, яку лишили сусіди, — це висота батька мінус його мінімум без нас.


func _ready() -> void:
	get_parent_control().resized.connect(_fit)
	for child in get_children():
		if child is Control:
			(child as Control).minimum_size_changed.connect(_fit)
	_fit.call_deferred()


func _fit() -> void:
	var parent: Control = get_parent_control()
	var content: float = 0.0
	for child in get_children():
		if child is Control:
			content = maxf(content, (child as Control).get_combined_minimum_size().y)
	var others: float = parent.get_combined_minimum_size().y - get_combined_minimum_size().y
	custom_minimum_size.y = maxf(0.0, minf(content, parent.size.y - others))
