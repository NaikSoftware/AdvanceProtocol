class_name PropLayer
extends Node3D
## Пропси поля бою: будівлі, руїни, мости, огорожі, тюки, опори з дротами, причепи, блоки,
## каміння. Лише вигляд — жодне правило їх не читає (docs/art-direction.md «Props»): будівля
## стоїть тільки на клітинках BUILDING і вміщається в їхню групу цілими тайлами, дрібні пропси —
## біля країв прохідних клітинок, ніколи в центрі, де стоїть юніт; техніка, що в'їхала, їх
## розчавлює. Розстановка — чиста функція дошки: той самий світ → ті самі перетворення, усе з
## cell_hash, ніколи Rules.roll чи глобальна випадковість, бо обидва гравці мусять бачити одне.
## Одна MultiMesh на модель — один вузол і по draw call на поверхню (§8).

enum Kind { STRUCTURE, RUIN, BRIDGE, FIELD_FENCE, GARDEN_FENCE, HAY, POLE, TRAILER, BLOCK, BOULDER }
## Як виглядає розчавлене: LAY — повалене набік, SQUASH — сплющене, SINK — втиснуте в землю.
enum Crush { NONE, LAY, SQUASH, SINK }

const MODEL_DIR: String = "res://assets/props/"
## Модель -> {kind, weight, …}. Слід будівлі в тайлах — з метаданих GLB (`footprint_tiles`), тож
## нова модель того самого виду стає в слот за самим ім'ям. Модель без файлу пропускається.
## max — скільки разів на карту (орієнтир, що має лишатись одним), ring — лише в кільці, gap —
## власний проміжок до сусідньої будівлі, якщо більший за STRUCTURE_GAP, tower —
## вежа (одна на карту, у власному дворі), storeys — двоповерховий (у селі їх не більше половини),
## scale — множник розміру брили (ассет завеликий для польового каменя),
## map/order/deck_top — міст своєї переправи (DECK_TOP з tools/blender/bridges/build_bridges.py).
const MODELS: Dictionary = {
	&"house_h1": {"kind": Kind.STRUCTURE, "weight": 4},
	&"house_h1_hit": {"kind": Kind.STRUCTURE, "weight": 1},
	&"house_h2": {"kind": Kind.STRUCTURE, "weight": 3},
	&"house_h3": {"kind": Kind.STRUCTURE, "weight": 2, "storeys": 2},
	&"house_h4": {"kind": Kind.STRUCTURE, "weight": 4},
	&"house_h5": {"kind": Kind.STRUCTURE, "weight": 6},
	&"house_h6": {"kind": Kind.STRUCTURE, "weight": 2, "storeys": 2},
	&"f8_shed": {"kind": Kind.STRUCTURE, "weight": 2},
	&"h5_panel_block": {"kind": Kind.STRUCTURE, "weight": 2, "max": 1},
	&"h5_panel_block_damaged": {"kind": Kind.STRUCTURE, "weight": 2, "max": 1},
	&"f1_farm_barn": {"kind": Kind.STRUCTURE, "weight": 1},
	&"f2_livestock_barn": {"kind": Kind.STRUCTURE, "weight": 2, "ring": true},
	&"f3_hangar": {"kind": Kind.STRUCTURE, "weight": 2, "max": 1},
	&"f3_hangar_damaged": {"kind": Kind.STRUCTURE, "weight": 2, "max": 1},
	&"f4_grain_bins": {"kind": Kind.STRUCTURE, "weight": 2, "max": 1},
	&"f5_silo_battery": {"kind": Kind.STRUCTURE, "weight": 2, "max": 1},
	&"f6_fuel_station": {"kind": Kind.STRUCTURE, "weight": 2, "max": 1},
	&"f7_water_tower": {"kind": Kind.STRUCTURE, "weight": 1, "gap": 0.5, "tower": true},
	&"f7b_brick_tower": {"kind": Kind.STRUCTURE, "weight": 1, "gap": 0.5, "tower": true},
	&"ruin_h1": {"kind": Kind.RUIN, "weight": 1},
	&"bridge_river_west": {"kind": Kind.BRIDGE, "map": &"river", "order": 0, "deck_top": 0.30},
	&"bridge_river_centre": {"kind": Kind.BRIDGE, "map": &"river", "order": 1, "deck_top": 0.30},
	&"bridge_river_east": {"kind": Kind.BRIDGE, "map": &"river", "order": 2, "deck_top": 0.21},
	&"infra_fence_picket": {"kind": Kind.FIELD_FENCE, "crush": Crush.LAY},
	&"infra_fence_sheet_green": {"kind": Kind.GARDEN_FENCE, "crush": Crush.LAY},
	&"infra_fence_sheet_brown": {"kind": Kind.GARDEN_FENCE, "crush": Crush.LAY},
	&"infra_fence_euro": {"kind": Kind.GARDEN_FENCE, "crush": Crush.LAY},
	&"infra_hay_round": {"kind": Kind.HAY, "crush": Crush.SQUASH},
	&"infra_hay_wrapped": {"kind": Kind.HAY, "crush": Crush.SQUASH},
	&"infra_pole_concrete_10kv": {"kind": Kind.POLE, "line": &"10kv", "crush": Crush.LAY},
	&"infra_pole_concrete_04kv": {"kind": Kind.POLE, "line": &"04kv", "crush": Crush.LAY},
	&"infra_pole_wood": {"kind": Kind.POLE, "line": &"04kv", "crush": Crush.LAY},
	&"infra_trailer_green": {"kind": Kind.TRAILER, "crush": Crush.SQUASH},
	&"infra_trailer_rust": {"kind": Kind.TRAILER, "crush": Crush.SQUASH},
	&"infra_jersey_block": {"kind": Kind.BLOCK, "crush": Crush.LAY},
	&"rock_moss_01": {"kind": Kind.BOULDER, "crush": Crush.SINK, "scale": 0.55},
	&"rock_moss_02": {"kind": Kind.BOULDER, "crush": Crush.SINK, "scale": 0.6},
	&"rock_moss_03": {"kind": Kind.BOULDER, "crush": Crush.SINK},
	&"rock_moss_04": {"kind": Kind.BOULDER, "crush": Crush.SINK},
	&"boulder_01": {"kind": Kind.BOULDER, "crush": Crush.SINK},
}
## Руїни, яких у таблиці ще нема, стають у слот за префіксом імені: напівзруйнована будівля —
## звичайна, повна руїна — рідкісна. Перший збіг виграє.
## Моделі, що лежать на диску, але ще не прийняті: їх не бере ні таблиця, ні префікс.
const RETIRED: Array[StringName] = [&"ruin_h3"]
const PREFIX_RULES: Array[Dictionary] = [
	{"prefix": "ruin_half_", "kind": Kind.RUIN, "weight": 6},
	{"prefix": "ruin_", "kind": Kind.RUIN, "weight": 1},
]
## Половина квадрата в центрі клітинки, куди не заходить жоден дрібний пропс: там стоїть юніт.
const KEEP_OUT: float = 0.2
## Частка викинутих пікселів даху над юнітом (≈ 30 % непрозорості, docs/art/props-research.md).
const FADE: float = 0.7
## Сусіди, що розчиняються разом із клітинкою юніта: камера стоїть на +x, +z від фокуса (yaw 45°),
## тож саме ці клітинки лежать між юнітом і камерою.
const REVEAL_OFFSETS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]
## Проліт ліній, клітинки: 10 кВ — 50–70 м, 0.4 кВ — 30–40 м (props-research, «Power lines»).
const SPAN: Dictionary = {&"10kv": 7.5, &"04kv": 4.5}
## Провис дроту посередині прольоту, клітинки (~1.1 м).
const WIRE_SAG: float = 0.14
const WIRE_SEGMENTS: int = 6
const WIRE_COLOR: Color = Color(0.12, 0.12, 0.115, 0.85)
## Відстань камери (клітинки), до якої дріт суцільний, і та, де він зник би зовсім: на дальньому
## зумі (~26) лишається третина — справжній дріт там тонший за піксель, а чорна лінія в пікселі
## обводила б містечко рамкою.
const WIRE_OPAQUE_DIST: float = 9.0
const WIRE_GONE_DIST: float = 34.0
## Імовірності з хешу на клітинку, у шістнадцятих: огорожа вздовж дороги йде відрізками по три
## клітинки, тюки — на кожній ~восьмій луці.
const FIELD_FENCE_RUN: int = 3
const FIELD_FENCE_CHANCE: int = 6
const HAY_CHANCE: int = 2
## Найменший проміжок між межами будівель (разом зі звісом даху), клітинки: 2 м. З камери під 38°
## вужчий прохід ховається за дахом, і два будинки читаються одним. Будівля, що не влазить із ним,
## поступається іншій моделі чи повороту або лишає клітинки порожнім двором.
const STRUCTURE_GAP: float = 0.25
## Велика будівля (слід понад клітинку) зі звісом тримається на стільки всередині своєї групи
## BUILDING (клітинки, ~2 м). Будинок на одну клітинку стоїть у ній по центру й тримає лише
## YARD_CLEAR_SMALL до межі: з повним відступом жоден не влазить, а з цим до огорожі на YARD_OUT
## лишається ≥ 0.3 клітинки й разом із її товщиною.
const YARD_CLEAR: float = 0.25
const YARD_CLEAR_SMALL: float = 0.03
## Хвіртка в огорожі двору, клітинки (~3.6 м): решта ребра обгороджена, двір не відкритий на вулицю.
const GATE: float = 0.45
## Кут камери для правила екрана (IsoCameraRig: 38–55°, бій здебільшого близько) і найменша глибина
## між будівлями, що на екрані накладаються: ближча будівля не сміє ховати дальшу, бо тоді дві
## читаються однією, хоч згори між ними й 2 м.
const SCREEN_PITCH_DEG: float = 40.0
const SCREEN_DEPTH_SEP: float = 1.2
## Огорожа двору стоїть за межею групи BUILDING на ~2.2 м: будинок на одну клітинку займає її
## майже всю, і до огорожі однаково лишається ≥ 0.3 клітинки; секція ще далеко від центру сусідньої
## клітинки, де стоїть юніт.
## 0.285: лице секції (півтовщини 0.0125) лишається за 0.2 від центру сусідньої клітинки.
const YARD_OUT: float = 0.285
## Кам'яні брили й бетонні блоки темніші за ассет: світлі, вони читались плямами фарби.
const STONE_TINT: float = 0.85
## Пляма дотику під брилою чи блоком: у скільки разів ширша за сам пропс і наскільки темна.
const CONTACT_SPREAD: float = 1.25
const CONTACT_ALPHA: float = 0.6
const _FADE_SHADER: Shader = preload("res://game/battle/shaders/prop_fade.gdshader")
const _THIN_SHADER: Shader = preload("res://game/battle/shaders/prop_thin.gdshader")
const _CONTACT_SHADER: Shader = preload("res://game/battle/shaders/prop_contact.gdshader")
## Той самий шейдер будівлі без розчинення: discard у шейдері вимикає ранню перевірку глибини на
## мобільних GPU, тож будівлі моделі, над якою зараз ніхто не стоїть, малюються без нього.
static var _solid_shader: Shader

