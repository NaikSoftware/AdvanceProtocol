class_name UnitView
extends Node3D
## Юніт на дошці: примітив-заступник майбутнього 3D-асета, факінг, HP-бар,
## лічильник дронів і твін руху (§1.5, Task 2.4).
##
## Туман живе не тут. `UnitView` не читає й не питає тайлову видимість — вирішує, чи
## існувати цьому вузлу взагалі, власник контейнера (Task 2.10): ворожий
## юніт отримує вузол лише коли він є в known_occupied_map активного
## гравця (§3.5). Невидимий ворог не лишає силует — у нього просто нема вузла.

## Крок факінгу: вісім напрямків Board.DIRS_8 рівномірно по колу.
const _DEGREES_PER_FACING: float = 45.0
## Фаза 5a: усе видиме в юніті — лише на цьому шарі рендеру, щоб відбиття й
## тіні могли відсікти юнітів маскою (відбиття не сміють показати прихований юніт).
const UNIT_LAYER: int = 2
## Найбільший нахил корпусу за схилом, окремо вздовж і впоперек. Крутіший берег
## перекинув би модель на бік; там юніт лягає під цим кутом, а нижній край висить.
const MAX_TILT_DEG: float = 20.0
## Відділення стоїть рівно й на стільки нижче землі під центром: на схилі край основи не висить.
const SQUAD_SINK: float = 0.05

## Board.DIRS_8 іде ЗА годинниковою стрілкою (0 N, 2 E, 4 S, 6 W), а поворот
## навколо Y у Godot — ПРОТИ. Тому знак обов'язковий: `facing * 45` збігається
## з правдою лише для N і S, а схід зі заходом міняє місцями — юніт, що їде на
## схід, показує корму. Перевірено в рушії перебором усіх восьми напрямків.
##
## Чому це прожило довго: і ствол, і стрілка-інструмент розробника — діти того самого вузла,
## тож вони крутились разом і виглядали узгодженими між собою. Помилку видно
## лише порівнянням з НАПРЯМКОМ РУХУ, а не з іншою деталлю силуету.
static func _degrees_for_facing(direction: int) -> float:
	return -float(direction) * _DEGREES_PER_FACING

## §3.9: 2 дрони на загін за матч — більше ніколи не буває, тож це стеля
## відображення, а не число з ростера.
const _MAX_DRONES: int = 2

## Розмір текстури HP-смуги в пікселях. Довга й тонка (8:1), а не квадрат:
## при pixel_size=0.02 виходить 0.96×0.12 світової одиниці — майже на всю
## ширину тайла, як у референсі (там смуга рівно `tile_width - 1` завширшки
## і 3 px заввишки).
const _HP_BAR_SIZE: Vector2i = Vector2i(48, 6)
## Розмір пікселя смуги у світі (тайли): той самий у спрайті-носії стану й у спільного MultiMesh.
const HP_BAR_PIXEL_SIZE: float = 0.02

## Рамка й порожнє тло — всередині ТІЄЇ САМОЇ текстури, що й заливка.
## Три накладені білборд-спрайти на одній висоті дали б z-fighting і три
## різні центри обертання, а §8 тримає бюджет ~100 draw call'ів на екран.
const _HP_BAR_FRAME_COLOR: Color = Color("14120f")
const _HP_BAR_BACK_COLOR: Color = Color("3b3833")
const _HP_FILL_LIFT: float = 0.3

const _DESTROY_DURATION: float = 0.6
## HP-бар і підпис — поверх усіх ефектів (вогонь уламків має пріоритет 1) і без перевірки
## глибини: інакше полум'я перекривало б одні підписи, а інші лишались зверху.
const OVERLAY_PRIORITY: int = 10
## Фігур у відділенні; стоїть одна на кожну чверть HP, що лишилась.
const SQUAD_FIGURES: int = 4
const _FALL_SEC: float = 0.5
## Знищена техніка зникає під спалахом, і саме тим кроком анімація закінчується:
## програвач одразу грає WreckLeft, тож уламки стають на тайл у тому самому кадрі, ще
## під кулею, а не після того, як дим розійшовся.
const KILL_HIDE_DELAY: float = 0.06

## Постріл і відповідь (§3.3.1): короткий поштовх силуету. Скарга власника —
## «атака у відповідь не відбувається»: вона відбувалась, але на дошці її було
## видно рівно як тихий стрибок HP-бара свого юніта, і найдорожче правило гри
## читалось як зламане. Це не снаряд (його ще нема), це мінімальний такт «цей
## юніт вистрілив» — і саме він відділяє відповідь від власного пострілу.
const _SHOT_PUNCH_SCALE: float = 1.18
const _SHOT_PUNCH_UP: float = 0.07
const _SHOT_PUNCH_DOWN: float = 0.13

## R14: хід чекає на гравця, не навпаки — поворот твінується, але лишається
## коротким, щоб не виглядав як затримка вводу.
const FACE_TURN_DURATION: float = 0.15
## Радіус дуги, якою юніт проходить поворот маршруту, у тайлах. 1 тайл = 8 м — у межах
## заокруглень доріг (RoadCourse, 6–14 м), тож техніка на дорозі йде її вигином.
const TURN_RADIUS: float = 1.0
## Хорд на чверть кола: ніс інтерполюється між ними, хорди лише тримають позицію на дузі.
const _ARC_SEGMENTS: int = 8

## Абстрактні кольори гравців-плейсхолдерів (§2 — жодного реального прапора
## чи армії). Індекс — Unit.owner. Колір несе лише заливка смуги HP: юніти
## різняться власником за нею, корпус однаковий для всіх.
const PLAYER_COLORS: Array[Color] = [
	Color("3a6ea5"),
	Color("a54a3a"),
	Color("5a8a4a"),
]

