class_name InputController
extends RefCounted
## Task 2.7: тап → намір → Command. Модель — «два тапи на будь-яку дію,
## жодного випадкового ходу від дотику» (task-2.7-brief.md): перший тап лише
## показує (вибір юніта і зон, прев'ю руху чи пострілу), другий — підтверджує
## (R23). Єдина точка, де цей файл торкається core/ ДІЄЮ, а не читанням, —
## confirm_pending(), і вона йде рівно крізь MatchService.submit(); жоден
## інший метод не створює Command.
##
## R5, найважливіша обіцянка файлу: і select_unit(), і tap_cell() читають
## ЛИШЕ state.known_occupied_map(state.active_player) — ніколи
## state.occupied_map(). Маршрут, порахований проти правди, обходить
## невидимого ворога, і сама форма обходу стає доносом про те, де той стоїть
## (§3.2 CLAUDE.md, core/battle_state.gd:110). occupied_map() у цьому файлі
## не з'являється жодного разу — навмисно.
##
## R24: is_playing() читається крізь інжектований Callable, а не через пряме
## посилання на вузол EventPlayer — контейнер юнітів і сама сцена бою
## з'являються лише в Task 2.10, а цей контролер не тримає жодного
## посилання на дерево сцени понад те, що йому явно передали (§9 CLAUDE.md:
## жодних get_node("../../Foo")).

signal selection_changed(unit: Unit)
signal action_preview(preview: Dictionary)
## Прев'ю щойно знято — скасовано, підтверджено, або перекрито новим вибором
## (усі три шляхи проходять крізь _clear_pending() нижче). action_preview НЕ
## підходить для цього: він рахує «рівно одне прев'ю на дію» (усталений
## контракт, tests/game/test_input_controller.gd), а тут потрібен сигнал, що
## сам факт відсутності прев'ю змінився — окремий слухач (PathOverlay) знімає
## підсвітку шляху рівно на нього, не займаючи action_preview.
signal pending_cleared
signal targets_changed(tiles: Array[Vector2i])
signal action_refused(reason: String)
## Режим DRONE озброєно: кільце дальності й позначки {id цілі: причина або ""} —
## обидва з Targeting (§3.13), вигляд лише малює.
signal drone_armed(ring: Array[Vector2i], marks: Dictionary)
## Огляд юніта (§3.13): кільце гармати й кільце дрона та їхні позначки ОКРЕМО
## (дрон — окрема дія з власними кільцем і позначками), усе з Targeting.
## is_floor — оглянуто ворога з хоч одним кільцем: позначки лише нижня межа.
## Порожні масиви — огляд знято.
signal inspected(ring: Array[Vector2i], drone_ring: Array[Vector2i], marked: Array[int],
		drone_marked: Array[int], is_floor: bool)

## Тип очікуваної на підтвердження дії — ключ "type" у словнику нижче.
## Обидва прев'ю несуть лише числа й ідентифікатори, ніколи готовий рядок
## для показу (§9/§10 CLAUDE.md, «жодних хардкод-рядків») — текст і кнопку
## малює HUD (Task 2.8) із цих даних.
enum ActionType { MOVE, SHOT, ENGINEER, DRONE }

## MatchService (Task 2.1) — не типізований на його клас, бо
## game/autoload/match_service.gd навмисно не має class_name (він
## автозавантаження, а не окремий тип для типізації); той самий прийом
## динамічного виклику через Node вже усталений у
## tests/game/test_match_service.gd.
var _match_service: Node
var _zone_overlay: ZoneOverlay
## R24: Callable() (невалідний) типово означає «ніхто нічого не
## програє» — легальний стан для викликів поза сценою (тести, майбутні
## інструменти), а не помилка виклику.
var _is_playing_check: Callable

