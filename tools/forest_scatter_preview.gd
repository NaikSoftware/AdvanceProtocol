extends Node
## Ліс з окремих крон бібліотеки, розкиданих так, як їх розкидатиме дошка. Два режими:
## - тестовий ліс 6×5 тайлів: танк у проламаній просіці, відділення в стоячому лісі,
##   кожен варіант показу юнітів (`FADE_MODES`) на мінімальному й максимальному зумі,
##   плюс «чистий» кадр без лісу для підрахунку пікселів юнітів і кадр поодиноких дерев;
## - `map`: справжній бойовий екран із картою <вигляд>: ліс на всіх клітинках FOREST,
##   просіка з 3–4 клітинок до й після пролому, варіанти показу юнітів, загальні кадри.
## Запуск (потрібне вікно, не --headless):
##   $GODOT --path . res://tools/forest_scatter_preview.tscn -- <тека> <ліс> <сезон> <вигляд> [map]
## ліс: pine | mixed | deciduous; сезон: late | summer | early; вигляд: river | crossroads | ridge.
##
## Правила розкидання — `ForestScatter.plan()` (game/battle/forest_scatter.gd); тут лише показ.
## - Тінь дерева кидає не крона, а її проксі `<вузол>_Shadow` (~34 трикутники, лише тінь):
##   форма та сама, тіньовий прохід у кілька разів дешевший.
## - Проламані клітинки (`_broken`) — з карти проламів того, хто дивиться.
## - Показ юнітів у лісі — одне налаштування з `FADE_MODES`: `none` — нічого;
##   `silhouette` — схована частина юніта видна обрисом кольору гравця (другий прохід без
##   тесту глибини); `soft` — лише крони, що накривають юніта, напівпрозорі (40–60 %);
##   `cut` — крони над юнітом зникають цілими пучками.

const WINDOW: Vector2i = Vector2i(1600, 900)
const TILE_M: float = 8.0
const COLS: int = 6
const ROWS: int = 5
const ORIGIN: Vector2i = Vector2i(3, 3)
const SEED: int = 7

const FADE_MODES: PackedStringArray = ["none", "silhouette", "soft", "cut"]
## Показ юнітів у лісі за замовчуванням — обрис кольору гравця крізь крони.
const DEFAULT_MODE: String = "silhouette"
const FADE_RADIUS: float = 0.6
const FADE_SOFT: float = 0.15
const FADE_REACH_EXTRA: float = 0.5
## Непрозорість крони над юнітом у режимі `soft` і ширина м'якого переходу (тайли).
const SOFT_ALPHA: float = 0.5
const SOFT_FALLOFF: float = 0.3
## Півдовжина корпусу юніта (тайли): танк, відділення — маска росте на неї.
const UNIT_HALF: Array[float] = [0.45, 0.2]
const UNIT_COLOR: Array[Color] = [Color(0.75, 0.2, 0.15), Color(0.95, 0.85, 0.1)]

## Тон поля тестового лісу; світло, тінь, дощ і тон листя ставить WeatherRig за
## game/battle/look/<вигляд>.tres — так само, як на бойовому екрані.
const GROUND: Dictionary = {"river": Color(0.29, 0.30, 0.22), "crossroads": Color(0.36, 0.35, 0.24),
	"ridge": Color(0.33, 0.32, 0.22)}

const HEROES: Array = [["Hero_Oak", Vector2(9.5, 1.0)], ["Hero_Lime", Vector2(12.4, 2.6)],
		["Hero_Birch", Vector2(9.8, 4.0)], ["Hero_Poplar", Vector2(11.4, 5.2)], ["Hero_Poplar", Vector2(12.3, 5.6)]]

