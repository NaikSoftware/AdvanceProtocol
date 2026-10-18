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

## Рамка й порожнє тло — всередині ТІЄЇ САМОЇ текстури, що й заливка.
## Три накладені білборд-спрайти на одній висоті дали б z-fighting і три
## різні центри обертання, а §8 тримає бюджет ~100 draw call'ів на екран.
const _HP_BAR_FRAME_COLOR: Color = Color("14120f")
const _HP_BAR_BACK_COLOR: Color = Color("3b3833")

const _DESTROY_DURATION: float = 0.6

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
const _FACE_TURN_DURATION: float = 0.15

## Абстрактні кольори гравців-плейсхолдерів (§2 — жодного реального прапора
## чи армії). Індекс — Unit.owner. Колір іде лише на корпус (Hull), не на
## ствол чи смугу — вони нейтральні для будь-якого власника.
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
## HpBar (y=1.1) / HpLabel (y=1.3) / DroneIcon (y=1.6) з unit_view.tscn —
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

@onready var _silhouette: Node3D = $Silhouette
@onready var _crosshair: Sprite3D = $Crosshair
@onready var _forbidden: Sprite3D = $Forbidden
@onready var _threatened: Sprite3D = $Threatened
@onready var _drone_threatened: Sprite3D = $DroneThreatened
@onready var _hp_bar: Sprite3D = $HpBar
@onready var _hp_label: Label3D = $HpLabel
@onready var _drone_icon: Sprite3D = $DroneIcon

var _hull_material: StandardMaterial3D
var _drones_left: int = 0
## Останнє показане співвідношення HP. Джерело правди замість колишнього
## _hp_bar.scale.x — заливка тепер намальована ВСЕРЕДИНІ текстури, тож
## масштаб вузла більше нічого про HP не каже.
var _hp_ratio: float = 1.0
## Живий твін останнього face(); тримаємо посилання, щоб наступний виклик
## міг убити цей замість того, щоб два твіни змагались за rotation_degrees.y.
var _face_tween: Tween


func _ready() -> void:
	# Заступники текстур: суцільний колір замість реального арту, той самий
	# підхід, що й нейтральні кольори тайлів у BoardView. HP-смуга сюди не
	# входить — її текстуру повністю володіє set_hp(), який і так кличеться
	# з кожного bind().
	_drone_icon.texture = _flat_texture(Color("d9b23a"))
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
	_build_silhouette(unit.type_id, unit.owner)
	# Свіжий вузол (чи перебудований battle_screen._rebuild_units_for_active_player)
	# не має попередньої орієнтації, з якої мало б сенс анімувати «доведення» —
	# твінований face() тут дав би видиме crank-довертання щоразу, коли дошка
	# перебудовується. Миттєве виставлення, не face().
	_set_facing_instant(unit.facing)
	set_hp(unit.hp, unit.max_hp())
	set_drones(unit.drones_left)
	# Свіжий (чи перебудований) вузол не є ціллю жодного прев'ю: прев'ю живе в
	# InputController і перебудову не переживає — лишити приціл увімкненим
	# означало б показувати намір, якого вже немає.
	set_targeted(false)
	set_forbidden(false)
	_put_on_unit_layer(self)


## Силует перебудовується на кожен bind(), тож шар ставиться після нього.
static func _put_on_unit_layer(node: Node) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = 1 << (UNIT_LAYER - 1)
	for child: Node in node.get_children():
		_put_on_unit_layer(child)


