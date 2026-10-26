class_name BattleFx
extends RefCounted
## Одноразові миті бою: вогняна куля знищеної техніки, влучання за класом зброї, дульний
## спалах. Кожна — запечений флипбук (assets/vfx/, симуляції з SOURCES.md) на квадах, що
## дивляться в камеру; живе ≤ 1,5 с, крутить власний твін і звільняє себе сама:
## `emitting = false` чи схований вузол лишали б її в кадрі й у дереві.
##
## Випадковість тут лише косметична (розкид порохових клубів і іскор) і береться з хешу
## місця, а не з `Rules.roll()`: косметика не сміє зсувати кидки правил.

enum Weapon { RIFLE, AUTOCANNON, TANK_GUN, SHELL, DRONE }

## Мить влучання й дульний спалах звільняються не пізніше цього.
const HIT_SEC: float = 1.45
## Скільки програвач чекає на влучання, перш ніж грати наступну подію (шкоду, поворот цілі):
## спалах мусить бути видно раніше, ніж ціль обернеться на стрільця.
const HIT_HOLD_SEC: float = 0.3

const EXPLOSION_TEX: Texture2D = preload("res://assets/vfx/explosion.png")
const DIRT_TEX: Texture2D = preload("res://assets/vfx/dirt_burst.png")
const FLASH_TEX: Texture2D = preload("res://assets/vfx/impact_flash.png")
const SPARKS_TEX: Texture2D = preload("res://assets/vfx/armour_sparks.png")

## Атласи (кадрів, сітка, швидкість, метрів у клітинці) — за SOURCES.md. Вміст на піку — з
## виміряних кадрів: куля 197 текселів із 256, ґрунт 190 із 256, спалах 112 із 192. Кожен
## виклик задає бажаний розмір вмісту в метрах; квад — у стільки ж разів більший за клітинку.
const EXPLOSION_FPS: float = 48.0
const EXPLOSION_CELL_M: float = 21.7
const EXPLOSION_BALL_M: float = 21.7 * 197.0 / 256.0
## 40 кадрів/с дали б 1,6 с; 44 вкладають усі 64 кадри в межу однієї миті (≤ 1,5 с).
const DIRT_FPS: float = 44.0
const DIRT_CELL_M: float = 13.4
const DIRT_CLOUD_M: float = 13.4 * 190.0 / 256.0
const FLASH_FPS: float = 60.0
const FLASH_CELL_M: float = 9.2
const FLASH_CORE_M: float = 9.2 * 112.0 / 192.0
## Точка вибуху в клітинці атласу (частка ширини зліва, висоти згори; SOURCES.md): квад
## зсунуто так, що вона лягає на точку влучання, а хмара здіймається з неї.
const EXPLOSION_BLAST := Vector2(0.508, 0.866)
const DIRT_BLAST := Vector2(0.495, 0.882)
const FLASH_BLAST := Vector2(0.479, 0.788)
## Іскри trace_03/04 (клітинки 2 і 3) звиваються блискавкою — їх не беремо.
const SPARK_CELLS: Array[int] = [0, 1, 4, 5, 6]

## Куля знищення: вогняна частина (кадри 0–40) — у темпі атласу, темний хвіст (40–63) —
## ще секунду, щоб полум'я уламків проступило під ним, а не змінило кулю одним кадром.
const EXPLOSION_TAIL_SEC: float = 1.0
const EXPLOSION_SEC: float = 40.0 / EXPLOSION_FPS + EXPLOSION_TAIL_SEC
## Межу клуби з землею й корпусом м'яко гасить глибина на 1,5 м.
const HIT_SOFT_FADE: float = 1.5 / 8.0
## Спалах не вигорає в чисто біле: перші ~4 кадри — з цією часткою підсилення.
const FLASH_EARLY_GAIN: float = 0.55
## Світло спалаху — 3–5 кадрів.
const FLASH_SEC: float = 0.08
## Куля народжується в корпусі, ~1 м над землею: точка вибуху атласу внизу клітинки, і
## клуба здіймається з неї, накриваючи машину, а не висить над нею.
const LIFT_M: float = 1.0

static var _mix_shader: Shader
static var _add_shader: Shader


