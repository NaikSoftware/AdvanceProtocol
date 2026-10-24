extends Node
## Знімає кожен GLB з assets/props камерою гри на тайлі поля: <name>.png на мінімальному
## зумі (найближче) і <name>_far.png на максимальному (де об'єкт ~100 px).
## Запуск (потрібне вікно, не --headless):
##   $GODOT --path . res://tools/prop_preview.tscn -- [out_dir] [name ...]
## Без out_dir знімки лягають у user://prop_preview. Без імен знімається все з assets/props.

const PROPS_DIR: String = "res://assets/props"
const WINDOW: Vector2i = Vector2i(1280, 720)
## Ширина смуги поля під об'єктом: мосту потрібна довжина з запасом, дому — тайл навколо.
const FIELD_HALF: float = 6.0

func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var out: String = "user://prop_preview"
	var names: PackedStringArray = PackedStringArray()
	for i in args.size():
		if i == 0 and (args[i].begins_with("/") or args[i].begins_with("user://")):
			out = args[i]
		else:
			names.append(args[i])
	if names.is_empty():
		for f in DirAccess.get_files_at(PROPS_DIR):
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
	# мокра приглушена сіра трава: ґрунт River L* 24–34, майже без насиченості
	fm.albedo_color = Color(0.20, 0.23, 0.18)
	fm.roughness = 0.55
	field.material_override = fm
	field.position = Vector3(cell.x, 0.0, cell.y)
	add_child(field)

	var sun := DirectionalLight3D.new()
	# похмуре м'яке світло: слабке пряме, сильне розсіяне, тінь прозора
	sun.rotation_degrees = Vector3(-60.0, -30.0, 0.0)
	sun.light_energy = 0.55
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.55
	sun.shadow_blur = 2.5
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.44, 0.47, 0.5)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.62, 0.65, 0.68)
	env.environment.ambient_light_energy = 1.0
	add_child(env)

	for n in names:
		var scene: PackedScene = load("%s/%s.glb" % [PROPS_DIR, n]) as PackedScene
		if scene == null:
			push_error("prop_preview: нема %s" % n)
			continue
		var inst: Node3D = scene.instantiate()
		inst.position = Vector3(cell.x, 0.0, cell.y)
		add_child(inst)
		print("PROP %s tris=%d" % [n, _triangles(inst)])
		var tank := _tank_box(inst, cell)
		add_child(tank)
		rig.center_on(cell)
		await _shoot(rig, IsoCameraRig.MIN_ZOOM, "%s/%s.png" % [out, n])
		await _shoot(rig, IsoCameraRig.MAX_ZOOM, "%s/%s_far.png" % [out, n])
		inst.queue_free()
		tank.queue_free()
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

## Масштабна коробка танка 0.9 x 0.45 x 0.3 тайла поруч із об'єктом: за нею видно, чи об'єкт у масштабі.
func _tank_box(inst: Node3D, cell: Vector2i) -> MeshInstance3D:
	var right: float = 0.0
	for m in inst.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (m as MeshInstance3D).global_transform * (m as MeshInstance3D).get_aabb()
		right = maxf(right, b.end.x - cell.x)
	var box := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.45, 0.3, 0.9)
	box.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.27, 0.21)
	mat.roughness = 0.8
	box.material_override = mat
	box.position = Vector3(cell.x + right + 0.35, 0.15, cell.y)
	return box
