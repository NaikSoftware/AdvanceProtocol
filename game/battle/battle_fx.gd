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
## Точка вибуху в клітинці атласу (частка ширини зліва, висоти згори; SOURCES.md): квад
## зсунуто так, що вона лягає на точку влучання, а хмара здіймається з неї.
const EXPLOSION_BLAST := Vector2(0.508, 0.866)
const DIRT_BLAST := Vector2(0.495, 0.882)
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
## Гаряче ядро спалаху — два кадри екрана; дульне — три (~50 мс), інакше його не видно.
const HOT_SEC: float = 0.035
const MUZZLE_HOT_SEC: float = 0.05
## Клуба тримає форму перші 35 % життя й рівно розчиняється решту: інакше рідкі краї
## з'їдались із першої ж секунди, і клуба зникала задовго до кінця.
const ERODE_FROM: float = 0.35
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
## тож основний шар (дим, ґрунт) — не густіший за OCCLUDE_ALPHA, а другий поверх нього (куля, чорне
## ядро) — за OCCLUDE_SECOND: 1 − 0,65 · 0,85 ≈ 0,45, і юніт усе ж бере відтінок диму, а не
## світиться в дірці. М'якого краю за глибиною всередині сліду нема: він і вирізав ту дірку.
## Слід — коло OCCLUDE_R тайла
## довкола середини корпусу, край розмитий на OCCLUDE_FEATHER тайла. Шари знищення діють так
## з 0,3 с: перші кадри кулі можуть накрити все.
const OCCLUDE_ALPHA: float = 0.35
const OCCLUDE_SECOND: float = 0.15
const OCCLUDE_FEATHER: float = 0.25
const OCCLUDE_R: float = 0.45
const OCCLUDE_MAX: int = 6
## Порядок прозорих квадів у тій самій точці: ґрунт, під ним гаряче ядро, над ними чорне ядро
## й вогняна куля.
const PRIORITY_HOT: int = 1
const PRIORITY_CORE: int = 2

