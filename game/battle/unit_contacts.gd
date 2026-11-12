class_name UnitContacts
extends MultiMeshInstance3D
## Тіні-контакт усіх юнітів екрана одним MultiMesh: окремий прозорий квад на юніта коштував виклик
## малювання на кожного (§8). Юніт (`UnitView`) лише віддає свій перетворений квад
## (`contact_transform`); тут вони збираються й оновлюються, щойно хтось зрушив.

const _SHADER: Shader = preload("res://game/battle/shaders/unit_contact_shadow.gdshader")
## Вершини кваду: на пагорбі шейдер кладе їх на рельєф, і ґрунт плями не ріже.
const SUBDIVIDE: int = 5
## Схований екземпляр — вироджений квад: MultiMesh не вміє ховати окремий екземпляр.
const HIDDEN := Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)

static var _material: ShaderMaterial

## Карта: на асфальті (ROAD) пляма слабшає — на темному покритті вона йшла б майже в чорне.
var map: MapData = null

var _views: Array[UnitView] = []
var _placed: Array[Transform3D] = []
var _road: Array[float] = []


func _init() -> void:
	name = "UnitContacts"
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Шар юнітів поза маскою зонда відбиття (§3.5), як і сам юніт.
	layers = 1 << (UnitView.UNIT_LAYER - 1)
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE
	plane.subdivide_width = SUBDIVIDE
	plane.subdivide_depth = SUBDIVIDE
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = plane
	# AABB з екземплярів MultiMesh не відсікає пляму на краю кадру помилково.
	custom_aabb = AABB(Vector3(-200.0, -20.0, -200.0), Vector3(400.0, 40.0, 400.0))
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = _SHADER
	material_override = _material
	set_process(false)


func count() -> int:
	return _views.size()


## Останній поставлений квад слоту — з нього тести читають те, що під headless із MultiMesh не прочитати.
func transform_of(slot: int) -> Transform3D:
	return _placed[slot]


func is_shown(slot: int) -> bool:
	return _placed[slot] != HIDDEN


func track(view: UnitView) -> void:
	if _views.has(view):
		sync()  # повторний bind() міг змінити тип юніта, а з ним і слід
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


## Рельєф під плямою — з активної карти висот (як і раніше в плями на вузлі юніта).
func _terrain() -> void:
	var th: TerrainHeight = TerrainHeight.active
	_material.set_shader_parameter("use_height", th != null)
	if th != null:
		_material.set_shader_parameter("height_map", th.texture())
		_material.set_shader_parameter("height_samples", float(th.samples))
		_material.set_shader_parameter("height_origin", -0.5 - th.margin)


func _resize() -> void:
	_terrain()
	multimesh.instance_count = _views.size()
	_placed.clear()
	_placed.resize(_views.size())
	_placed.fill(HIDDEN)
	_road.clear()
	_road.resize(_views.size())
	_road.fill(0.0)
	for i in _views.size():
		multimesh.set_instance_transform(i, HIDDEN)
	sync()


## Ставить квади за поточним станом юнітів; незмінені не чіпає, щоб нерухомий екран не будив кадр.
func sync() -> void:
	for i in _views.size():
		var xf: Transform3D = _views[i].contact_transform()
		var road: float = 1.0 if _on_road(_views[i]) else 0.0
		if xf != _placed[i] or road != _road[i]:
			_placed[i] = xf
			_road[i] = road
			multimesh.set_instance_transform(i, xf)
			multimesh.set_instance_custom_data(i, Color(road, 0.0, 0.0, 0.0))


func _on_road(view: UnitView) -> bool:
	return map != null and map.outer_kind_at(IsoCameraRig.world_to_cell(view.position)) == Terrain.Kind.ROAD


func _process(_delta: float) -> void:
	sync()
