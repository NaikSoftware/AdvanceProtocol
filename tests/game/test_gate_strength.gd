extends GutTest
## Сила команд на гейті передачі ходу. Вигляд лише переводить цілі HP з ядра в довжини:
## кожне очікуване значення тут рахується з тих самих чисел, а не з нічого.

const GateScene := preload("res://game/ui/handover_gate.tscn")

var gate: HandoverGate
var strength: GateStrength


func before_each() -> void:
	gate = GateScene.instantiate()
	add_child_autofree(gate)
	strength = gate.get_node("%Strength") as GateStrength


func _state(players: int) -> BattleState:
	var s: BattleState = BattleState.create(Board.create(12, 12, Terrain.GroundState.DRY), players, 3)
	for p in players:
		# Два юніти на гравця: загибель одного лишає живого, тож гравець ще «в грі».
		s.add_unit(2, p, Vector2i(1 + p * 3, 1), 2)
		s.add_unit(2, p, Vector2i(1 + p * 3, 2), 2)
	s.start()
	return s


func _show(state: BattleState, player: int = 0) -> void:
	gate.show_for(player, 1, state)
	await wait_process_frames(2)


func _hurt(s: BattleState, player: int, share: float) -> void:
	for u in s.units_of(player):
		u.hp = int(round(u.max_hp() * share))


func test_two_players_solid_lengths_follow_core_shares() -> void:
	var s: BattleState = _state(2)
	_hurt(s, 0, 0.7)
	_hurt(s, 1, 0.45)
	await _show(s)

	assert_eq(strength.mode, GateStrength.Mode.TWO)
	var row: Rect2 = Rect2(gate.get_node("%Horizon").get_parent().global_position - gate.global_position, (gate.get_node("%Horizon").get_parent() as Control).size)
	var slide: Control = gate.get_node("%NameSlide") as Control
	var left_len: float = slide.global_position.x - gate.global_position.x - row.position.x
	var right_len: float = row.end.x - (slide.global_position.x - gate.global_position.x + slide.size.x)
	assert_gt(left_len, 100.0, "передумова: лінії мають довжину")
	assert_almost_eq(strength.solid_rects[0].size.x, left_len * s.team_hp_share_of_start(0), 0.001)
	assert_almost_eq(strength.solid_rects[1].size.x, right_len * s.team_hp_share_of_start(1), 0.001)
	assert_almost_eq(s.team_hp_share_of_start(0), 0.7, 0.02)
	assert_almost_eq(s.team_hp_share_of_start(1), 0.45, 0.02)
	assert_eq(strength.solid_rects[0].size.y, 2.0, "лінія 2 dp")
	# Суцільне тягнеться від плити назовні: ліве закінчується на лівому краї плити, праве починається на правому.
	assert_almost_eq(strength.solid_rects[0].end.x, slide.global_position.x - gate.global_position.x, 0.001)
	assert_almost_eq(strength.solid_rects[1].position.x, slide.global_position.x - gate.global_position.x + slide.size.x, 0.001)
	assert_eq(strength.square_rects[0].size, Vector2(8, 8))


func test_two_players_hide_the_horizon_and_keep_nameplate_colour_of_the_incoming_player() -> void:
	await _show(_state(2), 1)

	assert_false((gate.get_node("%Horizon") as Control).visible, "горизонт замінено двома лініями")
	assert_eq((gate.get_node("%RuleTop") as ColorRect).color, UnitView.PLAYER_COLORS[1])


func test_two_player_lines_wipe_with_the_entrance_tween() -> void:
	gate.show_for(0, 1, _state(2))

	assert_lt(strength.scale.x, 0.001, "у першому кадрі лінії ще згорнуті, як і горизонт")
	gate.entrance_tween.custom_step(HandoverGate.ENTRANCE_S + 0.01)
	assert_eq(strength.scale.x, 1.0)


func test_three_players_keep_the_horizon_in_the_incoming_players_colour() -> void:
	await _show(_state(3), 2)

	var horizon: ColorRect = gate.get_node("%Horizon") as ColorRect
	assert_true(horizon.visible)
	assert_eq(horizon.color, Color(UnitView.PLAYER_COLORS[2], 0.7))
	assert_eq(strength.mode, GateStrength.Mode.THREE)
	assert_eq(strength.scale.x, 1.0, "смуга трійки не розкривається")


func test_three_players_segment_widths_follow_team_hp_and_fill_the_plate() -> void:
	var s: BattleState = _state(3)
	_hurt(s, 0, 0.8)
	_hurt(s, 1, 0.4)
	_hurt(s, 2, 1.0)
	await _show(s)

	var plate: Control = gate.get_node("%InfoPlate") as Control
	var total: int = s.team_hp(0) + s.team_hp(1) + s.team_hp(2)
	var usable: float = plate.size.x - 2.0 * GateStrength.BAR_GAP
	assert_eq(strength.segment_rects.size(), 3)
	var sum: float = 0.0
	for i in 3:
		assert_almost_eq(strength.segment_rects[i].size.x, usable * float(s.team_hp(i)) / float(total), 0.001)
		assert_eq(strength.segment_rects[i].size.y, 4.0)
		assert_eq(strength.segment_players[i], i)
		sum += strength.segment_rects[i].size.x
	assert_almost_eq(sum, usable, 0.001, "сума сегментів = ширина плити мінус проміжки")
	assert_almost_eq(strength.segment_rects[0].position.x, plate.global_position.x - gate.global_position.x, 0.001)
	assert_almost_eq(strength.segment_rects[2].end.x, plate.global_position.x - gate.global_position.x + plate.size.x, 0.001)
	assert_almost_eq(strength.segment_rects[0].end.y, plate.global_position.y - gate.global_position.y + plate.size.y, 0.001, "по нижньому краю плити")


func test_eliminated_player_has_no_segment() -> void:
	var s: BattleState = _state(3)
	for u in s.units_of(1):
		u.hp = 0
	s.eliminated[1] = true
	await _show(s)

	assert_eq(strength.segment_players, [0, 2] as Array[int])
	assert_eq(strength.segment_rects.size(), 2)


func test_no_state_draws_no_strength() -> void:
	gate.show_for(0, 1)

	assert_false(strength.visible)
	assert_true((gate.get_node("%Horizon") as Control).visible)


func test_strength_has_no_text_or_icons_and_the_pause_menu_has_none() -> void:
	await _show(_state(2))
	for n in strength.find_children("*", "", true, false):
		assert_false(n is Label or n is TextureRect, "під елементом сили немає підписів чи значків")
	assert_eq(strength.get_child_count(), 0)

	var pause: Node = (preload("res://game/ui/pause_menu.tscn") as PackedScene).instantiate()
	add_child_autofree(pause)
	assert_null(pause.find_child("Strength", true, false))
	assert_eq(pause.find_children("*", "GateStrength", true, false).size(), 0)
