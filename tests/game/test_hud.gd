extends GutTest
## Task 2.8, R28: HUD і інспектор — headless. Жива battle_screen.tscn зʼявляється
## лише в Task 2.10, тож сцена HUD інстанціюється тут напряму, а перевіряється
## рівно те, що побачить гравець: текст і видимість вузлів, а не внутрішні поля
## скрипта.
##
## Прев'ю приходять у форматі, який ВИПУСКАЄ InputController (R27): ключ "type"
## з InputController.ActionType, а не рядок. Останній тест у файлі женe справжній
## InputController крізь HUD саме для того, щоб контракт перевірявся проти
## емітента, а не проти переказу контракту в цьому файлі.

const HudScene := preload("res://game/ui/hud.tscn")
const MatchServiceScript := preload("res://game/autoload/match_service.gd")
const RigScene := preload("res://game/camera/iso_camera_rig.tscn")

## Поля безпеки з hud.tscn (SafeArea): панель, прив'язана до клітинки юніта,
## не сміє заїхати під виріз екрана, скільки б камеру не відводили від юніта.
const SAFE_LEFT: float = 56.0
const SAFE_TOP: float = 24.0
const SAFE_RIGHT: float = 56.0
const SAFE_BOTTOM: float = 24.0

## Той самий прийом, що й у tests/game/test_input_controller.gd: шпигун замість
## справжнього ZoneOverlay, бо той тягне за собою живий BoardView із MultiMesh,
## якого під headless не перевірити.
class SpyZoneOverlay extends ZoneOverlay:
	func _init() -> void:
		pass

	func show_for(_unit: Unit, _zones: Pathing.Zones) -> void:
		pass

	func clear() -> void:
		pass


var hud: Hud
var _service: Node


func before_each() -> void:
	hud = HudScene.instantiate()
	add_child_autofree(hud)
	_service = MatchServiceScript.new()
	add_child_autofree(_service)


func _state(ground_state: int = Terrain.GroundState.DRY) -> BattleState:
	_service.start_match(Board.create(12, 12, ground_state), 2, 1)
	return _service.state


func _label(unique_name: String) -> Label:
	return hud.get_node("%" + unique_name) as Label


func _inspector() -> UnitInspector:
	return hud.get_node("%Inspector") as UnitInspector


func _shot_preview(sector: int, dmg_min: int, dmg_max: int) -> Dictionary:
	return {
		"type": InputController.ActionType.SHOT,
		"unit_id": 1,
		"target_id": 2,
		"sector": sector,
		"min": dmg_min,
		"max": dmg_max,
	}


func _move_preview(ap_left: int) -> Dictionary:
	return {
		"type": InputController.ActionType.MOVE,
		"unit_id": 1,
		"target": Vector2i(4, 4),
		"path": [Vector2i(4, 4)] as Array[Vector2i],
		"ap_left": ap_left,
	}


# --- bind(): хід, гравець, стан ґрунту -------------------------------------

func test_bind_puts_turn_number_active_player_and_ground_state_on_screen() -> void:
	var state: BattleState = _state(Terrain.GroundState.MUD)
	state.turn_number = 7
	state.active_player = 1

	hud.bind(state)

	assert_eq(_label("TurnValue").text, "7", "номер ходу читається з turn_number")
	assert_eq(_label("PlayerValue").text, "2", "активний гравець показується як 1-based номер")
	assert_eq(_label("GroundStateLabel").text, "hud_ground_mud", "ґрунт — підписана іконка (§3.12)")
	assert_true(_label("GroundStateLabel").is_visible_in_tree(), "підпис ґрунту видимий постійно")
	assert_true(hud.get_node("%GroundStateIcon").is_visible_in_tree(), "іконка ґрунту видима постійно")


func test_ground_state_icon_and_label_follow_the_board_not_a_default() -> void:
	hud.bind(_state(Terrain.GroundState.FROZEN))
	var frozen_key: String = _label("GroundStateLabel").text
	var frozen_color: Color = (hud.get_node("%GroundStateIcon") as ColorRect).color

	hud.bind(_state(Terrain.GroundState.DRY))

	assert_eq(frozen_key, "hud_ground_frozen")
	assert_eq(_label("GroundStateLabel").text, "hud_ground_dry")
	assert_ne((hud.get_node("%GroundStateIcon") as ColorRect).color, frozen_color,
		"іконка мусить відрізнятися кольором між станами, інакше вона нічого не каже")


