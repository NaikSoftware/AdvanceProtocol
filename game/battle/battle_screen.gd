class_name BattleScreen
extends Node3D
## Task 2.10: збірка зрізу. Все, що зроблено в Task 2.1–2.9, зводиться сюди —
## і сюди ж перекладається кожна з рулінгів R1/R5/R7/R9, бо жоден з попередніх
## файлів не мав контейнера юнітів, у якому вони живуть.
##
## R5 (успадковано без змін): і InputController, і Pathing.compute_zones()
## всередині нього вже читають лише known_occupied_map() — цей файл нічого не
## додає до того рулінгу, лише не заводить власного, другого читання
## occupied_map().
##
## R7, гейт передачі ходу: контракт порядку описаний у game/ui/handover_gate.gd
## і належить виконати рівно тут. HandoverGate.show_for(player) — синхронний і
## непрозорий сам собою; він НЕ перебудовує юнітів і не рухає камеру (це не
## його справа) і не ховає себе сам після натискання «підтвердити». Обидва —
## відповідальність цього файла, у відповідь на сигнал `confirmed`,
## СИНХРОННО й ДО того, як гейт стане invisible (_on_gate_confirmed нижче).
##
## R9, початковий туман: BattleState.start() (core/battle_state.gd:57-70)
## навмисно відкидає TileRevealed кожного гравця — той потік призначений лише
## для активного гравця. Тому початкові вузли юнітів тут будуються НЕ з подій
## begin(), а прямим читанням known_occupied_map(), яке само читає
## vision[player].seen (§3.5) — стан, не потік.
##
## Фог-правило (§3.5) саме тут стає реальністю: ворожий юніт отримує вузол
## тоді й лише тоді, коли він у known_occupied_map(активного) — жодного
## тьмяного «останнього відомого положення», ворог без вузла просто відсутній.

const _UnitViewScene := preload("res://game/battle/unit_view.tscn")

## R1: єдина точка запуску, коли ЦЮ сцену показує сам двигун — вона стоїть
## run/main_scene у project.godot, і жоден інший виклик .setup() поки не
## існує: SceneRouter.goto_battle() (game/autoload/scene_router.gd) лише
## змінює сцену й не має точки ін'єкції MapData (це Phase 3, менюшна робота,
## навмисно лишена їй, а не цьому файлу). Без резервного старту тут пряме
## відкриття сцени в редакторі чи `$GODOT --path .` лишає _controller null —
## дошка стоїть порожня, і жоден тап нічого не робить.
##
## Фіксований сід (не randi() — §6 CLAUDE.md, детермінізм): це запасний,
## а не бойовий шлях, тож повторюваність важливіша за різноманіття.
const _FALLBACK_SEED: int = 1
const _FallbackMap := preload("res://maps/skirmish_bridge.tres")

@onready var _camera_rig: IsoCameraRig = %CameraRig
@onready var _board_view: BoardView = %BoardView
@onready var _units: Node3D = %Units
@onready var _hud: Hud = %Hud
@onready var _gate: HandoverGate = %HandoverGate

var _match_service: Node = null
var _controller: InputController = null
var _zone_overlay: ZoneOverlay = null
var _event_player: EventPlayer = null

## unit_id -> UnitView. Єдине джерело істини про те, які вузли юнітів зараз
## на дошці — саме з нього InputController і EventPlayer резолвлять id.
var _unit_views: Dictionary = {}

## R13/§3.13: поріг, за яким затиснутий палець/ЛКМ перестає бути тапом і стає
## паном камери. ~10dp, переведений у логічні пікселі вьюпорта діленням на
## content_scale_factor вікна (_drag_threshold_px() нижче — і коментар там
## же пояснює, чому саме ділення, не множення). Судження без усталеного
## прецеденту в проєкті (жоден інший файл ще не рахував dp) — винесено в
## окрему функцію нижче, щоб рішення було одним місцем, а не розмазаним по
## обробниках подій.
const _DRAG_THRESHOLD_DP: float = 10.0

