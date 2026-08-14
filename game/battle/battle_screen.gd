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


## R1: два кроки старту рівно в цьому порядку — start_match() лише будує
## стан, populate() наповнює його юнітами й цілями, begin() праймить
## видимість УСІХ гравців і запускає перший хід
## (core/battle_state.gd:44-72, MatchService.begin()).
##
## match_service — null для звичайного показу (тоді береться автозавантажений
## синглтон MatchService), або власний інстанс для ізольованого тесту — той
## самий прийом, що вже усталений у tests/game/test_input_controller.gd і
## tests/game/test_hud.gd.
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
	_camera_rig.center_on(_first_unit_cell(_match_service.state.active_player))

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
func _unhandled_input(event: InputEvent) -> void:
	var screen_pos: Vector2
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
			return
		screen_pos = mb.position
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if not st.pressed:
			return
		screen_pos = st.position
	else:
		return
	_handle_tap_at_screen_position(screen_pos)
	get_viewport().set_input_as_handled()


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
