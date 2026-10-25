extends Node
## Ліс 6×5 тайлів з окремих крон бібліотеки, розкиданих так, як їх розкидатиме дошка:
## пояс кущів по краю, нижчі крайові дерева, далі повний намет. Усередині — коробка танка
## й коробка відділення. Знімає мінімальний і максимальний зум, без розчинення й із ним.
## Запуск (потрібне вікно, не --headless):
##   $GODOT --path . res://tools/forest_scatter_preview.tscn -- <тека> <ліс> <сезон> <світло>
## ліс: pine | mixed | deciduous; сезон: late | summer | early; світло: overcast | sun.
##
## Правила розкидання (їх і переносить дошка):
## - Глибина точки `depth` — відстань у тайлах до найближчої клітинки без лісу, плюс шум
##   ±`EDGE_NOISE` з довжиною хвилі ~1,5 тайла: край не йде по межах клітинок.
## - Пояс кущів: `depth` 0–`SHRUB_BAND`, густина `SHRUB_DENSITY` на тайл; дрібна частка
##   кущів виходить на 0,15 тайла в поле.
## - Крайові дерева: `depth` `EDGE_FROM`–`EDGE_TO`, висота 8–15 м.
## - Намет: `depth` > `CANOPY_FROM`, висота 18–25 м; хвойні 2–3 на тайл, листяні 1–2.
## - Усі точки — сітка з кроком 1/√густини, зсунута на ±`JITTER` кроку; поворот довільний.
## - Масштаб: висоту задає шар, ширина крони — той самий множник, обмежений `CROWN_W`,
##   ще ±10 %.
## - Розчинення: екземпляр, що стоїть ближче за `FADE_RADIUS` до відрізка від юніта до
##   точки, над якою його крона перекриває юніта для камери, отримує альфу `FADE_ALPHA`
##   у кольорі екземпляра (растр у шейдері), з м'яким переходом ще на `FADE_SOFT`.

const WINDOW: Vector2i = Vector2i(1600, 900)
const TILE_M: float = 8.0
const COLS: int = 6
const ROWS: int = 5
const ORIGIN: Vector2i = Vector2i(3, 3)
const SEED: int = 7

const EDGE_NOISE: float = 0.3
const SHRUB_BAND: float = 0.45
const SHRUB_DENSITY: float = 5.0
const EDGE_FROM: float = 0.25
const EDGE_TO: float = 0.8
const EDGE_DENSITY: float = 2.2
const CANOPY_FROM: float = 0.65
const JITTER: float = 0.4
const FADE_RADIUS: float = 0.6
const FADE_SOFT: float = 0.25
const FADE_ALPHA: float = 0.3

## Склад лісу: частки видів у наметі й у крайовому ряду; густина намету на тайл.
const WOODS: Dictionary = {
	"pine": {"canopy": {"Pine": 0.85, "Spruce": 0.1, "Birch": 0.05}, "edge": {"Pine": 0.45, "Spruce": 0.25, "Birch": 0.3}, "density": 2.4},
	"mixed": {"canopy": {"Pine": 0.45, "Spruce": 0.2, "Birch": 0.2, "Oak": 0.15}, "edge": {"Birch": 0.45, "Spruce": 0.25, "Oak": 0.3}, "density": 2.2},
	"deciduous": {"canopy": {"Oak": 0.6, "Birch": 0.3, "Spruce": 0.1}, "edge": {"Birch": 0.5, "Oak": 0.3, "Spruce": 0.2}, "density": 1.5},
}
## Межі масштабу ширини крони відносно меша: ширина росте з висотою лише до цих меж.
const CROWN_W: Vector2 = Vector2(0.75, 1.1)
## Поодинокі дерева: ряд у полі ліворуч від лісу, окремий кадр.
const HEROES: Array = [["Hero_Oak", Vector2(9.5, 1.0)], ["Hero_Lime", Vector2(12.0, 2.5)],
		["Hero_Birch", Vector2(9.8, 3.8)], ["Hero_Poplar", Vector2(11.2, 5.2)], ["Hero_Poplar", Vector2(12.1, 5.6)]]
