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
## Приземна хвиля пилу розходиться на повний радіус за стільки секунд.
const DUST_SPREAD_SEC: float = 0.5
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
## Дим не ховає сусідів: там, де клуби миті лягають на екранний слід видимого живого юніта (крім
## цілі), разом вони не густіші за OCCLUDE_TOTAL, і юніт бере відтінок диму, а не світиться в
## дірці. Шарів у миті n (куля й дим, ґрунт і чорне ядро, 3–4 клуби пороху, 4 автогармати), тож
## кожен — не густіший за 1 − (1 − OCCLUDE_TOTAL)^(1/n) (`occlude_cap`). М'якого краю за глибиною
## всередині сліду нема: він і вирізав ту дірку. Слід — коло OCCLUDE_R тайла довкола середини
## корпусу, спад розмитий на OCCLUDE_FEATHER тайла, щоб у стовпі не лишалось виїмки. Діє з
## 0,3 с: перші кадри кулі можуть накрити все.
const OCCLUDE_TOTAL: float = 0.45
const OCCLUDE_FEATHER: float = 1.0
## Межа однієї клуби хвилі пилу над сусідом.
const WAVE_CAP: float = 0.1
## Скільки секунд вогняна куля над видимим сусідом вирізана повністю.
const FIREBALL_CUT_SEC: float = 0.1
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
	var all: Array[Node3D] = [boom, spawn_hit(parent, at, Weapon.TANK_GUN, true), spawn_hit(parent, at, Weapon.SHELL, false), spawn_muzzle(parent, Transform3D(Basis(), at), Weapon.TANK_GUN),
			spawn_topple_hit(parent, at, at + Vector3.UP, Debris.CONCRETE, true), spawn_topple_land(parent, at, at + Vector3.RIGHT, Debris.WOOD, true)]
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


## З чого зроблене те, що техніка валить: від цього залежать уламки й пил.
## CONCRETE — бетонна опора, єврозабір; WOOD — дерев'яна опора, штахетник, планки;
## SHEET — профлист; MESH — рабиця, ґрати.
enum Debris { CONCRETE, WOOD, SHEET, MESH }


## Мить удару звільняється не пізніше цього: пил біля основи опори висить, поки вона падає
## (до 1,8 с), і ще осідає.
const TOPPLE_HIT_SEC: float = 3.2
## Мить падіння: уламки лежать і осідають, пил осідає за 2–3 с.
const TOPPLE_LAND_SEC: float = 3.4
## Кадри атласу ґрунту для пилу повалення: з раннього (4-й) до повного об'єму (16-й) за
## SETTLE_FULL частку життя, далі до 40-го — так само, як клуба ґрунту влучання (`_dirt`).
const SETTLE_FRAMES := Vector2(4.0, 40.0)
const SETTLE_FULL: float = 0.08
## Форми уламків повалення (`_shard_mesh`). CLOD — темна грудка землі чи грязі з-під гусениці.
enum Shard { CHIP, SPLINTER, SHEET, ROD, CLOD }

## Пил за матеріалом (лінійні кольори): лише бетон дає світлу сіру хмару; дерево — темніший бурий
## пил; метал пилу майже не має, лише ґрунт з-під нього (той самий, що в хвилі пилу `_wave`).
const SOIL_DUST := Color(0.27, 0.24, 0.19)
const SOIL_DUST_DARK := Color(0.21, 0.185, 0.15)
const DUST: Dictionary = {
	Debris.CONCRETE: [Color(0.36, 0.345, 0.31), Color(0.27, 0.24, 0.19)],
	Debris.WOOD: [Color(0.25, 0.205, 0.15), Color(0.21, 0.17, 0.125)],
	Debris.SHEET: [SOIL_DUST, SOIL_DUST_DARK],
	Debris.MESH: [SOIL_DUST, SOIL_DUST_DARK],
}
## Мокра земля не куриться: замість світлого пилу — коротка низька бризка темно-бурої грязі.
const MUD_SPRAY: Array[Color] = [Color(0.045, 0.032, 0.02), Color(0.034, 0.025, 0.016)]
## Скільки грудок землі з-під удару дає матеріал: бетон і дерево — переважно власні уламки.
const CLODS: Dictionary = {Debris.CONCRETE: 3, Debris.WOOD: 2, Debris.SHEET: 4, Debris.MESH: 4}
## Скільки пилу дає матеріал (частка клуб і густоти): бетон кришиться, метал лише шкрябає ґрунт.
const POWDER: Dictionary = {Debris.CONCRETE: 1.0, Debris.WOOD: 0.75, Debris.SHEET: 0.5, Debris.MESH: 0.4}
## Дрібна фракція матеріалу: форма й розмір, м. Великі куски — частини розколотої моделі.
const FINE: Dictionary = {
	Debris.CONCRETE: [Shard.CHIP, 0.1, 0.26],
	Debris.WOOD: [Shard.SPLINTER, 0.15, 0.35],
	Debris.SHEET: [Shard.SHEET, 0.2, 0.35],
	Debris.MESH: [Shard.ROD, 0.2, 0.35],
}
## Опора вища за це (м над точкою удару); нижче — паркан. Лише коли той, хто кличе, не сказав сам.
const POLE_MIN_M: float = 3.5

## Мокрість мапи 0–1 (BattleLook.wetness): ставить екран бою разом із вітром.
static var wetness: float = 0.0
static var _shard_meshes: Dictionary = {}
static var _shard_mat: StandardMaterial3D
static var _settle_mesh: QuadMesh


