class_name BattleScreen
extends Node3D
## Task 2.10: збірка зрізу. Все, що зроблено в Task 2.1–2.9, зводиться сюди —
## і сюди ж перекладається кожне з рішень R1/R5/R7/R9, бо жоден з попередніх
## файлів не мав контейнера юнітів, у якому вони живуть.
##
## R5 (успадковано без змін): і InputController, і Pathing.compute_zones()
## всередині нього вже читають лише known_occupied_map() — цей файл нічого не
## додає до того рішення, лише не заводить власного, другого читання
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

## Бій закінчився / гравець вийшов у меню. Маршрутизація — у _ready (лише справжній запуск).
signal match_finished
signal left_to_menu

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
const _FallbackMap := preload("res://maps/river.tres")

@onready var _camera_rig: IsoCameraRig = %CameraRig
@onready var _board_view: BoardView = %BoardView
@onready var _units: Node3D = %Units
## Тіні-контакт усіх юнітів — один MultiMesh; поза %Units, де лежать лише вигляди юнітів і ефекти.
var _contacts := UnitContacts.new()
## Смуги HP усіх юнітів — теж один MultiMesh.
var _hp_bars := UnitHpBars.new()
@onready var _mine_layer: MineLayer = %MineLayer
@onready var _wreck_layer: WreckLayer = %WreckLayer
@onready var _hud: Hud = %Hud
@onready var _gate: HandoverGate = %HandoverGate
@onready var _pause: PauseMenu = %PauseMenu
@onready var _replay_overlay: ReplayOverlay = %ReplayOverlay
@onready var _ui: CanvasLayer = $UI
@onready var _weather: WeatherRig = $WeatherRig

## Куди пише «Зберегти й вийти» і що стирає завершений матч; тести підміняють.
var save_path: String = MatchService.SAVE_PATH

var _match_service: Node = null
var _prev_quit_on_go_back: bool = true
## Обмеження кадрів до бою; _exit_tree() повертає його.
var _prev_max_fps: int = 0
## Об'їзд дошки за гейтом (_warm_board) робиться один раз за життя екрана.
var _board_warmed: bool = false
## Тести вмикають об'їзд і без вікна.
var warm_board_in_headless: bool = false
var _warm_stops: Array[Vector2i] = []
## -1: юніти ще не будували; далі — скільки кадрів їх тримати під гейтом.
var _warm_units_frames: int = -1
## Кадри прогріву розчинення лісу за гейтом: −1 — ще не почато.
var _warm_forest_frames: int = -1
## Те саме для розчинення рослинності (VegetationLayer).
var _warm_veg_frames: int = -1
## Відлік спокою: таймер, а не _process, — у спокої екран не робить нічого щокадру (§8).
var _idle_timer: Timer
## Відкритий оверлей налаштувань (null, поки не відкривали).
var _settings: SettingsScreen = null
var _controller: InputController = null
var _zone_overlay: ZoneOverlay = null
var _path_overlay: PathOverlay = null
var _target_overlay: TargetOverlay = null
## Id, позначені останнім оглядом (InputController.inspected).
var _threatened: Array[int] = []
var _drone_threatened: Array[int] = []
var _event_player: EventPlayer = null
## Гравець, чий світ зараз на екрані. До гейта це ще попередній гравець, хоча
## `state.active_player` уже наступний: уламки з пакета передачі ходу звіряються з
## розвіданим того, хто дивиться, а не того, хто от-от сяде.
var _shown_viewer: int = 0
## Повтор ходів противників: копія матчу й глядач, чий туман на ній показано. Поки
## null, екран читає живий матч і активного гравця.
var _replay_state: BattleState = null
var _replay_viewer: int = -1
## Стан перед командою такту, що грається: з нього береться HP юніта, який щойно вийшов на екран.
var _replay_before: BattleState = null
## Номер повтору: кінець (сам, пропуском чи виходом екрана) його міняє, і такт, що прокинеться
## після цього, нічого вже не робить.
var _replay_run: int = 0
## Дошка на екрані під час повтору: копія початку відрізка, на яку лягають лише показані зміни
## мостів. Стан такту вже несе й мости, змінені непоміченим інженером раніше.
var _replay_board: Board = null
## Вид клітинок, з якого зараз намальована дошка (BoardView.rebuild_tiles).
var _drawn_tiles: PackedInt32Array = PackedInt32Array()
## Клітинки, над якими зараз розчинено дахи (юніти на дошці).
var _shown_cells: Array[Vector2i] = []
## Лічильник показів (гейт, початок і кінець повтору): відкладене тіло зі старого показу не лягає.
var _fall_run: int = 0
## Шрами бою на землі; маска — розвідане того, хто дивиться.
var _scars: ScarMap = null
## Шейдери ефектів уже розігріто: на старті нового бою, а в бою зі збереження — на першому
## гейті, коли камера вже стоїть на юнітах.
var _fx_warmed: bool = false
## Клітинки, у які в'їжджала техніка: ПРАВДА про розчавлені пропси, як BattleState.broken_forest
## для просік. Лише вигляд, тож живе тут, а не в core/; глядачеві показується обрізаною його
## seen (§3.5), інакше уламки огорожі видали б невидимий танк.
## shortcut: збереження цю правду не пише, тож «Продовжити» показує пропси цілими; перенести її
## в BattleState і серіалізатор (як broken_forest), коли розчавлене стане помітним між сесіями.
var _crushed_truth: Dictionary[Vector2i, bool] = {}
## Рухи техніки пакета, що грається (UnitMoved -> true): крок такого руху валить опори й паркани.
var _vehicle_moves: Dictionary[Events.UnitMoved, bool] = {}
## Кроки техніки за матч (Vector4i: з клітинки x,y у z,w): паркани й ворота ламаються лише там, де пройшов корпус.
## Видно їх глядачеві лише на розвіданому (_rebuild_units_for_active_player).
var _crush_edges: Array[Vector4i] = []
## Початки парканів, які зламав вал упалої опори (PropLayer.secondary_broke): правда для перебудов і гейта.
var _crush_marks: Array[Vector3] = []

## unit_id -> UnitView. Єдине джерело істини про те, які вузли юнітів зараз
## на дошці — саме з нього InputController і EventPlayer резолвлять id.
var _unit_views: Dictionary = {}

## R13/§3.13: поріг, за яким затиснутий палець/ЛКМ перестає бути тапом і стає
## паном камери. ~10dp = 10 логічних px, бо UiScale тримає логічний px ≈ dp
## (_drag_threshold_px() нижче) — одне місце, а не розмазане по обробниках.
const _DRAG_THRESHOLD_DP: float = 10.0
## Ясне небо (BattleLook.sky_clear): на сонці пропси кидають тінь, інакше висять над землею. Під
## хмарами River світло розсіяне, і будинки без тіні від землі не відриваються. Не за прозорістю
## тіні: на сонячних картах вона навмисно м'яка й світліша, ніж під хмарами.
const STRUCTURE_SHADOW_MIN_SKY_CLEAR: float = 0.5
## Частка світла, яку забирає запечена тінь лісу на сонячній карті (ForestLayer).
const FOREST_SHADOW: float = 0.22
## Мокра карта для пропсів (мости темніші й блищать): River під дощем — 0.55, сухі — 0.
const WET_MIN: float = 0.3