var _rig: IsoCameraRig
var _root: Node
var _forest: Dictionary = {}  ## Vector2i -> true
var _offset := Vector3.ZERO  ## світова позиція клітинки (0, 0)
var _meshes: Dictionary = {}  ## префікс виду -> Array[Mesh]
var _named: Dictionary = {}  ## ім'я вузла -> Mesh
var _species: Dictionary = {}  ## Mesh -> префікс виду
var _material: Dictionary = {}  ## Mesh -> ShaderMaterial
var _soft_material: Dictionary = {}  ## Mesh -> ShaderMaterial (режим soft)
var _ground_mesh: Dictionary = {}  ## Soil_Lane -> Mesh
var _groups: Dictionary = {}  ## Mesh -> Array[Dictionary] {xf, top, pos, r, rgb}
var _ground_groups: Dictionary = {}  ## Mesh -> Array[Transform3D]
var _mmi: Dictionary = {}  ## Mesh -> MultiMeshInstance3D
var _soft_mmi: Dictionary = {}
var _nodes: Array[Node] = []
var _units: Array[Vector2] = [Vector2(2.0, 2.0), Vector2(4.0, 2.0)]
var _boxes: Array[MeshInstance3D] = []
var _broken: Dictionary = {}
var _season: String = ""
var _wood_at: Callable
var _measure: bool = false  ## лише кадри для вимірювання: z6 і z20, кожен із маскою
var _mask_material: Dictionary = {}  ## Mesh -> матеріал маски (неосвітлений колір виду)
var _proxy: Dictionary = {}  ## Mesh крони -> Mesh її проксі тіні
var _proxy_mmi: Dictionary = {}  ## Mesh крони -> MultiMeshInstance3D проксі


## MSAA 2× (alpha-to-coverage для країв крон); як у проєкті, rendering/anti_aliasing/quality/msaa_3d.
const MSAA := Viewport.MSAA_2X


func _ready() -> void:
	get_viewport().msaa_3d = MSAA
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var out: String = args[0]
	var wood: String = args[1] if args.size() > 1 else "mixed"
	var season: String = args[2] if args.size() > 2 else "late"
	var look_name: String = args[3] if args.size() > 3 else "river"
	var on_map: bool = args.size() > 4 and args[4] in ["map", "measure"]
	_measure = args.size() > 4 and args[4] == "measure"
	_season = season
	DirAccess.make_dir_recursive_absolute(out)
	get_window().size = WINDOW
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	_load_library(season)
	if on_map:
		await _map_frames(out, wood, season, look_name)
	else:
		await _test_frames(out, wood, season, look_name)
	get_tree().quit()


func _test_frames(out: String, wood: String, season: String, look_name: String) -> void:
	_root = self
	_rig = (load("res://game/camera/iso_camera_rig.tscn") as PackedScene).instantiate()
	add_child(_rig)
	_rig.set_bounds(Vector2i(18, 14))
	var weather := WeatherRig.new()
	add_child(weather)
	var look: BattleLook = load("res://game/battle/look/%s.tres" % look_name) as BattleLook
	weather.apply(look)
	_ground(GROUND[look_name])
	for y in ROWS:
		for x in COLS:
			_forest[Vector2i(x, y)] = true
	_offset = Vector3(ORIGIN.x, 0, ORIGIN.y)
	# Підставний список проламів: клітинка танка й прохід до краю (на дошці — карта проламів).
	for c: Vector2i in [Vector2i(2, 2), Vector2i(2, 1), Vector2i(2, 0)]:
		_broken[c] = true
	_wood_at = func(_p: Vector2) -> String: return wood
	_rebuild(true)
	_add_boxes()
	await get_tree().process_frame
	_report("wood=%s season=%s tiles=%d" % [wood, season, COLS * ROWS])
	_rig.center_on(ORIGIN + Vector2i(3, 2))
	await _variants(out, "%s_%s_%s" % [wood, season, look_name])
	_set_mode(DEFAULT_MODE)
	_rig.center_on(ORIGIN + Vector2i(10, 2))
	await _shoot(IsoCameraRig.MIN_ZOOM, "%s/heroes_%s_%s_min.png" % [out, season, look_name])