## Мить, коли техніка б'є в опору чи паркан (той, хто кличе, далі сам валить чи розколює модель).
## at — точка удару біля основи, top — верх (для опори під напругою там іскрить дріт); `pole` —
## опора (інакше паркан, а не сказано — за висотою); `span` — півпрольоту полотна паркану від `at`
## уздовж огорожі (тайли), нуль — 0,75 м уздовж X.
## Опора лише кришиться біля основи: 3–5 малих клуб підскакують і висять, поки вона падає;
## паркан розлітається від удару, тож це його головний сплеск: 3–4 невеликі клуби вздовж полотна
## підскакують і гальмують. В обох уламки матеріалу (світлі сколи бетону, тріски, клапті, прути) і
## кілька грудок землі летять дугами на 2–3 м. На мокрій мапі — коротка бура бризка грязі.
## Дріт під напругою на верху дає 2–3 рвані синьо-білі дуги через нерівні проміжки й сиплеться
## розплавом — лише в першу третину секунди, поки верх опори ще на місці.
static func spawn_topple_hit(parent: Node, at: Vector3, top: Vector3, debris: Debris, live_wire: bool, pole: bool = false, span: Vector3 = Vector3.ZERO) -> Node3D:
	var root := _root("ToppleHit", parent, at)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(at)
	var is_pole: bool = pole or (top.y - at.y) * 8.0 > POLE_MIN_M
	var along: Vector3 = span if span.length() > 1e-4 else Vector3(0.75 / 8.0, 0, 0)
	var basis := _along(along)
	var half_m: float = Vector3(along.x, 0, along.z).length() * 8.0
	var low := Vector3(0, 0.3 / 8.0, 0)
	var wet: float = clampf(wetness, 0.0, 1.0)
	var powder: float = POWDER[debris] * (1.0 - 0.5 * wet)
	var colours: Array[Color] = _dust_colours(debris, wet)
	var fine: Array = FINE[debris]
	var clods: int = roundi(CLODS[debris] * (1.0 + 0.6 * wet))
	if is_pole:
		var spot := Vector3(0.2, 0.05, 0.2) / 8.0
		_shards(root, "Fine", rng, fine[0], 7, low, Basis(), spot, fine[1], fine[2], 2.0, 5.0, 70.0, 2.4)
		_shards(root, "Clods", rng, Shard.CLOD, clods, low, Basis(), spot, 0.12, 0.26, 2.0, 5.0, 70.0, 2.4)
		# 3–5 малих низьких клуб біля основи підскакують і висять, поки опора падає (до 1,8 с).
		_dust_puffs(root, rng, 5, Vector3.ZERO, Basis(), spot * 2.0, 0.7, 1.6, 2.8, colours, 0.9, 1.3, 30.0, 1.0, 0.25, 0.3, wet)
	else:
		var box := Vector3(half_m, 0.1, 0.3) / 8.0
		# Не далі ~3 м: віяло 70° від вертикалі на 4,5 м/с.
		_shards(root, "Fine", rng, fine[0], 10, low, basis, box, fine[1], fine[2], 2.0, 4.5, 70.0, 2.4)
		_shards(root, "Clods", rng, Shard.CLOD, clods + 2, low, basis, box, 0.12, 0.26, 2.0, 4.5, 70.0, 2.4)
		# Полотно, що впало, виштовхує з-під себе повітря: 4 низькі клуби вздовж прольоту підскакують
		# і далі ще здіймаються сталою тягою — 0,6–1 м за секунду — та зносяться на ~0,5 м.
		_dust_puffs(root, rng, 4, Vector3.ZERO, basis, box, 0.8, 1.8, 1.8, colours, 0.4, 0.7, 30.0, 0.6, 0.32, 0.5, wet)
	if live_wire:
		var up: Vector3 = top - at
		_arc(root, rng, up, 3, 1.1)
		# Іскри дуги й краплі розплаву: віялом на всі боки й одразу вниз під вагою, 0,4 с емісії.
		var drip := _sparks(root, "ArcSparks", 24, up, Vector3.DOWN, 180.0, 0.5, 4.5, 0.2, 0.5, 0.6, 1.5, 0.0)
		drip.explosiveness = 0.7
	_expire(root, TOPPLE_HIT_SEC)
	return root


## Мить, коли повалене (чи його частини) вдаряється об землю: модель той, хто кличе, ховає чи
## розсипає сам. a→b — відрізок на землі, який повалене накрило (опора: основа→верхівка; паркан:
## середня лінія полотна); `pole` — як у `spawn_topple_hit`, не сказано — за довжиною (> 5 м).
## Опора: з-під усієї довжини одразу б'ють клуби з об'ємом, що здіймаються на 0,5–1 м за ~1 с і
## розчиняються; дрібна фракція й грудки летять дугами на 2–3 м. Паркан, що розлетівся ще на ударі,
## лише осідає малою клубою. Дріт під напругою іскрить там, де ліг кінець.
static func spawn_topple_land(parent: Node, a: Vector3, b: Vector3, debris: Debris, live_wire: bool, pole: bool = false) -> Node3D:
	var root := _root("ToppleLand", parent, a)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(a + b * 3.1)
	var flat := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var len_m: float = maxf(flat.length() * 8.0, 0.5)
	var is_pole: bool = pole or len_m > 5.0 or live_wire
	var basis := _along(flat)
	var mid: Vector3 = (b - a) * 0.5
	var line := Vector3(len_m * 0.5, 0.1, 0.3) / 8.0
	var low: Vector3 = mid + Vector3(0, 0.15 / 8.0, 0)
	var wet: float = clampf(wetness, 0.0, 1.0)
	var powder: float = POWDER[debris] * (1.0 - 0.5 * wet)
	var colours: Array[Color] = _dust_colours(debris, wet)
	var fine: Array = FINE[debris]
	var clods: int = roundi(CLODS[debris] * (1.0 + 0.6 * wet))
	if is_pole:
		_shards(root, "Fine", rng, fine[0], clampi(roundi(len_m * 1.2), 6, 14), low, basis, line, fine[1], fine[2], 2.0, 5.0, 70.0, 2.6)
		_shards(root, "Clods", rng, Shard.CLOD, clampi(roundi(len_m * 0.25) + clods, 3, 10), low, basis, line, 0.12, 0.26, 2.0, 5.0, 70.0, 2.6)
		_dust_puffs(root, rng, clampi(roundi(len_m * 1.6), 12, 16), mid, basis, line, 1.4, 3.4, 2.6, colours, 1.2, 1.8, 25.0, 1.0, 0.25 + 0.05 * powder, 0.2, wet)
	else:
		_shards(root, "Clods", rng, Shard.CLOD, clods, low, basis, line, 0.12, 0.22, 1.0, 3.0, 60.0, 2.2)
		_dust_puffs(root, rng, 4, mid, basis, line, 0.7, 1.5, 1.8, colours, 0.5, 0.8, 35.0, 0.8, 0.22, 0.3, wet)
	# Уламки падають на площину землі посередині відрізка (на схилі — компроміс двох кінців).
	var floor_box := GPUParticlesCollisionBox3D.new()
	floor_box.name = "Ground"
	floor_box.size = Vector3(len_m / 8.0 + 1.5, 0.5, 1.5)
	floor_box.transform = Transform3D(basis, mid - Vector3(0, 0.25, 0))
	root.add_child(floor_box)
	if live_wire:
		var tip: Vector3 = b - a + Vector3(0, 0.05 / 8.0, 0)
		_arc(root, rng, tip, 2, 1.1)
		_sparks(root, "Sparks", 20, tip, Vector3.UP, 75.0, 2.0, 6.0, 0.15, 0.4, 0.2, 0.5, 0.0)
	_expire(root, TOPPLE_LAND_SEC)
	return root