## Крок зуму коліщатка/пінчу за одну подію. zoom_by() сам клемпить
## (IsoCameraRig.MIN_ZOOM..MAX_ZOOM) — тут лише симетричний множник туди й
## назад.
const _WHEEL_ZOOM_STEP: float = 0.9

var _pointer_down: bool = false
var _press_screen_pos: Vector2 = Vector2.ZERO
## true, як тільки сумарний зсув від натиску перевищив поріг — з цього
## моменту жест уже пан, і відпускання пальця НЕ мусить викликати tap_cell()
## (пункт 3 ТЗ).
var _drag_exceeded_threshold: bool = false

## Мультитач: index -> остання відома позиція КОЖНОГО притиснутого пальця
## (не лише активного) — потрібен щипку, щоб знати обидві точки одразу.
var _touch_positions: Dictionary = {}
## Індекс пальця, що зараз веде одно-пальцевий жест (тап/пан); -1, коли
## жодного немає (нема пальця, або зараз щипок).
var _active_touch_index: int = -1

var _pinch_active: bool = false
var _pinch_indices: Array = []
var _pinch_last_distance: float = 0.0
## true від моменту, коли поточний складений жест (від першого пальця вниз
## до всіх пальців угору) пройшов крізь щипок — навіть якщо після нього
## лишився один палець і той одразу піднявся, не перетнувши поріг драга.
## Скидається на false лише на початку СВІЖОГО жесту (перший палець з нуля,
## чи натиск миші) — саме тому, що щипок завжди закінчується підняттям без
## перетину порога, і без цього прапорця те підняття читалось би як тап.
var _gesture_had_pinch: bool = false


## R1: два кроки старту рівно в цьому порядку — start_match() лише будує
## стан, populate() наповнює його юнітами й цілями, begin() праймить
## видимість УСІХ гравців і запускає перший хід
## (core/battle_state.gd:44-72, MatchService.begin()).
##
## match_service — null для звичайного показу (тоді береться автозавантажений
## синглтон MatchService), або власний інстанс для ізольованого тесту — той
## самий прийом, що вже усталений у tests/game/test_input_controller.gd і
## tests/game/test_hud.gd.
## Резервний вхід для запуску сцени напряму (project.godot: run/main_scene).
## Без нього `$GODOT --path .` піднімає порожню дошку: setup() — єдине, що
## будує дошку, наповнює стан і створює контролер, а викликати його нема кому,
## бо SceneRouter.goto_battle() йде через change_scene_to_file() і не має куди
## передати MapData. Фазі 3 лишається обидва шляхи: ін'єктувати мапу до входу
## сцени в дерево або дорастити роутеру параметр.
##
## Гейт — саме `current_scene == self`, а не «чи вже є _controller». Сцена,
## запущена як головна, — це рівно той випадок, для якого резерв існує; сцена,
## доданa дочірнім вузлом (кожен тест у tests/game/test_battle_screen.gd), —
## ніколи. Перевірка на _controller цього не розрізняє: у тесті вона бачить
## null (setup() йде наступним рядком, уже після входу в дерево) і піднімає
## другий, фоновий матч на автозавантаженому MatchService поверх ізольованого
## інстансу теста. Відкласти її через call_deferred теж не рятує — відкладений
## виклик приходить у вже звільнений вузол.
func _ready() -> void:
	if get_tree().current_scene != self:
		return
	_start_fallback_match_if_not_injected()


func _start_fallback_match_if_not_injected() -> void:
	if _controller != null:
		return
	setup(_FallbackMap, 2, _FALLBACK_SEED)


