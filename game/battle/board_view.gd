class_name BoardView
extends Node3D
## Рендерить дошку: одну суцільну землю (GroundSurface, Phase 5a) і поверх неї
## контури та кола оверлеїв — так тримається бюджет ~100 draw calls (§8).
##
## §3.5: туман ховає ворожих юнітів і їхні міни, ніколи місцевість. Вона
## публічна з першого ходу й на повній яскравості, тож у BoardView свідомо
## немає ані apply_fog, ані будь-якого зв'язку з тайловою видимістю —
## приглушений тайл сам був би підказкою, а контур зони руху, що огинає
## нерозвідану перешкоду, видав би її не гірше за сам тайл. Ховати юнітів —
## робота інших вузлів (Task 2.4, Task 2.10), не цього.

## LAYER_PATH — окремий шар для контуру шляху (§3.13): шлях лежить УСЕРЕДИНІ
## зони руху, тобто малюється поверх її контурів, тож у нього власний шар.
## LAYER_INSPECT — кільця оглянутого юніта (Task 14): окремо від LAYER_TARGETS, бо
## режими верби й дрона замінюють свої тайли, а кільце вибраного юніта живе поруч.
enum { LAYER_ZONES, LAYER_PATH, LAYER_TARGETS, LAYER_INSPECT }

## Шар рендеру для накладок (контури, кільця). Не шар світу (1): зонд відбиттів
## знімає шар 1, і накладки активного гравця в знімку побачив би наступний гравець
## у річці. Шар 2 — юніти, 3 — міни (MineLayer.MARKER_LAYER).
const OVERLAY_LAYER: int = 4

## Крок часу імли (`fog_time` у surroundings.gdshaderinc), секунд. Кожне оновлення коштує
## один намальований кадр: на 10 Гц дошка без руху малює 10 кадрів на секунду, а крок не міняє
## жодного пікселя більш як на 2/255; на 5 Гц край клуба вже стрибає, на 2 Гц — видимо.
const FOG_TICK: float = 0.1

## Геометрія риски контуру (§3.13, draw_contour нижче): тонка й коротка за
## задумом — вона мусить читатись як лінія на межі тайла, а не як ще один
## пофарбований тайл. _CONTOUR_INSET відсуває риску від самого краю тайла:
## без цього риска золотої зони й риска сусідньої червоної, що лежать на
## тому самому фізичному ребрі, збіглися б і z-fighting'нули — з відступом
## між ними лишається вузька смужка місцевості, і вони читаються як дві окремі
## риски, а не одна змішана.
const _CONTOUR_WIDTH: float = 0.12
const _CONTOUR_INSET: float = 0.06
const _CONTOUR_PIECES: int = 4
## 0.95 клітинки: риска коротша за клітинку, тож кути сусідніх рисок не сходяться.
const _CONTOUR_LENGTH: float = 0.95
## Над землею (y = 0) і над маркерами мін (MineLayer.MARKER_Y = 0.06), щоб не
## z-fight'ити ні з тим, ні з іншим.
const _CONTOUR_Y: float = 0.04
const _CONTOUR_OFFSET: float = 0.5 - _CONTOUR_WIDTH * 0.5 - _CONTOUR_INSET

