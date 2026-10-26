class_name BattleFx
extends RefCounted
## Одноразові миті бою: вогняна куля знищеної техніки, влучання за класом зброї, дульний
## спалах. Кожна — запечений флипбук (assets/vfx/, симуляції з SOURCES.md) на квадах, що
## дивляться в камеру, плюс частинки (іскри, грудки, уламки); крутить власний твін і звільняє
## себе сама: `emitting = false` чи схований вузол лишали б її в кадрі й у дереві.
##
## Дим після вибуху не зникає на місці. Вибух різкий: клуба набирає повний об'єм за 0,1–0,2 с
## (атлас іде швидко), далі довга повільна фаза — атлас ледь повзе, клуба здіймається з
## уповільненням, ширшає, зноситься вітром і рівно розріджується до нуля за 1–5,5 с. Кінець
## задає власна крива прозорості, а не останній кадр атласу. Програвач на це не чекає (HIT_HOLD_SEC).
##
## Випадковість тут лише косметична (розкид порохових клубів і частинок) і береться з хешу
## місця, а не з `Rules.roll()`: косметика не сміє зсувати кидки правил.

enum Weapon { RIFLE, AUTOCANNON, TANK_GUN, SHELL, DRONE }

## Мить влучання й дульний спалах звільняються не пізніше цього: найдовший димний хвіст
## (снаряд) і запас на згасання.
const HIT_SEC: float = 6.5
## Скільки програвач чекає на влучання, перш ніж грати наступну подію (шкоду, поворот цілі):
## спалах мусить бути видно раніше, ніж ціль обернеться на стрільця.
const HIT_HOLD_SEC: float = 0.3
## Група всіх митей: на передачі ходу їх прибирають, бо дим над тайлом, якого гравець, що
## заходить, не розвідав, показав би, де стояла ціль (§3.5).
const GROUP: StringName = &"battle_fx"

const EXPLOSION_TEX: Texture2D = preload("res://assets/vfx/explosion.png")
const DIRT_TEX: Texture2D = preload("res://assets/vfx/dirt_burst.png")
const FLASH_TEX: Texture2D = preload("res://assets/vfx/impact_flash.png")
## Густий темний дим тієї ж симуляції, що й куля (SOURCES.md): у нього куля перетікає, коли
## вогонь згас, і саме він висить, здіймається й розріджується.
const SMOKE_TEX: Texture2D = preload("res://assets/vfx/smoke_column.png")

## Атласи (кадрів, сітка, швидкість, метрів у клітинці) — за SOURCES.md. Вміст на піку — з
## виміряних кадрів: куля 197 текселів із 256, ґрунт 190 із 256, спалах 112 із 192. Кожен
## виклик задає бажаний розмір вмісту в метрах; квад — у стільки ж разів більший за клітинку.
const EXPLOSION_FPS: float = 48.0
const EXPLOSION_CELL_M: float = 21.7
const EXPLOSION_BALL_M: float = 21.7 * 197.0 / 256.0
const DIRT_FPS: float = 44.0
const DIRT_CELL_M: float = 13.4
const DIRT_CLOUD_M: float = 13.4 * 190.0 / 256.0
## Спалах: перші два кадри атласу — суцільний білий диск, тож починаємо з третього; 90 кадрів/с
## лишають біле ядро на ~60 мс, далі воно холоне в помаранчеве.
const FLASH_FPS: float = 90.0
const FLASH_FIRST: int = 2
const FLASH_CELL_M: float = 9.2
const FLASH_CORE_M: float = 9.2 * 112.0 / 192.0
## Точка вибуху в клітинці атласу (частка ширини зліва, висоти згори; SOURCES.md): квад
## зсунуто так, що вона лягає на точку влучання, а хмара здіймається з неї.
const EXPLOSION_BLAST := Vector2(0.508, 0.866)
const DIRT_BLAST := Vector2(0.495, 0.882)
const FLASH_BLAST := Vector2(0.479, 0.788)
## Дим кадрований майже як куля на кадрі 40 (хмара 0,68 клітинки проти 0,75): квад диму в
## SMOKE_SCALE разів більший за квад кулі, а ця точка ставить центр його хмари на центр кулі.
const SMOKE_BLAST := Vector2(0.514, 0.835)
const SMOKE_SCALE: float = 1.1

