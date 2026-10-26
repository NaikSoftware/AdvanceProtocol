class_name BattleFx
extends RefCounted
## Одноразові миті бою: вогняна куля знищеної техніки, влучання за класом зброї, дульний
## спалах. Клуби — запечені флипбуки (assets/vfx/, симуляції з SOURCES.md) на квадах, що
## дивляться в камеру; гаряче ядро спалаху й кільце пилу — процедурні квади; іскри, грудки
## й уламки — частинки. Кожна мить крутить власний твін і звільняє себе сама: `emitting = false`
## чи схований вузол лишали б її в кадрі й у дереві.
##
## Дим після вибуху не зникає на місці. Вибух різкий: клуба набирає ~80 % об'єму за
## 0,1–0,2 с, далі довга повільна фаза — атлас повзе до кінця життя, клуба здіймається з
## уповільненням, але не зупиняється, ширшає, зноситься вітром і розчиняється за 3–6 с:
## спершу рідкі краї, потім густе ядро (ерозія за шумом, а не множення всієї хмари). Кінець
## задає ця крива, а не останній кадр атласу. Програвач на це не чекає (HIT_HOLD_SEC).
##
## Випадковість тут лише косметична (розкид клубів і частинок) і береться з хешу місця, а не з
## `Rules.roll()`: косметика не сміє зсувати кидки правил.

enum Weapon { RIFLE, AUTOCANNON, TANK_GUN, SHELL, DRONE }

## Мить влучання й дульний спалах звільняються не пізніше цього: найдовший дим (снаряд, 6 с)
## і запас.
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
## вогонь згас, і саме він висить, здіймається й розчиняється.
const SMOKE_TEX: Texture2D = preload("res://assets/vfx/smoke_column.png")

## Атласи (кадрів, сітка, метрів у клітинці) — за SOURCES.md. Вміст на піку — з виміряних
## кадрів: куля 197 текселів із 256, ґрунт 190 із 256, спалах 112 із 192. Кожен виклик задає
## бажаний розмір вмісту в метрах; квад — у стільки ж разів більший за клітинку.
const EXPLOSION_CELL_M: float = 21.7
const EXPLOSION_BALL_M: float = 21.7 * 197.0 / 256.0
const DIRT_CELL_M: float = 13.4
const DIRT_CLOUD_M: float = 13.4 * 190.0 / 256.0
## Спалах влучання: перші два кадри атласу — суцільний білий диск, тож починаємо з третього;
## 90 кадрів/с лишають біле ядро на ~60 мс, далі воно холоне в помаранчеве.
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

## Атласи кулі, ґрунту й диму мають ~80 % об'єму на кадрі FULL_FRAME; далі LAST_FRAME вони самі
## гаснуть до порожнечі — туди не доходимо: розчинення веде ерозія клуби.
const FULL_FRAME: float = 16.0
const LAST_FRAME: float = 44.0
## Куля знищення: повний об'єм за 0,12 с, вогонь розчиняється в дим за 0,4–1,0 с, увесь дим —
## 6 с (верхня межа: справжня хмара висить і довше).
const FIRE_SEC: float = 1.0
const EXPLOSION_SEC: float = 6.0
## Гаряче ядро спалаху — два кадри екрана.
const HOT_SEC: float = 0.035
## Клуба тримає форму першу третину життя й розчиняється решту: інакше рідкі краї
## з'їдались із першої ж секунди, і клуба зникала задовго до кінця.
const ERODE_FROM: float = 0.3
## Підйом клуби: на старті `rise` м/с, швидкість спадає з τ до RISE_FLOOR від стартової —
## гарячий газ гальмує, але не зависає.
const RISE_TAU_SEC: float = 2.0
const RISE_FLOOR: float = 0.3
## Вітер `WeatherRig.wind()` на 1,0 зносить дим на стільки м/с (River, 0,25 — ~1 м/с, туди ж,
## куди хиляться стовпи остовів); швидкості вітру дим набирає за DRIFT_TAU_SEC. Задає екран бою.
const DRIFT_PER_WIND: float = 4.0
const DRIFT_TAU_SEC: float = 1.0
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
## Квади влучання в броню посунуто до камери на півкорпусу з запасом (4 м): квад у центрі
## корпусу корпус і закрив би — від клуби лишалась би цятка над дахом.
const ARMOUR_PULL: float = 0.5
## Дим не ховає сусідів: там, де клуба лягає на екранний слід видимого юніта (крім цілі), разом
## вона не густіша за 0,4. Шарів диму в одній точці до двох (куля й дим, ґрунт і чорне ядро),
## тож кожен — не густіший за OCCLUDE_ALPHA: 1 − (1 − 0,22)² ≈ 0,39. Слід — коло OCCLUDE_R тайла
## довкола середини корпусу.
const OCCLUDE_ALPHA: float = 0.22
const OCCLUDE_R: float = 0.45
const OCCLUDE_MAX: int = 6
## Порядок прозорих квадів у тій самій точці: ґрунт, під ним гаряче ядро, над ними чорне ядро
## й вогняна куля.
const PRIORITY_HOT: int = 1
const PRIORITY_CORE: int = 2