## Косметичний підтип клітинок (MapData.surface); лише вигляд землі, тримається між перебудовами.
var surface: PackedByteArray = PackedByteArray()
## Seed косметичного рельєфу — з імені карти (battle_screen), щоб та сама карта мала той самий рельєф.
var relief_seed: int = 0
## Карта, з якої береться кільце довкола дошки (MapData.outer_*); null чи карта без кільця — світ
## закінчується краєм дошки. Лише вигляд: Board кільця не має.
var ring_map: MapData = null
## Пора року землі (BattleLook.season): `late` — звичайні файли, `summer` / `early` — сезонні.
## Ставити до першого build(): текстури землі вантажаться один раз.
var season: StringName = &"late"
## Будівлі кидають тінь сонця (PropLayer.structure_shadows): на сонячній карті без неї дім висить.
## Ставить екран бою з вигляду карти до першого build().
var structure_shadows: bool = false
## Мокра карта (PropLayer.wet): ставить екран бою з вигляду карти до першого build().
var wet: bool = false
## Час імли для всіх матеріалів світу; з боєм не скидається, бо візерунку однаково, з якого
## часу пливти.
static var fog_time: float = 0.0
## Таймер `FOG_TICK`; лише з кільцем — без нього імли нема.
var _fog_clock: Timer
## Кільце й розмір дошки останньої побудови: для імли на руїнах мостів кільця й лінії межі на
## настилах дошки.
var _ring: int = 0
var _board_size: Vector2i = Vector2i.ZERO
## Карта висот поточної дошки; ця ж поверхня — TerrainHeight.active для всіх, хто лежить на землі.
var _height: TerrainHeight
var _height_signature: String = ""
## Клас кожної клітинки (вода/пагорб/дорога/майданчик/інше), з яких складається рельєф: міст
## ціле/підірваний — той самий клас, тож перебудова мосту карту не перебакує.
var _height_kind_classes: PackedByteArray = PackedByteArray()
## Земля переживає build(): масиви її текстур не перевантажуються на кожен міст.
var _ground: GroundSurface
## Шрами бою (ScarMap) — їх тримає екран бою; земля отримує текстури на кожен build(),
## бо build() створює їй новий матеріал.
var scar_map: ScarMap
var _water: WaterSurface
## Зонд відбиттів знімає світ (шар 1) рівно один раз і теж переживає build():
## новий знімок посеред партії міг би захопити тимчасові вузли на дошці.
## §3.5: шар юнітів (UnitView.UNIT_LAYER) у cull_mask не входить ніколи.
var _probe: ReflectionProbe
## Скільки разів зонд просили зняти світ (створення + кожна перебудова) — для тестів.
var probe_captures_requested: int = 0
## Будівлі, мости й дрібні пропси (PropLayer). Переживає build(): набір клітинок під юнітами й
## розчавлених лишається між перебудовами мосту.
var _props: PropLayer
## тайл -> вид тайлу під ним.
var _kind_by_cell: Dictionary = {}
## шар контуру -> Array[Dictionary] сегментів {cell, dir, color}, які зараз
## намальовані draw_contour(). Читається тестами напряму — той самий прийом,
## що й решта стану вигляду: колір екземпляра мультимешу
## не читається назад під headless (R4/R16), тож перевіряється те, ЩО туди
## подали, а не намальований піксель.
var _contour_segments: Dictionary = {}
## шар контуру -> MultiMeshInstance3D цього шару, щоб clear_contour() міг
## звільнити рівно свій вузол, не займаючи вузли інших шарів контуру.
var _contour_nodes: Dictionary = {}
## шар -> Array[Dictionary] кіл {center: Vector2i, radius: int, color: Color}
## (draw_circles) і їхні вузли — той самий прийом, що й у контурів.
var _circles: Dictionary = {}
var _circle_nodes: Dictionary = {}


func _exit_tree() -> void:
	if TerrainHeight.active == _height:
		TerrainHeight.active = null


static func _classes(board: Board) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(board.width * board.height)
	for y in board.height:
		for x in board.width:
			var kind: int = board.kind_at(Vector2i(x, y))
			var c := 0
			if kind == Terrain.Kind.WATER or kind == Terrain.Kind.BRIDGE or kind == Terrain.Kind.BRIDGE_DESTROYED:
				c = 1
			elif kind == Terrain.Kind.HILL:
				c = 2
			elif kind == Terrain.Kind.ROAD:
				c = 3
			elif kind == Terrain.Kind.BUILDING or kind == Terrain.Kind.RUBBLE:
				c = 4
			out[y * board.width + x] = c
	return out