## Атласи кулі й ґрунту набирають повний об'єм на кадрі FULL_FRAME; далі LAST_FRAME вони самі
## рідшають і гаснуть до порожнечі — туди не доходимо: рівне згасання веде крива прозорості.
const FULL_FRAME: float = 16.0
const LAST_FRAME: float = 44.0
## Куля знищення: повний об'єм за 0,15 с, вогонь згасає в дим за 0,5–1,0 с, увесь дим — 6 с
## (верхня межа: справжня хмара висить і довше).
const EXPLOSION_FULL_SEC: float = 0.15
const FIRE_OUT := Vector2(0.5, 1.0)
const SMOKE_IN := Vector2(0.45, 0.9)
const EXPLOSION_SEC: float = 6.0
## Підйом клуби: швидкість на старті (м/с) спадає як e^(−t/τ) — гарячий газ спливає й гальмує.
## Висота за весь хвіст — v·τ·(1 − e^(−t/τ)), ширшання — у стільки ж кривій.
const RISE_TAU_SEC: float = 2.0
## Вітер `WeatherRig.wind()` на 1,0 зносить дим на стільки м/с (River, 0,25 — ~1 м/с, туди ж,
## куди хиляться стовпи остовів). Задає екран бою.
const DRIFT_PER_WIND: float = 4.0
static var wind: Vector3 = Vector3.ZERO

## Межу клуби з землею й корпусом м'яко гасить глибина на 1,5 м — для малої клуби на п'яту
## її кваду: інакше пилок завбільшки з метр, що цілий лежить у смузі згасання, зник би.
const HIT_SOFT_FADE: float = 1.5 / 8.0
## Спалах не вигорає в чисто біле: перші ~4 кадри — з цією часткою підсилення.
const FLASH_EARLY_GAIN: float = 0.55
## Світло спалаху — 3–5 кадрів.
const FLASH_SEC: float = 0.08
## Куля народжується в корпусі, ~1 м над землею: точка вибуху атласу внизу клітинки, і
## клуба здіймається з неї, накриваючи машину, а не висить над нею.
const LIFT_M: float = 1.0
## Дах корпусу, тайли (2,4 м): клуба влучання в броню виходить звідси, а не з середини корпусу,
## де корпус її б і сховав.
const ROOF: float = 2.4 / 8.0
## Квади влучання в броню посунуто до камери на півкорпусу з запасом (4 м): квад, що стоїть у центрі
## корпусу, корпус і закрив би — від клуби лишалась би цятка над дахом.
const ARMOUR_PULL: float = 0.5

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
	_fireball(root, size * 8.0, Vector3.ZERO, LIFT_M / 8.0, EXPLOSION_SEC, 2.0, 0.7)
	var flash := _sprite(root, "Flash", FLASH_TEX, Vector2(4, 4), 16, size * 0.5 * FLASH_CELL_M / FLASH_CORE_M, LIFT_M / 8.0, 2.5, true)
	_soft_flash(flash)
	_play(root, flash, FLASH_FIRST, 16, FLASH_FPS, 0.0)
	_light(root, 10.0, 6.0)
	# Корпус рветься: темні шматки 0,3–1 м летять на 5–15 м, і жменя палаючих уламків на дугах.
	var m: float = size * 8.0
	_debris(root, m, 0.3 * m / 12.0, 1.0 * m / 12.0, 12 + roundi(m))
	_sparks(root, "Embers", roundi(4.0 + m * 0.6), Vector3(0, LIFT_M / 8.0, 0), 6.0 * sqrt(m / 12.0), 13.0 * sqrt(m / 12.0), 0.35, 0.7, 0.9, 1.6, 55.0, 0.0, true)
	_expire(root, EXPLOSION_SEC)
	return root


## Розігрів на старті бою: перша куля, іскри й грудки інакше чекають на компіляцію шейдерів
## 0,2–1 с, і кадр застигає саме на першому вбивстві чи влучанні. Усе невидимо мале, світло
## вимкнене; звільняє себе сама.
static func warm_up(parent: Node, at: Vector3) -> Node3D:
	var boom: Node3D = spawn_explosion(parent, at, 0.0001)
	for hit: Node3D in [boom, spawn_hit(parent, at, Weapon.TANK_GUN, true), spawn_hit(parent, at, Weapon.SHELL, false)]:
		hit.scale = Vector3.ONE * 0.0001
		for l: Node in hit.find_children("*", "OmniLight3D", true, false):
			(l as OmniLight3D).light_energy = 0.0
			(l as OmniLight3D).visible = false
		# Розмір частинки масштаб кореня не зменшує: на першому юніті лишалась біла риска.
		for e: Node in hit.find_children("*", "GPUParticles3D", true, false):
			var pm := (e as GPUParticles3D).process_material as ParticleProcessMaterial
			pm.scale_min = 0.0001
			pm.scale_max = 0.0001
			pm.initial_velocity_min = 0.0
			pm.initial_velocity_max = 0.0
	return boom


