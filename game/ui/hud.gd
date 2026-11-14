class_name Hud
extends Control
## Постійна панель бою «Field Tablet». §1.5 — кожне правило, що впливає на кидок, видиме числом
## чи значком; §3.4 — сектор, у який піде постріл, показується ДО підтвердження.
##
## HUD нічого не рахує. Сектор, межі шкоди, «броня не діє» й «укриття ½» приходять готовими у
## прев'ю від InputController (його дані — з core/) і показуються без округлення чи власного
## «приблизно». Єдиний шлях до дії — «Підтвердити» → InputController.confirm_pending(). Жоден
## вузол цього файлу не створює Command і не торкається MatchService.submit().
##
## Розкладка. Чип гравця, пауза й «Завершити хід» — по кутах. Усе, що з'являється на дошці
## (кластер прев'ю + ряд дій, плита верб, смужка озброєння), стає за правилом стикування
## (HudDocking) з реальних екранних прямокутників видимих UnitView: HUD не закриває жодного
## юніта, що видно гравцеві. Перерахунок — на подію (прев'ю, вибір, режим, рух камери, нові
## юніти), а не щокадру (§8).
##
## Тег вибраного юніта (UnitTag + TagPlacement) і картка утримання (HoldCard) стають від тих самих
## екранних прямокутників; тег перераховується на вибір, рух камери й пакет подій, а не щокадру.
## Стану ґрунту інтерфейс не показує ніде: зони руху вже його враховують.

## Натиснуто «завершити хід». Саме рішення — не тут: подавати EndTurnCommand самому означало б
## завести другий шлях до core/ повз контролер. Сцена бою вирішує, що з цим робити (зокрема —
## гейт передачі пристрою, §3.5).
signal end_turn_pressed
## Пауза — оверлей сцени бою; HUD лише просить її відкрити.
signal pause_pressed
## Вибір змінився (unit != null — тег показано). own — вибрано свій юніт активного гравця.
## AP не показуємо ніде, ні свій, ні чужий. Лічильник дронів публічний (§3.9) і показується й для чужого.
signal selection_tag_changed(unit: Unit, own: bool)

const TOAST_SECONDS: float = 2.0
## Захист від другого тапу по плиті верб, що не змогла стати поза клітинками дошки.
const ENGINEER_TAP_GUARD_MS: int = 300
## Скільки камера мусить стояти, щоб розкладка стала наново.
const VIEW_SETTLE_SECONDS: float = 0.12
const TOAST_FADE: float = 0.15
const _EDGE: float = 24.0
const _BOTTOM: float = 12.0
const _TOAST_GAP: float = 8.0
const _VERB_ICONS: Dictionary = {
	EngineerCommand.Action.LAY_MINE: preload("res://assets/ui/icons/mine_lay.svg"),
	EngineerCommand.Action.CLEAR_MINE: preload("res://assets/ui/icons/mine_clear.svg"),
	EngineerCommand.Action.REPAIR_BRIDGE: preload("res://assets/ui/icons/bridge_repair.svg"),
	EngineerCommand.Action.DEMOLISH_BRIDGE: preload("res://assets/ui/icons/bridge_demolish.svg"),
	EngineerCommand.Action.REPAIR_UNIT: preload("res://assets/ui/icons/repair_unit.svg"),
}
const _ICON_DRONE: Texture2D = preload("res://assets/ui/icons/drone.svg")
const _ICON_FIRE: Texture2D = preload("res://assets/ui/icons/fire.svg")
const _ICON_MOVE: Texture2D = preload("res://assets/ui/icons/move.svg")
## Значки основної кнопки мають різний вміст у полі 24×24, тож їхній бокс підібрано так, щоб чорнило було
## в усіх близько 14–15 dp. Для довгих підписів проміжок між значком і словом тісніший.
const _CONFIRM_ICON_PX: Dictionary = {
	"hud_fire": 24.0, "hud_move": 26.0, "hud_repair": 22.0, "eng_clear_mine": 19.0,
	"eng_repair_bridge": 17.0, "eng_demolish_bridge": 17.0, "hud_strike": 16.5,
}
const _CONFIRM_GAP_TIGHT: Array[String] = ["eng_repair_bridge", "eng_demolish_bridge"]
const _ICON_CONFIRM: Texture2D = preload("res://assets/ui/icons/confirm.svg")

