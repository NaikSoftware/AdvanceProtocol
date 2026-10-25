class_name BattleFx
extends RefCounted
## Одноразові миті бою: вогняна куля знищеної техніки, влучання за класом зброї, дульний
## спалах. Кожна живе ≤ 1,5 с, крутить власний твін і звільняє себе сама: `emitting = false`
## чи схований вузол лишали б її в кадрі й у дереві.
##
## Випадковість тут лише косметична (розкид порохових клубів і іскор) і береться з хешу
## місця, а не з `Rules.roll()`: косметика не сміє зсувати кидки правил.

enum Weapon { RIFLE, AUTOCANNON, TANK_GUN, SHELL, DRONE }
## Палітри куль: вибух (біле → вогонь → чорне), мокрий ґрунт, сірий дим, чорне ядро дрона.
enum Palette { FIRE, DIRT, GREY, BLACK }

## Мить влучання й дульний спалах звільняються не пізніше цього.
const HIT_SEC: float = 1.45
## Скільки програвач чекає на влучання, перш ніж грати наступну подію (шкоду, поворот цілі):
## спалах мусить бути видно раніше, ніж ціль обернеться на стрільця.
const HIT_HOLD_SEC: float = 0.3

const EXPLOSION_SEC: float = 1.2
## Спалах і світло — 3–5 кадрів, далі вогонь і чорний дим.
const FLASH_SEC: float = 0.08
const FLASH_M: float = 4.0
## Куля починається ~2 м над землею: так вона накриває корпус, а не лежить на траві.
const LIFT_M: float = 2.0
const EXPLOSION_TEX_PATH: String = "res://assets/vfx/explosion.png"

static var _ball_shader: Shader
static var _flash_shader: Shader


## Діаметр кулі, тайли (1 тайл = 8 м): танк 12 м, гармата 5,5 м, решта техніки 7 м.
static func fireball_size(unit_class: int) -> float:
	match unit_class:
		UnitTypes.UnitClass.TANK:
			return 12.0 / 8.0
		UnitTypes.UnitClass.ARTILLERY:
			return 5.5 / 8.0
	return 7.0 / 8.0


static func spawn_explosion(parent: Node, at: Vector3, size: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Explosion"
	root.position = at
	var mat := ShaderMaterial.new()
	mat.shader = _shader(true)
	mat.set_shader_parameter("tex", _texture())
	mat.set_shader_parameter("size", size)
	mat.set_shader_parameter("lift", LIFT_M / 8.0)
	var ball := _quad("Ball", mat, Vector2.ONE)
	root.add_child(ball)
	var fmat := ShaderMaterial.new()
	fmat.shader = _shader(false)
	var flash := _quad("Flash", fmat, Vector2.ONE * FLASH_M / 8.0)
	flash.position.y = LIFT_M / 8.0
	root.add_child(flash)
	var light := OmniLight3D.new()
	light.name = "Light"
	light.light_color = Color("fff4d8")
	light.light_energy = 6.0
	light.omni_range = 10.0 / 8.0
	light.position.y = LIFT_M / 8.0
	light.layers = 1 << (UnitView.UNIT_LAYER - 1)
	root.add_child(light)
	# Читабельне ім'я (Hit2, Explosion3): поруч із ще не звільненою миттю рушій інакше дав би @Node3D@.
	parent.add_child(root, true)
	var tw: Tween = root.create_tween()
	tw.tween_method(func(a: float) -> void: mat.set_shader_parameter("age", a), 0.0, 1.0, EXPLOSION_SEC)
	tw.parallel().tween_property(light, "light_energy", 0.0, FLASH_SEC)
	tw.parallel().tween_callback(func() -> void: flash.visible = false).set_delay(FLASH_SEC)
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


## Влучання по цілі, розміри в метрах (1 тайл = 8 м). `armoured` — техніка: по броні
## іскри й сіра хмара, по піхоті й землі — порох і ґрунт.
static func spawn_hit(parent: Node, at: Vector3, weapon: Weapon, armoured: bool) -> Node3D:
	var root := _root("Hit", parent, at)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(at)
	var soft: Palette = Palette.GREY if armoured else Palette.DIRT
	match weapon:
		Weapon.RIFLE:
			if armoured:
				# Іскри 2–3 чергами за 0,8 с; на далекому зумі — кілька цяток.
				for burst in 3:
					for i in 2:
						_flash(root, 0.7, 0.07, Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(0.15, 0.4), rng.randf_range(-0.2, 0.2)), burst * 0.3)
			else:
				# 6–12 порохових фонтанчиків 0,3–0,6 м на ділянці 4 × 4 м довкола.
				for i in 9:
					_puff(root, rng.randf_range(0.4, 0.7), Palette.DIRT, 0.6, Vector3(rng.randf_range(-0.25, 0.25), 0.0, rng.randf_range(-0.25, 0.25)), rng.randf_range(0.0, 0.8))
		Weapon.AUTOCANNON:
			for r in 4:
				var o := Vector3(rng.randf_range(-0.12, 0.12), 0.2 if armoured else 0.0, rng.randf_range(-0.12, 0.12))
				_flash(root, 1.0, 0.06, o, r * 0.15)
				_puff(root, 1.5, soft, 0.7, o, r * 0.15)
		Weapon.TANK_GUN:
			_flash(root, 2.5, 0.08, Vector3(0, 0.25, 0), 0.0)
			_light(root, 10.0)
			_puff(root, 7.0, soft, 1.3, Vector3.ZERO, 0.0)
		Weapon.SHELL:
			_flash(root, 4.0, 0.1, Vector3(0, 0.2, 0), 0.0)
			_light(root, 15.0)
			_puff(root, 12.0, Palette.DIRT, 1.4, Vector3.ZERO, 0.0)
		Weapon.DRONE:
			# Удар згори: спалах на даху, чорноядерна клуба, жодного викиду ґрунту.
			_flash(root, 1.75, 0.08, Vector3(0, 0.4, 0), 0.0)
			_puff(root, 3.5, Palette.BLACK, 1.1, Vector3(0, 0.15, 0), 0.0)
	_expire(root)
	return root