## Модель -> {mesh, local, footprint, aabb, wires, tris}; спільний на процес, бо GLB кешуються.
static var _models: Dictionary = {}
## Модель -> ShaderMaterial розчинення (лише будівлі й руїни).
static var _fade_materials: Dictionary = {}
## Вид -> моделі на диску: перелік теки й сортування не повторюються на кожну групу будівель.
static var _by_kind: Dictionary = {}
## Модель -> {solid, fade} ShaderMaterial будівлі для поточного вузла.
var _node_materials: Dictionary = {}
var _contacts: MultiMeshInstance3D
var _apply_queued: bool = false

## Кожен екземпляр: {model, transform, cells (клітинки дошки під ним), crush, broken_of}.
var _instances: Array[Dictionary] = []
## Модель -> MultiMeshInstance3D і індекси екземплярів у ній.
var _nodes: Dictionary = {}
var _slots: Dictionary = {}
## Опори з дротами: [індекс екземпляра опори A, індекс B] — проліт.
var _spans: Array = []
var _wires: MeshInstance3D
var _reveal: Dictionary = {}
var _crushed: Dictionary = {}
var _board_size: Vector2i = Vector2i.ZERO
## Клітинки дошки з лісом: тут стоятимуть дерева, коли їхній вигляд буде готовий.
var forest_cells: Array[Vector2i] = []
## Пропси (крім мостів) кидають тінь сонця. Без неї на сонячній карті дім, тюк чи опора висять
## над землею; ставити до build().
var structure_shadows: bool = false


## Детермінований хеш клітинки; уся мінливість розстановки береться з нього.
static func cell_hash(cell: Vector2i, salt: int) -> int:
	return hash(Vector3i(cell.x, cell.y, salt))


## Вид моделі за таблицею чи префіксом; {} — модель не пропс цього шару.
static func spec_of(model: StringName) -> Dictionary:
	if MODELS.has(model):
		return MODELS[model]
	# Шматок мосту на одну клітинку («модель#k») і зруйнований двійник — той самий слот, що й цілий.
	var base := StringName(String(model).get_slice("#", 0).trim_suffix("_broken"))
	if base != model and MODELS.has(base):
		return MODELS[base]
	for rule in PREFIX_RULES:
		if String(model).begins_with(rule["prefix"]):
			return rule
	return {}


## Усі моделі виду, що є на диску: з таблиці й ті, що стали в слот за префіксом.
static func models_of(kind: int) -> Array[StringName]:
	if _by_kind.has(kind):
		return (_by_kind[kind] as Array[StringName]).duplicate()
	var out: Array[StringName] = []
	var names: Array[StringName] = []
	for m: StringName in MODELS:
		names.append(m)
	# Перелік через ResourceLoader: в експортованій збірці в теці лежать лише .import і .remap.
	for f in ResourceLoader.list_directory(MODEL_DIR):
		if f.ends_with(".glb") and not f.ends_with("_broken.glb") and not MODELS.has(StringName(f.get_basename())):
			names.append(StringName(f.get_basename()))
	# За рядком, не StringName.sort(): той порівнює вказівники й міняє порядок між запусками, а з ним
	# і кожен вибір моделі — розстановка мусить бути тією самою щоразу.
	names.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for m in names:
		var s: Dictionary = spec_of(m)
		if not s.is_empty() and int(s["kind"]) == kind and not RETIRED.has(m) and model(m) != null:
			out.append(m)
	_by_kind[kind] = out
	return out.duplicate()


