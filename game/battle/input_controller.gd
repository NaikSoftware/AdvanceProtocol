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

## Тип очікуваної на підтвердження дії — ключ "type" у словнику нижче.
## Обидва прев'ю несуть лише числа й ідентифікатори, ніколи готовий рядок
## для показу (§9/§10 CLAUDE.md, «жодних хардкод-рядків») — текст і кнопку
## малює HUD (Task 2.8) із цих даних.
enum ActionType { MOVE, SHOT }

## MatchService (Task 2.1) — не типізований на його клас, бо
## game/autoload/match_service.gd навмисно не має class_name (він
## автозавантаження, а не окремий тип для типізації); той самий прийом
## динамічного виклику через Node вже усталений у
## tests/game/test_match_service.gd.
var _match_service: Node
var _zone_overlay: ZoneOverlay
## R24: Callable() (невалідний) за замовчуванням означає «ніхто нічого не
## програє» — легальний стан для викликів поза сценою (тести, майбутні
## інструменти), а не помилка виклику.
var _is_playing_check: Callable

var _selected_unit: Unit = null
## Зони вибраного юніта — пораховані один раз при виборі (select_unit), а не
## на кожен тап: tap_cell() лише читає їх (can_reach/cost_to/path_to).
var _zones: Pathing.Zones = null
## Порожній словник means «нема дії, що чекає підтвердження». Не null:
## confirm_pending()/cancel_pending() перевіряють is_empty(), а не тип змінної.
var _pending: Dictionary = {}


func _init(match_service: Node, zone_overlay: ZoneOverlay, is_playing_check: Callable = Callable()) -> void:
	_match_service = match_service
	_zone_overlay = zone_overlay
	_is_playing_check = is_playing_check


## Прямий вибір юніта. Викликається і зсередини tap_cell() (тап по клітинці,
## де стоїть свій юніт), і ззовні — наприклад, майбутній вигляд юніта
## (Task 2.10) може резолвити власний тап напряму в Unit і покликати сюди,
## не проходячи крізь мапу клітинок узагалі. Зони рахуються лише для юніта
## АКТИВНОГО гравця: рахувати їх для чужого чи мертвого юніта означало б
## намалювати рух там, де жодного законного ходу для нього немає.
func select_unit(unit: Unit) -> void:
	if _is_playing():
		return  # R24: «кожен тап» — і прямий виклик теж тап

	_pending = {}
	_selected_unit = unit
	selection_changed.emit(unit)

	var state: BattleState = _match_service.state
	if unit != null and unit.is_alive() and unit.owner == state.active_player:
		# R5: known, ніколи occupied_map() — це і є весь зміст ruling'у.
		var occupied: Dictionary = state.known_occupied_map(unit.owner)
		occupied.erase(unit.pos)  # власний тайл юніта завжди прохідний для нього самого
		_zones = Pathing.compute_zones(state.board, unit, occupied)
		_zone_overlay.show_for(unit, _zones)
	else:
		_zones = null
		_zone_overlay.clear()


## Єдина точка входу для тапу, вже резолвленого в клітинку дошки (сам
## рейкаст із екранної точки в клітинку — робота вигляду й камери,
## IsoCameraRig.world_to_cell, Task 2.2; сюди приходить готовий Vector2i).
## Модель бриф:
## 1. тап по своєму юніту → вибір;
## 2. тап по клітинці своєї зони → прев'ю руху;
## 3. тап по ворогові в межах пострілу → прев'ю пострілу;
## 4. тап поза дошкою або по вже вибраному юніту → зняти вибір.
## Усе, що не відповідає жодному з цих чотирьох пунктів, — легальний no-op:
## контролер не «вгадує», чого хотів гравець, коли модель мовчить.
func tap_cell(cell: Vector2i) -> void:
	if _is_playing():
		return  # R24: ввід заблокований, доки триває програвання

	var state: BattleState = _match_service.state
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
		return  # нічого не вибрано — тап по порожній чи ворожій клітинці нічого не важить

	if tapped != null:
		_maybe_set_pending_shot(state, tapped)
		return

	if _zones != null and _zones.can_reach(cell):
		_set_pending_move(cell)
	# інакше: клітинка поза зоною вибраного юніта — no-op, а не здогад про намір


## R23: другий тап (кнопка HUD, Task 2.8) — єдиний спосіб дії. Ніщо інше в
## цьому файлі не викликає MatchService.submit().
func confirm_pending() -> void:
	if _pending.is_empty():
		return
	var command: Command = _build_command(_pending)
	_pending = {}
	if command == null:
		return
	var err: String = _match_service.submit(command)
	# Дії, які потрапляють у _pending, уже пройшли ту саму перевірку, що й
	# core/ (can_reach() зі свіжих зон, Targeting.firing_targets() — обидва
	# читають той самий стан, що submit() побачить за мить). Помилка тут
	# означала б розбіжність між прев'ю й правилами — дефект, який варто
	# піймати одразу, а не проковтнути мовчки.
	assert(err == "", "confirm_pending() підтвердив дію, яку core/ відхилив: %s" % err)


func cancel_pending() -> void:
	_pending = {}


func _build_command(pending: Dictionary) -> Command:
	match pending["type"]:
		ActionType.MOVE:
			# facing -1: гравець тут не обирає напрямок окремо — MoveCommand
			# сам виводить його з останнього кроку шляху (core/commands/move_command.gd).
			return MoveCommand.create(pending["unit_id"], pending["target"], -1)
		ActionType.SHOT:
			return FireCommand.create(pending["unit_id"], pending["target_id"])
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
	_selected_unit = null
	_zones = null
	_pending = {}
	_zone_overlay.clear()
	selection_changed.emit(null)


func _is_playing() -> bool:
	return _is_playing_check.is_valid() and bool(_is_playing_check.call())
