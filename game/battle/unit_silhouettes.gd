class_name UnitSilhouettes
extends RefCounted
## Тимчасові примітиви-заступники до асетів Фази 5.2: мінімум, що відрізняє 12 типів
## з фіксованого ізо-ракурсу. Ціна — кількість мешів (§8: <= 4 на юніт). Перед — -Z.

## Єдиний колір тіла для всіх власників: сторону показує смуга HP, не фарба юніта.
const BODY_COLOR := Color("4f5240")
const _BARREL_COLOR := Color("2e2b27")  # нейтральний метал
const _STRIPE_COLOR := Color("d9b23a")

## hull — розмір корпусу (1 тайл = 8 м, тож 3,6 м = 0,45); barrel — довжина ствола від центру
## корпусу/башти вперед (0 — без); extras — деталі. Ствол може виступати за корпус: у танка
## він 3,5–7 м від центру тайла. Висота танка = корпус + башта (TURRET_HEIGHT = 0,8 м).
const _SPECS: Array[Dictionary] = [
	{"hull": Vector3(0.40, 0.05, 0.40), "barrel": 0.0, "extras": [&"figures"]},  # 0 стрілецький загін
	{"hull": Vector3(0.40, 0.05, 0.40), "barrel": 0.0, "extras": [&"figures", &"drone_rack"]},  # 1 штурмовий
	{"hull": Vector3(0.325, 0.30, 0.75), "barrel": 0.50, "wheel": 0.06, "extras": [&"wheels"]},  # 2 бронеавто 2,6×2,4×6,0 м
	{"hull": Vector3(0.375, 0.325, 0.875), "barrel": 0.0, "wheel": 0.06, "extras": [&"wheels"]},  # 3 транспортер 3,0×2,6×7,0 м
	{"hull": Vector3(0.30, 0.25, 0.625), "barrel": 0.0, "wheel": 0.06, "extras": [&"wheels"]},  # 4 розвідувальне 2,4×2,0×5,0 м
	{"hull": Vector3(0.43, 0.20, 0.84), "barrel": 0.625, "wheel": 0.036, "extras": [&"turret"]},  # 5 середній танк 3,4×2,4×6,7 м
	{"hull": Vector3(0.4375, 0.1875, 0.9375), "barrel": 0.86, "wheel": 0.045, "extras": [&"turret"]},  # 6 винищувач танків 3,5×2,3×7,5 м
	{"hull": Vector3(0.3675, 0.1875, 0.70), "barrel": 0.46, "wheel": 0.034, "extras": [&"turret"]},  # 7 легкий танк 2,9×2,3×5,6 м
	{"hull": Vector3(0.475, 0.25, 0.90), "barrel": 0.75, "wheel": 0.039, "extras": [&"turret"]},  # 8 важкий танк 3,8×2,8×(корпус 7,2) м
	{"hull": Vector3(0.30, 0.225, 0.30), "barrel": 0.45, "wheel": 0.06, "extras": [&"trail"]},  # 9 польова гармата 2,4×1,8×5 м з лафетом
	{"hull": Vector3(0.325, 0.30, 0.35), "barrel": 0.45, "wheel": 0.06, "extras": [&"tall_barrel", &"trail"]},  # 10 гаубиця 2,6×2,4×6 м з лафетом
	{"hull": Vector3(0.425, 0.35, 0.875), "barrel": 0.0, "wheel": 0.06, "extras": [&"stripe"]},  # 11 інженерна машина 3,4×2,8×7,0 м
]

## Башта: 0,8 м заввишки.
const TURRET_HEIGHT: float = 0.10

