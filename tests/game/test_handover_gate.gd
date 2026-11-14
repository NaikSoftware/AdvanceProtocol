extends GutTest
## Task 2.9: гейт передачі пристрою. Це функція коректності (§3.5, §1.2), не
## декор — перевіряється не «вузол існує», а що саме гравець НЕ може побачити
## і що жодна дія, крім явного натискання, не може відкрити хід.
##
## Камера і перебудова юнітів під нове `seen` (Task 2.10) тут не
## перевіряються — контейнер юнітів і жива battle_screen.tscn з'являються
## лише там. Контракт порядку задокументований у самому handover_gate.gd, і
## Task 2.10 має його виконати.

const GateScene := preload("res://game/ui/handover_gate.tscn")

var gate: HandoverGate
var _orig_locale: String


func before_each() -> void:
	_orig_locale = TranslationServer.get_locale()
	gate = GateScene.instantiate()
	add_child_autofree(gate)


func after_each() -> void:
	TranslationServer.set_locale(_orig_locale)


## Твін входу (350 мс) докручуємо вручну: реального часу тест не чекає.
func _finish_entrance() -> void:
	gate.entrance_tween.custom_step(HandoverGate.ENTRANCE_S + 0.01)


# --- Крок 1: непрозора, повна, видима панель, ввід заблокований -----------

func test_show_for_makes_the_gate_visible() -> void:
	assert_false(gate.visible, "передумова: гейт не показаний, доки show_for не викликали")

	gate.show_for(0)

	assert_true(gate.visible)


func test_panel_is_fully_opaque_not_translucent() -> void:
	gate.show_for(0)

	var panel: ColorRect = gate.get_node("%Panel") as ColorRect
	assert_true(panel.visible, "панель мусить бути видимою частиною гейта")
	assert_eq(panel.color.a, 1.0, "панель мусить бути непрозорою — прозорість пропустила б попередню сцену")


func test_gate_covers_the_whole_viewport_not_a_corner_of_it() -> void:
	# Anchors 0..1 з нульовими offset'ами покривають будь-який розмір
	# viewport, а не лише той, що є під час тесту — так само надійніше, ніж
	# звіряти пікселі з get_viewport_rect() у headless.
	assert_eq(gate.anchor_left, 0.0)
	assert_eq(gate.anchor_top, 0.0)
	assert_eq(gate.anchor_right, 1.0)
	assert_eq(gate.anchor_bottom, 1.0)
	assert_eq(gate.offset_left, 0.0)
	assert_eq(gate.offset_top, 0.0)
	assert_eq(gate.offset_right, 0.0)
	assert_eq(gate.offset_bottom, 0.0)

	var panel: ColorRect = gate.get_node("%Panel") as ColorRect
	assert_eq(panel.anchor_left, 0.0)
	assert_eq(panel.anchor_top, 0.0)
	assert_eq(panel.anchor_right, 1.0)
	assert_eq(panel.anchor_bottom, 1.0)
	assert_eq(panel.offset_left, 0.0)
	assert_eq(panel.offset_top, 0.0)
	assert_eq(panel.offset_right, 0.0)
	assert_eq(panel.offset_bottom, 0.0)


func test_gate_blocks_input_from_reaching_whatever_is_underneath() -> void:
	# STOP (0), не IGNORE (2, той прийом, яким HUD навмисно пропускає клік
	# крізь себе, hud.tscn) — гейт мусить ловити ввід, а не пропускати його
	# до дошки під собою.
	assert_eq(gate.mouse_filter, Control.MOUSE_FILTER_STOP)
	var panel: ColorRect = gate.get_node("%Panel") as ColorRect
	assert_eq(panel.mouse_filter, Control.MOUSE_FILTER_STOP)


# --- Крок 2: confirmed лише від явного натискання ---------------------------

func test_confirmed_is_not_emitted_by_show_for() -> void:
	watch_signals(gate)

	gate.show_for(0)

	assert_signal_not_emitted(gate, "confirmed")


func test_confirmed_is_not_emitted_by_time_passing() -> void:
	watch_signals(gate)
	gate.show_for(0)

	for i in 30:
		simulate(gate, 1, 1.0 / 60.0)

	assert_signal_not_emitted(gate, "confirmed",
		"нічого, крім явного натискання, не сміє відкрити хід — жодного таймера тут немає")


func test_pressing_confirm_emits_confirmed_exactly_once() -> void:
	gate.show_for(0)
	watch_signals(gate)
	_finish_entrance()
	var button: Button = gate.get_node("%ConfirmButton") as Button

	button.pressed.emit()

	assert_signal_emit_count(gate, "confirmed", 1)