static var _mix_shader: Shader
static var _hot_shader: Shader
static var _dust_shader: Shader
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
			return 3.0 if armoured else 2.5
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
					_sparks(root, "Sparks", rng.randi_range(1, 3), Vector3(0, ROOF, 0), _ricochet(rng), 35.0, 5.0, 10.0, 0.3, 0.7, 0.12, 0.22, burst * 0.3)
			else:
				# 6–12 порохових фонтанчиків на ділянці 4 × 4 м довкола: кожен підскакує й осідає.
				for i in 9:
					var o := Vector3(rng.randf_range(-0.25, 0.25), 0.0, rng.randf_range(-0.25, 0.25))
					_dirt(root, rng.randf_range(1.2, 2.0), o, rng.randf_range(0.0, smoke_delay(weapon, armoured)), 0.08, life, 0.4, 0.4)
		Weapon.AUTOCANNON:
			for r in 4:
				var o := Vector3(rng.randf_range(-0.12, 0.12), ROOF if armoured else 0.0, rng.randf_range(-0.12, 0.12))
				_hot(root, 1.0 if armoured else 0.8, o, r * 0.12)
				if armoured:
					_sparks(root, "Sparks", rng.randi_range(2, 4), o, _ricochet(rng), 35.0, 6.0, 12.0, 0.5, 1.2, 0.15, 0.25, r * 0.12)
					_puff(root, cloud, o, r * 0.12, 0.05, life, 0.6, 0.6)
				else:
					_dirt(root, cloud, o, r * 0.12, 0.05, life, 0.6, 0.5)
		Weapon.TANK_GUN:
			_light(root, 10.0, 4.0)
			if armoured:
				_hot(root, 3.0, Vector3(0, ROOF, 0), 0.0, PRIORITY_CORE + 1)
				_sparks(root, "Sparks", rng.randi_range(7, 12), Vector3(0, ROOF, 0), _ricochet(rng), 35.0, 8.0, 16.0, 0.4, 1.8, 0.15, 0.3, 0.0)
				# Вогняна куля на корпусі 4,5 м, що розчиняється за 0,6 с (120 мм по башті: 4,3 м на
				# +0,12 с), над сірою клубою, що за 0,15 с уже майже повна (там само, нижче за порядком).
				var ball := _sprite(root, "Ball", EXPLOSION_TEX, 64, 4.5 * EXPLOSION_CELL_M / EXPLOSION_BALL_M / 8.0, 0.0, 1.6)
				ball.position = Vector3(0, ROOF, 0)
				(ball.material_override as ShaderMaterial).render_priority = PRIORITY_CORE
				(ball.material_override as ShaderMaterial).set_shader_parameter("warm", 1.0)
				_play_smoke(root, ball, 0.08, 0.6, 0.0, 1.0, 0.3, Vector2(0.0, 30.0), Vector2.ZERO, 0.1)
				_puff(root, cloud, Vector3(0, ROOF, 0), 0.0, 0.12, life, 1.0, 0.75)
			else:
				_hot(root, 4.0, Vector3(0, 0.1, 0))
				_dirt(root, cloud, Vector3.ZERO, 0.0, 0.15, life, 0.7, 0.4)
				_core(root, cloud, 0.6 * life, 0.7, 0.4)
				_dust(root, 8.0, Vector3.ZERO, 2.5, 0.8)
				_debris(root, cloud)
		Weapon.SHELL:
			_hot(root, 5.0, Vector3(0, 0.12, 0))
			_light(root, 15.0, 4.0)
			# Центр хмари 155 мм — на 1,5–3 м вище за 3 с: власний підйом атласу знято (`hold`).
			_dirt(root, cloud, Vector3.ZERO, 0.0, 0.2, life, 0.6, 0.3)
			_core(root, cloud, 0.5 * life, 0.6, 0.3)
			_dust(root, 16.0, Vector3.ZERO, 3.5, 0.9)
			_debris(root, cloud)
		Weapon.DRONE:
			# Удар згори: гаряче ядро на даху, чорна клуба на корпусі, іскри вниз і вбік, без ґрунту.
			_hot(root, 3.0, Vector3(0, ROOF + 0.05, 0), 0.0, PRIORITY_CORE + 1)
			_sparks(root, "Sparks", rng.randi_range(5, 9), Vector3(0, ROOF, 0), _ricochet(rng), 45.0, 6.0, 14.0, 0.4, 1.4, 0.15, 0.3, 0.0)
			_fireball(root, cloud, Vector3(0, ROOF, 0), 0.0, life, 1.0, 0.7)
	if armoured:
		for n: Node in root.find_children("*", "MeshInstance3D", true, false):
			var mat := (n as MeshInstance3D).material_override as ShaderMaterial
			if mat != null:
				mat.set_shader_parameter("pull", ARMOUR_PULL)
	_shield(root, parent, at)
	_expire(root, HIT_SEC)
	return root


## Дульний спалах біля стрільця: танк і гармата — жовто-біле гаряче ядро на два кадри, сіро-
## бежевий пороховий дим уздовж осі ствола й низький рваний шар пилу на землі під корпусом і перед
## ним; автогармата — три малі ядра й клубок диму. Розміри, крок і життя клубів — свої для кожного
## пострілу. Стрілецька зброя спалаху не має: на екрані він субпіксельний.
## Стрільця, якого глядач не бачить, сюди не передають зовсім.
static func spawn_muzzle(parent: Node, shooter: Transform3D, weapon: Weapon, type_id: int = -1) -> Node3D:
	if weapon == Weapon.RIFLE or weapon == Weapon.DRONE:
		return null
	var tip: Vector3 = shooter * (UnitSilhouettes.muzzle(type_id) if type_id >= 0 else Vector3(0, 0.2, -0.6))
	var root := _root("Muzzle", parent, tip)
	var axis: Vector3 = Vector3(-shooter.basis.z.x, 0.0, -shooter.basis.z.z).normalized()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(tip)
	if weapon == Weapon.AUTOCANNON:
		for r in 3:
			_hot(root, 1.0, Vector3.ZERO, r * 0.12, PRIORITY_HOT, MUZZLE_HOT_SEC, true)
		_powder(root, rng, 1.2 * rng.randf_range(0.6, 1.4), axis * 0.06, 0.1)
	else:
		_hot(root, 2.0, axis * 0.05, 0.0, PRIORITY_HOT, MUZZLE_HOT_SEC, true)
		# Пороховий дим — 3–4 клуби вздовж ствола: розмір 0,6–1,4 від 2,2 м, крок 0,6–1,3 м.
		var along: float = 0.0
		for i in rng.randi_range(3, 4):
			along += rng.randf_range(0.08, 0.16)
			_powder(root, rng, 2.2 * rng.randf_range(0.6, 1.4), axis * along, rng.randf_range(0.0, 0.04))
		# Ударна хвиля пострілу здіймає пил під корпусом і перед ним, а не кільцем довкола дула.
		var dust_at: Vector3 = shooter.origin + axis * 0.3 - tip
		_dust(root, 10.0, Vector3(dust_at.x, shooter.origin.y - tip.y + 0.03, dust_at.z), 1.8, 0.7)
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
## балістичними дугами, падають на землю, лежать і за останні 0,5 с осідають. Життя — з часу
## польоту 2v/g, тож у повітрі ніщо не зникає.
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