## Справжні моделі (docs/art-direction.md, «Unit models»): є файл — тіло з нього, нема — коробки.
## `_SPECS` лишаються метаданими для спалахів, уламків і плям тіні. `wheel` — радіус коліс моделі.
const MODEL_DIR: String = "res://assets/units/"
## Три набори техніки; набір 0 — моделі й `_SPECS` вище, набори 1 і 2 — у підкаталогах set1/, set2/.
const SET_COUNT: int = 3
## Виміри наборів: набір → {тип → рядок як у `_SPECS`}. Модель набору діє лише разом із рядком —
## без нього тип повністю береться з набору 0; тож рядок додають у тому самому коміті, що й GLB.
const _SET_SPECS: Dictionary = {
	1: {
		# важкий танк набору 1: корпус і висота осі ствола виміряні з моделі, дуло й колесо — як у _SPECS
		8: {"hull": Vector3(0.4793, 0.1903, 0.8877), "barrel": 0.75, "wheel": 0.039, "extras": [&"turret"]},
		# середній: корпус і висота осі ствола виміряні з моделі; дуло коротше за _SPECS, щоб відрізнятися від важкого
		5: {"hull": Vector3(0.4260, 0.1605, 0.7830), "barrel": 0.61, "wheel": 0.036, "extras": [&"turret"]},
		# винищувач: без башти, але extras як у _SPECS
		6: {"hull": Vector3(0.4299, 0.2238, 0.8971), "barrel": 0.86, "wheel": 0.045, "extras": [&"turret"]},
		# легкий: корпус вужчий за коробку, бо джерело довше за свою ширину; вісь ствола виміряна
		7: {"hull": Vector3(0.3390, 0.1705, 0.7020), "barrel": 0.46, "wheel": 0.034, "extras": [&"turret"]},
	},
	2: {
		5: {"hull": Vector3(0.4261, 0.159, 0.8433), "barrel": 0.625, "wheel": 0.036, "extras": [&"turret"]},  # середній (набір 2) 3,4×6,7 м
		6: {"hull": Vector3(0.4350, 0.187, 0.9423), "barrel": 0.86, "wheel": 0.045, "extras": [&"turret"]},  # винищувач (набір 2) 3,5×7,6 м
		7: {"hull": Vector3(0.3585, 0.153, 0.705), "barrel": 0.46, "wheel": 0.034, "extras": [&"turret"]},  # легкий (набір 2) 2,9×5,6 м
		8: {"hull": Vector3(0.4712, 0.175, 0.9031), "barrel": 0.75, "wheel": 0.0391, "extras": [&"turret"]},  # важкий (набір 2) 3,8×7,2 м
	},
}
## Чинні рядки: таблиця вище, а тести підміняють їх через `use_set_specs()`.
static var _set_specs: Dictionary = _SET_SPECS.duplicate(true)
const MODEL_SLUGS: Array[String] = [
	"rifle_soldier", "assault_soldier", "armoured_car", "troop_carrier", "scout_car", "medium_tank",
	"tank_destroyer", "light_tank", "heavy_tank", "field_gun", "howitzer", "engineer_vehicle",
]
const _MODEL_SHADER: Shader = preload("res://game/battle/shaders/unit_model.gdshader")
## Сітка моделі за (набір, тип) у системі юніта (null — файлу нема); у відділення — одна фігура.
static var _models: Dictionary = {}
## Тести підставляють сітки самі: тоді типи поза словником — без моделі, диск не читається.
static var _models_pinned: bool = false
static var _model_materials: Dictionary = {}

static var _materials: Dictionary = {}
## Злита сітка тіла за типом і кольором власника: один меш на всі юніти того самого вигляду.
static var _merged_meshes: Dictionary = {}
static var _merged_material: StandardMaterial3D
static var _figure_mesh: BoxMesh
static var _figure_material: StandardMaterial3D

## Фігура відділення: 1,8 × 0,5 м (1 тайл = 8 м). Колір дає екземпляр MultiMesh — живі в
## кольорі власника, загиблі темні (L* 20–28), тож уся четвірка — один виклик малювання.
const FIGURE_SIZE: Vector3 = Vector3(0.0625, 0.225, 0.05)
const FALLEN_COLOR: Color = Color("3a342c")
const _FIGURE_SLOTS: Array[Vector2] = [Vector2(-0.1, -0.09), Vector2(0.1, -0.1), Vector2(-0.09, 0.1), Vector2(0.11, 0.09)]


## Кінчик ствола в локальних координатах юніта: звідси вилітає спалах.
static func muzzle(type_id: int, set_id: int = 0) -> Vector3:
	return Vector3(0.0, barrel_y(type_id, set_id), -float(spec(type_id, set_id).barrel))


## Висота осі ствола: у башті — посередині неї, у гаубиці — над станиною, інакше — з корпусу.
static func barrel_y(type_id: int, set_id: int = 0) -> float:
	var s: Dictionary = spec(type_id, set_id)
	var h: float = (s.hull as Vector3).y
	var extras: Array = s.extras
	if extras.has(&"turret"):
		return h + TURRET_HEIGHT * 0.5
	return h + 0.04 if extras.has(&"tall_barrel") else h * 0.5