var _state: BattleState = null
var _controller: InputController = null
var _camera_rig: IsoCameraRig = null
var _selected_unit: Unit = null
## −1 — «гравця ще не показували жодного разу». Потрібне окремим значенням, бо 0 — це справжній
## гравець, а перехід до нового гравця мусить прибрати з екрана вибір попереднього.
var _shown_player: int = -1
var _last_preview: Dictionary = {}
## Тайли-цілі озброєної верби й id юнітів, яких може позначити озброєний дрон: ними смужка
## озброєння обходить цілі, які гравцеві ще треба тапнути.
var _armed_tiles: Array[Vector2i] = []
var _drone_mark_ids: Array[int] = []
## Callable() -> Dictionary {id юніта -> UnitView}: лише юніти, що є на екрані активного гравця.
var _unit_views: Callable = Callable()
var _toast_key: String = ""
var _toast_tween: Tween = null
## Тег: де стояв щодо юніта (зсув від лівого верхнього кута його коробки) — гістерезис: тримається,
## поки законний, тож тег їде за юнітом при русі камери й не стрибає при кожному перерахунку.
var _tag: UnitTag = null
var _card: HoldCard = null
var _tag_offset: Vector2 = Vector2.ZERO
var _tag_has_offset: bool = false
var _tag_relax: int = 0
## Свіжий пошук замість збереженого місця дозволений лише на виборі й спокої камери, не на зміні режиму
## (дрон, верба): інакше озброєння зсувало б тег убік.
var _tag_resettle: bool = false
var _tag_unit_id: int = -1
var _tag_queued: bool = false
var _tag_unit_pos: Vector2 = Vector2.ZERO
var _settle_timer: Timer = null
# Під час програвання подій юніт іде, а тег стояв би на старій клітинці.
var _tag_held: bool = false
## Кільце армованого дрона й огляд довгого натиску: дуги кілець — «позначки дошки» для тега.
var _drone_ring: Dictionary = {}
var _hold: Dictionary = {}
var _press_point: Vector2 = Vector2.ZERO
var _covered: Array[Control] = []
## Назва останнього обраного варіанта кластера — для тестів і діагностики.
var _cluster_name: String = ""

@onready var _chip: PanelContainer = %Chip
@onready var _player_bar: ColorRect = %PlayerBar
@onready var _turn_value: Label = %TurnValue
@onready var _player_value: Label = %PlayerValue
@onready var _plate: PreviewPlate = %PreviewPlate
@onready var _row: HBoxContainer = %ActionRow
@onready var _confirm_button: Button = %ConfirmButton
@onready var _cancel_button: Button = %CancelButton
@onready var _end_turn_button: Button = %EndTurnButton
@onready var _pause_button: Button = %PauseButton
@onready var _engineer_panel: EngineerPanel = %EngineerPanel
@onready var _drone_button: DroneButton = %DroneButton
@onready var _drone_strip: ArmedStrip = %DroneStrip
@onready var _toast: PanelContainer = %Toast
@onready var _toast_label: Label = %ToastLabel


func _ready() -> void:
	HudKit.group_content(_confirm_button, 20.0)
	_confirm_button.pressed.connect(_on_confirm_pressed)
	_cancel_button.pressed.connect(_on_cancel_pressed)
	_end_turn_button.pressed.connect(_on_end_turn_pressed)
	_pause_button.pressed.connect(pause_pressed.emit)
	_drone_strip.cancel_pressed.connect(_on_cancel_pressed)
	# Висота плити залежить від переносу рядків, який відомий лише після розкладки по ширині.
	_plate.minimum_size_changed.connect(_relayout)
	_engineer_panel.cancel_pressed.connect(_on_cancel_pressed)
	_engineer_panel.refused.connect(show_toast)
	_toast.custom_minimum_size.y = 34.0
	_square_pause_button()
	# Плита 9-slice малюється фільтром кнопки: NEAREST лишає край у 1 dp чітким, а значок і підпис живуть
	# у LINEAR-дітях групи, інакше стрілка значка сходинкується.
	HudKit.group_content(_end_turn_button, 20.0)
	HudKit.group_content(_pause_button, 22.0)
	HudKit.group_content(_cancel_button, 20.0)
	for b: Button in [_end_turn_button, _pause_button, _cancel_button]:
		b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_tag = UnitTag.new()
	add_child(_tag)
	_card = HoldCard.new()
	add_child(_card)
	# Підпис «щонайменше» живе в картці, але тести й сцена читають його за %ThreatFloorLabel.
	_card.floor_label.owner = self
	_card.floor_label.unique_name_in_owner = true
	resized.connect(_relayout)
	_clear_preview()
	_render_selection()


## Кнопка паузи — квадрат 48 × 48 лише зі значком: поля кнопки з теми (13 + 16) зробили б її шириною 51.
func _square_pause_button() -> void:
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		var box: StyleBox = _pause_button.get_theme_stylebox(state, "HudPlateButton")
		if box == null:
			continue
		box = box.duplicate()
		box.content_margin_left = 13.0
		box.content_margin_right = 13.0
		_pause_button.add_theme_stylebox_override(state, box)


## Підписи, зібрані через tr() у коді (гравець, сектор, тост), не перекладаються самі.
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		refresh()
		if not _last_preview.is_empty():
			show_preview(_last_preview)
		_retitle_drone_strip()
		if _toast_key != "":
			_toast_label.text = tr(_toast_key)


## Стан матчу для постійної частини панелі. Тримається посиланням, а не копією: BattleState
## змінюється на місці, і refresh() мусить читати нинішні числа, а не знімок.
func bind(state: BattleState) -> void:
	_state = state
	refresh()


## Перечитує все, що показується постійно. Викликається і ззовні, і з events_ready: після кожної
## застосованої команди AP вибраного юніта інший, а контролер про це не сигналить.
func refresh() -> void:
	if _state == null:
		return
	_turn_value.text = str(_state.turn_number)
	set_active_player(_state.active_player)
	# Матч завершився — core/ відхиляє EndTurnCommand разом з усіма іншими (ERR_MATCH_OVER),
	# тож кнопка не сміє пропонувати дію, яку правила вже не приймають.
	_end_turn_button.disabled = _state.is_over()
	_render_selection()