static var _mix_shader: Shader
static var _add_shader: Shader
static var _hot_shader: Shader
static var _ring_shader: Shader
static var _quad: QuadMesh


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
	var m: float = size * 8.0
	_fireball(root, m, Vector3.ZERO, LIFT_M / 8.0, EXPLOSION_SEC, 2.0, 0.7)
	# Ядро — поверх кулі: перші кадри кулі кремові, ядро робить їх біло-жовтими з помаранчевим краєм.
	_hot(root, m * 0.5, Vector3(0, LIFT_M / 8.0 + 0.25, 0), 0.0, PRIORITY_CORE + 1)
	# Корпус ще стоїть: без зсуву до камери він закрив би ядро.
	((root.get_node("Hot") as MeshInstance3D).material_override as ShaderMaterial).set_shader_parameter("pull", 0.6)
	_light(root, 10.0, 6.0)
	# Корпус рветься: темні уламки 0,2–0,7 м летять на 5–15 м, і жменя палаючих шматків на дугах.
	_debris(root, m, 0.2 * m / 12.0, 0.7 * m / 12.0, 12 + roundi(m), true)
	_sparks(root, "Embers", roundi(4.0 + m * 0.6), Vector3(0, LIFT_M / 8.0, 0), Vector3.UP, 55.0, 6.0 * sqrt(m / 12.0), 13.0 * sqrt(m / 12.0), 0.35, 0.7, 0.9, 1.6, 0.0, true)
	_shield(root, parent, at)
	_expire(root, EXPLOSION_SEC)
	return root


## Розігрів на старті бою: перша куля, іскри, грудки, ядро й кільце пилу інакше чекають на
## компіляцію шейдерів 0,2–1 с, і кадр застигає саме на першому вбивстві чи влучанні. Усе
## невидимо мале, світло вимкнене; звільняє себе сама.
static func warm_up(parent: Node, at: Vector3) -> Node3D:
	var boom: Node3D = spawn_explosion(parent, at, 0.0001)
	var all: Array[Node3D] = [boom, spawn_hit(parent, at, Weapon.TANK_GUN, true), spawn_hit(parent, at, Weapon.SHELL, false), spawn_muzzle(parent, Transform3D(Basis(), at), Weapon.TANK_GUN)]
	for hit: Node3D in all:
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


## Скільки живе клуба влучання від спалаху до повного розчинення, с: більший вибух висить довше.
static func smoke_sec(weapon: Weapon, armoured: bool) -> float:
	match weapon:
		Weapon.AUTOCANNON:
			return 3.5 if armoured else 3.0
		Weapon.TANK_GUN:
			return 4.0 if armoured else 4.5
		Weapon.SHELL:
			return 6.0
		Weapon.DRONE:
			return 4.5
	return 0.0 if armoured else 1.5


## Найпізніший старт клуби в миті, с (черга автогармати, порох куль).
static func smoke_delay(weapon: Weapon, armoured: bool) -> float:
	match weapon:
		Weapon.AUTOCANNON:
			return 3.0 * 0.12
		Weapon.RIFLE:
			return 0.0 if armoured else 0.8
	return 0.0


## Влучання по цілі. `armoured` — техніка: по броні розжарені іскри, малий спалах і сіра клуба;
## по піхоті й землі — порох і ґрунт.
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
					_sparks(root, "Sparks", rng.randi_range(2, 4), Vector3(0, ROOF, 0), _ricochet(rng), 60.0, 5.0, 10.0, 0.3, 0.7, 0.12, 0.22, burst * 0.3)
			else:
				# 6–12 порохових фонтанчиків на ділянці 4 × 4 м довкола: кожен підскакує й осідає.
				for i in 9:
					var o := Vector3(rng.randf_range(-0.25, 0.25), 0.0, rng.randf_range(-0.25, 0.25))
					_dirt(root, rng.randf_range(1.2, 2.0), o, rng.randf_range(0.0, smoke_delay(weapon, armoured)), 0.08, life, 0.4, 0.4)
		Weapon.AUTOCANNON:
			for r in 4:
				var o := Vector3(rng.randf_range(-0.12, 0.12), ROOF if armoured else 0.0, rng.randf_range(-0.12, 0.12))
				_flash(root, 1.0 if armoured else 0.8, o, r * 0.12)
				if armoured:
					_sparks(root, "Sparks", rng.randi_range(3, 6), o, _ricochet(rng), 60.0, 6.0, 12.0, 0.5, 1.2, 0.15, 0.25, r * 0.12)
					_puff(root, cloud, o, r * 0.12, 0.1, life, 0.6, 0.6)
				else:
					_dirt(root, cloud, o, r * 0.12, 0.1, life, 0.6, 0.5)
		Weapon.TANK_GUN:
			_flash(root, 3.0, Vector3(0, ROOF if armoured else 0.15, 0), 0.0)
			_light(root, 10.0, 4.0)
			if armoured:
				_sparks(root, "Sparks", rng.randi_range(12, 20), Vector3(0, ROOF, 0), _ricochet(rng), 55.0, 8.0, 16.0, 0.6, 1.8, 0.15, 0.3, 0.0)
				# Вогняна куля на корпусі 4,5 м, що розчиняється за 0,6 с (120 мм по башті: 4,3 м на
				# +0,12 с), над сірою клубою, що за 0,15 с уже майже повна (там само, нижче за порядком).
				var ball := _sprite(root, "Ball", EXPLOSION_TEX, 64, 4.5 * EXPLOSION_CELL_M / EXPLOSION_BALL_M / 8.0, 0.0, 1.6, false)
				ball.position = Vector3(0, ROOF, 0)
				(ball.material_override as ShaderMaterial).render_priority = PRIORITY_CORE
				(ball.material_override as ShaderMaterial).set_shader_parameter("warm", 1.0)
				_play_smoke(root, ball, 0.08, 0.6, 0.0, 1.0, 0.3, Vector2(0.0, 30.0), Vector2.ZERO, 0.15)
				_puff(root, cloud, Vector3(0, ROOF, 0), 0.0, 0.12, life, 1.0, 0.75)
			else:
				_hot(root, 4.0, Vector3(0, 0.1, 0))
				_dirt(root, cloud, Vector3.ZERO, 0.0, 0.15, life, 1.5, 0.6)
				_core(root, cloud, 0.6 * life, 1.5, 0.6)
				_ring(root, 8.0, Vector3.ZERO, 2.5, 0.8)
				_debris(root, cloud)
		Weapon.SHELL:
			_hot(root, 5.0, Vector3(0, 0.12, 0))
			_light(root, 15.0, 4.0)
			_dirt(root, cloud, Vector3.ZERO, 0.0, 0.2, life, 2.0, 0.5)
			_core(root, cloud, 0.5 * life, 2.0, 0.5)
			_ring(root, 16.0, Vector3.ZERO, 3.5, 0.9)
			_debris(root, cloud)
		Weapon.DRONE:
			# Удар згори: гаряче ядро на даху, чорна клуба на корпусі, іскри вниз і вбік, без ґрунту.
			_hot(root, 3.0, Vector3(0, ROOF + 0.05, 0), 0.0, PRIORITY_CORE + 1)
			_sparks(root, "Sparks", rng.randi_range(8, 14), Vector3(0, ROOF, 0), _ricochet(rng), 75.0, 6.0, 14.0, 0.5, 1.4, 0.15, 0.3, 0.0)
			_fireball(root, cloud, Vector3(0, ROOF, 0), 0.0, life, 1.0, 0.7)
	if armoured:
		for n: Node in root.find_children("*", "MeshInstance3D", true, false):
			((n as MeshInstance3D).material_override as ShaderMaterial).set_shader_parameter("pull", ARMOUR_PULL)
	_shield(root, parent, at)
	_expire(root, HIT_SEC)
	return root