## Прибрати всі миті з дерева (передача ходу, §3.5).
static func clear_all(tree: SceneTree) -> void:
	for n: Node in tree.get_nodes_in_group(GROUP):
		n.queue_free()


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


## Діаметр клуби влучання, метри (1 тайл = 8 м): по броні — сіра клуба диму й пилу з корпусу,
## по ґрунту — викид землі.
static func hit_cloud_m(weapon: Weapon, armoured: bool) -> float:
	match weapon:
		Weapon.AUTOCANNON:
			return 2.5
		Weapon.TANK_GUN:
			return 5.0 if armoured else 6.0
		Weapon.SHELL:
			return 12.0
		Weapon.DRONE:
			return 6.0
	return 1.2


## Скільки живе клуба влучання від спалаху до повного розсіяння, с: більший вибух висить довше.
static func smoke_sec(weapon: Weapon, armoured: bool) -> float:
	match weapon:
		Weapon.AUTOCANNON:
			return 3.0
		Weapon.TANK_GUN:
			return 3.5 if armoured else 4.5
		Weapon.SHELL:
			return 6.0
		Weapon.DRONE:
			return 4.5
	return 0.0 if armoured else 1.5


## Влучання по цілі. `armoured` — техніка: по броні біло-жовті іскри, що розлітаються й
## холонуть, малий спалах і сіра клуба; по піхоті й землі — порох і ґрунт.
static func spawn_hit(parent: Node, at: Vector3, weapon: Weapon, armoured: bool) -> Node3D:
	var root := _root("Hit", parent, at)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(at)
	var cloud: float = hit_cloud_m(weapon, armoured)
	var life: float = smoke_sec(weapon, armoured)
	match weapon:
		Weapon.RIFLE:
			if armoured:
				# Іскри 2–3 чергами за 0,8 с; на далекому зумі — кілька рисок.
				for burst in 3:
					_sparks(root, "Sparks", 3, Vector3(0, ROOF, 0), 6.0, 12.0, 0.4, 0.8, 0.12, 0.25, 70.0, burst * 0.3)
			else:
				# 6–12 порохових фонтанчиків на ділянці 4 × 4 м довкола: кожен підскакує й осідає.
				for i in 9:
					var o := Vector3(rng.randf_range(-0.25, 0.25), 0.0, rng.randf_range(-0.25, 0.25))
					_dirt(root, rng.randf_range(1.2, 2.0), o, rng.randf_range(0.0, 0.8), 0.1, life, 0.5, 0.4)
		Weapon.AUTOCANNON:
			for r in 4:
				var o := Vector3(rng.randf_range(-0.12, 0.12), ROOF if armoured else 0.0, rng.randf_range(-0.12, 0.12))
				_flash(root, 1.0 if armoured else 0.8, o, r * 0.12)
				if armoured:
					_sparks(root, "Sparks", 5, o, 8.0, 16.0, 1.0, 1.8, 0.12, 0.3, 65.0, r * 0.12)
					_puff(root, cloud, o, r * 0.12, 0.1, life, 0.8, 0.6)
				else:
					_dirt(root, cloud, o, r * 0.12, 0.1, life, 0.8, 0.5)
		Weapon.TANK_GUN:
			_flash(root, 3.0, Vector3(0, ROOF, 0), 0.0)
			_light(root, 10.0, 4.0)
			if armoured:
				_sparks(root, "Sparks", 18, Vector3(0, ROOF, 0), 12.0, 26.0, 1.0, 2.5, 0.15, 0.4, 70.0, 0.0)
				# Дим іде за вогнем: клуба проступає, коли куля вже на піку.
				_puff(root, cloud, Vector3(0, ROOF, 0), 0.15, 0.12, life, 1.5, 0.75)
				# Вогняна куля на корпусі 4,5 м, що гасне за 0,6 с (120 мм по башті: 4,3 м на +0,12 с); яскравіша
				# за атлас, бо мала куля на тлі корпусу інакше читається темною.
				var ball := _sprite(root, "Ball", EXPLOSION_TEX, Vector2(8, 8), 64, 4.5 * EXPLOSION_CELL_M / EXPLOSION_BALL_M / 8.0, 0.0, 1.6, false)
				ball.position = Vector3(0, ROOF, 0)
				# Вогонь — поверх сірої клуби, що народжується в тій самій точці.
				ball.sorting_offset = 1.0
				_play_smoke(root, ball, snap_tau(0.1, 0.0, 30.0), 0.6, 0.0, 1.5, 0.3, 1.0, Vector2(0.0, 30.0), Vector2.ZERO, 0.2)
			else:
				_dirt(root, cloud, Vector3.ZERO, 0.0, 0.15, life, 1.5, 0.6)
				_core(root, cloud, 0.6 * life, 1.5, 0.6)
				_debris(root, cloud)
		Weapon.SHELL:
			_flash(root, 3.5, Vector3(0, 0.2, 0), 0.0)
			_light(root, 15.0, 4.0)
			_dirt(root, cloud, Vector3.ZERO, 0.0, 0.2, life, 2.0, 0.5)
			_core(root, cloud, 0.5 * life, 2.0, 0.5)
			_debris(root, cloud)
		Weapon.DRONE:
			# Удар згори: спалах на даху, чорна клуба на корпусі, іскри вниз і вбік, без ґрунту.
			_flash(root, 1.75, Vector3(0, ROOF + 0.05, 0), 0.0)
			_sparks(root, "Sparks", 12, Vector3(0, ROOF, 0), 8.0, 18.0, 0.8, 1.8, 0.15, 0.35, 80.0, 0.0)
			_burst(root, cloud, Vector3(0, ROOF, 0), life)
	if armoured:
		for n: Node in root.find_children("*", "MeshInstance3D", true, false):
			((n as MeshInstance3D).material_override as ShaderMaterial).set_shader_parameter("pull", ARMOUR_PULL)
	_expire(root, HIT_SEC)
	return root


