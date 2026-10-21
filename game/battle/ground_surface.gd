class_name GroundSurface
extends MeshInstance3D
## Суцільна земля під дошкою (Phase 5a): один меш, один draw call (§8), колір і
## рельєф дає шейдер з карти видів, а не плитки на вид.
##
## §3.5: місцевість публічна й на повній яскравості — тут немає і не може бути
## жодного зв'язку з туманом. Рельєф (TerrainHeight, рішення власника 2026-10-22) —
## лише вигляд: вершинний шейдер піднімає сітку за картою висот, оверлеї лягають на ту
## саму поверхню (IsoCameraRig.cell_to_world), правила висоти не читають.

## Порядок шарів Texture2DArray — тут, поруч із TEX_LAYER_FOR_KIND, а не в
## окремому .tres, щоб відповідність вид -> шар читалась в одному місці.
const TEX_LAYERS: Array[String] = ["road", "field", "forest", "hill", "marsh", "mud", "rubble", "bank"]

## Скільки метрів покриває один повтор текстури шару (в порядку TEX_LAYERS), і
## глибина рельєфу шару в метрах (альфа альбедо = висота). Пояснення цифр — у ground.gdshader.
## Варіантів макро-текстури на шар (комірка гекс-сітки обирає свій). Файли
## macro/<шар>_albedo_<n>.png, n = 0..MACRO_VARIANTS-1; бракуючий n — копія варіанта 0.
const MACRO_VARIANTS: int = 2
const REPEAT_M: Array[float] = [2.5, 2.0, 1.5, 2.0, 2.0, 3.5, 3.5, 1.5]
const RELIEF_M: Array[float] = [0.02, 0.04, 0.04, 0.07, 0.05, 0.10, 0.10, 0.05]

## Косметичні підтипи (MapData.surface, рішення власника 2026-10-21): для виду — імена
## шарів за номером підтипу; перше ім'я — базовий шар. Шар підтипу вмикається, коли є
## macro/<ім'я>_albedo_0.png; нема файлу — підтип тихо лишається базовим шаром, тож
## додати PLOUGHED, PINE, DECIDUOUS пізніше — лише кинути файли (рядки нижче вже є).
const SURFACE_LAYERS: Dictionary = {
	Terrain.Kind.ROAD: ["road", "dirt", "cobble"],
	Terrain.Kind.FIELD: ["field", "ploughed"],
	Terrain.Kind.FOREST: ["forest", "pine", "deciduous"],
}
## Властивості шарів підтипів: шар деталі (фото-текстура близького плану, окремої нема),
## глибина рельєфу, тип зносу доріг (1 асфальт, 2 ґрунтівка, 3 бруківка) і вирівнювання макро
## (1 — baked колії вздовж осі дороги, 2 — без повороту, борозни).
const SURFACE_DETAIL: Dictionary = {"dirt": "hill", "cobble": "bank", "ploughed": "field", "pine": "forest", "deciduous": "forest"}
const SURFACE_RELIEF_M: Dictionary = {"dirt": 0.06, "cobble": 0.06, "ploughed": 0.08, "pine": 0.04, "deciduous": 0.04}
const SURFACE_WEAR: Dictionary = {"road": 1, "dirt": 2, "cobble": 3}
const SURFACE_ALIGNED: Dictionary = {"dirt": 1, "ploughed": 2}
const MAX_LAYERS: int = 16
## Підтипів на вид у таблиці шейдера (indeks = вид * SURFACES_PER_KIND + підтип).
const SURFACES_PER_KIND: int = 4

const TEX_LAYER_FOR_KIND: Dictionary = {
	Terrain.Kind.ROAD: 0,
	# Річка тече під мостом: під цілим мостом — русло, як під водою.
	Terrain.Kind.BRIDGE: 7,
	Terrain.Kind.FIELD: 1,
	Terrain.Kind.FOREST: 2,
	Terrain.Kind.HILL: 3,
	Terrain.Kind.MARSH: 4,
	Terrain.Kind.WATER: 7,
	Terrain.Kind.BRIDGE_DESTROYED: 7,
	Terrain.Kind.BUILDING: 6,
	Terrain.Kind.RUBBLE: 6,
}

## Частка поля й пагорба, що при GroundState.MUD вкрита плямами багна далеко від
## доріг (біля доріг шейдер додає ще 0.2). §3.12: стан ґрунту — правило, і земля
## мусить його показувати, не лише іконка HUD; але поле лишається полем.
const MUD_BLEND: float = 0.3

const _SHADER: Shader = preload("res://game/battle/shaders/ground.gdshader")