func test_set_active_player_changes_the_displayed_player() -> void:
	var state: BattleState = _state()
	hud.bind(state)
	assert_eq(_label("PlayerValue").text, "1", "передумова: показаний гравець 0")

	hud.set_active_player(1)

	assert_eq(_label("PlayerValue").text, "2")


func test_new_active_player_does_not_inherit_the_previous_players_selection() -> void:
	var state: BattleState = _state()
	var u: Unit = state.add_unit(5, 0, Vector2i(3, 3), 0)
	hud.bind(state)
	hud.show_selection(u)
	assert_true(hud.get_node("%SelectionRow").is_visible_in_tree(), "передумова: вибір показаний")

	hud.set_active_player(1)

	assert_false(hud.get_node("%SelectionRow").is_visible_in_tree(),
		"§1.2: панель вибору попереднього гравця не мусить пережити передачу ходу")
	assert_false(_inspector().is_visible_in_tree(), "інспектор чужого юніта теж не мусить лишатися")


# --- show_preview(): постріл ------------------------------------------------

func test_show_preview_shot_displays_the_payload_sector_and_both_damage_bounds() -> void:
	hud.bind(_state())

	# Сектор навмисно НЕ FRONT (0): захардкоджене значення пройшло б тест із
	# дефолтом і провалюється тут.
	hud.show_preview(_shot_preview(UnitTypes.ArmourSector.REAR, 37, 91))

	assert_eq(_label("PreviewSectorValue").text, "hud_sector_rear")
	assert_true(_label("PreviewSectorValue").is_visible_in_tree())
	var damage: String = _label("PreviewDamageValue").text
	assert_true(damage.contains("37"), "нижня межа мусить бути на екрані як є: %s" % damage)
	assert_true(damage.contains("91"), "верхня межа мусить бути на екрані як є: %s" % damage)
	assert_true(_label("PreviewDamageValue").is_visible_in_tree())
	assert_eq(_inspector().highlighted_sector(), UnitTypes.ArmourSector.REAR,
		"§3.4: інспектор мусить підсвітити той сектор, у який піде постріл")

	# Другий сектор тим самим шляхом — доказ, що показується саме payload.
	hud.show_preview(_shot_preview(UnitTypes.ArmourSector.SIDE, 12, 20))

	assert_eq(_label("PreviewSectorValue").text, "hud_sector_side")
	assert_eq(_inspector().highlighted_sector(), UnitTypes.ArmourSector.SIDE)


func test_show_preview_move_shows_ap_left_and_leaves_no_shot_fields_behind() -> void:
	hud.bind(_state())
	hud.show_preview(_shot_preview(UnitTypes.ArmourSector.REAR, 37, 91))
	assert_true(_label("PreviewSectorValue").is_visible_in_tree(), "передумова: прев'ю пострілу показане")

	hud.show_preview(_move_preview(18))

	assert_eq(_label("PreviewApValue").text, "18", "залишок AP показується числом")
	assert_true(_label("PreviewApValue").is_visible_in_tree())
	assert_false(_label("PreviewSectorValue").is_visible_in_tree(),
		"сектор попереднього прев'ю не мусить лишатися на екрані")
	assert_false(_label("PreviewDamageValue").is_visible_in_tree(),
		"шкода попереднього прев'ю не мусить лишатися на екрані")
	assert_eq(_inspector().highlighted_sector(), -1,
		"підсвітка сектора теж мусить зникнути разом із прев'ю пострілу")


func test_selecting_another_unit_clears_the_pending_preview() -> void:
	var state: BattleState = _state()
	var u: Unit = state.add_unit(5, 0, Vector2i(3, 3), 0)
	hud.bind(state)
	hud.show_preview(_shot_preview(UnitTypes.ArmourSector.REAR, 37, 91))

	hud.show_selection(u)

	assert_false(_label("PreviewSectorValue").is_visible_in_tree(),
		"новий вибір знімає pending у контролері — HUD не мусить показувати прев'ю, якого вже нема")
	assert_true((hud.get_node("%ConfirmButton") as Button).disabled,
		"без прев'ю підтверджувати нічого")