func set_active_player(player: int) -> void:
	if player != _shown_player:
		_shown_player = player
		# §1.2: приховане знання священне. Вибір і прев'ю попереднього гравця — це його AP,
		# його броня й його намір; пережити передачу ходу вони не мусять навіть на кадр.
		show_selection(null)
	# Колір гравця — з тієї самої таблиці, що фарбує корпуси юнітів.
	_player_bar.color = UnitView.PLAYER_COLORS[player % UnitView.PLAYER_COLORS.size()]
	_player_value.text = "%s %d" % [tr("hud_player"), player + 1]


## Вибраний юніт (null — вибору немає). Дії й AP — лише для СВОГО юніта активного гравця.
## Ворожий юніт сюди теж може прийти, але тег покаже тільки публічне: залишок дронів (§3.9).
func show_selection(unit: Unit) -> void:
	_selected_unit = unit
	# Відмова іншого юніта не мусить висіти над прев'ю нової дії.
	_hide_toast()
	# Новий вибір скидає pending у контролері, тож прев'ю на екрані стосувалося б дії, якої вже нема.
	_clear_preview()
	_render_selection()


## Словник приходить від InputController і має форму за "type" (InputController.ActionType):
## MOVE {unit_id, target, path, ap_left}, SHOT {unit_id, target_id, sector, min, max, armour_ignored,
## in_cover}, ENGINEER {unit_id, action, target[, heal_min, heal_max]}, DRONE {unit_id, target_id, min, max}.
func show_preview(preview: Dictionary) -> void:
	# Спершу гасимо все: без цього поля попереднього прев'ю лишилися б на екрані й читалися
	# б як частина нової дії.
	_clear_preview()
	_last_preview = preview
	if preview.is_empty():
		return
	_hide_toast()
	_retitle_confirm(preview)
	match int(preview["type"]):
		InputController.ActionType.MOVE:
			# Рух без плити: зони руху вже показують, куди можна дійти, а AP не пишемо ніде.
			# Плити нема, тож і чекати її запікання перед «Підтвердити» нема чого.
			_confirm_button.disabled = false
			_sync_modes()
			return
		InputController.ActionType.ENGINEER:
			_show_engineer_preview(preview)
			if int(preview["action"]) != EngineerCommand.Action.REPAIR_UNIT:
				_confirm_button.disabled = false
				_sync_modes()
				return
		InputController.ActionType.DRONE:
			# Броня ігнорується (§3.9) — сектора немає, лише межі з Rules.drone_damage_bounds().
			_show_target_row(_unit(int(preview["target_id"])))
			_plate.show_drone("%d–%d" % [int(preview["min"]), int(preview["max"])])
		InputController.ActionType.SHOT:
			_show_shot_preview(preview)
		_:
			return
	# Підтвердження живе лише поки плита показує те, що підтверджується (сектор до кроку, §3.4): поки вона
	# запікається, тло порожнє.
	_confirm_button.disabled = not _plate.is_baked()
	if _confirm_button.disabled and not _plate.baked.is_connected(_enable_confirm):
		_plate.baked.connect(_enable_confirm, CONNECT_ONE_SHOT)
	_sync_modes()


func _enable_confirm() -> void:
	_confirm_button.disabled = _last_preview.is_empty()


func _show_shot_preview(preview: Dictionary) -> void:
	var target: Unit = _unit(int(preview["target_id"]))
	_show_target_row(target)
	var sector: int = int(preview["sector"])
	# Піхота без броні: замість корпуса — силует (глиф без броні не має що підсвічувати). Клас —
	# лише вибір значка; «броня не діє» та «укриття ½» читаються з полів core-прев'ю.
	var infantry: bool = target != null and target.unit_class() == UnitTypes.UnitClass.INFANTRY
	var turret: bool = target != null and target.unit_class() == UnitTypes.UnitClass.TANK
	# Обидві межі як є — гравець мусить бачити розкид, а не одне «приблизно стільки» (§3.3, §1.5).
	_plate.show_shot(sector, tr(HudKit.SECTOR_KEYS[sector]), "%d–%d" % [int(preview["min"]), int(preview["max"])],
		infantry, turret, bool(preview.get("armour_ignored", false)), bool(preview.get("in_cover", false)))


## Основна кнопка називає дію, що чекає підтвердження: слово й значок слідують за прев'ю.
func _retitle_confirm(preview: Dictionary) -> void:
	var key: String = "hud_confirm"
	var tex: Texture2D = _ICON_CONFIRM
	match int(preview["type"]):
		InputController.ActionType.MOVE:
			key = "hud_move"
			tex = _ICON_MOVE
		InputController.ActionType.SHOT:
			key = "hud_fire"
			tex = _ICON_FIRE
		InputController.ActionType.DRONE:
			key = "hud_strike"
			tex = _ICON_DRONE
		InputController.ActionType.ENGINEER:
			var action: int = int(preview["action"])
			key = "hud_repair" if action == EngineerCommand.Action.REPAIR_UNIT else EngineerPanel.LABEL_KEYS[action]
			tex = _VERB_ICONS[action]
	HudKit.retitle_group(_confirm_button, tr(key), tex, float(_CONFIRM_ICON_PX.get(key, 20.0)),
		6 if key in _CONFIRM_GAP_TIGHT else 8)