## Базис, у якого локальна X — уздовж `dir` по землі: коробки емісії лягають уздовж поваленого.
static func _along(dir: Vector3) -> Basis:
	var flat := Vector3(dir.x, 0.0, dir.z)
	var x: Vector3 = flat.normalized() if flat.length() > 1e-6 else Vector3.RIGHT
	return Basis(x, Vector3.UP, x.cross(Vector3.UP))


static func _dust_colours(debris: Debris, wet: float) -> Array[Color]:
	var dry: Array = DUST[debris]
	var out: Array[Color] = []
	for i in dry.size():
		# Від половини мокрості — уже грязь: River (~0,55) інакше давав сіро-бежеві плями.
		out.append((dry[i] as Color).lerp(MUD_SPRAY[i], clampf(wet * 2.0, 0.0, 1.0)))
	return out


## Уламки повалення: `amount` шматків форми `shape` (`s_min`–`s_max` м уздовж найдовшої сторони)
## народжуються в коробці `extents` (тайли, локально до `basis`) і летять віялом `spread`° від
## вертикалі на `v_min`–`v_max` м/с — пологі дуги на 2–4 м за 0,3–0,5 с. Обертання стихає до
## приземлення: інакше шматок дзиґою крутився б на землі.
static func _shards(root: Node3D, node_name: String, rng: RandomNumberGenerator, shape: Shard, amount: int, at: Vector3, basis: Basis, extents: Vector3, s_min: float, s_max: float, v_min: float, v_max: float, spread: float, life: float) -> GPUParticles3D:
	var em := _debris_emitter(root, node_name, amount, v_max / 8.0, _shard_mesh(shape), s_min / 8.0, s_max / 8.0, life)
	em.transform = Transform3D(basis, at)
	em.use_fixed_seed = true
	em.seed = rng.randi()
	# Сфера зіткнення частинки — завтовшки зі шматок (товщина ~0,15 довжини), а не з його довжину:
	# інакше довгі куски висіли б над землею.
	em.collision_base_size = 0.15
	var pm := em.process_material as ParticleProcessMaterial
	pm.initial_velocity_min = v_min / 8.0
	pm.spread = spread
	pm.collision_bounce = 0.3
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = extents
	pm.lifetime_randomness = 0.2
	var flight: float = clampf(debris_flight_sec(v_max) / life, 0.05, 0.9)
	var spin := Curve.new()
	spin.add_point(Vector2(0.0, 1.0))
	spin.add_point(Vector2(flight, 0.0))
	var spin_t := CurveTexture.new()
	spin_t.curve = spin
	pm.angular_velocity_curve = spin_t
	# Кожен шматок трохи світліший чи темніший: однакові уламки читаються штампом.
	var shade := Gradient.new()
	# Під хмарами мокрої мапи затемнені уламки тонули в чорне (36 проти землі 79): там вони трохи
	# світліші за сухі, щоб лишатися бурими.
	var damp_k: float = 1.0 + 0.15 * clampf(wetness, 0.0, 1.0)
	shade.colors = PackedColorArray([Color.WHITE * 0.8 * damp_k, Color.WHITE * damp_k])
	var shade_t := GradientTexture1D.new()
	shade_t.gradient = shade
	pm.color_initial_ramp = shade_t
	return em