## Діаметр кулі, тайли (1 тайл = 8 м): танк 12 м, гармата 5,5 м, решта техніки 7 м.
static func fireball_size(unit_class: int) -> float:
	match unit_class:
		UnitTypes.UnitClass.TANK:
			return 12.0 / 8.0
		UnitTypes.UnitClass.ARTILLERY:
			return 5.5 / 8.0
	return 7.0 / 8.0


static func spawn_explosion(parent: Node, at: Vector3, size: float) -> Node3D:
	var root := _root("Explosion", parent, at)
	var ball := _sprite(root, "Ball", EXPLOSION_TEX, Vector2(8, 8), 64, size * EXPLOSION_CELL_M / EXPLOSION_BALL_M, LIFT_M / 8.0, 1.0, false)
	var bmat := ball.material_override as ShaderMaterial
	var bt: Tween = root.create_tween()
	bt.tween_method(func(f: float) -> void: bmat.set_shader_parameter("frame", f), 0.0, 40.0, 40.0 / EXPLOSION_FPS)
	bt.tween_method(func(f: float) -> void: bmat.set_shader_parameter("frame", f), 40.0, 63.0, EXPLOSION_TAIL_SEC)
	bt.tween_callback(func() -> void: ball.visible = false)
	var flash := _sprite(root, "Flash", FLASH_TEX, Vector2(4, 4), 16, size * 0.5 * FLASH_CELL_M / FLASH_CORE_M, LIFT_M / 8.0, 2.5, true)
	_soft_flash(flash)
	_play(root, flash, 16, FLASH_FPS, 0.0)
	_light(root, 10.0, 6.0)
	var tw: Tween = root.create_tween()
	tw.tween_interval(EXPLOSION_SEC)
	tw.tween_callback(root.queue_free)
	return root


## Розігрів на старті бою: перша куля інакше чекає на компіляцію шейдерів 0,2–1 с, і кадр
## застигає саме на першому вбивстві. Куля невидимо мала, світло вимкнене; звільняє себе сама.
static func warm_up(parent: Node, at: Vector3) -> Node3D:
	var boom: Node3D = spawn_explosion(parent, at, 0.0001)
	(boom.get_node("Light") as OmniLight3D).light_energy = 0.0
	(boom.get_node("Flash") as MeshInstance3D).scale = Vector3.ONE * 0.0001
	return boom


static func weapon_of(unit_class: int) -> Weapon:
	match unit_class:
		UnitTypes.UnitClass.INFANTRY:
			return Weapon.RIFLE
		UnitTypes.UnitClass.LIGHT_VEHICLE:
			return Weapon.AUTOCANNON
		UnitTypes.UnitClass.TANK:
			return Weapon.TANK_GUN
		UnitTypes.UnitClass.ARTILLERY:
			return Weapon.SHELL
	return Weapon.RIFLE


## Діаметр клуби влучання, метри (1 тайл = 8 м): по броні — малий спалах із бризками іскор,
## по ґрунту — викид землі.
static func hit_cloud_m(weapon: Weapon, armoured: bool) -> float:
	match weapon:
		Weapon.AUTOCANNON:
			return 0.5 if armoured else 1.5
		Weapon.TANK_GUN:
			return 2.5 if armoured else 3.5
		Weapon.SHELL:
			return 12.0
		Weapon.DRONE:
			return 3.5
	return 0.6