## Повалені стовбури на тайл усередині лісу; розмір не масштабується (Vector2.ZERO).
const LOG_DENSITY: float = 0.25
const CANOPY_H: Vector2 = Vector2(18.0, 25.0)
const EDGE_H: Vector2 = Vector2(8.0, 15.0)
const SHRUB_H: Vector2 = Vector2(2.0, 5.0)

var _rig: IsoCameraRig
var _rng := RandomNumberGenerator.new()
var _noise := FastNoiseLite.new()
var _meshes: Dictionary = {}  ## префікс виду -> Array[Mesh]
var _named: Dictionary = {}  ## ім'я вузла -> Mesh
var _material: Dictionary = {}  ## Mesh -> ShaderMaterial
var _groups: Dictionary = {}  ## Mesh -> Array[Dictionary] {xf, top_t, base_t}
var _mmi: Dictionary = {}  ## Mesh -> MultiMeshInstance3D
var _units: Array[Vector2] = [Vector2(2.0, 2.0), Vector2(4.0, 2.0)]


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var out: String = args[0]
	var wood: String = args[1] if args.size() > 1 else "mixed"
	var season: String = args[2] if args.size() > 2 else "late"
	var light: String = args[3] if args.size() > 3 else "overcast"
	DirAccess.make_dir_recursive_absolute(out)
	get_window().size = WINDOW
	_rng.seed = SEED
	_noise.seed = SEED
	_noise.frequency = 1.0 / 1.5

	_rig = (load("res://game/camera/iso_camera_rig.tscn") as PackedScene).instantiate()
	add_child(_rig)
	_rig.set_bounds(Vector2i(18, 14))
	_lights(light)
	_ground()
	_load_library(season)
	_scatter(WOODS[wood])
	_build_multimeshes()
	_add_boxes()
	await get_tree().process_frame

	var tris: int = 0
	var inst: int = 0
	for m: Mesh in _groups:
		tris += _triangles(m) * (_groups[m] as Array).size()
		inst += (_groups[m] as Array).size()
	print("SCATTER wood=%s season=%s instances=%d tris=%d multimeshes=%d tiles=%d" % [wood, season, inst, tris, _groups.size(), COLS * ROWS])

	_rig.center_on(ORIGIN + Vector2i(3, 2))
	var tag: String = "%s_%s_%s" % [wood, season, light]
	for z: Array in [["min", IsoCameraRig.MIN_ZOOM], ["max", IsoCameraRig.MAX_ZOOM]]:
		_set_fade(false, z[1])
		await _shoot(z[1], "%s/%s_%s_nofade.png" % [out, tag, z[0]])
		_set_fade(true, z[1])
		await _shoot(z[1], "%s/%s_%s_fade.png" % [out, tag, z[0]])
	_set_fade(false, IsoCameraRig.MIN_ZOOM)
	_rig.center_on(ORIGIN + Vector2i(10, 2))
	await _shoot(IsoCameraRig.MIN_ZOOM, "%s/heroes_%s_%s_min.png" % [out, season, light])
	get_tree().quit()


func _lights(kind: String) -> void:
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	add_child(sun)
	var env_node: WorldEnvironment = (load("res://game/battle/sky_rig.gd") as GDScript).new()
	add_child(env_node)
	if kind == "sun":
		# Тепле літнє сонце низько, синюватий розсіяний.
		sun.rotation_degrees = Vector3(-32.0, -60.0, 0.0)
		sun.light_color = Color(1.0, 0.9, 0.74)
		sun.light_energy = 1.5
		env_node.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env_node.environment.ambient_light_color = Color(0.55, 0.62, 0.75)
		env_node.environment.ambient_light_energy = 0.55
	else:
		# Те саме світло, що в battle_screen.tscn: напрям від камери гри, енергія 1.
		sun.transform = Transform3D(Basis(Vector3(0.7, 0, -0.7), Vector3(-0.5, 0.7, -0.5), Vector3(0.5, 0.7, 0.5)), Vector3(0, 10, 0))
		sun.light_energy = 1.0


