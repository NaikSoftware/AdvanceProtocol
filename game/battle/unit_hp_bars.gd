class_name UnitHpBars
extends MultiMeshInstance3D
## Смуги HP усіх юнітів екрана одним MultiMesh: окремий спрайт із прозорою текстурою на юніта
## коштував виклик малювання на кожного (§8). Юніт (`UnitView`) віддає лише стан смуги — шар за
## шириною заливки, точку над собою й чи показувати; тут ці стани збираються й оновлюються, щойно
## хтось змінився. Спрайт `HpBar` лишається в юніті вузлом стану, але сам не малюється.

const _SHADER: Shader = preload("res://game/battle/shaders/unit_hp_bar.gdshader")

static var _material: ShaderMaterial
static var _layers: Texture2DArray

var _views: Array[UnitView] = []
var _placed: Array[Vector3] = []
var _layer: PackedInt32Array = PackedInt32Array()
var _shown: Array[bool] = []


func _init() -> void:
	name = "UnitHpBars"
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	layers = 1 << (UnitView.UNIT_LAYER - 1)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = quad
	# Білборд у шейдері: AABB з екземплярів не відсікає смугу на краю кадру помилково.
	custom_aabb = AABB(Vector3(-200.0, -20.0, -200.0), Vector3(400.0, 40.0, 400.0))
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = _SHADER
		_material.set_shader_parameter("bars", _layer_array())
		_material.render_priority = UnitView.OVERLAY_PRIORITY
	material_override = _material
	set_process(false)


## Шарів у масиві: по одному на ширину заливки 0…внутрішня ширина смуги.
static func layer_count() -> int:
	return UnitView._HP_BAR_SIZE.x - 2 + 1


static func layer_image(fill_width: int) -> Image:
	return UnitView.hp_bar_image(fill_width)


static func _layer_array() -> Texture2DArray:
	if _layers == null:
		var images: Array[Image] = []
		for w in layer_count():
			images.append(layer_image(w))
		_layers = Texture2DArray.new()
		_layers.create_from_images(images)
	return _layers


func count() -> int:
	return _views.size()


## Шар, позиція й показ слоту — з них тести читають те, що під headless із MultiMesh не прочитати.
func layer_of(slot: int) -> int:
	return _layer[slot]


func position_of(slot: int) -> Vector3:
	return _placed[slot]


func is_shown(slot: int) -> bool:
	return _shown[slot]


func track(view: UnitView) -> void:
	if _views.has(view):
		sync()
		return
	_views.append(view)
	_resize()
	set_process(true)


func untrack(view: UnitView) -> void:
	if not _views.has(view):
		return
	_views.erase(view)
	_resize()
	set_process(not _views.is_empty())


func _resize() -> void:
	multimesh.instance_count = _views.size()
	_placed.clear()
	_placed.resize(_views.size())
	_placed.fill(Vector3.INF)
	_layer.resize(_views.size())
	_layer.fill(-1)
	_shown.clear()
	_shown.resize(_views.size())
	_shown.fill(false)
	sync()


## Ставить смуги за поточним станом юнітів; незмінені не чіпає, щоб нерухомий екран не будив кадр.
func sync() -> void:
	for i in _views.size():
		var v: UnitView = _views[i]
		var at: Vector3 = v.hp_bar_world()
		var layer: int = v.hp_bar_layer()
		var shown: bool = v.hp_bar_shown()
		if at != _placed[i] or layer != _layer[i] or shown != _shown[i]:
			_placed[i] = at
			_layer[i] = layer
			_shown[i] = shown
			multimesh.set_instance_transform(i, Transform3D(Basis(), at))
			multimesh.set_instance_custom_data(i, Color(float(layer), 0.0 if shown else 1.0, 0.0, 0.0))


func _process(_delta: float) -> void:
	sync()