## Дульний спалах біля стрільця: танк і гармата — жовто-біле гаряче ядро на два кадри, сіро-
## бежевий пороховий дим уздовж осі ствола й низьке кільце пилу на землі під дулом; автогармата —
## три малі ядра й клубок диму. Стрілецька зброя спалаху не має: на екрані він субпіксельний.
## Стрільця, якого глядач не бачить, сюди не передають зовсім.
static func spawn_muzzle(parent: Node, shooter: Transform3D, weapon: Weapon, type_id: int = -1) -> Node3D:
	if weapon == Weapon.RIFLE or weapon == Weapon.DRONE:
		return null
	var tip: Vector3 = shooter * (UnitSilhouettes.muzzle(type_id) if type_id >= 0 else Vector3(0, 0.2, -0.6))
	var root := _root("Muzzle", parent, tip)
	var axis: Vector3 = Vector3(-shooter.basis.z.x, 0.0, -shooter.basis.z.z).normalized()
	if weapon == Weapon.AUTOCANNON:
		for r in 3:
			_hot(root, 0.8, Vector3.ZERO, r * 0.12)
		_powder(root, 1.2, axis * 0.06, 0.1, 2.0)
	else:
		_hot(root, 2.5, axis * 0.05)
		# Пороховий дим — три клуби вздовж ствола, 0,4–2,4 м від дула, що ширшають і здіймаються.
		for i in 3:
			_powder(root, 1.6 + 0.6 * i, axis * (0.05 + 0.125 * i), 0.02 * i, 2.5)
		# Ударна хвиля пострілу здіймає пил: низьке кільце 1,25 клітинки на землі під дулом.
		_ring(root, 10.0, Vector3(0, -tip.y + shooter.origin.y + 0.03, 0), 1.8, 0.7)
	_shield(root, parent, shooter.origin)
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


## Напрям рикошету: вгору й убік на випадковий кут — віяло летить в один бік, а не зіркою.
static func _ricochet(rng: RandomNumberGenerator) -> Vector3:
	return Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(0.5, 1.2), rng.randf_range(-1.0, 1.0)).normalized()


## Викид ґрунту чи уламків: шматки `s_min`–`s_max` метрів неправильної форми летять
## балістичними дугами, падають на землю, лежать і за останні 0,5 с осідають; плюс кілька
## смуг пилу вздовж польоту. Життя — з часу польоту 2v/g, тож у повітрі ніщо не зникає.
static func _debris(root: Node3D, cloud_m: float, s_min: float = 0.1, s_max: float = 0.4, count: int = -1, scrap: bool = false) -> void:
	var k: float = clampf((cloud_m - 3.5) / 8.5, 0.0, 1.0)
	# Злітає вище за хмару ґрунту (снаряд — ~10 м, гармата по ґрунту — ~3 м) і падає за її
	# краєм: усередині клуби грудок не видно.
	var v_ms: float = sqrt(2.0 * 9.8 * cloud_m * 0.85)
	var flight: float = debris_flight_sec(v_ms)
	var clods := _debris_emitter(root, "Debris", count if count > 0 else 10 + roundi(8.0 * k), v_ms / 8.0, _chunk(scrap), s_min / 8.0, s_max / 8.0, flight + 0.6)
	clods.position = Vector3(0, 0.02, 0)
	var floor_box := GPUParticlesCollisionBox3D.new()
	floor_box.name = "Ground"
	floor_box.size = Vector3(6.0, 0.5, 6.0)
	floor_box.position = Vector3(0, -0.25, 0)
	root.add_child(floor_box)
	var streaks := _debris_emitter(root, "DebrisStreaks", 2 + roundi(2.0 * k), v_ms * 1.15 / 8.0, _streak(), 1.0 / 8.0, 2.0 / 8.0, flight * 0.6)
	var spm := streaks.process_material as ParticleProcessMaterial
	spm.particle_flag_align_y = true
	spm.collision_mode = ParticleProcessMaterial.COLLISION_DISABLED
	var fade := Gradient.new()
	fade.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var ft := GradientTexture1D.new()
	ft.gradient = fade
	spm.color_ramp = ft


