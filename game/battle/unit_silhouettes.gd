class_name UnitSilhouettes
extends RefCounted
## Тимчасові примітиви-заступники до асетів Фази 5.2: мінімум, що відрізняє 12 типів
## з фіксованого ізо-ракурсу. Ціна — кількість мешів (§8: <= 4 на юніт). Перед — -Z.

const _BARREL_COLOR := Color("2e2b27")  # нейтральний метал: колір гравця лише на корпусі
const _STRIPE_COLOR := Color("d9b23a")

## hull — розмір корпусу (1 тайл = 8 м, тож 3,6 м = 0,45); barrel — довжина ствола від центру
## корпусу/башти вперед (0 — без); extras — деталі. Ствол може виступати за корпус: у танка
## він 5–6 м від центру башти. Висота танка = корпус + башта (TURRET_HEIGHT = 0,8 м).
const _SPECS: Array[Dictionary] = [
	{"hull": Vector3(0.40, 0.05, 0.40), "barrel": 0.0, "extras": [&"figures"]},  # 0 стрілецький загін
	{"hull": Vector3(0.40, 0.05, 0.40), "barrel": 0.0, "extras": [&"figures", &"drone_rack"]},  # 1 штурмовий
	{"hull": Vector3(0.325, 0.30, 0.75), "barrel": 0.50, "extras": [&"wheels"]},  # 2 бронеавто 2,6×2,4×6,0 м
	{"hull": Vector3(0.375, 0.325, 0.875), "barrel": 0.0, "extras": [&"wheels"]},  # 3 транспортер 3,0×2,6×7,0 м
	{"hull": Vector3(0.30, 0.25, 0.625), "barrel": 0.0, "extras": [&"wheels"]},  # 4 розвідувальне 2,4×2,0×5,0 м
	{"hull": Vector3(0.45, 0.20, 0.875), "barrel": 0.69, "extras": [&"turret"]},  # 5 середній танк 3,6×2,4×7,0 м
	{"hull": Vector3(0.4375, 0.1875, 0.9375), "barrel": 0.75, "extras": [&"turret"]},  # 6 винищувач танків 3,5×2,3×7,5 м
	{"hull": Vector3(0.4125, 0.1875, 0.8125), "barrel": 0.625, "extras": [&"turret"]},  # 7 легкий танк 3,3×2,3×6,5 м
	{"hull": Vector3(0.475, 0.25, 0.90), "barrel": 0.75, "extras": [&"turret"]},  # 8 важкий танк 3,8×2,8×(корпус 7,2) м
	{"hull": Vector3(0.30, 0.225, 0.30), "barrel": 0.45, "extras": [&"trail"]},  # 9 польова гармата 2,4×1,8×5 м з лафетом
	{"hull": Vector3(0.325, 0.30, 0.35), "barrel": 0.45, "extras": [&"tall_barrel", &"trail"]},  # 10 гаубиця 2,6×2,4×6 м з лафетом
	{"hull": Vector3(0.425, 0.35, 0.875), "barrel": 0.0, "extras": [&"stripe"]},  # 11 інженерна машина 3,4×2,8×7,0 м
]

## Башта: 0,8 м заввишки.
const TURRET_HEIGHT: float = 0.10

static var _materials: Dictionary = {}
static var _figure_mesh: BoxMesh
static var _figure_material: StandardMaterial3D

## Фігура відділення: 1,8 × 0,5 м (1 тайл = 8 м). Колір дає екземпляр MultiMesh — живі в
## кольорі власника, загиблі темні (L* 20–28), тож уся четвірка — один виклик малювання.
const FIGURE_SIZE: Vector3 = Vector3(0.0625, 0.225, 0.05)
const FALLEN_COLOR: Color = Color("3a342c")
const _FIGURE_SLOTS: Array[Vector2] = [Vector2(-0.1, -0.09), Vector2(0.1, -0.1), Vector2(-0.09, 0.1), Vector2(0.11, 0.09)]


static func spec(type_id: int) -> Dictionary:
	return _SPECS[type_id]


## Матеріали спільні між усіма юнітами одного кольору (батчинг).
static func shared_material(color: Color) -> StandardMaterial3D:
	if not _materials.has(color):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		_materials[color] = mat
	return _materials[color]