func _show_engineer_preview(preview: Dictionary) -> void:
	var action: int = int(preview["action"])
	if action == EngineerCommand.Action.REPAIR_UNIT:
		var patient: Unit = _state.unit_at(preview["target"]) if _state != null else null
		_show_target_row(patient)
		var hp: int = patient.hp if patient != null else 0
		var max_hp: int = int(patient.type()["max_hp"]) if patient != null else 0
		_plate.show_repair(hp, max_hp, "%d–%d" % [int(preview["heal_min"]), int(preview["heal_max"])])
	# Решта верб без чисел: їхнє слово вже стоїть на основній кнопці, плита його б лише повторила.


func _show_target_row(target: Unit) -> void:
	var color: Color = Color("8f918a")
	var label: String = ""
	if target != null:
		color = UnitView.PLAYER_COLORS[target.owner % UnitView.PLAYER_COLORS.size()]
		label = tr(String(target.type()["name_key"]))
	_plate.show_target(label, color)


## Явна прив'язка замість пошуку вузла шляхом (§9). Контролер лишається власником наміру: HUD
## слухає його сигнали й кличе його ж confirm/cancel.
func attach_controller(controller: InputController) -> void:
	_controller = controller
	controller.selection_changed.connect(show_selection)
	controller.action_preview.connect(show_preview)
	# Контролер скинув pending (озброєння верби, новий вибір) — прев'ю й Confirm не мають
	# пережити дію, якої вже нема.
	controller.pending_cleared.connect(_clear_preview)
	_engineer_panel.action_chosen.connect(controller.arm_engineer)
	_drone_button.pressed.connect(controller.arm_drone)
	controller.targets_changed.connect(_on_targets_changed)
	controller.drone_armed.connect(_on_drone_armed)
	# Відмова з причиною — тост біля слота, де гравець щойно тапнув (§1.5: «чому ні»).
	controller.action_refused.connect(show_toast)
	# §3.13: огляд ворога — позначки лише нижня межа, і UI мусить сказати це вголос.
	controller.inspected.connect(_on_inspected)
	_sync_modes()


## Явна прив'язка камери (§9). Плити стають від екранних прямокутників юнітів, тож їдуть разом
## із дошкою: підписка на view_changed, а не опитування рига щокадру (§8).
func attach_camera(rig: IsoCameraRig) -> void:
	_camera_rig = rig
	rig.view_changed.connect(_on_view_changed)
	_relayout()


## Звідки брати видимі UnitView: Callable без аргументів → {id юніта: UnitView}. Лише юніти, які
## гравець бачить (фог, §3.5): стикування, що обходило б невидимого ворога, показало б, де він.
func attach_unit_views(provider: Callable) -> void:
	_unit_views = provider
	_relayout()


## Рух камери: поки дошка їде, тег лише зсувається разом з юнітом; розкладка й стикування —
## раз, коли рух стих (інакше кожен крок інерції будував би растр перешкод).
func _on_view_changed() -> void:
	var view: UnitView = _tag_view()
	if _tag.visible and _tag_has_offset and view != null:
		var pos: Vector2 = UnitScreenBox.of(view, _camera_rig).position
		_tag.position += (pos - _tag_unit_pos).round()
		_tag_unit_pos = pos
	if _settle_timer == null:
		_settle_timer = Timer.new()
		_settle_timer.one_shot = true
		_settle_timer.wait_time = VIEW_SETTLE_SECONDS
		_settle_timer.timeout.connect(_on_view_settled)
		add_child(_settle_timer)
	_settle_timer.start()


func _on_view_settled() -> void:
	_tag_resettle = true
	_relayout()


## Сцена бою вмикає на час програвання пакета подій і знімає після: тег стоїть лише при юніті,
## що вже дійшов, а units_changed() ставить його наново.
func hold_tag(on: bool) -> void:
	_tag_held = on
	if on:
		_tag.visible = false


## Юніти перебудовано (після пакета подій чи передачі ходу) — плити мусять стати наново.
func units_changed() -> void:
	_relayout()
	_request_tag()


## MatchService навмисно без class_name, тож тип тут Node, а виклик динамічний. Слухається лише
## events_ready; take_events() тут не викликається НІКОЛИ — черга належить EventPlayer.
func attach_match_service(service: Node) -> void:
	service.events_ready.connect(refresh)


# --- Тост -------------------------------------------------------------------

## Відмова правил: текст за ключем ERR_*, 2,0 с, зникає за 150 мс одним твіном.
func show_toast(key: String) -> void:
	if key == "":
		return
	_toast_key = key
	_toast_label.text = tr(key)
	_toast.modulate.a = 1.0
	_toast.visible = true
	_place_toast()
	if _toast_tween != null:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(TOAST_SECONDS - TOAST_FADE)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, TOAST_FADE)
	_toast_tween.tween_callback(_hide_toast)


## Для тестів: крок твіна вручну, без очікування в реальному часі.
func toast_tween() -> Tween:
	return _toast_tween


func _hide_toast() -> void:
	if _toast_tween != null:
		_toast_tween.kill()
	_toast.visible = false
	_toast_key = ""


## Праворуч, на 8 dp над тим, що займає слот унизу праворуч: кнопка, смужка, плита верб чи ряд
## дій. Нічого там нема — тост бере сам слот.
func _place_toast() -> void:
	_toast.size = _toast.get_combined_minimum_size()
	var bottom: float = size.y - _BOTTOM
	var top: float = _bottom_right_occupant_top()
	if top < bottom:
		bottom = top - _TOAST_GAP
	_toast.position = Vector2(size.x - _EDGE - _toast.size.x, bottom - _toast.size.y)