## Дульний спалах біля стрільця: танк і гармата — 4 м на 0,07 с, автогармата — три малі.
## Стрілецька зброя спалаху не має: на екрані він субпіксельний. Стрільця, якого глядач не
## бачить, сюди не передають зовсім.
static func spawn_muzzle(parent: Node, shooter: Transform3D, weapon: Weapon) -> Node3D:
	if weapon == Weapon.RIFLE or weapon == Weapon.DRONE:
		return null
	var tip: Vector3 = shooter.origin - shooter.basis.z.normalized() * 0.5 + Vector3(0, 0.25, 0)
	var root := _root("Muzzle", parent, tip)
	if weapon == Weapon.AUTOCANNON:
		for r in 3:
			_flash(root, 0.6, 0.05, Vector3.ZERO, r * 0.15)
	else:
		_flash(root, 4.0, 0.07, Vector3.ZERO, 0.0)
	_expire(root)
	return root


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


static func _flash(root: Node3D, size_m: float, sec: float, offset: Vector3, delay: float) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = _shader(false)
	var q := _quad("Flash", mat, Vector2.ONE * size_m / 8.0)
	q.position = offset
	q.visible = delay <= 0.0
	root.add_child(q)
	var tw: Tween = root.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
		tw.tween_callback(func() -> void: q.visible = true)
	tw.tween_interval(sec)
	tw.tween_callback(func() -> void: q.visible = false)


static func _puff(root: Node3D, size_m: float, palette: Palette, sec: float, offset: Vector3, delay: float) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = _shader(true)
	mat.set_shader_parameter("tex", _texture())
	mat.set_shader_parameter("size", size_m / 8.0)
	mat.set_shader_parameter("lift", 0.0)
	mat.set_shader_parameter("palette", int(palette))
	mat.set_shader_parameter("age", 0.0)
	var q := _quad("Puff", mat, Vector2.ONE)
	q.position = offset
	q.visible = delay <= 0.0
	root.add_child(q)
	var tw: Tween = root.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
		tw.tween_callback(func() -> void: q.visible = true)
	tw.tween_method(func(a: float) -> void: mat.set_shader_parameter("age", a), 0.0, 1.0, sec)
	tw.tween_callback(func() -> void: q.visible = false)


static func _light(root: Node3D, range_m: float) -> void:
	var light := OmniLight3D.new()
	light.name = "Light"
	light.light_color = Color("fff4d8")
	light.light_energy = 4.0
	light.omni_range = range_m / 8.0
	light.position.y = 0.3
	light.layers = 1 << (UnitView.UNIT_LAYER - 1)
	root.add_child(light)
	root.create_tween().tween_property(light, "light_energy", 0.0, FLASH_SEC)


static func _quad(node_name: String, mat: ShaderMaterial, size: Vector2) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var mesh := QuadMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-2, -1, -2), Vector3(4, 4, 4))
	mi.layers = 1 << (UnitView.UNIT_LAYER - 1)
	return mi


static func _texture() -> Texture2D:
	if ResourceLoader.exists(EXPLOSION_TEX_PATH):
		return load(EXPLOSION_TEX_PATH)
	return WreckLayer._flipbook(WreckLayer.SMOKE_TEX_PATH, false)


static func _shader(ball: bool) -> Shader:
	if ball:
		if _ball_shader == null:
			_ball_shader = Shader.new()
			_ball_shader.code = _BALL_CODE
		return _ball_shader
	if _flash_shader == null:
		_flash_shader = Shader.new()
		_flash_shader.code = _FLASH_CODE
	return _flash_shader


const _FLASH_CODE: String = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;