## Час польоту шматка, кинутого вгору на `v_ms` м/с, до повернення на землю, с.
static func debris_flight_sec(v_ms: float) -> float:
	return 2.0 * v_ms / 9.8


static var _clod_mesh: ArrayMesh
static var _scrap_mesh: ArrayMesh
static var _streak_mesh: ArrayMesh
static var _spark_mesh: QuadMesh


## Неправильний гранчастий шматок (розтягнутий і зім'ятий октаедр-сфера): грудка землі чи
## уламок металу — не кубик.
static func _chunk(scrap: bool) -> ArrayMesh:
	if (_scrap_mesh if scrap else _clod_mesh) != null:
		return _scrap_mesh if scrap else _clod_mesh
	var src := SphereMesh.new()
	src.radius = 0.5
	src.height = 0.7
	src.radial_segments = 6
	src.rings = 3
	var arr: Array = src.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	for i in idx:
		var v: Vector3 = verts[i]
		# Той самий шум для тієї самої точки: шов сфери не рветься.
		var h: float = fposmod(sin(v.dot(Vector3(12.9898, 78.233, 37.719))) * 43758.5453, 1.0)
		st.add_vertex(v * (0.7 + 0.6 * h) * Vector3(1.0, 0.8, 1.25))
	st.generate_normals()
	var mesh: ArrayMesh = st.commit()
	var m := StandardMaterial3D.new()
	if scrap:
		m.albedo_color = Color(0.075, 0.068, 0.062)
		m.metallic = 0.6
		m.roughness = 0.55
		_scrap_mesh = mesh
	else:
		m.albedo_color = Color(0.09, 0.07, 0.05)
		m.roughness = 1.0
		_clod_mesh = mesh
	mesh.surface_set_material(0, m)
	return mesh


static func _streak() -> ArrayMesh:
	if _streak_mesh == null:
		_streak_mesh = _cross_quad()
		var sm := StandardMaterial3D.new()
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.albedo_color = Color(0.05, 0.04, 0.03, 0.85)
		sm.vertex_color_use_as_albedo = true
		sm.cull_mode = BaseMaterial3D.CULL_DISABLED
		_streak_mesh.surface_set_material(0, sm)
	return _streak_mesh


static func _debris_emitter(root: Node3D, node_name: String, amount: int, v: float, mesh: Mesh, s_min: float, s_max: float, life: float) -> GPUParticles3D:
	var em := GPUParticles3D.new()
	em.name = node_name
	em.amount = amount
	em.lifetime = life
	em.one_shot = true
	em.explosiveness = 1.0
	em.randomness = 0.5
	em.local_coords = false
	em.collision_base_size = s_max * 0.4
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 60.0
	pm.initial_velocity_min = v * 0.5
	pm.initial_velocity_max = v
	# Справжня вага: шматки падають так, як падали б на 8-метровому тайлі.
	pm.gravity = Vector3(0.0, -9.8 / 8.0, 0.0)
	pm.scale_min = s_min
	pm.scale_max = s_max
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.03
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -360.0
	pm.angular_velocity_max = 360.0
	pm.particle_flag_rotate_y = true
	# Падає на землю (площина GPUParticlesCollisionBox3D під коренем) і лежить, а не тоне в ній.
	pm.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
	pm.collision_friction = 0.9
	pm.collision_bounce = 0.15
	# Останні 0,5 с шматок осідає (меншає до нуля) — не зникає одним кадром.
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 1.0))
	sc.add_point(Vector2(maxf(0.0, 1.0 - 0.5 / life), 1.0))
	sc.add_point(Vector2(1.0, 0.0))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	em.process_material = pm
	em.draw_pass_1 = mesh
	em.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	em.layers = 1 << (UnitView.UNIT_LAYER - 1)
	em.visibility_aabb = AABB(Vector3(-3, -0.5, -3), Vector3(6, 4, 6))
	root.add_child(em, true)
	em.emitting = true
	return em