## Довгий натиск (docs/ui/overlays.md): палець тримається стільки, не перетнувши
## поріг драга, — огляд дальності замість тапу; відпускання його знімає.
const LONG_PRESS_SEC: float = 0.5
## §8: хід здебільшого стоїть на місці, а батарея — спільна для всіх гравців. Після
## IDLE_AFTER_S без натисків, руху камери й анімації подій кадр обмежено до IDLE_FPS.
const IDLE_FPS: int = 30
const IDLE_AFTER_S: float = 1.0
## Повтор ходів противників грає сам, прискорено (Engine.time_scale), а тап прискорює поточний такт ще
## дужче. Ніщо в ньому не залежить від швидкості гравця (§1.1): це показ, а не правило.
const REPLAY_SPEED: float = 2.5
const REPLAY_FAST_FORWARD: float = 20.0
## Зум повтору: не ближче, ніж уміщає хід на кілька клітинок, і не далі за середину діапазону рига,
## де юніт ще читається силуетом.
const REPLAY_ZOOM_MIN: float = IsoCameraRig.MIN_ZOOM + 2.0
const REPLAY_ZOOM_MAX: float = (IsoCameraRig.MIN_ZOOM + IsoCameraRig.MAX_ZOOM) * 0.5

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
## Скільки тримається поточний натиск (_process()) і чи вже став довгим — тоді
## відпускання знімає огляд і НЕ є тапом.
var _press_held_sec: float = 0.0
var _long_pressed: bool = false

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
## стан, populate() наповнює його юнітами, begin() праймить
## видимість УСІХ гравців і запускає перший хід
## (core/battle_state.gd:44-72, MatchService.begin()).
##
## match_service — null для звичайного показу (тоді береться автозавантажений
## синглтон MatchService), або власний екземпляр для ізольованого тесту — той
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
## екземпляра теста. Відкласти її через call_deferred теж не рятує — відкладений
## виклик приходить у вже звільнений вузол.
func _ready() -> void:
	# Кадр потрібен лише поки тримається натиск (§8: нерухомий екран нічого не коштує).
	set_process(false)
	add_child(_contacts)
	add_child(_hp_bars)
	_prev_max_fps = Engine.max_fps
	_idle_timer = Timer.new()
	_idle_timer.one_shot = true
	_idle_timer.autostart = true
	_idle_timer.wait_time = IDLE_AFTER_S
	_idle_timer.timeout.connect(_on_idle_timeout)
	add_child(_idle_timer)
	_pause.settings_requested.connect(_open_settings)
	_pause.save_quit_requested.connect(_on_save_quit)
	_pause.surrender_requested.connect(_on_surrender)
	_hud.pause_pressed.connect(_open_pause)
	_replay_overlay.skip_pressed.connect(_on_replay_skip)
	_replay_overlay.environment = _weather.environment
	_camera_rig.view_changed.connect(_follow_weather)
	_camera_rig.view_changed.connect(_follow_forest)
	_follow_forest()
	# Android «назад» інакше виходить із гри разом із матчем; на цьому екрані
	# воно відкриває паузу. Значення меню повертає _exit_tree().
	_prev_quit_on_go_back = get_tree().quit_on_go_back
	get_tree().quit_on_go_back = false
	if get_tree().current_scene != self:
		return
	# Маршрути виходу з бою ведуть крізь SceneRouter лише у справжньому запуску;
	# у тестах сигнали просто спостерігаються.
	left_to_menu.connect(SceneRouter.goto_main_menu)
	match_finished.connect(SceneRouter.goto_results)
	_launch_from_service_or_fallback()


## Конфіг/завантаження, залишені MatchService меню; без них (сцена запущена
## напряму) — резервний матч.
func _launch_from_service_or_fallback() -> void:
	if _controller != null:
		return
	match MatchService.launch_mode:
		MatchService.Launch.NEW:
			launch(MatchService)
		MatchService.Launch.RESUME:
			resume(MatchService)
		_:
			_start_fallback_match_if_not_injected()


func _start_fallback_match_if_not_injected() -> void:
	if _controller != null:
		return
	setup(_FallbackMap, 2, _FALLBACK_SEED)


func launch(match_service: Node) -> void:
	var map: MapData = _FallbackMap
	if match_service.map_path != "":
		map = (load(match_service.map_path) as MapData) if ResourceLoader.exists(match_service.map_path) else null
		if map == null:
			map = _FallbackMap
	if not setup(map, match_service.players, match_service.seed_value, match_service):
		return
	match_service.launch_mode = MatchService.Launch.NONE
	# §3.5: «Почати» міг натиснути будь-хто з гравців, тож перший хід — теж за
	# гейтом, як «Продовжити»; юніти з'являться на confirmed.
	_clear_unit_views()
	_gate.show_for(_match_service.state.active_player, _match_service.state.turn_number, _match_service.state)
	_warm_board()


## Ґрунт дошки завжди з карти (MapData.ground_state).
## false — карта зламана (populate() відмовив): матч не починається, екран
## повертає в меню; порожня дошка без кінця була б гірша за вихід.
func setup(map_data: MapData, player_count: int, seed_value: int, match_service: Node = null) -> bool:
	_match_service = match_service if match_service != null else MatchService

	var board: Board = map_data.to_board()
	_match_service.start_match(board, player_count, seed_value)
	if not map_data.populate(_match_service.state):
		push_error("BattleScreen: карта відхилена — напрям поза 0..7")
		# Порожній матч не мусить пережити відмову: автозбереження в _notification
		# записало б його, і «Продовжити» вело б у бій без юнітів.
		_match_service.state = null
		left_to_menu.emit()
		return false
	_match_service.begin()
	# R9: ця черга — рівно TurnStarted (і, за потреби, MineRevealed) першого
	# ходу; TileRevealed усіх гравців тут відкинуто ще у start() самим core/,
	# тож зливати чергу безпечно — початковий туман нижче йде не з неї.
	_match_service.take_events()

	_board_view.surface = map_data.surface
	_mine_layer.surface = map_data.surface
	_board_view.relief_seed = map_data.name_key.hash()
	_board_view.ring_map = map_data
	_set_overlay_context(map_data)
	_contacts.map = map_data
	# Шлях самої карти, а не `map_path` сервісу: прямий запуск і резервний матч його не ставлять.
	var look: BattleLook = BattleLook.for_map_path(map_data.resource_path)
	_board_view.season = look.season
	_board_view.structure_shadows = look.sky_clear >= STRUCTURE_SHADOW_MIN_SKY_CLEAR
	_board_view.wet = look.wetness >= WET_MIN
	_apply_forest_sun(look)
	_weather.apply(look)
	BattleFx.wetness = look.wetness
	_wire_view(board)
	# Техніка, що стоїть на клітинці від старту матчу, теж розчавила дрібні пропси під собою; глядач
	# бачить це, як і решту шрамів, лише на розвіданому (§3.5, _rebuild_units_for_active_player).
	_crushed_truth.clear()
	_crush_edges.clear()
	_crush_marks.clear()
	for p in _state().player_count:
		for u: Unit in _state().units_of(p):
			if u.unit_class() != UnitTypes.UnitClass.INFANTRY:
				_crushed_truth[u.pos] = true
				_crush_edges.append(Vector4i(u.pos.x, u.pos.y, u.pos.x, u.pos.y))
	# R9: перший показ юнітів — зі стану (known_occupied_map -> vision.seen),
	# не з потоку подій, який щойно злитий вище.
	_rebuild_units_for_active_player(true)
	_rebuild_wrecks()
	_warm_up_fx(_first_unit_cell(_viewer()))
	# fly_to(), не center_on(): у самостійному запуску гейта немає, і програмний
	# рух камери мусить доводитись плавно. Через launch() дошку одразу закриває
	# гейт, а center_on() на confirmed зупиняє цей твін — витікати нічому.
	_camera_rig.fly_to(_first_unit_cell(_viewer()))
	_match_service.events_ready.connect(_on_events_ready)
	return true


