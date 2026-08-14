class_name EventPlayer
extends RefCounted
## Task 2.6: програвач подій. `core/` уже все вирішило — тут лише показ:
## строго по порядку, з `await` на кожній анімації, доки не скінчиться масив.
## Снаряд летить 400 мс, але шкоду вже вирішено (§6 CLAUDE.md) — цей файл не
## рахує жодного числа, яким можна вбити юніт; він лише читає готові події.
##
## R18: ідентифікатор юніта резолвиться в UnitView через інжектований
## лукап (`_unit_view_lookup`), ніколи через обхід дерева сцени. Контейнер
## юнітів з'являється лише в Task 2.10, тож лукап — параметр конструктора, а
## не жорстке посилання. Відсутній вузол (юніт поза `seen`, §3.5) —
## легальний no-op: подія просто нічого не малює, гра продовжується.
##
## R19: максимальне HP береться з ростера (`Unit.max_hp()` → `UnitTypes`),
## ніколи не вираховується з наглянутого трафіку подій. `core/` вирішує,
## вигляд показує — а зібраний з DamageDealt/UnitRepaired максимум був би
## рішенням цього файлу, забороненим архітектурою. Тому другий інжектований
## лукап, `_unit_lookup` (той самий контейнер Task 2.10, інша грань).

signal playback_finished

## Назва класу події (як у core/events.gd) → назва методу-обробника.
## R6: тест перевіряє це проти списку, добутого з самого events.gd, а не
## проти власних ключів цього словника — інакше бракуючий обробник ніколи б
## не впав. Порядок ключів нижче навмисно повторює порядок класів у
## core/events.gd, щоб діагностувати розбіжність оком було легко.
const HANDLERS: Dictionary = {
	"UnitMoved": "_handle_unit_moved",
	"UnitTurned": "_handle_unit_turned",
	"MoveBlocked": "_handle_move_blocked",
	"ShotFired": "_handle_shot_fired",
	"ShotRetaliated": "_handle_shot_retaliated",
	"DroneLaunched": "_handle_drone_launched",
	"DamageDealt": "_handle_damage_dealt",
	"UnitDestroyed": "_handle_unit_destroyed",
	"TileRevealed": "_handle_tile_revealed",
	"MinePlaced": "_handle_mine_placed",
	"MineCleared": "_handle_mine_cleared",
	"MineTriggered": "_handle_mine_triggered",
	"MineRevealed": "_handle_mine_revealed",
	"BridgeChanged": "_handle_bridge_changed",
	"UnitRepaired": "_handle_unit_repaired",
	"ObjectiveCaptured": "_handle_objective_captured",
	"ObjectiveDestroyed": "_handle_objective_destroyed",
	"ExperienceGained": "_handle_experience_gained",
	"ApChanged": "_handle_ap_changed",
	"TurnEnded": "_handle_turn_ended",
	"TurnStarted": "_handle_turn_started",
	"PlayerEliminated": "_handle_player_eliminated",
	"MatchEnded": "_handle_match_ended",
}

## Крок руху юніта клітинка-за-клітинкою (§1.4 — атмосфера читається, не
## пролітає повз). Той самий порядок величини, що й _FACE_TURN_DURATION у
## UnitView.
const _MOVE_STEP_DURATION: float = 0.12

var _unit_view_lookup: Callable
## R19: unit_id → Unit (той самий Task 2.10 контейнер, друга грань лукапу).
## Дає доступ до `Unit.max_hp()` — єдиного дозволеного джерела максимуму.
var _unit_lookup: Callable
var _is_playing: bool = false


func _init(unit_view_lookup: Callable = Callable(), unit_lookup: Callable = Callable()) -> void:
	_unit_view_lookup = unit_view_lookup
	_unit_lookup = unit_lookup


## Послідовно програє масив подій, чекаючи кожну анімацію, перш ніж почати
## наступну — порядок подій не косметика (§ бриф): відповідь, що зіграла
## раніше за постріл, який її викликав, читається як інша битва.
##
## Повторний виклик під час активного програвання — помилка виклика, не
## легітимний сценарій: Task 2.7 блокує ввід, поки is_playing() == true, тож
## другий play() міг би прийти лише з бага контролера. Рішення — тихо
## ігнорувати: `assert()` тут не годиться (перевірено окремо — падіння
## assert() у headless-запуску без дебагера здатне підвісити процес, а не
## просто вивести помилку), а `push_error()` забруднював би «чистий» вивід
## тесту, який саме цей сценарій і перевіряє. Перше програвання просто
## триває, друге не лишає жодного сліду.
func play(events: Array[Events.BattleEvent]) -> void:
	if _is_playing:
		return

	_is_playing = true
	for event in events:
		var awaitable: Variant = _dispatch(event)
		await awaitable
	_is_playing = false
	playback_finished.emit()