var _selected_unit: Unit = null
## Зони вибраного юніта — пораховані при виборі (select_unit) і наново після
## кожної підтвердженої дії (_sync_after_action, R23+рев'ю), а не на кожен
## тап: tap_cell() сам лише читає їх (can_reach/cost_to/path_to). Інваріант —
## _zones завжди описує ПОТОЧНІ позицію й AP _selected_unit, ніколи ту, що
## була на момент select_unit().
var _zones: Pathing.Zones = null
## Порожній словник means «нема дії, що чекає підтвердження». Не null:
## confirm_pending()/cancel_pending() перевіряють is_empty(), а не тип змінної.
var _pending: Dictionary = {}
## Озброєна верба інженера (-1 — режиму ENGINEER немає) і її допустимі тайли —
## рівно ті, що повернув EngineerCommand.action_status() (§3.13).
var _armed_action: int = -1
var _targets: Array[Vector2i] = []
## Режим DRONE: тап по ворогу — прев'ю удару, а не пострілу.
var _drone_armed: bool = false


func _init(match_service: Node, zone_overlay: ZoneOverlay, is_playing_check: Callable = Callable()) -> void:
	_match_service = match_service
	_zone_overlay = zone_overlay
	_is_playing_check = is_playing_check


## Прямий вибір юніта. Викликається і зсередини tap_cell() (тап по тайлі,
## де стоїть свій юніт), і ззовні — наприклад, майбутній вигляд юніта
## (Task 2.10) може резолвити власний тап напряму в Unit і покликати сюди,
## не проходячи крізь мапу тайлів узагалі. Зони рахуються лише для юніта
## АКТИВНОГО гравця: рахувати їх для чужого чи мертвого юніта означало б
## намалювати рух там, де жодного законного ходу для нього немає.
func select_unit(unit: Unit) -> void:
	if _input_blocked():
		return  # R24: «кожен тап» — і прямий виклик теж тап

	_clear_pending()
	disarm()
	_selected_unit = unit
	selection_changed.emit(unit)
	_recompute_zones_for_selected()
	if unit == null:
		inspect_clear()
	else:
		inspect_unit(unit)


## Перераховує _zones для ПОТОЧНОГО _selected_unit і синхронізує оверлей —
## спільне тіло для select_unit() (нова вибрана) і _sync_after_action()
## (та сама вибрана, але щойно змінені позиція/AP). Свідомо не чіпає
## selection_changed чи _selected_unit — той, хто вибраний, тут не міняється,
## лише те, що про нього пораховано.
func _recompute_zones_for_selected() -> void:
	var state: BattleState = _match_service.state
	if _selected_unit != null and _selected_unit.is_alive() and _selected_unit.owner == state.active_player:
		# R5: known, ніколи occupied_map() — це і є весь зміст рішення. Те саме
		# джерело, що й у MoveCommand: разом із відомими ворожими мінами (§3.11).
		var occupied: Dictionary = state.known_blocked_map(_selected_unit.owner)
		occupied.erase(_selected_unit.pos)  # власний тайл юніта завжди прохідний для нього самого
		_zones = Pathing.compute_zones(state.board, _selected_unit, occupied)
		_zone_overlay.show_for(_selected_unit, _zones)
	else:
		_zones = null
		_zone_overlay.clear()