# --- Вибраний юніт: AP і дрони ----------------------------------------------

func test_selected_unit_shows_its_ap_as_a_number() -> void:
	var state: BattleState = _state()
	var u: Unit = state.add_unit(5, 0, Vector2i(3, 3), 0)  # medium tank
	u.ap = 17
	hud.bind(state)

	hud.show_selection(u)

	assert_true(hud.get_node("%SelectionRow").is_visible_in_tree())
	assert_eq(_label("ApValue").text, "17")

	hud.show_selection(null)

	assert_false(hud.get_node("%SelectionRow").is_visible_in_tree(),
		"знятий вибір не мусить лишати чужого AP на екрані")


func test_remaining_drone_count_is_shown_for_a_squad_that_has_drones() -> void:
	var state: BattleState = _state()
	var squad: Unit = state.add_unit(1, 0, Vector2i(3, 3), 0)  # assault squad, 2 дрони
	hud.bind(state)

	hud.show_selection(squad)

	assert_true(hud.get_node("%DronesRow").is_visible_in_tree(), "§3.9: залишок дронів видимий")
	assert_eq(_label("DronesValue").text, "2")

	squad.drones_left = 1
	hud.show_selection(squad)

	assert_eq(_label("DronesValue").text, "1", "лічильник мусить читатися з юніта, а не бути константою")


func test_drone_count_is_public_and_shown_for_an_enemy_squad_too() -> void:
	var state: BattleState = _state()
	state.active_player = 0
	var enemy_squad: Unit = state.add_unit(1, 1, Vector2i(8, 8), 0)
	enemy_squad.drones_left = 1
	hud.bind(state)

	hud.show_selection(enemy_squad)

	assert_true(hud.get_node("%DronesRow").is_visible_in_tree(),
		"§3.9: лічильник дронів публічний — його видно кожному гравцеві, не лише власнику")
	assert_eq(_label("DronesValue").text, "1")


func test_unit_without_drones_hides_the_drone_row_instead_of_showing_zero() -> void:
	var state: BattleState = _state()
	var tank: Unit = state.add_unit(5, 0, Vector2i(3, 3), 0)  # medium tank, 0 дронів
	hud.bind(state)

	hud.show_selection(tank)

	assert_false(hud.get_node("%DronesRow").is_visible_in_tree(),
		"«0 дронів» у танка — шум: дронів у нього не буває взагалі")


# --- Інспектор: стати з UnitTypes і три числа броні --------------------------

func test_inspector_shows_roster_stats_and_three_armour_numbers() -> void:
	var state: BattleState = _state()
	var tank: Unit = state.add_unit(5, 0, Vector2i(3, 3), 0)  # medium tank
	tank.hp = 210
	hud.bind(state)

	hud.show_selection(tank)

	var insp: UnitInspector = _inspector()
	var t: Dictionary = UnitTypes.get_type(5)
	assert_true(insp.is_visible_in_tree())
	assert_eq((insp.get_node("%StatName") as Label).text, t["name_key"], "назва — ключ ростера, не рядок")
	assert_eq((insp.get_node("%StatHp") as Label).text, "210/%d" % int(t["max_hp"]))
	assert_eq((insp.get_node("%StatAttack") as Label).text, str(int(t["attack"])))
	assert_eq((insp.get_node("%StatRange") as Label).text, str(int(t["attack_range"])))
	assert_eq((insp.get_node("%StatVision") as Label).text, str(int(t["vision"])))
	var armour: Array = t["armour"]
	assert_eq((insp.get_node("%ArmourFront") as Label).text, str(int(armour[UnitTypes.ArmourSector.FRONT])))
	assert_eq((insp.get_node("%ArmourSide") as Label).text, str(int(armour[UnitTypes.ArmourSector.SIDE])))
	assert_eq((insp.get_node("%ArmourRear") as Label).text, str(int(armour[UnitTypes.ArmourSector.REAR])))