func build(board: Board) -> void:
	# free(), не queue_free(): відкладене звільнення лишає щойно відкріплений
	# вузол «сиротою» до наступного кадру, а тести це фіксують як витік.
	for child in get_children():
		if child != _ground and child != _water and child != _probe and child != _fog_clock and child != _props:
			child.free()
	_kind_by_cell.clear()
	# Вузли контуру щойно звільнені циклом free() вище (вони теж діти цього
	# Node3D) — без цього _contour_nodes лишав би посилання на вже мертві
	# вузли, і наступний clear_contour() спробував би звільнити їх удруге.
	_contour_segments.clear()
	_contour_nodes.clear()
	_circles.clear()
	_circle_nodes.clear()

	for y in board.height:
		for x in board.width:
			_kind_by_cell[Vector2i(x, y)] = board.kind_at(Vector2i(x, y))

	if _ground == null:
		_ground = GroundSurface.new()
		_ground.name = "Ground"
		_ground.season = &"" if season == &"late" else season
		add_child(_ground)
	# Рельєф бакається раз на карту: підірваний міст міняє вид клітинки, але не форму землі.
	# Підтип покриття (surface) теж міняє рельєф: від нього залежать тип і ширина дороги, а з
	# ними вирівнювання землі.
	# Світ — дошка разом із кільцем автора: рельєф, вода й дороги течуть крізь нього одним
	# запіканням.
	var ring: int = Surroundings.ring_of(ring_map) if board.width > 0 and board.height > 0 else 0
	var world: Board = Surroundings.world_board(board, ring_map) if ring > 0 else board
	_ring = ring
	_board_size = Vector2i(board.width, board.height)
	var world_surface: PackedByteArray = Surroundings.world_surface(ring_map) if ring > 0 else surface
	var signature: String = "%d:%d:%d:%d:%d" % [board.width, board.height, relief_seed, hash(surface), ring]
	if board.width <= 0 or board.height <= 0:
		_height = null
	elif _height == null or signature != _height_signature or _height_kind_classes != _classes(board):
		_height = TerrainHeight.bake(world, 0, relief_seed, world_surface, ring)
		_height_signature = signature
		_height_kind_classes = _classes(board)
	TerrainHeight.active = _height
	_ground.build(world, 0, world_surface, _height, ring)
	if scar_map != null and _ground.material_override is ShaderMaterial:
		scar_map.apply(_ground.material_override)

	if _water == null:
		_water = WaterSurface.new()
		_water.name = "Water"
		add_child(_water)
	var kinds: Image = _ground.kind_image()
	_water.build(world, 0, null if kinds.is_empty() else ImageTexture.create_from_image(kinds), _height, ring)

	if _props == null:
		_props = PropLayer.new()
		_props.name = "Props"
		add_child(_props)
	_props.structure_shadows = structure_shadows
	_props.wet = wet
	_props.garden_green = {&"summer": 1.0, &"early": 0.5}.get(season, 0.15)
	var fields: Array[Rect2] = []
	for r in _ground.field_edges:
		fields.append(Rect2(r.position - Vector2(ring, ring), r.size))
	var spawns: Array[Vector2i] = []
	if ring_map != null:
		for sp: Dictionary in ring_map.spawns:
			spawns.append(sp["pos"])
	_props.build(world, ring, _board_size, _height, _map_key(), _half_dir(board), fields, spawns)
	# Стежки публічні (§3.5): маска зносу не залежить від туману й ставиться разом із землею.
	if _ground.material_override is ShaderMaterial and not _props.footpaths.is_empty():
		var h: TerrainHeight = _height
		var dry: Callable = (func(q: Vector2) -> bool: return h.at(q.x, q.y) >= TerrainHeight.WATER_LEVEL) if h != null else Callable()
		Footpaths.apply(_ground.material_override, Footpaths.bake(_props.footpaths, _props.trodden, _board_size, dry), _board_size)
	if ring > 0:
		# Під найнижчою точкою землі: усередині кільця його закриває земля, за ним — лише він.
		add_child(Surroundings.skirt(Vector2i(board.width, board.height), _height.min_height() - 0.5))
		if _fog_clock == null:
			_fog_clock = Timer.new()
			_fog_clock.name = "FogClock"
			_fog_clock.wait_time = FOG_TICK
			_fog_clock.autostart = true
			_fog_clock.timeout.connect(_tick_fog)
			add_child(_fog_clock)
	if _fog_clock != null:
		# Без кільця імли нема: годинник стоїть і не будить кадр.
		_fog_clock.paused = ring == 0

	# Розмір дошки сталий у межах партії, тож коробку задаємо лише раз; перезйомку
	# після перебудови просить rebuild_tiles явно (_request_probe_capture).
	if _probe == null:
		_probe = ReflectionProbe.new()
		_probe.name = "ReflectionProbe"
		_probe.update_mode = ReflectionProbe.UPDATE_ONCE
		_probe.cull_mask = 1
		_probe.box_projection = true
		# З кільцем зонд гасне плавно за 1.5 клітинки від краю коробки (дошка + 2): інакше вода
		# кільця міняла б яскравість різкою прямою лінією. Клітинки дошки лишаються в неослабленій
		# частині.
		_probe.blend_distance = 1.5 if ring > 0 else 0.0
		# Коробка від y = -1 до 11 і на 2 клітинки ширша за дошку: на межі коробки
		# зонд гасне, і вода крайніх клітинок чорніла б. Знімок — з висоти 1.5.
		_probe.size = Vector3(board.width + 4, 12.0, board.height + 4)
		_probe.position = Vector3((board.width - 1) * 0.5, 5.0, (board.height - 1) * 0.5)
		_probe.origin_offset = Vector3(0.0, -3.5, 0.0)
		add_child(_probe)
		probe_captures_requested += 1

