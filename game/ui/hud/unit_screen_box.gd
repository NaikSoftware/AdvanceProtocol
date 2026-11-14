class_name UnitScreenBox
extends RefCounted
## Екранні прямокутники для стикування плит: модель юніта ∪ смуга HP ∪ напис HP ∪ значок
## дрона — саме те, що рушій малює зараз, а не припущення про розмір. Лише юніти з UnitView
## активного гравця (фог): плита, що обходить невидимого ворога, показала б, де він стоїть (§3.5).
## Вузли-діти беруться за іменами зі сцени unit_view.tscn.


static func of(view: Node3D, rig: IsoCameraRig) -> Rect2:
	var box := Rect2()
	var has: bool = false
	var parts: Array[Node] = []
	var sil: Node = view.get_node_or_null("Silhouette")
	if sil != null:
		for n in sil.find_children("*", "VisualInstance3D", true, false):
			parts.append(n)
	for part_name: String in ["HpBar", "HpLabel", "DroneIcon"]:
		var n: Node = view.get_node_or_null(part_name)
		if n != null:
			parts.append(n)
	for n in parts:
		var vi := n as VisualInstance3D
		if vi == null or not vi.visible:
			continue
		var r: Rect2 = _project_aabb(vi, rig)
		box = r if not has else box.merge(r)
		has = true
	return box


## Модель + приціл: те, що має лишатися вільним від плити, коли юніт — ціль прев'ю.
static func with_crosshair(view: Node3D, rig: IsoCameraRig) -> Rect2:
	var box: Rect2 = of(view, rig)
	var ch := view.get_node_or_null("Crosshair") as VisualInstance3D
	if ch != null and ch.visible:
		box = box.merge(_project_aabb(ch, rig))
	return box


## Клітинка на екрані: охопний прямокутник чотирьох її кутів на площині землі.
static func cell_rect(cell: Vector2i, rig: IsoCameraRig) -> Rect2:
	var c: Vector3 = IsoCameraRig.cell_to_world(cell)
	var box := Rect2(rig.unproject(c + Vector3(-0.5, 0.0, -0.5)), Vector2.ZERO)
	for corner: Vector3 in [Vector3(0.5, 0.0, -0.5), Vector3(0.5, 0.0, 0.5), Vector3(-0.5, 0.0, 0.5)]:
		box = box.expand(rig.unproject(c + corner))
	return box


static func _project_aabb(vi: VisualInstance3D, rig: IsoCameraRig) -> Rect2:
	var aabb: AABB = vi.get_aabb()
	var xf: Transform3D = vi.global_transform
	var box := Rect2(rig.unproject(xf * aabb.get_endpoint(0)), Vector2.ZERO)
	for i in range(1, 8):
		box = box.expand(rig.unproject(xf * aabb.get_endpoint(i)))
	return box