## «Продовжити»: вигляд з уже завантаженого state, без нового матчу. Пристрій
## віддають невідомо кому, тож дошка ховається за гейтом активного гравця;
## юніти й камера з'являються на confirmed (_on_gate_confirmed), як при передачі ходу.
## Під гейтом уже стоять міни, шрами, дахи й ліс того самого гравця, а ще йде об'їзд дошки
## (_warm_board), який на кілька кадрів ставить і одразу прибирає його юнітів.
func resume(match_service: Node = null) -> void:
	_match_service = match_service if match_service != null else MatchService
	# Підтипи поверхні живуть у MapData, не в збереженні: беремо їх з карти збереженої гри.
	var mp: String = _match_service.map_path
	var saved_map: MapData = null
	if mp != "" and ResourceLoader.exists(mp):
		saved_map = load(mp) as MapData
		_board_view.surface = saved_map.surface
		_mine_layer.surface = saved_map.surface
		_board_view.relief_seed = saved_map.name_key.hash()
		_board_view.ring_map = saved_map
	if saved_map != null:
		_set_overlay_context(saved_map)
	else:
		# Карти немає: гейт і пауза показують типову плиту й «-», а не чужу Річку.
		_gate.set_context("", "")
		_pause.set_context("", "")
	var look: BattleLook = BattleLook.for_map_path(mp)
	_board_view.season = look.season
	_board_view.structure_shadows = look.sky_clear >= STRUCTURE_SHADOW_MIN_SKY_CLEAR
	_board_view.wet = look.wetness >= WET_MIN
	_apply_forest_sun(look)
	_weather.apply(look)
	BattleFx.wetness = look.wetness
	_wire_view(_state().board)
	_gate.show_for(_match_service.state.active_player, _match_service.state.turn_number, _match_service.state)
	_warm_board()
	_match_service.events_ready.connect(_on_events_ready)
	_match_service.launch_mode = MatchService.Launch.NONE


func _wire_view(board: Board) -> void:
	_wreck_layer.set_wind(_weather.wind())
	BattleFx.wind = _weather.wind()
	_scars = ScarMap.new(Vector2i(board.width, board.height))
	_board_view.scar_map = _scars
	_board_view.build(board)
	_drawn_tiles = board.tiles.duplicate()
	# Мирний дим 1–3 димарів і 1–2 руїн: мапа та сама — і вибір той самий.
	if _board_view.props() != null:
		var props: PropLayer = _board_view.props()
		if not props.topple_hit.is_connected(_on_topple_hit):
			props.topple_hit.connect(_on_topple_hit)
			props.topple_landed.connect(_on_topple_landed)
			props.secondary_broke.connect(_on_secondary_broke)
		_wreck_layer.set_hearths(_board_view.props().chimney_tops(), _board_view.props().ruin_centres(), board.width * 73 + board.height * 31,
				_board_view.props().ruin_smoke_point_at)
	_camera_rig.set_bounds(Vector2i(board.width, board.height))
	_weather.attach_probe(_board_view.reflection_probe())
	_follow_weather()

	_zone_overlay = ZoneOverlay.new(_board_view)
	_path_overlay = PathOverlay.new(_board_view)
	_target_overlay = TargetOverlay.new(_board_view)
	_event_player = EventPlayer.new(Callable(self, "unit_view_for"), Callable(self, "_unit_for"),
		_on_bridge_changed,
		_on_wreck_left, _on_wreck_removed, _on_unit_found, _on_cell_entered, _on_unit_appeared, _on_unit_vanished)
	_event_player.forest_changed.connect(forest_changed)
	_event_player.figures_fell.connect(_on_figures_fell)
	_controller = InputController.new(_match_service, _zone_overlay, Callable(_event_player, "is_playing"))
	# Шлях — та сама система контурів, що й зони (game/battle/path_overlay.gd),
	# але власний шар і власний сигнал: action_preview малює його для прев'ю
	# руху, pending_cleared знімає його на скасуванні/підтвердженні/новому
	# виборі — саме там, де InputController уже гарантує, що _pending більше
	# не описує жодної дії (input_controller.gd, _clear_pending()).
	_controller.action_preview.connect(_path_overlay.show_preview)
	_controller.pending_cleared.connect(_path_overlay.clear)
	# Скарга власника: прев'ю пострілу було видно лише числами в нижній панелі,
	# а сама ціль на дошці не позначалась ніяк. Ті самі два сигнали, що й у
	# шляху вище: action_preview ставить приціл, pending_cleared знімає.
	_controller.action_preview.connect(_on_action_preview)
	_controller.pending_cleared.connect(_clear_all_crosshairs)
	# Допустимі тайли верби інженера (Task 8) — готові з core/ крізь контролер.
	_controller.targets_changed.connect(_target_overlay.show_tiles)
	# Дрон (Task 10): кільце на тому самому шарі цілей і позначки на юнітах — усе
	# готове з Targeting. disarm() завжди шле targets_changed, тож там і знімаємо.
	_controller.drone_armed.connect(_on_drone_armed)
	_controller.targets_changed.connect(func(_tiles: Array[Vector2i]) -> void: _clear_forbidden_marks())
	# Огляд (Task 14, §3.13): кільця й позначки готові з Targeting крізь контролер.
	_controller.inspected.connect(_on_inspected)

	_hud.bind(_state())
	_hud.attach_controller(_controller)
	_hud.attach_match_service(_match_service)
	# Панель характеристик належить вибраному юніту, а не куту екрана (скарга
	# власника: «рухаю камеру — вікно лишається на місці»). Прив'язка йде після
	# bind() навмисно: attach_camera() одразу ставить панель на місце, а робити
	# це до того, як HUD узагалі знає стан, означало б рахувати позицію без
	# вибору й без дошки.
	_hud.attach_camera(_camera_rig)
	_hud.attach_unit_views(func() -> Dictionary: return _unit_views)
	_hud.end_turn_pressed.connect(_on_end_turn_pressed)

	_gate.confirmed.connect(_on_gate_confirmed)


func _follow_weather() -> void:
	_weather.follow(_camera_rig.global_position, _camera_rig.zoom_level)


func _exit_tree() -> void:
	if _event_player != null:
		_event_player.stop()
	if _replay_state != null:
		# Екран пішов посеред повтору (пауза -> зберегти й вийти): прискорення — стан усього процесу.
		_replay_run += 1
		Engine.time_scale = 1.0
		_set_replay(null, -1)
	Engine.max_fps = _prev_max_fps
	if get_tree() != null:
		get_tree().quit_on_go_back = _prev_quit_on_go_back


## Жест «назад»: пауза відкрита — закриваємо як Resume, інакше відкриваємо.
## Згортання/закриття застосунку — автозбереження (save_current сам видаляє
## збереження завершеного матчу, тож застарілий автосейв не воскресить виграний бій). Гейт при Continue вмикається наявним шляхом, нічого не відкриваємо.
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_GO_BACK_REQUEST:
			# Гейт передачі: пауза під ним дісталась би гравцеві, що заходить.
			if _gate.visible:
				return
			# Закриваємо верхній оверлей: налаштування, інакше пауза.
			if is_instance_valid(_settings) and not _settings.is_queued_for_deletion():
				_settings.get_node("%BackButton").pressed.emit()
			elif _pause.visible:
				_pause.hide()
			else:
				_open_pause()
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST:
			if _match_service != null and _match_service.state != null:
				_match_service.save_current(save_path)


## Гейт і пауза показують карту; вона незмінні протягом матчу.
func _set_overlay_context(map_data: MapData) -> void:
	_gate.set_context(map_data.resource_path, map_data.name_key)
	_pause.set_context(map_data.resource_path, map_data.name_key)


func _open_pause() -> void:
	_pause.open(_match_service.state.turn_number)


## Налаштування з паузи відкриваються поверх бою, а не заміною сцени: бій
## (стан, вигляд, відкрита пауза) лишається під ними як є, тож нічого не треба
## автозберігати й відновлювати. «Назад» у оверлеї просто закриває його.
func _open_settings() -> void:
	_settings = preload("res://game/ui/settings_screen.tscn").instantiate()
	_settings.overlay = true
	_ui.add_child(_settings)


## Здача йде тим самим шляхом, що й кінець ходу: команда → події → програвач.
## 2 гравці — MatchEnded → результат; 3 — TurnStarted → гейт наступного гравця.
func _on_surrender() -> void:
	# Заблоковано — пауза лишається відкритою, натискання не зникає мовчки. На повторі теж: між
	# тактами програвач вільний, а на дошці ще копія.
	if _event_player.is_playing() or _replay_state != null or _match_service.state.is_over():
		return
	_pause.hide()
	var err: String = _match_service.submit(ConcedeCommand.create())
	assert(err == "", "core/ відхилив здачу: %s" % err)