## Рев'ю рішення, знахідка 1: поки гейт видимий, Task 2.10 виконує
## рецентрування камери й перебудову вузлів (крок 2a/2b контракту) — і саме
## в це вікно кнопка лишається на екрані, увімкнена. Звичайний подвійний
## тап на телефоні не сміє відкрити хід двічі.
func test_second_press_before_show_for_is_called_again_emits_nothing_more() -> void:
	gate.show_for(0)
	watch_signals(gate)
	_finish_entrance()
	var button: Button = gate.get_node("%ConfirmButton") as Button

	button.pressed.emit()
	button.pressed.emit()
	button.pressed.emit()

	assert_signal_emit_count(gate, "confirmed", 1,
		"перше натискання мусить вимкнути кнопку — другий і третій дотик не мають довести до другого confirmed")
	assert_true(button.disabled, "кнопка мусить лишитись вимкненою після одного натискання")


func test_show_for_re_enables_the_confirm_button_for_the_next_player() -> void:
	gate.show_for(0)
	_finish_entrance()
	var button: Button = gate.get_node("%ConfirmButton") as Button
	button.pressed.emit()
	assert_true(button.disabled, "передумова: перше підтвердження вимкнуло кнопку")

	gate.show_for(1)

	assert_false(button.disabled, "новий show_for мусить дати наступному гравцеві новий шанс натиснути")


func test_confirmed_signal_carries_no_unexpected_extra_emissions_from_construction() -> void:
	# Інстанціація сцени сама по собі (before_each) не мусила нічого
	# надсилати — сигнал ще не спостерігався там, тож тут доводимо це чере
	# другий екземпляр, спостережений одразу.
	var fresh: HandoverGate = GateScene.instantiate()
	add_child_autofree(fresh)
	watch_signals(fresh)

	assert_signal_not_emitted(fresh, "confirmed")


# --- Немає кнопки «пропустити» ----------------------------------------------

func test_no_skip_or_dismiss_affordance_exists() -> void:
	var buttons: Array[Button] = []
	_collect_buttons(gate, buttons)

	assert_eq(buttons.size(), 1, "єдина кнопка на гейті — підтвердження; друга кнопка це і є непомічений шлях пропустити")
	assert_eq(buttons[0].name, "ConfirmButton")


func _collect_buttons(node: Node, out: Array[Button]) -> void:
	for child in node.get_children():
		if child is Button:
			out.append(child as Button)
		_collect_buttons(child, out)


# --- Оголошений гравець ------------------------------------------------------

func test_announced_player_is_the_one_passed_in() -> void:
	# Гравець 2 (індекс 2), навмисно не 0 — захардкоджене значення пройшло б
	# тест із типовим значенням і провалюється тут.
	gate.show_for(2)

	var player_value: Label = gate.get_node("%PlayerValue") as Label
	assert_eq(player_value.text, "%s 3" % tr("hud_player"), "показаний номер — 1-based")


func test_announced_player_updates_on_a_second_call() -> void:
	gate.show_for(0)
	assert_eq((gate.get_node("%PlayerValue") as Label).text, "%s 1" % tr("hud_player"))

	gate.show_for(1)

	assert_eq((gate.get_node("%PlayerValue") as Label).text, "%s 2" % tr("hud_player"))


# --- R29: жоден підпис не є захардкодженим рядком ---------------------------

func test_no_user_facing_label_is_a_hard_coded_literal() -> void:
	# Підписи, що їх show_for підставляє з tr(), тут не рахуються: перевіряється те, що написане у сцені.
	var texts: Array[String] = []
	_collect_texts(gate, texts)

	assert_gt(texts.size(), 1, "обхід дерева мусить справді щось знайти")
	var key_re := RegEx.create_from_string("^[a-z][a-z0-9_]*_[a-z0-9_]+$")
	var numeric_re := RegEx.create_from_string("^[0-9]+$")
	for text in texts:
		if text.is_empty():
			continue
		var ok: bool = key_re.search(text) != null or numeric_re.search(text) != null
		assert_true(ok, "«%s» — не ключ перекладу і не число (§9, R29)" % text)


func _collect_texts(node: Node, out: Array[String]) -> void:
	for child in node.get_children():
		if child is Label:
			out.append((child as Label).text)
		elif child is Button:
			out.append((child as Button).text)
		_collect_texts(child, out)


# --- Тапабельність і бюджет --------------------------------------------------

func test_confirm_button_is_at_least_48_dp_tall() -> void:
	var button: Button = gate.get_node("%ConfirmButton") as Button
	assert_true(button.custom_minimum_size.y >= 48.0,
		"кнопка нижча за 48 dp — палець у неї не влучить (§9)")


