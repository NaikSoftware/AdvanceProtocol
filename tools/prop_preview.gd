extends Node
## Знімає кожен GLB з assets/props камерою гри на тайлі поля: <name>.png на мінімальному
## зумі (найближче) і <name>_far.png на максимальному (де об'єкт ~100 px).
## Єдине освітлення для всіх наборів: м'яке холодне похмуре світло, приглушена волога сіра земля.
## Запуск (потрібне вікно, не --headless):
##   $GODOT --path . res://tools/prop_preview.tscn -- [out_dir] [--graze] [--back] [--river] [--rl] [--black] [--side] [--tank] [--dir=res://...] [name ...]
## Без out_dir знімки лягають у user://prop_preview. Без імен знімається все з теки (за замовчуванням assets/props).
##   --graze  додає <name>_graze.png: низьке бічне сонце, щоб побачити рельєф карти нормалей;
##   --back   додає <name>_back.png: об'єкт, повернутий на 180°, щоб побачити протилежний фасад;
##   --rl     вигляд карти Річка з гри (BattleLook): розсіяне похмуре світло з дальнього боку, сильне небо, мокрий ґрунт; суфікс _rl;
##   --cr     вигляд карти Перехрестя (BattleLook): сонце пізнього літа; суфікс _cr;
##   --z2=N   зум другого кадру (_far) замість MAX_ZOOM;
##   --with=N  поруч (за 1,6 тайла) ставить ще модель N — наприклад, хату біля паркану для масштабу й тону;
##   --road=L:D  біля кожного кінця моста — смуга дороги з макротекстури землі L (road | dirt) на висоті настилу D (тайли),
##               щоб бачити стик настилу з дорогою;
##   --black  чорний ґрунт без відблисків: у кадрі лишається лише сам об'єкт, тож його середній тон міряється без тла; файли отримують суфікс _black;
##   --river  ґрунт із текстури River (мокрий мул) замість сірої площини; файли отримують суфікс _river;
##   --side   додає <name>_side.png: ортографічний вид збоку для перевірки кутів балок і висот;
##   --tank   ставить поруч коробку розміром із танк для масштабу (збоку, щоб не закривати малий об'єкт).

var props_dir: String = "res://assets/props"
var graze: bool = false
var back: bool = false
var river: bool = false
var black: bool = false
var rl: bool = false
var sfx: String = ""
var look_path: String = ""
var zoom2: float = IsoCameraRig.MAX_ZOOM
var road_layer: String = ""
var with_model: String = ""
var road_deck: float = 0.0
## Метрів на повтор макротекстури дороги й множник сухого покриття (як у GroundSurface і ground.gdshader).
const ROAD_M: Dictionary = {"road": 30.0, "dirt": 20.0}
const ROAD_K: Dictionary = {"road": 0.75, "dirt": 1.0}
var side: bool = false
const WINDOW: Vector2i = Vector2i(1280, 720)
## Ширина смуги поля під об'єктом: мосту потрібна довжина з запасом, дому — тайл навколо.
const FIELD_HALF: float = 6.0

