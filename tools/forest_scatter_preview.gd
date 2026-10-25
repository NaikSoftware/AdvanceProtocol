extends Node
## Ліс з окремих крон бібліотеки, розкиданих так, як їх розкидатиме дошка: пояс кущів по
## краю, нижчі крайові дерева, далі повний намет. Два режими:
## - тестовий ліс 6×5 тайлів із коробкою танка й коробкою відділення, мінімальний і
##   максимальний зум, без розчинення й із ним, плюс кадр поодиноких дерев;
## - `map`: справжній бойовий екран із картою <вигляд>, ліс на всіх клітинках FOREST.
## Запуск (потрібне вікно, не --headless):
##   $GODOT --path . res://tools/forest_scatter_preview.tscn -- <тека> <ліс> <сезон> <вигляд> [map]
## ліс: pine | mixed | deciduous; сезон: late | summer | early; вигляд: river | crossroads | ridge.
##
## Правила розкидання (їх і переносить дошка):
## - Глибина точки `depth` — відстань у тайлах до найближчої клітинки без лісу (назовні —
##   мінус відстань до лісу), плюс шум ±`EDGE_NOISE` з довжиною хвилі ~1,5 тайла: край не
##   йде по межах клітинок.
## - Пояс кущів: `depth` −0,15…`SHRUB_BAND`, густина `SHRUB_DENSITY` на тайл, висота 2–5 м;
##   частина поясу — молоді ялини (`belt` у `WOODS`): пізньої осені голі кущі пропускають
##   погляд, і стіною край тримає лише зелене до землі.
## - Крайові дерева: `depth` `EDGE_FROM`–`EDGE_TO`, висота 8–15 м; у крайовому ряду —
##   ялина з кроною до землі (`Spruce_B`), щоб край стояв стіною.
## - Намет: `depth` > `CANOPY_FROM`, висота 18–25 м, густина з `WOODS`.
## - Повалені стовбури: `depth` > 0,3, `LOG_DENSITY` на тайл, без масштабу.
## - Усі точки — сітка з кроком 1/√густини, зсунута на ±`JITTER` кроку; поворот довільний.
## - Масштаб: висоту задає шар, ширина крони — той самий множник, обмежений `CROWN_W`,
##   ще ±10 %.
## - Розчинення: екземпляр, чия крона (вісь плюс півширина крони) ближча за `FADE_RADIUS`
##   до відрізка від юніта вздовж справжнього променя до камери завдовжки
##   `висота крони · гориз. відстань до камери / висота камери`, зникає разом із тінню
##   (альфа 0 у кольорі екземпляра); у кільці ще `FADE_SOFT` альфа росте до 1 растром.

const WINDOW: Vector2i = Vector2i(1600, 900)
const TILE_M: float = 8.0
const COLS: int = 6
const ROWS: int = 5
const ORIGIN: Vector2i = Vector2i(3, 3)
const SEED: int = 7

const EDGE_NOISE: float = 0.3
const SHRUB_BAND: float = 0.6
const SHRUB_DENSITY: float = 12.0
const EDGE_FROM: float = 0.25
const EDGE_TO: float = 0.85
const EDGE_DENSITY: float = 2.4
const CANOPY_FROM: float = 0.7
const JITTER: float = 0.4
const FADE_RADIUS: float = 0.6
const FADE_SOFT: float = 0.3
## Межі масштабу ширини крони відносно меша: ширина росте з висотою лише до цих меж.
const CROWN_W: Vector2 = Vector2(0.95, 1.3)
const LOG_DENSITY: float = 0.25
const CANOPY_H: Vector2 = Vector2(18.0, 25.0)
const EDGE_H: Vector2 = Vector2(8.0, 15.0)
## Висота верхнього центра пучка; пучок додає ще ~1 м, тож видима висота 2,5–5 м.
const SHRUB_H: Vector2 = Vector2(1.6, 4.0)

## Склад лісу: частки видів (префікс вузла або ім'я вузла) у наметі й у крайовому ряду.
const WOODS: Dictionary = {
	"pine": {"canopy": {"Pine": 0.85, "Spruce": 0.1, "Birch": 0.05}, "edge": {"Spruce_B": 0.45, "Pine": 0.3, "Birch": 0.25}, "belt": {"Shrub": 0.5, "Spruce_B": 0.5}, "density": 2.4},
	"mixed": {"canopy": {"Pine": 0.45, "Spruce": 0.2, "Birch": 0.2, "Oak": 0.15}, "edge": {"Spruce_B": 0.35, "Birch": 0.4, "Oak": 0.25}, "belt": {"Shrub": 0.65, "Spruce_B": 0.35}, "density": 2.2},
	"deciduous": {"canopy": {"Oak": 0.6, "Birch": 0.3, "Spruce": 0.1}, "edge": {"Birch": 0.45, "Oak": 0.3, "Spruce_B": 0.25}, "belt": {"Shrub": 0.8, "Spruce_B": 0.2}, "density": 1.5},
}

