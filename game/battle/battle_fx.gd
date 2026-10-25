class_name BattleFx
extends RefCounted
## Одноразові миті бою: вогняна куля знищеної техніки. Кожна живе ≤ 1,5 с, крутить
## власний твін і звільняє себе сама: `emitting = false` чи схований вузол лишали б
## її в кадрі й у дереві.

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
	parent.add_child(root)
	var tw: Tween = root.create_tween()
	tw.tween_method(func(a: float) -> void: mat.set_shader_parameter("age", a), 0.0, 1.0, EXPLOSION_SEC)
	tw.parallel().tween_property(light, "light_energy", 0.0, FLASH_SEC)
	tw.parallel().tween_callback(func() -> void: flash.visible = false).set_delay(FLASH_SEC)
	tw.tween_callback(root.queue_free)
	return root


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