## Сітка, локальне перетворення сітки, слід і межі моделі; null — файлу нема.
static func model(name: StringName) -> Variant:
	if _models.has(name):
		return _models[name]
	if String(name).contains("#"):
		_models[name] = _segment(name)
		return _models[name]
	var path: String = MODEL_DIR + String(name) + ".glb"
	if not ResourceLoader.exists(path):
		_models[name] = null
		return null
	var root: Node3D = (load(path) as PackedScene).instantiate()
	var meshes: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
	if meshes.size() != 1:
		push_warning("PropLayer: %s має %d сіток, беру першу" % [name, meshes.size()])
	var mi: MeshInstance3D = meshes[0]
	var local: Transform3D = _to_root(mi, root)
	var footprint := Vector2i.ZERO
	for n in [root] + root.find_children("*", "", true, false):
		var ex: Variant = n.get_meta("extras") if n.has_meta("extras") else null
		if ex is Dictionary and (ex as Dictionary).has("footprint_tiles"):
			var f: Array = ex["footprint_tiles"]
			footprint = Vector2i(roundi(f[0]), roundi(f[1]))
	var wires: Array[Vector3] = []
	var named: Array[Node] = root.find_children("wire_*", "", true, false)
	named.sort_custom(func(a: Node, b: Node) -> bool: return String(a.name) < String(b.name))
	for w in named:
		wires.append(_to_root(w as Node3D, root).origin)
	var tris: int = 0
	for s in mi.mesh.get_surface_count():
		tris += (mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	var info: Dictionary = {"mesh": _tuned_mesh(name, mi.mesh), "local": local, "footprint": footprint,
			"aabb": local * mi.mesh.get_aabb(), "wires": wires, "tris": tris}
	root.free()
	_models[name] = info
	return info


## Копія сітки з власними матеріалами для огорож (двобічне світло) і каміння (темніше). Сам GLB
## не чіпаємо: load() ділить його сітку з усіма, хто його вантажить.
static func _tuned_mesh(name: StringName, mesh: Mesh) -> Mesh:
	var kind: int = int(spec_of(name).get("kind", -1))
	if kind != Kind.FIELD_FENCE and kind != Kind.GARDEN_FENCE and kind != Kind.BOULDER and kind != Kind.BLOCK:
		return mesh
	var copy: Mesh = mesh.duplicate()
	for i in copy.get_surface_count():
		var src := copy.surface_get_material(i) as BaseMaterial3D
		if src == null:
			continue
		if kind == Kind.BOULDER or kind == Kind.BLOCK:
			var dark: BaseMaterial3D = src.duplicate()
			dark.albedo_color = src.albedo_color * Color(STONE_TINT, STONE_TINT, STONE_TINT, 1.0)
			copy.surface_set_material(i, dark)
			continue
		var thin := ShaderMaterial.new()
		thin.shader = _THIN_SHADER
		thin.set_shader_parameter("albedo_tex", src.albedo_texture)
		thin.set_shader_parameter("albedo_color", src.albedo_color)
		thin.set_shader_parameter("use_vertex_color", src.vertex_color_use_as_albedo)
		var cut: bool = src.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		thin.set_shader_parameter("alpha_cut", src.alpha_scissor_threshold if cut else 0.0)
		thin.set_shader_parameter("roughness", src.roughness)
		thin.set_shader_parameter("metallic", src.metallic)
		copy.surface_set_material(i, thin)
	return copy


## Шматок моделі мосту на одну клітинку переправи: «модель#k» — k-та клітинка вздовж локальної Z
## (від −L/2). Підрив буває на одній клітинці (EngineerCommand), тож кожна клітинка показує власний
## стан: цілий настил чи руїну. Трикутники обрізано точно по межі клітинки, з інтерполяцією всіх
## атрибутів, тож довгий настил не зникає й не вилазить у сусідню клітинку.
static func _segment(name: StringName) -> Variant:
	var base := StringName(String(name).get_slice("#", 0))
	var k: int = int(String(name).get_slice("#", 1))
	var whole: Variant = model(base)
	if whole == null:
		return null
	var info: Dictionary = whole
	# Довжина переправи — за цілою моделлю: уламки зруйнованої можуть бути коротші.
	var intact := StringName(String(base).trim_suffix("_broken"))
	var length: int = roundi(((model(intact) if model(intact) != null else info)["aabb"] as AABB).size.z)
	var z0: float = -length * 0.5 + k
	var mesh: ArrayMesh = _clip_z(info["mesh"], info["local"], z0, z0 + 1.0)
	var tris: int = 0
	for s in mesh.get_surface_count():
		tris += (mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	var wires: Array[Vector3] = []
	return {"mesh": mesh, "local": Transform3D.IDENTITY, "footprint": Vector2i.ZERO,
			"aabb": mesh.get_aabb() if mesh.get_surface_count() > 0 else AABB(), "wires": wires, "tris": tris}


## Поверхні сітки (у просторі кореня моделі), обрізані площинами z = z0 і z = z1.
static func _clip_z(src: Mesh, local: Transform3D, z0: float, z1: float) -> ArrayMesh:
	var out := ArrayMesh.new()
	for s in src.get_surface_count():
		var a: Array = src.surface_get_arrays(s)
		var pos: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var nrm: PackedVector3Array = a[Mesh.ARRAY_NORMAL] if a[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var tan: PackedFloat32Array = a[Mesh.ARRAY_TANGENT] if a[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
		var col: PackedColorArray = a[Mesh.ARRAY_COLOR] if a[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV] if a[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var uv2: PackedVector2Array = a[Mesh.ARRAY_TEX_UV2] if a[Mesh.ARRAY_TEX_UV2] != null else PackedVector2Array()
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if idx.is_empty():
			idx.resize(pos.size())
			for i in pos.size():
				idx[i] = i
		var verts: Array = []
		for i in pos.size():
			# Вершина як масив атрибутів: позиція, нормаль, дотична, колір, uv, uv2.
			verts.append([local * pos[i],
					(local.basis * nrm[i]).normalized() if not nrm.is_empty() else Vector3.UP,
					Vector4(tan[i * 4], tan[i * 4 + 1], tan[i * 4 + 2], tan[i * 4 + 3]) if not tan.is_empty() else Vector4(1, 0, 0, 1),
					col[i] if not col.is_empty() else Color.WHITE,
					uv[i] if not uv.is_empty() else Vector2.ZERO,
					uv2[i] if not uv2.is_empty() else Vector2.ZERO])
		var o_pos := PackedVector3Array()
		var o_nrm := PackedVector3Array()
		var o_tan := PackedFloat32Array()
		var o_col := PackedColorArray()
		var o_uv := PackedVector2Array()
		var o_uv2 := PackedVector2Array()
		for t in range(0, idx.size(), 3):
			var poly: Array = [verts[idx[t]], verts[idx[t + 1]], verts[idx[t + 2]]]
			poly = _clip_poly(poly, z0, 1.0)
			poly = _clip_poly(poly, z1, -1.0)
			for j in range(1, poly.size() - 1):
				for v: Array in [poly[0], poly[j], poly[j + 1]]:
					o_pos.append(v[0])
					o_nrm.append(v[1])
					var tv: Vector4 = v[2]
					o_tan.append_array([tv.x, tv.y, tv.z, tv.w])
					o_col.append(v[3])
					o_uv.append(v[4])
					o_uv2.append(v[5])
		if o_pos.is_empty():
			continue
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = o_pos
		arrays[Mesh.ARRAY_NORMAL] = o_nrm
		if not tan.is_empty():
			arrays[Mesh.ARRAY_TANGENT] = o_tan
		if not col.is_empty():
			arrays[Mesh.ARRAY_COLOR] = o_col
		if not uv.is_empty():
			arrays[Mesh.ARRAY_TEX_UV] = o_uv
		if not uv2.is_empty():
			arrays[Mesh.ARRAY_TEX_UV2] = o_uv2
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(out.get_surface_count() - 1, src.surface_get_material(s))
	return out


## Сазерленд — Ходжмен однією площиною: лишає частину многокутника, де side·(z − plane) ≥ 0.
static func _clip_poly(poly: Array, plane: float, side: float) -> Array:
	var out: Array = []
	for i in poly.size():
		var a: Array = poly[i]
		var b: Array = poly[(i + 1) % poly.size()]
		var da: float = side * ((a[0] as Vector3).z - plane)
		var db: float = side * ((b[0] as Vector3).z - plane)
		if da >= 0.0:
			out.append(a)
		if (da >= 0.0) != (db >= 0.0):
			var t: float = da / (da - db)
			out.append([(a[0] as Vector3).lerp(b[0], t), (a[1] as Vector3).lerp(b[1], t).normalized(),
					(a[2] as Vector4).lerp(b[2], t), (a[3] as Color).lerp(b[3], t),
					(a[4] as Vector2).lerp(b[4], t), (a[5] as Vector2).lerp(b[5], t)])
	return out


static func _to_root(n: Node3D, root: Node3D) -> Transform3D:
	var t: Transform3D = n.transform
	var p: Node = n.get_parent()
	while p != null and p != root:
		t = (p as Node3D).transform * t
		p = p.get_parent()
	return t


## world — дошка разом із кільцем (Surroundings.world_board), ring — його ширина, тож клітинка
## дошки c лежить у світі на c + ring. map_key — ім'я файлу карти (мости своєї карти, сіль
## хешу), half_dir — напрям від центру дошки до баз гравця 0: половини мають власний набір.
func build(world: Board, ring: int, board_size: Vector2i, height: TerrainHeight,
		map_key: StringName = &"", half_dir: Vector2 = Vector2.ZERO) -> void:
	for child in get_children():
		child.free()
	_instances.clear()
	_nodes.clear()
	_slots.clear()
	_spans.clear()
	_wires = null
	_contacts = null
	_node_materials.clear()
	forest_cells.clear()
	_board_size = board_size
	if world.width <= 0 or world.height <= 0:
		return
	var p := _Placer.new(self, world, ring, board_size, height, map_key, half_dir)
	p.place_all()
	_spans = p.spans
	for y in board_size.y:
		for x in board_size.x:
			if world.kind_at(Vector2i(x + ring, y + ring)) == Terrain.Kind.FOREST:
				forest_cells.append(Vector2i(x, y))
	_build_nodes(ring > 0)
	_apply()


## Клітинки юнітів, які зараз показано: їхні будівлі й будівлі між ними та камерою розчиняються.
## Новий набір замінює попередній.
func set_reveal_cells(cells: Array[Vector2i]) -> void:
	_reveal.clear()
	for c in cells:
		for o in REVEAL_OFFSETS:
			_reveal[c + o] = true
	_queue_apply()


## Клітинки, де розчавлено дрібні пропси, — уже обрізані розвіданим глядача (§3.5): шар не
## знає ні про гравців, ні про туман і малює рівно те, що дали.
func set_crushed(cells: Array[Vector2i]) -> void:
	_crushed.clear()
	for c in cells:
		_crushed[c] = true
	_queue_apply()


## Для тестів: екземпляри, що стоять на клітинці дошки.
func instances_on(cell: Vector2i) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for inst in _instances:
		if (inst["cells"] as Array).has(cell):
			out.append({"model": inst["model"], "transform": _final_transform(inst),
					"faded": _is_faded(inst), "crushed": _is_crushed(inst)})
	return out


func all_instances() -> Array[Dictionary]:
	return _instances


func triangle_count() -> int:
	var t: int = 0
	for inst in _instances:
		t += int((model(inst["model"]) as Dictionary)["tris"])
	return t


func wire_spans() -> int:
	var n: int = 0
	for s: Array in _spans:
		if not _is_crushed(_instances[s[0]]) and not _is_crushed(_instances[s[1]]):
			n += 1
	return n


## Набір під юнітами й розчавлене приходять разом після кожного пакета подій: вузли оновлюються
## один раз наприкінці кадру, а не на кожен виклик. Стан (instances_on) правдивий одразу.
func _queue_apply() -> void:
	if _apply_queued:
		return
	_apply_queued = true
	_flush.call_deferred()


func _flush() -> void:
	if _apply_queued:
		_apply()


func _add(model_name: StringName, xform: Transform3D, cells: Array[Vector2i]) -> int:
	_instances.append({"model": model_name, "transform": xform, "cells": cells,
			"crush": int(spec_of(model_name).get("crush", Crush.NONE))})
	return _instances.size() - 1


func _build_nodes(haze: bool) -> void:
	var by_model: Dictionary = {}
	for i in _instances.size():
		var m: StringName = _instances[i]["model"]
		if not by_model.has(m):
			by_model[m] = []
		(by_model[m] as Array).append(i)
	var names: Array = by_model.keys()
	names.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for m: StringName in names:
		var info: Dictionary = model(m)
		var kind: int = int(spec_of(m)["kind"])
		var fades: bool = kind == Kind.STRUCTURE or kind == Kind.RUIN
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = fades
		mm.mesh = info["mesh"]
		mm.instance_count = (by_model[m] as Array).size()
		var mmi := MultiMeshInstance3D.new()
		mmi.name = String(m)
		mmi.multimesh = mm
		# §8: тіні — юнітам; пропсам — лише там, де без тіні на сонці річ висить над землею. Каміння
		# без тіні: низьке, а прохід тіней по ~50 брилах Ridge коштує понад 50 тис. трикутників.
		var casts: bool = structure_shadows and kind != Kind.BRIDGE and kind != Kind.BOULDER
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if casts else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if fades:
			_node_materials[m] = {"fade": _fade_material(m, info, haze, false), "solid": _fade_material(m, info, haze, true)}
			mmi.material_override = _node_materials[m]["solid"]
		add_child(mmi)
		_nodes[m] = mmi
		_slots[m] = by_model[m]
	if not _spans.is_empty():
		_wires = MeshInstance3D.new()
		_wires.name = "Wires"
		_wires.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = WIRE_COLOR
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
		# min > max: дріт гасне з відстанню, а не з'являється.
		mat.distance_fade_min_distance = WIRE_GONE_DIST
		mat.distance_fade_max_distance = WIRE_OPAQUE_DIST
		_wires.material_override = mat
		add_child(_wires)
	_build_contacts()


## Пляма дотику під брилами й блоками: один квадрат на кожен, лягає за схилом, одна MultiMesh. Без
## неї світлий камінь на траві читається наклеєним, а справжня тінь по всіх брилах — задорога.
func _build_contacts() -> void:
	var xforms: Array[Transform3D] = []
	var heights: Array[float] = []
	for inst in _instances:
		var k: int = int(spec_of(inst["model"])["kind"])
		if k != Kind.BOULDER and k != Kind.BLOCK:
			continue
		var t: Transform3D = inst["transform"]
		var box: AABB = t * ((model(inst["model"]) as Dictionary)["aabb"] as AABB)
		var size := Vector2(box.size.x, box.size.z) * CONTACT_SPREAD
		var c := Vector2(box.get_center().x, box.get_center().z)
		var hx: float = TerrainHeight.ground_y(c.x + 0.05, c.y) - TerrainHeight.ground_y(c.x - 0.05, c.y)
		var hz: float = TerrainHeight.ground_y(c.x, c.y + 0.05) - TerrainHeight.ground_y(c.x, c.y - 0.05)
		var up := Vector3(-hx / 0.1, 1.0, -hz / 0.1).normalized()
		var right: Vector3 = Vector3.RIGHT.slide(up).normalized()
		var back: Vector3 = right.cross(up)
		xforms.append(Transform3D(Basis(right * size.x, up, -back * size.y),
				Vector3(c.x, TerrainHeight.ground_y(c.x, c.y) + 0.004, c.y)))
		heights.append(box.size.y)
	if xforms.is_empty():
		return
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE
	var mat := ShaderMaterial.new()
	mat.shader = _CONTACT_SHADER
	mat.set_shader_parameter("strength", CONTACT_ALPHA)
	mat.set_shader_parameter("cast", 1.0 if structure_shadows else 0.0)
	quad.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_custom_data(i, Color(heights[i], 0.0, 0.0, 0.0))
	_contacts = MultiMeshInstance3D.new()
	_contacts.name = "ContactShadows"
	_contacts.multimesh = mm
	_contacts.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_contacts)


## Імпортований матеріал не чіпаємо: GLB кешується й ділиться між усіма, хто його вантажить.
## Розчинення й імла — у власному ShaderMaterial поверх сітки (material_override).
func _fade_material(m: StringName, info: Dictionary, haze: bool, solid: bool) -> ShaderMaterial:
	# Розмір дошки — у ключі: імла кільця залежить від нього, а кеш живе весь процес.
	var key: String = "%s:%s:%s:%s" % [m, haze, _board_size, solid]
	if _fade_materials.has(key):
		return _fade_materials[key]
	var src := (info["mesh"] as Mesh).surface_get_material(0) as BaseMaterial3D
	var mat := ShaderMaterial.new()
	mat.shader = _solid() if solid else _FADE_SHADER
	if src != null:
		mat.set_shader_parameter("albedo_tex", src.albedo_texture)
		mat.set_shader_parameter("normal_tex", src.normal_texture)
		mat.set_shader_parameter("albedo_color", src.albedo_color)
		mat.set_shader_parameter("roughness", src.roughness)
		mat.set_shader_parameter("metallic", src.metallic)
	if haze:
		Surroundings.apply(mat, _board_size)
	_fade_materials[key] = mat
	return mat


static func _solid() -> Shader:
	if _solid_shader == null:
		_solid_shader = Shader.new()
		var code: String = _FADE_SHADER.code
		var cut: String = "\tif (v_fade > bayer4(FRAGCOORD.xy)) {\n\t\tdiscard;\n\t}\n"
		assert(code.contains(cut), "PropLayer: розчинення в prop_fade.gdshader змінилось")
		_solid_shader.code = code.replace(cut, "")
	return _solid_shader


func _is_faded(inst: Dictionary) -> bool:
	var kind: int = int(spec_of(inst["model"])["kind"])
	if kind != Kind.STRUCTURE and kind != Kind.RUIN:
		return false
	for c: Vector2i in inst["cells"]:
		if _reveal.has(c):
			return true
	return false


func _is_crushed(inst: Dictionary) -> bool:
	return int(inst["crush"]) != Crush.NONE and _crushed.has((inst["cells"] as Array)[0])


## Розчавлене лишається на місці як шрам: повалене, сплющене чи втиснуте.
func _final_transform(inst: Dictionary) -> Transform3D:
	var t: Transform3D = inst["transform"]
	if not _is_crushed(inst):
		return t
	var h: int = cell_hash((inst["cells"] as Array)[0], int(t.origin.x * 1000.0))
	match int(inst["crush"]):
		Crush.LAY:
			# Набік довкола поздовжньої осі (локальна X): огорожа, опора, блок лягають на землю.
			var side: float = 1.0 if h & 1 else -1.0
			return t * Transform3D(Basis(Vector3.RIGHT, side * deg_to_rad(84.0)), Vector3.ZERO)
		Crush.SQUASH:
			return t * Transform3D(Basis.from_scale(Vector3(1.1, 0.35, 1.05)), Vector3.ZERO)
		Crush.SINK:
			var info: Dictionary = model(inst["model"])
			return t.translated(Vector3(0.0, -(info["aabb"] as AABB).size.y * 0.6 * t.basis.get_scale().y, 0.0))
	return t


func _apply() -> void:
	_apply_queued = false
	for m: StringName in _nodes:
		var mmi: MultiMeshInstance3D = _nodes[m]
		var mm: MultiMesh = mmi.multimesh
		var slots: Array = _slots[m]
		var local: Transform3D = (model(m) as Dictionary)["local"]
		var any_faded := false
		for k in slots.size():
			var inst: Dictionary = _instances[slots[k]]
			mm.set_instance_transform(k, _final_transform(inst) * local)
			if mm.use_custom_data:
				var faded: bool = _is_faded(inst)
				any_faded = any_faded or faded
				mm.set_instance_custom_data(k, Color(0, 0, 0, FADE if faded else 0.0))
		if _node_materials.has(m):
			mmi.material_override = _node_materials[m]["fade" if any_faded else "solid"]
	_rebuild_wires()


## Дроти — лінії в пікселях екрана, не геометрія: 1–3 см дроту менші за піксель (props-research).
## Проліт до поваленої опори не малюється.
func _rebuild_wires() -> void:
	if _wires == null:
		return
	var verts := PackedVector3Array()
	for s: Array in _spans:
		var a: Dictionary = _instances[s[0]]
		var b: Dictionary = _instances[s[1]]
		if _is_crushed(a) or _is_crushed(b):
			continue
		var wa: Array[Vector3] = (model(a["model"]) as Dictionary)["wires"]
		var wb: Array[Vector3] = (model(b["model"]) as Dictionary)["wires"]
		for k in mini(wa.size(), wb.size()):
			var pa: Vector3 = (a["transform"] as Transform3D) * wa[k]
			var pb: Vector3 = (b["transform"] as Transform3D) * wb[k]
			for j in WIRE_SEGMENTS:
				for t: float in [float(j) / WIRE_SEGMENTS, float(j + 1) / WIRE_SEGMENTS]:
					verts.append(pa.lerp(pb, t) - Vector3(0.0, WIRE_SAG * 4.0 * t * (1.0 - t), 0.0))
	if verts.is_empty():
		_wires.mesh = null
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	_wires.mesh = mesh


## Розстановка однієї побудови: окремий об'єкт, щоб стан обходу (зайняте, лічильники) не жив
## у шарі між побудовами.
class _Placer:
	var layer: PropLayer
	var world: Board
	var ring: int
	var size: Vector2i
	var height: TerrainHeight
	var map_key: StringName
	var half_dir: Vector2
	var salt: int
	var used: Dictionary = {}
	var spans: Array = []
	## Межі вже поставлених будівель у XZ разом зі звісом даху, власний проміжок кожної і її проєкція
	## на екран: [Rect2, gap, Rect2 екрана, Vector2 глибини]. Нова будівля тримається від них на
	## більший із двох проміжків і не накладається на екрані ближче за SCREEN_DEPTH_SEP углиб.
	var placed: Array = []
	## Клітинка -> модель будівлі на ній: однакові моделі поруч не стають.
	var model_at: Dictionary = {}
	var tower_placed := false
	## Клітинки дошки, на яких уже стоїть дрібний пропс (одна річ на ребро).
	var edges: Dictionary = {}
	## Клітинки дошки з огорожею двору: польова огорожа й причепи їх оминають.
	var yard_cells: Dictionary = {}
	## Клітинки дошки під будівлями -> напрям фасаду (−Z моделі) на дошці: двір без будівлі не
	## обгороджується (порожня огорожа серед поля читається уламком), а хвіртка стає перед дверима.
	var built: Dictionary = {}

	func _init(p_layer: PropLayer, p_world: Board, p_ring: int, p_size: Vector2i,
			p_height: TerrainHeight, p_map: StringName, p_half: Vector2) -> void:
		layer = p_layer
		world = p_world
		ring = p_ring
		size = p_size
		height = p_height
		map_key = p_map
		half_dir = p_half
		salt = String(p_map).hash()

	func place_all() -> void:
		_structures()
		_bridges()
		_yard_fences()
		_field_fences()
		_hay()
		_trailers()
		_blocks()
		_boulders()
		_poles()

	## Клітинка світу -> клітинка дошки.
	func board_cell(w: Vector2i) -> Vector2i:
		return w - Vector2i(ring, ring)

	func on_board(c: Vector2i) -> bool:
		return c.x >= 0 and c.y >= 0 and c.x < size.x and c.y < size.y

	func kind(c: Vector2i) -> int:
		var w: Vector2i = c + Vector2i(ring, ring)
		return world.kind_at(w) if world.in_bounds(w) else -1

	## Половина дошки: 0 — бік гравця 0. Без напряму — ліва/права.
	func half(c: Vector2i) -> int:
		var mid := Vector2(size) * 0.5 - Vector2(0.5, 0.5)
		var d: Vector2 = half_dir if half_dir != Vector2.ZERO else Vector2(-1.0, 0.0)
		return 0 if (Vector2(c) - mid).dot(d) > 0.0 else 1

	func h(c: Vector2i, k: int) -> int:
		return absi(PropLayer.cell_hash(c, salt + k * 7919))

	## Модель виду для половини: кожна половина бере свою, тож пейзаж не віддзеркалений.
	func pick_for_half(kind_id: int, half_id: int, filter: Callable = Callable()) -> StringName:
		var ms: Array[StringName] = PropLayer.models_of(kind_id)
		if filter.is_valid():
			ms = ms.filter(filter)
		if ms.is_empty():
			return &""
		var start: int = absi(hash(Vector2i(salt, kind_id))) % ms.size()
		return ms[(start + half_id) % ms.size()]

	func ground(x: float, z: float) -> float:
		return height.at(x, z) if height != null else 0.0

	## Межі екземпляра в XZ відносно центру клітинки не заходять у квадрат юніта.
	func clear_of_centre(m: StringName, xform: Transform3D, c: Vector2i) -> bool:
		var box: AABB = xform * ((PropLayer.model(m) as Dictionary)["aabb"] as AABB)
		var lo := Vector2(box.position.x - c.x, box.position.z - c.y)
		var hi := Vector2(box.end.x - c.x, box.end.z - c.y)
		return lo.x >= PropLayer.KEEP_OUT or hi.x <= -PropLayer.KEEP_OUT \
				or lo.y >= PropLayer.KEEP_OUT or hi.y <= -PropLayer.KEEP_OUT

	## tilt — довгий пропс (огорожа) лягає за схилом уздовж своєї довжини (локальна X), а не стоїть
	## рівно, одним кінцем у повітрі.
	## length — масштаб уздовж локальної X: огорожа двору подовжується на кутах до сусідньої.
	func put_small(m: StringName, c: Vector2i, local: Vector2, yaw: float, scale: float = 1.0, tilt: bool = false,
			length: float = 1.0) -> bool:
		if m == &"":
			return false
		var x: float = c.x + local.x
		var z: float = c.y + local.y
		var basis := Basis(Vector3.UP, yaw)
		var y: float = ground(x, z)
		if tilt:
			var half_len: float = ((PropLayer.model(m) as Dictionary)["aabb"] as AABB).size.x * 0.5 * length
			var along: Vector3 = basis.x * half_len
			var y0: float = ground(x - along.x, z - along.z)
			var y1: float = ground(x + along.x, z + along.z)
			basis = Basis(basis.z, atan2(y1 - y0, 2.0 * half_len)) * basis
			y = minf((y0 + y1) * 0.5, y)
		var xform := Transform3D(basis * Basis.from_scale(Vector3(length, 1.0, 1.0) * scale), Vector3(x, y, z))
		if not clear_of_centre(m, xform, c):
			return false
		var cells: Array[Vector2i] = [c]
		layer._add(m, xform, cells)
		return true

	# --- будівлі ---------------------------------------------------------------------------

	## Кожна зв'язна група BUILDING (і дошки, і кільця) заповнюється цілими слідами: спершу більші,
	## вага моделі й хеш вирішують, яку саме; повернута фасадом (−Z) до дороги, якщо та поруч.
	## Клітинка, куди не влізло нічого, лишається двором. RUBBLE — та сама логіка з руїнами.
	func _structures() -> void:
		# Руїни першими: клітинка RUBBLE мусить читатися руїною, а будинок поруч поступиться їй.
		for target: int in [Terrain.Kind.RUBBLE, Terrain.Kind.BUILDING]:
			var kind_id: int = Kind.STRUCTURE if target == Terrain.Kind.BUILDING else Kind.RUIN
			var seen: Dictionary = {}
			var groups: Array = []
			for wy in world.height:
				for wx in world.width:
					var w := Vector2i(wx, wy)
					if seen.has(w) or world.kind_at(w) != target:
						continue
					var group: Array[Vector2i] = []
					var queue: Array[Vector2i] = [w]
					seen[w] = true
					while not queue.is_empty():
						var q: Vector2i = queue.pop_back()
						group.append(board_cell(q))
						for d in Board.DIRS_4:
							var n: Vector2i = q + d
							if world.in_bounds(n) and not seen.has(n) and world.kind_at(n) == target:
								seen[n] = true
								queue.append(n)
					group.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
					groups.append(group)
			# Спершу групи дошки: єдина на карту вежа — орієнтир села, а не пейзажу за краєм.
			var board_first: Array = groups.filter(func(g: Array) -> bool: return g.any(func(c: Vector2i) -> bool: return on_board(c)))
			for g: Array[Vector2i] in board_first + groups.filter(func(g: Array) -> bool: return not board_first.has(g)):
				_fill_group(g, kind_id)

	func _fill_group(group: Array[Vector2i], kind_id: int) -> void:
		var free: Dictionary = {}
		for c in group:
			free[c] = true
		var in_group: Dictionary = free.duplicate()
		var in_ring: bool = not group.any(func(c: Vector2i) -> bool: return on_board(c))
		var has_tower := false
		var models: Array[StringName] = PropLayer.models_of(kind_id)
		var step: int = 0
		while true:
			var options: Array = []
			var total: int = 0
			for m in models:
				var s: Dictionary = PropLayer.spec_of(m)
				if bool(s.get("ring", false)) and not in_ring:
					continue
				if s.has("max") and int(used.get(m, 0)) >= int(s["max"]):
					continue
				if bool(s.get("tower", false)) and (has_tower or tower_placed):
					continue
				var fp: Vector2i = (PropLayer.model(m) as Dictionary)["footprint"]
				if fp == Vector2i.ZERO:
					continue
				for c in group:
					if not free.has(c):
						continue
					for rot in 4:
						var size_r: Vector2i = fp if rot % 2 == 0 else Vector2i(fp.y, fp.x)
						# Руїна стоїть на кожній клітинці RUBBLE (вона й є вид клітинки), тож правила відстані
						# її не відсувають; будинки ж тримаються від руїн, як від будь-якої будівлі.
						var ruin: bool = kind_id == Kind.RUIN
						if _fits(free, c, size_r) and _inside_yard(m, c, rot, size_r, in_group) \
								and (ruin or (_clear_of_placed(m, c, rot, size_r) and _no_twin(m, c, size_r) \
								and _tower_apart(m, c, size_r))):
							var weight: int = int(s.get("weight", 1)) * size_r.x * size_r.y
							options.append([m, c, rot, size_r, weight, _faces_road(c, size_r, rot)])
			if options.is_empty():
				return
			# Фасадом до дороги, щойно таке місце є: хата не стоїть до вулиці глухим боком.
			if options.any(func(o: Array) -> bool: return o[5]):
				options = options.filter(func(o: Array) -> bool: return o[5])
			for o: Array in options:
				total += int(o[4])
			var roll: int = h(group[0], 100 + step) % total
			step += 1
			for o: Array in options:
				roll -= int(o[4])
				if roll < 0:
					_put_structure(o[0], o[1], o[2], o[3], free)
					has_tower = has_tower or bool(PropLayer.spec_of(o[0]).get("tower", false))
					tower_placed = tower_placed or has_tower
					break

	func _rect_of(m: StringName, origin: Vector2i, rot: int, s: Vector2i) -> Rect2:
		var centre := Vector2(origin) + Vector2(s - Vector2i.ONE) * 0.5
		var box: AABB = Transform3D(Basis(Vector3.UP, rot * PI * 0.5), Vector3(centre.x, 0.0, centre.y)) \
				* ((PropLayer.model(m) as Dictionary)["aabb"] as AABB)
		return Rect2(box.position.x, box.position.z, box.size.x, box.size.z)

	func _gap_of(m: StringName) -> float:
		return maxf(STRUCTURE_GAP, float(PropLayer.spec_of(m).get("gap", 0.0)))

	func _clear_of_placed(m: StringName, origin: Vector2i, rot: int, s: Vector2i) -> bool:
		var r: Rect2 = _rect_of(m, origin, rot, s)
		var scr: Array = _screen_of(r, _height_of(m))
		for p: Array in placed:
			if r.grow(maxf(_gap_of(m), float(p[1]))).intersects(p[0]):
				return false
			if (scr[0] as Rect2).intersects(p[2]) and _depth_gap(scr[1], p[3]) < SCREEN_DEPTH_SEP:
				return false
		return true

	func _height_of(m: StringName) -> float:
		return ((PropLayer.model(m) as Dictionary)["aabb"] as AABB).size.y

	## Проєкція межі будівлі (разом із висотою даху) на екран камери гри: [Rect2 екрана, Vector2
	## глибини вздовж погляду]. Камера стоїть на +x, +z від фокуса й дивиться на −x, −z.
	static func _screen_of(r: Rect2, h: float) -> Array:
		var right := Vector2(1.0, -1.0).normalized()
		var fwd := Vector2(-1.0, -1.0).normalized()
		var pitch: float = deg_to_rad(SCREEN_PITCH_DEG)
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		var d := Vector2(INF, -INF)
		for c: Vector2 in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
			var depth: float = c.dot(fwd)
			d = Vector2(minf(d.x, depth), maxf(d.y, depth))
			for y: float in [0.0, h]:
				var p := Vector2(c.dot(right), depth * sin(pitch) + y * cos(pitch))
				lo = lo.min(p)
				hi = hi.max(p)
		return [Rect2(lo, hi - lo), d]

	static func _depth_gap(a: Vector2, b: Vector2) -> float:
		return maxf(0.0, maxf(b.x - a.y, a.x - b.y))

	## Та сама модель не стоїть у сусідній клітинці (і по діагоналі): ряд однакових хат — штамп.
	func _no_twin(m: StringName, origin: Vector2i, s: Vector2i) -> bool:
		for dy in range(-1, s.y + 1):
			for dx in range(-1, s.x + 1):
				if model_at.get(origin + Vector2i(dx, dy), &"") == m:
					return false
		return true

	## Вежа — у власному дворі: жодна будівля не стоїть поруч із нею (і по діагоналі).
	func _tower_apart(m: StringName, origin: Vector2i, s: Vector2i) -> bool:
		var tower: bool = bool(PropLayer.spec_of(m).get("tower", false))
		for dy in range(-1, s.y + 1):
			for dx in range(-1, s.x + 1):
				var n: Vector2i = origin + Vector2i(dx, dy)
				if not model_at.has(n):
					continue
				if tower or bool(PropLayer.spec_of(model_at[n]).get("tower", false)):
					return false
		return true

	## Межа моделі зі звісом даху лежить у власному сліді з відступом з усіх боків: огорожа двору йде
	## довкола ділянки під будівлями, тож може пройти й між будинком і порожньою клітинкою групи.
	## Велика будівля — YARD_CLEAR, на одну клітинку — YARD_CLEAR_SMALL (до огорожі однаково ≥ 0.3
	## клітинки), руїна (її не обгороджують) — лише не за межею клітинки.
	func _inside_yard(m: StringName, origin: Vector2i, rot: int, s: Vector2i, _in_group: Dictionary) -> bool:
		var r: Rect2 = _rect_of(m, origin, rot, s)
		var f := Rect2(Vector2(origin) - Vector2(0.5, 0.5), Vector2(s))
		var ruin: bool = int(PropLayer.spec_of(m)["kind"]) == Kind.RUIN
		var margin: float = 0.0 if ruin else (YARD_CLEAR_SMALL if s == Vector2i.ONE else YARD_CLEAR)
		return f.grow(-margin + 1e-4).encloses(r)

	func _fits(free: Dictionary, origin: Vector2i, s: Vector2i) -> bool:
		for dy in s.y:
			for dx in s.x:
				if not free.has(origin + Vector2i(dx, dy)):
					return false
		return true

	## Фасад (−Z моделі) після повороту rot·90° дивиться на дорогу одразу за слідом.
	func _faces_road(origin: Vector2i, s: Vector2i, rot: int) -> bool:
		var front: Vector2i = [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(1, 0)][rot]
		for dy in s.y:
			for dx in s.x:
				var n: Vector2i = origin + Vector2i(dx, dy) + front
				if kind(n) == Terrain.Kind.ROAD:
					return true
		return false

	func _put_structure(m: StringName, origin: Vector2i, rot: int, s: Vector2i, free: Dictionary) -> void:
		var cells: Array[Vector2i] = []
		var lo: float = INF
		for dy in s.y:
			for dx in s.x:
				var c: Vector2i = origin + Vector2i(dx, dy)
				free.erase(c)
				cells.append(c)
				built[c] = [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(1, 0)][rot]
				# Найнижча точка під слідом: стіна трохи заходить у землю, але ніде не висить.
				for o: Vector2 in [Vector2(-0.4, -0.4), Vector2(0.4, -0.4), Vector2(-0.4, 0.4), Vector2(0.4, 0.4)]:
					lo = minf(lo, ground(c.x + o.x, c.y + o.y))
		used[m] = int(used.get(m, 0)) + 1
		var r: Rect2 = _rect_of(m, origin, rot, s)
		var scr: Array = _screen_of(r, _height_of(m))
		placed.append([r, _gap_of(m), scr[0], scr[1]])
		for c in cells:
			model_at[c] = m
		var centre := Vector2(origin) + Vector2(s - Vector2i.ONE) * 0.5
		layer._add(m, Transform3D(Basis(Vector3.UP, rot * PI * 0.5), Vector3(centre.x, lo, centre.y)),
				_board_only(cells))

	func _board_only(cells: Array[Vector2i]) -> Array[Vector2i]:
		var out: Array[Vector2i] = []
		for c in cells:
			if on_board(c):
				out.append(c)
		# Будівля кільця не стоїть на жодній клітинці дошки, але має ключ для пошуку.
		return out if not out.is_empty() else cells

	# --- мости -----------------------------------------------------------------------------

	## Переправа — модель на всю довжину вздовж дороги; настил — на deck_y. Мости своєї карти
	## розкладаються на переправи за порядком уздовж X; інакше — будь-який міст тієї ж довжини. Міст
	## кільця моделі не має: у нього нема й настилу, а правила його не бачать. Підрив буває на одній
	## клітинці, тож змішана переправа — по шматку на клітинку, кожен у власному стані: гравець бачить,
	## яку саме клітинку може відновити інженер. Ціла чи вся зруйнована — одна модель.
	func _bridges() -> void:
		if height == null:
			return
		var groups: Array[Dictionary] = []
		for g in height.bridge_groups():
			if (g["cells"] as Array).all(func(c: Vector2i) -> bool: return on_board(c)):
				groups.append(g)
		groups.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a["centre"] as Vector2).x < (b["centre"] as Vector2).x)
		var own: Array[StringName] = PropLayer.models_of(Kind.BRIDGE).filter(
				func(m: StringName) -> bool: return PropLayer.spec_of(m).get("map", &"") == map_key)
		own.sort_custom(func(a: StringName, b: StringName) -> bool: return int(PropLayer.spec_of(a)["order"]) < int(PropLayer.spec_of(b)["order"]))
		var any: Array[StringName] = PropLayer.models_of(Kind.BRIDGE)
		for i in groups.size():
			var g: Dictionary = groups[i]
			var length: int = _length(g)
			var m: StringName = &""
			if own.size() == groups.size() and _model_length(own[i]) == length:
				m = own[i]
			else:
				for c in any:
					if _model_length(c) == length:
						m = c
						break
			if m == &"":
				push_warning("PropLayer: переправі довжиною %d нема моделі" % length)
				continue
			var axis: Vector2 = g["axis"]
			var cells: Array[Vector2i] = []
			cells.assign(g["cells"])
			# Клітинки за зростанням уздовж осі — у тому ж порядку, що й шматки моделі вздовж локальної Z.
			cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x if axis.x != 0.0 else a.y < b.y)
			var broken_m := StringName(String(m) + "_broken")
			if PropLayer.model(broken_m) == null:
				broken_m = m
			var broken: Array = cells.map(func(c: Vector2i) -> bool: return kind(c) == Terrain.Kind.BRIDGE_DESTROYED)
			# Вісь моделі — Z; переправа вздовж X повертається на 90° (локальна +Z → світова +X).
			var turn := Basis() if axis.x == 0.0 else Basis(Vector3.UP, PI * 0.5)
			var centre: Vector2 = g["centre"]
			var y: float = height.deck_y(cells[0]) - float(PropLayer.spec_of(m)["deck_top"])
			var xform := Transform3D(turn, Vector3(centre.x, y, centre.y))
			if not broken.has(true):
				layer._add(m, xform, cells)
			elif not broken.has(false):
				layer._add(broken_m, xform, cells)
			else:
				for k in cells.size():
					var one: Array[Vector2i] = [cells[k]]
					layer._add(StringName("%s#%d" % [broken_m if broken[k] else m, k]), xform, one)

	func _length(g: Dictionary) -> int:
		var axis: Vector2 = g["axis"]
		var lo := Vector2i(1 << 20, 1 << 20)
		var hi := -lo
		for c: Vector2i in g["cells"]:
			lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
			hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
		return (hi.x - lo.x + 1) if axis.x != 0.0 else (hi.y - lo.y + 1)

	func _model_length(m: StringName) -> int:
		return roundi(((PropLayer.model(m) as Dictionary)["aabb"] as AABB).size.z)

	# --- дрібні пропси -------------------------------------------------------------------------

	## Прохідна клітинка дошки, де можуть стояти дрібні пропси.
	func open_ground(c: Vector2i) -> bool:
		return on_board(c) and kind(c) == Terrain.Kind.FIELD

	## Пропс уздовж ребра клітинки c з боку d, на KEEP_OUT…0.5 від центру.
	func put_on_edge(m: StringName, c: Vector2i, d: Vector2i, inset: float = 0.44) -> bool:
		var key := Vector4i(c.x, c.y, d.x, d.y)
		if edges.has(key):
			return false
		var yaw: float = 0.0 if d.y != 0 else PI * 0.5
		if put_small(m, c, Vector2(d) * inset, yaw, 1.0, true):
			edges[key] = true
			return true
		return false

	## Огорожа двору — замкнений контур одного типу довкола ділянки: клітинок дошки під будівлями
	## (сусідні будівлі ділять двір), на YARD_OUT за її межею, з хвірткою GATE перед дверима, на
	## дорогу. Порожні клітинки групи BUILDING лишаються за огорожею: обгороджене порожнє місце
	## читається уламком. На опуклих кутах сусідні прольоти подовжуються назустріч, на вгнутих
	## коротшають, тож кути зімкнуті й нічого не стирчить. Де за межею вода чи край дошки, контур
	## уривається: огорожі на воді не буває.
	func _yard_fences() -> void:
		var seen: Dictionary = {}
		var cells: Array = built.keys()
		cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
		for start: Vector2i in cells:
			if seen.has(start) or not on_board(start) or kind(start) != Terrain.Kind.BUILDING:
				continue
			var lot: Dictionary = {start: true}
			var queue: Array[Vector2i] = [start]
			seen[start] = true
			while not queue.is_empty():
				var q: Vector2i = queue.pop_back()
				for d in Board.DIRS_4:
					var n: Vector2i = q + d
					if built.has(n) and on_board(n) and not seen.has(n) and kind(n) == Terrain.Kind.BUILDING:
						seen[n] = true
						lot[n] = true
						queue.append(n)
			_fence_yard(lot, start)

	func _fence_yard(lot: Dictionary, first: Vector2i) -> void:
		# Два типи огорожі на половину, двір бере свій: сусідні двори не однакові.
		var palette: Array[StringName] = PropLayer.models_of(Kind.GARDEN_FENCE)
		if palette.is_empty():
			return
		var base: int = absi(hash(Vector2i(salt, Kind.GARDEN_FENCE))) + half(first)
		var m: StringName = palette[(base + h(first, 121) % 2) % palette.size()]
		var cells: Array = lot.keys()
		cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
		var sides: Array = []
		for g: Vector2i in cells:
			for d in Board.DIRS_4:
				var c: Vector2i = g + d
				if lot.has(c) or not on_board(c):
					continue
				if kind(c) in [Terrain.Kind.FIELD, Terrain.Kind.ROAD, Terrain.Kind.HILL, Terrain.Kind.BUILDING]:
					sides.append([g, d])
		if sides.is_empty():
			return
		# Хвіртка — перед дверима (фасад будинку) і, де можна, на дорогу.
		var door: Array = sides.filter(func(e: Array) -> bool: return built.get(e[0], Vector2i.ZERO) == e[1])
		var to_road: Array = sides.filter(func(e: Array) -> bool: return kind(e[0] + e[1]) == Terrain.Kind.ROAD)
		var door_road: Array = door.filter(func(e: Array) -> bool: return to_road.has(e))
		var pool: Array = door_road
		for alt: Array in [door, to_road, sides]:
			if pool.is_empty():
				pool = alt
		var gate: Array = pool[h(first, 120) % pool.size()]
		for e: Array in sides:
			_yard_segment(m, lot, e[0], e[1], e == gate)

	func _yard_segment(m: StringName, lot: Dictionary, g: Vector2i, d: Vector2i, gate: bool) -> void:
		var c: Vector2i = g + d
		var t := Vector2i(absi(d.y), absi(d.x))
		var ext: Dictionary = {}
		for e: Vector2i in [t, -t]:
			if lot.has(g + e):
				ext[e] = -YARD_OUT if lot.has(c + e) else 0.0
			else:
				ext[e] = YARD_OUT
		# Проліт від lo до hi уздовж t (від центру клітинки); хвіртка вирізає GATE з одного кінця.
		var lo: float = -0.5 - float(ext[-t])
		var hi: float = 0.5 + float(ext[t])
		if gate:
			if h(c, 122) & 1:
				lo += GATE
			else:
				hi -= GATE
		var key := Vector4i(c.x, c.y, -d.x, -d.y)
		if edges.has(key) or hi - lo < 0.05:
			return
		var local: Vector2 = -Vector2(d) * (0.5 - YARD_OUT) + Vector2(t) * ((lo + hi) * 0.5)
		# Подовжена на куті секція може дістати до сусідньої будівлі (руїни) — тоді її нема.
		var mid := Vector2(c) + local
		var half_t: Vector2 = Vector2(t) * (hi - lo) * 0.5
		var span := Rect2(mid - half_t.abs(), half_t.abs() * 2.0).grow(0.3 - 1e-3)
		for pl: Array in placed:
			if span.intersects(pl[0]):
				return
		if put_small(m, c, local, 0.0 if d.y != 0 else PI * 0.5, 1.0, true, hi - lo):
			edges[key] = true
			yard_cells[c] = true

	## Огорожа поля вздовж дороги: відрізками щонайменше у дві клітинки, з одного боку дороги на
	## відрізок і не біля дворів — подвійні паралельні ряди й самотня секція серед поля читаються
	## помилкою.
	func _field_fences() -> void:
		var picks: Dictionary = {}
		for y in size.y:
			for x in size.x:
				var c := Vector2i(x, y)
				if not open_ground(c) or _near_yard(c):
					continue
				for d in Board.DIRS_4:
					var r: Vector2i = c + d
					if kind(r) != Terrain.Kind.ROAD:
						continue
					var t := Vector2i(absi(d.y), absi(d.x))
					var along: int = r.x if t.x != 0 else r.y
					var across: int = r.y if t.x != 0 else r.x
					var hr: int = h(Vector2i(along / FIELD_FENCE_RUN * 2 + t.x, across), 3)
					if hr % 16 >= FIELD_FENCE_CHANCE:
						continue
					var side: int = 1 if (hr / 16) % 2 == 0 else -1
					if -(d.y if t.x != 0 else d.x) != side:
						continue
					picks[Vector4i(c.x, c.y, d.x, d.y)] = true
		var keys: Array = picks.keys()
		keys.sort()
		for k: Vector4i in keys:
			var t := Vector2i(absi(k.w), absi(k.z))
			if not picks.has(Vector4i(k.x + t.x, k.y + t.y, k.z, k.w)) and not picks.has(Vector4i(k.x - t.x, k.y - t.y, k.z, k.w)):
				continue
			var c := Vector2i(k.x, k.y)
			put_on_edge(pick_for_half(Kind.FIELD_FENCE, half(c)), c, Vector2i(k.z, k.w))

	## Клітинка в межах однієї від двору чи будинку: польова огорожа поруч з огорожею двору читається
	## подвійним рядом.
	func _near_yard(c: Vector2i) -> bool:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var n: Vector2i = c + Vector2i(dx, dy)
				if yard_cells.has(n) or kind(n) == Terrain.Kind.BUILDING:
					return true
		return false

	## Тюки на луці, купкою в куті клітинки; не біля води, болота й дороги.
	func _hay() -> void:
		for y in size.y:
			for x in size.x:
				var c := Vector2i(x, y)
				if not open_ground(c) or h(c, 5) % 16 >= HAY_CHANCE:
					continue
				var near_bad := false
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var k: int = kind(c + d)
					near_bad = near_bad or k == Terrain.Kind.WATER or k == Terrain.Kind.MARSH or k == Terrain.Kind.ROAD
				if near_bad:
					continue
				var corner := Vector2(1.0 if h(c, 6) & 1 else -1.0, 1.0 if h(c, 6) & 2 else -1.0) * 0.33
				var m: StringName = pick_for_half(Kind.HAY, half(c))
				var n: int = 2 + h(c, 7) % 2
				for k in n:
					var off := Vector2(float(h(c, 8 + k) % 100) / 100.0 - 0.5, float(h(c, 12 + k) % 100) / 100.0 - 0.5) * 0.12
					put_small(m, c, corner + off - corner.normalized() * 0.09 * k, float(h(c, 16 + k) % 628) / 100.0)

	## Причіп біля подвір'я: один на групу, на полі за огорожею двору (ближче — сама огорожа), уздовж
	## ребра в бік двору.
	func _trailers() -> void:
		var done: Dictionary = {}
		for y in size.y:
			for x in size.x:
				var c := Vector2i(x, y)
				if not open_ground(c) or yard_cells.has(c) or h(c, 20) % 16 >= 4:
					continue
				for d in Board.DIRS_4:
					var f: Vector2i = c + d
					var b: Vector2i = f + d
					if not yard_cells.has(f) or kind(b) != Terrain.Kind.BUILDING or done.has(b / 4):
						continue
					if put_on_edge(pick_for_half(Kind.TRAILER, half(c)), c, d, 0.39):
						done[b / 4] = true
					break

	## Бетонні блоки на дорозі біля мосту: блокпост на кожному в'їзді, по блоку з боків дороги.
	func _blocks() -> void:
		var m: StringName = pick_for_half(Kind.BLOCK, 0)
		for y in size.y:
			for x in size.x:
				var c := Vector2i(x, y)
				if kind(c) != Terrain.Kind.ROAD:
					continue
				for d in Board.DIRS_4:
					var k: int = kind(c + d)
					if k != Terrain.Kind.BRIDGE and k != Terrain.Kind.BRIDGE_DESTROYED:
						continue
					var side := Vector2(d.y, d.x).abs()
					var yaw: float = PI * 0.5 if d.y == 0 else 0.0
					put_small(m, c, side * 0.36 - Vector2(d) * 0.2, yaw + 0.15)
					put_small(m, c, -side * 0.38 - Vector2(d) * 0.25, yaw - 0.1)

	## Каміння на пагорбах: одна-дві брили біля краю клітинки, кожна половина — свої дві породи.
	func _boulders() -> void:
		for y in size.y:
			for x in size.x:
				var c := Vector2i(x, y)
				if kind(c) != Terrain.Kind.HILL:
					continue
				var n: int = 1 + h(c, 30) % 2
				var pool: Array[StringName] = PropLayer.models_of(Kind.BOULDER)
				var base: int = absi(hash(Vector2i(salt, Kind.BOULDER))) + half(c) * 2
				for k in n:
					var m: StringName = pool[(base + h(c, 32 + k) % 2) % pool.size()]
					for attempt in 4:
						var a: float = float(h(c, 40 + k * 5 + attempt) % 628) / 100.0
						var r: float = 0.34 + float(h(c, 60 + k) % 10) / 100.0
						var scale: float = float(PropLayer.spec_of(m).get("scale", 1.0)) * (0.85 + float(h(c, 80 + k) % 30) / 100.0)
						if put_small(m, c, Vector2(cos(a), sin(a)) * r, float(h(c, 70 + k) % 628) / 100.0, scale):
							break

	## Опори вздовж доріг: асфальт і ґрунтівка — 10 кВ з прольотом ~7.5 клітинки, вулиці (бруківка)
	## — 0.4 кВ з ~4.5. Опора стоїть за узбіччям на прохідній клітинці біля її краю; сусідні
	## опори однієї лінії з'єднує дріт.
	func _poles() -> void:
		if height == null or height.roads == null:
			return
		var roads: RoadCourse = height.roads
		for li in roads.lines.size():
			var pts: PackedVector2Array = roads.lines[li]
			if pts.size() < 2:
				continue
			var mid: Vector3 = roads.types[li][pts.size() / 2]
			var line: StringName = &"04kv" if mid.z > maxf(mid.x, mid.y) else &"10kv"
			# Ґрунтівки — лише через одну: не кожна польова дорога веде струм.
			if mid.y > maxf(mid.x, mid.z) and h(Vector2i(li, 0), 90) % 2 == 1:
				continue
			var first := Vector2i(roundi(pts[0].x) - ring, roundi(pts[0].y) - ring)
			var m: StringName = pick_for_half(Kind.POLE, half(first),
					func(n: StringName) -> bool: return PropLayer.spec_of(n)["line"] == line)
			if m == &"":
				continue
			var side: float = 1.0 if h(Vector2i(li, 1), 91) & 1 else -1.0
			var step: float = SPAN[line]
			var dist: float = 0.0
			var next: float = step * 0.5
			var prev: int = -1
			for k in range(1, pts.size()):
				var a: Vector2 = pts[k - 1]
				var b: Vector2 = pts[k]
				var seg: float = a.distance_to(b)
				while next <= dist + seg and seg > 0.0:
					var t: float = (next - dist) / seg
					var p: Vector2 = a.lerp(b, t) - Vector2(ring, ring)
					var tan: Vector2 = (b - a) / seg
					var nrm := Vector2(-tan.y, tan.x) * side
					var half_w: float = float(roads.halfs[li][k]) / 8.0
					var pole: int = _pole_at(m, p + nrm * (half_w + 0.3), tan)
					if pole >= 0 and prev >= 0:
						spans.append([prev, pole])
					prev = pole
					next += step
				dist += seg

	func _pole_at(m: StringName, p: Vector2, tan: Vector2) -> int:
		for shift: float in [0.0, 0.3, -0.3, 0.6, -0.6]:
			var q: Vector2 = p + tan * shift
			var c := Vector2i(roundi(q.x), roundi(q.y))
			if not open_ground(c) and not (on_board(c) and kind(c) == Terrain.Kind.HILL):
				continue
			var before: int = layer._instances.size()
			# Траверса впоперек дороги: дроти йдуть уздовж (локальна Z — вздовж дороги).
			if put_small(m, c, q - Vector2(c), atan2(tan.x, tan.y)):
				return before
		return -1