func _ground() -> void:
	var field := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(46, 34)
	field.mesh = plane
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.29, 0.30, 0.22)  # приглушена трава, L* ≈ 31
	fm.roughness = 1.0
	field.material_override = fm
	field.position = Vector3(ORIGIN.x + 6.0, 0, ORIGIN.y + 2.0)
	add_child(field)


func _load_library(season: String) -> void:
	var shader: Shader = load("res://assets/props/forest/forest_crown.gdshader")
	for path: String in ["res://assets/props/forest/forest_conifer.glb", "res://assets/props/forest/forest_broadleaf_%s.glb" % season]:
		if not ResourceLoader.exists(path):
			push_warning("нема %s" % path)
			continue
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
	print("LIBRARY ", _meshes.keys())


func _is_forest(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < COLS and c.y < ROWS


## Глибина в лісі (тайли): усередині — відстань до найближчої клітинки без лісу,
## назовні — мінус відстань до найближчої клітинки лісу.
func _depth(p: Vector2) -> float:
	var c := Vector2i(floori(p.x + 0.5), floori(p.y + 0.5))
	var inside: bool = _is_forest(c)
	var best: float = 99.0
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			var n := c + Vector2i(dx, dy)
			if _is_forest(n) == inside:
				continue
			var lo := Vector2(n) - Vector2(0.5, 0.5)
			best = minf(best, p.distance_to(p.clamp(lo, lo + Vector2.ONE)))
	return best if inside else -best


func _pick(weights: Dictionary) -> String:
	var r: float = _rng.randf()
	var acc: float = 0.0
	for k: String in weights:
		acc += weights[k]
		if r <= acc and _meshes.has(k):
			return k
	for k: String in weights:
		if _meshes.has(k):
			return k
	return _meshes.keys()[0]


func _scatter(wood: Dictionary) -> void:
	_layer(wood["density"], func(d: float) -> bool: return d > CANOPY_FROM, wood["canopy"], CANOPY_H)
	_layer(EDGE_DENSITY, func(d: float) -> bool: return d > EDGE_FROM and d <= EDGE_TO, wood["edge"], EDGE_H)
	var shrub: String = "Shrub" if _meshes.has("Shrub") else "Pine"
	_layer(SHRUB_DENSITY, func(d: float) -> bool: return d > -0.15 and d <= SHRUB_BAND, {shrub: 1.0}, SHRUB_H)
	if _meshes.has("Log"):
		_layer(LOG_DENSITY, func(d: float) -> bool: return d > 0.3, {"Log": 1.0}, Vector2.ZERO)
	# Поодинокі дерева в полі біля лісу: так їх ставитиме дошка вздовж доріг і в хуторах.
	for h: Array in HEROES:
		if _named.has(h[0]):
			_place_mesh(_named[h[0]], h[1], 0.0)


func _layer(density: float, band: Callable, species: Dictionary, heights: Vector2) -> void:
	var step: float = 1.0 / sqrt(density)
	var y: float = -1.0
	while y < ROWS + 1.0:
		var x: float = -1.0
		while x < COLS + 1.0:
			var p := Vector2(x, y) + Vector2(_rng.randf_range(-JITTER, JITTER), _rng.randf_range(-JITTER, JITTER)) * step
			var d: float = _depth(p) + _noise.get_noise_2d(p.x, p.y) * EDGE_NOISE
			if band.call(d):
				_place(_pick(species), p, _rng.randf_range(heights.x, heights.y))
			x += step
		y += step


func _place(prefix: String, p: Vector2, height_m: float) -> void:
	var variants: Array = _meshes[prefix]
	_place_mesh(variants[_rng.randi() % variants.size()], p, height_m)


## height_m = 0 — справжній розмір меша.
func _place_mesh(mesh: Mesh, p: Vector2, height_m: float) -> void:
	var aabb: AABB = mesh.get_aabb()
	var s: float = height_m / TILE_M / aabb.end.y if height_m > 0.0 else 1.0
	# Висоту задає розкидка, а ширину крони — ні: низьке джерело, витягнуте до 25 м, дало
	# б крону на пів тайла ширшу за справжню, і намет злився б у суцільну плиту.
	var w: float = clampf(s, CROWN_W.x, CROWN_W.y) * _rng.randf_range(0.9, 1.1)
	var basis := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(w, s, w))
	var xf := Transform3D(basis, Vector3(ORIGIN.x + p.x, 0.0, ORIGIN.y + p.y))
	if not _groups.has(mesh):
		_groups[mesh] = []
	(_groups[mesh] as Array).append({"xf": xf, "top": aabb.end.y * s, "pos": p})


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
		add_child(node)
		_mmi[mesh] = node