## Розжарені іскри чи палаючі уламки: `amount` рисок, витягнутих уздовж швидкості (довжина
## `l_min`–`l_max` метрів), летять віялом `spread`° довкола `dir` на `v_min`–`v_max` м/с дугами
## під справжньою вагою й холонуть кольором чорного тіла: біле → жовте → помаранчеве →
## тьмяно-червоне, за `t_min`–`t_max` с. Змішування звичайне, не адитивне: над синім корпусом
## адитив давав лавандовий хвіст. Одна система частинок на віяло.
static func _sparks(root: Node3D, node_name: String, amount: int, at: Vector3, dir: Vector3, spread: float, v_min: float, v_max: float, l_min: float, l_max: float, t_min: float, t_max: float, delay: float, embers: bool = false) -> GPUParticles3D:
	if _spark_mesh == null:
		_spark_mesh = QuadMesh.new()
		# Ширина — 9 % довжини: дво-метрова іскра на зумі 8 — 2–3 пікселі завширшки.
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
	em.explosiveness = 0.9
	em.randomness = 1.0
	em.local_coords = false
	em.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	em.position = at
	var pm := ParticleProcessMaterial.new()
	pm.direction = dir
	pm.spread = spread
	pm.initial_velocity_min = v_min / 8.0
	pm.initial_velocity_max = v_max / 8.0
	pm.gravity = Vector3(0.0, -9.8 / 8.0, 0.0)
	pm.damping_min = 0.5 / 8.0
	pm.damping_max = 3.0 / 8.0
	pm.scale_min = l_min / 8.0
	pm.scale_max = l_max / 8.0
	pm.lifetime_randomness = 1.0 - t_min / t_max
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.02
	var ramp := Gradient.new()
	if embers:
		# Палаючий уламок: помаранчевий, тьмяніє до темно-червоного.
		ramp.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
		ramp.colors = PackedColorArray([Color(1.0, 0.75, 0.35, 1.0), Color(1.0, 0.42, 0.1, 0.85), Color(0.45, 0.08, 0.02, 0.0)])
	else:
		ramp.offsets = PackedFloat32Array([0.0, 0.2, 0.5, 1.0])
		ramp.colors = PackedColorArray([Color(1.0, 0.97, 0.88, 1.0), Color(1.0, 0.82, 0.35, 1.0), Color(1.0, 0.45, 0.1, 0.9), Color(0.45, 0.06, 0.02, 0.0)])
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


## Видимі юніти поруч (крім `except` — цілі чи стрільця) стають «щитом» для диму цієї миті.
static func _shield(root: Node3D, parent: Node, except: Vector3) -> void:
	var occ := PackedVector4Array()
	for c: Node in parent.get_children():
		var u := c as UnitView
		if u == null or not u.visible:
			continue
		var flat := Vector2(u.position.x - except.x, u.position.z - except.z)
		if flat.length() < 0.3 or flat.length() > 3.0 or occ.size() >= OCCLUDE_MAX:
			continue
		occ.append(Vector4(u.position.x, u.position.y + 0.15, u.position.z, OCCLUDE_R))
	var count: int = occ.size()
	if count == 0:
		return
	occ.resize(OCCLUDE_MAX)
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mat := (n as MeshInstance3D).material_override as ShaderMaterial
		if mat.shader == _mix_shader:
			mat.set_shader_parameter("occ", occ)
			mat.set_shader_parameter("occ_n", count)


## Спалах влучання: ядро `core_m` метрів.
static func _flash(root: Node3D, core_m: float, offset: Vector3, delay: float) -> void:
	var q := _sprite(root, "Flash", FLASH_TEX, 16, core_m * FLASH_CELL_M / FLASH_CORE_M / 8.0, 0.0, 2.5, true)
	var mat := q.material_override as ShaderMaterial
	mat.set_shader_parameter("grid", Vector2(4, 4))
	mat.set_shader_parameter("early_gain", FLASH_EARLY_GAIN)
	mat.set_shader_parameter("cool_edge", 1.0)
	q.position = offset
	_play(root, q, FLASH_FIRST, 16, FLASH_FPS, delay)


## Гаряче ядро спалаху `d_m` метрів: біло-жовте в середині, помаранчеве по краю, два кадри.
static func _hot(root: Node3D, d_m: float, offset: Vector3, delay: float = 0.0, priority: int = PRIORITY_HOT) -> void:
	if _hot_shader == null:
		_hot_shader = Shader.new()
		_hot_shader.code = _HOT_CODE
	var mat := ShaderMaterial.new()
	mat.shader = _hot_shader
	mat.render_priority = priority
	mat.set_shader_parameter("size", d_m / 8.0)
	mat.set_shader_parameter("seed", float(hash(root.position) % 97))
	mat.set_shader_parameter("pull", 0.0)
	var q := _quad_instance(root, "Hot", mat)
	q.position = offset
	q.visible = delay <= 0.0
	var tw: Tween = root.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
		tw.tween_callback(func() -> void: q.visible = true)
	tw.tween_method(func(f: float) -> void: mat.set_shader_parameter("heat", f), 0.0, 1.0, HOT_SEC)
	tw.tween_callback(func() -> void: q.visible = false)


## Низьке кільце пилу `d_m` метрів на землі (ударна хвиля): біжить від центру й розсіюється за
## `life` с. Пласкі квади лежать на землі, а не дивляться в камеру.
static func _ring(root: Node3D, d_m: float, offset: Vector3, life: float, opacity: float) -> void:
	if _ring_shader == null:
		_ring_shader = Shader.new()
		_ring_shader.code = _RING_CODE
	var mat := ShaderMaterial.new()
	mat.shader = _ring_shader
	mat.set_shader_parameter("size", d_m / 8.0)
	mat.set_shader_parameter("opacity", opacity)
	mat.set_shader_parameter("seed", float(hash(root.position) % 89))
	var q := _quad_instance(root, "Ring", mat)
	q.position = offset + Vector3(0, 0.02, 0)
	var tw: Tween = root.create_tween()
	tw.tween_method(func(f: float) -> void: mat.set_shader_parameter("progress", f), 0.0, 1.0, life)
	tw.tween_callback(func() -> void: q.visible = false)