func _on_save_quit() -> void:
	# Пауза досяжна й під час показу MatchEnded: завершений матч веде в результат,
	# як і в match_finished, а не в меню з мертвим збереженням.
	if _match_service.state.is_over():
		_match_service.delete_save(save_path)
		match_finished.emit()
		return
	var err: Error = _match_service.save_current(save_path)
	if err != OK:
		_pause.show_error("pause_save_failed")
		return
	left_to_menu.emit()


func unit_view_for(unit_id: int) -> UnitView:
	return _unit_views.get(unit_id, null) as UnitView


func input_controller() -> InputController:
	return _controller


## §3.13/§6: прев'ю приходить готовим — тут лише читається "target_id" і
## вмикається позначка. Жодного перерахунку дальності, сектора чи шкоди:
## рішення, що постріл узагалі можливий, уже прийняв InputController крізь
## Targeting/FireCommand.preview().
##
## Гасимо ВСІ перед тим, як увімкнути потрібний: два прев'ю пострілу поспіль
## (гравець перебирає цілі) інакше лишили б приціл на попередній — pending_cleared
## між ними не приходить, бо _pending не скидається, а перезаписується.
func _on_action_preview(preview: Dictionary) -> void:
	_clear_all_crosshairs()
	if preview.is_empty() or not int(preview["type"]) in [InputController.ActionType.SHOT, InputController.ActionType.DRONE]:
		return
	# Ціль може й не мати вузла — фог вирішує це окремо (§3.5), і вигляд не
	# сперечається з ним.
	var target_view: UnitView = unit_view_for(int(preview["target_id"]))
	if target_view != null:
		target_view.set_targeted(true)


## marks — {id: причина} з Targeting.drone_marks(): "" — приціл, інакше — хрест.
## Ворог без вузла (фог) не позначається — вигляд не сперечається з туманом.
func _on_drone_armed(center: Vector2i, radius: int, marks: Dictionary) -> void:
	_target_overlay.show_drone_reach(center, radius)
	for id: int in marks:
		var view: UnitView = unit_view_for(id)
		if view == null:
			continue
		if marks[id] == "":
			view.set_targeted(true)
		else:
			view.set_forbidden(true)


## Позначки тримаються списком id: вузли юнітів перебудовуються після кожного
## пакета подій (_rebuild_units_for_active_player), а огляд — ні.
func _on_inspected(inspection: Dictionary) -> void:
	_threatened.assign(inspection.get("marked", []))
	_drone_threatened.assign(inspection.get("drone_marked", []))
	_target_overlay.show_rings(inspection)
	_apply_threat_marks()


func _apply_threat_marks() -> void:
	for id: int in _unit_views:
		var view: UnitView = _unit_views[id]
		view.set_threatened(_threatened.has(id))
		view.set_drone_threatened(_drone_threatened.has(id))


func _clear_forbidden_marks() -> void:
	for id in _unit_views:
		(_unit_views[id] as UnitView).set_forbidden(false)


## Без окремого поля з id останньої цілі: _unit_views — це юніти одного екрана
## бою, зайвий стан тут дорожчий за прохід словником.
func _clear_all_crosshairs() -> void:
	for id in _unit_views:
		(_unit_views[id] as UnitView).set_targeted(false)


## game/ui/handover_gate.gd, крок 4 контракту (обов'язковий): маршрутизація
## тапів дошки йде через _unhandled_input(), а не _input() чи власний
## raycast-зворотний виклик, що не звіряється з GUI-деревом. Це не декор: Godot сам
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
## `Viewport`. Тому _on_magnify_gesture() нижче звіряється з `_gate.visible`
## явно, сам; якщо колись поруч з'явиться InputEventPanGesture чи інший
## жест — він теж потребує такої ж явної перевірки, Control-дерево його не
## прикриє.
func _unhandled_input(event: InputEvent) -> void:
	if _replay_state != null:
		_replay_input(event)
		return
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
## enable_pan_and_scale_gestures` типово вимкнений у Godot 4.7.1 —
## Android узагалі не шле InputEventMagnifyGesture, тож щипок збирається тут
## напряму з двох потоків ScreenTouch/ScreenDrag за їхнім `index`, а не
## покладається на подію, якої на головній платформі проєкту не існує.
##
## Третій+ палець (долоня чи великий палець при передачі пристрою з рук у
## руки — реальний сценарій для цього проєкту, §1) ІГНОРУЄТЬСЯ повністю: не
## додається в _touch_positions, і його підняття теж ігнорується (перевірка
## `has()` нижче, ДО erase) — інакше erase() зайвого індексу випадково
## зменшував би розмір словника й підняття третього пальця читалось би як
## кінець щипка/жесту двох перших, лишаючи їх без жодного господаря (рев'ю,
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
		# завершення щипка як тап по дошці — рев'ю відтворило це на
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
		# Скасований дотик (шторка, відкидання долоні) — не намір гравця: без тапу.
		if st.canceled:
			_pointer_down = false
			_cancel_peek()
			_camera_rig.end_hold()
		else:
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
	_cancel_peek()
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
	_press_held_sec = 0.0
	_long_pressed = false
	set_process(true)
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
## є причина, з якої тап міг вибрати тайл за кілька тайлів від точки
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
## камера рухається під час активного драга, тож тайл під точкою
## відпускання може вже не збігатися з тим, де насправді стояв палець на
## початку жесту (а для того, що ЛИШИЛОСЬ тапом — під порогом — камера
## взагалі не зсувалась, тож обидві точки й так майже збігаються; беремо
## press із міркувань коректності, а не тому, що тут це щось міняє).
##
## Поріг перевіряється тут ЩЕ РАЗ, не лише з прапорця
## _drag_exceeded_threshold: проміжні motion/drag-події могла з'їсти інша
## Control-вузол (HUD лежить унизу екрана — рівно там, де й їде палець),
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
	if _long_pressed:
		# Відпускання довгого натиску — лише кінець огляду, ніколи не тап.
		_cancel_peek()
		if _drag_exceeded_threshold:
			_camera_rig.end_pan()
		return
	if _drag_exceeded_threshold:
		_camera_rig.end_pan()
		return
	if _gesture_had_pinch:
		# Щипок мусить закінчуватись без тапу взагалі, навіть коли палець,
		# що лишився після нього, одразу піднявся, не перетнувши поріг
		# драга (рев'ю, головна поломка 3) — див. коментар у _on_screen_touch().
		return
	_handle_tap_at_screen_position(_press_screen_pos)


## Лічильник довгого натиску. Драг (поріг перетнуто) чи щипок ним ніколи не стають:
## обидва скидають _pointer_down/_drag_exceeded_threshold раніше, ніж натиск дотримається.
func _process(delta: float) -> void:
	if not _pointer_down or _drag_exceeded_threshold or _long_pressed or _controller == null:
		set_process(false)
		return
	_press_held_sec += delta
	if _press_held_sec >= LONG_PRESS_SEC:
		_long_pressed = true
		set_process(false)
		# Картка утримання обходить палець: їй потрібна точка натиску, а не лише клітинка.
		_hud.note_press(_press_screen_pos)
		_controller.peek_cell(_camera_rig.screen_point_to_cell(_press_screen_pos))


## _input, а не _unhandled_input: натиск на кнопку HUD чи гейта теж будить кадри. Рух
## камери й анімація подій завжди починаються з натиску; поки вони тривають, відлік
## спокою починається знову. Натиск знімає лише обмеження спокою й повертає те, що
## було до бою.
func _input(_event: InputEvent) -> void:
	_idle_timer.start()
	if Engine.max_fps != _prev_max_fps:
		Engine.max_fps = _prev_max_fps


func _on_idle_timeout() -> void:
	if _camera_rig.is_processing() or (_event_player != null and _event_player.is_playing()):
		_idle_timer.start()
	else:
		Engine.max_fps = IDLE_FPS


func _cancel_peek() -> void:
	_long_pressed = false
	if _controller != null:
		_controller.end_peek()


## UiScale (Task 4.1) робить логічний px ≈ dp, тож поріг у dp — це вже логічні
## пікселі події; ділення на content_scale_factor дало б на телефоні з
## фактором 1.627 лише ~6 dp замість задуманих 10.
func _drag_threshold_px() -> float:
	return _DRAG_THRESHOLD_DP