static func build(type_id: int, owner_color: Color) -> Node3D:
	var s: Dictionary = spec(type_id)
	var hull_size: Vector3 = s.hull
	var extras: Array = s.extras
	var root := Node3D.new()
	var hull := _box(root, "Hull", hull_size, Vector3(0, hull_size.y * 0.5, 0), owner_color)

	var top := hull_size.y
	if extras.has(&"turret"):
		_box(root, "Turret", Vector3(hull_size.x * 0.6, TURRET_HEIGHT, hull_size.z * 0.5), Vector3(0, top + TURRET_HEIGHT * 0.5, 0), owner_color)
		top += TURRET_HEIGHT
	if extras.has(&"stripe"):
		_box(root, "Stripe", Vector3(hull_size.x + 0.01, 0.02, hull_size.z * 0.3), Vector3(0, hull_size.y + 0.01, 0), _STRIPE_COLOR)
	if extras.has(&"figures"):
		root.add_child(figures(4, owner_color))
	if extras.has(&"drone_rack"):
		_box(root, "DroneRack", Vector3(0.30, 0.10, 0.12), Vector3(0, hull_size.y + 0.05, hull_size.z * 0.5 - 0.06), _BARREL_COLOR)
	if extras.has(&"wheels"):
		# одна ширша плита під корпусом замість чотирьох коліс — економія мешів
		_box(root, "Wheels", Vector3(hull_size.x + 0.05, 0.10, hull_size.z * 0.75), Vector3(0, 0.05, 0), _BARREL_COLOR)
	if extras.has(&"trail"):
		# станина лафета позаду гармати: разом з корпусом дає 5–6 м довжини
		var trail_len: float = hull_size.z * 1.05
		_box(root, "Trail", Vector3(hull_size.x * 0.25, 0.03, trail_len), Vector3(0, 0.015, (hull_size.z + trail_len) * 0.5), _BARREL_COLOR)

	var barrel_len: float = s.barrel
	if barrel_len > 0.0:
		var tall: bool = extras.has(&"tall_barrel")
		var thick := 0.07 if tall else 0.05
		var y: float = hull_size.y * 0.5  # без башти ствол стирчить із корпусу
		if extras.has(&"turret"):
			y = top - TURRET_HEIGHT * 0.5
		elif tall:
			y = hull_size.y + 0.04
		_box(root, "Barrel", Vector3(thick, thick, barrel_len), Vector3(0, y, -barrel_len * 0.5), _BARREL_COLOR)
	return root


## Четвірка фігур одним MultiMesh: стоять перші `standing`, решта лежить на тих самих місцях.
static func figures(standing: int, owner_color: Color) -> MultiMeshInstance3D:
	if _figure_mesh == null:
		_figure_mesh = BoxMesh.new()
		_figure_mesh.size = FIGURE_SIZE
		_figure_material = StandardMaterial3D.new()
		_figure_material.vertex_color_use_as_albedo = true
		_figure_material.vertex_color_is_srgb = true
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _figure_mesh
	mm.instance_count = _FIGURE_SLOTS.size()
	var mi := MultiMeshInstance3D.new()
	mi.name = "Figures"
	mi.multimesh = mm
	mi.material_override = _figure_material
	set_standing(mi, standing, owner_color)
	return mi


## Загибла фігура лежить уздовж землі на своєму місці, ледь зсунута вбік: не стоїть і не
## здіймається над основою — загиблі не перешкода.
static func set_standing(mi: MultiMeshInstance3D, standing: int, owner_color: Color) -> void:
	var mm: MultiMesh = mi.multimesh
	for i in mm.instance_count:
		mm.set_instance_transform(i, figure_transform(i, i < standing))
		mm.set_instance_color(i, owner_color if i < standing else FALLEN_COLOR)


static func figure_transform(i: int, standing: bool) -> Transform3D:
	var slot: Vector2 = _FIGURE_SLOTS[i]
	if standing:
		return Transform3D(Basis(), Vector3(slot.x, 0.05 + FIGURE_SIZE.y * 0.5, slot.y))
	var b := Basis(Vector3.UP, float(i) * 1.3) * Basis(Vector3.RIGHT, PI * 0.5)
	return Transform3D(b, Vector3(slot.x * 1.2, 0.05 + FIGURE_SIZE.z * 0.5, slot.y * 1.2))


static func _box(parent: Node3D, node_name: String, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	m.mesh = mesh
	m.position = pos
	m.material_override = shared_material(color)
	parent.add_child(m)
	return m