## Масиви текстур (~17 МБ стиснених) належать цьому вузлу: вантажаться при першому
## build(), повторний build() (підірваний міст) їх не чіпає, а вийшли з бою —
## звільнились разом із землею. BoardView тримає землю між перебудовами.
var _albedo_array: Texture2DArray
var _normal_array: Texture2DArray
## Макро-шари (вид зверху, 512 px = 12 м на повтор), assets/terrain/macro/<шар>_albedo.png.
## Оновлення: terrain_tex.py macro <raw_dir> assets/terrain/macro, потім terrain_tex.py imports assets/terrain/macro.
var _macro_array: Texture2DArray

var _kind_image: Image
var _surface_image: Image
## Імена шарів macro_array: перші 8 — TEX_LAYERS, далі — підтипи, чий файл існує.
var _macro_layers: Array[String] = []


## surface — MapData.surface (y * width + x), порожній — усюди 0 (типовий вигляд).
## height — карта висот (TerrainHeight.bake з тим самим margin); null — плоска земля.
func build(board: Board, margin: int, surface: PackedByteArray = PackedByteArray(), height: TerrainHeight = null) -> void:
	var w: int = board.width + 2 * margin
	var h: int = board.height + 2 * margin
	if w <= 0 or h <= 0:
		_kind_image = Image.new()
		mesh = null
		material_override = null
		return
	_kind_image = Image.create(w, h, false, Image.FORMAT_R8)
	_surface_image = Image.create(w, h, false, Image.FORMAT_R8)
	for py in h:
		for px in w:
			var cell := Vector2i(clampi(px - margin, 0, board.width - 1), clampi(py - margin, 0, board.height - 1))
			_kind_image.set_pixel(px, py, Color8(board.kind_at(cell), 0, 0))
			var si: int = cell.y * board.width + cell.x
			_surface_image.set_pixel(px, py, Color8(surface[si] if si < surface.size() else 0, 0, 0))

	var plane := PlaneMesh.new()
	plane.size = Vector2(w, h)
	if height != null:
		# Вершини рівно в відліках карти висот: одна клітинка = SAMPLES_PER_TILE квадів.
		plane.subdivide_width = height.cols - 2
		plane.subdivide_depth = height.rows - 2
		custom_aabb = AABB(Vector3(-w * 0.5, height.min_height(), -h * 0.5), Vector3(w, height.max_height() - height.min_height(), h))
	else:
		custom_aabb = AABB()
	mesh = plane
	position = Vector3((board.width - 1) * 0.5, 0.0, (board.height - 1) * 0.5)
	layers = 1
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var table := PackedInt32Array()
	table.resize(Terrain.Kind.size())
	for kind: int in TEX_LAYER_FOR_KIND:
		table[kind] = TEX_LAYER_FOR_KIND[kind]

	if _albedo_array == null:
		_albedo_array = _load_array("albedo")
		_normal_array = _load_array("normal")
		_macro_layers = _macro_layer_names()
		_macro_array = _load_macro_array(_macro_layers)

	var mat := ShaderMaterial.new()
	mat.shader = _SHADER
	mat.set_shader_parameter("surface_map", ImageTexture.create_from_image(_surface_image))
	var surface_table: PackedInt32Array = _surface_table(_macro_layers)
	if height != null:
		# З рельєфом голий ґрунт пагорба дає шейдер за схилом, а не за видом клітинки:
		# інакше ділянка HILL лишалась би овалом чужої текстури, що не знає про схил.
		for sub in SURFACES_PER_KIND:
			surface_table[Terrain.Kind.HILL * SURFACES_PER_KIND + sub] = TEX_LAYER_FOR_KIND[Terrain.Kind.FIELD]
	mat.set_shader_parameter("layer_for_surface", surface_table)
	_set_layer_properties(mat, _macro_layers)
	mat.set_shader_parameter("kind_map", ImageTexture.create_from_image(_kind_image))
	mat.set_shader_parameter("map_origin", Vector2(-margin, -margin))
	mat.set_shader_parameter("layer_for_kind", table)
	mat.set_shader_parameter("repeat_m", REPEAT_M)
	mat.set_shader_parameter("mud_amount", MUD_BLEND if board.ground_state == Terrain.GroundState.MUD else 0.0)
	mat.set_shader_parameter("albedo_array", _albedo_array)
	mat.set_shader_parameter("normal_array", _normal_array)
	mat.set_shader_parameter("macro_array", _macro_array)
	mat.set_shader_parameter("macro_variants", MACRO_VARIANTS)
	mat.set_shader_parameter("use_height", height != null)
	if height != null:
		mat.set_shader_parameter("height_map", ImageTexture.create_from_image(height.image()))
		mat.set_shader_parameter("height_samples", float(height.samples))
		mat.set_shader_parameter("water_level", TerrainHeight.WATER_LEVEL)
	material_override = mat