## Тон поля тестового лісу; світло, тінь, дощ і тон листя ставить WeatherRig за
## game/battle/look/<вигляд>.tres — так само, як на бойовому екрані.
const GROUND: Dictionary = {"river": Color(0.29, 0.30, 0.22), "crossroads": Color(0.36, 0.35, 0.24),
	"ridge": Color(0.33, 0.32, 0.22)}

## Поодинокі дерева: ряд у полі праворуч від тестового лісу, окремий кадр.
const HEROES: Array = [["Hero_Oak", Vector2(9.5, 1.0)], ["Hero_Lime", Vector2(12.4, 2.6)],
		["Hero_Birch", Vector2(9.8, 4.0)], ["Hero_Poplar", Vector2(11.4, 5.2)], ["Hero_Poplar", Vector2(12.3, 5.6)]]

var _rig: IsoCameraRig
var _root: Node
var _rng := RandomNumberGenerator.new()
var _noise := FastNoiseLite.new()
var _forest: Dictionary = {}  ## Vector2i -> true
var _offset := Vector3.ZERO  ## світова позиція клітинки (0, 0)
var _meshes: Dictionary = {}  ## префікс виду -> Array[Mesh]
var _named: Dictionary = {}  ## ім'я вузла -> Mesh
var _material: Dictionary = {}  ## Mesh -> ShaderMaterial
var _groups: Dictionary = {}  ## Mesh -> Array[Dictionary] {xf, top, pos}
var _mmi: Dictionary = {}  ## Mesh -> MultiMeshInstance3D
var _units: Array[Vector2] = [Vector2(2.0, 2.0), Vector2(4.0, 2.0)]


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var out: String = args[0]
	var wood: String = args[1] if args.size() > 1 else "mixed"
	var season: String = args[2] if args.size() > 2 else "late"
	var look_name: String = args[3] if args.size() > 3 else "river"
	var on_map: bool = args.size() > 4 and args[4] == "map"
	DirAccess.make_dir_recursive_absolute(out)
	get_window().size = WINDOW
	_rng.seed = SEED
	_noise.seed = SEED
	_noise.frequency = 1.0 / 1.5
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
	weather.apply(load("res://game/battle/look/%s.tres" % look_name) as BattleLook)
	_ground(GROUND[look_name])
	for y in ROWS:
		for x in COLS:
			_forest[Vector2i(x, y)] = true
	_offset = Vector3(ORIGIN.x, 0, ORIGIN.y)
	_scatter(Rect2i(-2, -2, COLS + 4, ROWS + 4), func(_p: Vector2) -> String: return wood)
	for h: Array in HEROES:
		if _named.has(h[0]):
			_place_mesh(_named[h[0]], h[1], 0.0)
	_build_multimeshes()
	_add_boxes()
	await get_tree().process_frame
	_report("wood=%s season=%s tiles=%d" % [wood, season, COLS * ROWS])

	_rig.center_on(ORIGIN + Vector2i(3, 2))
	var tag: String = "%s_%s_%s" % [wood, season, look_name]
	for z: Array in [["min", IsoCameraRig.MIN_ZOOM], ["max", IsoCameraRig.MAX_ZOOM]]:
		_set_fade(false)
		await _shoot(z[1], "%s/%s_%s_nofade.png" % [out, tag, z[0]])
		_set_fade(true)  # камера вже на цьому зумі після попереднього кадру
		await _shoot(z[1], "%s/%s_%s_fade.png" % [out, tag, z[0]])
	_set_fade(false)
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
	# Світло, тінь, дощ і тон листя ставить сам WeatherRig бойового екрана за виглядом карти.
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
	_scatter(Rect2i(-1, -1, board.width + 2, board.height + 2),
			func(p: Vector2) -> String: return "pine" if p.x < half else wood)
	_build_multimeshes()
	await get_tree().process_frame
	_report("map=%s season=%s forest_cells=%d" % [look_name, season, _forest.size()])
	var shots: Array = []
	var seen: Dictionary = {}
	# Кадри над кількома скупченнями лісу: перший — центр мас, далі — кутові клітинки лісу.
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
	for path: String in ["res://assets/props/forest/forest_conifer.glb", "res://assets/props/forest/forest_broadleaf_%s.glb" % season]:
		var root: Node = (load(path) as PackedScene).instantiate()
		for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
			var prefix: String = String(mi.name).get_slice("_", 0)
			_named[String(mi.name)] = mi.mesh
			if not _meshes.has(prefix):
				_meshes[prefix] = []
			(_meshes[prefix] as Array).append(mi.mesh)
			var src: StandardMaterial3D = mi.mesh.surface_get_material(0) as StandardMaterial3D
			var m := ShaderMaterial.new()
			m.shader = shader
			m.set_shader_parameter("albedo_tex", src.albedo_texture)
			m.set_shader_parameter("alpha_cutoff", src.alpha_scissor_threshold)
			_material[mi.mesh] = m
		root.free()