## Дульний спалах біля стрільця: танк і гармата — 4 м, автогармата — три малі; після нього
## пороховий дим висить біля дула, а постріл гармати здіймає пил із землі під стволом.
## Стрілецька зброя спалаху не має: на екрані він субпіксельний. Стрільця, якого глядач не
## бачить, сюди не передають зовсім.
static func spawn_muzzle(parent: Node, shooter: Transform3D, weapon: Weapon, type_id: int = -1) -> Node3D:
	if weapon == Weapon.RIFLE or weapon == Weapon.DRONE:
		return null
	var tip: Vector3 = shooter * (UnitSilhouettes.muzzle(type_id) if type_id >= 0 else Vector3(0, 0.2, -0.6))
	var root := _root("Muzzle", parent, tip)
	if weapon == Weapon.AUTOCANNON:
		for r in 3:
			_flash(root, 0.6, Vector3.ZERO, r * 0.12)
		_puff(root, 1.2, Vector3.ZERO, 0.1, 0.08, 2.0, 0.6, 0.6)
	else:
		_flash(root, 4.0, Vector3.ZERO, 0.0)
		_puff(root, 3.0, Vector3.ZERO, 0.03, 0.08, 2.5, 0.8, 0.8)
		# Пил із землі під дулом — ударна хвиля пострілу.
		_dirt(root, 5.0, Vector3(0, -tip.y, 0), 0.0, 0.15, 3.0, 0.6, 0.6, 0.55)
	_expire(root, HIT_SEC)
	return root


## Усі атласи, на які посилаються матеріали цієї миті (для тестів і розігріву).
static func atlases_of(root: Node) -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mat := (n as MeshInstance3D).material_override as ShaderMaterial
		if mat != null and mat.get_shader_parameter("tex") != null and not out.has(mat.get_shader_parameter("tex")):
			out.append(mat.get_shader_parameter("tex"))
	return out