## Рядок набору діє лише разом з його моделлю: без неї тип — це модель і рядок набору 0.
static func spec(type_id: int, set_id: int = 0) -> Dictionary:
	var resolved: int = _resolved_set(type_id, set_id)
	return _SPECS[type_id] if resolved == 0 else (_set_specs[resolved] as Dictionary)[type_id]


## Набір — це місце гравця: власник 4 носить набір 1.
static func set_of(owner: int) -> int:
	return owner % SET_COUNT


## Матеріали спільні між усіма юнітами одного кольору (батчинг).
static func shared_material(color: Color) -> StandardMaterial3D:
	if not _materials.has(color):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		_materials[color] = mat
	return _materials[color]


static func build(type_id: int, set_id: int = 0) -> Node3D:
	var s: Dictionary = spec(type_id, set_id)
	var hull_size: Vector3 = s.hull
	var extras: Array = s.extras
	var root := Node3D.new()
	var hull := _box(root, "Hull", hull_size, Vector3(0, hull_size.y * 0.5, 0), BODY_COLOR)

	var top := hull_size.y
	if extras.has(&"turret"):
		_box(root, "Turret", Vector3(hull_size.x * 0.6, TURRET_HEIGHT, hull_size.z * 0.5), Vector3(0, top + TURRET_HEIGHT * 0.5, 0), BODY_COLOR)
		top += TURRET_HEIGHT
	if extras.has(&"stripe"):
		_box(root, "Stripe", Vector3(hull_size.x + 0.01, 0.02, hull_size.z * 0.3), Vector3(0, hull_size.y + 0.01, 0), _STRIPE_COLOR)
	if extras.has(&"figures"):
		root.add_child(figures(4, BODY_COLOR))
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
		_box(root, "Barrel", Vector3(thick, thick, barrel_len), Vector3(0, barrel_y(type_id, set_id), -barrel_len * 0.5), _BARREL_COLOR)
	return root


## Той самий силует, але корпус, башта, ствол, ходова й фігури відділення — одна сітка `Hull` з
## кольорами у вершинах (однаковими для всіх власників):
## один виклик малювання й один у тіні замість трьох-п'яти на юніт (§8). `standing` — скільки
## фігур стоїть, решта лежить.
static func build_merged(type_id: int, standing: int = -1, set_id: int = 0) -> Node3D:
	var hull := MeshInstance3D.new()
	hull.name = "Hull"
	hull.mesh = merged_mesh(type_id, standing, set_id)
	if has_model(type_id, set_id):
		hull.material_override = model_material(type_id, set_id)
	else:
		hull.material_override = _merged_mat()
	var out := Node3D.new()
	out.add_child(hull)
	return out


static func _merged_mat() -> StandardMaterial3D:
	if _merged_material == null:
		_merged_material = StandardMaterial3D.new()
		_merged_material.vertex_color_use_as_albedo = true
		_merged_material.vertex_color_is_srgb = true
	return _merged_material


## Сітка тіла на тип і кількість стоячих фігур; спільна для всіх юнітів того
## самого вигляду, тож падіння фігури — підміна сітки, а не нова.
static func merged_mesh(type_id: int, standing: int = -1, set_id: int = 0) -> ArrayMesh:
	var has_figures: bool = (spec(type_id, set_id).extras as Array).has(&"figures")
	var up: int = _FIGURE_SLOTS.size() if standing < 0 else clampi(standing, 0, _FIGURE_SLOTS.size())
	var model: ArrayMesh = model_mesh(type_id, set_id)
	if model != null and not has_figures:
		return model
	var key := "%d:%d:%s:%d" % [_resolved_set(type_id, set_id), type_id, "model" if model != null else "box", up if has_figures else 0]
	if _merged_meshes.has(key):
		return _merged_meshes[key]
	if model != null:
		# Четверо бійців на місцях коробок-фігур: ступні там, де був низ коробки.
		var feet := Transform3D(Basis(), Vector3(0.0, -FIGURE_SIZE.y * 0.5, 0.0))
		var xfs: Array[Transform3D] = []
		for i in _FIGURE_SLOTS.size():
			xfs.append(figure_transform(i, i < up) * feet)
		_merged_meshes[key] = _merge_model(model, xfs)
		return _merged_meshes[key]
	var root := build(type_id, set_id)
	var pieces: Array[Array] = []  ## [масиви сітки, перетворення, колір]
	for part: Node in root.get_children():
		if part is MeshInstance3D:
			var mi := part as MeshInstance3D
			pieces.append([mi.mesh.surface_get_arrays(0), Transform3D(Basis(), mi.position), (mi.material_override as StandardMaterial3D).albedo_color])
		elif part is MultiMeshInstance3D:
			for i in _FIGURE_SLOTS.size():
				pieces.append([_figure_mesh.surface_get_arrays(0), figure_transform(i, i < up), BODY_COLOR if i < up else FALLEN_COLOR])
	root.free()
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var idx := PackedInt32Array()
	for piece: Array in pieces:
		var src: Array = piece[0]
		var xf: Transform3D = piece[1]
		var base: int = v.size()
		var src_v: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
		var src_n: PackedVector3Array = src[Mesh.ARRAY_NORMAL]
		for i in src_v.size():
			v.append(xf * src_v[i])
			n.append(xf.basis * src_n[i])
			c.append(piece[2])
		for i: int in src[Mesh.ARRAY_INDEX]:
			idx.append(base + i)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = n
	arrays[Mesh.ARRAY_COLOR] = c
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_merged_meshes[key] = mesh
	return mesh