## Єдина точка входу для тапу, вже резолвленого в тайл дошки (сам
## рейкаст із екранної точки в тайл — робота вигляду й камери,
## IsoCameraRig.world_to_cell, Task 2.2; сюди приходить готовий Vector2i).
## Модель бриф:
## 1. тап по своєму юніту → вибір;
## 2. тап по тайлі своєї зони → прев'ю руху;
## 3. тап по ворогові в межах пострілу → прев'ю пострілу;
## 4. тап поза дошкою або по вже вибраному юніту → зняти вибір.
## Усе, що не відповідає жодному з цих чотирьох пунктів, — легальний no-op:
## контролер не «вгадує», чого хотів гравець, коли модель мовчить.
func tap_cell(cell: Vector2i) -> void:
	if _input_blocked():
		return  # R24: ввід заблокований, доки триває програвання

	var state: BattleState = _match_service.state
	if _armed_action >= 0:
		_tap_in_engineer_mode(state, cell)
		return
	if _drone_armed:
		_tap_in_drone_mode(state, cell)
		return
	if not state.board.in_bounds(cell):
		_deselect()
		return

	if _selected_unit != null and _selected_unit.is_alive() and cell == _selected_unit.pos:
		_deselect()
		return

	# R5: те саме джерело зайнятості, що й у select_unit() — гравець тапає
	# в межах того, що сам знає, а не всезнаючого state.unit_at()/occupied_map().
	var known: Dictionary = state.known_occupied_map(state.active_player)
	var tapped: Unit = null
	if known.has(cell):
		tapped = state.get_unit(known[cell])

	if tapped != null and tapped.owner == state.active_player:
		select_unit(tapped)
		return

	if _selected_unit == null:
		# Нічого не вибрано: ворог — огляд його загрози, порожнє — зняти огляд (§3.13).
		if tapped != null:
			inspect_unit(tapped)
		else:
			inspect_clear()
		return

	if tapped != null:
		_maybe_set_pending_shot(state, tapped)
		return

	if _zones != null and _zones.can_reach(cell):
		_set_pending_move(cell)
	# інакше: тайл поза зоною вибраного юніта — no-op, а не здогад про намір


## R23: другий тап (кнопка HUD, Task 2.8) — єдиний спосіб дії. Ніщо інше в
## цьому файлі не викликає MatchService.submit().
func confirm_pending() -> void:
	if _input_blocked():
		return
	if _pending.is_empty():
		return
	var command: Command = _build_command(_pending)
	_clear_pending()
	disarm()
	if command == null:
		return
	var err: String = _match_service.submit(command)
	# Дії, які потрапляють у _pending, уже пройшли ту саму перевірку, що й
	# core/ (can_reach() зі свіжих зон, Targeting.firing_targets() — обидва
	# читають той самий стан, що submit() побачить за мить). Помилка тут
	# означала б розбіжність між прев'ю й правилами — дефект, який варто
	# піймати одразу, а не проковтнути мовчки.
	assert(err == "", "confirm_pending() підтвердив дію, яку core/ відхилив: %s" % err)
	if err == "":
		_sync_after_action()


## Огляд, знайдений на рев'ю: MoveCommand/FireCommand щойно змінили позицію
## й AP вибраного юніта (а рух через міну чи відповідь на постріл (§3.3.1)
## можуть його і вбити), тож _zones, пораховані ПРИ ВИБОРІ, більше не
## описують нинішній стан. Без цього виклику наступний тап планує від
## тайла, де юніта вже нема, і показує AP, якого вже нема, — а підтвердити
## таку дію submit() відмовиться, і трапиться саме assert() кількома рядками
## вище.
##
## Юніт лишається ВИБРАНИМ (жодного selection_changed) — це той самий юніт,
## лише щойно порахований наново; HUD (Task 2.8) слухає цей сигнал як «змінився
## об'єкт вибору», а не «змінилось щось про нього». Смерть — інша річ: тоді
## об'єкта вибору більше немає, і _deselect() каже про це правдиво.
func _sync_after_action() -> void:
	if _selected_unit == null:
		return
	if not _selected_unit.is_alive():
		_deselect()
		return
	_recompute_zones_for_selected()
	inspect_unit(_selected_unit)


## §3.13: кільце й позначки будь-якого видимого юніта. Які кільця існують і що
## позначено — вирішує core/ (Targeting.inspection), тут лише передача далі.
## Без _input_blocked(): це читання, а _sync_after_action() кличе його саме тоді,
## коли щойно подані події ще програються.
func inspect_unit(unit: Unit) -> void:
	if unit == null:
		inspect_clear()
		return
	var state: BattleState = _match_service.state
	var i: Dictionary = Targeting.inspection(state, unit.id, state.active_player)
	inspected.emit(i["ring"], i["drone_ring"], i["marked"], i["drone_marked"], i["is_floor"])


func inspect_clear() -> void:
	inspected.emit([] as Array[Vector2i], [] as Array[Vector2i], [] as Array[int], [] as Array[int], false)


