class_name Hud
extends Control
## Task 2.8: постійна панель бою. §1.5 — кожне правило, що впливає на кидок,
## мусить бути видиме числом або іконкою; §3.4 — сектор, у який піде постріл,
## показується ДО підтвердження.
##
## HUD нічого не рахує. Номери ходу й гравця, стан ґрунту, AP і залишок дронів
## читаються зі стану як є; сектор і межі шкоди приходять готовими у прев'ю від
## InputController (R27) і виводяться незмінними — без округлення, усереднення
## чи власного «приблизно». Порахувати їх наново тут означало б другу копію
## бойової моделі у вигляді (§6).
##
## Єдиний шлях до дії — кнопка підтвердження, і вона кличе рівно
## InputController.confirm_pending(). Жоден інший вузол цього файлу не створює
## Command і не торкається MatchService.submit().
##
## Локалізація (§9, R29): усі підписи — стабільні ключі перекладу, а не текст.
## Поки CSV немає, ключ і показується — некрасиво, зате чесно, і пізніший CSV
## стане файлом даних, а не переписуванням кожного підпису. Числа лишаються
## числами: AP чи межа шкоди — не ключ.

## Натиснуто «завершити хід». Саме рішення — не тут: у InputController немає
## точки входу для кінця ходу, а подавати EndTurnCommand самому означало б
## завести другий шлях до core/ повз контролер. Сцена бою (Task 2.10) вирішує,
## що з цим робити (зокрема — гейт передачі пристрою, §3.5).
signal end_turn_pressed

## §3.12: стан ґрунту — правило, а не погода, тож він на екрані постійно і
## підписаний. Мапа ключів тримається тут, а не в core/: Terrain не знає про
## екран і не мусить.
const GROUND_STATE_KEYS: Dictionary = {
	Terrain.GroundState.DRY: "hud_ground_dry",
	Terrain.GroundState.MUD: "hud_ground_mud",
	Terrain.GroundState.FROZEN: "hud_ground_frozen",
}

## Іконка — колірна пляма поруч із підписом: три стани мусять різнитися й на
## погляд, бо підпис читають, а іконку впізнають.
const GROUND_STATE_COLORS: Dictionary = {
	Terrain.GroundState.DRY: Color("c2a86b"),
	Terrain.GroundState.MUD: Color("6b4a2a"),
	Terrain.GroundState.FROZEN: Color("9fd0e8"),
}

## Панель характеристик стоїть ПОРУЧ із юнітом, а не поверх нього: зсув у
## екранних пікселях від точки, у яку проєктується його клітинка. x — убік від
## силуету, y — по центру панелі проти юніта (див. _reposition_inspector()).
##
## Було 40, стало 96 на прохання власника — «малюється дуже близько до юніта,
## треба трохи поодаль». Число живе тут одне, тож відстань підбирається рівно
## цим рядком, без правок у геометрії нижче.
const INSPECTOR_GAP: float = 96.0
## Підйом точки прив'язки над площиною дошки: клітинка лежить у y=0, а сам
## юніт має висоту, і панель, приклеєна до підлоги, перекривала б його ноги.
const INSPECTOR_LIFT: float = 1.0

var _state: BattleState = null
var _controller: InputController = null
var _camera_rig: IsoCameraRig = null
var _selected_unit: Unit = null
## −1 — «гравця ще не показували жодного разу». Потрібне окремим значенням, бо
## 0 — це справжній гравець, а перехід до нового гравця мусить прибрати з
## екрана вибір попереднього (див. set_active_player()).
var _shown_player: int = -1