## Малює контур шару з тонких рисок, а не заливкою тайлів (§3.13: «контур,
## не заливка» — і зони руху, і шлях мусять лишати місцевість та бойові сліди під
## собою видимими). Кожен сегмент — {cell: Vector2i, dir: Vector2i, color:
## Color}: тонка риска вздовж ребра `cell` з боку `dir`, а не перефарбування
## всього тайла. Замінює попередній контур цього шару —
## §3.2 «перемальовується після кожної дії» означає заміну.
##
## Один MultiMeshInstance3D на шар (не на сегмент) — ті самі draw-call міркування,
## що й у суцільної землі: дошка складається з десятків сегментів
## контуру за раз, і кожен окремим вузлом уже помітно проти бюджету §8.
func draw_contour(segments: Array[Dictionary], layer: int) -> void:
	clear_contour(layer)
	var kept: Array[Dictionary] = []
	for seg in segments:
		if _kind_by_cell.has(seg["cell"]):
			kept.append(seg)
	_contour_segments[layer] = kept
	if kept.is_empty():
		return

	# Усі риски шару — один стрічковий меш, накладений на ґрунт (кожна вершина бере висоту з
	# карти висот), у MultiMesh з одним екземпляром. Кінці стрічок заходять один за одного
	# (довжина 0.95 > відстань до перпендикулярного ребра), тож кути зімкнуті на будь-якому схилі.
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for seg in kept:
		var cell: Vector2i = seg["cell"]
		var dir: Vector2i = seg["dir"]
		var along := Vector3(1.0, 0.0, 0.0) if dir.x == 0 else Vector3(0.0, 0.0, 1.0)
		var side := Vector3(0.0, 0.0, 1.0) if dir.x == 0 else Vector3(1.0, 0.0, 0.0)
		var mid := Vector3(cell.x + dir.x * _CONTOUR_OFFSET, 0.0, cell.y + dir.y * _CONTOUR_OFFSET)
		var half: float = _CONTOUR_LENGTH * 0.5
		var base: int = verts.size()
		for k in _CONTOUR_PIECES + 1:
			var c: Vector3 = mid + along * lerpf(-half, half, float(k) / _CONTOUR_PIECES)
			for sgn: float in [-1.0, 1.0]:
				var p: Vector3 = c + side * (sgn * _CONTOUR_WIDTH * 0.5)
				verts.append(Vector3(p.x, TerrainHeight.ground_y(p.x, p.z) + _CONTOUR_Y, p.z))
				colors.append(seg["color"])
			if k > 0:
				var i: int = base + k * 2
				indices.append_array([i - 2, i - 1, i, i - 1, i + 1, i])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var ribbon := ArrayMesh.new()
	ribbon.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = ribbon
	mm.instance_count = 1
	mm.set_instance_transform(0, Transform3D.IDENTITY)

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Contour%d" % layer
	mmi.multimesh = mm
	mmi.material_override = _contour_material()
	mmi.layers = 1 << (OVERLAY_LAYER - 1)
	add_child(mmi)
	_contour_nodes[layer] = mmi