func setup(map_data: MapData, player_count: int, seed_value: int, match_service: Node = null) -> void:
	_match_service = match_service if match_service != null else MatchService

	var board: Board = map_data.to_board()
	_match_service.start_match(board, player_count, seed_value)
	map_data.populate(_match_service.state)
	_match_service.begin()
	# R9: ця черга — рівно TurnStarted (і, за потреби, MineRevealed) першого
	# ходу; TileRevealed усіх гравців тут відкинуто ще у start() самим core/,
	# тож зливати чергу безпечно — початковий туман нижче йде не з неї.
	_match_service.take_events()

	_board_view.build(board)
	_camera_rig.set_bounds(Vector2i(board.width, board.height))

	_zone_overlay = ZoneOverlay.new(_board_view)
	_event_player = EventPlayer.new(Callable(self, "unit_view_for"), Callable(self, "_unit_for"))
	_controller = InputController.new(_match_service, _zone_overlay, Callable(_event_player, "is_playing"))

	_hud.bind(_match_service.state)
	_hud.attach_controller(_controller)
	_hud.attach_match_service(_match_service)
	_hud.end_turn_pressed.connect(_on_end_turn_pressed)

	_gate.confirmed.connect(_on_gate_confirmed)

	# R9: перший показ юнітів — зі стану (known_occupied_map -> vision.seen),
	# не з потоку подій, який щойно злитий вище.
	_rebuild_units_for_active_player()
	# fly_to(), не center_on(): це не гейтове рецентрування (жодного гейта
	# ще не показано, нічому витікати) — програмний рух камери мусить
	# доводитись плавно, за мінімальною планкою.
	_camera_rig.fly_to(_first_unit_cell(_match_service.state.active_player))

	# Підключається останнім: begin() уже відпрацював свій events_ready
	# (нікому не почутий), і жодна дія до цього рядка не мусить проганяти
	# анімацію чи гейт.
	_match_service.events_ready.connect(_on_events_ready)


func unit_view_for(unit_id: int) -> UnitView:
	return _unit_views.get(unit_id, null) as UnitView


func input_controller() -> InputController:
	return _controller


## game/ui/handover_gate.gd, крок 4 контракту (обов'язковий): маршрутизація
## тапів дошки йде через _unhandled_input(), а не _input() чи власний
## raycast-колбек, що не звіряється з GUI-деревом. Це не декор: Godot сам
## доставляє подію сюди ЛИШЕ якщо жоден Control її не з'їв першим — а
## HandoverGate, поки видимий, стоїть повнорозмірним STOP-фільтром (крок 5,
## перевірено тестами самого гейта) і ковтає її раніше, ніж вона взагалі
## дійде до цього методу. Той самий шлях уже блокує InputController.tap_cell()
## і сам, поки триває програвання (R24) — обидва запобіжники незалежні й не
## дублюють один одного.
##
## ВАЖЛИВО, і саме тут попередня версія цього файла помилялась: Control'ів
## MOUSE_FILTER_STOP зупиняє лише InputEventMouse*/ScreenTouch/ScreenDrag —
## подію, яку GUI-дерево визнає «вхідною для елемента». InputEventMagnifyGesture
## (і будь-який інший жест) НЕ належить до цього набору й проходить крізь
## видимий гейт без жодної перешкоди — перевірено емпірично на справжньому
## вьюпорті. Тому _on_magnify_gesture() нижче звіряється з `_gate.visible`
## явно, сам; якщо колись поруч з'явиться InputEventPanGesture чи інший
## жест — він теж потребує такої ж явної перевірки, Control-дерево його не
## прикриє.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_on_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_on_mouse_motion(event as InputEventMouseMotion)
	elif event is InputEventScreenTouch:
		_on_screen_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_on_screen_drag(event as InputEventScreenDrag)
	elif event is InputEventMagnifyGesture:
		_on_magnify_gesture(event as InputEventMagnifyGesture)


func _on_mouse_button(mb: InputEventMouseButton) -> void:
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
		_camera_rig.zoom_by(_WHEEL_ZOOM_STEP, mb.position)
		get_viewport().set_input_as_handled()
		return
	if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
		_camera_rig.zoom_by(1.0 / _WHEEL_ZOOM_STEP, mb.position)
		get_viewport().set_input_as_handled()
		return
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	# Мишача частина жесту ігнорується, поки щипок двома пальцями вже веде
	# зум — на десктопі це поєднання неможливе фізично, але дешевше
	# перестрахуватись тут, ніж плутати два незалежні джерела курсора.
	if _pinch_active:
		return
	if mb.pressed:
		_gesture_had_pinch = false  # мишачий жест ніколи не щипок — свіжий старт
		_begin_pointer_press(mb.position)
	else:
		_end_pointer_press(mb.position)
	get_viewport().set_input_as_handled()


