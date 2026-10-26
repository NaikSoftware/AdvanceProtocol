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
##   --rg     вигляд карти Хребет (BattleLook): ясна рання осінь; суфікс _ri;
##   --z2=N   зум другого кадру (_far) замість MAX_ZOOM;
##   --with=N  поруч (за 1,6 тайла) ставить ще модель N — наприклад, хату біля паркану для масштабу й тону;
##   --road=L:D  біля кожного кінця моста — смуга дороги з макротекстури землі L (road | dirt) на висоті настилу D (тайли),
##               щоб бачити стик настилу з дорогою;
##   --black  чорний ґрунт без відблисків: у кадрі лишається лише сам об'єкт, тож його середній тон міряється без тла; файли отримують суфікс _black;
##   --river  ґрунт із текстури River (мокрий мул) замість сірої площини; файли отримують суфікс _river;
##   --side   додає <name>_side.png: ортографічний вид збоку для перевірки кутів балок і висот;
##   --tank   ставить поруч коробку розміром із танк для масштабу (збоку, щоб не закривати малий об'єкт).
##   --veg    рослинність: матеріали GLB замінюються шейдерами assets/props/vegetation (veg.gdshader і
##            veg_shade.gdshader для плями затінення) з його ж атласом, MSAA 2× (alpha-to-coverage);
##            --fade=A — veg_fade_depth.gdshader з next_pass veg_fade.gdshader, альфа екземпляра A;
##            --fade-floor=F — нижня межа альфи голої крони (fade_floor);
##   --neutral  біле світло й небо, без тону листя: кольори як в атласі (для tools/veg_measure.py leaf);
##   --dissolve=A  veg.gdshader з альфою екземпляра A: крона рідшає цілими пучками;
##   --tank=X:Z  коробка-танк у цій точці (тайли від об'єкта), напр. під кроною;
##   --nodes=a,b,c  лише ці вузли бібліотеки GLB, рядком уздовж X через --gap=G тайлів (типово 0,6);
##   --water[=E]  вода в дальній половині поля, край на E тайлів від об'єктів (типово −0,1 — за ними;
##            додатне — перед ними, об'єкти стоять у мілині);
##   --beside=res://….glb:X:Z  ще один GLB поруч (зсув у тайлах), напр. хата біля дерева;
##   --tag=T  ім'я знімка замість імені GLB.

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
var veg: bool = false
var fade: float = -1.0
var dissolve: float = -1.0
var fade_floor: float = 0.0
var neutral: bool = false
var tank_at: Vector2 = Vector2(1.2, 0.0)
var only_nodes: PackedStringArray = PackedStringArray()
var gap: float = 0.6
var water: bool = false
## Край води відносно об'єктів (тайли вздовж Z): від'ємний — вода за об'єктами, додатний — перед ними, об'єкти в мілині.
var water_edge: float = -0.1
var with_path: String = ""
var with_off: Vector2 = Vector2.ZERO
var tag: String = ""
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
		elif args[i] == "--rg":
			look_path = "res://maps/ridge.tres"
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
		elif args[i] == "--veg":
			veg = true
		elif args[i].begins_with("--fade="):
			fade = float(args[i].substr(7))
		elif args[i] == "--neutral":
			neutral = true
		elif args[i].begins_with("--fade-floor="):
			fade_floor = float(args[i].substr(13))
		elif args[i].begins_with("--dissolve="):
			dissolve = float(args[i].substr(11))
		elif args[i].begins_with("--tank="):
			var tp: PackedStringArray = args[i].substr(7).split(":")
			tank_at = Vector2(float(tp[0]), float(tp[1]))
			tank = true
		elif args[i].begins_with("--nodes="):
			only_nodes = args[i].substr(8).split(",")
		elif args[i].begins_with("--gap="):
			gap = float(args[i].substr(6))
		elif args[i] == "--water":
			water = true
		elif args[i].begins_with("--water="):
			water = true
			water_edge = float(args[i].substr(8))
		elif args[i].begins_with("--beside="):
			var wp: PackedStringArray = args[i].substr(9).split(":")
			with_path = wp[0] + ":" + wp[1]
			with_off = Vector2(float(wp[2]), float(wp[3]))
		elif args[i].begins_with("--tag="):
			tag = args[i].substr(6)
		elif args[i] == "--tank":
			tank = true
		elif args[i].begins_with("--dir="):
			props_dir = args[i].substr(6)
		elif i == 0 and (args[i].begins_with("/") or args[i].begins_with("user://")):
			out = args[i]
		else:
			names.append(args[i])
	sfx = ("_" + look_path.get_file().get_basename().substr(0, 2) if look_path != "" else "") + ("_rl" if rl else ("_river" if river else "")) + ("_black" if black else "")
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
	if veg:
		get_viewport().msaa_3d = Viewport.MSAA_2X
	if water:
		# Вода: темна сіро-синя гладь у дальній половині поля, трохи над ґрунтом.
		var wmi := MeshInstance3D.new()
		var wpl := PlaneMesh.new()
		wpl.size = Vector2(FIELD_HALF * 2.0, FIELD_HALF)
		wmi.mesh = wpl
		var wmat := StandardMaterial3D.new()
		wmat.albedo_color = Color(0.10, 0.13, 0.14)
		wmat.roughness = 0.08
		wmat.metallic_specular = 0.6
		wmi.material_override = wmat
		wmi.position = Vector3(cell.x, 0.004, cell.y + water_edge - FIELD_HALF * 0.5)
		add_child(wmi)
	if with_path != "":
		var ws: Node3D = (load(with_path) as PackedScene).instantiate()
		ws.position = Vector3(cell.x + with_off.x, 0.0, cell.y + with_off.y)
		add_child(ws)

	var sun: DirectionalLight3D
	if rl and look_path == "":
		look_path = "res://maps/river.tres"
	if look_path != "":
		# світло, небо, тінь і мокрість — тим самим WeatherRig, що й бій: власний набір світла давав інші числа, ніж у грі
		var weather := WeatherRig.new()
		add_child(weather)
		weather.apply(BattleLook.for_map_path(look_path))
		weather.rain.visible = false                                       # штрихи дощу лягали б на виміряні ділянки
		sun = weather.sun
	else:
		sun = DirectionalLight3D.new()
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
	if neutral:
		sun.light_color = Color(1, 1, 1)
		sun.light_energy = 1.0
		RenderingServer.global_shader_parameter_set(&"foliage_tint", Vector3.ONE)

	for n in names:
		var scene: PackedScene = load("%s/%s.glb" % [props_dir, n]) as PackedScene
		if scene == null:
			push_error("prop_preview: нема %s" % n)
			continue
		var inst: Node3D = scene.instantiate()
		inst.position = Vector3(cell.x, 0.0, cell.y)
		add_child(inst)
		if not only_nodes.is_empty():
			_pick_nodes(inst)
		if veg:
			_veg_material(inst)
		if road_layer != "":
			_road_ends(inst)
		var other: Node3D = null
		if with_model != "":
			var path: String = "%s/%s.glb" % [props_dir, with_model]
			if ResourceLoader.exists(path):
				other = (load(path) as PackedScene).instantiate()
				add_child(other)
				other.global_position = inst.global_position + Vector3(1.6, 0.0, -0.6)
			else:
				push_error("prop_preview: --with=%s не знайдено" % with_model)
		var kind: int = int(PropLayer.spec_of(StringName(n)).get("kind", -1))
		if kind == PropLayer.Kind.STRUCTURE or kind == PropLayer.Kind.RUIN:
			_battle_material(inst)
		if tank:
			var box := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.45, 0.3, 0.9)                         # танк 3,6 x 2,4 x 7,2 м у тайлах по 8 м
			box.mesh = bm
			var tm := StandardMaterial3D.new()
			tm.albedo_color = Color(0.32, 0.36, 0.30)
			box.material_override = tm
			box.position = Vector3(tank_at.x, 0.15, tank_at.y)
			inst.add_child(box)
		print("PROP %s tris=%d" % [n, _triangles(inst)])
		rig.center_on(cell)
		var shot: String = tag if tag != "" else n
		await _shoot(rig, IsoCameraRig.MIN_ZOOM, "%s/%s%s.png" % [out, shot, sfx])
		await _shoot(rig, zoom2, "%s/%s_far%s.png" % [out, shot, sfx])
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
	# Масштаб кадру для tools/veg_measure.py: пікселів на метр біля центру (тайл = 8 м).
	var cam: Camera3D = get_viewport().get_camera_3d()
	var c := Vector3(6.0, 0.0, 6.0)
	var k: float = Vector2(get_viewport().get_texture().get_size()).x / get_viewport().get_visible_rect().size.x
	print("PXPERM %s %.2f" % [path.get_file(), cam.unproject_position(c).distance_to(cam.unproject_position(c + Vector3(1, 0, 0))) * k / 8.0])
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