## Екранна геометрія (промінь -> тайл) живе в IsoCameraRig (game/camera/,
## §1 non-goals) — ця функція лише резолвлює тайл і передає його в
## InputController.tap_cell(), точнісінько так, як задокументовано в
## input_controller.gd: «сюди приходить готовий Vector2i».
func _handle_tap_at_screen_position(screen_pos: Vector2) -> void:
	if _controller == null:
		return
	var cell: Vector2i = _camera_rig.screen_point_to_cell(screen_pos)
	_controller.tap_cell(cell)


## Стан, з якого екран малює: копія повтору або живий матч.
func _state() -> BattleState:
	return _replay_state if _replay_state != null else _match_service.state


## Чиє знання зараз на дошці. Дії (хід, гейт, команди) читають active_player зі справжнього стану.
func _viewer() -> int:
	if _replay_state != null:
		# −1 як індекс мовчки читав би туман останнього гравця — витік, а не помилка.
		assert(_replay_viewer >= 0, "повтор без глядача")
		return _replay_viewer
	return _state().active_player


## Копія повтору й глядач ставляться й знімаються лише разом.
func _set_replay(state: BattleState, viewer: int) -> void:
	assert(state == null or viewer >= 0, "повтор без глядача")
	_replay_state = state
	_replay_viewer = viewer if state != null else -1


## Перший кадр повтору — світ глядача на початку відрізка: юніти з набору фільтра на тих клітинках,
## де вони тоді стояли, уламки, міни, мости й ліс зі знімка. Усе це й камера на першій видимій дії —
## ДО зняття гейта (контракт game/ui/handover_gate.gd): камера попереднього гравця не показується ні
## кадру. Шрами, розчавлені пропси й дахи будинків тримає екран, а не знімок, тож вони лишаються як є.
func _begin_replay(replay: ReplayFilter.Result) -> void:
	_set_replay(replay.start, _match_service.state.active_player)
	_replay_before = replay.start
	# Повторена техніка не валить нічого нового: усе, що вона повалила, вже лежить.
	_vehicle_moves.clear()
	_rebuild_wrecks()
	var b: Board = replay.start.board
	_replay_board = Board.create(b.width, b.height, b.ground_state)
	_replay_board.tiles = b.tiles.duplicate()
	_show_tiles(_replay_board)
	_rebuild_units_for_active_player(true, replay.on_screen_start)
	var focus: Vector2i = replay.beats[0].focus
	if not _fx_warmed:
		_warm_up_fx(focus)
	_hud.visible = false
	_replay_overlay.begin(replay.beats.size())
	# Зум попереднього гравця після повтору не повертається: камера вже належить тому, хто сів.
	_camera_rig.set_zoom(clampf(_camera_rig.zoom_level, REPLAY_ZOOM_MIN, REPLAY_ZOOM_MAX))
	_camera_rig.center_on(focus)
	_gate.visible = false
	_play_replay(replay)


## Такти грають самі, прискорено. Стан на екрані — уже після команди такту, як і в живій грі, поки
## грають її події; юнітів між тактами не перебудовують.
func _play_replay(replay: ReplayFilter.Result) -> void:
	var run: int = _replay_run
	for i in replay.beats.size():
		var beat: ReplayFilter.Beat = replay.beats[i]
		Engine.time_scale = REPLAY_SPEED
		_set_replay(beat.after, _replay_viewer)
		_replay_overlay.show_beat(i, beat.actor, beat.turn)
		# Твін, убитий пропуском, finished не подає: такт тоді просто лишається спати.
		await _camera_rig.fly_to(_beat_frame(beat)).finished
		if run != _replay_run:
			return
		_event_player.play(beat.events)
		if _event_player.is_playing():
			await _event_player.playback_finished
		if run != _replay_run:
			return
		_sync_replay_views(beat.on_screen)
		_replay_before = beat.after
	_end_replay()


## Куди летить камера в такті: фокус, а якщо другий учасник такту тоді ліг би під написи чи кнопку
## повтору — середина між ними. Другий учасник — ціль чи стрілець першого пострілу або дрона, або кінець
## маршруту; лише той, кого фільтр малює (§3.5): кадр, підігнаний під юніт у тумані, показав би, де він.
func _beat_frame(beat: ReplayFilter.Beat) -> Vector2i:
	var other: Vector2i = beat.focus
	for e in beat.events:
		if e is Events.ShotFired or e is Events.DroneLaunched:
			for id: int in [e.attacker_id, e.target_id]:
				var u: Unit = beat.after.get_unit(id)
				if u != null and u.pos != beat.focus and (_unit_views.has(id) or beat.on_screen.has(id)):
					other = u.pos
			break
		if e is Events.UnitMoved and not e.path.is_empty():
			other = e.path.back()
			break
	var offset: Vector2 = _camera_rig.unproject(IsoCameraRig.cell_to_world(other)) \
		- _camera_rig.unproject(IsoCameraRig.cell_to_world(beat.focus))
	return _replay_overlay.frame_for(beat.focus, other, offset)


## Кінець повтору, сам чи пропуском, — рівно раз: справжній стан, HUD і камера на першому юніті, як
## після гейта без повтору.
func _end_replay() -> void:
	if _replay_state == null:
		return
	_replay_run += 1
	Engine.time_scale = 1.0
	_set_replay(null, -1)
	_replay_before = null
	_replay_board = null
	_replay_overlay.finish()
	BattleFx.clear_all(get_tree())
	_cancel_falls()
	_show_tiles(_state().board)
	_rebuild_units_for_active_player(true)
	_rebuild_wrecks()
	_hud.visible = true
	_hud.bind(_state())
	_camera_rig.center_on(_first_unit_cell(_viewer()))


func _on_replay_skip() -> void:
	if _replay_state == null:
		return
	_event_player.cancel()
	_end_replay()


## Повтор: дошка не приймає нічого, крім тапу, що прискорює поточний такт. Ні вибору, ні огляду, ні
## руху камери: камеру веде повтор, і перетягування билося б із його польотом.
func _replay_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	var st := event as InputEventScreenTouch
	if (mb != null and mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed) \
			or (st != null and not st.pressed and not st.canceled):
		Engine.time_scale = REPLAY_FAST_FORWARD


## Повтор: юніт виходить на екран лише так — набір фільтра, не видимість на копії. Вузол стає на
## клітинку появи з HP до команди такту: стан на екрані вже після неї, і шкода показалась би раніше
## пострілу.
func _on_unit_appeared(unit_id: int, pos: Vector2i, facing: int) -> void:
	var was: Unit = _replay_before.get_unit(unit_id)
	var shown := Unit.create(unit_id, was.type_id, was.owner, pos, facing)
	shown.hp = was.hp
	shown.drones_left = was.drones_left
	_on_unit_vanished(unit_id)
	_add_unit_view(shown)
	_shown_cells.append(pos)
	_board_view.set_reveal_cells(_shown_cells)


func _on_unit_vanished(unit_id: int) -> void:
	var view: UnitView = unit_view_for(unit_id)
	if view == null:
		return
	view.free()
	_unit_views.erase(unit_id)


## Після такту на дошці рівно набір фільтра: загиблий у такті юніт сходить (перебудови між тактами
## нема), а дахи розчинені над тими, хто намальований.
func _sync_replay_views(on_screen: Dictionary) -> void:
	for id: int in _unit_views.keys():
		if not on_screen.has(id):
			_on_unit_vanished(id)
	_shown_cells.clear()
	for id: int in _unit_views:
		_shown_cells.append(_state().get_unit(id).pos)
	_shown_cells.append_array(_mine_layer.cells())
	_board_view.set_reveal_cells(_shown_cells)


## Міст змінився. На повторі на копію дошки лягає лише ця клітинка (§3.5): стан такту вже несе й
## мости, які непомічений інженер змінив раніше, і повна перемальовка показала б їх завчасно.
func _on_bridge_changed(pos: Vector2i) -> void:
	if _replay_state == null:
		_show_tiles(_state().board)
		return
	_replay_board.set_kind(pos, _state().board.kind_at(pos))
	_show_tiles(_replay_board)