## Перебудова тайлів після зміни виду (міст підірвано чи відновлено, BridgeChanged).
## build() знімає й контури, а зони й цілі в цю мить досі правдиві — тож
## малюємо їх наново тими самими сегментами.
func rebuild_tiles(board: Board) -> void:
	var kept: Dictionary = _contour_segments.duplicate()
	var kept_circles: Dictionary = _circles.duplicate()
	build(board)
	_request_probe_capture()
	for layer: int in kept:
		var segs: Array[Dictionary] = []
		segs.assign(kept[layer])
		draw_contour(segs, layer)
	for layer: int in kept_circles:
		var circles: Array[Dictionary] = []
		circles.assign(kept_circles[layer])
		draw_circles(circles, layer)


## Кільце дальності (§3.13, docs/ui/overlays.md): одне геометричне коло, не контур
## тайлів — радіус у тайлах (тайл — 1.0 світу), центр у середині тайла. Радіус
## приходить готовим із core/ (Targeting.inspection); тут лише геометрія малювання.
## Сплющений тор — один вузол і один draw call на коло (§8). Замінює кола шару.
func draw_circles(circles: Array[Dictionary], layer: int) -> void:
	for node: Node in _circle_nodes.get(layer, []):
		if is_instance_valid(node):
			node.free()
	_circles[layer] = circles
	var nodes: Array[Node] = []
	for c in circles:
		var r: float = float(c["radius"])
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = c["color"]
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var mi := MeshInstance3D.new()
		mi.name = "Circle%d_%d" % [layer, nodes.size()]
		mi.mesh = _ring_mesh(IsoCameraRig.cell_to_world(c["center"]), r)
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.layers = 1 << (OVERLAY_LAYER - 1)
		# Вершини кільця — у світі (висота за ґрунтом), тож вузол стоїть у центрі колом на y = 0.
		var centre: Vector3 = IsoCameraRig.cell_to_world(c["center"])
		mi.position = Vector3(centre.x, 0.0, centre.z)
		add_child(mi)
		nodes.append(mi)
	_circle_nodes[layer] = nodes


## Кільце-стрічка шириною _CONTOUR_WIDTH, що лягає на ґрунт: кожна вершина бере висоту з
## карти висот (тор лишився б площиною й тонув у схилі). Вершини — відносно центру в XZ.
func _ring_mesh(centre: Vector3, radius: float) -> ArrayMesh:
	var segments: int = clampi(int(TAU * radius * 8.0), 64, 512)
	var verts := PackedVector3Array()
	var indices := PackedInt32Array()
	for k in segments + 1:
		var a: float = TAU * float(k) / float(segments)
		var dir := Vector2(cos(a), sin(a))
		for r: float in [radius - _CONTOUR_WIDTH * 0.5, radius + _CONTOUR_WIDTH * 0.5]:
			var p := Vector2(centre.x, centre.z) + dir * r
			verts.append(Vector3(dir.x * r, TerrainHeight.ground_y(p.x, p.y) + _CONTOUR_Y, dir.y * r))
		if k > 0:
			var i: int = k * 2
			indices.append_array([i - 2, i - 1, i, i - 1, i + 1, i])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func circles(layer: int) -> Array:
	return _circles.get(layer, [])


## Вид тайла, який зараз намальовано (-1 — тайла немає).
func kind_at(cell: Vector2i) -> int:
	return _kind_by_cell.get(cell, -1)