func _on_mouse_motion(mm: InputEventMouseMotion) -> void:
	if not _pointer_down or mm.button_mask & MOUSE_BUTTON_MASK_LEFT == 0:
		return
	_advance_drag(mm.position, mm.relative)
	get_viewport().set_input_as_handled()


## Мультитач за пальцем (R-мультитач): лише ПЕРШИЙ притиснутий палець веде
## тап/пан (`_active_touch_index`) — другий палець, що лягає поверх уже
## активного жесту, не скидає його стан (стара версія викликала
## _begin_pointer_press() на КОЖЕН новий дотик і губила прогрес першого
## пальця), а стартує щипок. `input_devices/pointing/android/
## enable_pan_and_scale_gestures` за замовчуванням вимкнений у Godot 4.7.1 —
## Android узагалі не шле InputEventMagnifyGesture, тож щипок збирається тут
## напряму з двох потоків ScreenTouch/ScreenDrag за їхнім `index`, а не
## покладається на подію, якої на головній платформі проєкту не існує.
##
## Третій+ палець (долоня чи великий палець при передачі пристрою з рук у
## руки — реальний сценарій для цього проєкту, §1) ІГНОРУЄТЬСЯ повністю: не
## додається в _touch_positions, і його підняття теж ігнорується (перевірка
## `has()` нижче, ДО erase) — інакше erase() зайвого індексу випадково
## зменшував би розмір словника й підняття третього пальця читалось би як
## кінець щипка/жесту двох перших, лишаючи їх без жодного господаря (ревʼю,
## дрібний блокер).
func _on_screen_touch(st: InputEventScreenTouch) -> void:
	if st.pressed:
		if _touch_positions.size() >= 2:
			get_viewport().set_input_as_handled()
			return
		_touch_positions[st.index] = st.position
		if _touch_positions.size() == 1:
			_gesture_had_pinch = false  # свіжий жест з нуля — не щипок (поки що)
			_active_touch_index = st.index
			_begin_pointer_press(st.position)
		elif _touch_positions.size() == 2:
			_begin_pinch()
		get_viewport().set_input_as_handled()
		return

	if not _touch_positions.has(st.index):
		get_viewport().set_input_as_handled()
		return
	_touch_positions.erase(st.index)
	if _pinch_active:
		_end_pinch()
		# Щипок закінчується РІВНО так — підняттям одного з двох пальців, без
		# жодного перетину порога драга. Прапорець лишається true аж до
		# початку наступного СВІЖОГО жесту (гілка size()==1 вище скидає
		# його): без нього _end_pointer_press() нижче (чи то для пальця, що
		# лишився й одразу підноситься, чи взагалі без «резюме») прочитав би
		# завершення щипка як тап по дошці — ревʼю відтворило це на
		# юніті під двома пальцями: розвели, підняли, підняли — юніт
		# вибрався сам, а на вже вибраному це могло б підставити хід чи
		# постріл, яких гравець не задавав.
		_gesture_had_pinch = true
		if _touch_positions.size() == 1:
			# Один палець лишився притиснутим — це новий одно-пальцевий
			# жест від його ПОТОЧНОЇ позиції, не від точки, де він був до
			# щипка (інакше різкий стрибок _press_screen_pos дав би хибний
			# драг завдовжки в увесь щипок).
			_active_touch_index = _touch_positions.keys()[0]
			_begin_pointer_press(_touch_positions[_active_touch_index])
		get_viewport().set_input_as_handled()
		return

	if st.index == _active_touch_index:
		_end_pointer_press(st.position)
		_active_touch_index = -1
	get_viewport().set_input_as_handled()


func _on_screen_drag(sd: InputEventScreenDrag) -> void:
	if _pinch_active:
		if _pinch_indices.has(sd.index):
			_touch_positions[sd.index] = sd.position
			_update_pinch()
		get_viewport().set_input_as_handled()
		return
	if sd.index != _active_touch_index or not _pointer_down:
		return
	_touch_positions[sd.index] = sd.position
	_advance_drag(sd.position, sd.relative)
	get_viewport().set_input_as_handled()