func _set_fade(on: bool, zoom: float) -> void:
	# Напрям від юніта до камери по землі: крона, що ховає юніта, стоїть з цього боку.
	var cam: Camera3D = _rig.find_children("*", "Camera3D", true, false)[0] as Camera3D
	var f3: Vector3 = cam.global_basis.z
	var cam_dir := Vector2(f3.x, f3.z).normalized()
	var tan_p: float = tan(deg_to_rad(_rig.pitch_for(zoom)))
	for mesh: Mesh in _groups:
		var list: Array = _groups[mesh]
		var mm: MultiMesh = (_mmi[mesh] as MultiMeshInstance3D).multimesh
		for i in list.size():
			var a: float = 1.0
			if on:
				for u: Vector2 in _units:
					# Крона заввишки top перекриває юніта, стоячи до 'top / tan(pitch)' ближче до камери.
					var reach: float = float(list[i]["top"]) / tan_p
					var p: Vector2 = list[i]["pos"]
					var t: float = clampf((p - u).dot(cam_dir), 0.0, reach)
					var dist: float = p.distance_to(u + cam_dir * t)
					var k: float = smoothstep(FADE_RADIUS, FADE_RADIUS + FADE_SOFT, dist)
					a = minf(a, lerpf(FADE_ALPHA, 1.0, k))
			mm.set_instance_color(i, Color(1, 1, 1, a))


func _add_boxes() -> void:
	var tank := MeshInstance3D.new()
	var tb := BoxMesh.new()
	tb.size = Vector3(0.45, 0.3, 0.9)
	tank.mesh = tb
	tank.material_override = _flat(Color(0.75, 0.2, 0.15))
	tank.position = Vector3(ORIGIN.x + _units[0].x, 0.15, ORIGIN.y + _units[0].y)
	add_child(tank)
	var squad := MeshInstance3D.new()
	var sb := BoxMesh.new()
	sb.size = Vector3(0.35, 0.2, 0.35)
	squad.mesh = sb
	squad.material_override = _flat(Color(0.95, 0.85, 0.1))
	squad.position = Vector3(ORIGIN.x + _units[1].x, 0.1, ORIGIN.y + _units[1].y)
	add_child(squad)


func _flat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m


func _shoot(zoom: float, path: String) -> void:
	_rig.zoom_by(zoom / _rig.zoom_level)
	for i in 60:
		await get_tree().process_frame
	var calls: int = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var prims: int = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var img: Image = get_viewport().get_texture().get_image()
	if img.save_png(path) != OK:
		push_error("PNG не збережено: %s" % path)
	print("SHOT %s draw_calls=%d primitives=%d" % [path, calls, prims])


func _triangles(mesh: Mesh) -> int:
	var t: int = 0
	for s in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(s)
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		t += (idx.size() if not idx.is_empty() else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return t