## Четвірка фігур одним MultiMesh: стоять перші `standing`, решта лежить на тих самих місцях.
static func figures(standing: int, stand_color: Color) -> MultiMeshInstance3D:
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
	set_standing(mi, standing, stand_color)
	return mi


## Загибла фігура лежить уздовж землі на своєму місці, ледь зсунута вбік: не стоїть і не
## здіймається над основою — загиблі не перешкода.
static func set_standing(mi: MultiMeshInstance3D, standing: int, stand_color: Color) -> void:
	var mm: MultiMesh = mi.multimesh
	for i in mm.instance_count:
		mm.set_instance_transform(i, figure_transform(i, i < standing))
		mm.set_instance_color(i, stand_color if i < standing else FALLEN_COLOR)


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


static func model_dir(set_id: int) -> String:
	return MODEL_DIR if set_id == 0 else "%sset%d/" % [MODEL_DIR, set_id]


static func model_path(type_id: int, set_id: int = 0) -> String:
	return model_dir(set_id) + MODEL_SLUGS[type_id] + ".glb"


static func has_model(type_id: int, set_id: int = 0) -> bool:
	return model_mesh(type_id, set_id) != null


## Набір, чия модель і чий рядок справді діють: свій, коли має і модель, і рядок типу, інакше 0.
static func _resolved_set(type_id: int, set_id: int) -> int:
	if set_id == 0 or not (_set_specs.get(set_id, {}) as Dictionary).has(type_id):
		return 0
	return set_id if _own_model(type_id, set_id) != null else 0


## Сітка моделі в системі юніта (перетворення вузлів GLB уже впечені), або null, коли файлу нема.
## Матеріал поверхні — імпортований: з нього `model_material()` бере текстури.
static func model_mesh(type_id: int, set_id: int = 0) -> ArrayMesh:
	return _own_model(type_id, _resolved_set(type_id, set_id))


static func _own_model(type_id: int, set_id: int) -> ArrayMesh:
	var key := Vector2i(set_id, type_id)
	if not _models.has(key):
		var path: String = model_path(type_id, set_id)
		_models[key] = _load_model(path) if not _models_pinned and ResourceLoader.exists(path) else null
	return _models[key]


## Для тестів: лише ці сітки, решта — коробки, хай що лежить на диску. Ключ — тип (набір 0)
## або Vector2i(набір, тип).
static func use_models(models: Dictionary) -> void:
	reset_models()
	for k: Variant in models:
		_models[k if k is Vector2i else Vector2i(0, k as int)] = models[k]
	_models_pinned = true


## Для тестів: рядки наборів замість таблиці; `reset_models()` повертає таблицю.
static func use_set_specs(rows: Dictionary) -> void:
	_set_specs = rows.duplicate(true)
	_merged_meshes.clear()
	_model_materials.clear()


static func reset_models() -> void:
	_set_specs = _SET_SPECS.duplicate(true)
	_models.clear()
	_models_pinned = false
	_model_materials.clear()
	_merged_meshes.clear()