## Пил повалення: `amount` клуб атласу ґрунту `d_min`–`d_max` м в одній системі частинок — один
## виклик малювання на всю хмару — з тим самим виглядом, що клуба ґрунту влучання (`_SETTLE_CODE`).
## Клуби стоять рівномірно вздовж `extents` (тайли, локально до `basis`) щільніше за пів діаметра й
## кожна рідка (`peak` ~0,25): перекриваючись, вони складаються в одну масу, а не в намисто. Усі
## народжуються разом, летять угору віялом `spread`° на `v_min`–`v_max` м/с і гальмують на `damp` м/с²,
## а ще здіймаються сталою тягою `lift` м/с і зносяться вбік на ~0,4 м/с (за вітром, у штиль — у свій
## бік з хешу місця); ростуть удвічі й розчиняються до нуля на кінці життя `life`. Відстані між
## клубами гуляють на ±40 %, розміри — від `d_min` до `d_max`: однакові сусіди читалися б грудками.
## Колір — випадкова суміш `colours` (лінійні). Мокра земля (`wet` > 0,5) у дощ не куриться: низька
## темно-бура бризка грязі, що підскакує й за 0,7 с падає назад.
static func _dust_puffs(root: Node3D, rng: RandomNumberGenerator, amount: int, at: Vector3, basis: Basis, extents: Vector3, d_min: float, d_max: float, life: float, colours: Array[Color], v_min: float, v_max: float, spread: float, damp: float, peak: float, lift: float, wet: float) -> GPUParticles3D:
	var splash: bool = wet > 0.5
	if splash:
		d_min = 0.7
		d_max = 1.3
		life = 0.7
		v_min = 1.5
		v_max = 2.4
		damp = 0.0
		lift = 0.0
		peak = 0.85
	if _settle_mesh == null:
		_settle_mesh = QuadMesh.new()
		_settle_mesh.size = Vector2.ONE
		var mat := ShaderMaterial.new()
		mat.shader = Shader.new()
		mat.shader.code = _SETTLE_CODE
		mat.set_shader_parameter("tex", DIRT_TEX)
		mat.set_shader_parameter("frames", SETTLE_FRAMES)
		mat.set_shader_parameter("full", SETTLE_FULL)
		mat.set_shader_parameter("anchor", anchor_of(DIRT_TEX))
		_settle_mesh.material = mat
	var em := GPUParticles3D.new()
	em.name = "Settle"
	em.amount = amount
	em.lifetime = life
	em.one_shot = true
	# Усі разом: пізні клуби одноразова система обрізала б на кінці циклу — пів хмари зникало б
	# за кадр.
	em.explosiveness = 1.0
	em.local_coords = false
	em.use_fixed_seed = true
	em.seed = rng.randi()
	# Ближчі клуби поверх дальших: у порядку народження вони перескакували б одна через одну.
	em.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	em.transform = Transform3D(basis, at)
	var pm := ParticleProcessMaterial.new()
	# Клуби рівномірно вздовж відрізка (з тремтінням), а не навмання: випадкові збивались у
	# грона з дірками між ними, і пил читався намистом.
	var pts := Image.create(amount, 1, false, Image.FORMAT_RGBF)
	for i in amount:
		var u: float = (float(i) + 0.5 + rng.randf_range(-0.4, 0.4)) / float(amount) * 2.0 - 1.0
		pts.set_pixel(i, 0, Color(u * extents.x, rng.randf_range(-1.0, 1.0) * extents.y, rng.randf_range(-1.0, 1.0) * extents.z))
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
	pm.emission_point_texture = ImageTexture.create_from_image(pts)
	pm.emission_point_count = amount
	pm.direction = Vector3.UP
	pm.spread = spread
	pm.initial_velocity_min = v_min / 8.0
	pm.initial_velocity_max = v_max / 8.0
	pm.damping_min = damp * 0.8 / 8.0
	pm.damping_max = damp * 1.2 / 8.0
	# Бризка грязі важка: падає назад за ~0,6 с.
	pm.gravity = Vector3(0.0, -7.0 / 8.0, 0.0) if splash else Vector3.ZERO
	# Знесення й тяга вгору — окрема стала швидкість (directional velocity), яку гальмування не
	# з'їдає: інакше пил зупинявся б на місці за секунду.
	var side: Vector3 = Vector3(wind.x, 0.0, wind.z)
	if side.length() < 0.05:
		var ang: float = rng.randf_range(0.0, TAU)
		side = Vector3(cos(ang), 0.0, sin(ang))
	var push: Vector3 = side.normalized() * (0.0 if splash else 0.4) + Vector3.UP * lift
	var push_ms: float = maxf(push.length(), 1e-3)
	side = basis.inverse() * (push / push_ms)
	var drift_c := CurveXYZTexture.new()
	for c in 3:
		var cv := Curve.new()
		cv.min_value = -1.0
		cv.add_point(Vector2(0.0, side[c]))
		cv.add_point(Vector2(1.0, side[c]))
		if c == 0:
			drift_c.curve_x = cv
		elif c == 1:
			drift_c.curve_y = cv
		else:
			drift_c.curve_z = cv
	pm.directional_velocity_curve = drift_c
	pm.directional_velocity_min = push_ms * 0.8 / 8.0
	pm.directional_velocity_max = push_ms * 1.2 / 8.0
	pm.lifetime_randomness = 0.25
	var k: float = DIRT_CELL_M / DIRT_CLOUD_M / 8.0
	pm.scale_min = d_min * k
	pm.scale_max = d_max * k
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 1.0))
	sc.add_point(Vector2(1.0, 1.3 if splash else 2.1))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	pm.angle_min = -20.0
	pm.angle_max = 20.0
	var mix := Gradient.new()
	mix.colors = PackedColorArray(colours)
	var mix_t := GradientTexture1D.new()
	mix_t.gradient = mix
	pm.color_initial_ramp = mix_t
	# Проступає за 4 % життя; до нуля на кінці її доводить ерозія шейдера.
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.04, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, peak), Color(1, 1, 1, peak * 0.8)])
	var fade_t := GradientTexture1D.new()
	fade_t.gradient = fade
	pm.color_ramp = fade_t
	em.process_material = pm
	em.draw_pass_1 = _settle_mesh
	em.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	em.layers = 1 << (UnitView.UNIT_LAYER - 1)
	em.visibility_aabb = AABB(Vector3(-3, -0.5, -3), Vector3(6, 3, 6))
	root.add_child(em, true)
	em.emitting = true
	return em


## Дуга дроту під напругою: одне рване синьо-біле ядро `d_m` м (зубчасті розряди, свій узор на
## кожен спалах) і одне блакитне світло на 1–2 м довкола спалахують `flashes` разів по 30–60 мс
## через нерівні проміжки (з хешу місця) — не в такт і не мерехтінням на місці; світло потім
## звільняється. Світло слабке: яскраве робило з усієї опори білу блискавку.
static func _arc(root: Node3D, rng: RandomNumberGenerator, offset: Vector3, flashes: int, d_m: float) -> void:
	if _hot_shader == null:
		_hot_shader = Shader.new()
		_hot_shader.code = _HOT_CODE
	var mat := ShaderMaterial.new()
	mat.shader = _hot_shader
	mat.render_priority = PRIORITY_CORE + 1
	mat.set_shader_parameter("size", d_m / 8.0)
	mat.set_shader_parameter("pull", 0.0)
	mat.set_shader_parameter("arc", 1.0)
	var q := _quad_instance(root, "Arc", mat)
	q.position = offset
	q.visible = false
	var light := OmniLight3D.new()
	light.name = "ArcLight"
	light.light_color = Color(0.72, 0.84, 1.0)
	light.light_energy = 0.0
	light.omni_range = 2.0 / 8.0
	# На пів метра від опори: світло впритул вибілювало її стовбур до білого.
	light.position = offset + Vector3(0.35, 0.0, 0.35) / 8.0
	light.layers = 1 << (UnitView.UNIT_LAYER - 1)
	root.add_child(light)
	var tw: Tween = root.create_tween()
	var gap: float = rng.randf_range(0.0, 0.03)
	for i in flashes:
		var sec: float = rng.randf_range(0.03, 0.06)
		var energy: float = rng.randf_range(0.38, 0.6)
		var pattern: float = rng.randf_range(0.0, 97.0)
		tw.tween_interval(gap)
		tw.tween_callback(func() -> void:
			mat.set_shader_parameter("seed", pattern)
			q.visible = true
			light.light_energy = energy)
		tw.tween_method(func(f: float) -> void: mat.set_shader_parameter("heat", f), 0.0, 1.0, sec)
		tw.tween_callback(func() -> void:
			q.visible = false
			light.light_energy = 0.0)
		gap = rng.randf_range(0.08, 0.25) if i == 0 else rng.randf_range(0.15, 0.45)
	tw.tween_callback(light.queue_free)