func _bottom_right_occupant_top() -> float:
	var top: float = size.y
	var corner := Vector2(size.x - _EDGE, size.y - _BOTTOM)
	var slot: Array[Control] = [_drone_button, _drone_strip, _row]
	if _engineer_panel.visible:
		slot.append(_engineer_panel.strip() if _engineer_panel.strip().visible else _engineer_panel.plate())
	for c in slot:
		var r: Rect2 = _local_rect(c)
		if c.visible and absf(r.end.x - corner.x) < 1.0 and r.end.y >= corner.y - 1.0:
			top = minf(top, r.position.y)
	# Плита прев'ю над рядом (варіант a) теж займає слот: тост стає над нею.
	if _plate.visible and _row.visible:
		var p: Rect2 = _local_rect(_plate)
		if absf(p.end.y + HudDocking.GAP - _row.position.y) < 1.0 and top == _row.position.y:
			top = p.position.y
	return top


func _local_rect(c: Control) -> Rect2:
	return Rect2(c.global_position - global_position, c.size)


## Назва варіанта стикування кластера (a, a4, b, c, d) — для тестів і діагностики.
func cluster_name() -> String:
	return _cluster_name


# --- Режими й розкладка -------------------------------------------------------

func _on_targets_changed(tiles: Array[Vector2i]) -> void:
	_armed_tiles = tiles
	if tiles.is_empty():
		_drone_mark_ids = []
		_drone_ring = {}
	_sync_modes()


func _on_drone_armed(center: Vector2i, radius: int, marks: Dictionary) -> void:
	_drone_ring = {"center": center, "radius": radius}
	_drone_mark_ids = []
	for id: Variant in marks:
		_drone_mark_ids.append(int(id))
	_sync_modes()


## Що є на екрані зараз: ряд дій + плита — коли є прев'ю; смужка озброєння — коли озброєно й
## цілі ще нема; кнопка «Дрон» чи плита верб — коли нічого не озброєно. Рівно одне «Скасувати».
func _sync_modes() -> void:
	if not is_node_ready():
		return
	var pending: bool = not _last_preview.is_empty() or (_controller != null and _controller.has_cancelable())
	var waiting: bool = _controller != null and _controller.is_armed_waiting()
	var own: bool = _own_selected()
	var engineer: bool = own and _selected_unit.unit_class() == UnitTypes.UnitClass.ENGINEER
	_row.visible = pending
	_plate.visible = pending and _last_preview.size() > 0 and _plate_has_content(_last_preview)
	_cancel_button.visible = pending
	_engineer_panel.visible = engineer and not pending
	if _engineer_panel.visible:
		_engineer_panel.set_armed(waiting)
	_drone_strip.visible = waiting and own and not engineer
	_drone_button.visible = own and not engineer and _drone_button_applicable() and not pending and not waiting
	if _drone_strip.visible:
		_retitle_drone_strip()
	_relayout()


## Плита потрібна там, де є числа: рух і верби без чисел її не мають.
func _plate_has_content(preview: Dictionary) -> bool:
	match int(preview["type"]):
		InputController.ActionType.MOVE:
			return false
		InputController.ActionType.ENGINEER:
			return int(preview["action"]) == EngineerCommand.Action.REPAIR_UNIT
	return true


func _drone_button_applicable() -> bool:
	return _selected_unit != null and int(_selected_unit.type()["drones"]) > 0


func _own_selected() -> bool:
	return _selected_unit != null and _state != null and _selected_unit.owner == _state.active_player


func _retitle_drone_strip() -> void:
	if _selected_unit == null:
		return
	_drone_strip.configure(_ICON_DRONE, tr("hud_drone_strike"), tr("drone_hint_tap_target"),
		Vector2i(_selected_unit.drones_left, int(_selected_unit.type()["drones"])))


func _unit_boxes() -> Array[Rect2]:
	var out: Array[Rect2] = []
	if _camera_rig == null or not _unit_views.is_valid():
		return out
	var views: Dictionary = _unit_views.call()
	for id: Variant in views:
		var view := views[id] as UnitView
		if view == null or not is_instance_valid(view):
			continue
		var r: Rect2 = UnitScreenBox.of(view, _camera_rig)
		if r.size != Vector2.ZERO:
			out.append(r)
	return out


## Цілі прев'ю, які плита не має закривати: ціль пострілу/дрона/ремонту з прицілом; для руху —
## клітинка призначення й шлях; для верби-тайла — клітинка цілі.
func _preview_targets() -> Array[Rect2]:
	var out: Array[Rect2] = []
	if _camera_rig == null or _last_preview.is_empty():
		return out
	match int(_last_preview["type"]):
		InputController.ActionType.SHOT, InputController.ActionType.DRONE:
			out.append_array(_view_boxes([int(_last_preview["target_id"])], true))
		InputController.ActionType.ENGINEER:
			out.append(UnitScreenBox.cell_rect(_last_preview["target"], _camera_rig))
		InputController.ActionType.MOVE:
			for cell: Vector2i in _last_preview["path"]:
				out.append(UnitScreenBox.cell_rect(cell, _camera_rig))
			out.append(UnitScreenBox.cell_rect(_last_preview["target"], _camera_rig))
	return out