## Влучання по цілі. `armoured` — техніка: по броні біло-жовті бризки іскор і малий спалах,
## по піхоті й землі — порох і ґрунт.
static func spawn_hit(parent: Node, at: Vector3, weapon: Weapon, armoured: bool) -> Node3D:
	var root := _root("Hit", parent, at)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(at)
	var cloud: float = hit_cloud_m(weapon, armoured)
	match weapon:
		Weapon.RIFLE:
			if armoured:
				# Іскри 2–3 чергами за 0,8 с; на далекому зумі — кілька цяток.
				for burst in 3:
					_spray(root, rng, 2, Vector3(0, 0.25, 0), 0.2, burst * 0.3, 1.0)
			else:
				# 6–12 порохових фонтанчиків на ділянці 4 × 4 м довкола.
				for i in 9:
					var o := Vector3(rng.randf_range(-0.25, 0.25), 0.0, rng.randf_range(-0.25, 0.25))
					_dirt(root, rng.randf_range(0.5, 0.8), o, rng.randf_range(0.0, 0.8), 0.6)
		Weapon.AUTOCANNON:
			for r in 4:
				var o := Vector3(rng.randf_range(-0.12, 0.12), 0.2 if armoured else 0.0, rng.randf_range(-0.12, 0.12))
				_flash(root, 1.0 if armoured else 0.8, o, r * 0.15)
				if armoured:
					_spray(root, rng, 3, o, 0.1, r * 0.15, 1.4)
					_burst(root, cloud, o, r * 0.15, 0.7)
				else:
					_dirt(root, cloud, o, r * 0.15, 0.7)
		Weapon.TANK_GUN:
			_flash(root, 2.5, Vector3(0, 0.25, 0), 0.0)
			_light(root, 10.0, 4.0)
			if armoured:
				_spray(root, rng, 8, Vector3(0, 0.3, 0), 0.15, 0.0, 2.2)
				_burst(root, cloud, Vector3(0, 0.15, 0), 0.0, 64.0 / EXPLOSION_FPS)
			else:
				_dirt(root, cloud, Vector3.ZERO, 0.0, 64.0 / DIRT_FPS)
				_debris(root, cloud)
		Weapon.SHELL:
			_flash(root, 4.0, Vector3(0, 0.2, 0), 0.0)
			_light(root, 15.0, 4.0)
			_dirt(root, cloud, Vector3.ZERO, 0.0, 64.0 / DIRT_FPS)
			_debris(root, cloud)
		Weapon.DRONE:
			# Удар згори: спалах на даху, клуба вибуху на корпусі, жодного викиду ґрунту.
			_flash(root, 1.75, Vector3(0, 0.4, 0), 0.0)
			_burst(root, cloud, Vector3(0, 0.15, 0), 0.0, 64.0 / EXPLOSION_FPS)
	_expire(root)
	return root


## Дульний спалах біля стрільця: танк і гармата — 4 м, автогармата — три малі. Стрілецька
## зброя спалаху не має: на екрані він субпіксельний. Стрільця, якого глядач не бачить, сюди
## не передають зовсім.
static func spawn_muzzle(parent: Node, shooter: Transform3D, weapon: Weapon, type_id: int = -1) -> Node3D:
	if weapon == Weapon.RIFLE or weapon == Weapon.DRONE:
		return null
	var tip: Vector3 = shooter * (UnitSilhouettes.muzzle(type_id) if type_id >= 0 else Vector3(0, 0.2, -0.6))
	var root := _root("Muzzle", parent, tip)
	if weapon == Weapon.AUTOCANNON:
		for r in 3:
			_flash(root, 0.6, Vector3.ZERO, r * 0.15)
	else:
		_flash(root, 4.0, Vector3.ZERO, 0.0)
	_expire(root)
	return root


## Усі атласи, на які посилаються матеріали цієї миті (для тестів і розігріву).
static func atlases_of(root: Node) -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mat := (n as MeshInstance3D).material_override as ShaderMaterial
		if mat != null and not out.has(mat.get_shader_parameter("tex")):
			out.append(mat.get_shader_parameter("tex"))
	return out


## Викид ґрунту: 10–20 темних грудок 0,1–0,4 м, що крутяться в балістичних дугах, і 2–4
## смуги землі вздовж польоту. Більший вибух — більше грудок і вищий кидок. Дві системи
## частинок на вибух (по виклику малювання), матеріали й сітки спільні для всіх вибухів.
static func _debris(root: Node3D, cloud_m: float) -> void:
	var k: float = clampf((cloud_m - 3.5) / 8.5, 0.0, 1.0)
	# Злітає вище за хмару ґрунту (снаряд — ~10 м, гармата по ґрунту — ~3 м) і падає за її
	# краєм: усередині клуби грудок не видно.
	var v: float = sqrt(2.0 * 9.8 * cloud_m * 0.85) / 8.0
	if _clod_mesh == null:
		_clod_mesh = BoxMesh.new()
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.09, 0.07, 0.05)
		m.roughness = 1.0
		_clod_mesh.material = m
		_streak_mesh = _cross_quad()
		var sm := StandardMaterial3D.new()
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.albedo_color = Color(0.05, 0.04, 0.03, 0.85)
		sm.cull_mode = BaseMaterial3D.CULL_DISABLED
		_streak_mesh.surface_set_material(0, sm)
	var clods := _debris_emitter(root, "Debris", 10 + roundi(8.0 * k), v, _clod_mesh, 0.1 / 8.0, 0.4 / 8.0, false)
	clods.position = Vector3(0, 0.02, 0)
	_debris_emitter(root, "DebrisStreaks", 2 + roundi(2.0 * k), v * 1.15, _streak_mesh, 1.0 / 8.0, 2.0 / 8.0, true)