## Форма дрібного уламка повалення, довжина 1 уздовж X: скол бетону, тріска, гнутий клапоть
## профлисту, гнутий прут, грудка землі. Колір — у вершинах:
## усі уламки ділять один матеріал (один шейдер на розігріві).
static func _shard_mesh(shape: Shard) -> ArrayMesh:
	if _shard_meshes.has(shape):
		return _shard_meshes[shape]
	if _shard_mat == null:
		_shard_mat = StandardMaterial3D.new()
		_shard_mat.vertex_color_use_as_albedo = true
		_shard_mat.vertex_color_is_srgb = true
		_shard_mat.roughness = 0.95
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Дерево лишає колір кори й потемнілої деревини, не світліє на зламі.
	var wood := Color(0.22, 0.165, 0.11)
	match shape:
		Shard.CHIP:
			_bar(st, 2, 1.0, 0.4, 0.33, 0.0, 0.0, Color(0.48, 0.47, 0.45), 0.25, 1)
		Shard.SPLINTER:
			_bar(st, 4, 1.0, 0.07, 0.035, 0.03, 1.0, wood, 0.1, 3)
		Shard.SHEET:
			_bar(st, 5, 1.0, 0.35, 0.008, 0.12, 0.0, Color(0.3, 0.3, 0.27), 0.08, 5)
		Shard.ROD:
			_bar(st, 5, 1.0, 0.012, 0.012, 0.18, 0.0, Color(0.24, 0.24, 0.23), 0.0, 6)
		Shard.CLOD:
			# Бура грудка ґрунту; на мокрій мапі її темнить `_shards`.
			_bar(st, 2, 1.0, 0.42, 0.34, 0.0, 0.0, Color(0.275, 0.204, 0.133), 0.28, 7)
	st.generate_normals()
	var mesh: ArrayMesh = st.commit()
	mesh.surface_set_material(0, _shard_mat)
	_shard_meshes[shape] = mesh
	return mesh


## Брус уздовж X: `stations` перерізів на довжині `length`, півширина `w` (Z), півтовщина `h` (Y),
## прогин `bend` (зсув кінців угору, частка довжини), `taper` 1 — гострі кінці (тріска). Вершини
## перерізів зсунуті шумом на `jag` (рваний злам, а не різ); `salt` — свій шум кожній формі.
static func _bar(st: SurfaceTool, stations: int, length: float, w: float, h: float, bend: float, taper: float, col: Color, jag: float, salt: int) -> void:
	var rings: Array[PackedVector3Array] = []
	for i in stations:
		var u: float = float(i) / float(stations - 1)
		var c: float = 2.0 * u - 1.0
		var k: float = 1.0 - taper * 0.9 * pow(absf(c), 1.5)
		var x: float = c * length * 0.5
		var y0: float = bend * length * c * c
		var ring := PackedVector3Array()
		for corner in 4:
			var sy: float = 1.0 if corner < 2 else -1.0
			var sz: float = 1.0 if corner == 0 or corner == 3 else -1.0
			var p := Vector3(x, y0 + sy * h * k, sz * w * k)
			var n := Vector3(_hash01(salt, i, corner, 0), _hash01(salt, i, corner, 1), _hash01(salt, i, corner, 2)) * 2.0 - Vector3.ONE
			# Рваними роблять кінці; середина бруса лишається рівною.
			var end: float = 1.0 if i == 0 or i == stations - 1 else 0.3
			p += n * jag * end * Vector3(length, maxf(w, h) * 2.0, maxf(w, h) * 2.0)
			ring.append(p)
		rings.append(ring)
	st.set_color(col)
	for i in stations - 1:
		for s in 4:
			var t: int = (s + 1) % 4
			_quad_tri(st, rings[i][s], rings[i + 1][s], rings[i + 1][t], rings[i][t])
	var a: PackedVector3Array = rings[0]
	var z: PackedVector3Array = rings[stations - 1]
	_quad_tri(st, a[0], a[1], a[2], a[3])
	_quad_tri(st, z[3], z[2], z[1], z[0])


static func _quad_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for p: Vector3 in [a, b, c, a, c, d]:
		st.add_vertex(p)


## Детермінований шум 0–1 для вершин уламків: без `sin` великих аргументів і без глобального rand.
static func _hash01(a: int, b: int, c: int, d: int) -> float:
	return float(hash([a, b, c, d]) % 10007) / 10006.0


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
				# 2–3 черги за 0,8 с: кожна куля — малий спалах і віяло коротких іскор.
				for burst in 3:
					var spot := Vector3(rng.randf_range(-0.1, 0.1), ROOF, rng.randf_range(-0.1, 0.1))
					_hot(root, 0.3, spot, burst * 0.3, PRIORITY_HOT, 0.04)
					# 3–6 рисок по 0,25–0,5 м (4–8 px на зумі 8), 80–120 мс, віялом від броні.
					_sparks(root, "Sparks", rng.randi_range(3, 6), spot, _ricochet(rng), 70.0, 3.0, 6.0, 0.25, 0.5, 0.08, 0.12, burst * 0.3)
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
				_dust(root, 1.75 * cloud, Vector3.ZERO, 0.8 * life, 0.8)
				_wave(root, rng, 1.75 * cloud, 0.8 * life)
				_debris(root, cloud)
		Weapon.SHELL:
			_hot(root, 6.0, Vector3(0, 0.12, 0), 0.0, PRIORITY_HOT, HOT_SEC, true)
			_light(root, 15.0, 4.0)
			# Центр хмари 155 мм — на 1,5–3 м вище за 3 с: власний підйом атласу знято (`hold`).
			_dirt(root, cloud, Vector3.ZERO, 0.0, 0.2, life, 0.6, 0.3)
			_core(root, cloud, 0.5 * life, 0.6, 0.3)
			# Приземна хвиля пилу ~3 клітинки завширшки: розбігається за 0,5 с, рідшає разом із хмарою.
			_dust(root, 24.0, Vector3.ZERO, 0.8 * life, 0.9)
			_wave(root, rng, 24.0, 0.8 * life)
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
			_hot(root, 1.5, Vector3.ZERO, r * 0.12, PRIORITY_HOT, MUZZLE_HOT_SEC, true)
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


## Межа одного шару, коли в миті `layers` шарів диму: разом вони не густіші за OCCLUDE_TOTAL.
static func occlude_cap(layers: int) -> float:
	return 1.0 - pow(1.0 - OCCLUDE_TOTAL, 1.0 / float(maxi(layers, 1)))


