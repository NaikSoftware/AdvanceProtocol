class_name IsoCameraRig
extends Node3D
## Фіксований ізометричний ріг: панорама і зум по площині дошки, кут камери
## не змінюється (§1 non-goals — вільної камери нема). Ноду-власника фокусу —
## сам корінь рига, дочірній Yaw несе поворот на 45°, лише щоб дати камері
## погляд; жодна з цих обертань не потрапляє у клітинкові координати.

const MIN_ZOOM: float = 6.0
const MAX_ZOOM: float = 20.0
## §3.13/§1: панорама обмежена межами дошки з полем в 2 тайли — гравець не
## може завести камеру за край карти навіть на максимальному зумі.
const BOARD_MARGIN: float = 2.0
## R13: єдине джерело правди для 45° — сцена бере його звідси в _ready(),
## а pan() (через проекцію променя, нижче) відображає той самий кут, не
## повторюючи його вдруге власною формулою.
const YAW_DEGREES: float = 45.0

## Зум наздоганяє ціль експоненційно (1 - e^-rate*dt) — свідомо не лінійно:
## лінійне наближення дає помітний «зрив» швидкості в момент, коли ціль
## досягнута, експоненційне сповільнюється саме собою. Підібрано оком у
## реальному вікні (run/live), не з формули.
const ZOOM_SMOOTH_RATE: float = 10.0
const ZOOM_SNAP_EPSILON: float = 0.005

## Кидок пальцем: швидкість згасає експоненційно (тертя), а не лінійно, тим
## самим PAN_FRICTION, що й зум вище — та сама логіка «гальмує, а не
## спиняється». MIN_FLING_SPEED — поріг, нижче якого рух непомітний і
## анімацію чесніше зупинити, ніж повзти нескінченно малими кроками.
const PAN_FRICTION: float = 3.5
const MIN_FLING_SPEED: float = 0.05

## Програмне рецентрування (не гейтове — те лишається миттєвим, див.
## fly_to() нижче) із easing, а не телепортом.
const RECENTER_DURATION: float = 0.45

@onready var _yaw: Node3D = $Yaw
@onready var _camera: Camera3D = $Yaw/Camera3D

var zoom_level: float = 12.0
## Остання дійсна клітинка дошки (board_size - 1), не її розмір: cell_to_world
## кладе клітинку (19, 19) двадцятитайлової дошки у світові 19, а не 20 —
## межа панорами міряється від фактичного краю геометрії (R12), а не від
## кількості клітинок.
var _max_cell: Vector2i = Vector2i.ZERO

var _zoom_target: float = 12.0
var _zoom_anchor_screen: Vector2 = Vector2.ZERO

## Швидкість кидка міряється по кадрах (діагональ global_position між двома
## _process()-викликами), НЕ по годиннику між pan()-подіями: кілька
## motion-подій легко лягають в один кадр (accumulated input) чи, навпаки, в
## тісному синтетичному циклі (тест) майже без реального часу між ними —
## обидва випадки ламають годинникову оцінку. simulate() у тестах керує
## САМЕ кадровим delta, тож ця точка вимірювання детермінована й там, і в
## живому вікні.
var _prev_frame_position: Vector3 = Vector3.ZERO
var _pan_velocity: Vector3 = Vector3.ZERO

var _inertia_active: bool = false
var _inertia_velocity: Vector3 = Vector3.ZERO

## true, поки палець/ЛКМ притиснутий (begin_hold()..end_hold(), керує вхід).
## Без цього прапорця _process() вимикав себе в першому ж кадрі БЕЗ руху —
## палець, що зупинився й полежав перед відпусканням, лишав _pan_velocity
## замороженою на останньому вимірі замість згасання до нуля (ревʼю: замір
## 55.71 одразу після драга і 55.71 ще через 30 кадрів простою). Поки
## _held == true, _process() працює щокадру НАВІТЬ без жодного pan() —
## diff позиції тоді 0, і _pan_velocity згасає сама через ту саму
## експоненційну домішку, що й міряє рух.
var _held: bool = false

var _recenter_tween: Tween = null

func _ready() -> void:
	_yaw.rotation_degrees.y = YAW_DEGREES
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = zoom_level
	_zoom_target = zoom_level
	_prev_frame_position = global_position
	# Немає що доганяти й нема інерції в спокої — _process() вмикається
	# лише на час активної анімації (zoom_by/pan/end_pan/fly_to нижче), не
	# висить постійно.
	set_process(false)