## Час польоту шматка, кинутого вгору на `v_ms` м/с, до повернення на землю, с.
static func debris_flight_sec(v_ms: float) -> float:
	return 2.0 * v_ms / 9.8


static var _clod_mesh: ArrayMesh
static var _scrap_mesh: ArrayMesh
static var _spark_mesh: QuadMesh


## Неправильний гранчастий шматок (зім'ята сфера, сторони не довші за 2:1): грудка землі чи
## уламок металу — не кубик і не палиця.
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
		st.add_vertex(v * (0.85 + 0.3 * h) * Vector3(1.0, 1.0, 1.2))
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
	var occ: Array[Vector4] = []
	for c: Node in parent.get_children():
		var u := c as UnitView
		if u == null or not u.visible:
			continue
		var flat := Vector2(u.position.x - except.x, u.position.z - except.z)
		if flat.length() < 0.3 or flat.length() > 3.0 or occ.size() >= OCCLUDE_MAX:
			continue
		occ.append(Vector4(u.position.x, u.position.y + 0.15, u.position.z, OCCLUDE_R))
	if occ.is_empty():
		return
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mat := (n as MeshInstance3D).material_override as ShaderMaterial
		if mat == null or mat.shader != _mix_shader:
			continue
		for i in OCCLUDE_MAX:
			mat.set_shader_parameter("occ%d" % i, occ[i] if i < occ.size() else Vector4.ZERO)
		mat.set_shader_parameter("occ_n", occ.size())


## Гаряче ядро спалаху `d_m` метрів: м'який радіальний градієнт — біле в середині (дульне —
## жовте, `muzzle`), помаранчевий край, прозорість спадає до краю; живе `sec` с.
static func _hot(root: Node3D, d_m: float, offset: Vector3, delay: float = 0.0, priority: int = PRIORITY_HOT, sec: float = HOT_SEC, muzzle: bool = false) -> void:
	if _hot_shader == null:
		_hot_shader = Shader.new()
		_hot_shader.code = _HOT_CODE
	var mat := ShaderMaterial.new()
	mat.shader = _hot_shader
	mat.render_priority = priority
	mat.set_shader_parameter("size", d_m / 8.0)
	mat.set_shader_parameter("seed", float(hash(root.position) % 97))
	mat.set_shader_parameter("pull", 0.0)
	mat.set_shader_parameter("yellow", 1.0 if muzzle else 0.0)
	var q := _quad_instance(root, "Hot", mat)
	q.position = offset
	q.visible = delay <= 0.0
	var tw: Tween = root.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
		tw.tween_callback(func() -> void: q.visible = true)
	tw.tween_method(func(f: float) -> void: mat.set_shader_parameter("heat", f), 0.0, 1.0, sec)
	tw.tween_callback(func() -> void: q.visible = false)


## Низький рваний шар пилу `d_m` метрів на землі (ударна хвиля): заповнений, з радіальним спадом
## і краєм, роз'їденим шумом, свій для кожного місця; розходиться й осідає за `life` с. Пласкій
## квад висить на 0,3 м над землею й м'яко гасне там, де рельєф до нього підходить: інакше квад
## різав горби сходинками.
static func _dust(root: Node3D, d_m: float, offset: Vector3, life: float, opacity: float) -> void:
	if _dust_shader == null:
		_dust_shader = Shader.new()
		_dust_shader.code = _DUST_CODE
	var mat := ShaderMaterial.new()
	mat.shader = _dust_shader
	mat.set_shader_parameter("size", d_m / 8.0)
	mat.set_shader_parameter("opacity", opacity)
	mat.set_shader_parameter("seed", float(hash(root.position + offset) % 89))
	var q := _quad_instance(root, "Dust", mat)
	q.position = offset + Vector3(0, 0.3 / 8.0, 0)
	var tw: Tween = root.create_tween()
	tw.tween_method(func(f: float) -> void: mat.set_shader_parameter("progress", f), 0.0, 1.0, life)
	tw.tween_callback(func() -> void: q.visible = false)


