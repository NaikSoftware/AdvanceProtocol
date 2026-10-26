class_name PropLayer
extends Node3D
## Пропси поля бою: будівлі, руїни, мости, огорожі, тюки, опори з дротами, причепи, блоки,
## каміння. Лише вигляд — жодне правило їх не читає (docs/art-direction.md «Props»): будівля
## стоїть тільки на клітинках BUILDING і вміщається в їхню групу цілими тайлами, дрібні пропси —
## біля країв прохідних клітинок, ніколи в центрі, де стоїть юніт; техніка, що в'їхала, їх
## розчавлює. Розстановка — чиста функція дошки: той самий світ → ті самі перетворення, усе з
## cell_hash, ніколи Rules.roll чи глобальна випадковість, бо обидва гравці мусять бачити одне.
## Одна MultiMesh на модель — один вузол і по draw call на поверхню (§8).

enum Kind { STRUCTURE, RUIN, BRIDGE, FIELD_FENCE, GARDEN_FENCE, HAY, POLE, TRAILER, BLOCK, BOULDER, YARD }
## Як виглядає розчавлене: LAY — повалене набік, SQUASH — сплющене, SINK — втиснуте в землю.
enum Crush { NONE, LAY, SQUASH, SINK }

const MODEL_DIR: String = "res://assets/props/"
## Модель -> {kind, weight, …}. Слід будівлі в тайлах — з метаданих GLB (`footprint_tiles`), тож
## нова модель того самого виду стає в слот за самим ім'ям. Модель без файлу пропускається.
## max — скільки разів на карту (орієнтир, що має лишатись одним), ring — лише в кільці, gap —
## власний проміжок до сусідньої будівлі, якщо більший за STRUCTURE_GAP, tower —
## вежа (одна на карту, у власному дворі), storeys — двоповерховий (у селі їх не більше половини),
## scale — рівномірний множник розміру (брила завелика для польового каменя, хата на клітинку
## заширока, щоб між сусідніми з камери гри було видно землю),
## map/order/deck_top — міст своєї переправи (DECK_TOP з tools/blender/bridges/build_bridges.py).
const MODELS: Dictionary = {
	&"house_h1": {"kind": Kind.STRUCTURE, "weight": 4},
	&"house_h1_hit": {"kind": Kind.STRUCTURE, "weight": 1},
	&"house_h2": {"kind": Kind.STRUCTURE, "weight": 3},
	&"house_h3": {"kind": Kind.STRUCTURE, "weight": 2, "storeys": 2},
	&"house_h4": {"kind": Kind.STRUCTURE, "weight": 4},
	&"house_h5": {"kind": Kind.STRUCTURE, "weight": 6, "scale": HOUSE_SCALE},
	&"house_h6": {"kind": Kind.STRUCTURE, "weight": 2, "storeys": 2, "scale": HOUSE_SCALE},
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
	&"ruin_h3": {"kind": Kind.RUIN, "weight": 1},
	&"bridge_river_west": {"kind": Kind.BRIDGE, "map": &"river", "order": 0, "deck_top": 0.30},
	&"bridge_river_centre": {"kind": Kind.BRIDGE, "map": &"river", "order": 1, "deck_top": 0.30},
	&"bridge_river_east": {"kind": Kind.BRIDGE, "map": &"river", "order": 2, "deck_top": 0.21},
	&"infra_fence_picket": {"kind": Kind.GARDEN_FENCE, "crush": Crush.LAY},
	# Сільська садиба: дерев'яний штакетник або низький коричневий профлист (ассет 2 м — до ~1.4 м).
	# Зелений профлист з камери гри сірів до бетонних плит — він, як і єврозабір, для ферм.
	&"infra_fence_sheet_green": {"kind": Kind.FIELD_FENCE, "crush": Crush.LAY, "height": 0.7},
	&"infra_fence_sheet_brown": {"kind": Kind.GARDEN_FENCE, "crush": Crush.LAY, "height": 0.7},
	&"infra_fence_euro": {"kind": Kind.FIELD_FENCE, "crush": Crush.LAY},
	&"infra_hay_round": {"kind": Kind.HAY, "crush": Crush.SQUASH},
	&"infra_hay_wrapped": {"kind": Kind.HAY, "crush": Crush.SQUASH},
	&"infra_pole_concrete_10kv": {"kind": Kind.POLE, "line": &"10kv", "crush": Crush.LAY, "scale": 0.85},
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
	&"dead_tree_trunk_02": {"kind": Kind.YARD, "crush": Crush.SINK},
}
## Руїни з глухим фронтоном збоку: ставляться пошкодженим фасадом (−Z) до камери (+x чи +z).
const CAMERA_FRONT: Array[StringName] = [&"ruin_half_house2"]
## Руїни, яких у таблиці ще нема, стають у слот за префіксом імені: напівзруйнована будівля —
## звичайна, повна руїна — рідкісна. Перший збіг виграє.
## Моделі, що лежать на диску, але ще не прийняті: їх не бере ні таблиця, ні префікс.
const RETIRED: Array[StringName] = []
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
## Найменший проміжок між межами будівель (разом зі звісом даху), клітинки: 1 м. Чи читаються два
## будинки окремо, вирішує правило екрана (SCREEN_DEPTH_SEP); цей проміжок лише не дає стінам
## зійтися впритул згори.
const STRUCTURE_GAP: float = 0.125
## Повітка-двірська будівля на клітинці BUILDING без будинку: f8_shed, зменшена так, щоб вільно
## стала в клітинку (ассет на 0.96 клітинки не влазить із відступом до огорожі).
const YARD_SHED: StringName = &"f8_shed"
## Хата на клітинку (ассет на 0.94 клітинки, ~7.5 м) — рівномірно до ~6.4 м: така сільська хата
## звична, а між двома сусідніми з камери гри лишається смуга землі.
const HOUSE_SCALE: float = 1.0
## Відвід до хати — від стовпа не далі за стільки клітинок.
const SERVICE_REACH: float = 5.5
## Стовп, будівля й паркан тримаються від води й болота щонайменше на стільки клітинок.
const WATER_CLEAR: float = 0.4
const YARD_SHED_SCALE: float = 0.7
## Велика будівля (слід понад клітинку) зі звісом тримається на стільки всередині своєї групи
## BUILDING (клітинки, ~2 м). Будинок на одну клітинку стоїть у ній по центру й тримає лише
## YARD_CLEAR_SMALL до межі: з повним відступом жоден не влазить, а з цим до огорожі на YARD_OUT
## лишається ≥ 0.3 клітинки й разом із її товщиною.
const YARD_CLEAR: float = 0.25
const YARD_CLEAR_SMALL: float = 0.03
## Хвіртка в огорожі двору, клітинки (~3.6 м): решта ребра обгороджена, двір не відкритий на вулицю.
const GATE: float = 0.45
## Найкоротша секція огорожі, клітинки (4 м): коротший обрубок читається уламком, не огорожею.
const MIN_FENCE: float = 0.5
## Кут камери для правила екрана (IsoCameraRig: 38–55°, бій здебільшого близько) і найменша глибина
## між будівлями, що на екрані накладаються: ближча будівля не сміє ховати дальшу, бо тоді дві
## читаються однією, хоч згори між ними й 2 м.
# shortcut: один кут для правила екрана, хоча риг ходить 38–55°; на 55° силуети коротші, тож 40°
# суворіше — рахувати на кожному зумі, якщо на дальньому знову злипнуться будинки.
const SCREEN_PITCH_DEG: float = 40.0
const SCREEN_DEPTH_SEP: float = 1.2
## Земля між силуетами на екрані, клітинки (~1.2 м): силуети, що торкаються кутами, читаються одним.
const SCREEN_GROUND: float = 0.15
## Те саме між хатою й руїною (~0.4 м): руїна низька й напівзавалена, силует не злипається.
const SCREEN_GROUND_RUIN: float = 0.05
## Огорожа двору стоїть за межею групи BUILDING на ~2.2 м: будинок на одну клітинку займає її
## майже всю, і до огорожі однаково лишається ≥ 0.3 клітинки; секція ще далеко від центру сусідньої
## клітинки, де стоїть юніт.
## 0.285: лице секції (півтовщини 0.0125) лишається за 0.2 від центру сусідньої клітинки.
const YARD_OUT: float = 0.285
## Город займає таку частку двору садиби (30–50 %): решта — трава, хата, сарай.
const GARDEN_SHARE: float = 0.4
## Відступи сторони кільця паркану від межі двору, від бажаного (назовні) до найглибшого всередину;
## глибше −0.25 паркан зайшов би в квадрат юніта в центрі клітинки (KEEP_OUT).
const RING_OFFSETS: Array[float] = [YARD_OUT, 0.15, 0.0, -0.12, -0.25]
## Кам'яні брили й бетонні блоки темніші за ассет: світлі, вони читались плямами фарби.
const STONE_TINT: float = 0.85
## Опори ЛЕП: альбедо ассета ~0.56 (світлий бетон), і на сонці тонкий стовп світився білим поверх
## трави. Вивітрене дерево й брудний бетон — не світліші за ґрунт поруч.
const POLE_TINT: float = 0.45
## Пляма дотику під брилою чи блоком: у скільки разів ширша за сам пропс і наскільки темна.
const CONTACT_SPREAD: float = 1.25
const CONTACT_ALPHA: float = 0.6
const _FADE_SHADER: Shader = preload("res://game/battle/shaders/prop_fade.gdshader")
const _THIN_SHADER: Shader = preload("res://game/battle/shaders/prop_thin.gdshader")
## Огорожа без прозорих щілин — той самий шейдер без discard: рання перевірка глибини лишається.
static var _thin_solid_shader: Shader
const _CONTACT_SHADER: Shader = preload("res://game/battle/shaders/prop_contact.gdshader")
const _GARDEN_SHADER: Shader = preload("res://game/battle/shaders/prop_garden.gdshader")
const _GRIME_SHADER: Shader = preload("res://game/battle/shaders/prop_grime.gdshader")
const _RUBBLE_SHADER: Shader = preload("res://game/battle/shaders/prop_rubble.gdshader")
## Найбільший перепад рельєфу під хатою без цоколя, клітинки (1 м). Більший — хата стає на середню
## висоту: вгору по схилу врізана в землю, донизу — на кам'яному цоколі.
const PLINTH_FROM: float = 0.125
const PLINTH_ALBEDO: Color = Color(0.34, 0.32, 0.29)
## Пояс бруду довкола хати, клітинки (~0.5 м).
const GRIME_M: float = 0.0625
## Запас від краю дорожнього покриття для парканів і дрібних пропсів, клітинки (~0.4 м).
const ROAD_PAD: float = 0.05
## Сарай, причіп чи техніка — лише при хаті: хата в межах стількох клітинок (Чебишов).
const HOUSE_NEAR: int = 2
## Той самий шейдер будівлі без розчинення: discard у шейдері вимикає ранню перевірку глибини на
## мобільних GPU, тож будівлі моделі, над якою зараз ніхто не стоїть, малюються без нього.
static var _solid_shader: Shader