func test_inspector_highlights_exactly_one_armour_sector() -> void:
	var state: BattleState = _state()
	var tank: Unit = state.add_unit(5, 0, Vector2i(3, 3), 0)
	hud.bind(state)
	hud.show_selection(tank)
	var insp: UnitInspector = _inspector()
	var neutral: Color = (insp.get_node("%ArmourRear") as Label).modulate

	insp.highlight_sector(UnitTypes.ArmourSector.REAR)

	assert_eq(insp.highlighted_sector(), UnitTypes.ArmourSector.REAR)
	assert_ne((insp.get_node("%ArmourRear") as Label).modulate, neutral, "влучений сектор мусить виглядати інакше")
	assert_eq((insp.get_node("%ArmourFront") as Label).modulate, neutral, "невлучені сектори лишаються нейтральними")
	assert_eq((insp.get_node("%ArmourSide") as Label).modulate, neutral)

	insp.highlight_sector(-1)

	assert_eq(insp.highlighted_sector(), -1)
	assert_eq((insp.get_node("%ArmourRear") as Label).modulate, neutral)


# --- R29: жоден підпис не є захардкодженим рядком ----------------------------

## Ключі перекладу лишаються ключами, доки CSV не існує (R29), тож на екрані
## видно рівно те, що піде в CSV. Усе інше — числа. Будь-який «Хід:» чи «Damage»
## провалює цей тест.
func test_no_user_facing_label_is_a_hard_coded_literal() -> void:
	var state: BattleState = _state(Terrain.GroundState.MUD)
	var squad: Unit = state.add_unit(1, 0, Vector2i(3, 3), 0)
	hud.bind(state)
	hud.show_selection(squad)
	hud.show_preview(_shot_preview(UnitTypes.ArmourSector.SIDE, 40, 60))

	var texts: Array[String] = []
	_collect_texts(hud, texts)

	assert_gt(texts.size(), 15, "обхід дерева мусить справді щось знайти, інакше тест порожній")
	var key_re := RegEx.create_from_string("^[a-z][a-z0-9_]*_[a-z0-9_]+$")
	var roster_re := RegEx.create_from_string("^UNIT_[A-Z_]+$")
	var numeric_re := RegEx.create_from_string("^[0-9 /.%–-]+$")
	for text in texts:
		if text.is_empty():
			continue
		var ok: bool = key_re.search(text) != null \
			or roster_re.search(text) != null \
			or numeric_re.search(text) != null
		assert_true(ok, "«%s» — не ключ перекладу і не число (§9, R29)" % text)


func _collect_texts(node: Node, out: Array[String]) -> void:
	for child in node.get_children():
		if child is Label:
			out.append((child as Label).text)
		elif child is Button:
			out.append((child as Button).text)
		_collect_texts(child, out)


# --- Тапабельність і бюджет --------------------------------------------------

func test_every_button_is_at_least_48_dp_tall() -> void:
	var buttons: Array[Button] = []
	_collect_buttons(hud, buttons)
	assert_gt(buttons.size(), 2, "кнопок мусить бути принаймні три: скасувати, підтвердити, завершити хід")
	for b in buttons:
		assert_true(b.custom_minimum_size.y >= 48.0,
			"%s нижча за 48 dp — палець у неї не влучить (§9)" % b.name)


func _collect_buttons(node: Node, out: Array[Button]) -> void:
	for child in node.get_children():
		if child is Button:
			out.append(child as Button)
		_collect_buttons(child, out)


# --- Панель характеристик прив'язана до юніта, а не до кута екрана ----------
#
# Скарга власника: «якщо рухати камеру, вікно з характеристиками юніта
# лишається на місці». Панель належить ВИБРАНОМУ ЮНІТУ, тож мусить їхати
# разом із дошкою — і при цьому не вилазити за поля безпеки.
#
# Зв'язка збирається тут вручну (ріг + HUD + attach_camera), бо жива
# battle_screen.tscn проводить її своїм рядком, а перевіряти треба сам контракт
# HUD, а не сцену.

func _rig_for(unit: Unit) -> IsoCameraRig:
	var rig: IsoCameraRig = RigScene.instantiate()
	add_child_autofree(rig)
	rig.set_bounds(Vector2i(12, 12))
	rig.center_on(unit.pos)
	return rig


func test_inspector_moves_with_the_camera() -> void:
	var state: BattleState = _state()
	var u: Unit = state.add_unit(5, 0, Vector2i(6, 6), 0)
	var rig: IsoCameraRig = _rig_for(u)
	hud.bind(state)
	hud.attach_camera(rig)
	hud.show_selection(u)
	var before: Vector2 = _inspector().position

	rig.pan(Vector2(120.0, 0.0))

	assert_ne(_inspector().position, before,
		"панель прив'язана до юніта: поїхала камера — поїхала й вона (позиція лишилась %s)" % before)