static var _clod_mesh: BoxMesh
static var _streak_mesh: ArrayMesh


static func _debris_emitter(root: Node3D, node_name: String, amount: int, v: float, mesh: Mesh, s_min: float, s_max: float, align: bool) -> GPUParticles3D:
	var em := GPUParticles3D.new()
	em.name = node_name
	em.amount = amount
	em.lifetime = 1.2
	em.one_shot = true
	em.explosiveness = 1.0
	em.randomness = 0.5
	em.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 60.0
	pm.initial_velocity_min = v * 0.5
	pm.initial_velocity_max = v
	# Справжня вага: грудки падають так, як падали б на 8-метровому тайлі.
	pm.gravity = Vector3(0.0, -9.8 / 8.0, 0.0)
	pm.scale_min = s_min
	pm.scale_max = s_max
	pm.lifetime_randomness = 0.3
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.03
	if align:
		# Смуга тягнеться вздовж польоту.
		pm.particle_flag_align_y = true
		pm.color = Color(1, 1, 1, 1)
		var fade := Gradient.new()
		fade.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
		var ft := GradientTexture1D.new()
		ft.gradient = fade
		pm.color_ramp = ft
	else:
		pm.angle_min = -180.0
		pm.angle_max = 180.0
		pm.angular_velocity_min = -360.0
		pm.angular_velocity_max = 360.0
		pm.particle_flag_rotate_y = true
	em.process_material = pm
	em.draw_pass_1 = mesh
	em.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	em.layers = 1 << (UnitView.UNIT_LAYER - 1)
	em.visibility_aabb = AABB(Vector3(-1.5, -0.2, -1.5), Vector3(3, 2, 3))
	root.add_child(em, true)
	em.emitting = true
	return em


## Два схрещені вузькі квади: смугу видно з будь-якого боку, а не ребром.
static func _cross_quad() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for basis: Basis in [Basis(), Basis(Vector3.UP, PI * 0.5)]:
		var a: Vector3 = basis * Vector3(-0.06, -0.5, 0)
		var b: Vector3 = basis * Vector3(0.06, -0.5, 0)
		var c: Vector3 = basis * Vector3(0.06, 0.5, 0)
		var d: Vector3 = basis * Vector3(-0.06, 0.5, 0)
		for q: Vector3 in [a, b, c, a, c, d]:
			st.add_vertex(q)
	return st.commit()