func kind_image() -> Image:
	return _kind_image


## Шари macro_array: базові, далі — підтипи в порядку SURFACE_LAYERS, чий файл існує.
static func _macro_layer_names() -> Array[String]:
	var names: Array[String] = TEX_LAYERS.duplicate()
	for kind: int in SURFACE_LAYERS:
		for n: String in SURFACE_LAYERS[kind]:
			if not names.has(n) and ResourceLoader.exists("res://assets/terrain/macro/%s_albedo_0.png" % n):
				names.append(n)
	return names


## (вид, підтип) -> індекс шару macro_array. Підтип без шару (нема файлу) і невідомий
## номер дають базовий шар виду (підтип 0).
static func _surface_table(names: Array[String]) -> PackedInt32Array:
	var table := PackedInt32Array()
	table.resize(Terrain.Kind.size() * SURFACES_PER_KIND)
	for kind in Terrain.Kind.size():
		var base: int = TEX_LAYER_FOR_KIND.get(kind, 0)
		for s in SURFACES_PER_KIND:
			table[kind * SURFACES_PER_KIND + s] = base
		if SURFACE_LAYERS.has(kind):
			var list: Array = SURFACE_LAYERS[kind]
			for s in list.size():
				var idx: int = names.find(list[s])
				if s < SURFACES_PER_KIND and idx >= 0:
					table[kind * SURFACES_PER_KIND + s] = idx
	return table


## Властивості кожного шару macro_array: базовий шар, шар деталі, знос, вирівнювання, рельєф.
static func _set_layer_properties(mat: ShaderMaterial, names: Array[String]) -> void:
	var base := PackedInt32Array()
	var detail := PackedInt32Array()
	var wear := PackedInt32Array()
	var aligned := PackedInt32Array()
	var relief := PackedFloat32Array()
	for i in MAX_LAYERS:
		base.append(i if i < TEX_LAYERS.size() else 0)
		detail.append(i if i < TEX_LAYERS.size() else 0)
		wear.append(0)
		aligned.append(0)
		relief.append(RELIEF_M[i] if i < RELIEF_M.size() else 0.04)
	for i in names.size():
		var n: String = names[i]
		wear[i] = SURFACE_WEAR.get(n, 0)
		if i < TEX_LAYERS.size():
			continue
		detail[i] = TEX_LAYERS.find(SURFACE_DETAIL.get(n, "field"))
		relief[i] = SURFACE_RELIEF_M.get(n, 0.04)
		aligned[i] = SURFACE_ALIGNED.get(n, 0)
		# Базовий шар — той, з чийого списку підтипів взято ім'я.
		for kind: int in SURFACE_LAYERS:
			if (SURFACE_LAYERS[kind] as Array).has(n):
				base[i] = TEX_LAYERS.find((SURFACE_LAYERS[kind] as Array)[0])
	mat.set_shader_parameter("layer_base", base)
	mat.set_shader_parameter("layer_detail", detail)
	mat.set_shader_parameter("layer_wear", wear)
	mat.set_shader_parameter("layer_aligned", aligned)
	mat.set_shader_parameter("relief_m", relief)


static func _load_macro_array(names: Array[String]) -> Texture2DArray:
	var images: Array[Image] = []
	for layer_name in names:
		var base := "res://assets/terrain/macro/%s_albedo_%d.png"
		for n in MACRO_VARIANTS:
			var path: String = base % [layer_name, n]
			if not ResourceLoader.exists(path):
				path = base % [layer_name, 0]
			images.append((load(path) as Texture2D).get_image())
	var arr := Texture2DArray.new()
	arr.create_from_images(images)
	return arr


static func _load_array(suffix: String, subdir: String = "") -> Texture2DArray:
	var images: Array[Image] = []
	for layer_name in TEX_LAYERS:
		# Без запасного шляху: макро 512² і деталь 1024² не живуть в одному масиві.
		var tex: Texture2D = load("res://assets/terrain/%s%s_%s.png" % [subdir, layer_name, suffix])
		# Імпорт — VRAM-стиснений із міпмапами (S3TC/RGTC на ПК, ETC2 на телефоні):
		# шари однакового формату йдуть у масив як є, без розпаковки й CPU-міпмап.
		images.append(tex.get_image())
	var arr := Texture2DArray.new()
	arr.create_from_images(images)
	return arr