@onready var _turn_value: Label = %TurnValue
@onready var _player_value: Label = %PlayerValue
@onready var _ground_icon: ColorRect = %GroundStateIcon
@onready var _ground_label: Label = %GroundStateLabel
@onready var _selection_row: HBoxContainer = %SelectionRow
@onready var _ap_value: Label = %ApValue
@onready var _drones_row: HBoxContainer = %DronesRow
@onready var _drones_value: Label = %DronesValue
@onready var _preview_shot_box: HBoxContainer = %PreviewShotBox
@onready var _preview_sector_value: Label = %PreviewSectorValue
@onready var _preview_damage_value: Label = %PreviewDamageValue
@onready var _preview_move_box: HBoxContainer = %PreviewMoveBox
@onready var _preview_ap_value: Label = %PreviewApValue
@onready var _confirm_button: Button = %ConfirmButton
@onready var _cancel_button: Button = %CancelButton
@onready var _end_turn_button: Button = %EndTurnButton
@onready var _inspector: UnitInspector = %Inspector
## Поля безпеки читаються з того самого вузла, що їх і задає (§9: одне джерело
## правди) — панель поза цим контейнером, але поважає ті самі межі, бо виріз
## екрана однаково не питає, у контейнері вузол чи ні.
@onready var _safe_area: MarginContainer = %SafeArea
## Рядок дій — і нижня межа для панелі характеристик. Поля безпеки самі по собі
## тут не рятують: кнопки живуть УСЕРЕДИНІ них, а панель малюється поверх усього
## HUD, тож «влізла в безпечну зону» й «не накрила кнопки» — різні твердження.
@onready var _bottom_bar: HBoxContainer = %BottomBar


func _ready() -> void:
	_confirm_button.pressed.connect(_on_confirm_pressed)
	_cancel_button.pressed.connect(_on_cancel_pressed)
	_end_turn_button.pressed.connect(_on_end_turn_pressed)
	_clear_preview()
	_render_selection()


## Стан матчу для постійної частини панелі. Тримається посиланням, а не копією:
## BattleState змінюється на місці, і refresh() мусить читати нинішні числа, а
## не знімок, зроблений на прив'язці.
func bind(state: BattleState) -> void:
	_state = state
	refresh()


## Перечитує все, що показується постійно. Викликається і ззовні, і з
## events_ready (attach_match_service): після кожної застосованої команди AP
## вибраного юніта інший, а сам InputController про це не сигналить — він
## лишає той самий юніт вибраним (input_controller.gd:174).
func refresh() -> void:
	if _state == null:
		return
	_turn_value.text = str(_state.turn_number)
	_apply_ground_state(_state.board.ground_state)
	set_active_player(_state.active_player)
	# Матч завершився — core/ відхиляє EndTurnCommand разом з усіма іншими
	# (ERR_MATCH_OVER, core/commands/end_turn_command.gd:8), тож кнопка не сміє
	# пропонувати дію, яку правила вже не приймають. refresh() підписаний на
	# events_ready (attach_match_service), тож це спрацьовує одразу після пакета
	# подій, що завершив матч. Екран результату — Phase 3 (§10 CLAUDE.md).
	_end_turn_button.disabled = _state.is_over()
	_render_selection()


func set_active_player(player: int) -> void:
	if player != _shown_player:
		_shown_player = player
		# §1.2: приховане знання священне. Вибір і прев'ю попереднього гравця —
		# це його AP, його броня й його намір; пережити передачу ходу вони не
		# мусять навіть на кадр.
		show_selection(null)
	_player_value.text = str(player + 1)


## Вибраний юніт (null — вибору немає). Приймає будь-який юніт, не лише свій:
## залишок дронів публічний за правилом (§3.9), тож ворожа штурмова група
## показує його так само, як своя.
func show_selection(unit: Unit) -> void:
	_selected_unit = unit
	# Новий вибір скидає pending у контролері (input_controller.gd:72), тож
	# прев'ю на екрані стосувалося б дії, якої вже немає.
	_clear_preview()
	_render_selection()