## Викид ґрунту чи уламків: темні шматки `s_min`–`s_max` метрів, що крутяться в балістичних
## дугах, і кілька смуг уздовж польоту. Більший вибух — більше шматків і вищий кидок. Дві
## системи частинок на вибух (по виклику малювання), матеріали й сітки спільні для всіх.
static func _debris(root: Node3D, cloud_m: float, s_min: float = 0.1, s_max: float = 0.4, count: int = -1) -> void:
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
	var clods := _debris_emitter(root, "Debris", count if count > 0 else 10 + roundi(8.0 * k), v, _clod_mesh, s_min / 8.0, s_max / 8.0, false)
	clods.position = Vector3(0, 0.02, 0)
	_debris_emitter(root, "DebrisStreaks", 2 + roundi(2.0 * k), v * 1.15, _streak_mesh, 1.0 / 8.0, 2.0 / 8.0, true)


static var _clod_mesh: BoxMesh
static var _streak_mesh: ArrayMesh
static var _spark_mesh: QuadMesh


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
	em.visibility_aabb = AABB(Vector3(-2.5, -0.2, -2.5), Vector3(5, 3, 5))
	root.add_child(em, true)
	em.emitting = true
	return em


## Розжарені іскри чи палаючі уламки: риски, витягнуті вздовж швидкості (довжина `l_min`–`l_max`
## метрів), летять віялом угору на `v_min`–`v_max` м/с під справжньою вагою й холонуть від
## біло-жовтого до темно-червоного за `t_min`–`t_max` с. Одна система частинок на віяло.
static func _sparks(root: Node3D, node_name: String, amount: int, at: Vector3, v_min: float, v_max: float, l_min: float, l_max: float, t_min: float, t_max: float, spread: float, delay: float, embers: bool = false) -> GPUParticles3D:
	if _spark_mesh == null:
		_spark_mesh = QuadMesh.new()
		# Ширина — 9 % довжини: дво-метрова іскра на зумі 8 — 2–3 пікселі завширшки; тонша
		# зливалась із тлом.
		_spark_mesh.size = Vector2(0.09, 1.0)
		var mat := ShaderMaterial.new()
		mat.shader = Shader.new()
		mat.shader.code = _SPARK_CODE
		_spark_mesh.material = mat
	var em := GPUParticles3D.new()
	em.name = node_name
	em.amount = amount
	em.lifetime = t_max
	em.one_shot = true
	em.explosiveness = 1.0
	em.local_coords = false
	em.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	em.position = at
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = spread
	pm.initial_velocity_min = v_min / 8.0
	pm.initial_velocity_max = v_max / 8.0
	pm.gravity = Vector3(0.0, -9.8 / 8.0, 0.0)
	pm.damping_min = 0.5 / 8.0
	pm.damping_max = 2.0 / 8.0
	pm.scale_min = l_min / 8.0
	pm.scale_max = l_max / 8.0
	pm.lifetime_randomness = 1.0 - t_min / t_max
	var ramp := Gradient.new()
	if embers:
		# Палаючий уламок: помаранчевий, тьмяніє до темно-червоного, тягне за собою димок.
		ramp.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
		ramp.colors = PackedColorArray([Color(1.0, 0.75, 0.35, 1.0), Color(1.0, 0.42, 0.1, 0.8), Color(0.45, 0.08, 0.02, 0.0)])
	else:
		ramp.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
		ramp.colors = PackedColorArray([Color(1.0, 0.95, 0.8, 1.0), Color(1.0, 0.75, 0.4, 0.9), Color(0.9, 0.25, 0.05, 0.0)])
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	pm.color_ramp = rt
	em.process_material = pm
	em.draw_pass_1 = _spark_mesh
	em.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	em.layers = 1 << (UnitView.UNIT_LAYER - 1)
	em.visibility_aabb = AABB(Vector3(-3, -0.5, -3), Vector3(6, 4, 6))
	root.add_child(em, true)
	em.emitting = delay <= 0.0
	if delay > 0.0:
		root.create_tween().tween_callback(func() -> void: em.emitting = true).set_delay(delay)
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
	root.add_to_group(GROUP)
	# Читабельне ім'я (Hit2, Explosion3): поруч із ще не звільненою миттю рушій інакше дав би @Node3D@.
	parent.add_child(root, true)
	return root


static func _expire(root: Node3D, sec: float) -> void:
	var tw: Tween = root.create_tween()
	tw.tween_interval(sec)
	tw.tween_callback(root.queue_free)