## Юніт у дальньому кутку, камера відведена від нього до упору — екранна точка
## юніта опиняється ЗА верхнім краєм екрана. Панель мусить притиснутись рівно
## до поля безпеки, а не поїхати за ним слідом у нікуди.
func test_inspector_is_clamped_to_the_safe_area_when_its_unit_is_off_screen() -> void:
	var state: BattleState = _state()
	var u: Unit = state.add_unit(5, 0, Vector2i(0, 0), 0)
	var rig: IsoCameraRig = _rig_for(u)
	hud.bind(state)
	hud.attach_camera(rig)
	hud.show_selection(u)

	for i in 50:
		rig.pan(Vector2(0.0, -2000.0))

	assert_eq(_inspector().position.y, SAFE_TOP,
		"панель мусить стати рівно на верхнє поле безпеки (56/24 з hud.tscn), а не піти за юнітом за екран")
	var panel := Rect2(_inspector().position, _inspector().size)
	var safe := Rect2(SAFE_LEFT, SAFE_TOP,
		hud.size.x - SAFE_LEFT - SAFE_RIGHT, hud.size.y - SAFE_TOP - SAFE_BOTTOM)
	assert_true(safe.encloses(panel),
		"панель %s мусить цілком уміститись у полях безпеки %s" % [panel, safe])


func test_inspector_stays_hidden_when_nothing_is_selected_even_with_a_camera_attached() -> void:
	var state: BattleState = _state()
	var u: Unit = state.add_unit(5, 0, Vector2i(6, 6), 0)
	var rig: IsoCameraRig = _rig_for(u)
	hud.bind(state)
	hud.attach_camera(rig)
	hud.show_selection(u)
	assert_true(_inspector().visible, "передумова: панель показана")

	hud.show_selection(null)
	rig.pan(Vector2(120.0, 0.0))

	assert_false(_inspector().visible, "без вибору панель схована — і рух камери її не воскрешає")


## §8: панель їде за камерою на СИГНАЛ рига, не в _process. Той самий бюджет,
## що й у test_hud_does_no_per_frame_work нижче, але вже з прив'язаною камерою
## і живим вибором — тобто в стані, у якому спокуса опитувати камеру щокадру
## найбільша.
func test_a_camera_bound_inspector_still_does_no_per_frame_work() -> void:
	var state: BattleState = _state()
	var u: Unit = state.add_unit(5, 0, Vector2i(6, 6), 0)
	hud.bind(state)
	hud.attach_camera(_rig_for(u))
	hud.show_selection(u)

	assert_false(hud.is_processing(), "правила й показ не живуть у _process (§9)")
	assert_false(hud.is_physics_processing())
	assert_false(_inspector().is_processing())


func test_hud_does_no_per_frame_work() -> void:
	assert_false(hud.is_processing(), "правила й показ не живуть у _process (§9)")
	assert_false(hud.is_physics_processing())
	assert_false(_inspector().is_processing())


# --- R27: контракт перевіряється проти справжнього емітента ------------------

func test_controller_drives_the_hud_and_the_confirm_button_is_the_only_way_to_act() -> void:
	var state: BattleState = _state()
	var u: Unit = state.add_unit(5, 0, Vector2i(3, 3), 0)  # medium tank, ap 48
	_service.begin()
	_service.take_events()
	var controller := InputController.new(_service, SpyZoneOverlay.new())
	hud.bind(state)
	hud.attach_controller(controller)

	controller.select_unit(u)
	assert_eq(_label("ApValue").text, str(u.ap), "selection_changed мусить наповнити панель вибору")

	controller.tap_cell(Vector2i(4, 3))
	assert_true(_label("PreviewApValue").is_visible_in_tree(),
		"action_preview від справжнього контролера мусить читатися HUD'ом")
	assert_false((hud.get_node("%ConfirmButton") as Button).disabled, "є що підтверджувати")

	(hud.get_node("%CancelButton") as Button).pressed.emit()
	assert_eq(u.pos, Vector2i(3, 3), "скасування не рухає юніт")
	assert_true((hud.get_node("%ConfirmButton") as Button).disabled, "після скасування підтверджувати нічого")

	controller.tap_cell(Vector2i(4, 3))
	(hud.get_node("%ConfirmButton") as Button).pressed.emit()

	assert_eq(u.pos, Vector2i(4, 3), "кнопка підтвердження — єдиний шлях до дії")
	assert_true((hud.get_node("%ConfirmButton") as Button).disabled, "прев'ю спожите разом із дією")