## --- ЧАСОВИЙ ІНСТРУМЕНТ РОЗРОБНИКА (Task 2), почало ---------------------------------
## Примітиви-заступники (§1.5, коментар зверху файлу) не мають переду, який
## читається з фіксованого ізо-ракурсу так само однозначно, як читатиметься
## справжня модель — звідси скарга «де перед». Стрілка на даху корпусу —
## тимчасовий інструмент розробки, не ігрова інформація (є на кожному
## юніті, і своєму, і чужому, §3.13 — напрямок чужого юніта й так публічний).
##
## Одна точка вимкнення, а не вкраплення по коду: щоб прибрати стрілку,
## коли з'являться справжні моделі, досить (а) поставити прапорець нижче в
## false, або (б) видалити геть увесь цей блок разом із єдиним місцем, де
## стрілку будують і додають на дошку, — у _build_silhouette() нижче.
const _DEBUG_SHOW_FACING_ARROW: bool = false

## Яскравий, ненатуральний магента — свідомо поза палітрою решти юніта
## (гравці — приглушені сині/червоні/зелені, інженер — жовтий, ствол —
## темний метал), щоб стрілка ніколи не «зливалась із корпусом» і не
## читалась як щось ігрове. Той самий дух, що й «текстура відсутня» магента
## в інших рушіях — колір, який кричить «це заступник».
const _DEBUG_ARROW_COLOR: Color = Color("ff26d6")

## Трохи вище даху корпусу (уникнути z-fighting граней), і однозначно нижче
## HpBar (y=0.55) / HpLabel (y=0.65) / DroneIcon (y=0.8) з unit_view.tscn —
## стрілка не має перекривати жоден із них.
const _DEBUG_ARROW_Y_OFFSET: float = 0.02
## --- ЧАСОВИЙ ІНСТРУМЕНТ РОЗРОБНИКА (Task 2), кінець блоку констант -------------------

## Колір прицілу — рівно UnitInspector.MODULATE_HIT (game/ui/unit_inspector.gd:40),
## і не випадково: коментар там уже називає цей зв'язок («той самий сигнал
## “сюди прилетить”, що й у прицілі») — колір був зарезервований під цей приціл
## ще до того, як приціл з'явився. Два різні кольори про одне влучання читались
## би як два різні повідомлення: панель каже «сюди», дошка каже щось інше.
## Константа продубльована, а не імпортована з game/ui/: вигляд дошки не
## залежить від HUD — тест звіряє обидва значення й упаде, якщо вони розійдуться.
const _CROSSHAIR_COLOR: Color = Color("ff7a4a")
## Заборонена ціль дрона (§3.13): хрест, а не приціл, і інший колір — «сюди не можна»
## мусить читатись інакше, ніж «сюди прилетить».
const _FORBIDDEN_COLOR: Color = Color("d23c3c")
## Позначки огляду (§3.13) — кольори відповідних кілець, щоб читались як «у цьому кільці».
const _THREAT_COLOR: Color = TargetOverlay.GUN_RING_COLOR
const _DRONE_THREAT_COLOR: Color = TargetOverlay.DRONE_RING_COLOR

## Поточний факінг (0..7, порядок Board.DIRS_8). Читається ззовні для UI цілей.
var facing: int = 0
## Юніт гине (play_destroyed): дим довкола вже не береже його як сусіда (BattleFx).
var destroyed: bool = false

@onready var _silhouette: Node3D = $Silhouette
@onready var _crosshair: Sprite3D = $Crosshair
@onready var _forbidden: Sprite3D = $Forbidden
@onready var _threatened: Sprite3D = $Threatened
@onready var _drone_threatened: Sprite3D = $DroneThreatened
@onready var _hp_bar: Sprite3D = $HpBar
@onready var _hp_label: Label3D = $HpLabel
@onready var _drone_icon: Sprite3D = $DroneIcon

var _hull_material: Material
## Тіло — модель GLB (а не коробки): лише її шейдер крутить колеса й траки за пройденим шляхом.
var _has_model: bool = false
## Пройдений шлях в одиницях світу: від нього колеса й траки моделі крутяться в такт руху.
var _travel: float = 0.0
## Шлях за id юніта: дошка перебудовує вузли після кожної дії, і новий вузол інакше повертав би
## колеса в нульове положення одразу після руху.
static var _travel_by_unit: Dictionary = {}
var _unit_id: int = -1
var _type_id: int = 0
var _owner: int = 0
var _standing: int = 0
var _drones_left: int = 0
## Останнє показане співвідношення HP. Джерело правди замість колишнього
## _hp_bar.scale.x — заливка тепер намальована ВСЕРЕДИНІ текстури, тож
## масштаб вузла більше нічого про HP не каже.
var _hp_ratio: float = 1.0
## Живий твін останнього face(); тримаємо посилання, щоб наступний виклик
## міг убити цей замість того, щоб два твіни змагались за rotation_degrees.y.
var _face_tween: Tween
## Половини основи корпусу (x — ширина, y — довжина): по її кутах юніт ставиться на схил.
var _half_base: Vector2 = Vector2.ZERO
## Кут повороту, для якого востаннє рахувався нахил; NAN — ще не ставився.
var _posed_yaw: float = NAN
## Техніка нахиляється за схилом; відділення на одній основі лишається рівним.
var _tilts: bool = true