func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var out: String = "user://prop_preview"
	var names: PackedStringArray = PackedStringArray()
	var tank: bool = false
	for i in args.size():
		if args[i] == "--graze":
			graze = true
		elif args[i] == "--back":
			back = true
		elif args[i] == "--river":
			river = true
		elif args[i] == "--black":
			black = true
		elif args[i] == "--cr":
			look_path = "res://maps/crossroads.tres"
		elif args[i].begins_with("--with="):
			with_model = args[i].substr(7)
		elif args[i].begins_with("--road="):
			var parts: PackedStringArray = args[i].substr(7).split(":")
			road_layer = parts[0]
			road_deck = float(parts[1])
		elif args[i].begins_with("--z2="):
			zoom2 = float(args[i].substr(5))
		elif args[i] == "--rl":
			rl = true
			river = true
		elif args[i] == "--side":
			side = true
		elif args[i] == "--tank":
			tank = true
		elif args[i].begins_with("--dir="):
			props_dir = args[i].substr(6)
		elif i == 0 and (args[i].begins_with("/") or args[i].begins_with("user://")):
			out = args[i]
		else:
			names.append(args[i])
	sfx = ("_cr" if look_path != "" else "") + ("_rl" if rl else ("_river" if river else "")) + ("_black" if black else "")
	if names.is_empty():
		for f in DirAccess.get_files_at(props_dir):
			if f.ends_with(".glb"):
				names.append(f.get_basename())
		names.sort()
	DirAccess.make_dir_recursive_absolute(out)
	get_window().size = WINDOW

	var cell := Vector2i(6, 6)
	var rig: IsoCameraRig = (load("res://game/camera/iso_camera_rig.tscn") as PackedScene).instantiate()
	add_child(rig)
	rig.set_bounds(Vector2i(12, 12))

	var field := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(FIELD_HALF * 2.0, FIELD_HALF * 2.0)
	field.mesh = plane
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.30, 0.32, 0.30)
	fm.roughness = 1.0
	if river:
		# ґрунт River: волога розмита ріллі-мул з текстури гри, нижча яскравість, блиск мокрого
		fm.albedo_texture = load("res://assets/terrain/field_albedo.png") as Texture2D
		fm.normal_enabled = true
		fm.normal_texture = load("res://assets/terrain/field_normal.png") as Texture2D
		fm.uv1_scale = Vector3(5.0, 5.0, 1.0)
		fm.albedo_color = Color(0.62, 0.64, 0.62)
		fm.roughness = 0.45
	if black:
		fm.albedo_color = Color(0.0, 0.0, 0.0)
		fm.metallic_specular = 0.0
	if rl:
		fm.albedo_color = Color(0.26, 0.27, 0.26)
		fm.roughness = 0.42
	field.material_override = fm
	field.position = Vector3(cell.x, 0.0, cell.y)
	add_child(field)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	sun.light_color = Color(0.86, 0.91, 1.0)
	sun.light_energy = 0.9
	sun.light_angular_distance = 2.5
	sun.shadow_blur = 2.5
	sun.shadow_enabled = true
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.42, 0.45, 0.48)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.62, 0.66, 0.72)
	env.environment.ambient_light_energy = 0.8
	add_child(env)
	if rl and look_path == "":
		look_path = "res://maps/river.tres"
	if look_path != "":
		var look: BattleLook = BattleLook.for_map_path(look_path)
		sun.light_color = look.light_color
		sun.light_energy = look.light_energy
		sun.rotation_degrees = Vector3(-look.light_pitch_deg, look.light_yaw_deg, 0.0)
		sun.shadow_opacity = look.shadow_opacity
		sun.shadow_blur = look.shadow_blur
		env.environment.ambient_light_color = look.ambient_color
		env.environment.ambient_light_energy = look.ambient_energy
		env.environment.background_color = Color(0.40, 0.44, 0.48)

	for n in names:
		var scene: PackedScene = load("%s/%s.glb" % [props_dir, n]) as PackedScene
		if scene == null:
			push_error("prop_preview: нема %s" % n)
			continue
		var inst: Node3D = scene.instantiate()
		inst.position = Vector3(cell.x, 0.0, cell.y)
		add_child(inst)
		if road_layer != "":
			_road_ends(inst)
		var other: Node3D = null
		if with_model != "":
			var path: String = "%s/%s.glb" % [props_dir, with_model]
			if ResourceLoader.exists(path):
				other = (load(path) as PackedScene).instantiate()
				other.position = Vector3(1.6, 0.0, -0.6)
				add_child(other)
				other.global_position = inst.global_position + Vector3(1.6, 0.0, -0.6)
			else:
				push_error("prop_preview: --with=%s не знайдено" % with_model)
		if rl:
			# мокрий реквізит із гри: матеріал-накладка зменшує шорсткість, тож дахи й стіни дають мокрий блиск
			for mi: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
				for si: int in mi.mesh.get_surface_count():
					var wm: StandardMaterial3D = mi.get_active_material(si) as StandardMaterial3D
					if wm != null:
						var wet: StandardMaterial3D = wm.duplicate() as StandardMaterial3D
						wet.roughness = 0.4
						wet.metallic_specular = 0.12
						mi.set_surface_override_material(si, wet)
		if tank:
			var box := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.45, 0.3, 0.9)                         # танк 3,6 x 2,4 x 7,2 м у тайлах по 8 м
			box.mesh = bm
			var tm := StandardMaterial3D.new()
			tm.albedo_color = Color(0.32, 0.36, 0.30)
			box.material_override = tm
			var ex: float = 0.0                                         # коробка стоїть за найдальшим краєм моделі по +X, а не поверх неї
			for mi: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
				ex = maxf(ex, (mi.global_transform * mi.get_aabb()).end.x - inst.global_position.x)
			box.position = Vector3(maxf(1.2, ex + 0.45), 0.15, 0.0)
			inst.add_child(box)
		print("PROP %s tris=%d" % [n, _triangles(inst)])
		rig.center_on(cell)
		await _shoot(rig, IsoCameraRig.MIN_ZOOM, "%s/%s%s.png" % [out, n, sfx])
		await _shoot(rig, zoom2, "%s/%s_far%s.png" % [out, n, sfx])
		if graze:
			var rot0: Vector3 = sun.rotation_degrees
			var e0: float = sun.light_energy
			sun.rotation_degrees = Vector3(-14.0, -70.0, 0.0)
			sun.light_energy = 1.6
			await _shoot(rig, IsoCameraRig.MIN_ZOOM, "%s/%s_graze%s.png" % [out, n, sfx])
			# світло мапи (--rl, --cr) повертається, а не типове: інакше наступні об'єкти знімались би під чужим сонцем
			sun.rotation_degrees = rot0
			sun.light_energy = e0
		if back:
			inst.rotation.y = PI
			await _shoot(rig, IsoCameraRig.MIN_ZOOM, "%s/%s_back%s.png" % [out, n, sfx])
		if side:
			var prev: Camera3D = get_viewport().get_camera_3d()
			var cam := Camera3D.new()
			cam.projection = Camera3D.PROJECTION_ORTHOGONAL
			cam.size = 7.0
			add_child(cam)
			cam.position = Vector3(cell.x, 1.1, cell.y + 12.0)
			cam.look_at(Vector3(cell.x, 1.1, cell.y))
			cam.make_current()
			for i in 60:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png("%s/%s_side.png" % [out, n])
			if prev != null:
				prev.make_current()
			cam.queue_free()
		inst.queue_free()
		if other != null:
			other.queue_free()
	get_tree().quit()