func cancel_pending() -> void:
	_clear_pending()
	disarm()


## Режим ENGINEER для вибраного свого інженера. Тайли й причина відмови — лише
## з core/ (EngineerCommand.action_status), вигляд їх не виводить.
func arm_engineer(action: int) -> void:
	if _input_blocked() or _selected_unit == null:
		return
	var status: Dictionary = EngineerCommand.action_status(_match_service.state, _selected_unit.id, action)
	var tiles: Array[Vector2i] = status["tiles"]
	if tiles.is_empty():
		action_refused.emit(status["reason"])
		return
	_clear_pending()
	_armed_action = action
	_targets = tiles
	targets_changed.emit(tiles)


## Режим DRONE для вибраного свого загону (§3.9). Окрема дія, а не перемикач
## пострілу: без цього виклику тап по ворогу лишається пострілом.
func arm_drone() -> void:
	if _input_blocked() or _selected_unit == null:
		return
	var state: BattleState = _match_service.state
	var reason: String = DroneCommand.check_launch(state, _selected_unit)
	if reason != "":
		action_refused.emit(reason)
		return
	_clear_pending()
	disarm()
	_drone_armed = true
	drone_armed.emit(Targeting.reach_tiles(state, _selected_unit.id, DroneCommand.RANGE),
		Targeting.drone_marks(state, _selected_unit.id))


func disarm() -> void:
	_armed_action = -1
	_drone_armed = false
	_targets = []
	targets_changed.emit([] as Array[Vector2i])


## У режимі ENGINEER: тайл з допустимих — прев'ю верби; свій юніт — вибір
## (знімає режим); решта — action_refused з причиною цього тайла.
func _tap_in_engineer_mode(state: BattleState, cell: Vector2i) -> void:
	if _targets.has(cell):
		_pending = {
			"type": ActionType.ENGINEER,
			"unit_id": _selected_unit.id,
			"action": _armed_action,
			"target": cell,
		}
		# Межі ремонту — з core/, вигляд лише показує (§3.8, §3.13).
		if _armed_action == EngineerCommand.Action.REPAIR_UNIT:
			var bounds: Vector2i = EngineerCommand.repair_bounds(_selected_unit, state.unit_at(cell))
			_pending["heal_min"] = bounds.x
			_pending["heal_max"] = bounds.y
		action_preview.emit(_pending)
		return
	var known: Dictionary = state.known_occupied_map(state.active_player)
	if known.has(cell):
		var tapped: Unit = state.get_unit(known[cell])
		if tapped != null and tapped.owner == state.active_player:
			select_unit(tapped)
			return
	# Причина саме цього тайла — з validate(); несусідній тайл відмовляє раніше за
	# будь-яку перевірку вмісту, тож нічого прихованого не видає.
	action_refused.emit(EngineerCommand.create(_selected_unit.id, _armed_action, cell).validate(state))


## У режимі DRONE: відомий ворог — прев'ю удару або причина відмови з
## DroneCommand.validate() (та сама check_strike, що дала позначки); свій юніт —
## вибір (знімає режим); порожній, невідомий чи поза дошкою тайл — знімає режим,
## як «Скасувати», загін лишається вибраним (рішення контролера).
func _tap_in_drone_mode(state: BattleState, cell: Vector2i) -> void:
	var known: Dictionary = state.known_occupied_map(state.active_player)
	var tapped: Unit = state.get_unit(known[cell]) if known.has(cell) else null
	if tapped == null:
		cancel_pending()
		return
	if tapped.owner == state.active_player:
		select_unit(tapped)
		return
	var reason: String = DroneCommand.create(_selected_unit.id, tapped.id).validate(state)
	if reason != "":
		action_refused.emit(reason)
		return
	var bounds: Vector2i = Rules.drone_damage_bounds()
	_pending = {
		"type": ActionType.DRONE,
		"unit_id": _selected_unit.id,
		"target_id": tapped.id,
		"min": bounds.x,
		"max": bounds.y,
	}
	action_preview.emit(_pending)