func _ready() -> void:
	# Кадр потрібен лише поки твін крутить юніт (див. _process).
	set_process(false)
	# Заступники текстур: суцільний колір замість реального арту, той самий
	# підхід, що й нейтральні кольори-плейсхолдери мін (MineLayer). HP-смуга сюди не
	# входить — її текстуру повністю володіє set_hp(), який і так кличеться
	# з кожного bind().
	_hp_bar.pixel_size = HP_BAR_PIXEL_SIZE
	_drone_icon.texture = _flat_texture(Color("d9b23a"))
	# Значки й смуга — інтерфейс, не тіло: у проході тіней кожен з них був би ще одним викликом.
	for n: GeometryInstance3D in [_crosshair, _forbidden, _threatened, _drone_threatened, _hp_bar, _hp_label, _drone_icon]:
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for n: Node in [_hp_bar, _hp_label]:
		n.set("no_depth_test", true)
		n.set("render_priority", OVERLAY_PRIORITY)
	_hp_label.outline_render_priority = OVERLAY_PRIORITY - 1
	# Форма — біла, колір дає modulate (той самий прийом, що й у HP-барі вище):
	# одне місце, де живе _CROSSHAIR_COLOR, і його видно в інспекторі.
	_crosshair.texture = _crosshair_texture()
	_crosshair.modulate = _CROSSHAIR_COLOR
	_forbidden.texture = _cross_texture()
	_forbidden.modulate = _FORBIDDEN_COLOR
	_threatened.texture = _crosshair_texture()
	_threatened.modulate = _THREAT_COLOR
	_drone_threatened.texture = _diamond_texture()
	_drone_threatened.modulate = _DRONE_THREAT_COLOR


func bind(unit: Unit) -> void:
	position = IsoCameraRig.cell_to_world(unit.pos)
	_type_id = unit.type_id
	_unit_id = unit.id
	_travel = _travel_by_unit.get(unit.id, 0.0)
	_build_silhouette(unit.type_id, unit.owner)
	_tilts = UnitTypes.is_vehicle(UnitTypes.get_type(unit.type_id)["unit_class"])
	# Свіжий вузол (чи перебудований battle_screen._rebuild_units_for_active_player)
	# не має попередньої орієнтації, з якої мало б сенс анімувати «доведення» —
	# твінований face() тут дав би видиме crank-довертання щоразу, коли дошка
	# перебудовується. Миттєве виставлення, не face().
	_set_facing_instant(unit.facing)
	_pose(position)
	set_hp(unit.hp, unit.max_hp())
	set_drones(unit.drones_left)
	# Свіжий (чи перебудований) вузол не є ціллю жодного прев'ю: прев'ю живе в
	# InputController і перебудову не переживає — лишити приціл увімкненим
	# означало б показувати намір, якого вже немає.
	set_targeted(false)
	set_forbidden(false)
	_put_on_unit_layer(self)
	# Плями стежать за вже виставленим поворотом і позою, тож реєструються наприкінці bind().
	if contacts != null:
		if _contact_on:
			contacts.track(self)
		else:
			contacts.untrack(self)
	if hp_bars != null:
		# Спрайт лишається вузлом стану (текстура, видимість), а малює смугу спільний MultiMesh.
		_hp_bar.layers = 0
		hp_bars.track(self)


## Силует перебудовується на кожен bind(), тож шар ставиться після нього.
static func _put_on_unit_layer(node: Node) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = 1 << (UNIT_LAYER - 1)
	for child: Node in node.get_children():
		_put_on_unit_layer(child)