## §3.1: логічні координати цілі, світові — (x, 0, y). 45° дає камера, а не
## ці дані, тому функція лишається чистим переносом без жодного повороту.
static func cell_to_world(cell: Vector2i) -> Vector3:
	return Vector3(cell.x, 0.0, cell.y)

static func world_to_cell(point: Vector3) -> Vector2i:
	return Vector2i(roundi(point.x), roundi(point.z))

func set_bounds(board_size: Vector2i) -> void:
	_max_cell = board_size - Vector2i.ONE

## R13/пан-масштаб: делegований проекції самої камери, а не ручному
## коефіцієнту. Раніше pan() додавав екранні ПІКСЕЛІ до світових одиниць
## напряму (1px == 1 world unit) — при ортопроекції розміром (zoom_level) на
## вьюпорт 720px це ~60x зайвої чутливості: драг у 50px миттєво впирав
## камеру в клемп дошки і застрягав там до кінця жесту (відтворено і
## заміряно в реальному вікні, не здогад). Перетин променя з площиною y=0 —
## та сама геометрія, що вже давно й перевірено використовує
## screen_point_to_cell() нижче — автоматично враховує і zoom_level (розмір
## ортофрустума), і нахил камери (52°, чого груба формула теж не рахувала:
## вертикальний рух пальця «стискається» перспективою площини сильніше за
## горизонтальний), і будь-яку майбутню зміну проекції. Повертає null, якщо
## промінь не перетинає площину дошки (камера дивиться паралельно чи вгору)
## — виклик тоді просто нічого не робить цього кадру, безпечніше за ділення
## на нуль.
func _ray_ground_point(screen_pos: Vector2) -> Variant:
	var dir: Vector3 = _camera.project_ray_normal(screen_pos)
	if is_zero_approx(dir.y):
		return null
	var origin: Vector3 = _camera.project_ray_origin(screen_pos)
	var t: float = -origin.y / dir.y
	if t < 0.0:
		return null
	return origin + dir * t

## delta — палець гравця на екрані (raw screen relative), не світові осі.
## Контракт САМ pan() — «пряме маніпулювання»: світова точка, що щойно була
## під поточним екранним якорем (центр вьюпорта), опиняється під
## anchor+delta ПІСЛЯ виклику. Це не довільний стиль — при ортопроекції з
## реальною геометрією (проекція променя на площину дошки, як і в
## screen_point_to_cell()) є рівно один знак, що дає «дошка йде за пальцем»;
## інверсія рахується виведенням нижче (from - to), не обирається на смак.
## Раніше тут стояла проста формула Vector3(delta.x,0,delta.y).rotated(45°)
## — вона і плутала напрям (камера йшла за пальцем, а не дошка — власник
## назвав це «інвертовано»), і масштаб (екранний піксель важив рівно 1 world
## unit незалежно від zoom_level — 50px миттєво впирали камеру в клемп
## дошки). Обидва зникають разом, бо обидва були симптомами однієї грубої
## формули замість реальної проекції; battle_screen.gd передає delta
## СИРИМ — жодної інверсії чи повороту на своєму боці (R13, подвійний
## поворот заборонений).
func pan(delta: Vector2) -> void:
	if not is_processing():
		# Щойно вимкнений _process() лишив _prev_frame_position застарілою
		# (могла бути й телепортована center_on() без жодного кадру між
		# ними) — скидаємо на «зараз», інакше перший кадр цього жесту
		# виміряв би фантомну швидкість зі старої історії.
		_prev_frame_position = global_position
	var anchor: Vector2 = get_viewport().get_visible_rect().size * 0.5
	var from: Variant = _ray_ground_point(anchor)
	var to: Variant = _ray_ground_point(anchor + delta)
	if from == null or to == null:
		return
	var world_delta: Vector3 = (from as Vector3) - (to as Vector3)
	global_position = _clamp_to_bounds(global_position + world_delta)
	set_process(true)  # хоч один кадр _process() мусить пропрацювати, щоб виміряти швидкість для можливого end_pan()

## Вхід кличе begin_hold() рівно на натиск (тап чи пан — байдуже) і
## end_hold() на відпускання. Тримає _process() увімкненим НА ВЕСЬ час,
## поки палець притиснутий, незалежно від того, чи є рух цього кадру —
## саме це і згашує _pan_velocity до нуля, якщо палець зупинився й полежав
## перед відпусканням (ревʼю, головна поломка 1). Так само скидає й
## _prev_frame_position, як і pan() робить для щойно увімкненого процесу —
## одна причина, один код.
func begin_hold() -> void:
	_held = true
	if not is_processing():
		_prev_frame_position = global_position
	set_process(true)