func _shoot(rig: IsoCameraRig, zoom: float, path: String) -> void:
	rig.zoom_by(zoom / rig.zoom_level)
	for i in 90:
		await get_tree().process_frame
	var err: int = get_viewport().get_texture().get_image().save_png(path)
	if err != OK:
		push_error("prop_preview: PNG не збережено (%d)" % err)

func _triangles(root: Node) -> int:
	var t: int = 0
	for m in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (m as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			var arrays: Array = mesh.surface_get_arrays(s)
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			t += (idx.size() if not idx.is_empty() else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return t


## Дві смуги дороги вздовж осі моста (локальна Z) за його кінцями, на висоті настилу.
func _road_ends(inst: Node3D) -> void:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
		var a: AABB = mi.get_aabb()
		box = a if first else box.merge(a)
		first = false
	var w: float = box.size.x * 0.75
	var ln: float = 1.5
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/terrain/macro/%s_albedo_0.png" % road_layer)
	var k: float = pow(float(ROAD_K[road_layer]), 1.0 / 2.2)            # множник у лінійному світлі → sRGB-колір матеріалу
	m.albedo_color = Color(k, k, k)
	m.roughness = 0.9
	m.uv1_scale = Vector3(w * 8.0 / float(ROAD_M[road_layer]), ln * 8.0 / float(ROAD_M[road_layer]), 1.0)
	for sgn: float in [-1.0, 1.0]:
		var strip := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(w, ln)
		strip.mesh = pm
		strip.material_override = m
		strip.position = Vector3(box.get_center().x, road_deck + 0.002, box.get_center().z + sgn * (box.size.z * 0.5 + ln * 0.5))
		inst.add_child(strip)

