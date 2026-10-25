class_name GroundSurface
extends MeshInstance3D
## Суцільна земля під дошкою (Phase 5a): один меш, один draw call (§8), колір і
## рельєф дає шейдер з карти видів, а не плитки на вид.
##
## §3.5: місцевість публічна й на повній яскравості — тут немає і не може бути
## жодного зв'язку з туманом. Рельєф (TerrainHeight) —
## лише вигляд: вершинний шейдер піднімає сітку за картою висот, оверлеї лягають на ту
## саму поверхню (IsoCameraRig.cell_to_world), правила висоти не читають.

## Порядок шарів Texture2DArray — тут, поруч із TEX_LAYER_FOR_KIND, а не в
## окремому .tres, щоб відповідність вид -> шар була в одному місці.
const TEX_LAYERS: Array[String] = ["road", "field", "forest", "hill", "marsh", "mud", "rubble", "bank"]

## Скільки метрів покриває один повтор текстури шару (в порядку TEX_LAYERS), і
## глибина рельєфу шару в метрах (альфа альбедо = висота). Пояснення цифр — у ground.gdshader.
## Варіантів макро-текстури на шар (комірка гекс-сітки обирає свій). Файли
## macro/<шар>_albedo_<n>.png, n = 0..MACRO_VARIANTS-1; бракуючий n — копія варіанта 0.
const MACRO_VARIANTS: int = 2
const REPEAT_M: Array[float] = [2.5, 2.0, 1.5, 2.0, 2.0, 3.5, 3.5, 1.5]
const RELIEF_M: Array[float] = [0.02, 0.04, 0.04, 0.07, 0.05, 0.10, 0.10, 0.05]

## Косметичні підтипи (MapData.surface): для виду — імена
## шарів за номером підтипу; перше ім'я — базовий шар. Шар підтипу вмикається, коли є
## macro/<ім'я>_albedo_0.png; нема файлу — підтип тихо лишається базовим шаром. Новому
## підтипу файлу замало: шар ще потребує свого рядка в SURFACE_DETAIL, SURFACE_RELIEF_M
## (і SURFACE_ALIGNED, якщо текстура спрямована), як у ploughed.
const SURFACE_LAYERS: Dictionary = {
	Terrain.Kind.ROAD: ["road", "dirt", "cobble"],
	Terrain.Kind.FIELD: ["field", "ploughed"],
	Terrain.Kind.FOREST: ["forest", "pine", "deciduous"],
}
## Властивості шарів підтипів: шар деталі (фото-текстура близького плану, окремої нема),
## глибина рельєфу й вирівнювання макро (2 — поворот лише 0/180°, щоб борозни лишались
## паралельні). Базовий шар теж може взяти чужу деталь: власна деталь багна має колії шин,
## а колій поза дорогою нема, тож багно бере ізотропний мокрий ґрунт берега
## з галькою.
const SURFACE_DETAIL: Dictionary = {"dirt": "hill", "cobble": "bank", "ploughed": "field", "pine": "forest", "deciduous": "forest", "mud": "bank"}
const SURFACE_RELIEF_M: Dictionary = {"dirt": 0.06, "cobble": 0.06, "ploughed": 0.08, "pine": 0.04, "deciduous": 0.04}
const SURFACE_ALIGNED: Dictionary = {"ploughed": 2}
## Метрів на повтор макро-текстури шару (вид зверху); невказаний шар — 12 м. CC0-скани Poly
## Haven мають власний фізичний розмір, і ці метри дублюють таблицю CC0 у tools/terrain_tex.py —
## міняти обидві разом. Решта згенерована на 12 м. Бруківка — 3 м: ~20 каменів по 15 см у
## повторі, як справжня кладка. Ліс — 2 м: гілки в його макро мають справжню довжину 5–30 см
## лише на цьому масштабі, на 12 м вони розтягуються до 1–3 м. Болото — 8 м: купини в макро
## тоді 0.4–0.6 м, як справжні; на 12 м вони були б ~0.7–0.8 м.
const MACRO_M: Dictionary = {"dirt": 20.0, "mud": 25.0, "hill": 20.0, "bank": 25.0, "road": 30.0, "cobble": 3.0, "forest": 2.0, "marsh": 8.0}
const DEFAULT_MACRO_M: float = 12.0
## Класів покриття на карті (канали двох RGBA8 карт класів); зайві стають полем.
const CLASS_SLOTS: int = 8
## Клас двору в class_layers(): клітинка будівлі — поле з плямами втоптаного ґрунту (малює
## шейдер), а не щебінь.
const YARD: int = -2
const MAX_LAYERS: int = 16
## Полів ріллі в шейдері (uniform-масив plough_axis).
const MAX_PLOUGH_FIELDS: int = 64
## Смуга трави всередині крайньої клітинки поля, клітинки (PLOUGH_HEADLAND у ground.gdshader).
const PLOUGH_HEADLAND: float = 0.15
## Трави між прямим краєм ріллі й краєм дороги, м.
const PLOUGH_ROAD_GAP_M: float = 1.5
const METRES_PER_TILE: float = 8.0
## Схил (тангенс), на якому калюжа вже не стоїть: 5° -> 7.5° (PUDDLE_SLOPE_* у ground.gdshader).
const PUDDLE_SLOPE_LO: float = 0.087
const PUDDLE_SLOPE_HI: float = 0.13
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
## мусить його показувати, не лише іконка HUD; але поле лишається полем. 0.15 дає ~15 %
## поля далеко від доріг і ~35 % біля них; більша частка на далекому зумі гасить луку й ріллю.
const MUD_BLEND: float = 0.15

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
## Меш землі з кільцем і карта висот, з якої його складено: підірваний міст перебудовує землю,
## а форма меша від виду клітинок не залежить, тож він не складається вдруге.
var _ring_mesh: ArrayMesh
var _ring_mesh_height: TerrainHeight
## Пора року: `summer`, `early` (рання осінь); порожня — пізня осінь, звичайні файли.
## Для шару, що має файл macro/<шар>_albedo_<n>.<пора>.png, береться він; решта шарів — як є.
## Ставити до першого build(): масиви текстур вантажаться один раз.
var season: StringName = &""