func test_shot_preview_from_the_real_controller_shows_its_sector_and_bounds() -> void:
	var state: BattleState = _state()
	var u: Unit = state.add_unit(5, 0, Vector2i(3, 3), 0)
	# Ціль дивиться на північ (facing 0), стрілець стоїть південніше — постріл
	# іде в корму, тобто сектор навмисно не дефолтний.
	var enemy: Unit = state.add_unit(5, 1, Vector2i(3, 2), 0)
	_service.begin()
	_service.take_events()
	var controller := InputController.new(_service, SpyZoneOverlay.new())
	hud.bind(state)
	hud.attach_controller(controller)
	var expected: Dictionary = FireCommand.preview(state, u.id, enemy.id)

	controller.select_unit(u)
	controller.tap_cell(enemy.pos)

	assert_eq(_inspector().highlighted_sector(), int(expected["sector"]),
		"сектор на екрані мусить бути тим, що порахував FireCommand.preview()")
	var damage: String = _label("PreviewDamageValue").text
	assert_true(damage.contains(str(int(expected["min"]))), "нижня межа без переокруглення: %s" % damage)
	assert_true(damage.contains(str(int(expected["max"]))), "верхня межа без переокруглення: %s" % damage)


func test_end_turn_button_reports_the_press_and_submits_nothing_itself() -> void:
	var state: BattleState = _state()
	state.add_unit(5, 0, Vector2i(3, 3), 0)
	_service.begin()
	_service.take_events()
	hud.bind(state)
	watch_signals(hud)

	(hud.get_node("%EndTurnButton") as Button).pressed.emit()

	assert_signal_emitted(hud, "end_turn_pressed")
	assert_true(_service.take_events().is_empty(),
		"HUD не подає команд сам — рішення про кінець ходу належить сцені бою")


## Баг власника: після знищення останнього ворожого юніта натискання «завершити
## хід» падало на assert у battle_screen.gd, бо EndTurnCommand.validate()
## повертає ERR_MATCH_OVER (core/commands/end_turn_command.gd:8). Кнопка не сміє
## пропонувати дію, яку правила вже відхиляють. Матч завершується справжнім
## шляхом ядра: гравець 1 без юнітів вибуває на першому ж кінці ходу.
func test_end_turn_button_is_disabled_once_the_match_is_over() -> void:
	var state: BattleState = _state()
	state.add_unit(5, 0, Vector2i(3, 3), 0)
	_service.begin()
	_service.take_events()
	hud.bind(state)
	hud.attach_match_service(_service)
	var button := hud.get_node("%EndTurnButton") as Button
	assert_false(button.disabled, "передумова: поки матч триває, кінець ходу доступний")

	_service.submit(EndTurnCommand.create())

	assert_true(state.is_over(), "передумова: гравець 1 без юнітів — матч завершився")
	assert_true(button.disabled,
		"після завершення матчу кнопка кінця ходу мусить бути вимкнена — core/ цю команду вже відхиляє")


# --- Прив'язка до MatchService ----------------------------------------------

func test_events_ready_refreshes_turn_number_and_the_selected_units_ap() -> void:
	var state: BattleState = _state()
	var u: Unit = state.add_unit(5, 0, Vector2i(3, 3), 0)
	_service.begin()
	_service.take_events()
	hud.bind(state)
	hud.attach_match_service(_service)
	hud.show_selection(u)
	var ap_before: int = u.ap
	assert_eq(_label("ApValue").text, str(ap_before), "передумова: AP показаний")

	_service.submit(MoveCommand.create(u.id, Vector2i(4, 3), -1))

	assert_lt(u.ap, ap_before, "передумова: рух справді витратив AP")
	assert_eq(_label("ApValue").text, str(u.ap),
		"після події AP на екрані мусить бути нинішнім, а не тим, що був при виборі")