static func _root(node_name: String, parent: Node, at: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	root.position = at
	# Читабельне ім'я (Hit2, Explosion3): поруч із ще не звільненою миттю рушій інакше дав би @Node3D@.
	parent.add_child(root, true)
	return root


static func _expire(root: Node3D) -> void:
	var tw: Tween = root.create_tween()
	tw.tween_interval(HIT_SEC)
	tw.tween_callback(root.queue_free)


## Спалах: ядро `core_m` метрів.
static func _flash(root: Node3D, core_m: float, offset: Vector3, delay: float) -> void:
	var q := _sprite(root, "Flash", FLASH_TEX, Vector2(4, 4), 16, core_m * FLASH_CELL_M / FLASH_CORE_M / 8.0, 0.0, 2.5, true)
	_soft_flash(q)
	q.position = offset
	_play(root, q, 16, FLASH_FPS, delay)


## Клуба вибуху з кулею `ball_m` метрів.
static func _burst(root: Node3D, ball_m: float, offset: Vector3, delay: float, sec: float) -> void:
	var q := _sprite(root, "Burst", EXPLOSION_TEX, Vector2(8, 8), 64, ball_m * EXPLOSION_CELL_M / EXPLOSION_BALL_M / 8.0, 0.0, 1.0, false)
	q.position = offset
	_play(root, q, 64, 64.0 / sec, delay)


## Хмара ґрунту `cloud_m` метрів.
static func _dirt(root: Node3D, cloud_m: float, offset: Vector3, delay: float, sec: float) -> void:
	var q := _sprite(root, "Dirt", DIRT_TEX, Vector2(8, 8), 64, cloud_m * DIRT_CELL_M / DIRT_CLOUD_M / 8.0, 0.0, 1.0, false)
	q.position = offset
	_play(root, q, 64, 64.0 / sec, delay)


## Віяло з `count` іскор довкола точки влучання: кожна — смуга атласу, повернута в площині
## кадру на свій кут, `length_m` метрів, 0,12 с.
static func _spray(root: Node3D, rng: RandomNumberGenerator, count: int, at: Vector3, spread: float, delay: float, length_m: float) -> void:
	for i in count:
		var q := _sprite(root, "Spark", SPARKS_TEX, Vector2(4, 2), 8, length_m / 8.0, 0.0, 2.5, true)
		q.position = at + Vector3(rng.randf_range(-spread, spread), rng.randf_range(-spread, spread) * 0.5, rng.randf_range(-spread, spread))
		var mat := q.material_override as ShaderMaterial
		mat.set_shader_parameter("frame", float(SPARK_CELLS[rng.randi() % SPARK_CELLS.size()]))
		mat.set_shader_parameter("roll", rng.randf_range(-1.3, 1.3))
		q.visible = delay <= 0.0
		var tw: Tween = root.create_tween()
		if delay > 0.0:
			tw.tween_interval(delay)
			tw.tween_callback(func() -> void: q.visible = true)
		tw.tween_interval(0.12)
		tw.tween_callback(func() -> void: q.visible = false)


static func _soft_flash(q: MeshInstance3D) -> void:
	var mat := q.material_override as ShaderMaterial
	mat.set_shader_parameter("early_gain", FLASH_EARLY_GAIN)
	mat.set_shader_parameter("cool_edge", 1.0)


## Зсув центру кваду від точки влучання, у частках кваду (x — праворуч на екрані, y — угору):
## точка вибуху атласу лягає на точку влучання. Іскри — смуги з центру.
static func anchor_of(tex: Texture2D) -> Vector2:
	var blast := Vector2(0.5, 0.5)
	if tex == EXPLOSION_TEX:
		blast = EXPLOSION_BLAST
	elif tex == DIRT_TEX:
		blast = DIRT_BLAST
	elif tex == FLASH_TEX:
		blast = FLASH_BLAST
	return Vector2(0.5 - blast.x, blast.y - 0.5)


static func _sprite(root: Node3D, node_name: String, tex: Texture2D, grid: Vector2, frames: int, size: float, lift: float, gain: float, additive: bool) -> MeshInstance3D:
	var mat := ShaderMaterial.new()
	mat.shader = _shader(additive)
	mat.set_shader_parameter("tex", tex)
	mat.set_shader_parameter("grid", grid)
	mat.set_shader_parameter("frames", float(frames))
	mat.set_shader_parameter("frame", 0.0)
	mat.set_shader_parameter("size", size)
	mat.set_shader_parameter("lift", lift)
	mat.set_shader_parameter("gain", gain)
	mat.set_shader_parameter("early_gain", 1.0)
	mat.set_shader_parameter("cool_edge", 0.0)
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-2, -1, -2), Vector3(4, 4, 4))
	mi.layers = 1 << (UnitView.UNIT_LAYER - 1)
	mat.set_shader_parameter("anchor", anchor_of(tex))
	mat.set_shader_parameter("soft_fade", HIT_SOFT_FADE)
	# Читабельні імена (Spark2, Spark3): рушій інакше перейменував би однойменних сусідів у @…@.
	root.add_child(mi, true)
	return mi


## Кадри 0 → frames−1 за frames/fps секунд, далі квад ховається (атласи закінчуються порожніми).
static func _play(root: Node3D, q: MeshInstance3D, frames: int, fps: float, delay: float) -> void:
	var mat := q.material_override as ShaderMaterial
	q.visible = delay <= 0.0
	var tw: Tween = root.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
		tw.tween_callback(func() -> void: q.visible = true)
	tw.tween_method(func(f: float) -> void: mat.set_shader_parameter("frame", f), 0.0, float(frames - 1), float(frames) / fps)
	tw.tween_callback(func() -> void: q.visible = false)


static func _light(root: Node3D, range_m: float, energy: float) -> void:
	var light := OmniLight3D.new()
	light.name = "Light"
	light.light_color = Color("fff4d8")
	light.light_energy = energy
	light.omni_range = range_m / 8.0
	light.position.y = 0.3
	light.layers = 1 << (UnitView.UNIT_LAYER - 1)
	root.add_child(light)
	root.create_tween().tween_property(light, "light_energy", 0.0, FLASH_SEC)


