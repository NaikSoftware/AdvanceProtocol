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
		if vi == null or not vi.visible or _empty_mesh(vi):
			continue
		var r: Rect2 = part_rect(vi, rig)
		box = r if not has else box.merge(r)
		has = true
	return box


## Сітка без поверхонь (відділення, в якого не лишилось стоячих): на екрані нічого, а опукла оболонка
## порожнього мешу — помилка рушія.
static func _empty_mesh(vi: VisualInstance3D) -> bool:
	return vi is MeshInstance3D and ((vi as MeshInstance3D).mesh == null or (vi as MeshInstance3D).mesh.get_surface_count() == 0)


## Модель + приціл: те, що має лишатися вільним від плити, коли юніт — ціль прев'ю.
static func with_crosshair(view: Node3D, rig: IsoCameraRig) -> Rect2:
	var box: Rect2 = of(view, rig)
	var ch := view.get_node_or_null("Crosshair") as VisualInstance3D
	if ch != null and ch.visible:
		box = box.merge(part_rect(ch, rig))
	return box


## Юніт разом з усіма позначками на ньому (приціл, хрест, загроза, загроза дрона): тег обходить їх
## як перешкоду. Лише видимі — сховані на екрані нічого не закривають.
static func with_marks(view: Node3D, rig: IsoCameraRig) -> Rect2:
	var box: Rect2 = of(view, rig)
	for mark_name: String in ["Crosshair", "Forbidden", "Threatened", "DroneThreatened"]:
		var mark := view.get_node_or_null(mark_name) as VisualInstance3D
		if mark != null and mark.visible:
			box = box.merge(part_rect(mark, rig))
	return box


## Екранний прямокутник напису HP, як його малює рушій; порожній, якщо напису не видно.
static func label_rect(view: Node3D, rig: IsoCameraRig) -> Rect2:
	var n := view.get_node_or_null("HpLabel") as VisualInstance3D
	return part_rect(n, rig) if n != null and n.visible else Rect2()


## Смуга HP + модель без напису й значка дрона: сюди дістає лідер тега (повітря навколо напису
## читалося б як належне сусідові).
static func core(view: Node3D, rig: IsoCameraRig) -> Rect2:
	var box := Rect2()
	var has: bool = false
	var parts: Array[Node] = []
	var sil: Node = view.get_node_or_null("Silhouette")
	if sil != null:
		for n in sil.find_children("*", "VisualInstance3D", true, false):
			parts.append(n)
	var bar: Node = view.get_node_or_null("HpBar")
	if bar != null:
		parts.append(bar)
	for n in parts:
		var vi := n as VisualInstance3D
		if vi == null or not vi.visible or _empty_mesh(vi):
			continue
		var r: Rect2 = part_rect(vi, rig)
		box = r if not has else box.merge(r)
		has = true
	return box


## Силует смуги HP + моделі як опукла оболонка екранних точок: кінець лідера лягає на справжній
## контур, а не на кут охопного прямокутника, де юніта немає.
static func core_poly(view: Node3D, rig: IsoCameraRig) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var sil: Node = view.get_node_or_null("Silhouette")
	if sil != null:
		for n in sil.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if mi.visible and mi.mesh != null:
				for p: Vector3 in _hull_points(mi.mesh):
					pts.append(rig.unproject(mi.global_transform * p))
	var bar := view.get_node_or_null("HpBar") as VisualInstance3D
	if bar != null and bar.visible:
		var r: Rect2 = part_rect(bar, rig)
		pts.append_array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	return Geometry2D.convex_hull(pts)


## Кут клітинки у світі там, де його малює дошка: на мосту — на висоті настилу (контур клітинки мосту
## лежить над руслом), інакше на землі. Площина землі зсунула б позначку клітинки мосту вниз екраном.
static func corner_world(cell: Vector2i, corner: Vector2) -> Vector3:
	var x: float = cell.x + corner.x
	var z: float = cell.y + corner.y
	var th: TerrainHeight = TerrainHeight.active
	if th != null and th.is_deck(cell):
		return Vector3(x, th.deck_y(cell), z)
	return Vector3(x, TerrainHeight.ground_y(x, z), z)