## Вогняна куля `ball_m` метрів, що перетікає в темний дим: куля набирає об'єм за 0,12 с і
## розчиняється за FIRE_SEC поверх диму, а дим під нею вже повний із 0,35 с — без провалу
## «темно → світло → темно». Обидва квади рухаються однією кривою, тож це одна клуба.
static func _fireball(root: Node3D, ball_m: float, offset: Vector3, lift: float, life: float, rise: float, grow: float) -> void:
	var side: float = ball_m * EXPLOSION_CELL_M / EXPLOSION_BALL_M / 8.0
	var ball := _sprite(root, "Ball", EXPLOSION_TEX, 64, side, lift, 1.0)
	ball.position = offset
	var bmat := ball.material_override as ShaderMaterial
	bmat.render_priority = PRIORITY_CORE
	bmat.set_shader_parameter("warm", 1.0)
	bmat.set_shader_parameter("occ_cap", OCCLUDE_SECOND)
	_play_smoke(root, ball, 0.12, FIRE_SEC, 0.0, rise, grow, Vector2(0.0, LAST_FRAME), Vector2.ZERO, 0.4)
	var smoke := _sprite(root, "Smoke", SMOKE_TEX, 64, side * SMOKE_SCALE, lift, 1.0)
	smoke.position = offset
	_play_smoke(root, smoke, 0.3, life, 0.0, rise, grow, Vector2(6.0, LAST_FRAME), Vector2(0.1, 0.35), ERODE_FROM * life)


## Хмара ґрунту `cloud_m` метрів: ~80 % об'єму за `full` с, живе `life` с, здіймається на
## `rise` м/с і ширшає на частку `grow`.
static func _dirt(root: Node3D, cloud_m: float, offset: Vector3, delay: float, full: float, life: float, rise: float, grow: float) -> void:
	var q := _sprite(root, "Dirt", DIRT_TEX, 64, cloud_m * DIRT_CELL_M / DIRT_CLOUD_M / 8.0, 0.0, 1.0)
	q.position = offset
	_play_smoke(root, q, full, life, delay, rise, grow, Vector2(4.0, LAST_FRAME), Vector2.ZERO, ERODE_FROM * life, 1.0, false, true)


## Чорне ядро фугасного розриву в ґрунті: 155 мм на +0,1 с — чорна куля, і лише за 1–2 с її
## розбавляє бурий пил. Квад диму на 0,8 хмари ґрунту, поверх неї (і поверх гарячого ядра),
## сіро-бурий, проступає рівно за 0,15 с (не стрибком із бурого в сірий) і розчиняється за `life` с;
## рухається тією ж кривою, що й хмара.
static func _core(root: Node3D, cloud_m: float, life: float, rise: float, grow: float) -> void:
	var side: float = 0.8 * cloud_m * DIRT_CELL_M / DIRT_CLOUD_M / 8.0
	var q := _sprite(root, "Core", SMOKE_TEX, 64, side, 0.0, 1.0)
	var mat := q.material_override as ShaderMaterial
	mat.render_priority = PRIORITY_CORE
	mat.set_shader_parameter("occ_cap", OCCLUDE_SECOND)
	mat.set_shader_parameter("tint", Vector4(0.13, 0.11, 0.085, 0.35))
	_play_smoke(root, q, 0.15, life, 0.0, rise, grow, Vector2(4.0, 30.0), Vector2(0.0, 0.15), ERODE_FROM * life, 0.9)


## Сіра клуба диму й окалини (влучання в броню): той самий атлас ґрунту, знебарвлений і
## трохи світліший.
static func _puff(root: Node3D, cloud_m: float, offset: Vector3, delay: float, full: float, life: float, rise: float, grow: float) -> void:
	var q := _sprite(root, "Puff", DIRT_TEX, 64, cloud_m * DIRT_CELL_M / DIRT_CLOUD_M / 8.0, 0.0, 1.15)
	q.position = offset
	(q.material_override as ShaderMaterial).set_shader_parameter("desat", 1.0)
	_play_smoke(root, q, full, life, delay, rise, grow, Vector2(6.0, LAST_FRAME), Vector2.ZERO, ERODE_FROM * life)