## Вогняна куля `ball_m` метрів, що перетікає в темний дим: куля набирає об'єм за 0,12 с і
## розчиняється за FIRE_SEC поверх диму, а дим під нею вже повний із 0,35 с — без провалу
## «темно → світло → темно». Обидва квади рухаються однією кривою, тож це одна клуба.
static func _fireball(root: Node3D, ball_m: float, offset: Vector3, lift: float, life: float, rise: float, grow: float) -> void:
	var side: float = ball_m * EXPLOSION_CELL_M / EXPLOSION_BALL_M / 8.0
	var ball := _sprite(root, "Ball", EXPLOSION_TEX, 64, side, lift, 1.0, false)
	ball.position = offset
	var bmat := ball.material_override as ShaderMaterial
	bmat.render_priority = PRIORITY_CORE
	bmat.set_shader_parameter("warm", 1.0)
	_play_smoke(root, ball, 0.12, FIRE_SEC, 0.0, rise, grow, Vector2(0.0, LAST_FRAME), Vector2.ZERO, 0.4)
	var smoke := _sprite(root, "Smoke", SMOKE_TEX, 64, side * SMOKE_SCALE, lift, 1.0, false)
	smoke.position = offset
	_play_smoke(root, smoke, 0.3, life, 0.0, rise, grow, Vector2(6.0, LAST_FRAME), Vector2(0.1, 0.35), 0.8)


## Хмара ґрунту `cloud_m` метрів: ~80 % об'єму за `full` с, живе `life` с, здіймається на
## `rise` м/с і ширшає на частку `grow`.
static func _dirt(root: Node3D, cloud_m: float, offset: Vector3, delay: float, full: float, life: float, rise: float, grow: float) -> void:
	var q := _sprite(root, "Dirt", DIRT_TEX, 64, cloud_m * DIRT_CELL_M / DIRT_CLOUD_M / 8.0, 0.0, 1.0, false)
	q.position = offset
	_play_smoke(root, q, full, life, delay, rise, grow, Vector2(0.0, LAST_FRAME), Vector2.ZERO, ERODE_FROM * life)


## Чорне ядро фугасного розриву в ґрунті: 155 мм на +0,1 с — чорна куля, і лише за 1–2 с її
## розбавляє бурий пил. Квад диму на 0,8 хмари ґрунту, поверх неї (і поверх гарячого ядра),
## з'являється за 0,05–0,15 с і розчиняється за `life` с; рухається тією ж кривою, що й хмара.
static func _core(root: Node3D, cloud_m: float, life: float, rise: float, grow: float) -> void:
	var side: float = 0.8 * cloud_m * DIRT_CELL_M / DIRT_CLOUD_M / 8.0
	var q := _sprite(root, "Core", SMOKE_TEX, 64, side, 0.0, 1.0, false)
	(q.material_override as ShaderMaterial).render_priority = PRIORITY_CORE
	_play_smoke(root, q, 0.15, life, 0.0, rise, grow, Vector2(4.0, 30.0), Vector2(0.05, 0.15), 0.1, 0.9)


## Сіра клуба диму й окалини (влучання в броню): той самий атлас ґрунту, знебарвлений і
## трохи світліший.
static func _puff(root: Node3D, cloud_m: float, offset: Vector3, delay: float, full: float, life: float, rise: float, grow: float) -> void:
	var q := _sprite(root, "Puff", DIRT_TEX, 64, cloud_m * DIRT_CELL_M / DIRT_CLOUD_M / 8.0, 0.0, 1.15, false)
	q.position = offset
	(q.material_override as ShaderMaterial).set_shader_parameter("desat", 1.0)
	_play_smoke(root, q, full, life, delay, rise, grow, Vector2(0.0, LAST_FRAME), Vector2.ZERO, ERODE_FROM * life)


## Пороховий дим біля дула: сіро-бежевий (атлас ґрунту, знебарвлений на дві третини), повний
## за 0,06 с, повільно здіймається й розходиться.
static func _powder(root: Node3D, cloud_m: float, offset: Vector3, delay: float, life: float) -> void:
	var q := _sprite(root, "Powder", DIRT_TEX, 64, cloud_m * DIRT_CELL_M / DIRT_CLOUD_M / 8.0, 0.0, 1.25, false)
	q.position = offset
	(q.material_override as ShaderMaterial).set_shader_parameter("desat", 0.65)
	_play_smoke(root, q, 0.06, life, delay, 0.5, 0.9, Vector2(0.0, LAST_FRAME), Vector2.ZERO, 0.2 * life, 0.85)


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


## Один квад на всі ефекти: розмір і поворот до камери задає шейдер.
static func _quad_instance(root: Node3D, node_name: String, mat: ShaderMaterial) -> MeshInstance3D:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2.ONE
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = _quad
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-2, -1, -2), Vector3(4, 4, 4))
	mi.layers = 1 << (UnitView.UNIT_LAYER - 1)
	# Читабельні імена (Flash2, Dirt3): рушій інакше перейменував би однойменних сусідів у @…@.
	root.add_child(mi, true)
	return mi


static func _sprite(root: Node3D, node_name: String, tex: Texture2D, frames: int, size: float, lift: float, gain: float, additive: bool) -> MeshInstance3D:
	var mat := ShaderMaterial.new()
	mat.shader = _shader(additive)
	mat.set_shader_parameter("tex", tex)
	mat.set_shader_parameter("grid", Vector2(8, 8))
	mat.set_shader_parameter("frames", float(frames))
	mat.set_shader_parameter("frame", 0.0)
	mat.set_shader_parameter("size", size)
	mat.set_shader_parameter("lift", lift)
	mat.set_shader_parameter("gain", gain)
	mat.set_shader_parameter("early_gain", 1.0)
	mat.set_shader_parameter("cool_edge", 0.0)
	mat.set_shader_parameter("desat", 0.0)
	mat.set_shader_parameter("opacity", 1.0)
	mat.set_shader_parameter("erode", 0.0)
	mat.set_shader_parameter("warm", 0.0)
	mat.set_shader_parameter("pull", 0.0)
	mat.set_shader_parameter("occ_n", 0)
	mat.set_shader_parameter("seed", float(hash(root.position + Vector3(size, lift, frames)) % 101))
	mat.set_shader_parameter("anchor", anchor_of(tex))
	mat.set_shader_parameter("soft_fade", minf(HIT_SOFT_FADE, size * 0.2))
	return _quad_instance(root, node_name, mat)