## Модель -> {mesh, local, footprint, aabb, wires, tris}; спільний на процес, бо GLB кешуються.
static var _models: Dictionary = {}
## Модель -> ShaderMaterial розчинення (лише будівлі й руїни).
static var _fade_materials: Dictionary = {}
## Вид -> моделі на диску: перелік теки й сортування не повторюються на кожну групу будівель.
static var _by_kind: Dictionary = {}
## Модель -> мокра копія сітки (мости під дощем).
static var _wet_meshes: Dictionary = {}
const WET_DARK: float = 0.75
const WET_ROUGHNESS: float = 0.55
const BRIDGE_ROUGH: float = 0.85
## Тюки: загорнутий у плівку мав шорсткість 0.35 і блищав, як метал.
const HAY_ROUGH: float = 0.8
## Спекуляр будівель: мінеральні поверхні (тиньк, цегла, шифер) ≤ 0.3, якщо GLB не каже менше.
const MINERAL_SPECULAR: float = 0.3
## Модель -> {solid, fade} ShaderMaterial будівлі для поточного вузла.
var _node_materials: Dictionary = {}
var _contacts: MultiMeshInstance3D
var _apply_queued: bool = false

## Кожен екземпляр: {model, transform, cells (клітинки дошки під ним), crush, broken_of}.
var _instances: Array[Dictionary] = []
## Вузол (модель або «модель@ring») -> модель.
var _node_model: Dictionary = {}
## Вузол -> MultiMeshInstance3D і індекси екземплярів у ньому.
var _nodes: Dictionary = {}
var _slots: Dictionary = {}
## Городи садиб з макету: {rect, dir — від хати, green — частка зеленого}.
var _garden_plots: Array[Dictionary] = []
## Розстановка останньої побудови: для перевірки дорожнього покриття (тести, інструменти).
var _placer: RefCounted
## Городні грядки: клітинка BUILDING без будинку й без повітки — город (лише вигляд).
var _gardens: Array[Vector2i] = []
var _garden_node: MultiMeshInstance3D
## Наскільки грядки зелені (BattleLook.season): літо — зелень, рання осінь — жовта, пізня — гола рілля.
var garden_green: float = 0.2
## Цоколі хат на схилі: перетворення коробки одиничного розміру.
var _plinths: Array[Transform3D] = []
## Відводи до хат: [індекс опори, точка на стіні хати].
var _drops: Array = []
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
## Мокра карта (BattleLook.wetness): мости темніші й з полиском. Імпортований матеріал мосту
## погоди не читає, тож мокра копія сітки; ставити до build().
var wet: bool = false


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
	# Маркер chimney_top (порожній вузол над шапкою димаря): туди чіпляється дим.
	var chimneys: Array[Vector3] = []
	for n in root.find_children("chimney_top*", "", true, false):
		chimneys.append(_to_root(n as Node3D, root).origin)
	var tris: int = 0
	for s in mi.mesh.get_surface_count():
		tris += (mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	var info: Dictionary = {"mesh": _tuned_mesh(name, mi.mesh), "local": local, "footprint": footprint,
			"aabb": local * mi.mesh.get_aabb(), "wires": wires, "tris": tris, "chimneys": chimneys}
	root.free()
	_models[name] = info
	return info


## Копія сітки з власними матеріалами для огорож (двобічне світло) і каміння (темніше). Сам GLB
## не чіпаємо: load() ділить його сітку з усіма, хто його вантажить.
static func _tuned_mesh(name: StringName, mesh: Mesh) -> Mesh:
	var kind: int = int(spec_of(name).get("kind", -1))
	if kind not in [Kind.FIELD_FENCE, Kind.GARDEN_FENCE, Kind.BOULDER, Kind.BLOCK, Kind.POLE, Kind.HAY]:
		return mesh
	var copy: Mesh = mesh.duplicate()
	for i in copy.get_surface_count():
		var src := copy.surface_get_material(i) as BaseMaterial3D
		if src == null:
			continue
		if kind == Kind.HAY:
			var matte: BaseMaterial3D = src.duplicate()
			matte.roughness = maxf(src.roughness, HAY_ROUGH)
			matte.metallic = 0.0
			copy.surface_set_material(i, matte)
			continue
		if kind == Kind.BOULDER or kind == Kind.BLOCK or kind == Kind.POLE:
			var tint: float = POLE_TINT if kind == Kind.POLE else STONE_TINT
			var dark: BaseMaterial3D = src.duplicate()
			dark.albedo_color = src.albedo_color * Color(tint, tint, tint, 1.0)
			dark.roughness = maxf(src.roughness, 0.95 if kind == Kind.POLE else src.roughness)
			copy.surface_set_material(i, dark)
			continue
		var thin := ShaderMaterial.new()
		var cut: bool = src.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		thin.shader = _THIN_SHADER if cut else _thin_solid()
		thin.set_shader_parameter("albedo_tex", src.albedo_texture)
		thin.set_shader_parameter("albedo_color", src.albedo_color)
		thin.set_shader_parameter("use_vertex_color", src.vertex_color_use_as_albedo)
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
	_node_model.clear()
	_spans.clear()
	_drops.clear()
	_plinths.clear()
	_wires = null
	_contacts = null
	_garden_node = null
	_gardens.clear()
	_garden_plots.clear()
	_placer = null
	_node_materials.clear()
	forest_cells.clear()
	_board_size = board_size
	if world.width <= 0 or world.height <= 0:
		return
	var p := _Placer.new(self, world, ring, board_size, height, map_key, half_dir)
	p.place_all()
	_spans = p.spans
	_gardens = p.gardens
	_garden_plots = p.garden_plots
	_placer = p
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


## Світові точки верху димарів хат дошки (вузол chimney_top моделі) — для диму з димарів.
func chimney_tops() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for inst in _instances:
		if int(spec_of(inst["model"])["kind"]) != Kind.STRUCTURE or inst.get("yard", false):
			continue
		if not _on_board((inst["cells"] as Array)[0]):
			continue
		var t: Transform3D = _final_transform(inst) * (model(inst["model"]) as Dictionary)["local"]
		for p: Vector3 in (model(inst["model"]) as Dictionary).get("chimneys", []):
			out.append(t * p)
	return out


## Центри руїн дошки на землі (середина обрису, висота підошви) — для тління руїн.
func ruin_centres() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for inst in _instances:
		if int(spec_of(inst["model"])["kind"]) != Kind.RUIN or not _on_board((inst["cells"] as Array)[0]):
			continue
		var box: AABB = (inst["transform"] as Transform3D) * ((model(inst["model"]) as Dictionary)["aabb"] as AABB)
		out.append(Vector3(box.get_center().x, box.position.y, box.get_center().z))
	return out


## Точка на покритті дороги (осі й ширина RoadCourse) з запасом pad, клітинки.
func on_road(p: Vector2, pad: float = 0.0) -> bool:
	return _placer != null and _placer.on_road(p, pad)


## Для тестів: екземпляри, що стоять на клітинці дошки.
func instances_on(cell: Vector2i) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _gardens.has(cell):
		out.append({"model": &"garden", "transform": Transform3D(Basis(), Vector3(cell.x, 0.0, cell.y)),
				"faded": false, "crushed": false, "yard": true})
	for inst in _instances:
		if (inst["cells"] as Array).has(cell):
			out.append({"model": inst["model"], "transform": _final_transform(inst),
					"faded": _is_faded(inst), "crushed": _is_crushed(inst), "yard": inst.get("yard", false)})
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


## yard — двірське вбрання клітинки без будинку (зменшена повітка, дрова, тюки): правила
## відстані між будинками його не стосуються.
func _add(model_name: StringName, xform: Transform3D, cells: Array[Vector2i], yard: bool = false) -> int:
	_instances.append({"model": model_name, "transform": xform, "cells": cells,
			"crush": int(spec_of(model_name).get("crush", Crush.NONE)), "yard": yard})
	return _instances.size() - 1


## Будівлі кільця — окремий вузол на модель, без тіні: MultiMesh відсікається камерою й тінню
## цілим, тож спільний із дошкою вузол малював би кільце (і його тінь) навіть на близькому зумі.
func _build_nodes(haze: bool) -> void:
	var by_node: Dictionary = {}
	for i in _instances.size():
		var m: StringName = _instances[i]["model"]
		var key: StringName = m
		var k: int = int(spec_of(m)["kind"])
		if (k == Kind.STRUCTURE or k == Kind.RUIN) and not _on_board((_instances[i]["cells"] as Array)[0]):
			key = StringName(String(m) + "@ring")
		if not by_node.has(key):
			by_node[key] = []
			_node_model[key] = m
		(by_node[key] as Array).append(i)
	var names: Array = by_node.keys()
	names.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for key: StringName in names:
		var m: StringName = _node_model[key]
		var ring: bool = String(key).ends_with("@ring")
		var info: Dictionary = model(m)
		var kind: int = int(spec_of(m)["kind"])
		var fades: bool = kind == Kind.STRUCTURE or kind == Kind.RUIN
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = fades
		mm.mesh = _bridge_mesh(m, info["mesh"], wet) if kind == Kind.BRIDGE else info["mesh"]
		mm.instance_count = (by_node[key] as Array).size()
		var mmi := MultiMeshInstance3D.new()
		# Godot міняє «@» в імені вузла на «_», тож вузол кільця — «модель_ring».
		mmi.name = String(key).replace("@ring", "_ring")
		mmi.multimesh = mm
		# §8: тіні — юнітам; пропсам — лише будинкам дошки, де без тіні на сонці дім висить над
		# землею. Руїни (низькі й важкі, до 4 тис. трикутників) лягають плямою дотику, як каміння;
		# огорожі, опори й дрібнота без тіні: їхній прохід тіней коштував десятки тисяч трикутників
		# на кадр, а тонка тінь на м'якому сонці майже не видна.
		var casts: bool = structure_shadows and not ring and kind == Kind.STRUCTURE
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if casts else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if fades:
			_node_materials[key] = {"fade": _fade_material(m, info, haze, false), "solid": _fade_material(m, info, haze, true)}
			mmi.material_override = _node_materials[key]["solid"]
		add_child(mmi)
		_nodes[key] = mmi
		_slots[key] = by_node[key]
	if not _spans.is_empty() or not _drops.is_empty():
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
	_build_gardens()
	_build_grime()
	_build_plinths()
	_build_rubble_floors()


## Городи: сусідні клітинки городу зливаються в одну ділянку (жадібні прямокутники, тож Г-подібна
## група не ляже на хату), трохи повернуту й з відступом від меж — один город на двір, а не плитка
## на кожну клітинку. Ряди — шейдер, крок у метрах однаковий для будь-якого розміру ділянки.
func _build_gardens() -> void:
	if not _garden_plots.is_empty():
		_build_garden_plots()
		return
	if _gardens.is_empty():
		return
	var plots: Array[Rect2i] = _garden_rects()
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE
	var mat := ShaderMaterial.new()
	mat.shader = _GARDEN_SHADER
	mat.set_shader_parameter("green", garden_green)
	quad.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = plots.size()
	for i in plots.size():
		var r: Rect2i = plots[i]
		var hv: int = absi(cell_hash(r.position, 144))
		# Ряди вздовж довшого боку; ділянка трохи повернута й менша за свої клітинки.
		var long_x: bool = r.size.x >= r.size.y
		var yaw: float = (0.0 if long_x else PI * 0.5) + (float(hv % 41) / 40.0 - 0.5) * 0.2
		var len_a: float = float(maxi(r.size.x, r.size.y)) - 0.28 - float(hv / 64 % 10) / 100.0
		var len_b: float = float(mini(r.size.x, r.size.y)) - 0.3 - float(hv / 1024 % 10) / 100.0
		var centre := Vector2(r.position) + Vector2(r.size - Vector2i.ONE) * 0.5
		var hx: float = TerrainHeight.ground_y(centre.x + 0.3, centre.y) - TerrainHeight.ground_y(centre.x - 0.3, centre.y)
		var hz: float = TerrainHeight.ground_y(centre.x, centre.y + 0.3) - TerrainHeight.ground_y(centre.x, centre.y - 0.3)
		var up := Vector3(-hx / 0.6, 1.0, -hz / 0.6).normalized()
		var right: Vector3 = Vector3(cos(yaw), 0.0, -sin(yaw)).slide(up).normalized()
		mm.set_instance_transform(i, Transform3D(Basis(right * len_a, up, right.cross(up) * len_b),
				Vector3(centre.x, TerrainHeight.ground_y(centre.x, centre.y) + 0.006, centre.y)))
		# r — скільки рядів на ділянці (ряд ~0.9 м), g — зсув візерунка краю.
		mm.set_instance_custom_data(i, Color(len_a * 8.0 / 0.9, float(hv % 97) / 97.0, 0.0, 0.0))
	_garden_node = MultiMeshInstance3D.new()
	_garden_node.name = "GardenBeds"
	_garden_node.multimesh = mm
	_garden_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_garden_node)