## §3.9 non-goals не заперечує пінч — це не вільна камера, а той самий зум,
## що й коліщатко, лише інший тригер. Лишається на випадок платформ, де
## жест усе ж генерується (напр. трекпад настільної збірки для розробки) —
## основний мобільний шлях веде _begin_pinch()/_update_pinch() вище, з
## реальних ScreenTouch/ScreenDrag. Явна перевірка гейта тут обов'язкова:
## Control-дерево цей тип події не зупиняє (див. коментар над
## _unhandled_input()).
func _on_magnify_gesture(mg: InputEventMagnifyGesture) -> void:
	if _gate.visible:
		return
	_camera_rig.zoom_by(1.0 / mg.factor, mg.position)
	get_viewport().set_input_as_handled()


func _begin_pinch() -> void:
	_pinch_indices = _touch_positions.keys()
	_pinch_indices.sort()
	var a: Vector2 = _touch_positions[_pinch_indices[0]]
	var b: Vector2 = _touch_positions[_pinch_indices[1]]
	_pinch_last_distance = a.distance_to(b)
	_pinch_active = true
	# Другий палець сам собою означає намір щипка, не дотику — жест одного
	# пальця більше не завершиться тапом чи паном.
	_pointer_down = false
	_active_touch_index = -1


func _update_pinch() -> void:
	var a: Vector2 = _touch_positions[_pinch_indices[0]]
	var b: Vector2 = _touch_positions[_pinch_indices[1]]
	var distance: float = a.distance_to(b)
	if _pinch_last_distance > 0.001 and distance > 0.001:
		# Пальці розходяться (distance росте) => наближення => менший
		# zoom_level (та сама конвенція, що й у _on_magnify_gesture).
		_camera_rig.zoom_by(_pinch_last_distance / distance, (a + b) * 0.5)
	_pinch_last_distance = distance


func _end_pinch() -> void:
	_pinch_active = false
	_pinch_indices.clear()


func _begin_pointer_press(screen_pos: Vector2) -> void:
	_pointer_down = true
	_press_screen_pos = screen_pos
	_drag_exceeded_threshold = false
	# Новий дотик до дошки перебиває кидок, що ще котиться — гравець знову
	# тримає камеру рукою.
	_camera_rig.cancel_inertia()
	# Тримає _process() рига живим на ввесь час натиску, навіть коли палець
	# не рухається — інакше «зупинив перед відпусканням» лишав би виміряну
	# швидкість замороженою на останньому русі, а не згасаючою до нуля
	# (game/camera/iso_camera_rig.gd, begin_hold()).
	_camera_rig.begin_hold()


## Напрям: «пряме маніпулювання» — гравець хапає ДОШКУ і тягне її за
## пальцем. Це тепер ВЛАСНИЙ контракт pan() (game/camera/iso_camera_rig.gd,
## коментар над pan()), виведений із реальної геометрії проекції, а не
## довільний вибір знаку на боці входу: при ортопроекції з проекцією
## променя на площину дошки є рівно один знак, що дає «дошка йде за
## пальцем», і рахує його сам ріг. Тому тут — жодної інверсії, жодного
## повороту, delta йде в pan() сирою, рівно так, як прийшла з
## InputEventScreenDrag/MouseMotion.
##
## Поріг: пан НЕ застосовується, поки сумарний зсув від натиску не
## перевищить _drag_threshold_px() — інакше тремтіння пальця в межах «ще
## тапу» встигає зсунути камеру ще до того, як жест визнаний драгом (це і
## є причина, з якої тап міг вибрати клітинку за кілька тайлів від точки
## дотику). Коли поріг щойно перетнутий — камера доганяє одним стрибком на
## всю накопичену з натиску дельту (_press_screen_pos -> current), інакше
## рух під порогом просто губиться і 1:1-стеження ламається на самому
## старті жесту.
func _advance_drag(current_screen_pos: Vector2, raw_relative: Vector2) -> void:
	if not _drag_exceeded_threshold:
		if (current_screen_pos - _press_screen_pos).length() > _drag_threshold_px():
			_drag_exceeded_threshold = true
			_camera_rig.pan(current_screen_pos - _press_screen_pos)
		return
	_camera_rig.pan(raw_relative)