## Видимі живі юніти поруч (крім `except` — цілі чи стрільця) стають «щитом» для диму цієї миті.
static func _shield(root: Node3D, parent: Node, except: Vector3) -> void:
	var occ: Array[Vector4] = []
	for c: Node in parent.get_children():
		var u := c as UnitView
		# Невидимий юніт (поза розвіданим) не має сліду на екрані, а той, що гине, вже не сусід.
		if u == null or not u.visible or u.destroyed:
			continue
		var flat := Vector2(u.position.x - except.x, u.position.z - except.z)
		if flat.length() < 0.3 or flat.length() > 3.0 or occ.size() >= OCCLUDE_MAX:
			continue
		occ.append(Vector4(u.position.x, u.position.y + 0.15, u.position.z, OCCLUDE_R))
	if occ.is_empty():
		return
	var layers: Array[ShaderMaterial] = []
	var wave: Array[ShaderMaterial] = []
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mat := (n as MeshInstance3D).material_override as ShaderMaterial
		if mat != null and mat.shader == _mix_shader:
			(wave if String(n.name).begins_with("Wave") else layers).append(mat)
	# Хвиля пилу — окремий малий бюджет: над точкою сусіда перекривається одна-дві її клуби.
	for mat in wave:
		mat.set_shader_parameter("occ_cap", WAVE_CAP)
	for mat in layers:
		mat.set_shader_parameter("occ_cap", occlude_cap(layers.size()))
	for mat in layers + wave:
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
	# Хвиля розходиться від 0,3 до повного радіуса за DUST_SPREAD_SEC, далі лише рідшає.
	root.create_tween().tween_method(func(f: float) -> void: mat.set_shader_parameter("spread", f), 0.0, 1.0, DUST_SPREAD_SEC).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
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
	# Над сусідом найяскравіша фаза кулі (перші FIREBALL_CUT_SEC) вирізана зовсім, далі куля не
	# густіша за 0,6, а з 0,3 с — за спільну межу миті.
	bmat.set_shader_parameter("occ_floor", 0.0)
	var cut: Tween = root.create_tween()
	cut.tween_interval(FIREBALL_CUT_SEC)
	cut.tween_method(func(f: float) -> void: bmat.set_shader_parameter("occ_floor", f), 0.0, 0.6, 0.05)
	bmat.set_shader_parameter("crown", 1.0)
	_play_smoke(root, ball, 0.12, FIRE_SEC, 0.0, rise, grow, Vector2(0.0, LAST_FRAME), Vector2.ZERO, 0.4)
	var smoke := _sprite(root, "Smoke", SMOKE_TEX, 64, side * SMOKE_SCALE, lift, 1.0)
	smoke.position = offset
	(smoke.material_override as ShaderMaterial).set_shader_parameter("crown", 1.0)
	_play_smoke(root, smoke, 0.3, life, 0.0, rise, grow, Vector2(6.0, LAST_FRAME), Vector2(0.1, 0.35), ERODE_FROM * life)


## Хмара ґрунту `cloud_m` метрів: ~80 % об'єму за `full` с, живе `life` с, здіймається на
## `rise` м/с і ширшає на частку `grow`.
static func _dirt(root: Node3D, cloud_m: float, offset: Vector3, delay: float, full: float, life: float, rise: float, grow: float) -> void:
	var q := _sprite(root, "Dirt", DIRT_TEX, 64, cloud_m * DIRT_CELL_M / DIRT_CLOUD_M / 8.0, 0.0, 1.0)
	q.position = offset
	(q.material_override as ShaderMaterial).set_shader_parameter("crown", 1.0)
	var f0: float = 4.0 + _vary(q, 0.35)
	_play_smoke(root, q, full, life, delay, rise, grow, Vector2(f0, LAST_FRAME), Vector2.ZERO, ERODE_FROM * life, 1.0, false, true)


## Низька хвиля пилу, що розбігається від розриву: 24 невисокі (~2 м) рідкі бежеві клуби по колу,
## кожна ширша за крок між ними, зливаються в суцільний вал без «намиста» і з ease-out за DUST_SPREAD_SEC доходять до `d_m`/2 від центру;
## розчиняються за `life` с. Над сусідом вони лише рідшають (WAVE_CAP), а не вирізаються.
static func _wave(root: Node3D, rng: RandomNumberGenerator, d_m: float, life: float) -> void:
	var n: int = 24
	for i in n:
		var ang: float = TAU * (float(i) + rng.randf_range(-0.3, 0.3)) / float(n)
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var q := _sprite(root, "Wave", DIRT_TEX, 64, 3.25 * rng.randf_range(0.75, 1.25) * DIRT_CELL_M / DIRT_CLOUD_M / 8.0, 0.0, 1.0)
		# Розбіг від 0,25 клітинки (пляма 0,5 клітинки) до краю хвилі.
		q.position = dir * 0.25
		var mat := q.material_override as ShaderMaterial
		mat.set_shader_parameter("tint", Vector4(0.27, 0.24, 0.19, 0.7))
		mat.set_shader_parameter("feather", 1.0)
		var reach: float = (d_m * 0.5 * rng.randf_range(0.85, 1.0)) / 8.0
		_play_smoke(root, q, 0.15, life * rng.randf_range(0.7, 1.0), 0.0, 0.2, 0.8, Vector2(28.0 + float(i % 5), LAST_FRAME), Vector2.ZERO, 0.2 * life, 0.5, false, false, RISE_TAU_SEC, 1.0, dir * (reach - 0.25))


## Чорне ядро фугасного розриву в ґрунті: 155 мм на +0,1 с — чорна куля, і лише за 1–2 с її
## розбавляє бурий пил. Квад диму на 0,8 хмари ґрунту, поверх неї (і поверх гарячого ядра),
## сіро-бурий, проступає рівно за 0,15 с (не стрибком із бурого в сірий) і розчиняється за `life` с;
## рухається тією ж кривою, що й хмара.
static func _core(root: Node3D, cloud_m: float, life: float, rise: float, grow: float) -> void:
	var side: float = 0.8 * cloud_m * DIRT_CELL_M / DIRT_CLOUD_M / 8.0
	var q := _sprite(root, "Core", SMOKE_TEX, 64, side, 0.0, 1.0)
	var mat := q.material_override as ShaderMaterial
	mat.render_priority = PRIORITY_CORE
	mat.set_shader_parameter("tint", Vector4(0.13, 0.11, 0.085, 0.35))
	# Без темного жорсткого згустка вгорі хмари: на третину світліше й з розмитим краєм.
	mat.set_shader_parameter("gain", 1.3)
	mat.set_shader_parameter("feather", 1.0)
	_play_smoke(root, q, 0.15, life, 0.0, rise, grow, Vector2(4.0, 30.0), Vector2(0.0, 0.15), ERODE_FROM * life, 0.9)