## Твін по шляху, повертає tween.finished. AP і туман сюди не заглядають —
## контролер вирішує, коли рухати, view лише показує вже прийняте рішення.
##
## Юніт їде кривою, а не ламаною через центри клітинок: прямі ділянки, а на кожному
## повороті маршруту — дуга радіуса TURN_RADIUS, дотична до обох відрізків. Так машина
## на дорозі повторює її заокруглення, а не стає й не крутиться на перехресті. Ніс
## дивиться вздовж дотичної. Дуга лишається в клітинках маршруту: вона огинає центр
## діагональної клітинки на відстані радіуса, тож у сусідню клітинку не заходить.
## Сходинку з одиничних кроків юніт проходить навскіс, однією прямою.
##
## На місці юніт довертається лише перед стартом, коли перший крок іде не туди, куди він
## дивиться: розворот на 180° дугою — це задній хід або петля по чужих клітинках.
##
## final_facing — останнє слово: фейсинг, який вирішив core/, а не здогад вигляду з path.
## Якщо він інший, ніж напрямок останнього кроку, юніт довертається на місці в кінці.
## -1 (типово) — орієнтація лишається такою, якою її поставив останній крок.
##
## on_step(i) — у мить, коли юніт доїхав до path[i] (на повороті — до точки кривої,
## найближчої до центру клітинки): те, що core/ вирішило на цьому кроці (знахідка
## укриття), показується тут, а не після всього шляху. Колбек живе в цьому ж твіні.
func move_along(path: Array[Vector2i], duration_per_step: float, final_facing: int = -1,
		on_step: Callable = Callable()) -> Signal:
	# Той самий власник rotation_degrees.y, що й face(): живий твін повороту вбиваємо, а
	# цей зберігаємо, щоб наступний face() убив уже його.
	if _face_tween != null and _face_tween.is_valid():
		_face_tween.kill()
	var tween: Tween = create_tween()
	_face_tween = tween
	set_process(true)
	if path.is_empty():
		# Твін без жодного кроку міг би ніколи не подати finished.
		tween.tween_interval(0.0)
		return tween.finished

	var start_cell: Vector2i = IsoCameraRig.world_to_cell(position)
	var pts: Array[Vector2] = [Vector2(position.x, position.z)]
	for cell: Vector2i in path:
		var w: Vector3 = IsoCameraRig.cell_to_world(cell)
		pts.append(Vector2(w.x, w.z))
	var n: int = pts.size()
	# Опорна ламана. Самотній кут маршруту лишається вершиною. Кут, сусідній крок якого —
	# теж кут (сходинка, зсув на одну смугу), зрізаний між серединами ребер: сходинка
	# стає однією діагоналлю, а не змійкою дуг, що смикала б ніс щопівтайла. Діагональ
	# через середини ребер не торкається кутів клітинок, тож лишається в маршруті.
	# Розвороту на 180° посеред шляху не буває: шлях — найкоротший (Pathing.path_to).
	var corner := PackedByteArray()
	corner.resize(n + 1)
	for k in range(1, n - 1):
		if absf((pts[k] - pts[k - 1]).normalized().dot((pts[k + 1] - pts[k]).normalized())) < 0.01:
			corner[k] = 1
	var q := PackedVector2Array([pts[0]])
	for k in range(1, n):
		if corner[k] == 1 and (corner[k - 1] == 1 or corner[k + 1] == 1):
			_push(q, pts[k].lerp(pts[k - 1], 0.5))
			_push(q, pts[k].lerp(pts[k + 1], 0.5))
		else:
			_push(q, pts[k])

	# Кожен злам ламаної — дуга радіуса TURN_RADIUS, дотична до обох відрізків; відрізок
	# між двома дугами ділиться навпіл, і на тісному місці радіус менший.
	var m: int = q.size()
	var turn := PackedFloat32Array()
	turn.resize(m)
	var tl := PackedFloat32Array()
	tl.resize(m)
	for k in range(1, m - 1):
		turn[k] = (q[k] - q[k - 1]).angle_to(q[k + 1] - q[k])
		var t: float = TURN_RADIUS * tan(absf(turn[k]) * 0.5)
		t = minf(t, q[k].distance_to(q[k - 1]) * (0.5 if k > 1 else 1.0))
		tl[k] = minf(t, q[k].distance_to(q[k + 1]) * (0.5 if k < m - 2 else 1.0))

	# Дотична в кожній вершині — точна: на прямій це її напрям, на дузі — дотична кола.
	# Ніс між вершинами інтерполюється, тож не скаче сходинками по хордах.
	var line := PackedVector2Array([q[0]])
	var acc := PackedFloat32Array([0.0])
	var tangents := PackedVector2Array([(q[1] - q[0]).normalized()])
	for k in range(1, m):
		var d_in: Vector2 = (q[k] - q[k - 1]).normalized()
		var entry: Vector2 = q[k] - d_in * tl[k]
		_extend(line, acc, tangents, entry, d_in)
		if tl[k] <= 0.0:
			continue
		var r: float = tl[k] / tan(absf(turn[k]) * 0.5)
		var centre: Vector2 = entry + d_in.rotated(signf(turn[k]) * PI * 0.5) * r
		var segs: int = maxi(1, ceili(_ARC_SEGMENTS * absf(turn[k]) / (PI * 0.5)))
		for j in range(1, segs + 1):
			var a: float = turn[k] * float(j) / segs
			_extend(line, acc, tangents, centre + (entry - centre).rotated(a), d_in.rotated(a))

	# Клітинка шляху «досягнута» в найближчій до її центру точці кривої.
	var stations := PackedFloat32Array()
	var seg: int = 1
	for i in path.size():
		var c: Vector2 = pts[i + 1]
		var best: float = INF
		var best_s: float = 0.0
		var best_seg: int = seg
		for j in range(seg, line.size()):
			var ab: Vector2 = line[j] - line[j - 1]
			var u: float = clampf((c - line[j - 1]).dot(ab) / ab.length_squared(), 0.0, 1.0)
			var dist: float = c.distance_squared_to(line[j - 1] + ab * u)
			if dist < best - 1e-9:
				best = dist
				best_s = acc[j - 1] + (acc[j] - acc[j - 1]) * u
				best_seg = j
		seg = best_seg
		stations.append(maxf(best_s, stations[i - 1] if i > 0 else 0.0))
	stations[stations.size() - 1] = acc[acc.size() - 1]

	# Твін ще не виконався в момент побудови графа — кут доводиться передбачати, а не
	# перечитувати властивість (той самий прийом найкоротшої дельти, що й у face()).
	var predicted: float = rotation_degrees.y
	var start_delta: float = wrapf(_yaw_of(tangents[0]) - predicted, -180.0, 180.0)
	if absf(start_delta) > 0.01:
		tween.tween_property(self, "rotation_degrees:y", predicted + start_delta, FACE_TURN_DURATION)
	predicted += start_delta
	for t: Vector2 in tangents:
		predicted += wrapf(_yaw_of(t) - predicted, -180.0, 180.0)

	var follow: Callable = _follow.bind(line, acc, tangents)
	var from_s: float = 0.0
	for i in path.size():
		# Швидкість — тайл за duration_per_step: дуга коротша за ламану, і крок через неї теж.
		tween.tween_method(follow, from_s, stations[i], duration_per_step * (stations[i] - from_s))
		if on_step.is_valid():
			tween.tween_callback(on_step.bind(i))
		from_s = stations[i]

	var before_last: Vector2i = path[path.size() - 2] if path.size() > 1 else start_cell
	facing = Board.facing_towards(before_last, path[path.size() - 1])
	if final_facing >= 0 and final_facing != facing:
		var end_delta: float = wrapf(_degrees_for_facing(final_facing) - predicted, -180.0, 180.0)
		tween.tween_property(self, "rotation_degrees:y", predicted + end_delta, FACE_TURN_DURATION)
		facing = final_facing
	return tween.finished


## Додає вершину до опорної ламаної: збіг із попередньою відкидає, а продовження того
## самого відрізка зливає з ним, щоб дуги ставали лише на справжніх зламах.
static func _push(q: PackedVector2Array, p: Vector2) -> void:
	var last: int = q.size() - 1
	if q[last].distance_to(p) < 1e-4:
		return
	if last > 0 and absf((q[last] - q[last - 1]).normalized().cross((p - q[last]).normalized())) < 1e-4 \
			and (q[last] - q[last - 1]).dot(p - q[last]) > 0.0:
		q[last] = p
		return
	q.append(p)


## Додає вершину до кривої руху разом із довжиною шляху до неї й дотичною в ній. Вершина,
## що майже збігається з попередньою, заміняє її: кінець дуги лягає точно в центр клітинки,
## а не за похибку обертання від нього, і нульових відрізків без напрямку не буває.
static func _extend(line: PackedVector2Array, acc: PackedFloat32Array, tangents: PackedVector2Array,
		p: Vector2, tangent: Vector2) -> void:
	var last: int = line.size() - 1
	if line[last].distance_to(p) < 1e-4:
		if last > 0:
			line[last] = p
			acc[last] = acc[last - 1] + line[last - 1].distance_to(p)
			tangents[last] = tangent
		return
	line.append(p)
	acc.append(acc[last] + line[last].distance_to(p))
	tangents.append(tangent)


