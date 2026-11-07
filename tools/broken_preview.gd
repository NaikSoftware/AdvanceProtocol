extends Node
## Знімає зламані моделі з assets/props/broken камерою гри (yaw 45°, pitch −52°, ортогональна): ліворуч — складені на місці
## шматки, праворуч — рознесені від центру, щоб видно було, як модель розпалась і чим закриті злами.
## Запуск (потрібне вікно, не --headless):
##   tools/godot_run.sh --path . res://tools/broken_preview.tscn -- <out_dir> [--size=S] [--spread=K] [name ...]
## name — ім'я файлу без _broken.glb (напр. infra_pole_wood); без імен знімається вся тека. Знімки: <name>.png.

const DIR := "res://assets/props/broken/"
const YAW := 45.0
const PITCH := -52.0

var out_dir: String = ""
var size: float = 3.0
var spread: float = 1.7
var focus: float = -1.0


func _ready() -> void:
	var names: Array[String] = []
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--size="):
			size = float(a.substr(7))
		elif a.begins_with("--focus="):
			focus = float(a.substr(8))
		elif a.begins_with("--spread="):
			spread = float(a.substr(9))
		elif out_dir.is_empty():
			out_dir = a
		else:
			names.append(a)
	if names.is_empty():
		for f: String in DirAccess.get_files_at(DIR):
			if f.ends_with("_broken.glb"):
				names.append(f.trim_suffix("_broken.glb"))
		names.sort()
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_window().size = Vector2i(1280, 720)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.52, 0.56, 0.6)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.65, 0.7)
	env.ambient_light_energy = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -30, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.27, 0.29, 0.21)
	gm.roughness = 1.0
	pm.material = gm
	add_child(ground)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = size
	add_child(cam)
	for n in names:
		await _shoot(n, cam)
	get_tree().quit()


func _shoot(n: String, cam: Camera3D) -> void:
	var scene: PackedScene = load(DIR + n + "_broken.glb")
	var root := Node3D.new()
	add_child(root)
	var a: Node3D = scene.instantiate()
	var b: Node3D = scene.instantiate()
	root.add_child(a)
	root.add_child(b)
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := Vector3(-1e9, -1e9, -1e9)
	for c in b.get_children():
		var mi := c as MeshInstance3D
		var bb: AABB = mi.get_aabb()
		bb.position += mi.position
		lo = lo.min(bb.position)
		hi = hi.max(bb.end)
	var mid := (lo + hi) / 2.0
	var w := maxf(hi.x - lo.x, hi.z - lo.z) + 0.3
	a.position = Vector3(-w * 0.55, 0, 0)
	b.position = Vector3(w * 0.55, 0, 0)
	for c in b.get_children():
		var mi := c as MeshInstance3D
		var d := mi.position - mid
		mi.position = mid + d * spread
	cam.rotation_degrees = Vector3(PITCH, YAW, 0)
	cam.position = Vector3(0, (hi.y - lo.y) / 2.0 if focus < 0.0 else focus, 0) + cam.basis.z * 20.0
	for i in 6:
		await get_tree().process_frame
	var err := get_viewport().get_texture().get_image().save_png(out_dir.path_join(n + ".png"))
	print("SHOT ", n, " ", err)
	root.queue_free()