## Справжня карта: ліс на клітинках FOREST, ліва половина — сосновий бік, права — `wood`.
func _map_frames(out: String, wood: String, season: String, look_name: String) -> void:
	var bs: Node = (load("res://game/battle/battle_screen.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(bs)
	await get_tree().process_frame
	var m: MapData = load("res://maps/%s.tres" % look_name) as MapData
	bs.setup(m, 2, 1)
	(bs.get_node("%Units") as Node3D).visible = false
	(bs.get_node("UI") as CanvasLayer).visible = false
	_rig = bs.get_node("%CameraRig")
	_root = bs
	var board: Board = bs._match_service.state.board
	var sum := Vector2.ZERO
	for y in board.height:
		for x in board.width:
			if board.kind_at(Vector2i(x, y)) == Terrain.Kind.FOREST:
				_forest[Vector2i(x, y)] = true
				sum += Vector2(x, y)
	var half: float = board.width / 2.0
	_wood_at = func(p: Vector2) -> String: return "pine" if p.x < half else wood
	var lane: Array[Vector2i] = _find_lane()
	var mid: Vector2i = lane[1]
	var dir: Vector2i = lane[1] - lane[0]
	var side := Vector2i(dir.y, dir.x)
	var squad_cell: Vector2i = mid + side * 2 if _forest.has(mid + side * 2) else mid - side * 2
	if not _forest.has(squad_cell):
		squad_cell = mid + side if _forest.has(mid + side) else mid - side
	_units = [Vector2(mid), Vector2(squad_cell)]
	# Просіка до пролому й після: та сама камера, тільки карта проламів інша.
	_rebuild(true)
	await get_tree().process_frame
	_report("map=%s season=%s forest_cells=%d" % [look_name, season, _forest.size()])
	# Бойовий екран після setup() ще веде камеру до першого юніта: чекаємо, доки доведе.
	for i in 180:
		await get_tree().process_frame
	if _measure:
		for c: Vector2i in lane:
			_broken[c] = true
		_rebuild(true)
		for z: Array in [["z6", IsoCameraRig.MIN_ZOOM], ["z20", IsoCameraRig.MAX_ZOOM]]:
			_rig.center_on(mid)
			await _shoot(z[1], "%s/m_%s_%s_%s.png" % [out, look_name, season, z[0]])
			# Ціна MSAA на тому самому кадрі: середній час GPU без і з.
			get_viewport().msaa_3d = Viewport.MSAA_DISABLED
			var t_off: float = await _gpu_avg(90)
			get_viewport().msaa_3d = MSAA
			var t_on: float = await _gpu_avg(90)
			print("MSAA_GPU %s %s off=%.2f on=%.2f calls=%d" % [look_name, z[0], t_off, t_on,
					RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)])
			_mask_on(true)
			await _shoot(z[1], "%s/m_%s_%s_%s_mask.png" % [out, look_name, season, z[0]])
			_mask_on(false)
			_set_mode("clear")
			await _shoot(z[1], "%s/m_%s_%s_%s_ground.png" % [out, look_name, season, z[0]])
			_set_mode(DEFAULT_MODE)
			for hm: Array in [["cells", 1.05], ["cells_top", 1.3]]:
				var cells := _cell_mask(hm[1])
				_set_mode("clear")
				await _shoot(z[1], "%s/m_%s_%s_%s_%s.png" % [out, look_name, season, z[0], hm[0]])
				cells.queue_free()
			_set_mode(DEFAULT_MODE)
		return
	_rig.center_on(mid)
	await _shoot(IsoCameraRig.MAX_ZOOM, "%s/_settle.png" % out)
	_rig.center_on(mid)
	for z: Array in [["min", IsoCameraRig.MIN_ZOOM], ["max", IsoCameraRig.MAX_ZOOM]]:
		await _shoot(z[1], "%s/map_%s_%s_lane_before_%s.png" % [out, look_name, season, z[0]])
	for c: Vector2i in lane:
		_broken[c] = true
	_rebuild(true)
	_rig.center_on(mid)
	for z: Array in [["min", IsoCameraRig.MIN_ZOOM], ["max", IsoCameraRig.MAX_ZOOM]]:
		await _shoot(z[1], "%s/map_%s_%s_lane_after_%s.png" % [out, look_name, season, z[0]])
	_add_boxes()
	await _variants(out, "map_%s_%s" % [look_name, season])
	_set_mode(DEFAULT_MODE)
	for b: MeshInstance3D in _boxes:
		b.visible = false
	var shots: Array = []
	var seen: Dictionary = {}
	for c: Vector2i in _forest:
		var key := Vector2i(c.x / 8, c.y / 7)
		if not seen.has(key):
			seen[key] = c
	for k: Vector2i in seen:
		shots.append(seen[k])
	shots = shots.slice(0, 4)
	var i: int = 0
	for c: Vector2i in shots:
		_rig.center_on(c)
		await _shoot(IsoCameraRig.MIN_ZOOM, "%s/map_%s_%s_%d_min.png" % [out, look_name, season, i])
		i += 1
	_rig.center_on(Vector2i(roundi(sum.x / _forest.size()), roundi(sum.y / _forest.size())))
	await _shoot(IsoCameraRig.MAX_ZOOM, "%s/map_%s_%s_max.png" % [out, look_name, season])
	# Тінь від справжніх крон проти тіні від проксі: форма має збігтися, прохід — подешевшати.
	for z: Array in [["min", IsoCameraRig.MIN_ZOOM], ["max", IsoCameraRig.MAX_ZOOM]]:
		if z[0] == "min":
			_rig.center_on(shots[0])
		_use_proxies(false)
		await _shoot(z[1], "%s/map_%s_%s_shadow_crowns_%s.png" % [out, look_name, season, z[0]])
		var t_rt: float = await _gpu_avg(90)
		var info_rt: String = _shadow_info()
		_use_proxies(true)
		await _shoot(z[1], "%s/map_%s_%s_shadow_proxy_%s.png" % [out, look_name, season, z[0]])
		var t_bk: float = await _gpu_avg(90)
		if z[0] == "min":
			print("CASTERS proxy ", _casters())
		print("SHADOW_GPU %s %s crowns=%.2f proxy=%.2f shadow crowns %s proxy %s" % [look_name, z[0], t_rt, t_bk, info_rt, _shadow_info()])


## Пряма з 4 клітинок лісу, що входить у ліс з поля (перед першою клітинкою — не ліс) і
## йде гущею: так видно і вхід просіки, і її межі серед стоячих дерев.
func _find_lane() -> Array[Vector2i]:
	var best: Array[Vector2i] = []
	var best_score: int = -1
	for c: Vector2i in _forest:
		for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
			var run: Array[Vector2i] = []
			for k in 4:
				if _forest.has(c + d * k):
					run.append(c + d * k)
			if run.size() < 4 or _forest.has(c - d):
				continue
			var side := Vector2i(d.y, d.x)
			var score: int = 0
			for r: Vector2i in run:
				score += int(_forest.has(r + side)) + int(_forest.has(r - side)) + int(_forest.has(r + side * 2)) + int(_forest.has(r - side * 2))
			if score > best_score:
				best_score = score
				best = run
	return best


## Варіанти показу юнітів на обох зумах + чистий кадр без лісу; час кадру GPU поруч.
func _variants(out: String, tag: String) -> void:
	for z: Array in [["min", IsoCameraRig.MIN_ZOOM], ["max", IsoCameraRig.MAX_ZOOM]]:
		_set_mode("clear")
		await _shoot(z[1], "%s/%s_units_clear_%s.png" % [out, tag, z[0]])
		for mode: String in ["none", "silhouette", "soft", "cut"]:
			_set_mode(mode)
			await _shoot(z[1], "%s/%s_units_%s_%s.png" % [out, tag, mode, z[0]])


func _ground(c: Color) -> void:
	var field := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(46, 34)
	field.mesh = plane
	var fm := StandardMaterial3D.new()
	fm.albedo_color = c
	fm.roughness = 1.0
	field.material_override = fm
	field.position = Vector3(ORIGIN.x + 6.0, 0, ORIGIN.y + 2.0)
	add_child(field)


func _load_library(season: String) -> void:
	var shader: Shader = load("res://assets/props/forest/forest_crown.gdshader")
	# Режим soft: та сама крона, але альфа екземпляра — справжня прозорість, а не відкидання.
	var soft := Shader.new()
	soft.code = shader.code.replace("depth_draw_opaque, ", "").replace(", alpha_to_coverage", "").replace(
			"|| (!shadow_pass && piece_hash > COLOR.a)", "").replace(
			"ROUGHNESS = 1.0;", "ROUGHNESS = 1.0;\n\tALPHA = COLOR.a;").replace(
			"ALPHA = t.a; ALPHA_SCISSOR_THRESHOLD = cut; ALPHA_ANTIALIASING_EDGE = a2c_edge; ALPHA_TEXTURE_COORDINATE = UV * vec2(textureSize(albedo_tex, 0));",
			"if (t.a < cut) { discard; }")
	assert(soft.code.contains("ALPHA = COLOR.a;"), "шейдер soft не зібрався: змінився forest_crown.gdshader")
	# Маска для вимірювання: ті самі пікселі крони, неосвітлений колір виду.
	var mask := Shader.new()
	mask.code = shader.code.replace("render_mode cull_disabled,", "render_mode unshaded, cull_disabled,").replace(
			"ROUGHNESS = 1.0;", "ALBEDO = mix(vec3(1.0, 0.0, 1.0), mask_col, is_card);\n\tROUGHNESS = 1.0;").replace(
			"shader_type spatial;", "shader_type spatial;\nuniform vec3 mask_col;")
	assert(mask.code.contains("mask_col, is_card);") and mask.code.contains("unshaded"), "шейдер маски не зібрався")
	for path: String in ["res://assets/props/forest/forest_conifer.glb", "res://assets/props/forest/forest_broadleaf_%s.glb" % season]:
		var root: Node = (load(path) as PackedScene).instantiate()
		var meshes: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
		for mi: MeshInstance3D in meshes:
			if String(mi.name).ends_with("_Shadow"):
				_proxy[(root.find_child(String(mi.name).trim_suffix("_Shadow"), true, false) as MeshInstance3D).mesh] = mi.mesh
		for mi: MeshInstance3D in meshes:
			var prefix: String = String(mi.name).get_slice("_", 0)
			_named[String(mi.name)] = mi.mesh
			_species[mi.mesh] = prefix
			if not _meshes.has(prefix):
				_meshes[prefix] = []
			(_meshes[prefix] as Array).append(mi.mesh)
			if String(mi.name).ends_with("_Shadow"):
				_named.erase(String(mi.name))
				_species.erase(mi.mesh)
				(_meshes[prefix] as Array).erase(mi.mesh)
			var src: StandardMaterial3D = mi.mesh.surface_get_material(0) as StandardMaterial3D
			for pair: Array in [[shader, _material], [soft, _soft_material], [mask, _mask_material]]:
				var m := ShaderMaterial.new()
				m.shader = pair[0]
				m.set_shader_parameter("albedo_tex", src.albedo_texture)
				m.set_shader_parameter("alpha_cutoff", src.alpha_scissor_threshold)
				# Червоний — хвойні, зелений — листяні дерева, синій — решта (кущі, узлісся, гілля).
				var conifer: bool = prefix in ["Pine", "Spruce"]
				var broad: bool = prefix in ["Birch", "Oak", "Hero"]
				m.set_shader_parameter("mask_col", Color(1, 0, 0) if conifer else (Color(0, 1, 0) if broad else Color(0, 0, 1)))
				(pair[1] as Dictionary)[mi.mesh] = m
		root.free()
	var g: Node = (load("res://assets/props/forest/forest_ground.glb") as PackedScene).instantiate()
	for mi: MeshInstance3D in g.find_children("*", "MeshInstance3D", true, false):
		_ground_mesh[String(mi.name)] = mi.mesh
	g.free()


func _rebuild(with_ground: bool) -> void:
	for n: Node in _nodes:
		n.queue_free()
	_nodes.clear()
	_groups.clear()
	_ground_groups.clear()
	_mmi.clear()
	_soft_mmi.clear()
	_proxy_mmi.clear()
	var lib: Dictionary = {}
	for name: String in _named:
		var a: AABB = (_named[name] as Mesh).get_aabb()
		lib[name] = {"h": a.end.y, "half": maxf(maxf(-a.position.x, a.end.x), maxf(-a.position.z, a.end.z))}
	var fixed: Array = HEROES if _offset == Vector3(ORIGIN.x, 0, ORIGIN.y) else []
	for e: Dictionary in ForestScatter.plan(_forest, _wood_at, _broken, _season, SEED, lib, fixed):
		var xf: Transform3D = e["xf"]
		xf.origin += _offset
		if e["ground"]:
			if _ground_mesh.has(e["node"]):
				_ground_add(e["node"], xf)
		else:
			_add_instance(_named[e["node"]], xf, e["pos"], e["r"], e["rgb"])
	_build_multimeshes()
	if with_ground:
		_build_ground()


func _add_instance(mesh: Mesh, xf: Transform3D, p: Vector2, r: float, rgb: Color = Color.WHITE) -> void:
	if not _groups.has(mesh):
		_groups[mesh] = []
	(_groups[mesh] as Array).append({"xf": _on_ground(xf), "top": mesh.get_aabb().end.y * xf.basis.get_scale().y + 0.15, "pos": p, "r": r, "rgb": rgb})


func _build_multimeshes() -> void:
	for mesh: Mesh in _groups:
		var list: Array = _groups[mesh]
		for pair: Array in [[_material, _mmi], [_soft_material, _soft_mmi]]:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.use_custom_data = true
			mm.mesh = mesh
			mm.instance_count = list.size()
			for i in list.size():
				mm.set_instance_transform(i, list[i]["xf"])
				var c: Color = list[i]["rgb"]
				# Тон крони — у custom data; у кольорі лише розчинення (альфа).
				mm.set_instance_custom_data(i, Color(c.r, c.g, c.b, 1.0))
				mm.set_instance_color(i, Color(1, 1, 1, 1.0 if pair[1] == _mmi else 0.0))
			var node := MultiMeshInstance3D.new()
			node.multimesh = mm
			node.material_override = (pair[0] as Dictionary)[mesh]
			# Картки розгортаються в шейдері, тож AABB меша не містить країв пучків.
			node.extra_cull_margin = 0.4
			node.visible = pair[1] == _mmi
			# Тінь дерева кидає проксі (нижче); видима крона — лише якщо проксі немає.
			# Підстилка лежить пласко на землі — її тінь не видно, а прохід вона коштує.
			if pair[1] != _mmi or _proxy.has(mesh) or _species.get(mesh, "") == "Litter":
				node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_root.add_child(node)
			_nodes.append(node)
			(pair[1] as Dictionary)[mesh] = node
		if _proxy.has(mesh):
			var main: MultiMeshInstance3D = _mmi[mesh]
			var mm: MultiMesh = main.multimesh.duplicate() as MultiMesh
			mm.mesh = _proxy[mesh]
			var node := MultiMeshInstance3D.new()
			node.multimesh = mm
			node.material_override = main.material_override
			node.extra_cull_margin = main.extra_cull_margin
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			_root.add_child(node)
			_nodes.append(node)
			_proxy_mmi[mesh] = node


func _build_ground() -> void:
	for name: String in _ground_groups:
		var node := MeshInstance3D.new()
		node.mesh = _drape(_ground_mesh[name], _ground_groups[name])
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_root.add_child(node)
		_nodes.append(node)


## Рельєф карти косметичний, але є (до ±2 м): усе, що стоїть на землі, — на її висоті.
func _on_ground(xf: Transform3D) -> Transform3D:
	xf.origin.y += TerrainHeight.ground_y(xf.origin.x, xf.origin.z)
	return xf


## Плоскі шматки землі не можуть лишатись пласкими квадами: рельєф прорізав би їх прямими
## лініями. Кожен шматок — сітка DRAPE × DRAPE, вершини на висоті землі + DRAPE_LIFT; усі
## шматки одного виду — один меш, один виклик малювання.
const DRAPE: int = 10
const DRAPE_LIFT: float = 0.01


func _drape(src: Mesh, xfs: Array) -> ArrayMesh:
	var a: Array = src.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
	# Кути квада за UV: (min u, min v) … (max u, max v), білінійно між ними.
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for t in uv:
		lo = lo.min(t)
		hi = hi.max(t)
	var corner: Dictionary = {}
	for i in v.size():
		corner[Vector2i(int(uv[i].x > (lo.x + hi.x) * 0.5), int(uv[i].y > (lo.y + hi.y) * 0.5))] = v[i]
	assert(corner.size() == 4, "шматок землі має бути квадом")
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base: int = 0
	for xf: Transform3D in xfs:
		for j in DRAPE + 1:
			for i in DRAPE + 1:
				var fx: float = float(i) / DRAPE
				var fy: float = float(j) / DRAPE
				var local: Vector3 = (corner[Vector2i(0, 0)] as Vector3).lerp(corner[Vector2i(1, 0)], fx).lerp(
						(corner[Vector2i(0, 1)] as Vector3).lerp(corner[Vector2i(1, 1)], fx), fy)
				var w: Vector3 = xf * local
				w.y = TerrainHeight.ground_y(w.x, w.z) + DRAPE_LIFT
				st.set_uv(Vector2(lerpf(lo.x, hi.x, fx), lerpf(lo.y, hi.y, fy)))
				st.set_normal(Vector3.UP)
				st.add_vertex(w)
		for j in DRAPE:
			for i in DRAPE:
				var k: int = base + j * (DRAPE + 1) + i
				for idx: int in [k, k + 1, k + DRAPE + 2, k, k + DRAPE + 2, k + DRAPE + 1]:
					st.add_index(idx)
		base += (DRAPE + 1) * (DRAPE + 1)
	var m: ArrayMesh = st.commit()
	m.surface_set_material(0, src.surface_get_material(0))
	return m


## Хто кидає тінь: вид -> трикутники всіх екземплярів (до каскадів).
func _casters() -> String:
	var by: Dictionary = {}
	for n: Node in _nodes:
		var mmi := n as MultiMeshInstance3D
		if mmi == null or not mmi.visible or mmi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			continue
		var m: Mesh = mmi.multimesh.mesh
		var k: String = m.resource_name if m.resource_name != "" else str(m)
		var t: int = 0
		for si in m.get_surface_count():
			t += (m.surface_get_arrays(si)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		by[k] = int(by.get(k, 0)) + t * mmi.multimesh.instance_count
	return str(by)


## Біла маска стоячих лісових клітинок (без просіки) поверх усього, на висоті height
## (тайли): середина крони ~8,5 м або верх зімкненого лісу ~10,5 м — з камери гри крона
## лежить над клітинкою там, а не на землі.
func _cell_mask(height: float) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for c: Vector2i in _forest:
		if _broken.has(c):
			continue
		var q: Array[Vector3] = []
		for o: Vector2 in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)]:
			var w := _offset + Vector3(c.x + o.x, 0.0, c.y + o.y)
			w.y = TerrainHeight.ground_y(w.x, w.z) + height
			q.append(w)
		for i: int in [0, 1, 2, 0, 2, 3]:
			st.add_vertex(q[i])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.no_depth_test = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color.WHITE
	mi.material_override = m
	_root.add_child(mi)
	return mi