func clear_contour(layer: int) -> void:
	_contour_segments[layer] = []
	if _contour_nodes.has(layer):
		var node: Node = _contour_nodes[layer]
		if is_instance_valid(node):
			node.free()
		_contour_nodes.erase(layer)


func contour_segments(layer: int) -> Array:
	return _contour_segments.get(layer, [])


func _contour_material() -> StandardMaterial3D:
	# Колір іде з екземпляра мультимешу (use_colors), матеріал лише вмикає його
	# читання — сам він лишається білим, щоб не домішувати власний тон.
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Стрічка без нормалей: освітлення дало б чорні ділянки; контур — позначка, не матеріал.
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Зони руху — головний інтерфейс гри (§3.2): підніжжя огорожі чи стіна, що стоїть на межі
	# клітинки, не сміє сховати риску.
	mat.no_depth_test = true
	mat.render_priority = 1
	return mat


func reflection_probe() -> ReflectionProbe:
	return _probe


func props() -> PropLayer:
	return _props


## Клітинки юнітів, що зараз на дошці: будівлі над ними й між ними та камерою розчиняються.
## instant — без переходу (гейт передачі, §3.5): див. PropLayer.set_reveal_cells.
func set_reveal_cells(cells: Array[Vector2i], instant: bool = false) -> void:
	_props.set_reveal_cells(cells, instant)


## Клітинки з розчавленими пропсами, уже обрізані розвіданим глядача (§3.5).
func set_crushed_cells(cells: Array[Vector2i]) -> void:
	_props.set_crushed(cells)


## Ім'я файлу карти без розширення: мости своєї карти й сіль хешу розстановки.
func _map_key() -> StringName:
	return StringName(ring_map.resource_path.get_file().get_basename()) if ring_map != null else &""


## Від центру дошки до баз гравця 0: половини дошки мають власний набір пропсів.
func _half_dir(board: Board) -> Vector2:
	if ring_map == null:
		return Vector2.ZERO
	var sum := Vector2.ZERO
	var n: int = 0
	for sp: Dictionary in ring_map.spawns:
		if int(sp.get("owner", 0)) == 0:
			sum += Vector2(sp["pos"] as Vector2i)
			n += 1
	if n == 0:
		return Vector2.ZERO
	return sum / n - (Vector2(board.width, board.height) * 0.5 - Vector2(0.5, 0.5))


## Імла пливе лише цим кроком, а не за `TIME`: матеріал з `TIME` змушує Mobile малювати
## кожен кадр, і дошка без руху не відпочивала б зовсім.
func _tick_fog() -> void:
	fog_time += FOG_TICK
	RenderingServer.global_shader_parameter_set(&"fog_time", fog_time)


## Вісь дороги через міст: та, де за суцільним рядом клітинок мосту стоїть
## дорога з обох боків. Широкий міст (кілька клітинок) так не плутає вісь із
## сусідньою клітинкою того ж мосту. Руїни беруть ту саму вісь.
static func _bridge_axis(board: Board, cell: Vector2i) -> Vector2i:
	var best := Vector2i(1, 0)
	var best_score := -1
	for axis: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
		var score := 0
		for dir: Vector2i in [axis, -axis]:
			var p := cell + dir
			while board.in_bounds(p) and board.kind_at(p) == Terrain.Kind.BRIDGE:
				p += dir
			if board.in_bounds(p) and board.kind_at(p) == Terrain.Kind.ROAD:
				score += 1
		if score > best_score:
			best = axis
			best_score = score
	return best


## Перезнімає світ один раз (підірваний чи відновлений міст мусить бути й у
## відбитті). Безпечно посеред партії: накладки (OVERLAY_LAYER), юніти
## (UnitView.UNIT_LAYER) і міни (MineLayer.MARKER_LAYER) — поза маскою зонда.
## Повторне присвоєння UPDATE_ONCE знову позначає зонд у RenderingServer до зйомки.
func _request_probe_capture() -> void:
	_probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe_captures_requested += 1