## Імена шарів macro_array: перші 8 — TEX_LAYERS, далі — підтипи, чий файл існує.
var _macro_layers: Array[String] = []


## surface — MapData.surface (y * width + x), порожній — усюди 0 (типовий вигляд).
## height — карта висот (TerrainHeight.bake з тим самим margin); null — плоска земля.
## `ring` > 0: `board` — світ (`Surroundings.world_board`), на `ring` клітинок ширший за дошку з
## кожного боку; земля стоїть у координатах дошки, кільце — смугами грубшого меша
## (`Surroundings.ground_mesh`).
func build(board: Board, margin: int, surface: PackedByteArray = PackedByteArray(), height: TerrainHeight = null, ring: int = 0) -> void:
	var w: int = board.width + 2 * margin
	var h: int = board.height + 2 * margin
	if w <= 0 or h <= 0:
		_kind_image = Image.new()
		mesh = null
		material_override = null
		return
	_kind_image = Image.create(w, h, false, Image.FORMAT_R8)
	for py in h:
		for px in w:
			var cell := Vector2i(clampi(px - margin, 0, board.width - 1), clampi(py - margin, 0, board.height - 1))
			_kind_image.set_pixel(px, py, Color8(board.kind_at(cell), 0, 0))

	var size := Vector2i(board.width - 2 * ring, board.height - 2 * ring)
	if height != null and ring > 0:
		if _ring_mesh_height != height:
			_ring_mesh = Surroundings.ground_mesh(size, ring, height.samples, height.bank_cells())
			_ring_mesh_height = height
		mesh = _ring_mesh
	else:
		var plane := PlaneMesh.new()
		plane.size = Vector2(w, h)
		if height != null:
			# Вершини рівно в відліках карти висот: одна клітинка = SAMPLES_PER_TILE квадів.
			plane.subdivide_width = height.cols - 2
			plane.subdivide_depth = height.rows - 2
		mesh = plane
	if height != null:
		custom_aabb = AABB(Vector3(-w * 0.5, height.min_height(), -h * 0.5), Vector3(w, height.max_height() - height.min_height(), h))
	else:
		custom_aabb = AABB()
	position = Vector3((size.x - 1) * 0.5, 0.0, (size.y - 1) * 0.5)
	layers = 1
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	if _albedo_array == null:
		_albedo_array = _load_array("albedo")
		_normal_array = _load_array("normal")
		_macro_layers = _macro_layer_names()
		_macro_array = _load_macro_array(_macro_layers, season)

	var mat := ShaderMaterial.new()
	mat.shader = _SHADER
	var surface_table: PackedInt32Array = _surface_table(_macro_layers)
	if height != null:
		# З рельєфом голий ґрунт пагорба дає шейдер за схилом, а не за видом клітинки:
		# інакше ділянка HILL лишалась би овалом чужої текстури, що не знає про схил.
		for sub in SURFACES_PER_KIND:
			surface_table[Terrain.Kind.HILL * SURFACES_PER_KIND + sub] = TEX_LAYER_FOR_KIND[Terrain.Kind.FIELD]
	_set_layer_properties(mat, _macro_layers)
	var plough: int = _macro_layers.find("ploughed")
	var cells: PackedInt32Array = plough_cells(board, margin, surface, surface_table, height != null)
	# Рілля — рукотворна: у картах класів її клітинки — лука (природна м'яка межа), а саме поле
	# шейдер кладе зверху прямокутником із прямим краєм.
	var class_table: PackedInt32Array = surface_table.duplicate()
	for s in SURFACES_PER_KIND:
		if plough >= 0 and class_table[Terrain.Kind.FIELD * SURFACES_PER_KIND + s] == plough:
			class_table[Terrain.Kind.FIELD * SURFACES_PER_KIND + s] = TEX_LAYER_FOR_KIND[Terrain.Kind.FIELD]
	_set_classes(mat, board, margin, surface, class_table, height != null)
	_set_plough(mat, cells, board.width + 2 * margin, plough, height)
	var bm: PackedByteArray = bank_mask(board, margin)
	var hm: PackedByteArray = hill_mask(board, margin)
	var rg := PackedByteArray()
	rg.resize(bm.size() * 2)
	for i in bm.size():
		rg[i * 2] = bm[i]
		rg[i * 2 + 1] = hm[i]
	var bank := Image.create_from_data(board.width + 2 * margin, board.height + 2 * margin, false, Image.FORMAT_RG8, rg)
	mat.set_shader_parameter("bank_map", ImageTexture.create_from_image(bank))
	_set_roads(mat, height)
	mat.set_shader_parameter("map_origin", Vector2(-margin - ring, -margin - ring))
	mat.set_shader_parameter("repeat_m", REPEAT_M)
	if ring > 0:
		Surroundings.apply(mat, size)
		mat.set_shader_parameter("snap_edges", height != null)
	mat.set_shader_parameter("mud_amount", MUD_BLEND if board.ground_state == Terrain.GroundState.MUD else 0.0)
	mat.set_shader_parameter("dry_season", season != &"")
	mat.set_shader_parameter("albedo_array", _albedo_array)
	mat.set_shader_parameter("normal_array", _normal_array)
	mat.set_shader_parameter("macro_array", _macro_array)
	mat.set_shader_parameter("macro_variants", MACRO_VARIANTS)
	mat.set_shader_parameter("use_height", height != null)
	if height != null:
		mat.set_shader_parameter("height_map", height.texture())
		mat.set_shader_parameter("height_samples", float(height.samples))
		mat.set_shader_parameter("water_level", TerrainHeight.WATER_LEVEL)
	material_override = mat


