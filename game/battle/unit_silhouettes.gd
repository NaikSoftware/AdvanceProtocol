class_name UnitSilhouettes
extends RefCounted
## Тимчасові примітиви-заступники до асетів Фази 5.2: мінімум, що відрізняє 12 типів
## з фіксованого ізо-ракурсу. Ціна — кількість мешів (§8: <= 4 на юніт). Перед — -Z.

const _BARREL_COLOR := Color("2e2b27")  # нейтральний метал: колір гравця лише на корпусі
const _STRIPE_COLOR := Color("d9b23a")

## hull — розмір корпусу; barrel — довжина ствола (0 — без); extras — деталі.
## Кінчик ствола завжди на z = -0.5, тож увесь силует влазить в один тайл.
const _SPECS: Array[Dictionary] = [
	{"hull": Vector3(0.40, 0.35, 0.40), "barrel": 0.0, "extras": []},  # 0 стрілецький загін
	{"hull": Vector3(0.40, 0.35, 0.40), "barrel": 0.0, "extras": [&"drone_rack"]},  # 1 штурмовий
	{"hull": Vector3(0.55, 0.30, 0.85), "barrel": 0.30, "extras": [&"wheels"]},  # 2 бронеавто
	{"hull": Vector3(0.62, 0.38, 0.90), "barrel": 0.0, "extras": [&"wheels"]},  # 3 транспортер
	{"hull": Vector3(0.45, 0.25, 0.75), "barrel": 0.0, "extras": [&"wheels"]},  # 4 розвідувальне
	{"hull": Vector3(0.66, 0.40, 0.74), "barrel": 0.40, "extras": [&"turret"]},  # 5 середній танк
	{"hull": Vector3(0.64, 0.36, 0.80), "barrel": 0.55, "extras": [&"turret"]},  # 6 винищувач танків
	{"hull": Vector3(0.55, 0.34, 0.70), "barrel": 0.30, "extras": [&"turret"]},  # 7 легкий танк
	{"hull": Vector3(0.72, 0.46, 0.86), "barrel": 0.45, "extras": [&"turret"]},  # 8 важкий танк
	{"hull": Vector3(0.45, 0.30, 0.50), "barrel": 0.70, "extras": [&"spade"]},  # 9 польова гармата
	{"hull": Vector3(0.50, 0.35, 0.50), "barrel": 0.70, "extras": [&"tall_barrel"]},  # 10 гаубиця
	{"hull": Vector3(0.60, 0.40, 0.60), "barrel": 0.0, "extras": [&"stripe"]},  # 11 інженерна машина
]

static var _materials: Dictionary = {}


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
		_box(root, "Turret", Vector3(hull_size.x * 0.6, 0.14, hull_size.z * 0.5), Vector3(0, top + 0.07, 0), owner_color)
		top += 0.14
	if extras.has(&"stripe"):
		_box(root, "Stripe", Vector3(hull_size.x + 0.02, 0.04, hull_size.z * 0.3), Vector3(0, hull_size.y + 0.02, 0), _STRIPE_COLOR)
	if extras.has(&"drone_rack"):
		_box(root, "DroneRack", Vector3(0.30, 0.10, 0.12), Vector3(0, hull_size.y + 0.05, hull_size.z * 0.5 - 0.06), _BARREL_COLOR)
	if extras.has(&"wheels"):
		# одна ширша плита під корпусом замість чотирьох коліс — економія мешів
		_box(root, "Wheels", Vector3(hull_size.x + 0.10, 0.12, hull_size.z * 0.75), Vector3(0, 0.06, 0), _BARREL_COLOR)
	if extras.has(&"spade"):
		_box(root, "Spade", Vector3(hull_size.x, 0.20, 0.06), Vector3(0, 0.10, hull_size.z * 0.5), _BARREL_COLOR)

	var barrel_len: float = s.barrel
	if barrel_len > 0.0:
		var tall: bool = extras.has(&"tall_barrel")
		var thick := 0.14 if tall else 0.10
		var y: float = hull_size.y * 0.5  # без башти ствол стирчить із корпусу
		if extras.has(&"turret"):
			y = top - 0.07
		elif tall:
			y = hull_size.y + 0.15
		_box(root, "Barrel", Vector3(thick, thick, barrel_len), Vector3(0, y, -0.5 + barrel_len * 0.5), _BARREL_COLOR)
	return root


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
