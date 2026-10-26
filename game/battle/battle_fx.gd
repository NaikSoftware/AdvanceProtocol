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

## Атласи (кадрів, сітка, швидкість, метрів у клітинці) — за SOURCES.md. Куля вибуху на піку
## займає ~15 м із 22-метрової клітинки (виміряно на кадрах), хмара ґрунту — ~8 м із 13,7,
## спалах — ~3 м із 6,7.
const EXPLOSION_FPS: float = 48.0
const EXPLOSION_CELL_M: float = 22.0
const EXPLOSION_BALL_M: float = 15.0
## 40 кадрів/с дали б 1,6 с; 44 вкладають усі 64 кадри в межу однієї миті (≤ 1,5 с).
const DIRT_FPS: float = 44.0
const DIRT_CELL_M: float = 13.7
const DIRT_CLOUD_M: float = 8.0
const FLASH_FPS: float = 60.0
const FLASH_CELL_M: float = 6.7
const FLASH_CORE_M: float = 3.0
## Іскри trace_03/04 (клітинки 2 і 3) звиваються блискавкою — їх не беремо.
const SPARK_CELLS: Array[int] = [0, 1, 4, 5, 6]

## Куля знищення: вогняна частина (кадри 0–40) — у темпі атласу, темний хвіст (40–63) —
## ще секунду, щоб полум'я уламків проступило під ним, а не змінило кулю одним кадром.
const EXPLOSION_TAIL_SEC: float = 1.0
const EXPLOSION_SEC: float = 40.0 / EXPLOSION_FPS + EXPLOSION_TAIL_SEC
## Квад влучання піднято на пів радіуса: атлас знято з землі під 45°, і низ клуби інакше
## різав би землю рівною лінією. Межу з землею ще й м'яко гасить глибина на 1,5 м.
const HIT_ANCHOR: float = 0.25
const HIT_SOFT_FADE: float = 1.5 / 8.0
## Ґрунт гасне з цього кадру: хвіст атласу лишав би темну грудку на траві.
const DIRT_FADE_FROM: float = 40.0
## Світло спалаху — 3–5 кадрів.
const FLASH_SEC: float = 0.08
## Куля починається ~2 м над землею: так вона накриває корпус, а не лежить на траві.
const LIFT_M: float = 2.0

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
	(ball.material_override as ShaderMaterial).set_shader_parameter("anchor", -0.1)
	var bmat := ball.material_override as ShaderMaterial
	var bt: Tween = root.create_tween()
	bt.tween_method(func(f: float) -> void: bmat.set_shader_parameter("frame", f), 0.0, 40.0, 40.0 / EXPLOSION_FPS)
	bt.tween_method(func(f: float) -> void: bmat.set_shader_parameter("frame", f), 40.0, 63.0, EXPLOSION_TAIL_SEC)
	bt.tween_callback(func() -> void: ball.visible = false)
	var flash := _sprite(root, "Flash", FLASH_TEX, Vector2(4, 4), 16, size * 0.5 * FLASH_CELL_M / FLASH_CORE_M, LIFT_M / 8.0, 2.5, true)
	(flash.material_override as ShaderMaterial).set_shader_parameter("anchor", -0.1)
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
		Weapon.SHELL:
			_flash(root, 4.0, Vector3(0, 0.2, 0), 0.0)
			_light(root, 15.0, 4.0)
			_dirt(root, cloud, Vector3.ZERO, 0.0, 64.0 / DIRT_FPS)
		Weapon.DRONE:
			# Удар згори: спалах на даху, клуба вибуху на корпусі, жодного викиду ґрунту.
			_flash(root, 1.75, Vector3(0, 0.4, 0), 0.0)
			_burst(root, cloud, Vector3(0, 0.15, 0), 0.0, 64.0 / EXPLOSION_FPS)
	_expire(root)
	return root


## Дульний спалах біля стрільця: танк і гармата — 4 м, автогармата — три малі. Стрілецька
## зброя спалаху не має: на екрані він субпіксельний. Стрільця, якого глядач не бачить, сюди
## не передають зовсім.
static func spawn_muzzle(parent: Node, shooter: Transform3D, weapon: Weapon) -> Node3D:
	if weapon == Weapon.RIFLE or weapon == Weapon.DRONE:
		return null
	var tip: Vector3 = shooter.origin - shooter.basis.z.normalized() * 0.5 + Vector3(0, 0.25, 0)
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
	(q.material_override as ShaderMaterial).set_shader_parameter("fade_from", DIRT_FADE_FROM)
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
		mat.set_shader_parameter("anchor", 0.0)
		q.visible = delay <= 0.0
		var tw: Tween = root.create_tween()
		if delay > 0.0:
			tw.tween_interval(delay)
			tw.tween_callback(func() -> void: q.visible = true)
		tw.tween_interval(0.12)
		tw.tween_callback(func() -> void: q.visible = false)


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
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-2, -1, -2), Vector3(4, 4, 4))
	mi.layers = 1 << (UnitView.UNIT_LAYER - 1)
	mat.set_shader_parameter("anchor", HIT_ANCHOR)
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
// Зсув центру кваду вгору, у частках його розміру; задає BattleFx на кожен ефект
// (HIT_ANCHOR — влучання, −0,1 — куля й спалах знищення).
uniform float anchor = 0.0;
// Поворот смуги в площині кадру (іскри віялом).
uniform float roll = 0.0;
// З цього кадру клуба гасне до нуля (хвіст атласу інакше лишається темною грудкою).
uniform float fade_from = 1000.0;
// Сонце (WeatherRig): освітлений бік клуби світліший на ясних мапах; у похмурі — нічого.
global uniform vec3 sun_dir;
global uniform float sky_clear;
varying vec2 v_sun;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
// М'які краї (1,2 м) лише там, де квад врізається в землю чи корпус.
uniform float soft_fade = 0.15;

void vertex() {
	float s = size * length(MODEL_MATRIX[0].xyz);
	vec3 c = MODEL_MATRIX[3].xyz + vec3(0.0, lift + s * anchor, 0.0);
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
	ALBEDO = t.rgb * gain * (1.0 + 0.45 * sky_clear * lit);
	ALPHA = t.a * (1.0 - smoothstep(fade_from, fade_from + 16.0, frame));
	// shortcut: глибина в NDC як у Vulkan (Forward+/Mobile); Compatibility дає z*2-1, краї там будуть жорсткіші.
	vec4 sv = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, texture(depth_tex, SCREEN_UV).r, 1.0);
	ALPHA *= clamp((VERTEX.z - sv.z / sv.w) / soft_fade, 0.0, 1.0);
}
"""