## R27: словник приходить від InputController і має рівно дві форми —
## {type: MOVE, unit_id, target, path, ap_left} і
## {type: SHOT, unit_id, target_id, sector, min, max}. Дискримінатор — "type"
## зі значенням InputController.ActionType.
func show_preview(preview: Dictionary) -> void:
	# Спершу гасимо все: без цього поля попереднього прев'ю (сектор і шкода
	# пострілу) лишилися б на екрані під час показу руху й читалися б як
	# частина нової дії.
	_clear_preview()
	if preview.is_empty():
		return
	match int(preview["type"]):
		InputController.ActionType.MOVE:
			_preview_ap_value.text = str(int(preview["ap_left"]))
			_preview_move_box.visible = true
		InputController.ActionType.SHOT:
			var sector: int = int(preview["sector"])
			_preview_sector_value.text = tr(UnitInspector.SECTOR_KEYS[sector])
			# Обидві межі як є — гравець мусить бачити розкид, а не одне
			# «приблизно стільки» (§3.3, §1.5).
			_preview_damage_value.text = "%d–%d" % [int(preview["min"]), int(preview["max"])]
			_preview_shot_box.visible = true
			# §3.4: сектор видно на самій броні цілі до підтвердження.
			_inspector.highlight_sector(sector)
		_:
			return
	_confirm_button.disabled = false


## Явна прив'язка замість пошуку вузла шляхом (§9). Контролер лишається
## власником наміру: HUD слухає його сигнали і кличе його ж confirm/cancel.
func attach_controller(controller: InputController) -> void:
	_controller = controller
	controller.selection_changed.connect(show_selection)
	controller.action_preview.connect(show_preview)


## Явна прив'язка камери (§9), у тому ж стилі, що attach_controller() вище.
## Панель характеристик належить вибраному юніту, а не куту екрана: власник
## назвав це багом — «якщо рухати камеру, вікно з характеристиками лишається на
## місці». Підписка на view_changed, а не опитування рига щокадру: §8 — поки
## ніхто не возить камеру, HUD не сміє коштувати жодного кадру.
func attach_camera(rig: IsoCameraRig) -> void:
	_camera_rig = rig
	rig.view_changed.connect(_reposition_inspector)
	_reposition_inspector()


## MatchService (Task 2.1) навмисно без class_name, тож тип тут Node, а виклик
## динамічний — той самий прийом, що в input_controller.gd:37.
##
## Слухається лише events_ready; take_events() тут не викликається НІКОЛИ —
## черга належить EventPlayer (Task 2.6), і забрати з неї події означало б
## украсти в нього анімацію. HUD перечитує стан, а не потік.
func attach_match_service(service: Node) -> void:
	service.events_ready.connect(refresh)


func _apply_ground_state(ground_state: int) -> void:
	_ground_label.text = tr(GROUND_STATE_KEYS[ground_state])
	_ground_icon.color = GROUND_STATE_COLORS[ground_state]


func _render_selection() -> void:
	# Юніт міг загинути від відповіді (§3.3.1) між вибором і перемальовуванням —
	# показувати AP мерця гірше, ніж не показувати нічого.
	if _selected_unit != null and not _selected_unit.is_alive():
		_selected_unit = null
	if _selected_unit == null:
		_selection_row.visible = false
		_inspector.clear()
		return
	_selection_row.visible = true
	_ap_value.text = str(_selected_unit.ap)
	# Рядок дронів показується лише тому, у кого дрони бувають: «0» у танка —
	# шум, а не інформація, бо дронів у нього немає за ростером (§3.9).
	_drones_row.visible = int(_selected_unit.type()["drones"]) > 0
	_drones_value.text = str(_selected_unit.drones_left)
	_inspector.show_unit(_selected_unit)
	# Рівно тут, а не в _reposition_inspector(): вміст панелі змінюється тільки
	# на цьому шляху, а позиція перераховується ще й на кожен кадр руху камери
	# (view_changed). Перерахунок мінімального розміру PanelContainer з усім його
	# деревом міток на кожен кадр кидка пальцем — робота ні за що.
	_inspector.reset_size()
	_reposition_inspector()