## Баг-звіт (виправлення 3): «вибираю танк, вказую їхати вперед — він їде
## спиною». Причина була саме тут — попередня версія тягнула поворот і рух
## ПАРАЛЕЛЬНО в тому самому кроці tween'а: юніт в'їжджав носом у СТАРУ
## сторону в новий тайл і лише дорогою довертався в потрібну. На 90° це
## майже непомітно, на 180° виглядає рівно як задній хід — звідси й «іноді
## розвертається, іноді ні» в скарзі. Реальна машина так не їздить: вона
## довертається НА МІСЦІ, і лише тоді рушає. Тому нижче поворот і рух —
## окремі, ПОСЛІДОВНІ сходинки tween'а (set_parallel(false) між ними), а не
## паралельна група.
##
## Твін по шляху, повертає tween.finished. AP і туман сюди не заглядають —
## контролер вирішує, коли рухати, view лише показує вже прийняте рішення.
##
## Юніт довертається на кожному кроці, де кут справді змінюється (рішення
## продукту, §бриф): напрямок кроку йде з Board.facing_towards (чиста
## функція core/) від тайла, з якого юніт справді стартує цей крок, а не з
## event.path[0] — walked у події не несе стартовий тайл (лише пройдені),
## тож єдине надійне джерело — власна поточна position вузла. Коли delta
## кута точно нульова (пряма ділянка маршруту — попередній крок уже дивився
## туди ж), сходинка повороту взагалі не додається: жодної паузи там, де
## гравець і так їде прямо.
##
## final_facing — останнє слово: фейсинг, який вирішив core/ (напрямок
## останнього пройденого кроку), а не здогад вигляду з path. -1 (типово)
## означає «немає окремого фінального facing» — орієнтація лишається такою,
## якою її поставив останній крок шляху.
func move_along(path: Array[Vector2i], duration_per_step: float, final_facing: int = -1) -> Signal:
	# Той самий власник rotation_degrees.y, що й face()/_set_facing_instant()
	# (_face_tween): цей твін теж крутить її (послідовно з рухом, нижче), тож
	# перш ніж почати свій, він убиває будь-який живий твін від попереднього
	# face() — інакше «доворот на місці, і одразу рух» лишає два твіни на
	# тій самій властивості. І сам зберігається в _face_tween ПІСЛЯ створення,
	# щоб наступний face()/_set_facing_instant() міг убити вже ЙОГО, а не
	# лишити рух і новий поворот змагатись за той самий кут (рев'ю, дрібний
	# блокер — раніше цей твін ніде не зберігався взагалі).
	if _face_tween != null and _face_tween.is_valid():
		_face_tween.kill()
	var tween: Tween = create_tween()
	_face_tween = tween
	if path.is_empty():
		# Твін без жодного кроку міг би ніколи не подати finished — гарантований
		# нульовий інтервал забезпечує, що сигнал таки настане.
		tween.tween_interval(0.0)
		return tween.finished

	var current_cell: Vector2i = IsoCameraRig.world_to_cell(position)
	# Твін ще не виконався в момент побудови графа нижче — rotation_degrees.y
	# лишиться незмінним аж до реального програвання, тож цю величину
	# доводиться передбачати самим, а не перечитувати властивість між кроками
	# (той самий прийом найкоротшої дельти, що й у face()).
	var predicted_degrees: float = rotation_degrees.y
	for i in path.size():
		var cell: Vector2i = path[i]
		var is_last_step: bool = i == path.size() - 1
		var step_facing: int = Board.facing_towards(current_cell, cell)
		var target_facing: int = final_facing if (is_last_step and final_facing >= 0) else step_facing
		var target_degrees: float = _degrees_for_facing(target_facing)
		var delta: float = fposmod(target_degrees - predicted_degrees + 180.0, 360.0) - 180.0

		# set_parallel(false) перед КОЖНИМ tween_property нижче — кожен виклик
		# сам ставить кордон нової послідовної сходинки (а не лише перший після
		# parallel(true)), тож поворот і рух ніколи не потрапляють в одну й ту
		# саму паралельну групу, навіть коли якийсь крок пропускає поворот.
		if delta != 0.0:
			# Доворот НА МІСЦІ, перш ніж юніт зрушить у новий тайл — це і є
			# виправлення бага: раніше цей tween_property йшов паралельно з
			# рухом нижче (set_parallel(true)) і юніт в'їжджав носом у стару
			# сторону. _FACE_TURN_DURATION, не duration_per_step: той самий
			# короткий поворот, що й у face(), — крок лишається читабельним, а
			# хід не починає відчуватись повільним.
			tween.set_parallel(false)
			tween.tween_property(self, "rotation_degrees:y", predicted_degrees + delta, _FACE_TURN_DURATION)
		predicted_degrees += delta

		tween.set_parallel(false)
		tween.tween_property(self, "position", IsoCameraRig.cell_to_world(cell), duration_per_step)

		current_cell = cell
		facing = target_facing
	return tween.finished


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
	_face_tween.tween_property(self, "rotation_degrees:y", current + delta, _FACE_TURN_DURATION)


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
	_hp_bar.texture = _hp_bar_texture(ratio)
	# Білий: колір тепер живе всередині текстури (рамка, тло й заливка мають
	# кожен свій), і modulate поверх нього перефарбував би й рамку теж.
	_hp_bar.modulate = Color.WHITE
	_hp_label.text = "%d/%d" % [hp, max_hp]