## Перебудова дошки повна й дорога (§8): лише коли вид клітинок інший, ніж намальований.
func _show_tiles(board: Board) -> void:
	if board.tiles == _drawn_tiles:
		return
	_drawn_tiles = board.tiles.duplicate()
	_board_view.rebuild_tiles(board)


func _unit_for(unit_id: int) -> Unit:
	if _match_service == null or _state() == null:
		return null
	return _state().get_unit(unit_id)


## HUD вимикає кнопку кінця ходу, щойно матч завершився (hud.gd, refresh()), —
## але рішення лишається тут: сигнал end_turn_pressed може прийти й не від тієї
## кнопки, а покладатися на її стан означало б довіряти вигляду те, що вже
## вирішили правила (EndTurnCommand.validate() → ERR_MATCH_OVER). assert нижче
## не пом'якшено навмисно: він стереже розбіжність вигляду з правилами.
func _on_end_turn_pressed() -> void:
	if _event_player.is_playing() or _replay_state != null or _match_service.state.is_over():
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
	_record_crushes(events)
	_hud.hold_tag(true)
	await _event_player.play(events)
	_hud.hold_tag(false)
	_hud.units_changed()

	var turn_started: bool = false
	var match_ended: bool = false
	for event in events:
		if event is Events.TurnStarted:
			turn_started = true
		elif event is Events.MatchEnded:
			match_ended = true

	if match_ended:
		# Завершену гру не можна «продовжити» — збереження стирається тут,
		# після того як останню подію вже показано.
		_match_service.delete_save(save_path)
		match_finished.emit()
		return

	if turn_started:
		# §1.2: вибір і прев'ю попереднього гравця не сміють пережити гейт —
		# select_unit(null) очищає і InputController, і оверлей зон разом.
		# R7: рекон і перебудова — лише як реакція на confirmed нижче, не тут.
		_controller.select_unit(null)
		# Огляд не переживає гейт (§3.13): натиск, що тримався, тут і закінчено.
		_cancel_peek()
		if _pointer_down:
			_camera_rig.end_hold()  # інакше риг крутить _process за гейтом до наступного натиску (§8)
		_pointer_down = false
		# Дим влучань висить кілька секунд: над тайлом, якого наступний гравець не розвідав, він
		# показав би, де стояла ціль (§3.5).
		BattleFx.clear_all(get_tree())
		# Те, що ламається, обривається разом з миттями: інакше падіння, що доходить під гейтом, показало б
		# наступному гравцеві пил над клітинкою, яку він не розвідав.
		_cancel_falls()
		_gate.show_for(_match_service.state.active_player, _match_service.state.turn_number, _match_service.state)
	elif not events.all(func(e: Events.BattleEvent) -> bool: return e is Events.UnitTurned):
		# Поворот на місці не міняє ні позицій, ні огляду (ромб без фейсингу), а
		# перебудова поставила б вузли миттєво й з'їла б анімацію повороту.
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
	BattleFx.clear_all(get_tree())
	_cancel_falls()
	var replay: ReplayFilter.Result = _match_service.replay_for(_match_service.state.active_player)
	if replay != null:
		_begin_replay(replay)
		return
	# Дахи — одразу в стан нового гравця, без переходу (§3.5): див. PropLayer.set_reveal_cells.
	_rebuild_units_for_active_player(true)
	_rebuild_wrecks()
	if not _fx_warmed:
		_warm_up_fx(_first_unit_cell(_viewer()))
	_camera_rig.center_on(_first_unit_cell(_viewer()))
	_gate.visible = false


func _clear_unit_views() -> void:
	for id in _unit_views.keys():
		(_unit_views[id] as UnitView).free()
	_unit_views.clear()


## §3.5: повна перебудова — найпростіший спосіб гарантувати, що на дошці
## рівно ті вузли, які known_occupied_map(активного) дозволяє знати. Юніт, що
## щойно рухався, устигає доанімуватись (play() уже дочекався його твіна) до
## виклику цієї функції, тож перебудова не рве рух на середині кроку.
## instant — розчинення дахів без переходу (гейт передачі й перший показ). drawn — лише на повторі:
## id юнітів, яких дав фільтр (ReplayFilter.Result.on_screen_start).
func _rebuild_units_for_active_player(instant: bool = false, drawn: Dictionary = {}) -> void:
	var state: BattleState = _state()
	_clear_unit_views()
	# §3.11: міни — той самий знімок знання активного гравця, що й юніти, і в ті
	# самі моменти (setup, після пакета подій, на confirmed гейта).
	_mine_layer.rebuild(state, _viewer())
	_wreck_layer.rebuild_fallen(state, _viewer())
	# Розвідане росте з кожним кроком — шрами на щойно розвіданому з'являються одразу.
	if _scars != null:
		_scars.show_for(state.vision[_viewer()])

	# Повтор малює набір фільтра: посеред схованого маршруту загону копія його бачить (ReplayFilter.Beat).
	var ids: Array = drawn.keys() if _replay_state != null else state.known_occupied_map(_viewer()).values()
	# Дах над показаним юнітом розчиняється — і лише над показаним: невидимий ворог під будинком
	# прозорим дахом себе не видає.
	_shown_cells.clear()
	for id: int in ids:
		var unit: Unit = state.get_unit(id)
		if unit == null:
			continue
		_add_unit_view(unit)
		_shown_cells.append(unit.pos)
	# Міна під дахом чи кроною теж мусить бути видна, як юніт.
	_shown_cells.append_array(_mine_layer.cells())
	# HUD ставить плити за екранними прямокутниками саме цих вузлів (§3.5: лише видимі гравцеві).
	_hud.units_changed()
	_board_view.set_reveal_cells(_shown_cells, instant)
	var crushed: Array[Vector2i] = []
	for pos: Vector2i in _crushed_truth:
		if state.vision[_viewer()].is_seen(pos):
			crushed.append(pos)
	# Злам показується, лише коли власна клітинка пропса розвідана глядачем (PropLayer.set_crushed), як шрами й ліс.
	_board_view.set_crushed_cells(crushed, instant, _crush_edges, state.vision[_viewer()].is_seen, _crush_marks)
	forest_changed()
	_apply_threat_marks()


func _add_unit_view(unit: Unit) -> void:
	var view: UnitView = _UnitViewScene.instantiate()
	view.contacts = _contacts
	view.hp_bars = _hp_bars
	_units.add_child(view)
	view.bind(unit)
	_unit_views[unit.id] = view


## Загін в укритті знайдено посеред ходу — він з'являється на тому кроці, а не після всього
## шляху. Дах над ним розчиняється тієї ж миті: фігура під суцільним дахом не видна. Решту
## клітинок не перераховуємо зі стану: той уже кінцевий, і дахи над ворогом, якого хід
## відкриє лише далі, розчинилися б раніше, ніж він з'явиться.
func _on_unit_found(unit_id: int) -> void:
	var state: BattleState = _state()
	var unit: Unit = state.get_unit(unit_id)
	# На повторі на екран виводить лише Appeared: видимість на копії бреше посеред схованого маршруту.
	if _replay_state != null or unit == null or not unit.is_alive() or _unit_views.has(unit_id) \
			or not state.can_see_unit(_shown_viewer, unit):
		return
	_add_unit_view(unit)
	_shown_cells.append(unit.pos)
	_board_view.set_reveal_cells(_shown_cells)


## §3.5: уламки, вогонь і дим — лише над розвіданим (`seen`) гравцем, що сідає.
## Не в _rebuild_units_for_active_player(): та йде після кожного пакета подій і
## щоразу народжувала б щойно поставлені уламки наново, з новою фазою диму.
func _rebuild_wrecks() -> void:
	_fall_run += 1
	_shown_viewer = _viewer()
	_event_player.viewer = _shown_viewer
	_wreck_layer.rebuild(_state(), _shown_viewer)
	# Плями — за загиблими показаного стану (на повторі — його початку): відділення, що на повторі ще
	# стоїть, плями під собою не має, а пляма вигорілих уламків лишається.
	_scars.reset_scorches()
	for w in _state().wrecks:
		if not _no_scorch(w.pos):
			_scars.stamp_scorch(w.pos)
	for u: Unit in _state().units.values():
		if u.is_alive() or _no_scorch(u.pos):
			continue
		if u.unit_class() == UnitTypes.UnitClass.INFANTRY:
			_scars.stamp_squad_scorch(u.pos)
		else:
			_scars.stamp_scorch(u.pos)
	_scars.show_for(_state().vision[_shown_viewer])


