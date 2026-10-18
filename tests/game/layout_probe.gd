class_name LayoutProbe
extends RefCounted
## Помічник тестів розкладки (без префікса test_ — GUT його не запускає).
## Сцена монтується в SubViewport заданого ЛОГІЧНОГО розміру: після UiScale
## логічний px ≈ dp, тож 800×360 — це справді малий телефон, а не зменшений ПК.

const PHONE_SMALL := Vector2i(800, 360)
const PHONE_LARGE := Vector2i(985, 442)
const PC := Vector2i(1280, 720)
const TABLET := Vector2i(1280, 800)
## Лише для перевірки, що вміст меню не тягнеться на всю ширину.
const WIDE := Vector2i(1600, 720)
const SIZES: Array[Vector2i] = [PHONE_SMALL, PHONE_LARGE, PC, TABLET]


## setup отримує екземпляр ДО додавання в дерево — щоб підмінити залежності
## (match_service) до _ready().
static func mount(test: GutTest, scene: PackedScene, size: Vector2i, setup: Callable = Callable()) -> Control:
	var viewport := SubViewport.new()
	viewport.size = size
	test.add_child_autofree(viewport)
	var root: Control = scene.instantiate()
	if setup.is_valid():
		setup.call(root)
	viewport.add_child(root)
	await settle(test)
	return root


## Два кадри: контейнери перераховують мінімуми з відкладеним сортуванням.
static func settle(test: GutTest) -> void:
	await test.get_tree().process_frame
	await test.get_tree().process_frame


## Вміст ScrollContainer не рахується: він обрізаний і досяжний прокруткою —
## перевіряється сам ScrollContainer.
static func overflowing(root: Control, size: Vector2i) -> Array[String]:
	# Пів пікселя запасу на дробові позиції CenterContainer.
	var screen := Rect2(Vector2.ZERO, size).grow(0.5)
	var out: Array[String] = []
	for c: Control in _visible_controls(root):
		if _inside_scroll(root, c):
			continue
		if not screen.encloses(c.get_global_rect()):
			out.append("%s %s" % [root.get_path_to(c), c.get_global_rect()])
	return out


static func _inside_scroll(root: Control, c: Control) -> bool:
	var n: Node = c.get_parent()
	while n != null and n != root.get_parent():
		if n is ScrollContainer:
			return true
		n = n.get_parent()
	return false


## Кнопки, яких не видно без прокрутки: прямокутник виходить за Viewport або за
## будь-який ScrollContainer-предок у його нинішньому (початковому) положенні.
static func clipped(root: Control, buttons: Array[Control], size: Vector2i) -> Array[String]:
	var screen := Rect2(Vector2.ZERO, size).grow(0.5)
	var out: Array[String] = []
	for b: Control in buttons:
		var rect: Rect2 = b.get_global_rect()
		var ok: bool = b.is_visible_in_tree() and screen.encloses(rect)
		var n: Node = b.get_parent()
		while ok and n != null and n != root.get_parent():
			if n is ScrollContainer:
				ok = (n as Control).get_global_rect().grow(0.5).encloses(rect)
			n = n.get_parent()
		if not ok:
			out.append("%s %s" % [root.get_path_to(b), rect])
	return out


static func small_targets(root: Control, min_px: float = 48.0) -> Array[String]:
	var out: Array[String] = []
	for c: Control in _visible_controls(root):
		if c is BaseButton and (c.size.x < min_px or c.size.y < min_px):
			out.append("%s %s" % [root.get_path_to(c), c.size])
	return out


static func overlapping(controls: Array[Control]) -> Array[String]:
	var out: Array[String] = []
	for i in controls.size():
		for j in range(i + 1, controls.size()):
			var a: Control = controls[i]
			var b: Control = controls[j]
			if a.is_visible_in_tree() and b.is_visible_in_tree() \
					and a.get_global_rect().intersects(b.get_global_rect()):
				out.append("%s × %s" % [a.name, b.name])
	return out


static func _visible_controls(root: Control) -> Array[Control]:
	var out: Array[Control] = []
	if not root.is_visible_in_tree():
		return out
	out.append(root)
	for child in root.find_children("*", "Control", true, false):
		var c := child as Control
		if c.is_visible_in_tree():
			out.append(c)
	return out