## Клітинка на екрані: охопний прямокутник чотирьох її кутів.
static func cell_rect(cell: Vector2i, rig: IsoCameraRig) -> Rect2:
	var poly: PackedVector2Array = cell_poly(cell, rig)
	var box := Rect2(poly[0], Vector2.ZERO)
	for v in poly:
		box = box.expand(v)
	return box


## Чотири кути клітинки на екрані (за годинниковою) — полігон для перешкод тега.
static func cell_poly(cell: Vector2i, rig: IsoCameraRig) -> PackedVector2Array:
	var out := PackedVector2Array()
	for corner: Vector2 in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)]:
		out.append(rig.unproject(corner_world(cell, corner)))
	return out


## Екранний прямокутник однієї частини юніта. Смуга HP, напис, значок дрона й приціл — білборди:
## на екрані вони завжди повернуті до камери, тож їхній AABB, спроєктований як є, виходить
## вужчим за намальоване (і міняється від повороту юніта). Для них проєкція — центр ± пів-розміру
## вздовж осей камери; для моделі — кути AABB.
static func part_rect(vi: VisualInstance3D, rig: IsoCameraRig) -> Rect2:
	var camera: Camera3D = vi.get_viewport().get_camera_3d() if vi.is_inside_tree() else null
	var billboard: bool = (vi is Sprite3D or vi is Label3D) and camera != null \
			and int(vi.get("billboard")) != BaseMaterial3D.BILLBOARD_DISABLED
	if not billboard:
		return _project_mesh(vi, rig) if vi is MeshInstance3D and (vi as MeshInstance3D).mesh != null else _project_aabb(vi, rig)
	var xf: Transform3D = vi.global_transform
	var scale: Vector3 = xf.basis.get_scale()
	var size: Vector2 = _billboard_size(vi)
	var cam_x: Vector3 = camera.global_transform.basis.x.normalized()
	var cam_y: Vector3 = camera.global_transform.basis.y.normalized()
	# offset (у пікселях текстури чи тексту) зсуває намальоване від вузла: значок дронів стоїть над
	# числом HP лише завдяки йому, і без зсуву тег ліг би на його точки.
	var off: Vector2 = (vi.get("offset") as Vector2) * float(vi.get("pixel_size"))
	var centre: Vector3 = xf.origin + cam_x * off.x * scale.x + cam_y * off.y * scale.y
	var right: Vector3 = cam_x * size.x * 0.5 * scale.x
	var up: Vector3 = cam_y * size.y * 0.5 * scale.y
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
	# Видно лише цифри: висота рядка й обводка — порожнє поле, від якого тег «відсувався» на око.
	return Vector2(text_size.x, float(label.font_size) * DIGIT_HEIGHT) * label.pixel_size


## Висота цифр відносно кегля: рядок шрифту вищий за видимі цифри.
const DIGIT_HEIGHT: float = 0.72

## Опуклі оболонки сіток: рахуються раз на сітку, бо кадр не мусить обходити всі її вершини.
static var _hulls: Dictionary = {}


static func _hull_points(mesh: Mesh) -> PackedVector3Array:
	var key: int = mesh.get_instance_id()
	if not _hulls.has(key):
		var shape: ConvexPolygonShape3D = mesh.create_convex_shape(true, true)
		_hulls[key] = shape.points if shape != null else PackedVector3Array()
	return _hulls[key]


## Силует моделі: екранні межі точок її опуклої оболонки, а не восьми кутів AABB, що завищує
## габарит куточками, де моделі немає. Порожня оболонка — повернення до AABB.
static func _project_mesh(vi: MeshInstance3D, rig: IsoCameraRig) -> Rect2:
	var pts: PackedVector3Array = _hull_points(vi.mesh)
	if pts.is_empty():
		return _project_aabb(vi, rig)
	var xf: Transform3D = vi.global_transform
	var box := Rect2(rig.unproject(xf * pts[0]), Vector2.ZERO)
	for i in range(1, pts.size()):
		box = box.expand(rig.unproject(xf * pts[i]))
	return box


static func _project_aabb(vi: VisualInstance3D, rig: IsoCameraRig) -> Rect2:
	var aabb: AABB = vi.get_aabb()
	var xf: Transform3D = vi.global_transform
	var box := Rect2(rig.unproject(xf * aabb.get_endpoint(0)), Vector2.ZERO)
	for i in range(1, 8):
		box = box.expand(rig.unproject(xf * aabb.get_endpoint(i)))
	return box