## Сіра клуба диму й окалини (влучання в броню): той самий атлас ґрунту, знебарвлений і
## трохи світліший.
static func _puff(root: Node3D, cloud_m: float, offset: Vector3, delay: float, full: float, life: float, rise: float, grow: float) -> void:
	var q := _sprite(root, "Puff", DIRT_TEX, 64, cloud_m * DIRT_CELL_M / DIRT_CLOUD_M / 8.0, 0.0, 1.15)
	q.position = offset
	(q.material_override as ShaderMaterial).set_shader_parameter("desat", 1.0)
	var f0: float = 6.0 + _vary(q, 0.6)
	_play_smoke(root, q, full, life, delay, rise, grow, Vector2(f0, LAST_FRAME), Vector2.ZERO, ERODE_FROM * life)


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
	mat.set_shader_parameter("roll", rng.randf_range(-PI, PI))
	_play_smoke(root, q, 0.25, life, delay, 0.5, 1.0, Vector2(rng.randf_range(0.0, 6.0), LAST_FRAME), Vector2.ZERO, life, 0.85, true, false, 0.5, 0.6)


## Кожна дрібна клуба — свій поворот (±`spin` рад) і свій початковий кадр атласу: однакові
## «цвітні капустини» в черзі чи в пороховому димі читаються штампом.
static func _vary(q: MeshInstance3D, spin: float) -> float:
	var mat := q.material_override as ShaderMaterial
	var u: float = fposmod(float(mat.get_shader_parameter("seed")) * 0.618034, 1.0)
	mat.set_shader_parameter("roll", (u * 2.0 - 1.0) * spin)
	return floorf(fposmod(u * 7.0, 1.0) * 5.0)


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
	mat.set_shader_parameter("occ_cap", 1.0)
	mat.set_shader_parameter("occ_floor", 1.0)
	mat.set_shader_parameter("feather", 0.0)
	# Свій зерно кожному квадові миті: інакше однакові клуби (черга, порох) мали б однакові кадр і поворот.
	mat.set_shader_parameter("seed", float(hash(root.position + Vector3(size, lift, frames + root.get_child_count())) % 101))
	mat.set_shader_parameter("roll", 0.0)
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
static func _play_smoke(root: Node3D, q: MeshInstance3D, full: float, life: float, delay: float, rise: float, grow: float, frames: Vector2 = Vector2(0.0, LAST_FRAME), fade_in: Vector2 = Vector2.ZERO, erode_from: float = 0.0, opacity: float = 1.0, linear_fade: bool = false, hold: bool = false, grow_tau: float = RISE_TAU_SEC, scale0: float = 1.0, run: Vector3 = Vector3.ZERO) -> void:
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
		# `run` — розбіг від розриву (хвиля пилу): ease-out за DUST_SPREAD_SEC.
		var out: float = 1.0 - pow(1.0 - clampf(t / DUST_SPREAD_SEC, 0.0, 1.0), 3.0)
		q.position = base + Vector3(0.0, rise_m(rise, t), 0.0) / 8.0 + drift * drift_m(t) / 8.0 + run * out
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


## Клуба пилу повалення — частинка, а не окремий квад, але той самий вигляд, що в клуби ґрунту
## влучання (`_dirt`, `_SPRITE_CODE`): квад у камеру з точкою вибуху атласу на місці частинки, атлас
## грає від раннього кадру до повного об'єму за `full` частку життя і далі повзе до кінця, тож
## клуба сама здіймається й має об'єм. Перефарбування (COLOR) тримає світлотінь атласу, розмитий
## край, розчинення шумовим порогом від 35 % життя до нуля на кінці; м'який край лише там, де квад
## врізається в землю.
const _SETTLE_CODE: String = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, skip_vertex_transform;

uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform vec2 grid = vec2(8.0);
uniform vec2 frames = vec2(4.0, 40.0);
uniform float full = 0.1;
uniform vec2 anchor = vec2(0.0);
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
global uniform float sky_clear;
varying float v_frame;
varying float v_life;
varying float v_seed;
varying float v_depth;
""" + _NOISE_CODE + """
void vertex() {
	float s = length(MODEL_MATRIX[0].xyz);
	float r = INSTANCE_CUSTOM.x;
	vec2 v = vec2(cos(r) * VERTEX.x - sin(r) * VERTEX.y, sin(r) * VERTEX.x + cos(r) * VERTEX.y) + anchor;
	vec3 world = MODEL_MATRIX[3].xyz + (INV_VIEW_MATRIX[0].xyz * v.x + INV_VIEW_MATRIX[1].xyz * v.y) * s;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	v_seed = fract(float(INSTANCE_ID) * 0.618034 + fract(MODEL_MATRIX[3].x * 3.7));
	v_life = INSTANCE_CUSTOM.y;
	// Як BattleFx.smoke_frame: різко до повного об'єму (кадр 16), далі повільніше до кінця.
	float f0 = frames.x + floor(v_seed * 4.0);
	float u = clamp(v_life / full, 0.0, 1.0);
	v_frame = v_life < full ? mix(f0, 16.0, 1.0 - (1.0 - u) * (1.0 - u)) : mix(16.0, frames.y, pow((v_life - full) / (1.0 - full), 0.75));
	v_depth = min(s * 0.2, 1.5 / 8.0);
}

vec4 frame_at(float f, vec2 uv) {
	float n = clamp(f, 0.0, 63.0);
	return texture(tex, (clamp(uv, vec2(0.002), vec2(0.998)) + vec2(mod(n, grid.x), floor(n / grid.x))) / grid);
}