func is_playing() -> bool:
	return _is_playing


func _resolve_unit_view(unit_id: int) -> UnitView:
	if not _unit_view_lookup.is_valid():
		return null
	var result: Variant = _unit_view_lookup.call(unit_id)
	if result is UnitView:
		return result
	return null


## R19: 0 означає "не резолвилось" (лукап не інжектовано, або він не знає
## цей id) — викликач трактує це як легальний no-op, той самий дух, що й
## R18, а не як справжній нульовий максимум.
func _resolve_max_hp(unit_id: int) -> int:
	if not _unit_lookup.is_valid():
		return 0
	var result: Variant = _unit_lookup.call(unit_id)
	if result is Unit:
		return result.max_hp()
	return 0


## Спільна бухгалтерія DamageDealt і UnitRepaired: обидві події несуть лише
## `unit_id`/`hp_left`, обидві мають показати той самий пропорційний
## HP-бар. Максимум завжди з ростера (R19) — ніколи не виводиться з самих
## подій.
func _apply_hp_update(unit_id: int, hp_left: int) -> void:
	var view: UnitView = _resolve_unit_view(unit_id)
	if view == null:
		return
	var max_hp: int = _resolve_max_hp(unit_id)
	if max_hp <= 0:
		return
	view.set_hp(hp_left, max_hp)


## Єдина точка розгалуження за типом події. Anonymous вкладені класи
## core/events.gd не мають власного class_name (лише зовнішній `Events`
## його має), тож рефлексією ім'я типу не дістати — `is` лишається
## найпростішим і вже усталеним у core/ прийомом (див. core/mines.gd,
## tests/core/test_events.gd). Кожен `_handle_*` повертає або `Signal` для
## очікування, або null — `await` на null просто продовжує без паузи.
func _dispatch(event: Events.BattleEvent) -> Variant:
	if event is Events.UnitMoved:
		return _handle_unit_moved(event)
	elif event is Events.UnitTurned:
		return _handle_unit_turned(event)
	elif event is Events.MoveBlocked:
		return _handle_move_blocked(event)
	elif event is Events.ShotFired:
		return _handle_shot_fired(event)
	elif event is Events.ShotRetaliated:
		return _handle_shot_retaliated(event)
	elif event is Events.DroneLaunched:
		return _handle_drone_launched(event)
	elif event is Events.DamageDealt:
		return _handle_damage_dealt(event)
	elif event is Events.UnitDestroyed:
		return _handle_unit_destroyed(event)
	elif event is Events.TileRevealed:
		return _handle_tile_revealed(event)
	elif event is Events.MinePlaced:
		return _handle_mine_placed(event)
	elif event is Events.MineCleared:
		return _handle_mine_cleared(event)
	elif event is Events.MineTriggered:
		return _handle_mine_triggered(event)
	elif event is Events.MineRevealed:
		return _handle_mine_revealed(event)
	elif event is Events.BridgeChanged:
		return _handle_bridge_changed(event)
	elif event is Events.UnitRepaired:
		return _handle_unit_repaired(event)
	elif event is Events.ObjectiveCaptured:
		return _handle_objective_captured(event)
	elif event is Events.ObjectiveDestroyed:
		return _handle_objective_destroyed(event)
	elif event is Events.ExperienceGained:
		return _handle_experience_gained(event)
	elif event is Events.ApChanged:
		return _handle_ap_changed(event)
	elif event is Events.TurnEnded:
		return _handle_turn_ended(event)
	elif event is Events.TurnStarted:
		return _handle_turn_started(event)
	elif event is Events.PlayerEliminated:
		return _handle_player_eliminated(event)
	elif event is Events.MatchEnded:
		return _handle_match_ended(event)
	else:
		# Недосяжно, поки HANDLERS (перевірено тестом на повноту, R6) і ця
		# гілка тримаються в парі — це остання лінія оборони, не очікуваний
		# шлях, тому push_error(), а не мовчазний null.
		push_error("EventPlayer: необроблений тип події — %s" % event.describe())
		return null


func _handle_unit_moved(event: Events.UnitMoved) -> Variant:
	var view: UnitView = _resolve_unit_view(event.unit_id)
	if view == null:
		return null
	return view.move_along(event.path, _MOVE_STEP_DURATION)


func _handle_unit_turned(event: Events.UnitTurned) -> Variant:
	var view: UnitView = _resolve_unit_view(event.unit_id)
	if view == null:
		return null
	# face() навмисно fire-and-forget (Task 2.4, R14) — гравець не чекає на
	# поворот, тож тут немає сигналу для await.
	view.face(event.facing)
	return null