func test_gate_does_no_per_frame_work() -> void:
	assert_false(gate.is_processing(), "правила й показ не живуть у _process (§9)")
	assert_false(gate.is_physics_processing())


# --- «Field Tablet»: вхідний твін, фон, ширина ----------------------------------

func test_confirm_is_ignored_until_the_entrance_tween_ends() -> void:
	gate.show_for(0)
	watch_signals(gate)
	var button: Button = gate.get_node("%ConfirmButton") as Button

	button.pressed.emit()
	assert_signal_not_emitted(gate, "confirmed", "тап під час твіну не знімає гейт")
	assert_false(button.disabled, "проігнорований тап не вимикає кнопку")

	_finish_entrance()
	button.pressed.emit()
	assert_signal_emit_count(gate, "confirmed", 1)


func test_gate_is_opaque_from_the_first_frame_and_only_accents_animate() -> void:
	gate.show_for(1)

	assert_eq((gate.get_node("%Panel") as ColorRect).color, Color("0d1013"))
	assert_eq(gate.modulate.a, 1.0, "сам гейт ніколи не з'являється плавно")
	assert_almost_eq((gate.get_node("%RuleTop") as Control).scale.x, 0.0, 0.0001, "Godot не дає масштабу стати рівно 0")
	assert_eq((gate.get_node("%Nameplate") as Control).modulate.a, 0.0)

	_finish_entrance()
	assert_eq((gate.get_node("%RuleTop") as Control).scale.x, 1.0)
	assert_eq((gate.get_node("%Horizon") as Control).scale.x, 1.0)
	assert_eq((gate.get_node("%Nameplate") as Control).modulate.a, 1.0)
	assert_eq((gate.get_node("%Nameplate") as Control).position.y, 0.0)


func test_rules_use_the_incoming_players_colour() -> void:
	gate.show_for(1)

	assert_eq((gate.get_node("%RuleTop") as ColorRect).color, UnitView.PLAYER_COLORS[1])
	assert_eq((gate.get_node("%Horizon") as ColorRect).color, Color(UnitView.PLAYER_COLORS[1], 0.7))


func test_backdrop_plate_follows_the_map_resource_name_with_a_default_fallback() -> void:
	assert_eq(HandoverGate.plate_for("res://maps/river.tres").resource_path, "res://assets/ui/gate/river.webp")
	assert_eq(HandoverGate.plate_for("res://maps/ridge.tres").resource_path, "res://assets/ui/gate/ridge.webp")
	assert_eq(HandoverGate.plate_for("user://maps/new_one.tres").resource_path, "res://assets/ui/gate/default.webp")
	assert_eq(HandoverGate.plate_for("").resource_path, "res://assets/ui/gate/default.webp")


func test_info_plate_shows_turn_and_map_and_shares_its_width_with_the_nameplate() -> void:
	gate.set_context("res://maps/river.tres", "map_river")

	gate.show_for(0, 3)

	assert_eq((gate.get_node("%TurnValue") as Label).text, "3")
	assert_eq((gate.get_node("%MapValue") as Label).text, tr("map_river"))
	var info: Control = gate.get_node("%InfoPlate") as Control
	assert_eq((gate.get_node("%NameSlide") as Control).custom_minimum_size.x, info.custom_minimum_size.x)
	assert_eq(HandoverGate.MIN_WIDTH, 400.0)
	assert_gte(info.custom_minimum_size.x, 400.0)


## Стан ґрунту не показується ніде в інтерфейсі: ні вузла, ні підпису, ні значка.
static func _ground_text_or_icon(root: Node) -> Array[String]:
	var found: Array[String] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if "ground" in String(n.name).to_lower():
			found.append(String(n.name))
		var text: String = (n as Label).text if n is Label else ""
		if n is Button:
			text = (n as Button).text
		for w in ["ґрунт", "ground", "багно", "мерзлота", "mud", "frozen"]:
			if w in text.to_lower():
				found.append("%s: %s" % [n.name, text])
		if n is TextureRect and (n as TextureRect).texture != null and "ground" in (n as TextureRect).texture.resource_path:
			found.append("%s: %s" % [n.name, (n as TextureRect).texture.resource_path])
	return found


func test_gate_shows_no_ground_state() -> void:
	for lang in ["uk", "en"]:
		TranslationServer.set_locale(lang)
		gate.set_context("res://maps/river.tres", "map_river")
		gate.show_for(0, 3)
		assert_eq(_ground_text_or_icon(gate), [] as Array[String], "гейт, мова %s" % lang)
	var cells: Node = gate.get_node("%InfoPlate/Pad/Cells")
	assert_eq(cells.get_child_count(), 3, "[ХІД] | [КАРТА] без порожньої клітинки")
