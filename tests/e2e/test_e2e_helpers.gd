extends GutTest
## Тестове середовище e2e: GUI раннера GUT не сміє з'їдати мишу. Смуга прокрутки
## RichTextLabel виводу — ВНУТРІШНІЙ вузол (get_children() її не бачить), і саме
## вона з'їла драг у test_threat_e2e, коли виводу стало досить для прокрутки.

const E2E := preload("res://tests/e2e/e2e_helpers.gd")


func test_ignore_runner_gui_mutes_internal_children_and_restore_brings_them_back() -> void:
	var runner: Node = get_tree().root.get_node_or_null("GutRunner")
	assert_not_null(runner, "e2e працює під раннером GUT")
	if runner == null:
		return
	var host := Control.new()
	var internal := Control.new()
	internal.mouse_filter = Control.MOUSE_FILTER_STOP
	host.add_child(internal, false, Node.INTERNAL_MODE_BACK)
	runner.add_child(host)
	var e2e := E2E.new(self)
	e2e.ignore_runner_gui()
	assert_eq(internal.mouse_filter, Control.MOUSE_FILTER_IGNORE, "внутрішній вузол приглушено")
	e2e.restore_runner_gui()
	assert_eq(internal.mouse_filter, Control.MOUSE_FILTER_STOP, "і повернуто після тесту")
	host.free()