func kind_image() -> Image:
	return _kind_image


## Шар (індекс macro_array) кожної клітинки з відступом: класи покриття, з яких шейдер
## малює межі, вільні від сітки (згладжена білінійна + повернутий шум зсуву, std ~2.5 м і ~0.5 м).
## Дорога — окрема геометрія (RoadCourse), тож клітинка ROAD бере покриття сусідів; вода й міст
## з рельєфом — поле (берег малює висота).
static func class_layers(board: Board, margin: int, surface: PackedByteArray, table: PackedInt32Array, relief: bool) -> PackedInt32Array:
	var w: int = board.width + 2 * margin
	var h: int = board.height + 2 * margin
	var out := PackedInt32Array()
	out.resize(w * h)
	var field: int = TEX_LAYER_FOR_KIND[Terrain.Kind.FIELD]
	for py in h:
		for px in w:
			var cell := Vector2i(clampi(px - margin, 0, board.width - 1), clampi(py - margin, 0, board.height - 1))
			var kind: int = board.kind_at(cell)
			var si: int = cell.y * board.width + cell.x
			var layer: int = table[kind * SURFACES_PER_KIND + clampi(surface[si] if si < surface.size() else 0, 0, SURFACES_PER_KIND - 1)]
			if kind == Terrain.Kind.ROAD:
				layer = -1
			elif kind == Terrain.Kind.BUILDING:
				layer = YARD
			elif relief and TEX_LAYERS[TEX_LAYER_FOR_KIND[kind]] == "bank":
				layer = field
			out[py * w + px] = layer
	# Дорога: більшість серед сусідів, що вже мають покриття; кілька проходів для широких смуг.
	for _pass in 4:
		var next: PackedInt32Array = out.duplicate()
		for py in h:
			for px in w:
				if out[py * w + px] != -1:
					continue
				var votes: Dictionary = {}
				for d in Board.DIRS_4:
					var q := Vector2i(px, py) + d
					if q.x >= 0 and q.y >= 0 and q.x < w and q.y < h and out[q.y * w + q.x] != -1:
						votes[out[q.y * w + q.x]] = int(votes.get(out[q.y * w + q.x], 0)) + 1
				var best := -1
				for l: int in votes:
					if best < 0 or int(votes[l]) > int(votes[best]) or (votes[l] == votes[best] and l == field):
						best = l
				next[py * w + px] = best
		out = next
	for i in out.size():
		if out[i] == -1:
			out[i] = field
	return out