## Пороховий дим біля дула `cloud_m` метрів: сіро-бежевий (#8a8274), з розмитим краєм, свій кадр
## атласу й своє життя 1,5–2,5 с; за першу чверть секунди помітно розходиться (від 0,6 розміру),
## далі повільно здіймається й рівно (лінійно) тане.
static func _powder(root: Node3D, rng: RandomNumberGenerator, cloud_m: float, offset: Vector3, delay: float) -> void:
	var q := _sprite(root, "Powder", DIRT_TEX, 64, cloud_m * DIRT_CELL_M / DIRT_CLOUD_M / 8.0, 0.0, 1.0)
	q.position = offset
	var mat := q.material_override as ShaderMaterial
	mat.set_shader_parameter("tint", Vector4(0.254, 0.223, 0.175, 0.85))
	mat.set_shader_parameter("feather", 1.0)
	var life: float = rng.randf_range(1.5, 2.5)
	_play_smoke(root, q, 0.25, life, delay, 0.5, 1.0, Vector2(rng.randf_range(0.0, 6.0), LAST_FRAME), Vector2.ZERO, life, 0.85, true, false, 0.5, 0.6)


## Зсув центру кваду від точки влучання, у частках кваду (x — праворуч на екрані, y — угору):
## точка вибуху атласу лягає на точку влучання.
static func anchor_of(tex: Texture2D) -> Vector2:
	var blast := Vector2(0.5, 0.5)
	if tex == EXPLOSION_TEX:
		blast = EXPLOSION_BLAST
	elif tex == DIRT_TEX:
		blast = DIRT_BLAST
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
	# Читабельні імена (Hot2, Dirt3): рушій інакше перейменував би однойменних сусідів у @…@.
	root.add_child(mi, true)
	return mi


static func _sprite(root: Node3D, node_name: String, tex: Texture2D, frames: int, size: float, lift: float, gain: float) -> MeshInstance3D:
	if _mix_shader == null:
		_mix_shader = Shader.new()
		_mix_shader.code = _SPRITE_CODE
	var mat := ShaderMaterial.new()
	mat.shader = _mix_shader
	mat.set_shader_parameter("tex", tex)
	mat.set_shader_parameter("grid", Vector2(8, 8))
	mat.set_shader_parameter("frames", float(frames))
	mat.set_shader_parameter("frame", 0.0)
	mat.set_shader_parameter("size", size)
	mat.set_shader_parameter("lift", lift)
	mat.set_shader_parameter("gain", gain)
	mat.set_shader_parameter("desat", 0.0)
	mat.set_shader_parameter("tint", Vector4.ZERO)
	mat.set_shader_parameter("opacity", 1.0)
	mat.set_shader_parameter("erode", 0.0)
	mat.set_shader_parameter("warm", 0.0)
	mat.set_shader_parameter("pull", 0.0)
	mat.set_shader_parameter("occ_n", 0)
	mat.set_shader_parameter("occ_k", 0.0)
	mat.set_shader_parameter("occ_cap", OCCLUDE_ALPHA)
	mat.set_shader_parameter("feather", 0.0)
	mat.set_shader_parameter("seed", float(hash(root.position + Vector3(size, lift, frames)) % 101))
	mat.set_shader_parameter("anchor", anchor_of(tex))
	mat.set_shader_parameter("soft_fade", minf(HIT_SOFT_FADE, size * 0.2))
	return _quad_instance(root, node_name, mat)