## Щойно знищена техніка: її вузол існував, отже тайл розвіданий тим, хто дивиться.
## Перевірка все одно потрібна — події не фільтруються за гравцем (§6), і на здачі
## WreckLeft приходить для всієї техніки того, хто здався.
func _on_wreck_left(pos: Vector2i, type_id: int, facing: int, owner: int) -> void:
	# Пляма ставиться завжди: на нерозвіданому її ховає маска, а розвідка згодом покаже.
	if not _no_scorch(pos):
		_scars.stamp_scorch(pos)
	if _state().vision[_shown_viewer].is_seen(pos):
		_wreck_layer.add(pos, type_id, 1.0, facing, UnitSilhouettes.set_of(owner))


## Бійці лягають там, де відділення стояло, у мить влучання; події не фільтровані за гравцем (§6),
## тож показується лише тіло, вже показане глядачеві в `core/` (`Casualties.Body.shown_to()`).
## Тіло береться з показаного стану за (unit_id, seq): об'єкт події на повторі — живий стан перегону, і
## його біти показу вже кінця проміжку.
func _on_figures_fell(body: Casualties.Body) -> void:
	# Фігури, що перекидаються, сповзають туди, де ляже тіло.
	var view: UnitView = _unit_views.get(body.unit_id)
	if view != null and is_instance_valid(view):
		var targets: Dictionary = {}
		for slot in range(body.first, body.first + body.count):
			targets[slot] = WreckLayer.body_transform(body, slot, _state().board, WreckLayer.earlier_on_tile(_state().bodies, body))
		view.aim_tips(targets)
	# Тіло лягає, коли фігура вже перекинулась (UnitView._tip_over).
	get_tree().create_timer(UnitView.FALL_TIP_SEC).timeout.connect(_land_body.bind(body.unit_id, body.seq, _fall_run))
	# Ніхто не лишився стояти — відділення знищене: стримана пляма (на нерозвіданому її ховає маска).
	if body.first == 0 and _scars != null and not _no_scorch(body.pos):
		_scars.stamp_squad_scorch(body.pos)


## Відкладене тіло: за цей час міг змінитися гравець за гейтом, початися чи скінчитися повтор
## (`_fall_run`) — тоді тіло вже не цього показу. Інакше — з показаного стану й лише показане глядачеві.
func _land_body(unit_id: int, seq: int, run: int) -> void:
	if run != _fall_run:
		return
	for b: Casualties.Body in _state().bodies:
		if b.unit_id == unit_id and b.seq == seq and b.shown_to(_shown_viewer):
			_wreck_layer.add_body(b)


## Тайл без плями: вода й підірваний міст (загиблі в річці) і міст — карта шрамів лежить на ґрунті, а
## під настилом це русло; пляма там зринула б, щойно міст підірвуть, і не відновилась би на перебудові.
func _no_scorch(pos: Vector2i) -> bool:
	var k: int = _state().board.kind_at(pos)
	return k == Terrain.Kind.WATER or k == Terrain.Kind.BRIDGE_DESTROYED or k == Terrain.Kind.BRIDGE


## Прибрати показане — нічого не розкриває. Решту на гейті перемалює _rebuild_wrecks().
func _on_wreck_removed(pos: Vector2i, _reason: int) -> void:
	_wreck_layer.remove(pos)


## Перше вбивство не сміє застигати на компіляції шейдерів ефектів: малюємо кожен раз,
## невидимо, там, куди дивиться камера (поза кадром рушій їх не малює й не компілює).
func _warm_up_fx(cell: Vector2i) -> void:
	_fx_warmed = true
	var at: Vector3 = IsoCameraRig.cell_to_world(cell)
	BattleFx.warm_up(_units, at)
	_wreck_layer.warm_up(at)


## Поки гейт закриває екран, камера по кадру стоїть над кожним блоком дошки (BoardWarmUp), а потім
## над першим юнітом гравця, що сідає, з його юнітами: матеріали, які інакше вперше потрапили б у
## кадр після гейта чи на першому скролі, компілюються тут. Під гейтом лишаються міни, шрами, дахи
## й ліс того самого гравця (їх і так ставить setup/resume), а юніти після об'їзду знову прибираються
## й з'являються, як і раніше, на confirmed. Гейт не чіпається; якщо гравець устиг підтвердити,
## об'їзд кидається: камера вже стоїть на його позиції. Покадрово через сигнал кадру, а не await:
## з'єднання зі звільненим екраном рушій розриває сам, тож корутина не прокинеться на мертвому вузлі.
## Без вікна (headless) нічого не малюється; `warm_board_in_headless` — лише для тестів.
func _warm_board() -> void:
	if _board_warmed or (DisplayServer.get_name() == "headless" and not warm_board_in_headless):
		return
	_board_warmed = true
	var board: Board = _state().board
	_warm_stops = BoardWarmUp.stops(Vector2i(board.width, board.height))
	_warm_units_frames = -1
	_warm_forest_frames = -1
	_warm_veg_frames = -1
	get_tree().process_frame.connect(_warm_tick, CONNECT_ONE_SHOT)


func _warm_tick() -> void:
	if not _gate.visible:
		return
	if not _warm_stops.is_empty():
		_camera_rig.center_on(_warm_stops.pop_front())
	elif _warm_forest_frames < 0:
		# Матеріали розчинення лісу (прохід глибини й колір) з'являються, лише коли юніт стоїть під
		# кроною: розчинена крона кожного атласу біля середини дошки — тут, за гейтом.
		var board: Board = _state().board
		var cell: Vector2i = _board_view.forest().warm_fade(Vector2i(board.width / 2, board.height / 2))
		if cell.x >= 0:
			_camera_rig.center_on(cell)
		_warm_forest_frames = 2
	elif _warm_forest_frames > 0:
		_warm_forest_frames -= 1
	elif _warm_veg_frames < 0:
		# Розчинення рослин (кущ, дерево, очерет над юнітом) — так само за гейтом.
		var board: Board = _state().board
		var veg: VegetationLayer = _board_view.vegetation()
		var cell: Vector2i = veg.warm_fade(Vector2i(board.width / 2, board.height / 2)) if veg != null else Vector2i(-1, -1)
		if cell.x >= 0:
			_camera_rig.center_on(cell)
		_warm_veg_frames = 2
	elif _warm_veg_frames > 0:
		_warm_veg_frames -= 1
	elif _warm_units_frames < 0:
		# Юніти з'являються лише на confirmed, тож їхні матеріали й підписи теж уперше малювалися б
		# у першому кадрі після гейта.
		_rebuild_units_for_active_player(true)
		_camera_rig.center_on(_first_unit_cell(_viewer()))
		_warm_units_frames = 2
	elif _warm_units_frames > 0:
		_warm_units_frames -= 1
	else:
		_clear_unit_views()
		return
	get_tree().process_frame.connect(_warm_tick, CONNECT_ONE_SHOT)


## Сонце карти для запеченої тіні лісу: напрям НА сонце, як у WeatherRig (sun.basis.z), і сила —
## слабша під похмурим небом (менше прямого світла).
func _apply_forest_sun(look: BattleLook) -> void:
	_board_view.sun_dir = Basis.from_euler(Vector3(deg_to_rad(-look.light_pitch_deg), deg_to_rad(look.light_yaw_deg), 0.0)).z
	_board_view.forest_shadow = FOREST_SHADOW * clampf(look.light_energy / 1.5, 0.4, 1.0)


## Зум камери для лісу: підлісок лише до ForestLayer.DETAIL_ZOOM.
func _follow_forest() -> void:
	_board_view.set_forest_zoom(_camera_rig.zoom_level)
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam != null:
		_board_view.set_view_eye(cam.global_position)