## Город садиби — частина двору за хатою (GARDEN_SHARE двору), м'який рваний край у траву.
func _build_garden_plots() -> void:
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE
	var mat := ShaderMaterial.new()
	mat.shader = _GARDEN_SHADER
	mat.set_shader_parameter("green", garden_green)
	quad.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = _garden_plots.size()
	for i in _garden_plots.size():
		var gp: Dictionary = _garden_plots[i]
		var rect: Rect2 = gp["rect"]
		var away: Vector2 = gp["dir"]
		var centre: Vector2 = rect.get_center()
		var hv: int = absi(cell_hash(Vector2i(centre.floor()), 144))
		# Ряди впоперек напряму від хати (UV.x уздовж away), трохи повернуто.
		var along_x: bool = absf(away.x) >= absf(away.y)
		var along: float = rect.size.x if along_x else rect.size.y
		var across: float = rect.size.y if along_x else rect.size.x
		var yaw: float = (0.0 if along_x else PI * 0.5) + (float(hv / 16 % 21) / 20.0 - 0.5) * 0.06
		var hx: float = TerrainHeight.ground_y(centre.x + 0.3, centre.y) - TerrainHeight.ground_y(centre.x - 0.3, centre.y)
		var hz: float = TerrainHeight.ground_y(centre.x, centre.y + 0.3) - TerrainHeight.ground_y(centre.x, centre.y - 0.3)
		var up := Vector3(-hx / 0.6, 1.0, -hz / 0.6).normalized()
		var right: Vector3 = Vector3(cos(yaw), 0.0, -sin(yaw)).slide(up).normalized()
		mm.set_instance_transform(i, Transform3D(Basis(right * along, up, right.cross(up) * across),
				Vector3(centre.x, TerrainHeight.ground_y(centre.x, centre.y) + 0.004, centre.y)))
		# r — рядів (крок ~0.7 м, клітинка 8 м), g — зерно краю, b — частка зеленого.
		mm.set_instance_custom_data(i, Color(along * 8.0 / 0.7, float(hv % 97) / 97.0, float(gp["green"]), 0.0))
	_garden_node = MultiMeshInstance3D.new()
	_garden_node.name = "GardenBeds"
	_garden_node.multimesh = mm
	_garden_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_garden_node)


## Жадібне покриття клітинок городу прямокутниками: рядок за рядком, вшир, потім углиб.
func _garden_rects() -> Array[Rect2i]:
	var left: Dictionary = {}
	for c in _gardens:
		left[c] = true
	var cells: Array = left.keys()
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	var out: Array[Rect2i] = []
	for c: Vector2i in cells:
		if not left.has(c):
			continue
		var w: int = 1
		while left.has(c + Vector2i(w, 0)):
			w += 1
		var hgt: int = 1
		while true:
			var full := true
			for x in w:
				full = full and left.has(c + Vector2i(x, hgt))
			if not full:
				break
			hgt += 1
		for y in hgt:
			for x in w:
				left.erase(c + Vector2i(x, y))
		out.append(Rect2i(c, Vector2i(w, hgt)))
	return out


## Підлога руїн дошки: плита уламків на обрисі руїни (трохи ширша за нього), щоб крізь пролом не
## було видно трави. Одна MultiMesh, два трикутники на руїну.
func _build_rubble_floors() -> void:
	var xforms: Array[Transform3D] = []
	for inst in _instances:
		if int(spec_of(inst["model"])["kind"]) != Kind.RUIN or not _on_board((inst["cells"] as Array)[0]):
			continue
		var box: AABB = (inst["transform"] as Transform3D) * ((model(inst["model"]) as Dictionary)["aabb"] as AABB)
		var c := Vector2(box.get_center().x, box.get_center().z)
		xforms.append(Transform3D(Basis.from_scale(Vector3(box.size.x * 1.08, 1.0, box.size.z * 1.08)),
				Vector3(c.x, TerrainHeight.ground_y(c.x, c.y) + 0.004, c.y)))
	if xforms.is_empty():
		return
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE
	var mat := ShaderMaterial.new()
	mat.shader = _RUBBLE_SHADER
	quad.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = quad
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var node := MultiMeshInstance3D.new()
	node.name = "RubbleFloors"
	node.multimesh = mm
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)


## Кам'яні цоколі хат на схилі: одна MultiMesh коробок.
func _build_plinths() -> void:
	if _plinths.is_empty():
		return
	var box := BoxMesh.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = PLINTH_ALBEDO
	mat.roughness = 1.0
	box.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = box
	mm.instance_count = _plinths.size()
	for i in _plinths.size():
		mm.set_instance_transform(i, _plinths[i])
	var node := MultiMeshInstance3D.new()
	node.name = "Plinths"
	node.multimesh = mm
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if structure_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)


func plinths() -> Array[Transform3D]:
	return _plinths


