extends RefCounted
## Спільне для e2e-тестів. Ім'я без префікса `test_`, тож GUT не вважає файл тестом.
## Тримає посилання на GutTest, щоб кидати assert-и й чекати кадри від його імені.

var _t: GutTest
## Control -> початковий mouse_filter; повертаємо в restore_runner_gui(),
## щоб правка не текла в інші тести.
var _saved_filters: Dictionary[Control, int] = {}


func _init(test: GutTest) -> void:
	_t = test


## GUT-раннер вішає на root власний GUI (RichTextLabel з виводом), який перехоплює
## миші й не пускає її до гри — у релізі його нема. Гасимо йому mouse_filter:
## це правка тестового середовища, а не гри. skip — піддерева, які чіпати не можна
## (екран, що його тест сам клікає).
func ignore_runner_gui(skip: Array[Node] = []) -> void:
	var runner: Node = _t.get_tree().root.get_node_or_null("GutRunner")
	if runner != null:
		_ignore_recursive(runner, skip)


func _ignore_recursive(n: Node, skip: Array[Node]) -> void:
	if skip.has(n):
		return
	if n is Control:
		var ctl := n as Control
		if not _saved_filters.has(ctl):
			_saved_filters[ctl] = ctl.mouse_filter
		ctl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c: Node in n.get_children():
		_ignore_recursive(c, skip)


func restore_runner_gui() -> void:
	for c: Control in _saved_filters:
		if is_instance_valid(c):
			c.mouse_filter = _saved_filters[c]
	_saved_filters.clear()


## Справжній клік мишею у viewport: рух, натиск, відпускання.
func click_at(p: Vector2) -> void:
	var vp: Viewport = _t.get_viewport()
	var mv := InputEventMouseMotion.new()
	mv.position = p
	mv.global_position = p
	vp.push_input(mv, true)
	for pressed: bool in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = p
		ev.global_position = p
		ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		vp.push_input(ev, true)


## Гасимо твіни вручну (реального часу не чекаємо).
func step_tweens() -> void:
	for tw: Tween in Engine.get_main_loop().get_processed_tweens():
		if tw.is_valid():
			tw.custom_step(10.0)


## Крутить кадри з прискореними твінами, доки cond не стане true; не став —
## падає голосно, а не зависає.
func wait_until(cond: Callable, what: String, max_frames: int = 120) -> bool:
	for i in max_frames:
		step_tweens()
		await _t.get_tree().process_frame
		if cond.call():
			return true
	_t.assert_true(cond.call(), "не дочекались: " + what)
	return cond.call()