func end_hold() -> void:
	_held = false

## Викликається входом, коли жест-пан завершується відпусканням пальця:
## накопичена (по кадрах — див. _process()) швидкість переходить у кидок.
func end_pan() -> void:
	_inertia_velocity = _pan_velocity
	_inertia_active = _inertia_velocity.length() > MIN_FLING_SPEED
	if _inertia_active:
		set_process(true)

## Новий дотик до екрана (наступний натиск чи щипок) обриває кидок одразу —
## гравець знову тримає дошку рукою, інерція більше не її господар.
##
## _prev_frame_position теж скидається тут, а не лише в pan()/begin_hold():
## поки дошка котиться, _process() лишається увімкненим (_inertia_active),
## тож is_processing() у pan() вже TRUE й свій скид не спрацьовує. Без
## цього рядка «схопити рухому дошку» (cancel_inertia() тут, потім pan()
## на 1px руху пальця) міряло б diff від СТАРОЇ позиції — тієї, де камера
## була до скасування — і зчитувало б залишковий біг інерції як швидкість
## пальця (ревʼю, головна поломка 2: pan_v=20.16 після 1px руху, дошка їде
## ще ~5 одиниць вже після відпускання).
func cancel_inertia() -> void:
	_inertia_active = false
	_inertia_velocity = Vector3.ZERO
	_pan_velocity = Vector3.ZERO
	_prev_frame_position = global_position

func _update_inertia(delta: float) -> void:
	if not _inertia_active:
		return
	var next_pos: Vector3 = global_position + _inertia_velocity * delta
	var clamped: Vector3 = _clamp_to_bounds(next_pos)
	# Жорсткий клемп (власник відмовився від пружного опору), але без ривка:
	# коли межа гасить рух по осі, гасимо й швидкість по ній — інакше кидок
	# намагався б проштовхнутись крізь межу щокадру й це читалося б як
	# дрож/поштовх, а не плавна зупинка рівно на краю.
	if not is_equal_approx(clamped.x, next_pos.x):
		_inertia_velocity.x = 0.0
	if not is_equal_approx(clamped.z, next_pos.z):
		_inertia_velocity.z = 0.0
	global_position = clamped
	_inertia_velocity *= exp(-PAN_FRICTION * delta)
	if _inertia_velocity.length() < MIN_FLING_SPEED:
		_inertia_velocity = Vector3.ZERO
		_inertia_active = false

## Task 2.10: тап по екрану -> клітинка дошки. Перетин променя камери з
## площиною y=0, де лежать центри тайлів (§3.1 — дошка сама лишається
## непорушеною площиною, 45° тут лише повертає, звідки дивиться камера).
## Лишається тут, а не в battle_screen.gd: уся екранна геометрія рига — в
## одному місці, і жоден інший файл не тримає власної копії цієї проєкції.
func screen_point_to_cell(screen_pos: Vector2) -> Vector2i:
	var origin: Vector3 = _camera.project_ray_origin(screen_pos)
	var dir: Vector3 = _camera.project_ray_normal(screen_pos)
	if is_zero_approx(dir.y):
		# Промінь паралельний площині дошки — перетину нема. Деградує на
		# свідомо позадошкову клітинку: Board.in_bounds() відкидає її самим
		# викликачем, а не діленням на нуль тут.
		return Vector2i(-1, -1)
	var t: float = -origin.y / dir.y
	if t < 0.0:
		return Vector2i(-1, -1)
	return world_to_cell(origin + dir * t)


## Миттєве рецентрування — єдиний виклик, дозволений на гейті передачі ходу
## (game/ui/handover_gate.gd, крок 2a контракту): камера мусить опинитись на
## позиції ДО того, як гейт стане invisible, синхронно, без жодного кадру
## анімації між ними, інакше перший кадр нового ходу встигає показати місце,
## де стояв попередній гравець, — витік прихованої інформації (§1.2), а не
## косметичний недолік. Плавний варіант — fly_to() нижче, і саме тому це два
## різні методи, а не один параметр animated: true/false — виклик з гейта не
## має самому вирішувати, чи він «забув» передати animated=false.
func center_on(cell: Vector2i) -> void:
	if _recenter_tween != null and _recenter_tween.is_valid():
		_recenter_tween.kill()
	global_position = _clamp_to_bounds(cell_to_world(cell))