func _view_boxes(ids: Array, with_crosshair: bool) -> Array[Rect2]:
	var out: Array[Rect2] = []
	if not _unit_views.is_valid():
		return out
	var views: Dictionary = _unit_views.call()
	for id: Variant in ids:
		var view := views.get(id, null) as UnitView
		if view != null and is_instance_valid(view):
			out.append(UnitScreenBox.with_crosshair(view, _camera_rig) if with_crosshair else UnitScreenBox.of(view, _camera_rig))
	return out


## Місця всього, що стає за правилом стикування. Викликається на події, не щокадру.
func _relayout() -> void:
	if not is_node_ready():
		return
	# Фіксовані місця: кнопка «Дрон» стоїть у слоті внизу праворуч.
	_drone_button.position = Vector2(size.x - _EDGE - DroneButton.WIDTH, size.y - _BOTTOM - 48.0)
	_drone_button.size = Vector2(DroneButton.WIDTH, 48.0)
	if _row.visible:
		_dock_cluster()
	if _engineer_panel.visible:
		_dock_engineer()
	if _drone_strip.visible:
		_dock_drone_strip()
	if _toast.visible:
		_place_toast()
	_request_tag()


func _dock_cluster() -> void:
	var plate_h: float = _plate.get_combined_minimum_size().y if _plate.visible else 0.0
	var pick: Dictionary = HudDocking.choose_cluster(size, plate_h, _unit_boxes(), _preview_targets())
	_cluster_name = pick["name"]
	var rects: Array[Rect2] = pick["rects"]
	_plate.position = rects[0].position
	_plate.size = Vector2(HudDocking.CLUSTER_W, plate_h)
	_row.position = rects[1].position
	_row.size = rects[1].size


func _dock_engineer() -> void:
	var part: Vector2 = _engineer_panel.active_size()
	var pick: Dictionary
	if _engineer_panel.strip().visible:
		pick = HudDocking.choose_strip(size, part, _unit_boxes(), _armed_target_boxes())
	else:
		pick = HudDocking.choose_verb_plate(size, part, _unit_boxes(), _neighbour_boxes())
		if _controller != null:
			_controller.tap_guard_ms = 0 if pick["clear"] else ENGINEER_TAP_GUARD_MS
	var rects: Array[Rect2] = pick["rects"]
	_engineer_panel.position = rects[0].position
	_engineer_panel.size = part


func _dock_drone_strip() -> void:
	var strip_size: Vector2 = _drone_strip.get_combined_minimum_size()
	var pick: Dictionary = HudDocking.choose_strip(size, strip_size, _unit_boxes(), _view_boxes(_drone_mark_ids, true))
	var rects: Array[Rect2] = pick["rects"]
	_drone_strip.position = rects[0].position
	_drone_strip.size = strip_size


func _armed_target_boxes() -> Array[Rect2]:
	var out: Array[Rect2] = []
	if _camera_rig == null:
		return out
	for cell in _armed_tiles:
		out.append(UnitScreenBox.cell_rect(cell, _camera_rig))
	return out