## Гачок вигляду лісу: його перемальовують з known_broken_map(активного) — ніколи з
## події. Викликається з перебудови після пакета подій і на гейті, тобто і на ForestBroken,
## і на передачі ходу.
func forest_changed() -> void:
	var state: BattleState = _state()
	_board_view.set_forest_broken(state.known_broken_map(_viewer()))


## Техніка, що ввійшла в клітинку, розчавлює її дрібні пропси; піхота проходить повз. Шлях
## UnitMoved — лише тайли, у які юніт справді ввійшов. Юніт, що загинув на міні, зі стану вже
## може зникнути: техніка лишає остов (WreckLeft) на останньому тайлі, піхота — ні.
func _record_crushes(events: Array[Events.BattleEvent]) -> void:
	_vehicle_moves.clear()
	var wrecks: Dictionary = {}
	for e in events:
		if e is Events.WreckLeft:
			wrecks[(e as Events.WreckLeft).pos] = true
	for e in events:
		if not e is Events.UnitMoved:
			continue
		var moved := e as Events.UnitMoved
		var unit: Unit = _state().get_unit(moved.unit_id)
		var vehicle: bool = unit.unit_class() != UnitTypes.UnitClass.INFANTRY if unit != null \
				else wrecks.has(moved.path.back())
		if vehicle:
			_vehicle_moves[moved] = true
			for pos in moved.path:
				_crushed_truth[pos] = true


## Початок кроку техніки: опори й паркани клітинки падають, але лише на розвіданому (§3.5) — інакше
## падіння вказало б, де їде невидимий ворог. Нерозвідане лишається в _crushed_truth і постане вже
## повалене, коли його розвідають.
func _on_cell_entered(moved: Events.UnitMoved, from: Vector2i, to: Vector2i) -> void:
	var state: BattleState = _state()
	if not _vehicle_moves.has(moved):
		return
	var edge := Vector4i(from.x, from.y, to.x, to.y)
	if not _crush_edges.has(edge):
		_crush_edges.append(edge)
	_step_key = edge
	# Корпус під час падіння ще перетинає клітинку from: вал не лягає й на неї.
	var avoid: Array[Vector2i] = _known_unit_cells()
	if not avoid.has(from):
		avoid.append(from)
	_board_view.props().topple_cell(to, from, avoid, state.vision[_viewer()].is_seen)


## Точки падіння — у координатах шару пропсів; мить живе в _units, тож її в'язка — до нього.
func _units_point(p: Vector3) -> Vector3:
	return _units.to_local(_board_view.props().to_global(p))


## Секції паркану, зламані одним кроком, дають один момент удару, а не по моменту на секцію (§8): збираємо їх до кінця
## кадру й зливаємо в один виклик. Опори — кожна своя.
var _hit_batch: Array[Dictionary] = []
var _land_batch: Array[Dictionary] = []
## Крок техніки (з клітинки x,y у z,w), що зараз ламає: ключ злиття ударів, а не кадр (затримка не зливає різні кроки).
var _step_key: Vector4i = Vector4i.ZERO

func _on_topple_hit(at: Vector3, top: Vector3, debris: int, live_wire: bool, is_pole: bool, span: Vector3) -> void:
	if is_pole:
		var base: Vector3 = _units_point(at)
		BattleFx.spawn_topple_hit(_units, base, _units_point(top), debris as BattleFx.Debris, live_wire, true, _units_point(at + span) - base)
		return
	_hit_batch.append({"at": at, "top": top, "debris": debris, "live": live_wire, "span": span, "step": _step_key})
	if _hit_batch.size() == 1:
		_flush_hits.call_deferred()


func _flush_hits() -> void:
	var by_step: Dictionary = {}
	for e: Dictionary in _hit_batch:
		if not by_step.has(e["step"]):
			by_step[e["step"]] = [] as Array[Dictionary]
		(by_step[e["step"]] as Array[Dictionary]).append(e)
	_hit_batch.clear()
	for step: Vector4i in by_step:
		var group: Array[Dictionary] = by_step[step]
		var u: Dictionary = _union_line(group, "at", "span")
		var at: Vector3 = u["at"]
		var top: Vector3 = at
		var live := false
		for e: Dictionary in group:
			top += ((e["top"] as Vector3) - (e["at"] as Vector3)) / float(group.size())
			live = live or bool(e["live"])
		var base: Vector3 = _units_point(at)
		BattleFx.spawn_topple_hit(_units, base, _units_point(top), _majority(group) as BattleFx.Debris, live, false,
				_units_point(at + (u["span"] as Vector3)) - base)


## Спільна лінія кількох відрізків: центр і піввідрізок уздовж найдовшого з них, що вкриває всі кінці. Кожен запис —
## центр (ключ at) і півдовжина-вектор (ключ span).
func _union_line(list: Array[Dictionary], at_key: String, span_key: String) -> Dictionary:
	var dir := Vector3.RIGHT
	var longest: float = 0.0
	var mean := Vector3.ZERO
	for e: Dictionary in list:
		mean += (e[at_key] as Vector3) / float(list.size())
		if (e[span_key] as Vector3).length() > longest:
			longest = (e[span_key] as Vector3).length()
			dir = (e[span_key] as Vector3).normalized()
	var lo: float = INF
	var hi: float = -INF
	for e: Dictionary in list:
		for sgn: float in [-1.0, 1.0]:
			var q: float = ((e[at_key] as Vector3) + (e[span_key] as Vector3) * sgn).dot(dir)
			lo = minf(lo, q)
			hi = maxf(hi, q)
	var centre: Vector3 = mean + dir * ((lo + hi) * 0.5 - mean.dot(dir))
	return {"at": centre, "span": dir * ((hi - lo) * 0.5)}


func _majority(list: Array[Dictionary]) -> int:
	var count: Dictionary = {}
	var best: int = int(list[0]["debris"])
	for e: Dictionary in list:
		count[int(e["debris"])] = int(count.get(int(e["debris"]), 0)) + 1
		if int(count[int(e["debris"])]) > int(count.get(best, 0)):
			best = int(e["debris"])
	return best


func _on_secondary_broke(origin: Vector3) -> void:
	if not _crush_marks.has(origin):
		_crush_marks.append(origin)


func _on_topple_landed(a: Vector3, b: Vector3, debris: int, live_wire: bool, is_pole: bool, cell: Vector2i) -> void:
	# Падіння бачимо лише на розвіданому (_on_cell_entered), тож слід на мокрій землі — теж лише там.
	if _board_view.wet and _scars != null:
		_scars.stamp_scuff(a, b, cell)
	if is_pole:
		BattleFx.spawn_topple_land(_units, _units_point(a), _units_point(b), debris as BattleFx.Debris, live_wire, true)
		return
	_land_batch.append({"at": (a + b) * 0.5, "span": (b - a) * 0.5, "debris": debris})
	if _land_batch.size() == 1:
		_flush_lands.call_deferred()


func _flush_lands() -> void:
	if _land_batch.is_empty():
		return
	var u: Dictionary = _union_line(_land_batch, "at", "span")
	var c: Vector3 = u["at"]
	var half: Vector3 = u["span"]
	BattleFx.spawn_topple_land(_units, _units_point(c - half), _units_point(c + half), _majority(_land_batch) as BattleFx.Debris, false, false)
	_land_batch.clear()


## Клітинки юнітів, які глядач вправі знати (§3.5): повалений стовп лягає повз їхні корпуси. Усіх юнітів сюди не
## дають — напрям падіння видав би невидимого ворога.
func _known_unit_cells() -> Array[Vector2i]:
	var state: BattleState = _state()
	var out: Array[Vector2i] = []
	out.assign(state.known_occupied_map(_viewer()).keys())
	return out


func _cancel_falls() -> void:
	_hit_batch.clear()
	_land_batch.clear()
	if _board_view.props() != null:
		_board_view.props().cancel_falls()


func _first_unit_cell(player: int) -> Vector2i:
	var units: Array[Unit] = _state().units_of(player)
	if units.is_empty():
		return Vector2i.ZERO
	return units[0].pos