## Єдина точка, де _pending скидається до «нема дії, що чекає підтвердження»
## (select_unit(), confirm_pending(), cancel_pending(), _deselect() — усі
## чотири крізь неї): pending_cleared надсилається рівно тут, один раз на
## кожен реальний скид, а не розкидано по викликах, де його легко забути в
## п'ятому.
func _clear_pending() -> void:
	_pending = {}
	pending_cleared.emit()


func _build_command(pending: Dictionary) -> Command:
	match pending["type"]:
		ActionType.MOVE:
			# facing -1: гравець тут не обирає напрямок окремо — MoveCommand
			# сам виводить його з останнього кроку шляху (core/commands/move_command.gd).
			return MoveCommand.create(pending["unit_id"], pending["target"], -1)
		ActionType.SHOT:
			return FireCommand.create(pending["unit_id"], pending["target_id"])
		ActionType.ENGINEER:
			return EngineerCommand.create(pending["unit_id"], pending["action"], pending["target"])
		ActionType.DRONE:
			return DroneCommand.create(pending["unit_id"], pending["target_id"])
	return null


func _set_pending_move(target: Vector2i) -> void:
	_pending = {
		"type": ActionType.MOVE,
		"unit_id": _selected_unit.id,
		"target": target,
		"path": Pathing.path_to(_zones, target),
		"ap_left": _selected_unit.ap - _zones.cost_to(target),
	}
	action_preview.emit(_pending)


## §3.3.1: «чи безпечно стріляти» — центральне питання ходу, тож сектор і
## межі шкоди йдуть у прев'ю непорушними — рівно те, що повернув
## FireCommand.preview(), без жодного власного округлення чи перерахунку.
func _maybe_set_pending_shot(state: BattleState, target: Unit) -> void:
	# Той самий запит, що малює оверлей цілей (§3.13) і не дублює умов
	# FireCommand.check_shot() — тап по ворогові поза дальністю чи поза
	# видимістю просто нічого не змінює, а не показує неправдиве прев'ю.
	if not Targeting.firing_targets(state, _selected_unit.id).has(target):
		return
	var preview: Dictionary = FireCommand.preview(state, _selected_unit.id, target.id)
	_pending = {
		"type": ActionType.SHOT,
		"unit_id": _selected_unit.id,
		"target_id": target.id,
		"sector": preview["sector"],
		"min": preview["min"],
		"max": preview["max"],
	}
	action_preview.emit(_pending)


func _deselect() -> void:
	disarm()
	_selected_unit = null
	_zones = null
	_clear_pending()
	_zone_overlay.clear()
	selection_changed.emit(null)
	inspect_clear()


func _is_playing() -> bool:
	return _is_playing_check.is_valid() and bool(_is_playing_check.call())


## Ввід не приймається взагалі — дві незалежні причини, один запобіжник на всі
## три точки входу (select_unit, tap_cell, confirm_pending).
##
## R24 (програвання) — перша половина, вона тут була й раніше. Друга —
## завершений матч, і це той самий дефект іншим боком: core/ відхиляє, якщо
## state.is_over(), УСІ команди (move_command.gd:16, fire_command.gd:22,
## drone_command.gd:25, engineer_command.gd:23, end_turn_command.gd:8), тож
## після перемоги будь-яке підтверджене прев'ю повернулось би помилкою й
## упало на assert нижче — рівно баг власника. Правильна відповідь — не
## пропонувати дії, яку правила вже відхиляють; assert лишається як стереже.
##
## confirm_pending() досі не перевіряв навіть _is_playing() — окрема діра,
## закрита цим же рядком, а не окремим.
##
## Екран результату — Phase 3 (§10 CLAUDE.md), не цей файл: поки що дошка
## просто завмирає. state може бути null до start_match() — це легальний стан
## для контролера, створеного до матчу, а не «матч завершено».
func _input_blocked() -> bool:
	var state: BattleState = _match_service.state
	return _is_playing() or (state != null and state.is_over())