static func _load_model(path: String) -> ArrayMesh:
	var root: Node = (load(path) as PackedScene).instantiate()
	var found: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
	var out: ArrayMesh = null
	if found.is_empty():
		push_error("%s: немає сітки" % path)
	else:
		var mi := found[0] as MeshInstance3D
		var xf := Transform3D()
		var n: Node = mi
		while n != root:
			if n is Node3D:
				xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var xfs: Array[Transform3D] = [xf]
		out = _merge_model(mi.mesh, xfs)
		out.surface_set_material(0, mi.get_active_material(0))
	root.free()
	return out


## Копії поверхні 0 сітки `src` за перетвореннями в одну поверхню з усіма атрибутами: дотичні й
## UV2 потрібні карті нормалей, гусеницям і колесам.
static func _merge_model(src: Mesh, xfs: Array[Transform3D]) -> ArrayMesh:
	var a: Array = src.surface_get_arrays(0)
	var sv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var count: int = sv.size()
	var sn: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var st: PackedFloat32Array = a[Mesh.ARRAY_TANGENT] if a[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
	var sc: PackedColorArray = a[Mesh.ARRAY_COLOR] if a[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	var su: PackedVector2Array = a[Mesh.ARRAY_TEX_UV] if a[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	var su2: PackedVector2Array = a[Mesh.ARRAY_TEX_UV2] if a[Mesh.ARRAY_TEX_UV2] != null else PackedVector2Array()
	var si: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(count))
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var t := PackedFloat32Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	for k in xfs.size():
		var xf: Transform3D = xfs[k]
		var base: int = v.size()
		for i in count:
			v.append(xf * sv[i])
			n.append((xf.basis * sn[i]).normalized())
			if st.size() == count * 4:
				var tg: Vector3 = (xf.basis * Vector3(st[i * 4], st[i * 4 + 1], st[i * 4 + 2])).normalized()
				t.append_array([tg.x, tg.y, tg.z, st[i * 4 + 3]])
			var col: Color = sc[i] if sc.size() == count else Color.BLACK
			c.append(col)
			uv.append(su[i] if su.size() == count else Vector2.ZERO)
			var u2: Vector2 = su2[i] if su2.size() == count else Vector2.ZERO
			if col.b > 0.5:
				# Вісь колеса їде разом із вершинами. shortcut: вісь лишається паралельною X лише
				# без повороту довкола Y/Z; у GLB вузли без такого повороту, тож поки досить.
				var axle: Vector3 = xf * Vector3(0.0, u2.x, u2.y)
				u2 = Vector2(axle.y, axle.z)
			uv2.append(u2)
		for i: int in si:
			idx.append(base + i)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = n
	if t.size() == v.size() * 4:
		arrays[Mesh.ARRAY_TANGENT] = t
	arrays[Mesh.ARRAY_COLOR] = c
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Один матеріал на тип: текстури, шорсткість і specular — з імпортованого матеріалу моделі.
static func model_material(type_id: int, set_id: int = 0) -> ShaderMaterial:
	var key := Vector2i(_resolved_set(type_id, set_id), type_id)
	if _model_materials.has(key):
		return _model_materials[key]
	var m := ShaderMaterial.new()
	m.shader = _MODEL_SHADER
	m.set_shader_parameter("wheel_radius", float(spec(type_id, set_id).get("wheel", 0.06)))
	var src := model_mesh(type_id, set_id).surface_get_material(0) as BaseMaterial3D
	if src != null:
		m.set_shader_parameter("albedo_tex", src.albedo_texture)
		m.set_shader_parameter("albedo_color", src.albedo_color)
		if src.normal_enabled:
			m.set_shader_parameter("normal_tex", src.normal_texture)
			m.set_shader_parameter("normal_scale", src.normal_scale)
		m.set_shader_parameter("orm_tex", src.roughness_texture)
		m.set_shader_parameter("roughness_channel", _channel(src.roughness_texture_channel))
		m.set_shader_parameter("metallic_channel", _channel(src.metallic_texture_channel))
		m.set_shader_parameter("roughness", src.roughness)
		m.set_shader_parameter("metallic", src.metallic)
		m.set_shader_parameter("specular", src.metallic_specular)
	_model_materials[key] = m
	return m


static func _channel(ch: BaseMaterial3D.TextureChannel) -> Vector4:
	if ch == BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE:
		return Vector4(1.0, 1.0, 1.0, 0.0) / 3.0
	var out := Vector4.ZERO
	out[ch] = 1.0
	return out