void vertex() {
	vec3 c = MODEL_MATRIX[3].xyz;
	float s = length(MODEL_MATRIX[0].xyz);
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(c + (INV_VIEW_MATRIX[0].xyz * VERTEX.x + INV_VIEW_MATRIX[1].xyz * VERTEX.y) * s, 1.0);
}

void fragment() {
	vec2 q = UV - 0.5;
	float r = length(q);
	// Гаряче ядро й чотири короткі промені, що згасають до 0,45 півкваду.
	float core = 1.0 - smoothstep(0.0, 0.22, r);
	float rays = (1.0 - smoothstep(0.01, 0.025, min(abs(q.x), abs(q.y)))) * (1.0 - smoothstep(0.1, 0.45, r));
	float a = clamp(core + rays * 0.5, 0.0, 1.0) * (1.0 - smoothstep(0.35, 0.45, r));
	ALBEDO = vec3(1.0, 0.957, 0.847) * 3.0 * a;
}
"""

const _BALL_CODE: String = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// Без міпмап і без розмиття: куля мусить читатись клубами, а не плямою.
uniform sampler2D tex : source_color, filter_linear;
uniform float grid = 8.0;
uniform float age = 0.0;
uniform float size = 1.5;
uniform float lift = 0.25;
// BattleFx.Palette: 0 вибух, 1 мокрий ґрунт, 2 сірий дим, 3 чорне ядро дрона.
uniform int palette = 0;
uniform vec2 alpha_edge = vec2(0.42, 0.58);
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
// М'які краї (1,2 м) лише там, де квад врізається в землю чи уламки.
uniform float soft_fade = 0.15;

varying float v_frame;

void vertex() {
	// Заступник заповнює ~70 % кадру, тож квад на 40 % більший за діаметр кулі.
	float s = size * 1.4 * mix(0.6, 1.0, sqrt(age));
	// Центр піднімається з корпусу разом із ростом кулі, низ лишається на ньому.
	vec3 c = MODEL_MATRIX[3].xyz + vec3(0.0, lift + s * 0.25, 0.0);
	vec3 world = c + (INV_VIEW_MATRIX[0].xyz * VERTEX.x + INV_VIEW_MATRIX[1].xyz * VERTEX.y) * s;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
	v_frame = age * (grid * grid - 1.0);
}

vec4 frame_at(float f, vec2 uv) {
	float n = clamp(f, 0.0, grid * grid - 1.0);
	return texture(tex, (clamp(uv, vec2(0.002), vec2(0.998)) + vec2(mod(n, grid), floor(n / grid))) / grid);
}

void fragment() {
	vec4 t = mix(frame_at(floor(v_frame), UV), frame_at(floor(v_frame) + 1.0, UV), fract(v_frame));
	float lum = dot(t.rgb, vec3(0.299, 0.587, 0.114));
	// Біло-гарячий (#FFF4D8) перші кадри → вогонь (#E0702A…#FFD9A0) → чорні клуби до ~1 с.
	vec3 white = vec3(1.0, 0.91, 0.69) * 3.0;
	vec3 fire = mix(vec3(0.75, 0.16, 0.024), vec3(1.0, 0.70, 0.35), lum * lum) * 1.6;
	vec3 smoke = vec3(0.012, 0.011, 0.010) * (0.6 + 0.9 * lum);
	vec3 col = mix(white, fire, smoothstep(0.03, 0.08, age));
	// Темні, тіньові клуби чорніють першими: жар лишається в освітлених і гасне до ~1 с.
	col = mix(col, smoke, smoothstep(0.2, 0.75, age + (0.6 - lum) * 0.5));
	if (palette == 1) {
		// Мокрий суглинок L* 28–38 → сірий L* 45–50, коли пил осідає.
		col = mix(vec3(0.075, 0.062, 0.048), vec3(0.15, 0.145, 0.14), smoothstep(0.2, 1.0, age)) * (0.6 + 0.8 * lum);
	} else if (palette == 2) {
		col = mix(vec3(0.07, 0.065, 0.06), vec3(0.17, 0.165, 0.16), smoothstep(0.1, 1.0, age)) * (0.6 + 0.8 * lum);
	} else if (palette == 3) {
		col = mix(fire, vec3(0.008), smoothstep(0.02, 0.25, age + (0.5 - lum) * 0.3)) * (0.7 + 0.6 * lum);
	}
	ALBEDO = col;
	float a = smoothstep(alpha_edge.x, alpha_edge.y, t.a);
	// Наприкінці клуби розпадаються за кадром, а не тьмяніють рівно.
	a *= 1.0 - smoothstep(0.8, 1.0, age + (1.0 - lum) * 0.15);
	ALPHA = a;
	// shortcut: глибина в NDC як у Vulkan (Forward+/Mobile); Compatibility дає z*2-1, краї там будуть жорсткіші.
	vec4 sv = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, texture(depth_tex, SCREEN_UV).r, 1.0);
	ALPHA *= clamp((VERTEX.z - sv.z / sv.w) / soft_fade, 0.0, 1.0);
}
"""