## §3.2/§3.5: позиція вже показана попереднім UnitMoved, чий шлях
## обірвався перед цим тайлом — MoveBlocked нічого нового не малює в цьому
## зрізі. Свідомий no-op, не пропущений ключ: майбутня задача може додати
## сюди коротку "не туди" анімацію чи іконку.
func _handle_move_blocked(_event: Events.MoveBlocked) -> Variant:
	return null


## Постріл і влучання показує DamageDealt (HP-бар) та, за потреби,
## UnitDestroyed. Власного снаряда/спалаху ще нема — жоден із спожитих
## інтерфейсів (BoardView/UnitView/IsoCameraRig) його не дає, а вигадувати
## нову механіку без узгодження заборонено CLAUDE.md §10. Свідомий no-op до
## задачі, яка додасть проєктильний вигляд.
func _handle_shot_fired(_event: Events.ShotFired) -> Variant:
	return null


## Та сама причина, що й у _handle_shot_fired — відповідь ще не має
## власного проєктильного вигляду в цьому зрізі.
func _handle_shot_retaliated(_event: Events.ShotRetaliated) -> Variant:
	return null


## §3.9: залишок дронів публічний і має готовий візуал — UnitView.set_drones.
func _handle_drone_launched(event: Events.DroneLaunched) -> Variant:
	var view: UnitView = _resolve_unit_view(event.attacker_id)
	if view == null:
		return null
	view.set_drones(event.drones_left)
	return null


func _handle_damage_dealt(event: Events.DamageDealt) -> Variant:
	_apply_hp_update(event.unit_id, event.hp_left)
	return null


func _handle_unit_destroyed(event: Events.UnitDestroyed) -> Variant:
	var view: UnitView = _resolve_unit_view(event.unit_id)
	if view == null:
		return null
	# Вилучення вузла з дерева — робота власника контейнера (Task 2.10), не
	# цього програвача: EventPlayer лише показує знищення, не керує складом
	# юнітів.
	return view.play_destroyed()


## §3.5: сама фог-логіка (які клітинки тепер `seen`) уже застосована в
## core/; BoardView свідомо не читає видимість і не приховує тайли
## (місцевість публічна з першого ходу). Немає що домальовувати тут.
func _handle_tile_revealed(_event: Events.TileRevealed) -> Variant:
	return null


## Візуал міни (маркер на тайлі) не входить до жодного з інтерфейсів, які
## споживає ця задача (BoardView/UnitView/IsoCameraRig). Свідомий no-op.
func _handle_mine_placed(_event: Events.MinePlaced) -> Variant:
	return null


func _handle_mine_cleared(_event: Events.MineCleared) -> Variant:
	return null


## Сам вибух міни без власного візуала в цьому зрізі — шкода, яку він
## завдав, уже прийде окремою DamageDealt/UnitDestroyed.
func _handle_mine_triggered(_event: Events.MineTriggered) -> Variant:
	return null


func _handle_mine_revealed(_event: Events.MineRevealed) -> Variant:
	return null


## Зміна виду тайлу (міст цілий/зруйнований) — це BoardView.build(), а не
## точкове перефарбовування; BoardView не дає API для зміни виду одного
## тайлу без перебудови всієї дошки, тож поки що це no-op.
func _handle_bridge_changed(_event: Events.BridgeChanged) -> Variant:
	return null


func _handle_unit_repaired(event: Events.UnitRepaired) -> Variant:
	_apply_hp_update(event.unit_id, event.hp_left)
	return null


## Маркери цілей на дошці не входять до споживаних цією задачею інтерфейсів.
func _handle_objective_captured(_event: Events.ObjectiveCaptured) -> Variant:
	return null


func _handle_objective_destroyed(_event: Events.ObjectiveDestroyed) -> Variant:
	return null


## §3.7: рівень досвіду піде в HUD (інша задача), не в анімацію на дошці.
func _handle_experience_gained(_event: Events.ExperienceGained) -> Variant:
	return null


## Індикатора АП немає серед споживаних інтерфейсів — контролер читає
## BattleState напряму для HUD, а не через цей потік подій.
func _handle_ap_changed(_event: Events.ApChanged) -> Variant:
	return null


## Передача ходу і ворота розвороту (§3.5) — контролер (Task 2.7+), не
## анімація на дошці.
func _handle_turn_ended(_event: Events.TurnEnded) -> Variant:
	return null


func _handle_turn_started(_event: Events.TurnStarted) -> Variant:
	return null


## Екран поразки/перемоги — інша задача.
func _handle_player_eliminated(_event: Events.PlayerEliminated) -> Variant:
	return null


func _handle_match_ended(_event: Events.MatchEnded) -> Variant:
	return null