## Карти класів: до CLASS_SLOTS шарів у каналах двох RGBA8 (255 — клітинка цього класу).
func _set_classes(mat: ShaderMaterial, board: Board, margin: int, surface: PackedByteArray, table: PackedInt32Array, relief: bool) -> void:
	var w: int = board.width + 2 * margin
	var h: int = board.height + 2 * margin
	var layers: PackedInt32Array = class_layers(board, margin, surface, table, relief)
	var slots := PackedInt32Array()
	var slot_of: Dictionary = {}
	for l in layers:
		if not slot_of.has(l) and slots.size() < CLASS_SLOTS:
			slot_of[l] = slots.size()
			slots.append(l)
	var imgs: Array[Image] = [Image.create(w, h, false, Image.FORMAT_RGBA8), Image.create(w, h, false, Image.FORMAT_RGBA8)]
	for py in h:
		for px in w:
			# shortcut: дев'ятий і далі клас малюється першим слотом; на картах їх ≤ 6.
			var sl: int = slot_of.get(layers[py * w + px], 0)
			var c := Color(0, 0, 0, 0)
			c[sl % 4] = 1.0
			imgs[sl / 4].set_pixel(px, py, c)
	mat.set_shader_parameter("yard_slot", slot_of.get(YARD, -1))
	var field: int = TEX_LAYER_FOR_KIND[Terrain.Kind.FIELD]
	for i in slots.size():
		if slots[i] == YARD:
			slots[i] = field
	while slots.size() < CLASS_SLOTS:
		slots.append(slots[0] if not slots.is_empty() else 0)
	mat.set_shader_parameter("class_map0", ImageTexture.create_from_image(imgs[0]))
	mat.set_shader_parameter("class_map1", ImageTexture.create_from_image(imgs[1]))
	mat.set_shader_parameter("class_layer", slots)


## Смуга біля річки (рядок ширини board.width + 2 * margin): 255 — клітинка води чи мосту
## або її сусід (8 напрямків), 0 — решта. Шейдер не кладе тут стоячої води: калюжі й вікна
## болота на березі читались дивно.
static func bank_mask(board: Board, margin: int) -> PackedByteArray:
	var w: int = board.width + 2 * margin
	var h: int = board.height + 2 * margin
	var out := PackedByteArray()
	out.resize(w * h)
	for py in h:
		for px in w:
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var c := Vector2i(clampi(px + dx - margin, 0, board.width - 1), clampi(py + dy - margin, 0, board.height - 1))
					var k: int = board.kind_at(c)
					if k == Terrain.Kind.WATER or k == Terrain.Kind.BRIDGE or k == Terrain.Kind.BRIDGE_DESTROYED:
						out[py * w + px] = 255
	return out


## Клітинки пагорба (рядок ширини board.width + 2 * margin): 255 — HILL, 0 — решта. На пагорбі
## калюж не буває ніде, навіть на пологому місці.
static func hill_mask(board: Board, margin: int) -> PackedByteArray:
	var w: int = board.width + 2 * margin
	var h: int = board.height + 2 * margin
	var out := PackedByteArray()
	out.resize(w * h)
	for py in h:
		for px in w:
			var c := Vector2i(clampi(px - margin, 0, board.width - 1), clampi(py - margin, 0, board.height - 1))
			if board.kind_at(c) == Terrain.Kind.HILL:
				out[py * w + px] = 255
	return out


## Частка калюжі, яку дозволяє рельєф (копія pud_gate у ground.gdshader — міняти разом):
## схил `slope_tan` (тангенс) понад ~5–7.5° і гребінь (`curvature` > 0) — сухі, клітинка пагорба
## (`hill` 0..1) — суха завжди. Низини й рівне — 1.
static func puddle_gate(slope_tan: float, curvature: float, hill: float) -> float:
	return (1.0 - smoothstep(PUDDLE_SLOPE_LO, PUDDLE_SLOPE_HI, slope_tan)) \
			* (1.0 - smoothstep(0.0, 0.08, curvature)) * (1.0 - smoothstep(0.2, 0.6, hill))