## Кадри `first` → frames−1 у темпі fps, далі квад ховається (атлас спалаху закінчується порожнім).
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


## Клуба, що живе `life` с. Атлас — `smoke_frame`: кадри `frames` до FULL_FRAME (~80 % об'єму)
## за `full` с, далі повзе до кінця життя. Проступає за `fade_in` (нуль — одразу), розчиняється
## ерозією від `erode_from` с до `life` (`smoke_erode`). Увесь цей час квад здіймається
## (`rise_m`), ширшає (`smoke_scale`) і зноситься вітром. Ховається, лише коли вже розчинився.
static func _play_smoke(root: Node3D, q: MeshInstance3D, full: float, life: float, delay: float, rise: float, grow: float, frames: Vector2 = Vector2(0.0, LAST_FRAME), fade_in: Vector2 = Vector2.ZERO, erode_from: float = 0.0, opacity: float = 1.0) -> void:
	var mat := q.material_override as ShaderMaterial
	var base: Vector3 = q.position
	var drift: Vector3 = wind * DRIFT_PER_WIND
	var step := func(t: float) -> void:
		mat.set_shader_parameter("frame", smoke_frame(t, full, life, frames))
		mat.set_shader_parameter("opacity", opacity * (smoothstep(fade_in.x, fade_in.y, t) if fade_in.y > 0.0 else 1.0))
		mat.set_shader_parameter("erode", smoke_erode(t, life, erode_from))
		q.position = base + Vector3(0.0, rise_m(rise, t), 0.0) / 8.0 + drift * drift_m(t) / 8.0
		q.scale = Vector3.ONE * smoke_scale(grow, t)
	step.call(0.0)
	q.visible = delay <= 0.0
	var tw: Tween = root.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
		tw.tween_callback(func() -> void: q.visible = true)
	tw.tween_method(step, 0.0, life, life)
	tw.tween_callback(func() -> void: q.visible = false)


## Кадр атласу клуби на `t` с: від `frames.x` до FULL_FRAME за `full` с зі спадом (вибух різкий),
## далі до `frames.y` на `life` — ледь сповільнюючись, але не зупиняючись: клуба крутиться до кінця.
static func smoke_frame(t: float, full: float, life: float, frames: Vector2 = Vector2(0.0, LAST_FRAME)) -> float:
	var f_full: float = minf(FULL_FRAME, frames.y)
	if t < full:
		var u: float = t / full
		return lerpf(frames.x, f_full, 1.0 - (1.0 - u) * (1.0 - u))
	return lerpf(f_full, frames.y, pow(clampf((t - full) / maxf(life - full, 1e-3), 0.0, 1.0), 0.75))


## Ерозія клуби на `t` с, 0–1: нуль до `erode_from`, далі рівно до 1 на `life` без зламу.
## Шейдер з'їдає за шумовим порогом спершу рідкі краї, наостанок — густе ядро.
static func smoke_erode(t: float, life: float, erode_from: float = 0.0) -> float:
	return smoothstep(erode_from, life, t)


## Висота підйому клуби за `t` с, метри: на старті `rise` м/с, гальмує з τ до RISE_FLOOR · rise.
static func rise_m(rise: float, t: float) -> float:
	return rise * (RISE_FLOOR * t + (1.0 - RISE_FLOOR) * RISE_TAU_SEC * (1.0 - exp(-t / RISE_TAU_SEC)))


## Ширшання клуби на `t` с: 1 → 1 + grow тією ж кривою, що й підйом, і ще трохи щосекунди.
static func smoke_scale(grow: float, t: float) -> float:
	return 1.0 + grow * (1.0 - exp(-t / RISE_TAU_SEC)) + 0.04 * t


## Знесення вітром за `t` с у метрах на 1 м/с вітру: набирає швидкість за DRIFT_TAU_SEC.
static func drift_m(t: float) -> float:
	return t - DRIFT_TAU_SEC * (1.0 - exp(-t / DRIFT_TAU_SEC))


static func _light(root: Node3D, range_m: float, energy: float) -> void:
	var light := OmniLight3D.new()
	light.name = "Light"
	light.light_color = Color("fff4d8")
	light.light_energy = energy
	light.omni_range = range_m / 8.0
	light.position.y = 0.3
	light.layers = 1 << (UnitView.UNIT_LAYER - 1)
	root.add_child(light)
	var tw: Tween = root.create_tween()
	tw.tween_property(light, "light_energy", 0.0, FLASH_SEC)
	# Згасле світло не лишається в сцені на всі 6 с диму.
	tw.tween_callback(light.queue_free)


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


## Риска іскри вздовж швидкості: колір чорного тіла й згасання — з рампи частинки; яскравіша в
## середині, тьмяніє до кінців і до країв, тож не читається прямокутником.
const _SPARK_CODE: String = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