static func _shader(additive: bool) -> Shader:
	if additive:
		if _add_shader == null:
			_add_shader = Shader.new()
			_add_shader.code = _SPRITE_CODE.replace("blend_mix", "blend_add")
		return _add_shader
	if _mix_shader == null:
		_mix_shader = Shader.new()
		_mix_shader.code = _SPRITE_CODE
	return _mix_shader


## Квад флипбука в камеру. Колір і пряма альфа — з самого атласу (він уже освітлений і
## розфарбований); між кадрами — плавний перехід, бо один кадр атласу триває кілька кадрів
## екрана. `gain` > 1 — для спалаху й іскор: вони мусять бути найяскравішими на екрані.
const _SPRITE_CODE: String = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform vec2 grid = vec2(8.0);
uniform float frames = 64.0;
uniform float frame = 0.0;
uniform float size = 1.0;
uniform float lift = 0.0;
uniform float gain = 1.0;
// Зсув центру кваду від точки влучання в площині кадру, у частках кваду (BattleFx.anchor_of):
// точка вибуху атласу лягає на точку влучання.
uniform vec2 anchor = vec2(0.0);
// Поворот смуги в площині кадру (іскри віялом).
uniform float roll = 0.0;
// Спалах: перші ~4 кадри — з такою часткою підсилення (без чисто білої плями), а край, де
// альфа спадає, холоне до #B8400F. Іскри й клуби — без цього.
uniform float early_gain = 1.0;
uniform float cool_edge = 0.0;
// Сонце (WeatherRig): освітлений бік клуби світліший на ясних мапах; у похмурі — нічого.
global uniform vec3 sun_dir;
global uniform float sky_clear;
varying vec2 v_sun;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
// М'які краї (1,2 м) лише там, де квад врізається в землю чи корпус.
uniform float soft_fade = 0.15;

void vertex() {
	float s = size * length(MODEL_MATRIX[0].xyz);
	vec3 c = MODEL_MATRIX[3].xyz + vec3(0.0, lift, 0.0) + (INV_VIEW_MATRIX[0].xyz * anchor.x + INV_VIEW_MATRIX[1].xyz * anchor.y) * s;
	vec2 v = vec2(cos(roll) * VERTEX.x - sin(roll) * VERTEX.y, sin(roll) * VERTEX.x + cos(roll) * VERTEX.y);
	vec3 world = c + (INV_VIEW_MATRIX[0].xyz * v.x + INV_VIEW_MATRIX[1].xyz * v.y) * s;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
	v_sun = normalize(vec2(dot(sun_dir, INV_VIEW_MATRIX[0].xyz), -dot(sun_dir, INV_VIEW_MATRIX[1].xyz)) + 1e-4);
}

vec4 frame_at(float f, vec2 uv) {
	float n = clamp(f, 0.0, frames - 1.0);
	return texture(tex, (clamp(uv, vec2(0.002), vec2(0.998)) + vec2(mod(n, grid.x), floor(n / grid.x))) / grid);
}

void fragment() {
	vec4 t = mix(frame_at(floor(frame), UV), frame_at(floor(frame) + 1.0, UV), fract(frame));
	// Бік клуби до сонця — світліший на 0,3–0,5 сонячного світла (лише на ясних мапах).
	float lit = clamp(dot(normalize(UV - 0.5 + 1e-4), v_sun), 0.0, 1.0) * smoothstep(0.05, 0.35, length(UV - 0.5));
	vec3 rgb = mix(t.rgb, vec3(0.479, 0.051, 0.005) * 2.0, cool_edge * (1.0 - smoothstep(0.15, 0.7, t.a)));
	ALBEDO = rgb * gain * mix(early_gain, 1.0, smoothstep(0.0, 4.0, frame)) * (1.0 + 0.45 * sky_clear * lit);
	ALPHA = t.a;
	// shortcut: глибина в NDC як у Vulkan (Forward+/Mobile); Compatibility дає z*2-1, краї там будуть жорсткіші.
	vec4 sv = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, texture(depth_tex, SCREEN_UV).r, 1.0);
	ALPHA *= clamp((VERTEX.z - sv.z / sv.w) / soft_fade, 0.0, 1.0);
}
"""