## Дефект, знайдений на ЖИВОМУ екрані, не в тесті: коли юніт близько до правого
## краю, панель праворуч уже не влазить, і сам по собі clampf зсовував її вліво
## — рівно на той юніт, який вона описує (танк зникав під власними
## характеристиками разом зі своєю HP-смугою). Правильна поведінка — стати з
## ІНШОГО боку від юніта, і лише потім затискатись у поля безпеки.
##
## Перевіряється зовнішня правда, а не формула коду: точка прив'язки береться
## тим самим публічним unproject() рига, а далі стверджується геометрія —
## прямокутник панелі не сміє містити цю точку.
func test_inspector_flips_to_the_other_side_instead_of_covering_its_own_unit() -> void:
	var state: BattleState = _state()
	var u: Unit = state.add_unit(5, 0, Vector2i(6, 6), 0)
	var rig: IsoCameraRig = _rig_for(u)
	hud.bind(state)
	hud.attach_camera(rig)
	hud.show_selection(u)

	# Відводимо камеру до упору так, щоб юніт поїхав до правого краю екрана.
	for i in 50:
		rig.pan(Vector2(2000.0, 0.0))

	var anchor: Vector2 = rig.unproject(
		IsoCameraRig.cell_to_world(u.pos) + Vector3(0.0, Hud.INSPECTOR_LIFT, 0.0))
	var panel := Rect2(_inspector().position, _inspector().size)
	assert_gt(anchor.x + Hud.INSPECTOR_GAP + panel.size.x,
		hud.size.x - SAFE_RIGHT,
		"передумова: юніт мусить стояти так, щоб праворуч від нього панель уже не влазила")
	assert_false(panel.has_point(anchor),
		"панель %s накрила точку прив'язки власного юніта %s — вона мусила стати з іншого боку" % [panel, anchor])
	assert_lt(panel.end.x, anchor.x,
		"панель мусить цілком лежати ЛІВІШЕ юніта, коли праворуч місця нема")


## Знахідка ревʼю, і найдорожча з усіх: нижньою межею клемпа був НИЗ поля
## безпеки, а рядок дій живе всередині нього. Панель малюється поверх усього
## HUD, тож «влізла в безпечну зону» й «не накрила кнопки» — різні твердження,
## і перше було істинним саме тоді, коли друге хибне. Ціна: кнопка підтвердження
## — єдиний легальний шлях до дії (§6), і гравець, вибравши юніта в нижній
## частині кадру, тицяв би в неї наосліп.
##
## Юніт у дальньому кутку, камера — у протилежному: під ізо-ракурсом обидві
## додатні осі йдуть униз екрана, тож юніт гарантовано проєктується нижче
## рядка кнопок. Це і є передумова, і вона перевіряється явно — інакше тест
## лишався б зеленим, ніколи не діставши до самого клемпа.
func test_inspector_never_covers_the_action_buttons() -> void:
	var state: BattleState = _state()
	var u: Unit = state.add_unit(5, 0, Vector2i(11, 11), 0)
	var rig: IsoCameraRig = _rig_for(u)
	hud.bind(state)
	hud.attach_camera(rig)
	hud.show_selection(u)
	# Розкладка контейнерів рахується не миттєво, а клемп міряє реальний
	# прямокутник рядка кнопок.
	await get_tree().process_frame
	await get_tree().process_frame

	rig.center_on(Vector2i(0, 0))

	var bar: Control = hud.get_node("%BottomBar")
	var bar_top: float = bar.get_global_rect().position.y - hud.get_global_rect().position.y
	var anchor: Vector2 = rig.unproject(
		IsoCameraRig.cell_to_world(u.pos) + Vector3(0.0, Hud.INSPECTOR_LIFT, 0.0))
	var panel := Rect2(_inspector().position, _inspector().size)

	assert_gt(bar_top, 0.0, "передумова: розкладка порахована й рядок кнопок має власну висоту")
	assert_gt(anchor.y, bar_top,
		"передумова: юніт мусить проєктуватись НИЖЧЕ верху рядка кнопок, інакше клемп не задіяний")
	assert_lte(panel.end.y, bar_top,
		"панель %s заїхала на рядок кнопок (його верх — %s): кнопку підтвердження мусить бути видно" % [panel, bar_top])