## Кут вузла для напрямку в площині XZ (x, z): ніс — це -Z, північ — кут 0.
static func _yaw_of(d: Vector2) -> float:
	return rad_to_deg(atan2(-d.x, -d.y))


## Точка кривої на відстані s від старту: XZ — з кривої, висота й нахил — з рельєфу під
## юнітом (а не пряма між центрами клітинок, що протикала б горб).
func _follow(s: float, line: PackedVector2Array, acc: PackedFloat32Array, tangents: PackedVector2Array) -> void:
	var last: int = line.size() - 1
	var i: int = clampi(acc.bsearch(s), 1, last)
	var t: float = clampf((s - acc[i - 1]) / (acc[i] - acc[i - 1]), 0.0, 1.0)
	var p: Vector2 = line[last] if s >= acc[last] else line[i - 1].lerp(line[i], t)
	var d: Vector2 = tangents[i - 1].lerp(tangents[i], t)
	rotation_degrees.y += wrapf(_yaw_of(d) - rotation_degrees.y, -180.0, 180.0)
	if _has_model:
		# Лише в плані: висота рельєфу під юнітом не є шляхом коліс.
		_travel += Vector2(p.x - position.x, p.y - position.z).length()
		_travel_by_unit[_unit_id] = _travel
		(_silhouette.get_node("Hull") as GeometryInstance3D).set_instance_shader_parameter("travel", _travel)
	_pose(Vector3(p.x, 0.0, p.y))


## Твін повороту крутить лише кут вузла; нахил залежить від нього, тож іде слідом. Кадр
## вмикають face() і move_along() і вимикає перший кадр після кінця твіна.
func _process(_delta: float) -> void:
	if rotation.y != _posed_yaw:
		_pose(position)
	if _face_tween == null or not _face_tween.is_running():
		set_process(false)


## Ставить юніт у точці `at` на рельєф усією основою. Нахил — лише в силуеті, тангаж і
## крен у його власних осях: кут вузла навколо Y лишається напрямом (§3.4), а ніс у плані
## дивиться туди ж, куди й без нахилу. Висота — найменша, за якої жоден кут основи і
## центр не входять у ґрунт; на схилі, крутішому за MAX_TILT_DEG, нижній край висить.
## Відділення не нахиляється: фігури на одній основі завалювались би разом із нею.
func _pose(at: Vector3) -> void:
	_posed_yaw = rotation.y
	var th: TerrainHeight = TerrainHeight.active
	if th == null:
		position = Vector3(at.x, 0.0, at.z)
		_silhouette.rotation = Vector3.ZERO
		return
	var cell: Vector2i = IsoCameraRig.world_to_cell(at)
	var deck: float = th.deck_y(cell)
	if deck > th.at(float(cell.x), float(cell.y)) + 0.001:
		# Міст: настил рівний, а рельєф під ним — русло.
		position = Vector3(at.x, deck, at.z)
		_silhouette.rotation = Vector3.ZERO
		return
	if not _tilts:
		position = Vector3(at.x, th.at(at.x, at.z) - SQUAD_SINK, at.z)
		_silhouette.rotation = Vector3.ZERO
		return
	var yaw := Basis(Vector3.UP, rotation.y)
	var corners: Array[Vector3] = []
	var h: Array[float] = []
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var c := Vector3(_half_base.x * sx, 0.0, _half_base.y * sz)
			var w: Vector3 = at + yaw * c
			corners.append(c)
			h.append(th.at(w.x, w.z))
	# Порядок кутів: (-x,-z), (-x,+z), (+x,-z), (+x,+z); ніс — це -Z.
	var limit: float = deg_to_rad(MAX_TILT_DEG)
	var pitch: float = 0.0
	var roll: float = 0.0
	if _half_base.y > 0.0:
		pitch = atan(((h[0] + h[2]) - (h[1] + h[3])) / (4.0 * _half_base.y))
	if _half_base.x > 0.0:
		roll = atan(((h[2] + h[3]) - (h[0] + h[1])) / (4.0 * _half_base.x))
	_silhouette.rotation = Vector3(clampf(pitch, -limit, limit), 0.0, clampf(roll, -limit, limit))
	var tilt: Basis = _silhouette.basis
	var y: float = th.at(at.x, at.z)
	for c: Vector3 in corners:
		# Нахилений кут зсувається в плані (cos < 1), тож ґрунт беремо під ним, а не під
		# рівним: на крутому березі різниця — кілька сантиметрів, і кут інакше тоне.
		var tc: Vector3 = tilt * c
		var w: Vector3 = at + yaw * tc
		y = maxf(y, th.at(w.x, w.z) - tc.y)
	position = Vector3(at.x, y, at.z)


## R14: поворот твінується, а не клацає миттєво — «Твіни руху й повороту»
## (Task 2.4, Step 2) називає поворот окремо від руху, і атмосфера (§1.4) не
## терпить дерев'яного корпусу. Гравець на це не чекає (сигнатура лишається
## void, виклик fire-and-forget), тож твін лишається коротким.
func face(direction: int) -> void:
	assert(direction >= 0 and direction < 8, "напрямок поза межами 8 фейсингів: %d" % direction)
	facing = direction
	var current: float = rotation_degrees.y
	var target: float = _degrees_for_facing(direction)
	# Найкоротший шлях, не абсолютний кут: з 350° у 10° крутимось на +20°,
	# а не в обхід на -340°. Стандартна формула найкоротшої дельти кута.
	var delta: float = fposmod(target - current + 180.0, 360.0) - 180.0

	# Другий face() під час першого — це заміна, а не перегони: попередній
	# твін вбиваємо, інакше обидва тягнутимуть той самий rotation_degrees.y.
	if _face_tween != null and _face_tween.is_valid():
		_face_tween.kill()
	_face_tween = create_tween()
	_face_tween.tween_property(self, "rotation_degrees:y", current + delta, FACE_TURN_DURATION)
	set_process(true)