## Клуба, що живе `life` с. Атлас — `smoke_frame`: кадри `frames` до FULL_FRAME (~80 % об'єму)
## за `full` с, далі повзе до кінця життя. Проступає за `fade_in` (нуль — одразу), розчиняється
## ерозією від `erode_from` с до `life` (`smoke_erode`), а з `linear_fade` — рівно тане вся
## (пороховий дим). Увесь цей час квад здіймається (`rise_m`), ширшає (`smoke_scale`, від `scale0`
## зі сталою `grow_tau`) довкола середини хмари й зноситься вітром. З `hold` квад опускається на
## стільки, на скільки хмара сама піднялась усередині атласу ґрунту (`dirt_rise`): швидкість
## підйому — лише та, що задана. Обмеження над сусідами вмикається до 0,3 с. Ховається, лише
## коли вже розчинився.
static func _play_smoke(root: Node3D, q: MeshInstance3D, full: float, life: float, delay: float, rise: float, grow: float, frames: Vector2 = Vector2(0.0, LAST_FRAME), fade_in: Vector2 = Vector2.ZERO, erode_from: float = 0.0, opacity: float = 1.0, linear_fade: bool = false, hold: bool = false, grow_tau: float = RISE_TAU_SEC, scale0: float = 1.0) -> void:
	var mat := q.material_override as ShaderMaterial
	var anchor0: Vector2 = mat.get_shader_parameter("anchor")
	var base: Vector3 = q.position
	var drift: Vector3 = wind * DRIFT_PER_WIND
	var step := func(t: float) -> void:
		var f: float = smoke_frame(t, full, life, frames)
		mat.set_shader_parameter("frame", f)
		if hold:
			mat.set_shader_parameter("anchor", anchor0 - Vector2(0.0, dirt_rise(f)))
		var o: float = opacity * (smoothstep(fade_in.x, fade_in.y, t) if fade_in.y > 0.0 else 1.0)
		mat.set_shader_parameter("opacity", o * (1.0 - t / life) if linear_fade else o)
		mat.set_shader_parameter("erode", smoke_erode(t, life, erode_from))
		mat.set_shader_parameter("occ_k", clampf((t - 0.15) / 0.15, 0.0, 1.0))
		q.position = base + Vector3(0.0, rise_m(rise, t), 0.0) / 8.0 + drift * drift_m(t) / 8.0
		q.scale = Vector3.ONE * (scale0 + (1.0 - scale0 + grow) * (1.0 - exp(-t / grow_tau)) + 0.04 * t if scale0 < 1.0 else smoke_scale(grow, t))
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
	var f_full: float = maxf(minf(FULL_FRAME, frames.y), frames.x)
	if t < full:
		var u: float = t / full
		return lerpf(frames.x, f_full, 1.0 - (1.0 - u) * (1.0 - u))
	return lerpf(f_full, frames.y, pow(clampf((t - full) / maxf(life - full, 1e-3), 0.0, 1.0), 0.75))


## Ерозія клуби на `t` с, 0–1: нуль до `erode_from`, далі лінійно до 1 на `life`. Шейдер з'їдає
## за шумовим порогом спершу рідкі краї, наостанок — густе ядро, і ще множить усю клубу на
## (1 − ерозія): кінець рівний, без обвалу.
static func smoke_erode(t: float, life: float, erode_from: float = 0.0) -> float:
	if erode_from >= life:
		return 0.0
	return clampf((t - erode_from) / (life - erode_from), 0.0, 1.0)


## Висота підйому клуби за `t` с, метри: на старті `rise` м/с, гальмує з τ до RISE_FLOOR · rise.
static func rise_m(rise: float, t: float) -> float:
	return rise * (RISE_FLOOR * t + (1.0 - RISE_FLOOR) * RISE_TAU_SEC * (1.0 - exp(-t / RISE_TAU_SEC)))


## Наскільки центр хмари піднявся всередині клітинки атласу ґрунту від кадру повного об'єму
## (FULL_FRAME) до кадру `f`, у частках клітинки (виміряно по альфі: центр 0,62 → 0,465 до кадру 32
## → 0,44 до кадру 40).
static func dirt_rise(f: float) -> float:
	return 0.155 * clampf((f - FULL_FRAME) / 16.0, 0.0, 1.0) + 0.025 * clampf((f - 32.0) / 8.0, 0.0, 1.0)


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




## Риска іскри вздовж швидкості: колір чорного тіла й згасання — з рампи частинки; яскравіша в
## середині, тьмяніє до кінців і до країв, тож не читається прямокутником.
const _SPARK_CODE: String = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