## Спалах: ядро `core_m` метрів.
static func _flash(root: Node3D, core_m: float, offset: Vector3, delay: float) -> void:
	var q := _sprite(root, "Flash", FLASH_TEX, Vector2(4, 4), 16, core_m * FLASH_CELL_M / FLASH_CORE_M / 8.0, 0.0, 2.5, true)
	_soft_flash(q)
	q.position = offset
	_play(root, q, FLASH_FIRST, 16, FLASH_FPS, delay)


## Вогняна куля `ball_m` метрів, що перетікає в темний дим: куля набирає об'єм за 0,15 с і
## гасне за FIRE_OUT, дим проступає за SMOKE_IN і живе до `life` с. Обидва квади рухаються
## однією кривою, тож це одна клуба, а не дві.
static func _fireball(root: Node3D, ball_m: float, offset: Vector3, lift: float, life: float, rise: float, grow: float) -> void:
	var side: float = ball_m * EXPLOSION_CELL_M / EXPLOSION_BALL_M / 8.0
	var ball := _sprite(root, "Ball", EXPLOSION_TEX, Vector2(8, 8), 64, side, lift, 1.0, false)
	ball.position = offset
	_play_smoke(root, ball, snap_tau(EXPLOSION_FULL_SEC, 0.0, 44.0), FIRE_OUT.y, 0.0, rise, grow, 1.0, Vector2(0.0, 44.0), Vector2.ZERO, FIRE_OUT.x)
	var smoke := _sprite(root, "Smoke", SMOKE_TEX, Vector2(8, 8), 64, side * SMOKE_SCALE, lift, 1.0, false)
	smoke.position = offset
	_play_smoke(root, smoke, life * 0.6, life, 0.0, rise, grow, 1.0, Vector2(6.0, 44.0), SMOKE_IN, SMOKE_IN.y)


## Клуба вибуху з кулею `ball_m` метрів, що живе `life` с.
static func _burst(root: Node3D, ball_m: float, offset: Vector3, life: float) -> void:
	_fireball(root, ball_m, offset, 0.0, life, 1.5, 0.7)


## Хмара ґрунту `cloud_m` метрів: повний об'єм за `full` с, живе `life` с, здіймається на
## `rise` м/с і ширшає на частку `grow`.
static func _dirt(root: Node3D, cloud_m: float, offset: Vector3, delay: float, full: float, life: float, rise: float, grow: float, opacity: float = 1.0) -> void:
	var q := _sprite(root, "Dirt", DIRT_TEX, Vector2(8, 8), 64, cloud_m * DIRT_CELL_M / DIRT_CLOUD_M / 8.0, 0.0, 1.0, false)
	q.position = offset
	_play_smoke(root, q, snap_tau(full, 0.0, LAST_FRAME), life, delay, rise, grow, opacity)


## Чорне ядро фугасного розриву в ґрунті: 155 мм на +0,1 с — чорна куля, і лише за 1–2 с її
## розбавляє бурий пил. Квад диму на 0,8 хмари ґрунту, поверх неї, з'являється за 0,05–0,15 с і
## розчиняється за `life` с; рухається тією ж кривою, що й хмара.
static func _core(root: Node3D, cloud_m: float, life: float, rise: float, grow: float) -> void:
	var side: float = 0.8 * cloud_m * DIRT_CELL_M / DIRT_CLOUD_M / 8.0
	var q := _sprite(root, "Core", SMOKE_TEX, Vector2(8, 8), 64, side, 0.0, 1.0, false)
	# Ядро малюється поверх ґрунту, хоча стоїть у тій самій точці.
	q.sorting_offset = 1.0
	_play_smoke(root, q, life, life, 0.0, rise, grow, 0.9, Vector2(4.0, 30.0), Vector2(0.05, 0.15), 0.15)


## Сіра клуба диму й окалини (влучання в броню, пороховий дим біля дула): той самий атлас
## ґрунту, знебарвлений і трохи світліший.
static func _puff(root: Node3D, cloud_m: float, offset: Vector3, delay: float, full: float, life: float, rise: float, grow: float) -> void:
	var q := _sprite(root, "Puff", DIRT_TEX, Vector2(8, 8), 64, cloud_m * DIRT_CELL_M / DIRT_CLOUD_M / 8.0, 0.0, 1.0, false)
	q.position = offset
	var mat := q.material_override as ShaderMaterial
	mat.set_shader_parameter("desat", 1.0)
	mat.set_shader_parameter("gain", 1.15)
	_play_smoke(root, q, snap_tau(full, 0.0, LAST_FRAME), life, delay, rise, grow)