## Виправлення 1: bind() кличе це замість face() — щойно створений (чи
## перебудований) вузол не має орієнтації, з якої мало б сенс довертатись, і
## гасить будь-який живий _face_tween, щоб не лишити два джерела правди для
## rotation_degrees.y.
func _set_facing_instant(direction: int) -> void:
	assert(direction >= 0 and direction < 8, "напрямок поза межами 8 фейсингів: %d" % direction)
	if _face_tween != null and _face_tween.is_valid():
		_face_tween.kill()
	facing = direction
	rotation_degrees.y = _degrees_for_facing(direction)


## Миттєво, без твінів: сцена перебудовує ВСІ вузли юнітів після кожної дії
## (див. коментар у bind()), тож анімована смуга щоразу починала б з нуля.
func set_hp(hp: int, max_hp: int) -> void:
	var ratio: float = 0.0
	if max_hp > 0:
		ratio = clampf(float(hp) / float(max_hp), 0.0, 1.0)
	_hp_ratio = ratio
	# Текстура кешована за співвідношенням (скінченна множина hp/max_hp).
	_hp_bar.texture = _hp_bar_texture(ratio, _owner)
	# Білий: колір тепер живе всередині текстури (рамка, тло й заливка мають
	# кожен свій), і modulate поверх нього перефарбував би й рамку теж.
	_hp_bar.modulate = Color.WHITE
	_hp_label.text = "%d/%d" % [hp, max_hp]
	_set_standing(_figures_for(hp, max_hp))


## Єдине джерело правди про показане HP — для UI й тестів. Колишнє
## _hp_bar.scale.x більше нічого не означає (§бриф, скарга власника).
func hp_ratio() -> float:
	return _hp_ratio


## Рамка (1 px по периметру), темне тло всередині й заливка від ЛІВОГО краю
## завширшки ratio — одна текстура, один спрайт. Заливка росте зліва
## направо, як у референсі; старий scale.x стискав смугу до центру.
static func _hp_bar_texture(ratio: float, owner: int = 0) -> ImageTexture:
	var fill_width: int = _hp_fill(ratio)
	# Ключ — ширина заливки й власник: колір заливки — його, тож без власника в ключі
	# юніти двох гравців ділили б одну текстуру.
	var key: Array = ["hp", fill_width, owner % PLAYER_COLORS.size()]
	if not _texture_cache.has(key):
		_texture_cache[key] = ImageTexture.create_from_image(hp_bar_image(fill_width, owner))
	return _texture_cache[key]


## Ширина заливки в пікселях для співвідношення HP.
static func _hp_fill(ratio: float) -> int:
	return roundi(float(_HP_BAR_SIZE.x - 2) * ratio)


## Колір заливки смуги власника. Світліший за колір гравця: на темному тлі смуги синій і
## червоний давали контраст ~2:1 і тонули на мокрій землі та асфальті.
static func hp_fill_color(owner: int) -> Color:
	return PLAYER_COLORS[owner % PLAYER_COLORS.size()].lerp(Color.WHITE, _HP_FILL_LIFT)


## Малюнок смуги з заливкою завширшки `fill_width` пікселів: рамка, тло й заливка кольору власника.
static func hp_bar_image(fill_width: int, owner: int = 0) -> Image:
	var inner := Rect2i(Vector2i.ONE, _HP_BAR_SIZE - Vector2i(2, 2))
	var image := Image.create(_HP_BAR_SIZE.x, _HP_BAR_SIZE.y, false, Image.FORMAT_RGBA8)
	image.fill(_HP_BAR_FRAME_COLOR)
	image.fill_rect(inner, _HP_BAR_BACK_COLOR)
	if fill_width > 0:
		image.fill_rect(Rect2i(inner.position, Vector2i(fill_width, inner.size.y)), hp_fill_color(owner))
	return image


## §3.9: залишок дронів публічний — показується на будь-якому видимому
## загоні для будь-якого гравця, тож метод свідомо не питає й не знає, чий
## це юніт.
func set_drones(count: int) -> void:
	_drones_left = clampi(count, 0, _MAX_DRONES)
	_drone_icon.visible = _drones_left > 0
	_drone_icon.scale = Vector3.ONE * (0.5 + 0.25 * float(_drones_left))


## Ціль прев'ю пострілу, яке гравець ще не підтвердив (§3.13): вузол лише
## вмикає позначку, ніколи не вирішує, чи він ціль. Рішення приходить готовим
## із InputController.action_preview крізь контейнер (battle_screen) — вигляд
## не питає ні дальності, ні видимості, ні шкоди (§6 CLAUDE.md).
func set_targeted(targeted: bool) -> void:
	_crosshair.visible = targeted


## Ціль, яку озброєний дрон бити не може (піхота, §3.9). Рішення — з
## Targeting.drone_marks() крізь battle_screen; вузол лише показує.
func set_forbidden(on: bool) -> void:
	_forbidden.visible = on


## Позначений оглядом юніта (§3.13): рішення — з Targeting крізь
## InputController.inspected і battle_screen; вузол лише показує.
func set_threatened(on: bool) -> void:
	_threatened.visible = on


func is_threatened() -> bool:
	return _threatened.visible


## Позначка дрона — окрема від гарматної (§3.13): юніт в обох списках несе обидві.
func set_drone_threatened(on: bool) -> void:
	_drone_threatened.visible = on


func is_drone_threatened() -> bool:
	return _drone_threatened.visible


func standing_figures() -> int:
	return _standing