void fragment() {
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	float along = sin(UV.y * 3.14159);
	ALBEDO = COLOR.rgb;
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


## Гаряче ядро спалаху: м'який радіальний градієнт біле → жовте → помаранчеве, прозорість
## спадає до краю; `heat` 0 → 1 за два кадри. Звичайне змішування, кольори не вище 1: без
## білого багатокутника й без рожевої облямівки.
const _HOT_CODE: String = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform float size = 1.0;
uniform float heat = 0.0;
uniform float seed = 0.0;
uniform float pull = 0.0;
// Дульний спалах: середина жовта, а не біла.
uniform float yellow = 0.0;
""" + _NOISE_CODE + """
void vertex() {
	float s = size * length(MODEL_MATRIX[0].xyz);
	vec3 c = MODEL_MATRIX[3].xyz + INV_VIEW_MATRIX[2].xyz * (pull + 0.2);
	vec3 world = c + (INV_VIEW_MATRIX[0].xyz * VERTEX.x + INV_VIEW_MATRIX[1].xyz * VERTEX.y) * s;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float re = r * (0.92 + 0.16 * vnoise(UV * 5.0 + seed));
	vec3 col = mix(mix(vec3(1.0, 0.97, 0.9), vec3(1.0, 0.86, 0.45), yellow), vec3(1.0, 0.82, 0.4), smoothstep(0.0, 0.35, re));
	col = mix(col, vec3(0.95, 0.45, 0.12), smoothstep(0.35, 0.75, re));
	ALBEDO = col;
	ALPHA = pow(clamp(1.0 - re, 0.0, 1.0), 1.5) * (1.0 - 0.6 * heat);
}
"""


## Низький рваний шар пилу на землі: пласкій квад на 0,3 м над землею, радіальний спад
## прозорості, край роз'їдений шумом (радіус гуляє за кутом), свій для кожного `seed`; лише низькі
## повернуті октави шуму, без регулярної сітки. Там, де рельєф підходить до кваду ближче за 0,4 м,
## пил м'яко гасне, а не ріжеться сходинками. Розходиться з 0,35 до краю й осідає.
const _DUST_CODE: String = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, skip_vertex_transform;

uniform float size = 1.0;
uniform float progress = 0.0;
uniform float opacity = 1.0;
uniform float seed = 0.0;
global uniform float sky_clear;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;
""" + _NOISE_CODE + """
float fbm(vec2 p) {
	// Повернуті октави: квадратна решітка value-шуму не складається в ромби.
	float a = vnoise(p);
	p = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p * 2.03 + 17.0;
	a += 0.5 * vnoise(p);
	p = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p * 2.01 + 31.0;
	a += 0.25 * vnoise(p);
	return a / 1.75;
}

void vertex() {
	float s = size * length(MODEL_MATRIX[0].xyz);
	vec3 world = MODEL_MATRIX[3].xyz + vec3(VERTEX.x, 0.0, VERTEX.y) * s;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
}

void fragment() {
	vec2 q = UV - 0.5;
	float r = length(q) * 2.0;
	vec2 dir = q / max(length(q), 1e-4);
	float petals = fbm(dir * 1.7 + seed);
	float e = 1.0 - pow(1.0 - progress, 3.0);
	// Найдальший край — 0,8 півкваду: форма ніколи не впирається в квадрат.
	float R = mix(0.3, 0.8, e) * (0.6 + 0.4 * petals);
	float d = fbm(UV * 3.5 + seed);
	float edge = 1.0 - smoothstep(0.45, 1.0, r / R + (d - 0.5) * 0.35);
	float body = edge * pow(clamp(1.0 - r / R, 0.0, 1.0), 0.35);
	ALBEDO = vec3(0.23, 0.20, 0.16) * (0.85 + 0.3 * d) * (1.0 + 0.3 * sky_clear);
	ALPHA = body * (0.5 + 0.5 * d) * opacity * 0.8 * (1.0 - smoothstep(0.3, 1.0, progress));
	vec4 sv = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, texture(depth_tex, SCREEN_UV).r, 1.0);
	ALPHA *= clamp((VERTEX.z - sv.z / sv.w) / (0.4 / 8.0), 0.0, 1.0);
}
"""


## Квад флипбука в камеру. Колір і пряма альфа — з самого атласу (він уже освітлений і
## розфарбований); між кадрами — плавний перехід, бо один кадр атласу триває кілька кадрів
## екрана.
const _SPRITE_CODE: String = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, skip_vertex_transform;

uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform vec2 grid = vec2(8.0);
uniform float frames = 64.0;
uniform float frame = 0.0;
uniform float size = 1.0;
uniform float lift = 0.0;
uniform float gain = 1.0;
// Зсув центру кваду від точки влучання в площині кадру, у частках кваду (BattleFx.anchor_of):
// точка вибуху атласу лягає на точку влучання. Береться від розміру без ширшання, тож клуба
// ширшає довкола своєї середини, а не росте вгору від точки вибуху.
uniform vec2 anchor = vec2(0.0);
// Сіра клуба з бурого атласу ґрунту: 1 — повністю знебарвлена.
uniform float desat = 0.0;
// Перефарбування (пороховий дим): rgb — колір, a — частка.
uniform vec4 tint = vec4(0.0);
// Прозорість усієї клуби: проступання, легший пил, рівне згасання порохового диму.
uniform float opacity = 1.0;
// Розчинення 0–1: шумовий поріг з'їдає спершу рідкі краї, наостанок густе ядро.
uniform float erode = 0.0;
uniform float seed = 0.0;
// Вогняна куля: перші кадри атласу гарячіші в середині й темніші по краю, наче їх уже затягує дим.
uniform float warm = 0.0;
// Зсув до камери, тайли: клуба влучання стоїть перед корпусом, а не в ньому.
uniform float pull = 0.0;
// Видимі сусіди (xyz — середина корпусу, w — радіус сліду в тайлах): над ними шар не густіший
// за `occ_cap`, край розмитий на 0,25 тайла; `occ_k` вмикає це до 0,3 с.
uniform vec4 occ0;
uniform vec4 occ1;
uniform vec4 occ2;
uniform vec4 occ3;
uniform vec4 occ4;
uniform vec4 occ5;
uniform int occ_n = 0;
uniform float occ_k = 0.0;
// Межа шару над сусідом: основний 0,35, другий поверх нього 0,15 — разом ≤ 0,45.
uniform float occ_cap = 0.35;
// Розмитий край клуби (пороховий дим): рідкі краї атласу ще прозоріші.
uniform float feather = 0.0;
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
	vec3 c = MODEL_MATRIX[3].xyz + vec3(0.0, lift, 0.0) + INV_VIEW_MATRIX[2].xyz * pull + (INV_VIEW_MATRIX[0].xyz * anchor.x + INV_VIEW_MATRIX[1].xyz * anchor.y) * size;
	vec3 world = c + (INV_VIEW_MATRIX[0].xyz * VERTEX.x + INV_VIEW_MATRIX[1].xyz * VERTEX.y) * s;
	// VERTEX — справжня позиція кваду в просторі камери: з нею фрагмент знає, де він на екрані
	// (обмеження над сусідами) і на якій глибині (м'який край). Запис лише в POSITION лишав би
	// у фрагменті позицію неповернутого кваду в корені миті.
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
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
	vec3 rgb = t.rgb;
	float luma = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
	rgb = mix(rgb, vec3(luma), desat);
	rgb = mix(rgb, tint.rgb * (0.7 + 0.6 * smoothstep(0.0, 0.3, luma)), tint.a);
	float early = warm * (1.0 - smoothstep(3.0, 12.0, frame));
	float edge = smoothstep(0.08, 0.3, length(UV - vec2(0.53, 0.6)));
	rgb = mix(rgb, rgb * mix(vec3(1.0, 0.82, 0.5), vec3(0.32, 0.2, 0.13), edge), early);
	ALBEDO = rgb * gain * (1.0 + 0.45 * sky_clear * lit);
	float n = vnoise(UV * 7.0 + seed) * 0.6 + vnoise(UV * 17.0 + seed * 1.7) * 0.4;
	float thr = erode * 1.05;
	float keep = smoothstep(thr - 0.25, thr, t.a * (0.6 + 0.4 * n));
	float a = t.a * mix(1.0, smoothstep(0.0, 0.7, t.a), feather) * keep * opacity * (1.0 - erode);
	// shortcut: глибина в NDC як у Vulkan (Forward+/Mobile); Compatibility дає z*2-1, краї там будуть жорсткіші.
	vec4 sv = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, texture(depth_tex, SCREEN_UV).r, 1.0);
	float soft = clamp((VERTEX.z - sv.z / sv.w) / soft_fade, 0.0, 1.0);
	// Над видимим сусідом: шар не густіший за occ_cap і без м'якого краю за глибиною — корпус
	// сусіда близько до кваду, і край вирізав би в диму дірку, де юніт світився б яскраво-синім.
	vec4 occ[6] = vec4[6](occ0, occ1, occ2, occ3, occ4, occ5);
	float inside = 0.0;
	for (int i = 0; i < occ_n; i++) {
		vec3 ov = (VIEW_MATRIX * vec4(occ[i].xyz, 1.0)).xyz;
		float d = length(VERTEX.xy / -VERTEX.z - ov.xy / -ov.z) * -ov.z;
		inside = max(inside, 1.0 - smoothstep(occ[i].w, occ[i].w + 0.25, d));
	}
	ALPHA = mix(a * soft, min(a, occ_cap), inside * occ_k);
}
"""