## Тап резолвиться від ПОЗИЦІЇ НАТИСКУ (_press_screen_pos), не відпускання:
## камера рухається під час активного драга, тож клітинка під точкою
## відпускання може вже не збігатися з тим, де насправді стояв палець на
## початку жесту (а для того, що ЛИШИЛОСЬ тапом — під порогом — камера
## взагалі не зсувалась, тож обидві точки й так майже збігаються; беремо
## press із міркувань коректності, а не тому, що тут це щось міняє).
##
## Поріг перевіряється тут ЩЕ РАЗ, не лише з прапорця
## _drag_exceeded_threshold: проміжні motion/drag-події могла з'їсти інша
## Control-нода (HUD лежить унизу екрана — рівно там, де й їде палець),
## і тоді прапорець не встиг виставитися жодного разу за весь жест.
## Довіряти саме йому означало б інколи класифікувати справжній драг як
## тап. Якщо перевірка тут ловить перетин порога вперше — камера доганяє
## одним стрибком на всю дельту жесту, так само, як у _advance_drag().
func _end_pointer_press(screen_pos: Vector2) -> void:
	if not _pointer_down:
		return
	_pointer_down = false
	_camera_rig.end_hold()
	if not _drag_exceeded_threshold:
		var total_shift: Vector2 = screen_pos - _press_screen_pos
		if total_shift.length() > _drag_threshold_px():
			_drag_exceeded_threshold = true
			_camera_rig.pan(total_shift)
	if _drag_exceeded_threshold:
		_camera_rig.end_pan()
		return
	if _gesture_had_pinch:
		# Щипок мусить закінчуватись без тапу взагалі, навіть коли палець,
		# що лишився після нього, одразу піднявся, не перетнувши поріг
		# драга (ревʼю, головна поломка 3) — див. коментар у _on_screen_touch().
		return
	_handle_tap_at_screen_position(_press_screen_pos)


## dp -> пікселі логічного простору події: `content_scale_factor` — властивість
## `Window`, не базового `Viewport` (звернення через get_viewport() впало б,
## якби цю сцену колись поклали в SubViewport, де такого поля нема), і при
## факторі > 1 події приходять у МЕНШОМУ логічному просторі, тож фіксований
## dp-поріг ділиться на фактор, а не множиться — множення давало поріг у
## кілька разів товщий за задумані ~10dp і саме на це відкат.
func _drag_threshold_px() -> float:
	var factor: float = get_window().content_scale_factor
	if factor <= 0.0:
		factor = 1.0
	return _DRAG_THRESHOLD_DP / factor


## Екранна геометрія (промінь -> клітинка) живе в IsoCameraRig (game/camera/,
## §1 non-goals) — ця функція лише резолвлює клітинку і передає її в
## InputController.tap_cell(), точнісінько так, як задокументовано в
## input_controller.gd: «сюди приходить готовий Vector2i».
func _handle_tap_at_screen_position(screen_pos: Vector2) -> void:
	if _controller == null:
		return
	var cell: Vector2i = _camera_rig.screen_point_to_cell(screen_pos)
	_controller.tap_cell(cell)


func _unit_for(unit_id: int) -> Unit:
	if _match_service == null or _match_service.state == null:
		return null
	return _match_service.state.get_unit(unit_id)


func _on_end_turn_pressed() -> void:
	if _event_player.is_playing():
		return
	var err: String = _match_service.submit(EndTurnCommand.create())
	assert(err == "", "HUD дозволив кінець ходу, який core/ відхилив: %s" % err)


