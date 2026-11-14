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
		var r: Rect2 = part_rect(vi, rig)
		box = r if not has else box.merge(r)
		has = true
	return box


## Модель + приціл: те, що має лишатися вільним від плити, коли юніт — ціль прев'ю.
static func with_crosshair(view: Node3D, rig: IsoCameraRig) -> Rect2:
	var box: Rect2 = of(view, rig)
	var ch := view.get_node_or_null("Crosshair") as VisualInstance3D
	if ch != null and ch.visible:
		box = box.merge(part_rect(ch, rig))
	return box


## Клітинка на екрані: охопний прямокутник чотирьох її кутів на площині землі.
static func cell_rect(cell: Vector2i, rig: IsoCameraRig) -> Rect2:
	var c: Vector3 = IsoCameraRig.cell_to_world(cell)
	var box := Rect2(rig.unproject(c + Vector3(-0.5, 0.0, -0.5)), Vector2.ZERO)
	for corner: Vector3 in [Vector3(0.5, 0.0, -0.5), Vector3(0.5, 0.0, 0.5), Vector3(-0.5, 0.0, 0.5)]:
		box = box.expand(rig.unproject(c + corner))
	return box


## Екранний прямокутник однієї частини юніта. Смуга HP, напис, значок дрона й приціл — білборди:
## на екрані вони завжди повернуті до камери, тож їхній AABB, спроєктований як є, виходить
## вужчим за намальоване (і міняється від повороту юніта). Для них проєкція — центр ± пів-розміру
## вздовж осей камери; для моделі — кути AABB.
static func part_rect(vi: VisualInstance3D, rig: IsoCameraRig) -> Rect2:
	var camera: Camera3D = vi.get_viewport().get_camera_3d() if vi.is_inside_tree() else null
	var billboard: bool = (vi is Sprite3D or vi is Label3D) and camera != null \
			and int(vi.get("billboard")) != BaseMaterial3D.BILLBOARD_DISABLED
	if not billboard:
		return _project_aabb(vi, rig)
	var xf: Transform3D = vi.global_transform
	var scale: Vector3 = xf.basis.get_scale()
	var size: Vector2 = _billboard_size(vi)
	var centre: Vector3 = xf.origin
	var right: Vector3 = camera.global_transform.basis.x.normalized() * size.x * 0.5 * scale.x
	var up: Vector3 = camera.global_transform.basis.y.normalized() * size.y * 0.5 * scale.y
	var box := Rect2(rig.unproject(centre + right + up), Vector2.ZERO)
	for corner: Vector3 in [centre + right - up, centre - right + up, centre - right - up]:
		box = box.expand(rig.unproject(corner))
	return box


## Світовий розмір білборда з його власних даних (текстура × pixel_size; текст × pixel_size), а не з
## get_aabb(): без рендерера (headless) AABB порожній, а розмір має бути той самий, що малює рушій.
static func _billboard_size(vi: VisualInstance3D) -> Vector2:
	if vi is Sprite3D:
		var sprite := vi as Sprite3D
		return (sprite.texture.get_size() if sprite.texture != null else Vector2.ZERO) * sprite.pixel_size
	var label := vi as Label3D
	var font: Font = label.font if label.font != null else ThemeDB.fallback_font
	var text_size: Vector2 = font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, label.font_size)
	return (text_size + Vector2.ONE * float(label.outline_size) * 2.0) * label.pixel_size


static func _project_aabb(vi: VisualInstance3D, rig: IsoCameraRig) -> Rect2:
	var aabb: AABB = vi.get_aabb()
	var xf: Transform3D = vi.global_transform
	var box := Rect2(rig.unproject(xf * aabb.get_endpoint(0)), Vector2.ZERO)
	for i in range(1, 8):
		box = box.expand(rig.unproject(xf * aabb.get_endpoint(i)))
	return box
