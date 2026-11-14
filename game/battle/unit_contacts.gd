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
## Сила плями слота, поставлена в дані екземпляра (.g): без неї шейдер мав би 0 і ховав би кожну пляму.
var _strength: Array[float] = []


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


## Скільки юнітів (не квадів) стежить за плямами.
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


## Квадів у слотах: юніт дає їх стільки, скільки `contact_slots()` (техніка — один, відділення — по
## бійцю), і всі вони — екземпляри того самого `MultiMesh`, тож виклик малювання один.
func _slot_count() -> int:
	var n: int = 0
	for v in _views:
		n += v.contact_slots()
	return n


func _resize() -> void:
	_terrain()
	var n: int = _slot_count()
	multimesh.instance_count = n
	_placed.clear()
	_placed.resize(n)
	_placed.fill(HIDDEN)
	_road.clear()
	_road.resize(n)
	_road.fill(-1.0)
	_strength.clear()
	_strength.resize(n)
	_strength.fill(0.0)
	for i in n:
		multimesh.set_instance_transform(i, HIDDEN)
	sync()


## Ставить квади за поточним станом юнітів; незмінені не чіпає, щоб нерухомий екран не будив кадр.
func sync() -> void:
	if _slot_count() != _placed.size():
		_resize()  # перев'язаний вигляд міг стати іншим типом, з іншим числом квадів
		return
	var slot: int = 0
	for view in _views:
		var road: float = 1.0 if _on_road(view) else 0.0
		var k: float = view.contact_strength()
		for xf: Transform3D in view.contact_transforms():
			if xf != _placed[slot] or road != _road[slot] or k != _strength[slot]:
				_placed[slot] = xf
				_road[slot] = road
				_strength[slot] = k
				multimesh.set_instance_transform(slot, xf)
				multimesh.set_instance_custom_data(slot, Color(road, k, 0.0, 0.0))
			slot += 1


## Сила плями слота відносно тіні техніки, як її поставлено в дані екземпляра.
func strength_of(slot: int) -> float:
	return _strength[slot]


## 1.0, коли юніт стоїть на асфальті (дорога чи міст), інакше 0.0; поставлене останньою синхронізацією.
func road_of(slot: int) -> float:
	return _road[slot]


## Рішення за клітинкою під юнітом: на узбіччі тієї ж клітинки пляма теж слабшає.
func _on_road(view: UnitView) -> bool:
	if map == null:
		return false
	var kind: int = map.outer_kind_at(IsoCameraRig.world_to_cell(view.position))
	return kind == Terrain.Kind.ROAD or kind == Terrain.Kind.BRIDGE


func _process(_delta: float) -> void:
	sync()