## Плавне рецентрування (розгін-гальмування) для всього, що НЕ гейт —
## початковий показ дошки, наведення на вибраний юніт у межах ходу.
## Повертає сам Tween: керуючий код може await tween.finished у реальному
## житті, а тест — крокнути tween.custom_step(dt) детерміновано, без
## реального очікування (той самий прийом, що й для інерції/зуму: керована
## анімація, а не сигнал у реальному часі).
func fly_to(cell: Vector2i) -> Tween:
	if _recenter_tween != null and _recenter_tween.is_valid():
		_recenter_tween.kill()
	var target: Vector3 = _clamp_to_bounds(cell_to_world(cell))
	_recenter_tween = create_tween()
	_recenter_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_recenter_tween.tween_property(self, "global_position", target, RECENTER_DURATION)
	return _recenter_tween

## factor > 1 — звужуємось (зум ін), factor < 1 — розширюємось (зум аут);
## те саме позначення, що вже було в zoom_by(), лишене без змін, аби не
## перевертати сенс на боці кожного викликача. anchor_screen — точка, що
## мусить лишитись під пальцем/курсором (рішення власника: зум у точку під
## пальцем, не в центр екрана); Vector2.INF — сентинел «немає природної
## точки» (наразі жоден викликач цим не користується, лишено для безпечного
## дефолту).
func zoom_by(factor: float, anchor_screen: Vector2 = Vector2.INF) -> void:
	_zoom_target = clampf(_zoom_target * factor, MIN_ZOOM, MAX_ZOOM)
	_zoom_anchor_screen = anchor_screen if anchor_screen != Vector2.INF \
		else get_viewport().get_visible_rect().size * 0.5
	set_process(true)

func _update_zoom(delta: float) -> void:
	if is_equal_approx(zoom_level, _zoom_target):
		return
	var t: float = 1.0 - exp(-ZOOM_SMOOTH_RATE * delta)
	var next_zoom: float = lerp(zoom_level, _zoom_target, t)
	if absf(next_zoom - _zoom_target) < ZOOM_SNAP_EPSILON:
		next_zoom = _zoom_target
	_apply_zoom_keep_anchor(next_zoom)

## Зум «у точку під пальцем»: беремо світову точку під якорем ДО зміни
## розміру фрустума, міняємо розмір, дивимось, куди той самий екранний якір
## тепер указує, і зсуваємо камеру рівно на різницю. Той самий трюк, яким
## screen_point_to_cell()/pan() проектують промінь на площину дошки — тут
## застосований двічі навколо зміни zoom_level.
func _apply_zoom_keep_anchor(next_zoom: float) -> void:
	var before: Variant = _ray_ground_point(_zoom_anchor_screen)
	zoom_level = next_zoom
	_camera.size = zoom_level
	var after: Variant = _ray_ground_point(_zoom_anchor_screen)
	if before != null and after != null:
		global_position = _clamp_to_bounds(global_position + ((before as Vector3) - (after as Vector3)))

func _process(delta: float) -> void:
	# Швидкість «останніх кадрів перед відривом» (рішення власника, не повна
	# дельта жесту): експоненційно згладжений diff позиції по кадрах.
	# Вимірюється тут, а не в pan(), саме тому, що кадр — стабільна одиниця
	# і в реальному вікні, і в тесті (simulate() керує тим самим delta), а
	# годинник між подіями — ні (кілька подій легко лягають в один кадр).
	if delta > 0.0:
		var instant_v: Vector3 = (global_position - _prev_frame_position) / delta
		_pan_velocity = _pan_velocity.lerp(instant_v, 0.35)
	_prev_frame_position = global_position

	_update_zoom(delta)
	_update_inertia(delta)
	# _held утримує процес живим, навіть коли нічого не анімується — рівно
	# для того, щоб нерухомий, але притиснутий палець продовжував гасити
	# _pan_velocity до нуля щокадру (замір швидкості вище), а не заморожував
	# її на останньому значенні, отриманому з живого руху.
	if is_equal_approx(zoom_level, _zoom_target) and not _inertia_active and not _held:
		set_process(false)

func _clamp_to_bounds(pos: Vector3) -> Vector3:
	var min_edge: float = -BOARD_MARGIN
	var max_x: float = float(_max_cell.x) + BOARD_MARGIN
	var max_z: float = float(_max_cell.y) + BOARD_MARGIN
	return Vector3(
		clampf(pos.x, min_edge, max_x),
		pos.y,
		clampf(pos.z, min_edge, max_z)
	)