## Лишає з бібліотеки лише вузли only_nodes, рядком уздовж X з проміжком gap.
func _pick_nodes(inst: Node3D) -> void:
	var k: int = 0
	for mi: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
		var i: int = only_nodes.find(String(mi.name))
		if i < 0:
			mi.queue_free()
			continue
		mi.position = Vector3((float(i) - float(only_nodes.size() - 1) * 0.5) * gap, 0.0, 0.0)
		k += 1
	if k == 0:
		push_error("prop_preview: жодного з вузлів %s" % [only_nodes])


## Ставить вузлам бібліотеки рослинності матеріали з veg_mesh(); для --fade і --dissolve —
## через MultiMesh, як на дошці (альфа розчинення йде кольором екземпляра).
func _veg_material(inst: Node3D) -> void:
	for mi: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
		if mi.is_queued_for_deletion():
			continue
		var mesh: Mesh = veg_mesh(mi.mesh, fade, fade_floor)
		if fade < 0.0 and dissolve < 0.0:
			mi.mesh = mesh
			continue
		# Альфа розчинення приходить кольором екземпляра MultiMesh, як на дошці: у veg_fade —
		# прозорість (--fade), у veg — гасіння цілими пучками (--dissolve).
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh
		mm.instance_count = 1
		mm.set_instance_transform(0, Transform3D.IDENTITY)
		mm.set_instance_color(0, Color(1, 1, 1, fade if fade >= 0.0 else dissolve))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.position = mi.position
		mi.get_parent().add_child(mmi)
		mi.visible = false