## Сам інженер і чотири сусідні клітинки: саме там верби працюють, плита їх не закриває.
func _neighbour_boxes() -> Array[Rect2]:
	var out: Array[Rect2] = []
	if _camera_rig == null or _selected_unit == null:
		return out
	for d: Vector2i in [Vector2i.ZERO, Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		out.append(UnitScreenBox.cell_rect(_selected_unit.pos + d, _camera_rig))
	return out


# --- Решта --------------------------------------------------------------------

func _render_selection() -> void:
	# Юніт міг загинути від відповіді (§3.3.1) між вибором і перемальовуванням.
	if _selected_unit != null and not _selected_unit.is_alive():
		_selected_unit = null
	var own: bool = _own_selected()
	# Панель верб — лише своєму інженерові активного гравця: чужі верби не дія, а їхня
	# доступність була б підказкою про чужий стан.
	if own and _selected_unit.unit_class() == UnitTypes.UnitClass.ENGINEER:
		_engineer_panel.show_for(_state, _selected_unit)
	# Дрон — дія, тож лише свій загін активного гравця.
	_drone_button.show_for(_selected_unit if own else null)
	_sync_modes()
	selection_tag_changed.emit(_selected_unit, own)
	_request_tag()


func _clear_preview() -> void:
	_last_preview = {}
	_plate.clear()
	_confirm_button.disabled = true
	if is_node_ready():
		_sync_modes()


func _on_confirm_pressed() -> void:
	if _controller == null:
		return
	_controller.confirm_pending()
	_clear_preview()
	# Дія щойно змінила позицію й AP того самого юніта — HUD мусить показувати нинішнє.
	_render_selection()


func _on_cancel_pressed() -> void:
	_hide_toast()
	if _controller != null:
		_controller.cancel_pending()
	_clear_preview()


func _on_end_turn_pressed() -> void:
	end_turn_pressed.emit()


func _unit(id: int) -> Unit:
	return _state.get_unit(id) if _state != null else null


# --- Тег вибраного юніта ---------------------------------------------------------

func unit_tag() -> UnitTag:
	return _tag


func hold_card() -> HoldCard:
	return _card


## Перерахунок тега — раз на кадр, відкладено: вибір, режими й рух камери часто приходять пачкою.
func _request_tag() -> void:
	if _tag_queued or not is_node_ready():
		return
	_tag_queued = true
	if _selected_unit == null:
		_update_tag.call_deferred()
		return
	# Контейнери стискаються наприкінці кадру: тег читає розміри плит уже після цього, інакше висота
	# щойно показаної плити ще при вузькій ширині виганяла б його з законного місця.
	get_tree().process_frame.connect(_update_tag, CONNECT_ONE_SHOT)


func _update_tag() -> void:
	_tag_queued = false
	var view: UnitView = _tag_view()
	if view == null or _tag_held:
		_tag.visible = false
		_tag_has_offset = false
		_tag_unit_id = -1
		return
	if _selected_unit.id != _tag_unit_id:
		_tag_unit_id = _selected_unit.id
		_tag_has_offset = false
	_tag.show_unit(_selected_unit, _own_selected())
	var tag_size: Vector2 = _tag.get_combined_minimum_size().ceil()
	var scene: Dictionary = _tag_scene(view, tag_size)
	var placement := TagPlacement.new(scene)
	var unit_box: Rect2 = scene["unit"]
	_tag_unit_pos = unit_box.position
	var rect := Rect2()
	var resettle: bool = _tag_resettle or not _tag_has_offset
	_tag_resettle = false
	if _tag_has_offset:
		var kept := Rect2(unit_box.position + _tag_offset, tag_size)
		if placement.is_legal(kept, _tag_relax):
			rect = kept
			# Місце, збережене лише з послабленням правил, не тримається, коли суворіше знайшлося: перший
			# розрахунок міг іти до розкладки дошки, і тег лишався б накриваючи клітинки.
			if _tag_relax > 0:
				var strict: Dictionary = placement.best()
				if strict["found"] and placement.relax_used < _tag_relax:
					rect = strict["rect"]
					_tag_relax = placement.relax_used
			# Камера могла доїжджати, коли місце вибирали: збережене, що накриває контури, коли свіжий пошук
			# знаходить менш накрите, не тримається. Лише на спокої камери, не на зміні режиму.
			elif resettle and placement.mark_cover(kept) > 0.0:
				var fresh: Dictionary = placement.best()
				if fresh["found"] and placement.mark_cover(fresh["rect"]) < placement.mark_cover(kept):
					rect = fresh["rect"]
					_tag_relax = placement.relax_used
	if rect.size == Vector2.ZERO:
		var pick: Dictionary = placement.best()
		if not pick["found"]:
			# Місця немає: тег ховається, а не лягає на юніта чи плиту.
			_tag.visible = false
			_tag_has_offset = false
			return
		rect = pick["rect"]
		_tag_relax = placement.relax_used
	_tag_offset = rect.position - unit_box.position
	_tag_has_offset = true
	_tag.position = rect.position.round()
	_tag.size = rect.size
	if placement.needs_leader(rect):
		var ends: PackedVector2Array = placement.leader_points(rect)
		_tag.set_leader(ends[0], ends[1])
	else:
		_tag.clear_leader()
	# Поки картка утримання на екрані, тег не показується зовсім (на дошці лишаються лише контури й кільця).
	_tag.visible = not _card.visible


func _tag_view() -> UnitView:
	if _selected_unit == null or not _selected_unit.is_alive() or _camera_rig == null or not _unit_views.is_valid():
		return null
	return (_unit_views.call() as Dictionary).get(_selected_unit.id, null) as UnitView


## Усе, що тег обходить, з реальних екранних даних видимих UnitView. Невидимий ворог тут не
## з'являється ніде: стоїть лише те, що має вузол (§3.5).
func _tag_scene(view: UnitView, tag_size: Vector2) -> Dictionary:
	var others: Array[Rect2] = []
	var views: Dictionary = _unit_views.call()
	for id: Variant in views:
		var other := views[id] as UnitView
		if other == null or not is_instance_valid(other) or int(id) == _selected_unit.id:
			continue
		var r: Rect2 = UnitScreenBox.with_marks(other, _camera_rig)
		if r.size != Vector2.ZERO:
			others.append(r)
	var unit_box: Rect2 = UnitScreenBox.of(view, _camera_rig)
	var chrome: Array[Rect2] = []
	var parts: Array[Control] = [_chip, _pause_button, _end_turn_button, _plate, _row, _drone_button, _drone_strip]
	if _engineer_panel.visible:
		parts.append(_engineer_panel.strip() if _engineer_panel.strip().visible else _engineer_panel.plate())
	for c in parts:
		if c.is_visible_in_tree():
			var cr: Rect2 = _local_rect(c)
			# Плита щойно показана ще не стиснута до свого розміру: застарілий розмір вигнав би тег зі свого місця.
			if c == _plate:
				cr.size.y = minf(cr.size.y, c.get_combined_minimum_size().y)
			chrome.append(cr)
	var polys: Array[PackedVector2Array] = []
	if _own_selected() and _selected_unit.unit_class() == UnitTypes.UnitClass.ENGINEER:
		# Клітинки, на які діють верби, — перешкода від вибору, тож озброєння верби тег не зрушує.
		for d: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			polys.append(UnitScreenBox.cell_poly(_selected_unit.pos + d, _camera_rig))
	var fire := PackedVector2Array()
	if not _last_preview.is_empty():
		match int(_last_preview["type"]):
			InputController.ActionType.MOVE:
				for cell: Vector2i in _last_preview["path"]:
					polys.append(UnitScreenBox.cell_poly(cell, _camera_rig))
				polys.append(UnitScreenBox.cell_poly(_last_preview["target"], _camera_rig))
			InputController.ActionType.SHOT, InputController.ActionType.DRONE:
				var target := views.get(int(_last_preview["target_id"]), null) as UnitView
				if target != null:
					fire = PackedVector2Array([unit_box.get_center(), UnitScreenBox.of(target, _camera_rig).get_center()])
	var icon := Rect2()
	var icon_node := view.get_node_or_null("DroneIcon") as VisualInstance3D
	if icon_node != null and icon_node.visible:
		icon = UnitScreenBox.part_rect(icon_node, _camera_rig)
	return {
		"icon": icon,
		"tag_size": tag_size, "unit": unit_box, "core": UnitScreenBox.core(view, _camera_rig), "core_poly": UnitScreenBox.core_poly(view, _camera_rig),
		"label": UnitScreenBox.label_rect(view, _camera_rig),
		"others": others, "chrome": chrome, "polys": polys, "fire": fire, "marks": _board_marks(),
		"screen": Rect2(Vector2.ZERO, size),
	}


## Ламані контурів зон і дуг кілець на екрані. shortcut: контур береться з ребер зон (ZoneOverlay),
## а не з пікселів дошки, тож тінь від рельєфу чи перекриття дахом не враховується.
func _board_marks() -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	var zones: Pathing.Zones = _controller.zones() if _controller != null and _own_selected() else null
	if zones != null:
		for zone: Array[Vector2i] in [zones.move_only, zones.move_and_fire]:
			for e: Dictionary in ZoneOverlay._edges(zone, Color.WHITE):
				var c: Vector3 = IsoCameraRig.cell_to_world(e["cell"])
				var d: Vector2i = e["dir"]
				var mid: Vector3 = c + Vector3(d.x * 0.5, 0.0, d.y * 0.5)
				var along := Vector3(absf(d.y) * 0.5, 0.0, absf(d.x) * 0.5)
				out.append(PackedVector2Array([_camera_rig.unproject(mid - along), _camera_rig.unproject(mid + along)]))
	if not _drone_ring.is_empty():
		out.append(_ring(_drone_ring["center"], int(_drone_ring["radius"])))
	for key: String in ["radius", "drone_radius"]:
		if int(_hold.get(key, 0)) > 0:
			out.append(_ring(_hold["center"], int(_hold[key])))
	return out


func _ring(center: Vector2i, radius: int) -> PackedVector2Array:
	var c: Vector3 = IsoCameraRig.cell_to_world(center)
	var out := PackedVector2Array()
	for i in 49:
		var a: float = TAU * i / 48.0
		out.append(_camera_rig.unproject(c + Vector3(cos(a), 0.0, sin(a)) * radius))
	return out


# --- Картка утримання ----------------------------------------------------------------

## Точка натиску на екрані: картка обходить палець (spec §2).
func note_press(point: Vector2) -> void:
	_press_point = point


## Огляд довгого натиску від контролера: словник Targeting.inspection() + unit_id; {} — відпущено.
## Картка лише для юніта, на якого є UnitView, тобто якого гравець бачить (§3.5).
func _on_inspected(inspection: Dictionary) -> void:
	_hold = inspection
	_restore_covered()
	var unit: Unit = _unit(int(inspection.get("unit_id", -1))) if not inspection.is_empty() else null
	var views: Dictionary = _unit_views.call() if _unit_views.is_valid() else {}
	if unit == null or not views.has(unit.id) or _camera_rig == null:
		_card.hide_card()
		_request_tag()
		return
	_card.show_unit(unit, bool(inspection.get("is_floor", false)))
	var marks: Array[Rect2] = []
	for key: String in ["marked", "drone_marked"]:
		for id: Variant in inspection.get(key, []):
			var marked := views.get(int(id), null) as UnitView
			if marked != null:
				marks.append(UnitScreenBox.with_marks(marked, _camera_rig))
	var held: Rect2 = UnitScreenBox.with_marks(views[unit.id], _camera_rig)
	var arcs: Array[PackedVector2Array] = []
	for key: String in ["radius", "drone_radius"]:
		if int(inspection.get(key, 0)) > 0:
			arcs.append(_ring(inspection["center"], int(inspection[key])))
	var rect: Rect2 = HudDocking.choose_card(size, _card.get_combined_minimum_size(), held, marks, _press_point, arcs)
	_card.position = rect.position
	_card.size = rect.size
	# Поки палець униз, плита дій, що лежить під карткою, не потрібна: вона її закрила б.
	for c: Control in [_plate, _row, _engineer_panel, _drone_strip, _drone_button]:
		if c.is_visible_in_tree() and _local_rect(c).intersects(rect):
			c.modulate.a = 0.0
			# Прозорий Button усе ще ловить дотик; картка вводу не бере, тож інший палець по ній
			# дістався б до прихованого «Підтвердити».
			c.process_mode = Node.PROCESS_MODE_DISABLED
			_covered.append(c)
	_request_tag()


func _restore_covered() -> void:
	for c in _covered:
		c.modulate.a = 1.0
		c.process_mode = Node.PROCESS_MODE_INHERIT
	_covered.clear()