## Пояс бруду довкола хат дошки: квадрат на сліді хати, ширший на GRIME_M з кожного боку; шейдер
## темнить смугу вздовж стін. Одна MultiMesh, два трикутники на хату.
func _build_grime() -> void:
	var xforms: Array[Transform3D] = []
	for inst in _instances:
		if int(spec_of(inst["model"])["kind"]) != Kind.STRUCTURE or inst.get("yard", false):
			continue
		if not _on_board((inst["cells"] as Array)[0]):
			continue
		var t: Transform3D = inst["transform"]
		var box: AABB = t * ((model(inst["model"]) as Dictionary)["aabb"] as AABB)
		var size := Vector2(box.size.x, box.size.z) + Vector2.ONE * GRIME_M * 2.0
		var c := Vector2(box.get_center().x, box.get_center().z)
		xforms.append(Transform3D(Basis.from_scale(Vector3(size.x, 1.0, size.y)),
				Vector3(c.x, TerrainHeight.ground_y(c.x, c.y) + 0.005, c.y)))
	if xforms.is_empty():
		return
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE
	var mat := ShaderMaterial.new()
	mat.shader = _GRIME_SHADER
	quad.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = quad
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var node := MultiMeshInstance3D.new()
	node.name = "HouseGrime"
	node.multimesh = mm
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)