## Єдине джерело правди про показане HP — для UI й тестів. Колишнє
## _hp_bar.scale.x більше нічого не означає (§бриф, скарга власника).
func hp_ratio() -> float:
	return _hp_ratio


## Рамка (1 px по периметру), темне тло всередині й заливка від ЛІВОГО краю
## завширшки ratio — одна текстура, один спрайт. Заливка росте зліва
## направо, як у референсі; старий scale.x стискав смугу до центру.
static func _hp_bar_texture(ratio: float) -> ImageTexture:
	var inner := Rect2i(Vector2i.ONE, _HP_BAR_SIZE - Vector2i(2, 2))
	var fill_width: int = roundi(float(inner.size.x) * ratio)
	# Ключ — ціла ширина заливки: різних текстур не більше, ніж пікселів смуги.
	var key: Array = ["hp", fill_width]
	if _texture_cache.has(key):
		return _texture_cache[key]
	var image := Image.create(_HP_BAR_SIZE.x, _HP_BAR_SIZE.y, false, Image.FORMAT_RGBA8)
	image.fill(_HP_BAR_FRAME_COLOR)
	image.fill_rect(inner, _HP_BAR_BACK_COLOR)
	if fill_width > 0:
		# Колір з показаної ширини, а не з ratio: одна ширина — один вигляд.
		var shown: float = float(fill_width) / float(inner.size.x)
		image.fill_rect(Rect2i(inner.position, Vector2i(fill_width, inner.size.y)), Color.RED.lerp(Color.GREEN, shown))
	_texture_cache[key] = ImageTexture.create_from_image(image)
	return _texture_cache[key]


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


## Твінує _silhouette, а не self: self.scale належить play_destroyed(), і два
## твіни на одну властивість змагались би на пострілі, який убиває.
func play_shot() -> Signal:
	var tween: Tween = create_tween()
	tween.tween_property(_silhouette, "scale", Vector3.ONE * _SHOT_PUNCH_SCALE, _SHOT_PUNCH_UP)
	tween.tween_property(_silhouette, "scale", Vector3.ONE, _SHOT_PUNCH_DOWN)
	return tween.finished


func play_destroyed() -> Signal:
	var tween: Tween = create_tween()
	tween.tween_property(self, "scale", Vector3.ZERO, _DESTROY_DURATION)
	return tween.finished


func _build_silhouette(type_id: int, owner: int) -> void:
	# free(), не queue_free(): відкладене звільнення лишає щойно відкріплений
	# вузол «сиротою» до наступного кадру, і headless-тести це фіксують.
	for child in _silhouette.get_children():
		child.free()

	var built := UnitSilhouettes.build(type_id, PLAYER_COLORS[owner % PLAYER_COLORS.size()])
	for part in built.get_children():
		built.remove_child(part)
		_silhouette.add_child(part)
	built.free()
	var hull := _silhouette.get_node("Hull") as MeshInstance3D
	var hull_size: Vector3 = (hull.mesh as BoxMesh).size
	_hull_material = hull.material_override as StandardMaterial3D

	# ЧАСОВИЙ ІНСТРУМЕНТ РОЗРОБНИКА (Task 2) — єдиний виклик, єдине місце, де стрілку
	# додають на дошку. Прибрати стрілку — це прибрати рівно ці два рядки
	# (або поставити _DEBUG_SHOW_FACING_ARROW у false), а не шукати по файлу.
	if _DEBUG_SHOW_FACING_ARROW:
		_silhouette.add_child(_build_facing_arrow(hull_size))


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