## `ceil(SQUAD_FIGURES · hp / max_hp)` цілими: фігура падає, щойно втрачено її чверть.
static func _figures_for(hp: int, max_hp: int) -> int:
	if max_hp <= 0 or hp <= 0:
		return 0
	return mini(SQUAD_FIGURES, (SQUAD_FIGURES * hp + max_hp - 1) / max_hp)


func _set_standing(count: int) -> void:
	if not (UnitSilhouettes.spec(_type_id).extras as Array).has(&"figures"):
		_standing = 0
		return
	_standing = count
	(_silhouette.get_node("Hull") as MeshInstance3D).mesh = UnitSilhouettes.merged_mesh(_type_id, count)


## Твінує _silhouette, а не self: self.scale належить play_destroyed() відділення, і два
## твіни на одну властивість змагались би на пострілі, який убиває.
func play_shot() -> Signal:
	var tween: Tween = create_tween()
	tween.tween_property(_silhouette, "scale", Vector3.ONE * _SHOT_PUNCH_SCALE, _SHOT_PUNCH_UP)
	tween.tween_property(_silhouette, "scale", Vector3.ONE, _SHOT_PUNCH_DOWN)
	return tween.finished


func play_destroyed() -> Signal:
	destroyed = true
	var tween: Tween = create_tween()
	var cls: int = UnitTypes.get_type(_type_id)["unit_class"]
	if not UnitTypes.is_vehicle(cls):
		# Відділення падає, а не стискається: лежачі фігури далі малює шар загиблих зі стану.
		for n: Node3D in [_hp_bar, _hp_label, _drone_icon]:
			n.visible = false
		_set_standing(0)
		_contact_on = false
		tween.tween_interval(_FALL_SEC)
		return tween.finished
	# Куля — у контейнері, не в цьому вузлі: вузол юніта звільнить перебудова дошки,
	# а куля мусить догоріти над уламками.
	BattleFx.spawn_explosion(get_parent(), position, BattleFx.fireball_size(cls))
	for n: Node3D in [_hp_bar, _hp_label, _drone_icon]:
		n.visible = false
	tween.tween_interval(KILL_HIDE_DELAY)
	tween.tween_callback(func() -> void: _silhouette.visible = false)
	return tween.finished


func _build_silhouette(type_id: int, owner: int) -> void:
	# free(), не queue_free(): відкладене звільнення лишає щойно відкріплений
	# вузол «сиротою» до наступного кадру, і headless-тести це фіксують.
	for child in _silhouette.get_children():
		child.free()

	_owner = owner
	var built := UnitSilhouettes.build_merged(type_id)
	for part in built.get_children():
		built.remove_child(part)
		_silhouette.add_child(part)
	built.free()
	var hull := _silhouette.get_node("Hull") as MeshInstance3D
	var hull_size: Vector3 = UnitSilhouettes.spec(type_id).hull
	_half_base = Vector2(hull_size.x, hull_size.z) * 0.5
	_hull_material = hull.material_override
	_has_model = UnitSilhouettes.has_model(type_id)
	if _has_model:
		hull.set_instance_shader_parameter("travel", _travel)
	_hull_size = hull_size
	_contact_on = contacts != null and WeatherRig.unit_contact > 0.0

	# ЧАСОВИЙ ІНСТРУМЕНТ РОЗРОБНИКА (Task 2) — єдиний виклик, єдине місце, де стрілку
	# додають на дошку. Прибрати стрілку — це прибрати рівно ці два рядки
	# (або поставити _DEBUG_SHOW_FACING_ARROW у false), а не шукати по файлу.
	if _DEBUG_SHOW_FACING_ARROW:
		_silhouette.add_child(_build_facing_arrow(hull_size))


## Пляма тіні-контакту ширша за слід корпусу: край гасне вже за корпусом.
const CONTACT_SPREAD: float = 2.0
## Спільний MultiMesh плям екрана (`UnitContacts`); без нього — без плям. Ставить власник
## вигляду до bind().
var contacts: UnitContacts = null
## Спільний MultiMesh смуг HP екрана (`UnitHpBars`); без нього смугу малює сам спрайт HpBar.
var hp_bars: UnitHpBars = null
## Нема, коли вигляд карти тіні-контакту не має: інакше кожен юніт платить прозорий виклик малювання.
var _contact_on: bool = false
var _hull_size: Vector3 = Vector3.ZERO


## Тінь-контакт: квад під корпусом у системі силуету, тож нахиляється разом із ним на схилі й
## ховається разом із юнітом; де ґрунт вищий за квад, шейдер кладе вершини на рельєф. Сонця не
## чекає — силу ставить вигляд карти глобальним uniform. Світове перетворення для `UnitContacts`.
func contact_transform() -> Transform3D:
	if not _contact_on or not is_visible_in_tree() or not _silhouette.visible:
		return UnitContacts.HIDDEN
	var size := Basis.from_scale(Vector3(_hull_size.x * CONTACT_SPREAD, 1.0, _hull_size.z * CONTACT_SPREAD))
	return _silhouette.global_transform * Transform3D(size, Vector3(0.0, 0.01, 0.0))


func _exit_tree() -> void:
	if contacts != null and is_instance_valid(contacts):
		contacts.untrack(self)
	if hp_bars != null and is_instance_valid(hp_bars):
		hp_bars.untrack(self)


## Стан смуги HP для `UnitHpBars`: шар — власник і ширина заливки (текстура спрайта — той самий малюнок),
## точка — там, де стоїть спрайт, показ — як у спрайта.
func hp_bar_layer() -> int:
	return (_owner % PLAYER_COLORS.size()) * UnitHpBars.fills_per_owner() + _hp_fill(_hp_ratio)


func hp_bar_world() -> Vector3:
	return global_position + Vector3(0.0, _hp_bar.position.y, 0.0)


func hp_bar_shown() -> bool:
	return _hp_bar.visible and is_visible_in_tree()


