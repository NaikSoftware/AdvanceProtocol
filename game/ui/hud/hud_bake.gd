class_name HudBake
extends Control
## Плита, що малюється одним викликом: справжні вузли (плита, підписи, значки, глиф броні) живуть у
## власному SubViewport і запікаються в текстуру лише коли вміст змінився, а екран малює цю текстуру.
## Причина: у каналі 2D кожен підпис іншого шрифту чи розміру, значок і рівна смужка — окремий
## draw call, бо їх текстури різні й не склеюються; плита прев'ю з глифом коштувала ~22 викликів,
## тег ~9 при бюджеті +8 на весь стан. Тут вони коштують по одному, а запікання — це кадр-два
## після зміни вмісту, не щокадру.
##
## Нащадок кладе вміст у `face` (PanelContainer з темою плити) і кличе request_bake() після кожної
## зміни, яку не видно з розміру (текст тієї ж ширини, інший сектор глифа). Мінімальний розмір
## хоста — мінімальний розмір `face`, тож розкладка ззовні не відрізняє його від PanelContainer.

## Текстура відповідає нинішньому вмісту: після запікання, до наступної зміни.
signal baked

var face: PanelContainer

var _vp: SubViewport
var _pending: bool = false


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_vp = SubViewport.new()
	_vp.transparent_bg = true
	_vp.disable_3d = true
	_vp.gui_disable_input = true
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.size = Vector2i(1, 1)
	add_child(_vp, false, Node.INTERNAL_MODE_FRONT)
	face = PanelContainer.new()
	face.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	face.minimum_size_changed.connect(_on_face_min_changed)
	_vp.add_child(face)


func _enter_tree() -> void:
	# SubViewport не передає тему вниз: беремо ту, що діє на хоста.
	var n: Node = get_parent()
	while n != null:
		if n is Control and (n as Control).theme != null:
			face.theme = (n as Control).theme
			break
		n = n.get_parent()
	request_bake()


func _get_minimum_size() -> Vector2:
	return face.get_combined_minimum_size()


## Розмір хоста змінюють ззовні; плита у viewport мусить мати той самий логічний розмір.
func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_fit()
	elif what == NOTIFICATION_VISIBILITY_CHANGED and is_visible_in_tree():
		request_bake()


func _fit() -> void:
	var logical := Vector2i(maxi(1, ceili(size.x)), maxi(1, ceili(size.y)))
	var scale: float = _pixel_scale()
	_vp.size = Vector2i(maxi(1, ceili(logical.x * scale)), maxi(1, ceili(logical.y * scale)))
	_vp.size_2d_override = logical
	_vp.size_2d_override_stretch = true
	face.position = Vector2.ZERO
	face.size = size
	request_bake()


func _pixel_scale() -> float:
	if not is_inside_tree():
		return 1.0
	var vp := get_viewport()
	return vp.get_final_transform().get_scale().x * get_global_transform_with_canvas().get_scale().x


func _on_face_min_changed() -> void:
	update_minimum_size()
	request_bake()


func is_baked() -> bool:
	return not _pending


## Запікає після того, як розкладка вмісту осіла: підпис, що змінив текст, міняє розмір лише
## на кінці кадру. Поки запікання не відбулося, хост нічого не малює — краще порожньо, ніж
## чужий текст попереднього юніта.
func request_bake() -> void:
	if _pending or not is_inside_tree():
		return
	_pending = true
	queue_redraw()
	_bake_later()


## Два кадри чекаємо сигналом із прив'язкою до себе, а не await: знищений хост тихо відписується,
## а await у знищеного екземпляра — помилка рушія.
func _bake_later(frames: int = 2) -> void:
	if frames > 0:
		get_tree().process_frame.connect(_bake_later.bind(frames - 1), CONNECT_ONE_SHOT)
		return
	_pending = false
	_fit_pixels()
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	queue_redraw()
	baked.emit()


## Масштаб екрана міг змінитися між запитом і запіканням (поворот, зміна вікна).
func _fit_pixels() -> void:
	var logical := Vector2i(maxi(1, ceili(size.x)), maxi(1, ceili(size.y)))
	var scale: float = _pixel_scale()
	_vp.size = Vector2i(maxi(1, ceili(logical.x * scale)), maxi(1, ceili(logical.y * scale)))


func _draw() -> void:
	if _pending:
		return
	draw_texture_rect(_vp.get_texture(), Rect2(Vector2.ZERO, Vector2(_vp.size_2d_override)), false)