void fragment() {
	vec4 t = mix(frame_at(floor(v_frame), UV), frame_at(floor(v_frame) + 1.0, UV), fract(v_frame));
	float luma = dot(t.rgb, vec3(0.2126, 0.7152, 0.0722));
	// Контраст атласу (темна середина, світлий обідок) приглушено до середнього: у дрібних клубах
	// він читався ватяними кульками з обідком.
	ALBEDO = mix(t.rgb, COLOR.rgb * (0.94 + 0.12 * smoothstep(0.0, 0.3, luma)), 0.92) * (1.0 + 0.3 * sky_clear);
	// Згасання з пологим кінцем (smoothstep): поріг шуму рве край, а до нуля клубу доводить множник —
	// інакше остання третина хмари зникала за 0,4 с.
	float erode = smoothstep(0.3, 1.0, v_life);
	float n = vnoise(UV * 7.0 + v_seed * 31.0) * 0.6 + vnoise(UV * 17.0 + v_seed * 13.0) * 0.4;
	float thr = erode * 0.75;
	float keep = smoothstep(thr - 0.25, thr, t.a * (0.6 + 0.4 * n));
	// Корінь прозорості атласу: середина клуби пласкіша, ніж в атласі, але край ще м'який —
	// без кореня клуба була б пласким диском.
	float a = sqrt(t.a) * smoothstep(0.0, 0.7, t.a) * keep * COLOR.a * (1.0 - erode);
	// shortcut: глибина в NDC як у Vulkan (Forward+/Mobile); Compatibility дає z*2-1, край там жорсткіший.
	vec4 sv = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, texture(depth_tex, SCREEN_UV).r, 1.0);
	ALPHA = a * clamp((VERTEX.z - sv.z / sv.w) / v_depth, 0.0, 1.0);
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
// Дуга дроту під напругою: біле ядро, синьо-блакитний край.
uniform float arc = 0.0;
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
	if (arc > 0.0) {
		// Дуга — не диск: мала біла точка й зубчасті розряди, що ламаються вздовж радіуса (шум від
		// напрямку й радіуса, без шва atan), свій узор на кожен спалах (seed); блакитна слабка імла.
		vec2 q = UV - 0.5;
		vec2 dir = q / max(length(q), 1e-4);
		float bolt = smoothstep(0.6, 0.85, vnoise(dir * 2.6 + vec2(r * 6.0, -r * 4.0) + seed));
		bolt *= 1.0 - smoothstep(0.35, 0.95, r);
		float core = 1.0 - smoothstep(0.03, 0.14, r);
		float haze = 0.06 * pow(clamp(1.0 - r, 0.0, 1.0), 4.0);
		ALBEDO = mix(vec3(1.0), vec3(0.55, 0.72, 1.0), smoothstep(0.05, 0.5, r) * (1.0 - 0.5 * bolt));
		ALPHA = clamp(core + bolt + haze, 0.0, 1.0) * (1.0 - 0.5 * heat);
	}
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
uniform float spread = 1.0;
uniform float opacity = 1.0;
uniform float seed = 0.0;
global uniform float sky_clear;
// Лінійна вибірка глибини: найближча давала зубці на межі рельєфу.
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
	// Найдальший край — 0,8 півкваду: форма ніколи не впирається в квадрат.
	float R = mix(0.17, 0.85, spread) * (0.75 + 0.25 * petals);
	float d = fbm(UV * 3.5 + seed);
	float edge = 1.0 - smoothstep(0.45, 1.0, r / R + (d - 0.5) * 0.35);
	float body = edge * pow(clamp(1.0 - r / R, 0.0, 1.0), 0.35);
	ALBEDO = vec3(0.23, 0.20, 0.16) * (0.85 + 0.3 * d) * (1.0 + 0.3 * sky_clear);
	// Останнє вікно: що б не нашуміли пелюстки, біля краю кваду альфа вже нуль — без прямої
	// діагональної сходинки по ребру кваду.
	ALPHA = body * (0.5 + 0.5 * d) * opacity * 0.8 * (1.0 - smoothstep(0.3, 1.0, progress)) * (1.0 - smoothstep(0.85, 0.98, r));
	// shortcut: глибина в NDC як у Vulkan (Forward+/Mobile); Compatibility дає z*2-1, і м'який
	// спад біля рельєфу там буде хибним — пил різатиметься жорсткіше.
	vec4 sv = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, texture(depth_tex, SCREEN_UV).r, 1.0);
	ALPHA *= clamp((VERTEX.z - sv.z / sv.w) / (0.4 / 8.0), 0.0, 1.0);
}
"""


## Квад флипбука в камеру. Колір і пряма альфа — з самого атласу (він уже освітлений і
## розфарбований); між кадрами — плавний перехід, бо один кадр атласу триває кілька кадрів
## екрана.
const _SPRITE_CODE: String = """
shader_type spatial;
// Смуга «голівки» в клітинці атласу (UV.y від верху) і кадр, з якого вона з'являється в симуляції:
// раніше верх — ще вогняна куля, і рвати його не можна.
const float CROWN_TOP = 0.05;
const float CROWN_BASE = 0.42;
const float CROWN_FROM = 10.0;
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
// за `occ_cap`, спад розмитий на тайл; `occ_k` вмикає це до 0,3 с.
uniform vec4 occ0;
uniform vec4 occ1;
uniform vec4 occ2;
uniform vec4 occ3;
uniform vec4 occ4;
uniform vec4 occ5;
uniform int occ_n = 0;
uniform float occ_k = 0.0;
// Межа шару над сусідом (BattleFx.occlude_cap): усі шари миті разом ≤ 0,45; 1 — без межі.
uniform float occ_cap = 1.0;
// Межа до 0,3 с, поки `occ_k` не ввімкнув повну (вогняна куля — 0,6 від першого кадру).
uniform float occ_floor = 1.0;
// Поворот кваду в площині кадру довкола його середини (дрібні клуби — кожна по-своєму).
uniform float roll = 0.0;
// Розмитий край клуби (пороховий дим): рідкі краї атласу ще прозоріші.
uniform float feather = 0.0;
// Верх хмари: в атласах симуляції на пізніх кадрах угорі сидить щільна темна «голівка» стовпа з
// плоским зрізом об стелю обсягу. 0 — як в атласі; 1 — вона рвано розсіюється (поріг шуму тим
// вищий, чим ближче до верху клітинки), а не висить окремою кулею над димом.
uniform float crown = 0.0;
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
	vec2 v = vec2(cos(roll) * VERTEX.x - sin(roll) * VERTEX.y, sin(roll) * VERTEX.x + cos(roll) * VERTEX.y);
	vec3 world = c + (INV_VIEW_MATRIX[0].xyz * v.x + INV_VIEW_MATRIX[1].xyz * v.y) * s;
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
	// «Голівка» проступає з кадру CROWN_FROM: у перших кадрах вогняна куля ще цілком, її верх не чіпаємо.
	// Шум рахується лише на шарах із crown > 0: решта шарів вибуху за нього не платить.
	if (crown > 0.0) {
		float top = (1.0 - smoothstep(CROWN_TOP, CROWN_BASE, UV.y)) * crown * smoothstep(CROWN_FROM, CROWN_FROM + 8.0, frame);
		float rag = vnoise(UV * 9.0 + seed * 1.3) * 0.6 + vnoise(UV * 23.0 + seed * 2.1) * 0.4;
		a *= mix(1.0, 0.5 * smoothstep(0.35, 0.7, rag), top);
	}
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
		inside = max(inside, 1.0 - smoothstep(occ[i].w, occ[i].w + 1.0, d));
	}
	float lim = mix(occ_floor, occ_cap, occ_k);
	// Межа вмикається плавно (від 1 до 0,9), а не стрибком, коли м'який край зникає над сусідом.
	ALPHA = mix(a * soft, min(a, lim), inside * (1.0 - smoothstep(0.9, 1.0, lim)));
}
"""