## Перебудова юнітів після кожної дії створює десяток вузлів: матеріал і
## текстури спільні між ними (один колір — один екземпляр), інакше кожен вигляд
## платить за власний ресурс і не батчиться. Ніхто не змінює їх після створення.
static var _texture_cache: Dictionary = {}


## ЧАСОВИЙ ІНСТРУМЕНТ РОЗРОБНИКА (Task 2): плаский трикутник на даху корпусу, носиком у
## локальний -Z — той самий «перед», що й у _build_barrel вище, тож стрілка
## завжди узгоджена з рештою силуету й із самим rotation_degrees.y (жодної
## окремої логіки повороту тут нема — вузол крутить її разом з усім
## Silhouette). SurfaceTool, не BoxMesh: стрілоподібний контур (а не
## прямокутник) — щоб форма сама, без кольору чи підпису, читалась як «перед»
## з фіксованого ізо-ракурсу зверху.
func _build_facing_arrow(hull_size: Vector3) -> MeshInstance3D:
	var arrow := MeshInstance3D.new()
	arrow.name = "DebugFacingArrow"

	var length: float = hull_size.z * 0.45
	var half_width: float = hull_size.x * 0.28
	var tip := Vector3(0.0, 0.0, -length)
	var left := Vector3(-half_width, 0.0, length * 0.35)
	var right := Vector3(half_width, 0.0, length * 0.35)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)  # площина лежить в XZ — нормаль дивиться туди, звідки й камера
	# Порядок вершин (носик, ліва, права) — лише для читабельності коду, не
	# для контролю лицьової грані: яка сторона в Godot вважається «лицьовою»
	# — не той бій, який варто вести заради тимчасового маркера (нижче
	# CULL_DISABLED прибирає це питання геть).
	st.add_vertex(tip)
	st.add_vertex(left)
	st.add_vertex(right)
	arrow.mesh = st.commit()
	arrow.position = Vector3(0.0, hull_size.y + _DEBUG_ARROW_Y_OFFSET, 0.0)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = _DEBUG_ARROW_COLOR
	# Без освітлення: інструмент розробника мусить читатись однаково чітко в тіні й на сонці,
	# а не губитись під directional-light рушія (§8 CLAUDE.md).
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Без відсікання граней: єдина трикутна площина лежить строго в XZ, і
	# фіксована камера завжди дивиться на неї трохи збоку (§8 CLAUDE.md, кут
	# рига не змінюється) — покладатись на те, який бік трикутника Godot
	# вважає «лицьовим», зайвий ризик для тимчасового маркера, де це геть не
	# важливо.
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	arrow.material_override = mat
	return arrow


## Кільце з чотирма рисками, що дивляться до центру — форма, а не пляма:
## на ~100 px силуету (§1.5) суцільна крапка читалась би як маркер юніта, а
## приціл мусить читатись як приціл із одного погляду. Мальовано в код, як і
## решта заступників тут (_flat_texture нижче), поки нема справжнього арту.
static func _crosshair_texture(size: int = 32) -> ImageTexture:
	var key: Array = ["cross", size]
	if _texture_cache.has(key):
		return _texture_cache[key]
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 1.0, 1.0, 0.0))
	var center: float = float(size - 1) * 0.5
	var radius: float = float(size) * 0.42
	var thickness: float = float(size) * 0.045
	for y in size:
		for x in size:
			var dx: float = float(x) - center
			var dy: float = float(y) - center
			var distance: float = sqrt(dx * dx + dy * dy)
			var on_ring: bool = absf(distance - radius) <= thickness
			# Риски йдуть по осях від кільця всередину і НЕ доходять до центру
			# (distance > radius * 0.4) — перехрестя посеред корпусу ховало б
			# сам силует, який гравець і намагається впізнати.
			var on_tick: bool = (
				distance < radius
				and distance > radius * 0.4
				and (absf(dx) <= thickness or absf(dy) <= thickness)
			)
			if on_ring or on_tick:
				image.set_pixel(x, y, Color.WHITE)
	_texture_cache[key] = ImageTexture.create_from_image(image)
	return _texture_cache[key]


## Діагональний хрест — той самий біло-прозорий прийом, що й приціл.
static func _cross_texture(size: int = 32) -> ImageTexture:
	var key: Array = ["forbid", size]
	if _texture_cache.has(key):
		return _texture_cache[key]
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 1.0, 1.0, 0.0))
	var thickness: int = maxi(1, size / 10)
	for i in range(thickness, size - thickness):
		for t in range(-thickness, thickness + 1):
			image.set_pixel(clampi(i + t, 0, size - 1), i, Color.WHITE)
			image.set_pixel(clampi(size - 1 - i + t, 0, size - 1), i, Color.WHITE)
	_texture_cache[key] = ImageTexture.create_from_image(image)
	return _texture_cache[key]


## Контур ромба — дронова позначка: форма, якої немає ні в прицілу, ні в хреста.
static func _diamond_texture(size: int = 32) -> ImageTexture:
	var key: Array = ["diamond", size]
	if _texture_cache.has(key):
		return _texture_cache[key]
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 1.0, 1.0, 0.0))
	var center: float = float(size - 1) * 0.5
	var radius: float = float(size) * 0.42
	var thickness: float = float(size) * 0.06
	for y in size:
		for x in size:
			var d: float = absf(float(x) - center) + absf(float(y) - center)
			if absf(d - radius) <= thickness:
				image.set_pixel(x, y, Color.WHITE)
	_texture_cache[key] = ImageTexture.create_from_image(image)
	return _texture_cache[key]


static func _flat_texture(color: Color, size: int = 8) -> ImageTexture:
	var key: Array = ["flat", color, size]
	if _texture_cache.has(key):
		return _texture_cache[key]
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(color)
	_texture_cache[key] = ImageTexture.create_from_image(image)
	return _texture_cache[key]