## class_layers для пошуку полів: дорога, міст і вода лишають власний вид (-1), а не беруть
## покриття сусідів голосуванням — інакше поле перескакувало б через дорогу й зливалось із
## сусіднім в одне.
static func plough_cells(board: Board, margin: int, surface: PackedByteArray, table: PackedInt32Array, relief: bool) -> PackedInt32Array:
	var out: PackedInt32Array = class_layers(board, margin, surface, table, relief)
	var w: int = board.width + 2 * margin
	for i in out.size():
		var cell := Vector2i(clampi(i % w - margin, 0, board.width - 1), clampi(i / w - margin, 0, board.height - 1))
		var kind: int = board.kind_at(cell)
		if kind == Terrain.Kind.ROAD or kind == Terrain.Kind.WATER or kind == Terrain.Kind.BRIDGE or kind == Terrain.Kind.BRIDGE_DESTROYED:
			out[i] = -1
	return out


## Поля ріллі: зв'язні (4 сусіди) групи клітинок шару `layer` у `cells` (plough_cells, рядок
## ширини `w`). Повертає [номер поля + 1 у кожній клітинці (0 — не рілля), прямокутники
## Rect2i за клітинками]. Не більше MAX_PLOUGH_FIELDS: решта лишається лукою.
static func plough_fields(cells: PackedInt32Array, w: int, layer: int) -> Array:
	var ids := PackedByteArray()
	ids.resize(cells.size())
	var rects: Array[Rect2i] = []
	if layer < 0 or w <= 0:
		return [ids, rects]
	var h: int = cells.size() / w
	for start in cells.size():
		if cells[start] != layer or ids[start] != 0 or rects.size() >= MAX_PLOUGH_FIELDS:
			continue
		var id: int = rects.size() + 1
		var rect := Rect2i(start % w, start / w, 1, 1)
		var stack: Array[int] = [start]
		ids[start] = id
		while not stack.is_empty():
			var i: int = stack.pop_back()
			var c := Vector2i(i % w, i / w)
			rect = rect.expand(c).expand(c + Vector2i.ONE)
			for d in Board.DIRS_4:
				var q: Vector2i = c + d
				var j: int = q.y * w + q.x
				if q.x >= 0 and q.y >= 0 and q.x < w and q.y < h and cells[j] == layer and ids[j] == 0:
					ids[j] = id
					stack.append(j)
		rects.append(rect)
	return [ids, rects]


func _set_plough(mat: ShaderMaterial, cells: PackedInt32Array, w: int, layer: int, height: TerrainHeight) -> void:
	var res: Array = plough_fields(cells, w, layer)
	var rects: Array[Rect2i] = res[1]
	mat.set_shader_parameter("plough_layer", layer if not rects.is_empty() else -1)
	if rects.is_empty():
		return
	var img := Image.create_from_data(w, cells.size() / w, false, Image.FORMAT_R8, res[0])
	mat.set_shader_parameter("plough_map", ImageTexture.create_from_image(img))
	var axis := PackedInt32Array()
	var insets := PackedVector4Array()
	var rc: RoadCourse = height.roads if height != null else null
	for r in rects:
		# Борозни вздовж довгого боку; квадратне поле — вздовж x.
		axis.append(1 if r.size.y > r.size.x else 0)
		insets.append(plough_road_insets(r, rc))
	mat.set_shader_parameter("plough_axis", axis)
	mat.set_shader_parameter("plough_inset", insets)