static func _soft_flash(q: MeshInstance3D) -> void:
	var mat := q.material_override as ShaderMaterial
	mat.set_shader_parameter("early_gain", FLASH_EARLY_GAIN)
	mat.set_shader_parameter("cool_edge", 1.0)


## Зсув центру кваду від точки влучання, у частках кваду (x — праворуч на екрані, y — угору):
## точка вибуху атласу лягає на точку влучання.
static func anchor_of(tex: Texture2D) -> Vector2:
	var blast := Vector2(0.5, 0.5)
	if tex == EXPLOSION_TEX:
		blast = EXPLOSION_BLAST
	elif tex == DIRT_TEX:
		blast = DIRT_BLAST
	elif tex == FLASH_TEX:
		blast = FLASH_BLAST
	elif tex == SMOKE_TEX:
		blast = SMOKE_BLAST
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
	mat.set_shader_parameter("desat", 0.0)
	mat.set_shader_parameter("opacity", 1.0)
	mat.set_shader_parameter("pull", 0.0)
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
	mat.set_shader_parameter("soft_fade", minf(HIT_SOFT_FADE, size * 0.2))
	# Читабельні імена (Flash2, Dirt3): рушій інакше перейменував би однойменних сусідів у @…@.
	root.add_child(mi, true)
	return mi


## Кадри `first` → frames−1 у темпі fps, далі квад ховається (атласи закінчуються порожніми).
static func _play(root: Node3D, q: MeshInstance3D, first: int, frames: int, fps: float, delay: float) -> void:
	var mat := q.material_override as ShaderMaterial
	mat.set_shader_parameter("frame", float(first))
	q.visible = delay <= 0.0
	var tw: Tween = root.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
		tw.tween_callback(func() -> void: q.visible = true)
	tw.tween_method(func(f: float) -> void: mat.set_shader_parameter("frame", f), float(first), float(frames - 1), float(frames - first) / fps)
	tw.tween_callback(func() -> void: q.visible = false)


## Клуба, що живе `life` с. Атлас іде кадрами `frames` за кривою спаду з постійною `tau`
## (`smoke_frame`): швидко на старті, ледь повзе в кінці. Прозорість — `smoke_opacity`: проступає
## за `fade_in` (нуль — одразу повна) і рівно спадає від `fade_out` с до нуля на `life`, без
## обриву. Увесь цей час квад здіймається (`rise` м/с на старті, гальмує з τ), ширшає на частку
## `grow` і зноситься вітром. Ховається, лише коли вже прозорий.
static func _play_smoke(root: Node3D, q: MeshInstance3D, tau: float, life: float, delay: float, rise: float, grow: float, opacity: float = 1.0, frames: Vector2 = Vector2(0.0, LAST_FRAME), fade_in: Vector2 = Vector2.ZERO, fade_out: float = 0.0) -> void:
	var mat := q.material_override as ShaderMaterial
	mat.set_shader_parameter("opacity", opacity * smoke_opacity(0.0, life, fade_in, fade_out))
	mat.set_shader_parameter("frame", frames.x)
	q.visible = delay <= 0.0
	var base: Vector3 = q.position
	var drift: Vector3 = wind * DRIFT_PER_WIND
	var step := func(t: float) -> void:
		mat.set_shader_parameter("frame", smoke_frame(t, tau, life, frames))
		mat.set_shader_parameter("opacity", opacity * smoke_opacity(t, life, fade_in, fade_out))
		q.position = base + Vector3(0.0, rise_m(rise, t), 0.0) / 8.0 + drift * (t - (1.0 - exp(-t))) / 8.0
		q.scale = Vector3.ONE * smoke_scale(grow, t)
	var tw: Tween = root.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
		tw.tween_callback(func() -> void: q.visible = true)
	tw.tween_method(step, 0.0, life, life)
	tw.tween_callback(func() -> void: q.visible = false)


## Постійна спаду, з якою атлас від кадру `f0` доходить до кадру повного об'єму (FULL_FRAME) за
## `full` с на шляху до кадру `f1`.
static func snap_tau(full: float, f0: float, f1: float) -> float:
	return -full / log(1.0 - (FULL_FRAME - f0) / (f1 - f0))