## R23-стиль: єдина точка, де ця сцена реагує на щойно застосовану команду.
## Гілка вирішується рівно TurnStarted у щойно зіграному пакеті: він приходить
## лише коли EndTurnCommand дійсно передав хід (core/commands/end_turn_command.gd
## повертає РАНІШЕ, до begin_turn(), якщо матч уже завершився — TurnStarted
## тоді відсутній узагалі, і код нижче природно потрапляє в else-гілку,
## прибираючи з дошки щойно знищених юнітів фінальним станом, без жодного
## окремого випадку на MatchEnded. Екран результату — Phase 3, не цей файл
## (§10 CLAUDE.md: не вгадувати UI, якого ще немає).
func _on_events_ready() -> void:
	var events: Array[Events.BattleEvent] = _match_service.take_events()
	if events.is_empty():
		return
	await _event_player.play(events)

	var turn_started: bool = false
	for event in events:
		if event is Events.TurnStarted:
			turn_started = true
			break

	if turn_started:
		# §1.2: вибір і прев'ю попереднього гравця не сміють пережити гейт —
		# select_unit(null) очищає і InputController, і оверлей зон разом.
		# R7: рекон і перебудова — лише як реакція на confirmed нижче, не тут.
		_controller.select_unit(null)
		_gate.show_for(_match_service.state.active_player)
	else:
		_rebuild_units_for_active_player()


## R7 крок 2: реакція на confirmed, СИНХРОННО і ДО зняття гейта. Порядок між
## рецентруванням і перебудовою тут байдужий (обидва мають завершитись, поки
## гейт ще на екрані) — байдужий і документом-контрактом game/ui/handover_gate.gd.
##
## center_on(), НЕ fly_to(): рішення (не забутий параметр). Контракт гейта
## (game/ui/handover_gate.gd, крок 2a) вимагає, щоб камера стояла на позиції
## гравця, що заходить, ПОКИ ГЕЙТ ЩЕ ЗАКРИВАЄ ЕКРАН, і лише тоді гейт ховається
## (`_gate.visible = false` — останній рядок, синхронно тут-таки). Плавний
## fly_to() повертає Tween і продовжує рухати камеру ще кілька кадрів ПІСЛЯ
## цього рядка — якби гейт ховався одразу, перший кадр гравця, що заходить,
## показав би камеру ще на позиції ПОПЕРЕДНЬОГО гравця (Tween лише почав
## їхати), і лише за ~RECENTER_DURATION секунд вона доїхала б до правильної.
## Це витік прихованої інформації (§1.2), не косметика — тому саме на
## гейті рецентрування лишається миттєвим; плавним воно стає рівно там, де
## контракту гейта немає (початковий показ дошки в setup() вище). Тест, що
## це стереже: test_handover_rebuilds_units_and_recenters_camera_before_gate_lifts
## (tests/game/test_battle_screen.gd) — читає camera.global_position одразу
## після confirmed, без жодного кроку кадру; якби тут стояв fly_to(), він
## ловив би позицію ще НЕ на цілі й падав.
func _on_gate_confirmed() -> void:
	_rebuild_units_for_active_player()
	_camera_rig.center_on(_first_unit_cell(_match_service.state.active_player))
	_gate.visible = false


## §3.5: повна перебудова — найпростіший спосіб гарантувати, що на дошці
## рівно ті вузли, які known_occupied_map(активного) дозволяє знати. Юніт, що
## щойно рухався, устигає доанімуватись (play() уже дочекався його твіна) до
## виклику цієї функції, тож перебудова не рве рух на середині кроку.
func _rebuild_units_for_active_player() -> void:
	var state: BattleState = _match_service.state
	for id in _unit_views.keys():
		(_unit_views[id] as UnitView).free()
	_unit_views.clear()

	var known: Dictionary = state.known_occupied_map(state.active_player)
	for pos in known:
		var uid: int = known[pos]
		var unit: Unit = state.get_unit(uid)
		if unit == null:
			continue
		var view: UnitView = _UnitViewScene.instantiate()
		_units.add_child(view)
		view.bind(unit)
		_unit_views[uid] = view


func _first_unit_cell(player: int) -> Vector2i:
	var units: Array[Unit] = _match_service.state.units_of(player)
	if units.is_empty():
		return Vector2i.ZERO
	return units[0].pos