## Чому %Inspector у hud.tscn — пряма дитина Hud, а не вузол SafeArea/Layout
## (коментар тут, бо в .tscn коментар не переживе першого ж перезбереження
## редактором): панель належить вибраному юніту, тож її місце рахується тут, а
## контейнер його б негайно перезаписав своїм. Оголошена в сцені останньою —
## отже, малюється поверх решти HUD. mouse_filter=IGNORE там же: панель тепер
## висить над самою дошкою, і тапи по клітинках під нею мусять доходити до
## _unhandled_input() сцени бою, а не гинути в PanelContainer'і.
##
## Місце панелі рахується з ЛОГІЧНОЇ клітинки юніта крізь проєкцію самого рига
## (IsoCameraRig.unproject) — жодної власної копії екранної геометрії тут нема
## і бути не може (R13). Викликається рівно на три речі: рух камери
## (view_changed), зміну вибору і refresh() — не щокадру.
func _reposition_inspector() -> void:
	if _camera_rig == null or _selected_unit == null or not _inspector.visible:
		return
	var anchor: Vector2 = _camera_rig.unproject(
		IsoCameraRig.cell_to_world(_selected_unit.pos) + Vector3(0.0, INSPECTOR_LIFT, 0.0))
	var panel: Vector2 = _inspector.size
	var left: float = float(_safe_area.get_theme_constant("margin_left"))
	var top: float = float(_safe_area.get_theme_constant("margin_top"))
	var right: float = size.x - float(_safe_area.get_theme_constant("margin_right")) - panel.x
	# Нижня межа — ВЕРХ рядка кнопок, а не низ поля безпеки. Кнопки лежать
	# усередині безпечної зони, а панель малюється поверх усього HUD, тож
	# «панель у безпечній зоні» не означає «кнопки видно». Ціна помилки конкретна:
	# єдиний легальний шлях до дії — кнопка підтвердження (§6), і гравець,
	# вибравши юніта в нижній третині кадру, тицяв би в неї наосліп.
	var bottom: float = _bottom_bar_top() - panel.y
	# Бік ВИБИРАЄТЬСЯ, а не затискається, і це не косметика. Сам по собі clampf
	# нижче, коли праворуч місця вже не лишилось, тягне панель уліво — тобто
	# рівно НА той юніт, який вона описує: на живому екрані танк зникав під
	# власними характеристиками разом зі своєю HP-смугою. Тому спершу дзеркалимо
	# панель на протилежний бік від юніта, і лише те, що не влізло й там,
	# віддаємо клемпу.
	var x: float = anchor.x + INSPECTOR_GAP
	if x > right:
		x = anchor.x - INSPECTOR_GAP - panel.x
	# maxf у верхній межі: на вузькому екрані панель може не влізти між полями
	# взагалі, і тоді clampf із min > max віддав би саме max — тобто виштовхнув
	# би її за протилежний край. Хай радше стирчить із безпечного кута.
	_inspector.position = Vector2(
		clampf(x, left, maxf(left, right)),
		clampf(anchor.y - panel.y * 0.5, top, maxf(top, bottom)))


## Верх рядка кнопок у координатах самого HUD. Через глобальний прямокутник, а
## не через position: BottomBar лежить на два контейнери вглиб, і його position
## відлічується від Layout, а не звідси. Поки розкладка ще не порахована (перший
## кадр, або тест одразу після add_child) прямокутник вироджений — тоді чесніше
## віддати нижнє поле безпеки, ніж нуль, який притиснув би панель до стелі.
func _bottom_bar_top() -> float:
	var bar: Rect2 = _bottom_bar.get_global_rect()
	if bar.size.y <= 0.0:
		return size.y - float(_safe_area.get_theme_constant("margin_bottom"))
	return bar.position.y - get_global_rect().position.y


func _clear_preview() -> void:
	_preview_shot_box.visible = false
	_preview_move_box.visible = false
	_confirm_button.disabled = true
	_inspector.highlight_sector(UnitInspector.NO_SECTOR)


func _on_confirm_pressed() -> void:
	if _controller == null:
		return
	_controller.confirm_pending()
	_clear_preview()
	# Дія щойно змінила позицію й AP того самого юніта — панель мусить
	# показувати нинішнє, а не те, що було до натискання.
	_render_selection()


func _on_cancel_pressed() -> void:
	if _controller != null:
		_controller.cancel_pending()
	_clear_preview()


func _on_end_turn_pressed() -> void:
	end_turn_pressed.emit()