func _mask_on(on: bool) -> void:
	for mesh: Mesh in _mmi:
		(_mmi[mesh] as GeometryInstance3D).material_override = _mask_material[mesh] if on else _material[mesh]


## false — тінь кидають самі крони (для порівняння), true — проксі.
func _use_proxies(on: bool) -> void:
	for mesh: Mesh in _proxy_mmi:
		(_mmi[mesh] as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if on else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		(_proxy_mmi[mesh] as Node3D).visible = on


func _ground_add(name: String, xf: Transform3D) -> void:
	if not _ground_groups.has(name):
		_ground_groups[name] = []
	(_ground_groups[name] as Array).append(xf)


## Наскільки крона i накриває юніта: 0 — накриває повністю, 1 — далеко (у тайлах відстані).
func _cover(entry: Dictionary, cam: Camera3D, soft: float) -> float:
	var a: float = 1.0
	for ui in _units.size():
		var u: Vector2 = _units[ui]
		# Промінь від юніта до камери (перспектива: справжній кут до цієї точки). Крона
		# заввишки top ховає юніта, стоячи до top · (гориз. відстань / висота камери) ближче.
		var to_cam: Vector3 = cam.global_position - (_offset + Vector3(u.x, 0.0, u.y))
		var flat := Vector2(to_cam.x, to_cam.z)
		var reach: float = float(entry["top"]) * flat.length() / to_cam.y + FADE_REACH_EXTRA
		var dir: Vector2 = flat.normalized()
		var p: Vector2 = entry["pos"]
		var t: float = clampf((p - u).dot(dir), 0.0, reach)
		var dist: float = p.distance_to(u + dir * t)
		var r0: float = FADE_RADIUS + float(entry["r"]) + UNIT_HALF[ui]
		a = minf(a, smoothstep(r0, r0 + soft, dist))
	return a


## Режим показу юнітів: none | silhouette | soft | cut, а також clear (ліс схований).
func _set_mode(mode: String) -> void:
	var cam: Camera3D = _rig.find_children("*", "Camera3D", true, false)[0] as Camera3D
	for mesh: Mesh in _groups:
		var list: Array = _groups[mesh]
		var main: MultiMeshInstance3D = _mmi[mesh]
		var soft: MultiMeshInstance3D = _soft_mmi[mesh]
		main.visible = mode != "clear"
		soft.visible = mode == "soft"
		for i in list.size():
			var a: float = 1.0
			var sa: float = 0.0
			if mode == "cut":
				a = _cover(list[i], cam, FADE_SOFT)
			elif mode == "soft":
				var k: float = _cover(list[i], cam, SOFT_FALLOFF)
				if k < 0.999:
					a = 0.0
					sa = lerpf(SOFT_ALPHA, 1.0, k)
			main.multimesh.set_instance_color(i, Color(1, 1, 1, a))
			if _proxy_mmi.has(mesh):
				(_proxy_mmi[mesh] as MultiMeshInstance3D).multimesh.set_instance_color(i, Color(1, 1, 1, a))
			soft.multimesh.set_instance_color(i, Color(1, 1, 1, sa))
	for b: MeshInstance3D in _boxes:
		var m: StandardMaterial3D = b.material_override
		m.next_pass = m.get_meta("silhouette") if mode == "silhouette" else null


func _add_boxes() -> void:
	var sizes: Array[Vector3] = [Vector3(0.45, 0.3, 0.9), Vector3(0.35, 0.2, 0.35)]
	for i in 2:
		var box := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = sizes[i]
		box.mesh = bm
		var m := _flat(UNIT_COLOR[i])
		# Обрис крізь крони: другий прохід без тесту глибини, напівпрозорий колір гравця.
		var sil := StandardMaterial3D.new()
		sil.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sil.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sil.no_depth_test = true
		sil.albedo_color = Color(UNIT_COLOR[i], 0.6)
		sil.render_priority = 10
		m.set_meta("silhouette", sil)
		box.material_override = m
		box.position = _offset + Vector3(_units[i].x, sizes[i].y / 2.0, _units[i].y)
		_root.add_child(box)
		_boxes.append(box)


func _flat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m


func _report(what: String) -> void:
	var tris: int = 0
	var inst: int = 0
	for m: Mesh in _groups:
		tris += _triangles(m) * (_groups[m] as Array).size()
		inst += (_groups[m] as Array).size()
	print("SCATTER %s instances=%d tris=%d multimeshes=%d" % [what, inst, tris, _groups.size() + _ground_groups.size()])
	var by: Dictionary = {}
	for m: Mesh in _groups:
		var k: String = _species.get(m, "?")
		by[k] = int(by.get(k, 0)) + _triangles(m) * (_groups[m] as Array).size()
	print("SCATTER_BY %s" % by)


## Середній час GPU за n кадрів: один кадр шумить у рази, порівнювати можна лише середнє.
## Тіньовий прохід останнього кадру: трикутники й виклики малювання — без шуму таймера.
func _shadow_info() -> String:
	var vp: RID = get_viewport().get_viewport_rid()
	var t: int = RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
	var d: int = RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
	return "tris=%d calls=%d" % [t, d]


func _gpu_avg(n: int) -> float:
	var vp: RID = get_viewport().get_viewport_rid()
	var sum: float = 0.0
	for i in n:
		await get_tree().process_frame
		sum += RenderingServer.viewport_get_measured_render_time_gpu(vp)
	return sum / n


func _shoot(zoom: float, path: String) -> void:
	_rig.zoom_by(zoom / _rig.zoom_level)
	# Пан і зум камери плавні: до та після пролому мають бути в однаковому кадрі.
	for i in 120:
		await get_tree().process_frame
	var vp: RID = get_viewport().get_viewport_rid()
	var gpu: float = RenderingServer.viewport_get_measured_render_time_gpu(vp)
	var calls: int = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var img: Image = get_viewport().get_texture().get_image()
	if img.save_png(path) != OK:
		push_error("PNG не збережено: %s" % path)
	print("SHOT %s draw_calls=%d gpu_ms=%.2f" % [path, calls, gpu])


func _triangles(mesh: Mesh) -> int:
	var t: int = 0
	for s in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(s)
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		t += (idx.size() if not idx.is_empty() else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return t