## Глибина в лісі (тайли): усередині — відстань до найближчої клітинки без лісу,
## назовні — мінус відстань до найближчої клітинки лісу.
func _depth(p: Vector2) -> float:
	var c := Vector2i(floori(p.x + 0.5), floori(p.y + 0.5))
	var inside: bool = _forest.has(c)
	var best: float = 99.0
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			var n := c + Vector2i(dx, dy)
			if _forest.has(n) == inside:
				continue
			var lo := Vector2(n) - Vector2(0.5, 0.5)
			best = minf(best, p.distance_to(p.clamp(lo, lo + Vector2.ONE)))
	return best if inside else -best


func _pick(weights: Dictionary) -> String:
	var r: float = _rng.randf()
	var acc: float = 0.0
	for k: String in weights:
		acc += weights[k]
		if r <= acc and (_meshes.has(k) or _named.has(k)):
			return k
	for k: String in weights:
		if _meshes.has(k) or _named.has(k):
			return k
	return _meshes.keys()[0]


## wood_at(p) -> склад лісу в точці: на карті два боки мають різний характер.
func _scatter(area: Rect2i, wood_at: Callable) -> void:
	var canopy := func(d: float) -> bool: return d > CANOPY_FROM
	var edge := func(d: float) -> bool: return d > EDGE_FROM and d <= EDGE_TO
	var shrub := func(d: float) -> bool: return d > -0.15 and d <= SHRUB_BAND
	var logs := func(d: float) -> bool: return d > 0.3
	_layer(area, 2.4, canopy, func(p: Vector2) -> Dictionary: return WOODS[wood_at.call(p)]["canopy"], CANOPY_H,
			func(p: Vector2) -> float: return float(WOODS[wood_at.call(p)]["density"]))
	_layer(area, EDGE_DENSITY, edge, func(p: Vector2) -> Dictionary: return WOODS[wood_at.call(p)]["edge"], EDGE_H)
	_layer(area, SHRUB_DENSITY, shrub, func(p: Vector2) -> Dictionary: return WOODS[wood_at.call(p)]["belt"], SHRUB_H)
	if _meshes.has("Log"):
		_layer(area, LOG_DENSITY, logs, func(_p: Vector2) -> Dictionary: return {"Log": 1.0}, Vector2.ZERO)


## Сітка з кроком 1/√густини; density_at (якщо є) проріджує точки до місцевої густини.
func _layer(area: Rect2i, density: float, band: Callable, species_at: Callable, heights: Vector2, density_at: Callable = Callable()) -> void:
	var step: float = 1.0 / sqrt(density)
	var y: float = area.position.y
	while y < area.end.y:
		var x: float = area.position.x
		while x < area.end.x:
			var p := Vector2(x, y) + Vector2(_rng.randf_range(-JITTER, JITTER), _rng.randf_range(-JITTER, JITTER)) * step
			var d: float = _depth(p) + _noise.get_noise_2d(p.x, p.y) * EDGE_NOISE
			var keep: bool = density_at.is_null() or _rng.randf() < float(density_at.call(p)) / density
			if band.call(d) and keep:
				var k: String = _pick(species_at.call(p))
				var mesh: Mesh = _named[k] if _named.has(k) else (_meshes[k] as Array)[_rng.randi() % (_meshes[k] as Array).size()]
				_place_mesh(mesh, p, _rng.randf_range(heights.x, heights.y))
			x += step
		y += step