## Копія меша вузла рослинності з матеріалами гри (VegetationLayer.veg_mesh). Спільна з
## tools/veg_board_shot.gd.
static func veg_mesh(src: Mesh, p_fade: float, p_floor: float) -> Mesh:
	return VegetationLayer.veg_mesh(src, p_fade, p_floor)


## Будівлі в бою малює prop_fade (мокрість за weather_wetness, теплі стіни), а не матеріал GLB;
## параметри — ті самі, що в PropLayer._fade_material (суцільний варіант, без імли кільця).
## shortcut: копія відображення параметрів з PropLayer._fade_material; якщо там зміниться набір — оновити й тут.
func _battle_material(root: Node) -> void:
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		for si: int in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(si) as BaseMaterial3D
			if src == null:
				continue
			var mat := ShaderMaterial.new()
			mat.shader = load("res://game/battle/shaders/prop_fade.gdshader") as Shader
			mat.set_shader_parameter("albedo_tex", src.albedo_texture)
			mat.set_shader_parameter("normal_tex", src.normal_texture)
			mat.set_shader_parameter("normal_scale", src.normal_scale if src.normal_enabled else 1.0)
			mat.set_shader_parameter("albedo_color", src.albedo_color)
			mat.set_shader_parameter("roughness", src.roughness)
			mat.set_shader_parameter("metallic", src.metallic)
			mat.set_shader_parameter("specular", minf(src.metallic_specular, PropLayer.MINERAL_SPECULAR))
			mat.set_shader_parameter("use_roughness_tex", src.roughness_texture != null)
			if src.roughness_texture != null:
				mat.set_shader_parameter("roughness_tex", src.roughness_texture)
				mat.set_shader_parameter("roughness_channel", PropLayer._channel(src.roughness_texture_channel))
			mat.set_shader_parameter("use_metallic_tex", src.metallic_texture != null)
			if src.metallic_texture != null:
				mat.set_shader_parameter("metallic_tex", src.metallic_texture)
				mat.set_shader_parameter("metallic_channel", PropLayer._channel(src.metallic_texture_channel))
			var ao: bool = src.ao_enabled and src.ao_texture != null
			mat.set_shader_parameter("use_ao_tex", ao)
			if ao:
				mat.set_shader_parameter("ao_tex", src.ao_texture)
				mat.set_shader_parameter("ao_channel", PropLayer._channel(src.ao_texture_channel))
				mat.set_shader_parameter("ao_light_affect", src.ao_light_affect)
			mi.set_surface_override_material(si, mat)
