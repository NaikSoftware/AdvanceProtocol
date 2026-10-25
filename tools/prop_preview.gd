extends Node
## Знімає кожен GLB з assets/props камерою гри на тайлі поля: <name>.png на мінімальному
## зумі (найближче) і <name>_far.png на максимальному (де об'єкт ~100 px).
## Єдине освітлення для всіх наборів: м'яке холодне похмуре світло, приглушена волога сіра земля.
## Запуск (потрібне вікно, не --headless):
##   $GODOT --path . res://tools/prop_preview.tscn -- [out_dir] [--graze] [--back] [--river] [--side] [--tank] [--dir=res://...] [name ...]
## Без out_dir знімки лягають у user://prop_preview. Без імен знімається все з теки (за замовчуванням assets/props).
##   --graze  додає <name>_graze.png: низьке бічне сонце, щоб побачити рельєф карти нормалей;
##   --back   додає <name>_back.png: об'єкт, повернутий на 180°, щоб побачити протилежний фасад;
##   --river  ґрунт із текстури River (мокрий мул) замість сірої площини; файли отримують суфікс _river;
##   --side   додає <name>_side.png: ортографічний вид збоку для перевірки кутів балок і висот;
##   --tank   ставить поруч коробку розміром із танк для масштабу (збоку, щоб не закривати малий об'єкт).

var props_dir: String = "res://assets/props"
var graze: bool = false
var back: bool = false
var river: bool = false
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

	for n in names:
		var scene: PackedScene = load("%s/%s.glb" % [props_dir, n]) as PackedScene
		if scene == null:
			push_error("prop_preview: нема %s" % n)
			continue
		var inst: Node3D = scene.instantiate()
		inst.position = Vector3(cell.x, 0.0, cell.y)
		add_child(inst)
		if tank:
			var box := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.75, 0.5, 0.9)
			box.mesh = bm
			var tm := StandardMaterial3D.new()
			tm.albedo_color = Color(0.32, 0.36, 0.30)
			box.material_override = tm
			box.position = Vector3(2.6, 0.25, 1.6)
			inst.add_child(box)
		print("PROP %s tris=%d" % [n, _triangles(inst)])
		rig.center_on(cell)
		await _shoot(rig, IsoCameraRig.MIN_ZOOM, "%s/%s%s.png" % [out, n, "_river" if river else ""])
		await _shoot(rig, IsoCameraRig.MAX_ZOOM, "%s/%s_far%s.png" % [out, n, "_river" if river else ""])
		if graze:
			sun.rotation_degrees = Vector3(-14.0, -70.0, 0.0)
			sun.light_energy = 1.6
			await _shoot(rig, IsoCameraRig.MIN_ZOOM, "%s/%s_graze%s.png" % [out, n, "_river" if river else ""])
			sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
			sun.light_energy = 0.9
		if back:
			inst.rotation.y = PI
			await _shoot(rig, IsoCameraRig.MIN_ZOOM, "%s/%s_back%s.png" % [out, n, "_river" if river else ""])
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