## height_m = 0 — справжній розмір меша.
func _place_mesh(mesh: Mesh, p: Vector2, height_m: float) -> void:
	var aabb: AABB = mesh.get_aabb()
	var s: float = height_m / TILE_M / aabb.end.y if height_m > 0.0 else 1.0
	# Висоту задає розкидка, а ширину крони — ні: низьке джерело, витягнуте до 25 м, дало
	# б крону на пів тайла ширшу за справжню, і намет злився б у суцільну плиту.
	# Молоде дерево (поясу кущів чи крайового ряду) не тримає ширини дорослої крони.
	var w: float = clampf(s, minf(CROWN_W.x, s * 1.8), CROWN_W.y) * _rng.randf_range(0.9, 1.1)
	var basis := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(w, s, w))
	var xf := Transform3D(basis, _offset + Vector3(p.x, 0.0, p.y))
	if not _groups.has(mesh):
		_groups[mesh] = []
	var half: float = maxf(maxf(-aabb.position.x, aabb.end.x), maxf(-aabb.position.z, aabb.end.z))
	# AABB меша — центри карток; пучки виходять за нього ще на ~1,2 м угору й убік.
	(_groups[mesh] as Array).append({"xf": xf, "top": aabb.end.y * s + 0.15, "pos": p, "r": half * w + 0.15})


func _build_multimeshes() -> void:
	for mesh: Mesh in _groups:
		var list: Array = _groups[mesh]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i]["xf"])
			mm.set_instance_color(i, Color.WHITE)
		var node := MultiMeshInstance3D.new()
		node.multimesh = mm
		node.material_override = _material[mesh]
		# Картки розгортаються в шейдері, тож AABB меша не містить країв пучків.
		node.extra_cull_margin = 0.4
		_root.add_child(node)
		_mmi[mesh] = node


func _set_fade(on: bool) -> void:
	var cam: Camera3D = _rig.find_children("*", "Camera3D", true, false)[0] as Camera3D
	for mesh: Mesh in _groups:
		var list: Array = _groups[mesh]
		var mm: MultiMesh = (_mmi[mesh] as MultiMeshInstance3D).multimesh
		for i in list.size():
			var a: float = 1.0
			if on:
				for u: Vector2 in _units:
					# Промінь від юніта до камери (перспектива: не середній кут камери, а
					# справжній до цієї точки). Крона заввишки top ховає юніта, стоячи до
					# top · (гориз. відстань / висота камери) ближче до камери вздовж цього променя.
					var to_cam: Vector3 = cam.global_position - (_offset + Vector3(u.x, 0.0, u.y))
					var flat := Vector2(to_cam.x, to_cam.z)
					var reach: float = float(list[i]["top"]) * flat.length() / to_cam.y
					var dir: Vector2 = flat.normalized()
					var p: Vector2 = list[i]["pos"]
					var t: float = clampf((p - u).dot(dir), 0.0, reach)
					var dist: float = p.distance_to(u + dir * t)
					# Відстань рахується від осі стовбура, тож радіус крони додається: інакше край
					# крони сусіднього дерева лишається над юнітом.
					var r0: float = FADE_RADIUS + float(list[i]["r"])
					a = minf(a, smoothstep(r0, r0 + FADE_SOFT, dist))
			mm.set_instance_color(i, Color(1, 1, 1, a))


func _add_boxes() -> void:
	var tank := MeshInstance3D.new()
	var tb := BoxMesh.new()
	tb.size = Vector3(0.45, 0.3, 0.9)
	tank.mesh = tb
	tank.material_override = _flat(Color(0.75, 0.2, 0.15))
	tank.position = _offset + Vector3(_units[0].x, 0.15, _units[0].y)
	add_child(tank)
	var squad := MeshInstance3D.new()
	var sb := BoxMesh.new()
	sb.size = Vector3(0.35, 0.2, 0.35)
	squad.mesh = sb
	squad.material_override = _flat(Color(0.95, 0.85, 0.1))
	squad.position = _offset + Vector3(_units[1].x, 0.1, _units[1].y)
	add_child(squad)


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
	print("SCATTER %s instances=%d tris=%d multimeshes=%d" % [what, inst, tris, _groups.size()])


func _shoot(zoom: float, path: String) -> void:
	_rig.zoom_by(zoom / _rig.zoom_level)
	for i in 60:
		await get_tree().process_frame
	var calls: int = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var img: Image = get_viewport().get_texture().get_image()
	if img.save_png(path) != OK:
		push_error("PNG не збережено: %s" % path)
	print("SHOT %s draw_calls=%d" % [path, calls])


func _triangles(mesh: Mesh) -> int:
	var t: int = 0
	for s in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(s)
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		t += (idx.size() if not idx.is_empty() else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return t