## Пляма дотику під брилами й блоками: один квадрат на кожен, лягає за схилом, одна MultiMesh. Без
## неї світлий камінь на траві читається наклеєним, а справжня тінь по всіх брилах — задорога.
func _build_contacts() -> void:
	var xforms: Array[Transform3D] = []
	var heights: Array[float] = []
	for inst in _instances:
		var k: int = int(spec_of(inst["model"])["kind"])
		if k != Kind.BOULDER and k != Kind.BLOCK and k != Kind.RUIN:
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
		# Права трійка (z = x × y): дзеркальна перевернула б обхід трикутників, і cull_back викинув би
		# пляму зовсім.
		xforms.append(Transform3D(Basis(right * size.x, up, back * size.y),
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
		# Усе, що є в матеріалі GLB: карта шорсткості з її каналом, метал, AO, сила нормалей і
		# спекуляр; інакше атлас із фактурою в бою читається рівним пластиком.
		mat.set_shader_parameter("albedo_tex", src.albedo_texture)
		mat.set_shader_parameter("normal_tex", src.normal_texture)
		mat.set_shader_parameter("normal_scale", src.normal_scale if src.normal_enabled else 1.0)
		mat.set_shader_parameter("albedo_color", src.albedo_color)
		mat.set_shader_parameter("roughness", src.roughness)
		mat.set_shader_parameter("metallic", src.metallic)
		mat.set_shader_parameter("specular", minf(src.metallic_specular, MINERAL_SPECULAR))
		mat.set_shader_parameter("use_roughness_tex", src.roughness_texture != null)
		if src.roughness_texture != null:
			mat.set_shader_parameter("roughness_tex", src.roughness_texture)
			mat.set_shader_parameter("roughness_channel", _channel(src.roughness_texture_channel))
		mat.set_shader_parameter("use_metallic_tex", src.metallic_texture != null)
		if src.metallic_texture != null:
			mat.set_shader_parameter("metallic_tex", src.metallic_texture)
			mat.set_shader_parameter("metallic_channel", _channel(src.metallic_texture_channel))
		var ao: bool = src.ao_enabled and src.ao_texture != null
		mat.set_shader_parameter("use_ao_tex", ao)
		if ao:
			mat.set_shader_parameter("ao_tex", src.ao_texture)
			mat.set_shader_parameter("ao_channel", _channel(src.ao_texture_channel))
			mat.set_shader_parameter("ao_light_affect", src.ao_light_affect)
	if haze:
		Surroundings.apply(mat, _board_size)
	_fade_materials[key] = mat
	return mat


## Копія сітки мосту під погоду карти. Ассет має «мокрі» поверхні з шорсткістю 0.15 і сталь 0.5 —
## у кадрі міст блищав, як скло. Шорсткість тепер не нижча за BRIDGE_ROUGH (суха карта) чи
## WET_ROUGHNESS (мокра; там ще й темніше).
static func _bridge_mesh(m: StringName, mesh: Mesh, wet_look: bool) -> Mesh:
	var key: String = "%s:%s" % [m, wet_look]
	if _wet_meshes.has(key):
		return _wet_meshes[key]
	var copy: Mesh = mesh.duplicate()
	for i in copy.get_surface_count():
		var src := copy.surface_get_material(i) as BaseMaterial3D
		if src == null:
			continue
		var w: BaseMaterial3D = src.duplicate()
		var dark: float = WET_DARK if wet_look else 1.0
		w.albedo_color = src.albedo_color * Color(dark, dark, dark, 1.0)
		w.roughness = maxf(src.roughness, WET_ROUGHNESS if wet_look else BRIDGE_ROUGH)
		w.metallic = minf(src.metallic, 0.1)
		copy.surface_set_material(i, w)
	_wet_meshes[key] = copy
	return copy


static func _thin_solid() -> Shader:
	if _thin_solid_shader == null:
		_thin_solid_shader = Shader.new()
		var code: String = _THIN_SHADER.code
		var cut: String = "\tif (alpha_cut > 0.0 && tex.a < alpha_cut) {\n\t\tdiscard;\n\t}\n"
		assert(code.contains(cut), "PropLayer: відсікання в prop_thin.gdshader змінилось")
		_thin_solid_shader.code = code.replace(cut, "")
	return _thin_solid_shader


## Канал текстури StandardMaterial3D (TEXTURE_CHANNEL_*) як вектор для dot у шейдері.
static func _channel(ch: int) -> Vector4:
	return [Vector4(1, 0, 0, 0), Vector4(0, 1, 0, 0), Vector4(0, 0, 1, 0), Vector4(0, 0, 0, 1), Vector4(0.299, 0.587, 0.114, 0)][ch]


static func _solid() -> Shader:
	if _solid_shader == null:
		_solid_shader = Shader.new()
		var code: String = _FADE_SHADER.code
		var cut: String = "\tif (v_fade > bayer4(FRAGCOORD.xy)) {\n\t\tdiscard;\n\t}\n"
		assert(code.contains(cut), "PropLayer: розчинення в prop_fade.gdshader змінилось")
		_solid_shader.code = code.replace(cut, "")
	return _solid_shader


## Відтінок даху будинку (множник альбедо даху): сіро-синій бляшаний переважає, решта —
## червоно-брунатний, зелений і брунатний лист. З хешу клітинки: обидва гравці бачать те саме.
const ROOF_TINTS: Array[Color] = [Color(1, 1, 1), Color(1, 1, 1), Color(1.25, 0.8, 0.68),
		Color(0.82, 1.08, 0.82), Color(1.12, 0.92, 0.74)]


func _roof_tint(inst: Dictionary) -> Color:
	if int(spec_of(inst["model"])["kind"]) != Kind.STRUCTURE or inst.get("yard", false):
		return Color(1, 1, 1)
	var c: Vector2i = (inst["cells"] as Array)[0]
	return ROOF_TINTS[absi(cell_hash(c, 9137)) % ROOF_TINTS.size()]


func _on_board(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < _board_size.x and c.y < _board_size.y


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
	for key: StringName in _nodes:
		var m: StringName = _node_model[key]
		var mmi: MultiMeshInstance3D = _nodes[key]
		var mm: MultiMesh = mmi.multimesh
		var slots: Array = _slots[key]
		var local: Transform3D = (model(m) as Dictionary)["local"]
		var any_faded := false
		for k in slots.size():
			var inst: Dictionary = _instances[slots[k]]
			mm.set_instance_transform(k, _final_transform(inst) * local)
			if mm.use_custom_data:
				var faded: bool = _is_faded(inst)
				any_faded = any_faded or faded
				var tint: Color = _roof_tint(inst)
				mm.set_instance_custom_data(k, Color(tint.r, tint.g, tint.b, FADE if faded else 0.0))
		if _node_materials.has(key):
			mmi.material_override = _node_materials[key]["fade" if any_faded else "solid"]
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
	# Відвід до хати: два дроти від траверси стовпа до стіни під дахом, з невеликим провисом.
	for dr: Array in _drops:
		var pole: Dictionary = _instances[dr[0]]
		if _is_crushed(pole):
			continue
		var wp: Array[Vector3] = (model(pole["model"]) as Dictionary)["wires"]
		if wp.is_empty():
			continue
		var target: Vector3 = dr[1]
		for k in [0, wp.size() - 1]:
			var pa: Vector3 = (pole["transform"] as Transform3D) * wp[k]
			var pb: Vector3 = target + Vector3(0.0, 0.0, 0.02 * (k - 0.5))
			for j in WIRE_SEGMENTS:
				for t: float in [float(j) / WIRE_SEGMENTS, float(j + 1) / WIRE_SEGMENTS]:
					verts.append(pa.lerp(pb, t) - Vector3(0.0, WIRE_SAG * 0.4 * 4.0 * t * (1.0 - t), 0.0))
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
	## Скільки поставлено будинків: [одноповерхових, двоповерхових].
	var storeys: Array[int] = [0, 0]
	## Макет сіл карти (VillageLayout); порожній — розстановка процедурою, як для тестових дощок.
	var layout: Dictionary = {}
	## Клітинки дошки, на яких уже стоїть дрібний пропс (одна річ на ребро).
	var edges: Dictionary = {}
	var gardens: Array[Vector2i] = []
	## Городи садиб: {rect, dir — від хати, green — частка зеленого}.
	var garden_plots: Array[Dictionary] = []
	## Клітинка дошки -> відрізки осі дороги поруч [a, b, півширина в клітинках]: покриття дороги
	## — власна геометрія (RoadCourse), не вид клітинки, тож паркан на «полі» міг лягти на асфальт.
	var road_index: Dictionary = {}
	var road_indexed := false
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
		layout = VillageLayout.for_map(p_map)

	func place_all() -> void:
		if not layout.is_empty():
			_structures()
			_homesteads()
			_bridges()
			_layout_hay()
			_blocks()
			_boulders()
			_layout_poles()
			return
		_structures()
		_dress_yards()
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

	## Точка на покритті дороги (з запасом pad), за осями RoadCourse і їхньою шириною.
	func on_road(p: Vector2, pad: float) -> bool:
		if not road_indexed:
			_index_roads()
		var c := Vector2i(roundi(p.x), roundi(p.y))
		for seg: Array in road_index.get(c, []):
			var a: Vector2 = seg[0]
			var b: Vector2 = seg[1]
			var ab: Vector2 = b - a
			var t: float = clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
			if p.distance_to(a + ab * t) < float(seg[2]) + pad:
				return true
		return false

	func _index_roads() -> void:
		road_indexed = true
		if height == null or height.roads == null:
			return
		var roads: RoadCourse = height.roads
		for li in roads.lines.size():
			var pts: PackedVector2Array = roads.lines[li]
			for k in range(1, pts.size()):
				var a: Vector2 = pts[k - 1] - Vector2(ring, ring)
				var b: Vector2 = pts[k] - Vector2(ring, ring)
				var half: float = float(roads.halfs[li][k]) / 8.0
				var lo := Vector2i(floori(minf(a.x, b.x) - half - 0.5), floori(minf(a.y, b.y) - half - 0.5))
				var hi := Vector2i(ceili(maxf(a.x, b.x) + half + 0.5), ceili(maxf(a.y, b.y) + half + 0.5))
				for y in range(lo.y, hi.y + 1):
					for x in range(lo.x, hi.x + 1):
						var key := Vector2i(x, y)
						if not road_index.has(key):
							road_index[key] = []
						(road_index[key] as Array).append([a, b, half])

	## Межа пропса в XZ (кути й середина) лежить на покритті дороги.
	func _box_on_road(m: StringName, xform: Transform3D) -> bool:
		var box: AABB = xform * ((PropLayer.model(m) as Dictionary)["aabb"] as AABB)
		for v: Vector2 in [Vector2(box.position.x, box.position.z), Vector2(box.end.x, box.position.z),
				Vector2(box.end.x, box.end.z), Vector2(box.position.x, box.end.z),
				Vector2(box.get_center().x, box.get_center().z)]:
			if on_road(v, ROAD_PAD):
				return true
		return false

	## Точка ближче за clear до клітинки води чи болота.
	func near_wet(p: Vector2, clear: float) -> bool:
		var c := Vector2i(roundi(p.x), roundi(p.y))
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var n: Vector2i = c + Vector2i(dx, dy)
				var kd: int = kind(n)
				if kd != Terrain.Kind.WATER and kd != Terrain.Kind.MARSH:
					continue
				var nearest := Vector2(clampf(p.x, n.x - 0.5, n.x + 0.5), clampf(p.y, n.y - 0.5, n.y + 0.5))
				if p.distance_to(nearest) < clear:
					return true
		return false

	## Хата (будинок, не вежа й не двірське вбрання) в межах HOUSE_NEAR клітинок.
	func house_near(c: Vector2i) -> bool:
		for dy in range(-HOUSE_NEAR, HOUSE_NEAR + 1):
			for dx in range(-HOUSE_NEAR, HOUSE_NEAR + 1):
				var n: StringName = model_at.get(c + Vector2i(dx, dy), &"")
				if n == &"":
					continue
				var s: Dictionary = PropLayer.spec_of(n)
				if int(s["kind"]) == Kind.STRUCTURE and not bool(s.get("tower", false)):
					return true
		return false

	const N_FACE := Vector2i(0, -1)
	const W_FACE := Vector2i(-1, 0)
	const S_FACE := Vector2i(0, 1)
	const E_FACE := Vector2i(1, 0)

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
			# Секція обертається довкола середини: та стоїть на середній висоті кінців, тож обидва
			# кінці на землі, а не один у ній.
			y = (y0 + y1) * 0.5
		var xform := Transform3D(basis * Basis.from_scale(Vector3(length, 1.0, 1.0) * scale), Vector3(x, y, z))
		if not clear_of_centre(m, xform, c) or _box_on_road(m, xform):
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
			# Села дошки — з макету карти; процедура лишається для кільця.
			if not layout.is_empty() and target == Terrain.Kind.BUILDING:
				groups = groups.filter(func(g: Array) -> bool: return not board_first.has(g))
				board_first = []
			for g: Array[Vector2i] in board_first + groups.filter(func(g: Array) -> bool: return not board_first.has(g)):
				_fill_group(g, kind_id)

	func _fill_group(group: Array[Vector2i], kind_id: int) -> void:
		var free: Dictionary = {}
		for c in group:
			free[c] = true
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
				# Двоповерхових не більше, ніж одноповерхових: село — це передусім хати.
				if int(s.get("storeys", 1)) >= 2 and storeys[1] >= storeys[0]:
					continue
				var fp: Vector2i = (PropLayer.model(m) as Dictionary)["footprint"]
				if fp == Vector2i.ZERO:
					continue
				for c in group:
					if not free.has(c):
						continue
					for rot in 4:
						# Фасад до камери: −Z після повороту дивиться на +z (rot 2) чи +x (rot 3).
						if PropLayer.CAMERA_FRONT.has(m) and rot < 2:
							continue
						var size_r: Vector2i = fp if rot % 2 == 0 else Vector2i(fp.y, fp.x)
						# Руїна стоїть на кожній клітинці RUBBLE (вона й є вид клітинки), тож правила відстані
						# її не відсувають; будинки ж тримаються від руїн, як від будь-якої будівлі.
						var ruin: bool = kind_id == Kind.RUIN
						if _fits(free, c, size_r) and _inside_yard(m, c, rot, size_r) \
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
		var box: AABB = Transform3D(_basis_of(m, rot), Vector3(centre.x, 0.0, centre.y)) \
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
			var margin: float = SCREEN_GROUND_RUIN if p[4] else SCREEN_GROUND
			if (scr[0] as Rect2).grow(margin).intersects(p[2]) and _depth_gap(scr[1], p[3]) < SCREEN_DEPTH_SEP:
				return false
		return true

	func _height_of(m: StringName) -> float:
		return ((PropLayer.model(m) as Dictionary)["aabb"] as AABB).size.y * _scale_of(m)

	func _scale_of(m: StringName) -> float:
		return float(PropLayer.spec_of(m).get("scale", 1.0))

	func _basis_of(m: StringName, rot: int) -> Basis:
		return Basis(Vector3.UP, rot * PI * 0.5).scaled(Vector3.ONE * _scale_of(m))

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
	func _inside_yard(m: StringName, origin: Vector2i, rot: int, s: Vector2i) -> bool:
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
		# І під самою моделлю: хата буває ширша за 0.8 клітинки, і на схилі її кут висів би.
		var r_box: Rect2 = _rect_of(m, origin, rot, s)
		var hi: float = -INF
		for v: Vector2 in [r_box.position, r_box.end, Vector2(r_box.position.x, r_box.end.y),
				Vector2(r_box.end.x, r_box.position.y), r_box.get_center()]:
			lo = minf(lo, ground(v.x, v.y))
			hi = maxf(hi, ground(v.x, v.y))
		# Хата дошки на схилі: на середину, уверх по схилу — врізана, донизу — цоколь.
		if hi - lo > PLINTH_FROM and int(PropLayer.spec_of(m)["kind"]) == Kind.STRUCTURE and on_board(origin):
			var base: float = (lo + hi) * 0.5
			var foot: Rect2 = r_box.grow(-0.02)
			layer._plinths.append(Transform3D(Basis.from_scale(Vector3(foot.size.x, base - lo + 0.02, foot.size.y)),
					Vector3(foot.get_center().x, (base + lo) * 0.5, foot.get_center().y)))
			lo = base
		used[m] = int(used.get(m, 0)) + 1
		var sp: Dictionary = PropLayer.spec_of(m)
		if int(sp["kind"]) == Kind.STRUCTURE and not bool(sp.get("tower", false)):
			storeys[1 if int(sp.get("storeys", 1)) >= 2 else 0] += 1
		var r: Rect2 = _rect_of(m, origin, rot, s)
		var scr: Array = _screen_of(r, _height_of(m))
		placed.append([r, _gap_of(m), scr[0], scr[1], int(PropLayer.spec_of(m)["kind"]) == Kind.RUIN])
		for c in cells:
			model_at[c] = m
		var centre := Vector2(origin) + Vector2(s - Vector2i.ONE) * 0.5
		layer._add(m, Transform3D(_basis_of(m, rot), Vector3(centre.x, lo, centre.y)), _board_only(cells))

	func _board_only(cells: Array[Vector2i]) -> Array[Vector2i]:
		var out: Array[Vector2i] = []
		for c in cells:
			if on_board(c):
				out.append(c)
		# Будівля кільця не стоїть на жодній клітинці дошки, але має ключ для пошуку.
		return out if not out.is_empty() else cells

	# --- двори ------------------------------------------------------------------------------

	## Кожна клітинка BUILDING дошки читається забудованою (§8: вид клітинки видно). Хата — головне;
	## де вона не стала, там двір хати: одна повітка й один причіп на двір як доповнення, решта —
	## город із грядками й тюком. Клітинки двору обгороджуються разом із хатою одним контуром.
	func _dress_yards() -> void:
		var shed_in: Dictionary = {}
		var trailer_in: Dictionary = {}
		for y in size.y:
			for x in size.x:
				var c := Vector2i(x, y)
				if kind(c) != Terrain.Kind.BUILDING or built.has(c):
					continue
				built[c] = Vector2i.ZERO
				var yard: Vector2i = _yard_key(c)
				var yaw: float = float(h(c, 140) % 4) * PI * 0.5
				var lo: float = minf(ground(c.x - 0.3, c.y - 0.3), ground(c.x + 0.3, c.y + 0.3))
				# Поруч із вежею повітки нема: вежа стоїть у власному дворі.
				var by_tower := false
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						var n: StringName = model_at.get(c + Vector2i(dx, dy), &"")
						by_tower = by_tower or bool(PropLayer.spec_of(n).get("tower", false))
				var roll: int = h(c, 141) % 3 if house_near(c) else 2
				if roll == 0 and not by_tower and not shed_in.has(yard) and PropLayer.model(YARD_SHED) != null:
					shed_in[yard] = true
					var cells: Array[Vector2i] = [c]
					layer._add(YARD_SHED, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * YARD_SHED_SCALE),
							Vector3(c.x, lo, c.y)), cells, true)
				elif roll == 1 and not trailer_in.has(yard):
					trailer_in[yard] = true
					_yard_item(pick_for_half(Kind.TRAILER, half(c)), c, Vector2(0.0, 0.1), yaw)
				elif _house_beside(c) and h(c, 145) % 3 != 0:
					# Город — при самій хаті, і не на кожній вільній клітинці.
					gardens.append(c)
				else:
					_yard_item(pick_for_half(Kind.HAY, half(c)), c, Vector2(0.25, 0.25).rotated(yaw), float(h(c, 142) % 628) / 100.0)

	## Хата на сусідній клітинці (і по діагоналі).
	func _house_beside(c: Vector2i) -> bool:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var n: StringName = model_at.get(c + Vector2i(dx, dy), &"")
				if n == &"":
					continue
				var sp: Dictionary = PropLayer.spec_of(n)
				if int(sp["kind"]) == Kind.STRUCTURE and not bool(sp.get("tower", false)):
					return true
		return false

	## Двір — зв'язна група BUILDING дошки; ключ — її найменша клітинка.
	func _yard_key(c: Vector2i) -> Vector2i:
		var best: Vector2i = c
		var seen: Dictionary = {c: true}
		var queue: Array[Vector2i] = [c]
		while not queue.is_empty():
			var q: Vector2i = queue.pop_back()
			if q.y < best.y or (q.y == best.y and q.x < best.x):
				best = q
			for d in Board.DIRS_4:
				var n: Vector2i = q + d
				if not seen.has(n) and on_board(n) and kind(n) == Terrain.Kind.BUILDING:
					seen[n] = true
					queue.append(n)
		return best

	func _yard_item(m: StringName, c: Vector2i, local: Vector2, yaw: float) -> void:
		if m == &"" or PropLayer.model(m) == null:
			return
		var x: float = c.x + local.x
		var z: float = c.y + local.y
		var cells: Array[Vector2i] = [c]
		layer._add(m, Transform3D(Basis(Vector3.UP, yaw), Vector3(x, ground(x, z), z)), cells, true)

	# --- села за макетом карти -----------------------------------------------------------------

	## Садиби з VillageLayout: хата на своїй клітинці фасадом до дороги, город за нею (30–50 % двору,
	## частина зелена, частина гола), сарай, решта двору — трава. Клітинки між садибами (orchards) —
	## трав'яні двори й лук із поодиноким дров'яником, без городів.
	func _homesteads() -> void:
		var homes: Array = layout.get("homes", [])
		var owner_of: Dictionary = {}
		for i in homes.size():
			for c: Vector2i in homes[i]["cells"]:
				owner_of[c] = i
		var sheds: Array[Rect2] = []
		for i in homes.size():
			var home: Dictionary = homes[i]
			var hc: Vector2i = home["house"]
			var rot: int = [N_FACE, W_FACE, S_FACE, E_FACE].find(home["face"])
			_put_structure(_house_model(hc, i), hc, rot, Vector2i.ONE, {})
			var gcells: Array = home.get("garden", [])
			if not gcells.is_empty():
				# Город — одна ділянка по клітинках городу, площею ~40 % двору (не більше 80 % тих клітинок),
				# зсунута від хати вглиб.
				var lo := Vector2(gcells[0])
				var hi := Vector2(gcells[0])
				for g: Vector2i in gcells:
					lo = lo.min(Vector2(g))
					hi = hi.max(Vector2(g))
					gardens.append(g)
				var box := Rect2(lo - Vector2(0.5, 0.5), hi - lo + Vector2.ONE)
				var f: float = sqrt(minf(GARDEN_SHARE * float((home["cells"] as Array).size()), 0.8 * box.get_area()) / box.get_area())
				var away: Vector2 = (box.get_center() - Vector2(hc)).normalized()
				var size: Vector2 = box.size * f
				var centre: Vector2 = box.get_center() + away * (box.size - size) * 0.25
				# Частка зеленого: картопля чи капуста на частині городу, решта — голий ґрунт.
				garden_plots.append({"rect": Rect2(centre - size * 0.5, size), "dir": away,
						"green": [0.0, 0.4, 0.65][h(hc, 151) % 3]})
			for c: Vector2i in home["cells"]:
				if not built.has(c):
					built[c] = Vector2i.ZERO
			if home.has("shed") and PropLayer.model(YARD_SHED) != null:
				var sc: Vector2i = home["shed"]
				var lo: float = minf(ground(sc.x - 0.3, sc.y - 0.3), ground(sc.x + 0.3, sc.y + 0.3))
				var cells: Array[Vector2i] = [sc]
				var xf := Transform3D(Basis(Vector3.UP, rot * PI * 0.5).scaled(Vector3.ONE * YARD_SHED_SCALE), Vector3(sc.x, lo, sc.y))
				layer._add(YARD_SHED, xf, cells, true)
				var box: AABB = xf * ((PropLayer.model(YARD_SHED) as Dictionary)["aabb"] as AABB)
				sheds.append(Rect2(box.position.x, box.position.z, box.size.x, box.size.z))
		for c: Vector2i in layout.get("orchards", []):
			built[c] = Vector2i.ZERO
			# Трав'яний двір; на кожному четвертому — дров'яник під стіною двору.
			if h(c, 152) % 4 == 0:
				var yaw: float = float(h(c, 153) % 4) * PI * 0.5
				for k in 2:
					var local: Vector2 = Vector2(0.3, -0.25 + 0.1 * k).rotated(yaw)
					_yard_item(&"dead_tree_trunk_02", c, local, yaw + PI * 0.5 + 0.05 * k)
		for i in homes.size():
			_fence_ring(i, homes[i], owner_of, sheds)

	## Хата садиби: здебільшого одноповерхова, двоповерхова — кожна четверта за хешем; сусідні садиби
	## не повторюють модель.
	func _house_model(hc: Vector2i, i: int) -> StringName:
		var single: StringName = &"house_h5"
		var tall: StringName = &"house_h6"
		var m: StringName = tall if h(hc, 150) % 4 == 0 else single
		if not _no_twin(m, hc, Vector2i.ONE):
			m = single if m == tall else tall
		return m if PropLayer.model(m) != null else single

	## Паркан садиби — одне замкнене кільце по межі двору з одними воротами GATE до дороги. Межа двору
	## обходиться як многокутник; кожна сторона стає на YARD_OUT назовні, а якщо там дорога, вода чи
	## будівля ближче 0.3 клітинки — зсувається всередину двору, але не зникає. Кути — перетини
	## сусідніх сторін, тож завжди зімкнуті. Межу з сусідньою садибою ставить одна з них, рівно по межі.
	func _fence_ring(i: int, home: Dictionary, owner_of: Dictionary, sheds: Array[Rect2]) -> void:
		var lot: Dictionary = {}
		for c: Vector2i in home["cells"]:
			lot[c] = true
		var hc: Vector2i = home["house"]
		var palette: Array[StringName] = PropLayer.models_of(Kind.GARDEN_FENCE)
		if palette.is_empty():
			return
		var base: int = absi(hash(Vector2i(salt, Kind.GARDEN_FENCE))) + half(hc)
		var m: StringName = palette[(base + h(hc, 121)) % palette.size()]
		var sides: Array[Dictionary] = _lot_sides(lot, owner_of)
		if sides.is_empty():
			return
		# Ворота: на стороні, що містить ребро фасаду хати; інакше — на стороні до дороги.
		var gate_side: int = -1
		for k in sides.size():
			for e: Array in sides[k]["edges"]:
				if e[0] == hc and e[1] == home["face"] and int(sides[k]["nb"]) < 0:
					gate_side = k
		if gate_side < 0:
			for k in sides.size():
				if int(sides[k]["nb"]) < 0 and kind((sides[k]["edges"][0] as Array)[0] + sides[k]["d"]) == Terrain.Kind.ROAD:
					gate_side = k
					break
		# Відступ кожної сторони: найдальший назовні, де сторона найменше перекрита дорогою, водою чи
		# будівлями; що лишилось перекритим — _fence_run обходить. Межа з сусідом — рівно по межі.
		for k in sides.size():
			var sd: Dictionary = sides[k]
			sd["o"] = 0.0
			if int(sd["nb"]) >= 0:
				continue
			var best: float = INF
			for o: float in RING_OFFSETS:
				var blocked: float = _ring_side_blocked(sd, o, sheds)
				if blocked < best - 1e-3:
					best = blocked
					sd["o"] = o
				if blocked == 0.0:
					break
		var n: int = sides.size()
		for k in n:
			var sd: Dictionary = sides[k]
			if int(sd["nb"]) >= 0 and int(sd["nb"]) < i:
				continue
			var p0: Vector2 = _ring_corner(sides[(k - 1 + n) % n], sd)
			var p1: Vector2 = _ring_corner(sd, sides[(k + 1) % n])
			var spans_out: Array = [[p0, p1]]
			if k == gate_side:
				# Ворота навпроти хати, уздовж сторони; кінці воріт не ближче 0.15 до кутів.
				var along: Vector2 = (p1 - p0).normalized()
				var total: float = p0.distance_to(p1)
				# Ворота навпроти хати; шматок паркану біля воріт або ≥ MIN_FENCE, або нуль (ворота в куті).
				var at: float = (Vector2(hc) - p0).dot(along) - GATE * 0.5
				if at < MIN_FENCE:
					at = 0.0 if at < MIN_FENCE * 0.5 or total - GATE < 2.0 * MIN_FENCE else MIN_FENCE
				if total - at - GATE < MIN_FENCE:
					at = total - GATE if total - at - GATE < MIN_FENCE * 0.5 or at < MIN_FENCE else total - GATE - MIN_FENCE
				at = clampf(at, 0.0, maxf(total - GATE, 0.0))
				spans_out = [[p0, p0 + along * at], [p0 + along * (at + GATE), p1]]
			for sp: Array in spans_out:
				_fence_run(m, sp[0], sp[1], lot, sheds)

	## Сторони межі двору як замкнений обхід: кожна — {d: нормаль назовні, nb: садиба по той бік чи −1,
	## edges: [[клітинка, d], …], line: координата межі (x для вертикальної, y для горизонтальної)}.
	func _lot_sides(lot: Dictionary, owner_of: Dictionary) -> Array[Dictionary]:
		var by_start: Dictionary = {}
		var cells: Array = lot.keys()
		cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
		for g: Vector2i in cells:
			for d in Board.DIRS_4:
				if lot.has(g + d):
					continue
				var c := Vector2(g)
				var a: Vector2
				var b: Vector2
				if d == Vector2i(0, -1):
					a = c + Vector2(0.5, -0.5)
					b = c + Vector2(-0.5, -0.5)
				elif d == Vector2i(-1, 0):
					a = c + Vector2(-0.5, -0.5)
					b = c + Vector2(-0.5, 0.5)
				elif d == Vector2i(0, 1):
					a = c + Vector2(-0.5, 0.5)
					b = c + Vector2(0.5, 0.5)
				else:
					a = c + Vector2(0.5, 0.5)
					b = c + Vector2(0.5, -0.5)
				by_start[Vector2i(roundi(a.x * 2.0), roundi(a.y * 2.0))] = {"g": g, "d": d, "a": a, "b": b,
						"nb": int(owner_of.get(g + d, -1))}
		if by_start.is_empty():
			return []
		# Обхід від найменшого початку; кожне ребро веде до наступного, що починається в його кінці.
		var keys: Array = by_start.keys()
		keys.sort()
		var chain: Array[Dictionary] = []
		var cur: Dictionary = by_start[keys[0]]
		for guard in by_start.size():
			chain.append(cur)
			var nk := Vector2i(roundi(cur["b"].x * 2.0), roundi(cur["b"].y * 2.0))
			if not by_start.has(nk) or by_start[nk] == chain[0]:
				break
			cur = by_start[nk]
		# Зливаємо підряд ребра з тією самою нормаллю й тим самим сусідом у сторону.
		var sides: Array[Dictionary] = []
		for e in chain:
			if not sides.is_empty() and sides.back()["d"] == e["d"] and sides.back()["nb"] == e["nb"]:
				(sides.back()["edges"] as Array).append([e["g"], e["d"]])
				continue
			var line: float = e["a"].y if (e["d"] as Vector2i).y != 0 else e["a"].x
			sides.append({"d": e["d"], "nb": e["nb"], "edges": [[e["g"], e["d"]]], "line": line,
					"from": e["a"], "o": 0.0})
		# Перша й остання сторони можуть бути однією, розірваною початком обходу.
		if sides.size() > 1 and sides[0]["d"] == sides.back()["d"] and sides[0]["nb"] == sides.back()["nb"]:
			(sides[0]["edges"] as Array).append_array(sides.back()["edges"])
			sides.pop_back()
		return sides

	## Кут між двома послідовними сторонами: x — з вертикальної, y — з горизонтальної (зі зсувами).
	func _ring_corner(s0: Dictionary, s1: Dictionary) -> Vector2:
		var v: Dictionary = s0 if (s0["d"] as Vector2i).x != 0 else s1
		var hz: Dictionary = s1 if v == s0 else s0
		var x: float = float(v["line"]) + float((v["d"] as Vector2i).x) * float(v["o"])
		var y: float = float(hz["line"]) + float((hz["d"] as Vector2i).y) * float(hz["o"])
		return Vector2(x, y)

	## Частка сторони на відступі o, що лягла б на дорогу, воду чи ближче 0.3 до будівлі або сараю.
	## Назовні на болото чи уламки сторона не виходить зовсім (частка 1).
	func _ring_side_blocked(sd: Dictionary, o: float, sheds: Array[Rect2]) -> float:
		var d: Vector2i = sd["d"]
		var hit: int = 0
		var n: int = 0
		for e: Array in sd["edges"]:
			var g: Vector2i = e[0]
			if o > 0.0 and kind(g + d) not in [Terrain.Kind.FIELD, Terrain.Kind.ROAD, Terrain.Kind.HILL, Terrain.Kind.BUILDING]:
				return 1.0
			var mid: Vector2 = Vector2(g) + Vector2(d) * (0.5 + o)
			var t := Vector2(absf(d.y), absf(d.x))
			for k in 9:
				n += 1
				if _fence_blocked(mid + t * (float(k) / 8.0 - 0.5), sheds):
					hit += 1
		return float(hit) / float(maxi(n, 1))

	## Точка паркану заборонена: дорога, вода, ближче 0.3 до будівлі чи сараю; +0.02 — товщина секції.
	func _fence_blocked(q: Vector2, sheds: Array[Rect2]) -> bool:
		if on_road(q, ROAD_PAD + 0.02):
			return true
		# Вода й болото — квадратом довкола клітинки, не колом: паркан не підходить і до кута берега.
		# +0.08: на крутому березі секція нахилена схилом і верхом виходить за свій кінець.
		var c := Vector2i(roundi(q.x), roundi(q.y))
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var n: Vector2i = c + Vector2i(dx, dy)
				if kind(n) in [Terrain.Kind.WATER, Terrain.Kind.MARSH] \
						and absf(q.x - n.x) < 0.5 + WATER_CLEAR + 0.08 and absf(q.y - n.y) < 0.5 + WATER_CLEAR + 0.08:
					return true
		for p: Array in placed:
			if (p[0] as Rect2).grow(0.32).has_point(q):
				return true
		for r in sheds:
			if r.grow(0.32).has_point(q):
				return true
		return false

	## Ділянка паркану від a до b, розірвана там, де дорога, вода чи хата (≥ 0.3 від даху): стіна хати
	## сама замикає двір. Шматки, коротші за MIN_FENCE, читаються уламком — їх нема.
	func _fence_run(m: StringName, a: Vector2, b: Vector2, lot: Dictionary, sheds: Array[Rect2]) -> void:
		var total: float = a.distance_to(b)
		if total < 0.05:
			return
		var dir: Vector2 = (b - a) / total
		# Вільні проміжки з кроком 0.04 (~0.3 м): паркан рветься на дорозі, воді й біля будівель.
		var steps: int = maxi(1, ceili(total / 0.04))
		var from: float = -1.0
		for k in steps + 1:
			var t: float = total * float(k) / float(steps)
			var free: bool = not _fence_blocked(a + dir * t, sheds)
			if free and from < 0.0:
				from = t
			if (not free or k == steps) and from >= 0.0:
				var to: float = t if free else t - total / float(steps)
				if to - from >= MIN_FENCE:
					_fence_straight(m, a + dir * from, a + dir * to, lot)
				from = -1.0

	## Пряма ділянка паркану: рівні секції не довші за клітинку, кожна лежить на землі обома кінцями;
	## секція належить найближчій клітинці двору, тож давить її той, хто заїхав у двір.
	func _fence_straight(m: StringName, a: Vector2, b: Vector2, lot: Dictionary) -> void:
		var total: float = a.distance_to(b)
		var n: int = maxi(1, ceili(total / 1.0))
		var along: Vector2 = (b - a) / float(n)
		var hs: float = float(PropLayer.spec_of(m).get("height", 1.0))
		var model_len: float = ((PropLayer.model(m) as Dictionary)["aabb"] as AABB).size.x
		for k in n:
			var p0: Vector2 = a + along * k
			var p1: Vector2 = p0 + along
			var mid: Vector2 = (p0 + p1) * 0.5
			var yaw: float = atan2(-along.y, along.x)
			var y0: float = ground(p0.x, p0.y)
			var y1: float = ground(p1.x, p1.y)
			var length: float = along.length()
			var basis := Basis(Vector3.UP, yaw)
			basis = Basis(basis.z, atan2(y1 - y0, length)) * basis
			var xf := Transform3D(basis * Basis.from_scale(Vector3(length / model_len, hs, 1.0)), Vector3(mid.x, (y0 + y1) * 0.5, mid.y))
			var c: Vector2i = lot.keys()[0]
			for g: Vector2i in lot:
				if Vector2(g).distance_squared_to(mid) < Vector2(c).distance_squared_to(mid):
					c = g
			var cells: Array[Vector2i] = [c]
			layer._add(m, xf, cells)
			yard_cells[c] = true

	## Тюки з макету: на краю поля, поодинці чи вільною парою, кожен своїм поворотом.
	func _layout_hay() -> void:
		for p0: Vector2 in layout.get("hay", []):
			var c := Vector2i(roundi(p0.x), roundi(p0.y))
			# Тюк — біля краю клітинки, не в центрі, де стоїть юніт.
			var local: Vector2 = p0 - Vector2(c)
			if absf(local.x) < 0.32 and absf(local.y) < 0.32:
				local = (local if local.length() > 0.01 else Vector2(1, 0)).normalized() * 0.4
			var p: Vector2 = Vector2(c) + local
			# Тюк — лише на полі (край поля), не в лісі й не на пагорбі.
			if not on_board(c) or kind(c) != Terrain.Kind.FIELD:
				continue
			var m: StringName = pick_for_half(Kind.HAY, half(c))
			var n: int = 1 + h(c, 7) % 2
			for k in n:
				var q: Vector2 = p + Vector2(0.18 * k, 0.05 * k)
				var cells: Array[Vector2i] = [c]
				var xform := Transform3D(Basis(Vector3.UP, float(h(c, 16 + k) % 628) / 100.0), Vector3(q.x, ground(q.x, q.y), q.y))
				if m != &"" and not _box_on_road(m, xform):
					layer._add(m, xform, cells)

	## Траси ЛЕП з макету: стовпи з рівним кроком уздовж ламаної, на твердій землі (не у воді, не
	## на дорозі, не в садибі) — інакше найближче місце вздовж траси; над водою проліт не довший за
	## півтора кроки. Сусідні стовпи однієї траси з'єднує дріт; хату — відвід від найближчого стовпа.
	func _layout_poles() -> void:
		for line: Dictionary in layout.get("lines", []):
			var kind_name: StringName = line["kind"]
			var m: StringName = &"infra_pole_concrete_10kv" if kind_name == &"10kv" else &"infra_pole_concrete_04kv"
			if PropLayer.model(m) == null:
				continue
			var pts: Array = line["points"]
			var step: float = SPAN[kind_name]
			var length: float = 0.0
			for k in range(1, pts.size()):
				length += (pts[k] as Vector2).distance_to(pts[k - 1])
			var prev: int = -1
			var prev_at := Vector2.INF
			var s: float = 0.5
			while s <= length - 0.3:
				var placed_at: Vector2 = Vector2.INF
				var idx: int = -1
				for off: float in _pole_offsets(step):
					var q: float = clampf(s + off, 0.0, length)
					var p: Vector2 = _point_at(pts, q)
					var t: Vector2 = _tangent_at(pts, q)
					idx = _pole_on(m, p, t)
					if idx >= 0:
						placed_at = p
						s = q
						break
				if idx >= 0:
					if prev >= 0 and prev_at.distance_to(placed_at) <= step * 1.5 + 0.5:
						spans.append([prev, idx])
					prev = idx
					prev_at = placed_at
				s += step
		_service_drops()

	func _pole_offsets(step: float) -> Array[float]:
		var out: Array[float] = [0.0]
		var k: float = 0.25
		while k <= step * 0.5:
			out.append_array([-k, k])
			k += 0.25
		return out

	func _point_at(pts: Array, s: float) -> Vector2:
		var acc: float = 0.0
		for k in range(1, pts.size()):
			var a: Vector2 = pts[k - 1]
			var b: Vector2 = pts[k]
			var l: float = a.distance_to(b)
			if acc + l >= s:
				return a.lerp(b, (s - acc) / maxf(l, 1e-6))
			acc += l
		return pts.back()

	func _tangent_at(pts: Array, s: float) -> Vector2:
		var acc: float = 0.0
		for k in range(1, pts.size()):
			var a: Vector2 = pts[k - 1]
			var b: Vector2 = pts[k]
			var l: float = a.distance_to(b)
			if acc + l >= s:
				return (b - a).normalized()
			acc += l
		return Vector2(0, 1)

	## Стовп на точці траси, якщо там тверда земля поза садибами й дорогою; індекс екземпляра чи −1.
	func _pole_on(m: StringName, p: Vector2, t: Vector2) -> int:
		var c := Vector2i(roundi(p.x), roundi(p.y))
		if not on_board(c) or kind(c) not in [Terrain.Kind.FIELD, Terrain.Kind.HILL] or on_road(p, 0.1):
			return -1
		# Стовп на березі, не в руслі й не над болотом.
		if near_wet(p, WATER_CLEAR + 0.15):
			return -1
		var before: int = layer._instances.size()
		# Стовп у метрах: 0.4 кВ — 8.8 м (ассет), 10 кВ — з 10.7 до ~9.1 м (scale у таблиці).
		if put_small(m, c, p - Vector2(c), atan2(t.x, t.y), float(PropLayer.spec_of(m).get("scale", 1.0))):
			return before
		return -1

	## Відвід до кожної хати від найближчого стовпа (до SERVICE_REACH клітинок): два дроти до стіни
	## під дахом, з боку стовпа, — не в землю.
	func _service_drops() -> void:
		var poles: Array[int] = []
		for i in layer._instances.size():
			if int(PropLayer.spec_of(layer._instances[i]["model"])["kind"]) == Kind.POLE:
				poles.append(i)
		for home: Dictionary in layout.get("homes", []):
			var hc: Vector2i = home["house"]
			var best: int = -1
			var best_d: float = SERVICE_REACH
			for i in poles:
				var o: Vector3 = (layer._instances[i]["transform"] as Transform3D).origin
				var dist: float = Vector2(o.x, o.z).distance_to(Vector2(hc))
				if dist < best_d:
					best_d = dist
					best = i
			if best < 0:
				continue
			var house_i: int = -1
			for i in layer._instances.size():
				if (layer._instances[i]["cells"] as Array).has(hc) and int(PropLayer.spec_of(layer._instances[i]["model"])["kind"]) == Kind.STRUCTURE \
						and not layer._instances[i].get("yard", false):
					house_i = i
			if house_i < 0:
				continue
			var ht: Transform3D = layer._instances[house_i]["transform"]
			var box: AABB = ht * ((PropLayer.model(layer._instances[house_i]["model"]) as Dictionary)["aabb"] as AABB)
			var po: Vector3 = (layer._instances[best]["transform"] as Transform3D).origin
			var to_pole := Vector2(po.x - box.get_center().x, po.z - box.get_center().z).normalized()
			var wall := Vector2(box.get_center().x, box.get_center().z) + to_pole * minf(box.size.x, box.size.z) * 0.48
			layer._drops.append([best, Vector3(wall.x, box.position.y + box.size.y * 0.55, wall.y)])

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
		var plans: Array[Dictionary] = []
		for e: Array in sides:
			var plan: Dictionary = _yard_segment(lot, e[0], e[1], e == gate)
			if not plan.is_empty():
				plans.append(plan)
		# Секція, що ні з ким не стикується кінцем, — самотня панель серед двору: її нема.
		for plan in plans:
			var joined := false
			for other in plans:
				if other == plan:
					continue
				for a: Vector2 in plan["ends"]:
					for b: Vector2 in other["ends"]:
						joined = joined or a.distance_to(b) < 0.15
			if not joined:
				continue
			var c: Vector2i = plan["c"]
			if put_small(m, c, plan["local"], plan["yaw"], 1.0, true, plan["length"]):
				edges[plan["key"]] = true
				yard_cells[c] = true

	## План секції огорожі на ребрі ділянки (без розстановки): {} — секції тут не буде.
	func _yard_segment(lot: Dictionary, g: Vector2i, d: Vector2i, gate: bool) -> Dictionary:
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
		if edges.has(key) or hi - lo < MIN_FENCE:
			return {}
		# Секція тримає ≥ 0.3 клітинки від будь-якої будівлі (зокрема руїни на сусідній клітинці) і
		# не лягає на дорогу: заважає — коротшає з обох кінців, коротша за MIN_FENCE не стає зовсім.
		var cut: float = 0.0
		while not _span_clear(c, d, t, lo + cut, hi - cut):
			cut += 0.05
			if hi - lo - 2.0 * cut < MIN_FENCE:
				return {}
		lo += cut
		hi -= cut
		var base: Vector2 = Vector2(c) - Vector2(d) * (0.5 - YARD_OUT)
		return {"c": c, "key": key, "length": hi - lo, "yaw": 0.0 if d.y != 0 else PI * 0.5,
				"local": base - Vector2(c) + Vector2(t) * ((lo + hi) * 0.5),
				"ends": [base + Vector2(t) * lo, base + Vector2(t) * hi]}

	func _span_clear(c: Vector2i, d: Vector2i, t: Vector2i, lo: float, hi: float) -> bool:
		var mid: Vector2 = Vector2(c) - Vector2(d) * (0.5 - YARD_OUT) + Vector2(t) * ((lo + hi) * 0.5)
		var half_t: Vector2 = (Vector2(t) * (hi - lo) * 0.5).abs()
		# Паркан не лягає на дорогу й не висить над водою: секція коротшає, доки не зійде з них.
		for k in 9:
			var q: Vector2 = mid + (Vector2(t) * (hi - lo) * 0.5) * (float(k) / 4.0 - 1.0)
			if on_road(q, ROAD_PAD) or near_wet(q, WATER_CLEAR):
				return false
		var span := Rect2(mid - half_t, half_t * 2.0).grow(0.3 - 1e-3)
		for pl: Array in placed:
			if span.intersects(pl[0]):
				return false
		return true

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
				# Тюк один чи вільна пара, кожен своїм поворотом: три однакові поруч читаються рядом копій.
				var n: int = 1 + h(c, 7) % 2
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
					if not yard_cells.has(f) or kind(b) != Terrain.Kind.BUILDING or done.has(b / 4) or not house_near(c):
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
					# На узбіччі, не на асфальті: put_small відкидає блок на покритті дороги.
					put_small(m, c, side * 0.43 - Vector2(d) * 0.2, yaw + 0.15)
					put_small(m, c, -side * 0.43 - Vector2(d) * 0.3, yaw - 0.1)

	## Каміння на пагорбах: одна-дві брили біля краю клітинки, кожна половина — свої дві породи.
	func _boulders() -> void:
		for y in size.y:
			for x in size.x:
				var c := Vector2i(x, y)
				if kind(c) != Terrain.Kind.HILL:
					continue
				# Одна брила на клітинку, і не на кожній: дрібнота коштувала ~17 тис. трикутників на кадр.
				if h(c, 29) % 3 == 0:
					continue
				var n: int = 1
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