void fragment() {
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	float along = sin(UV.y * 3.14159);
	ALBEDO = COLOR.rgb * 1.5;
	ALPHA = clamp(COLOR.a * across * 1.6 * sqrt(along), 0.0, 1.0);
}
"""


const _NOISE_CODE: String = """
float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
// Шум у координатах кваду (не в часі): нерухомий узор, що їде разом із клубою.
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}
"""


## Гаряче ядро спалаху: біло-жовте в середині, помаранчеве по нерівному краю; `heat` 0 → 1
## за два кадри. Звичайне змішування — без рожевої облямівки адитиву над синім.
const _HOT_CODE: String = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform float size = 1.0;
uniform float heat = 0.0;
uniform float seed = 0.0;
uniform float pull = 0.0;
""" + _NOISE_CODE + """
void vertex() {
	float s = size * length(MODEL_MATRIX[0].xyz);
	vec3 c = MODEL_MATRIX[3].xyz + INV_VIEW_MATRIX[2].xyz * (pull + 0.2);
	vec3 world = c + (INV_VIEW_MATRIX[0].xyz * VERTEX.x + INV_VIEW_MATRIX[1].xyz * VERTEX.y) * s;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float n = vnoise(UV * 6.0 + seed);
	float re = r * (0.8 + 0.4 * n);
	float a = 1.0 - smoothstep(0.35 + 0.3 * heat, 1.0, re);
	vec3 col = mix(vec3(1.0, 0.42, 0.08), vec3(1.0, 0.93, 0.72), 1.0 - smoothstep(0.0, 0.55 - 0.25 * heat, re));
	ALBEDO = col * 1.6;
	ALPHA = a * (1.0 - 0.5 * heat);
}
"""


## Низьке кільце пилу на землі: пласкій квад, кільце біжить від 0,3 до краю й розсіюється.
const _RING_CODE: String = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform float size = 1.0;
uniform float progress = 0.0;
uniform float opacity = 1.0;
uniform float seed = 0.0;
global uniform float sky_clear;
""" + _NOISE_CODE + """
void vertex() {
	float s = size * length(MODEL_MATRIX[0].xyz);
	vec3 world = MODEL_MATRIX[3].xyz + vec3(VERTEX.x, 0.0, VERTEX.y) * s;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float e = 1.0 - pow(1.0 - progress, 3.0);
	float R = mix(0.3, 1.0, e);
	float w = 0.25 + 0.35 * progress;
	float n = vnoise(UV * 9.0 + seed) * 0.6 + vnoise(UV * 23.0 + seed * 1.7) * 0.4;
	float band = smoothstep(R - w, R - w * 0.3, r) * (1.0 - smoothstep(R - w * 0.3, R, r));
	float inner = (1.0 - smoothstep(0.0, R, r)) * 0.25;
	ALBEDO = vec3(0.20, 0.18, 0.15) * (0.85 + 0.3 * n) * (1.0 + 0.4 * sky_clear);
	ALPHA = max(band, inner) * (0.4 + 0.6 * n) * opacity * (1.0 - smoothstep(0.35, 1.0, progress));
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
// Прозорість усієї клуби: проступання й легший пил; згасання — не тут, а в `erode`.
uniform float opacity = 1.0;
// Розчинення 0–1: шумовий поріг з'їдає спершу рідкі краї, наостанок густе ядро.
uniform float erode = 0.0;
uniform float seed = 0.0;
// Вогняна куля: перші кадри атласу (кремово-білі) гарячіші — біло-жовті з помаранчевим.
uniform float warm = 0.0;
// Зсув до камери, тайли: клуба влучання стоїть перед корпусом, а не в ньому.
uniform float pull = 0.0;
// Видимі сусіди (xyz — середина корпусу, w — радіус сліду в тайлах): над ними шар не густіший
// за 0,22, тож два шари разом — за 0,4.
uniform vec4 occ[6];
uniform int occ_n = 0;
// Сонце (WeatherRig): освітлений бік клуби світліший на ясних мапах; у похмурі — нічого.
global uniform vec3 sun_dir;
global uniform float sky_clear;
varying vec2 v_sun;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
// М'які краї лише там, де квад врізається в землю чи корпус.
uniform float soft_fade = 0.15;
""" + _NOISE_CODE + """
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
	rgb *= mix(vec3(1.0), vec3(1.0, 0.62, 0.3), warm * (1.0 - smoothstep(4.0, 16.0, frame)));
	ALBEDO = rgb * gain * mix(early_gain, 1.0, smoothstep(0.0, 4.0, frame)) * (1.0 + 0.45 * sky_clear * lit);
	float n = vnoise(UV * 7.0 + seed) * 0.6 + vnoise(UV * 17.0 + seed * 1.7) * 0.4;
	float e = erode * 1.25;
	float keep = smoothstep(e - 0.2, e, t.a * (0.6 + 0.4 * n));
	ALPHA = t.a * keep * opacity * (1.0 - 0.25 * erode);
	for (int i = 0; i < occ_n; i++) {
		vec3 ov = (VIEW_MATRIX * vec4(occ[i].xyz, 1.0)).xyz;
		float d = length(VERTEX.xy / -VERTEX.z - ov.xy / -ov.z) * -ov.z;
		ALPHA = mix(min(ALPHA, 0.22), ALPHA, smoothstep(occ[i].w, occ[i].w * 1.4, d));
	}
	// shortcut: глибина в NDC як у Vulkan (Forward+/Mobile); Compatibility дає z*2-1, краї там будуть жорсткіші.
	vec4 sv = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, texture(depth_tex, SCREEN_UV).r, 1.0);
	ALPHA *= clamp((VERTEX.z - sv.z / sv.w) / soft_fade, 0.0, 1.0);
}
"""