## Відступ кожного боку поля (клітинки: -x, -y, +x, +y), щоб між прямим краєм ріллі й дорогою
## лишалось PLOUGH_ROAD_GAP_M трави. Бік зсувається цілим, тож край лишається прямим, а не йде
## за вигином дороги. Не більше 0.45 клітинки: глибше край вийшов би з крайньої клітинки поля.
static func plough_road_insets(r: Rect2i, rc: RoadCourse) -> Vector4:
	if rc == null:
		return Vector4.ZERO
	var img: Image = rc.rasterise()[0]
	# Растр доріг починається там, де карта класів: координата дороги = клітинка - відступ курсу.
	var off := Vector2(rc._margin, rc._margin)
	var lo := Vector2(r.position) - Vector2(0.5, 0.5)
	var hi := Vector2(r.end) - Vector2(0.5, 0.5)
	var out := Vector4.ZERO
	# Бік: [вісь (0 — x, 1 — y), знак напрямку всередину поля].
	var sides: Array = [[0, 1.0], [1, 1.0], [0, -1.0], [1, -1.0]]
	for k in 4:
		var ax: int = sides[k][0]
		var inward: float = sides[k][1]
		var edge: float = (lo if inward > 0.0 else hi)[ax]
		var t: float = 0.0
		for _iter in 6:
			var line: float = edge + inward * (PLOUGH_HEADLAND + t)
			var dmin: float = INF
			var a: float = lo[1 - ax]
			while a <= hi[1 - ax]:
				var q := Vector2(line, a) if ax == 0 else Vector2(a, line)
				dmin = minf(dmin, rc.d_from(img, q - off))
				a += 0.125
			if dmin >= PLOUGH_ROAD_GAP_M:
				break
			t = minf(t + (PLOUGH_ROAD_GAP_M - dmin) / METRES_PER_TILE, 0.45)
		out[k] = t
	return out


## Шар дороги (RoadCourse.rasterise): поле відстані/осі й ваги типів; без рельєфу доріг нема.
func _set_roads(mat: ShaderMaterial, height: TerrainHeight) -> void:
	var rc: RoadCourse = height.roads if height != null else null
	mat.set_shader_parameter("has_roads", rc != null)
	if rc == null:
		return
	var imgs: Array[Image] = rc.rasterise()
	mat.set_shader_parameter("road_field", ImageTexture.create_from_image(imgs[0]))
	mat.set_shader_parameter("road_type", ImageTexture.create_from_image(imgs[1]))
	mat.set_shader_parameter("road_px", float(RoadCourse.PX))
	var road_layers := PackedInt32Array()
	for n: String in SURFACE_LAYERS[Terrain.Kind.ROAD]:
		var idx: int = _macro_layers.find(n)
		road_layers.append(idx if idx >= 0 else TEX_LAYERS.find("road"))
	mat.set_shader_parameter("road_layer", road_layers)


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


## Властивості кожного шару macro_array: базовий шар, деталь, вирівнювання, рельєф, розмір макро.
static func _set_layer_properties(mat: ShaderMaterial, names: Array[String]) -> void:
	var base := PackedInt32Array()
	var detail := PackedInt32Array()
	var aligned := PackedInt32Array()
	var relief := PackedFloat32Array()
	for i in MAX_LAYERS:
		base.append(i if i < TEX_LAYERS.size() else 0)
		detail.append(i if i < TEX_LAYERS.size() else 0)
		aligned.append(0)
		relief.append(RELIEF_M[i] if i < RELIEF_M.size() else 0.04)
	for i in names.size():
		var n: String = names[i]
		if i < TEX_LAYERS.size():
			if SURFACE_DETAIL.has(n):
				detail[i] = TEX_LAYERS.find(SURFACE_DETAIL[n])
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
	mat.set_shader_parameter("layer_aligned", aligned)
	mat.set_shader_parameter("relief_m", relief)
	var macro := PackedFloat32Array()
	for i in MAX_LAYERS:
		macro.append(MACRO_M.get(names[i], DEFAULT_MACRO_M) if i < names.size() else DEFAULT_MACRO_M)
	mat.set_shader_parameter("macro_m", macro)


## Файл варіанта n шару для пори року. Порядок: варіант n цієї пори, варіант 0 цієї пори,
## звичайний n, звичайний 0. Сезонні йдуть першими обидва: інакше бракуючий сезонний
## варіант 1 узяв би осінній файл і на літній луці лягли б осінні латки.
static func macro_path(layer_name: String, n: int, p_season: StringName = &"") -> String:
	var base := "res://assets/terrain/macro/%s_albedo_%d%s.png"
	var tries: Array[String] = []
	if p_season != &"":
		tries.append(base % [layer_name, n, "." + p_season])
		tries.append(base % [layer_name, 0, "." + p_season])
	tries.append(base % [layer_name, n, ""])
	for path in tries:
		if ResourceLoader.exists(path):
			return path
	return base % [layer_name, 0, ""]


static func _load_macro_array(names: Array[String], p_season: StringName) -> Texture2DArray:
	var images: Array[Image] = []
	for layer_name in names:
		for n in MACRO_VARIANTS:
			images.append((load(macro_path(layer_name, n, p_season)) as Texture2D).get_image())
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