## Кадр атласу клуби на `t` с: спад від `frames.x` до `frames.y` як 1 − e^(−t/τ), нормований
## так, що на `life` — рівно `frames.y`.
static func smoke_frame(t: float, tau: float, life: float, frames: Vector2 = Vector2(0.0, LAST_FRAME)) -> float:
	return lerpf(frames.x, frames.y, (1.0 - exp(-t / tau)) / (1.0 - exp(-life / tau)))


## Прозорість клуби на `t` с: проступає за `fade_in` (від x до y с), тримається, від `fade_out`
## рівно спадає й лягає в нуль на `life` без зламу (нахил 0 на обох кінцях).
static func smoke_opacity(t: float, life: float, fade_in: Vector2 = Vector2.ZERO, fade_out: float = 0.0) -> float:
	var a: float = smoothstep(fade_in.x, fade_in.y, t) if fade_in.y > 0.0 else 1.0
	return a * (1.0 - smoothstep(fade_out, life, t))


## Ширшання клуби на `t` с: 1 → 1 + grow тією ж кривою, що й підйом.
static func smoke_scale(grow: float, t: float) -> float:
	return 1.0 + grow * (1.0 - exp(-t / RISE_TAU_SEC))


## Висота підйому клуби за `t` с, метри (для тестів і вимірів).
static func rise_m(rise: float, t: float) -> float:
	return rise * RISE_TAU_SEC * (1.0 - exp(-t / RISE_TAU_SEC))


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


## Риска іскри вздовж швидкості: колір і згасання — з рампи частинки; яскравіша в середині,
## тьмяніє до кінців і до країв, тож не читається прямокутником.
const _SPARK_CODE: String = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

void fragment() {
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	float along = sin(UV.y * 3.14159);
	ALBEDO = COLOR.rgb * COLOR.a * 2.5 * across * sqrt(along);
}
"""


## Квад флипбука в камеру. Колір і пряма альфа — з самого атласу (він уже освітлений і
## розфарбований); між кадрами — плавний перехід, бо один кадр атласу триває кілька кадрів
## екрана. `gain` > 1 — для спалаху: він мусить бути найяскравішим на екрані.
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
// Спалах: перші ~4 кадри — з такою часткою підсилення (без чисто білої плями), а край, де
// альфа спадає, холоне до #B8400F. Клуби — без цього.
uniform float early_gain = 1.0;
uniform float cool_edge = 0.0;
// Сіра клуба з бурого атласу ґрунту: 1 — повністю знебарвлена.
uniform float desat = 0.0;
// Прозорість усієї клуби (пил під дулом легший за викид снаряда).
uniform float opacity = 1.0;
// Зсув до камери, тайли: клуба влучання стоїть перед корпусом, а не в ньому.
uniform float pull = 0.0;
// Сонце (WeatherRig): освітлений бік клуби світліший на ясних мапах; у похмурі — нічого.
global uniform vec3 sun_dir;
global uniform float sky_clear;
varying vec2 v_sun;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
// М'які краї (1,2 м) лише там, де квад врізається в землю чи корпус.
uniform float soft_fade = 0.15;

void vertex() {
	float s = size * length(MODEL_MATRIX[0].xyz);
	vec3 c = MODEL_MATRIX[3].xyz + vec3(0.0, lift, 0.0) + INV_VIEW_MATRIX[2].xyz * pull + (INV_VIEW_MATRIX[0].xyz * anchor.x + INV_VIEW_MATRIX[1].xyz * anchor.y) * s;
	vec3 world = c + (INV_VIEW_MATRIX[0].xyz * VERTEX.x + INV_VIEW_MATRIX[1].xyz * VERTEX.y) * s;
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
	rgb = mix(rgb, vec3(dot(rgb, vec3(0.2126, 0.7152, 0.0722))), desat);
	ALBEDO = rgb * gain * mix(early_gain, 1.0, smoothstep(0.0, 4.0, frame)) * (1.0 + 0.45 * sky_clear * lit);
	ALPHA = t.a * opacity;
	// shortcut: глибина в NDC як у Vulkan (Forward+/Mobile); Compatibility дає z*2-1, краї там будуть жорсткіші.
	vec4 sv = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, texture(depth_tex, SCREEN_UV).r, 1.0);
	ALPHA *= clamp((VERTEX.z - sv.z / sv.w) / soft_fade, 0.0, 1.0);
}
"""
