extends GutTest

func _populated_state() -> BattleState:
	var b: Board = Board.create(8, 8, Terrain.GroundState.MUD)
	b.set_kind(Vector2i(3, 3), Terrain.Kind.FOREST)
	b.set_kind(Vector2i(4, 4), Terrain.Kind.BRIDGE)
	var s: BattleState = BattleState.create(b, 3, 1234)
	s.add_unit(5, 0, Vector2i(1, 1), 3)
	s.add_unit(1, 1, Vector2i(6, 6), 5)
	s.add_unit(11, 2, Vector2i(2, 6), 0)
	Mines.place(s, Vector2i(5, 5), 0)
	Objectives.add(s, Vector2i(4, 0), 1)
	s.experience[0].add_damage(UnitTypes.UnitClass.TANK, 1200)
	s.damage_dealt = [1200, 0, 90] as Array[int]
	s.turn_number = 4
	s.active_player = 2
	return s

func test_round_trip_preserves_everything() -> void:
	var a: BattleState = _populated_state()
	var b: BattleState = BattleSerializer.from_dict(BattleSerializer.to_dict(a))
	assert_eq(b.board.width, a.board.width)
	assert_eq(b.board.ground_state, a.board.ground_state)
	assert_eq(b.board.kind_at(Vector2i(3, 3)), Terrain.Kind.FOREST)
	assert_eq(b.units.size(), a.units.size())
	assert_eq(b.turn_number, 4)
	assert_eq(b.active_player, 2)
	assert_eq(b.mines.size(), 1)
	assert_eq(b.objectives.size(), 1)
	assert_eq(b.experience[0].level_of(UnitTypes.UnitClass.TANK), a.experience[0].level_of(UnitTypes.UnitClass.TANK))
	assert_eq(b.damage_dealt, [1200, 0, 90] as Array[int])

func test_a_save_without_damage_dealt_loads_as_zeros() -> void:
	var d: Dictionary = BattleSerializer.to_dict(_populated_state())
	d.erase("damage_dealt")
	var b: BattleState = BattleSerializer.from_dict(d)
	assert_eq(b.damage_dealt, [0, 0, 0] as Array[int], "старі збереження мусять відкриватися")

func test_objective_hold_target_round_trips() -> void:
	var a: BattleState = _populated_state()
	a.objective_hold_target = 5
	var b: BattleState = BattleSerializer.from_dict(BattleSerializer.to_dict(a))
	assert_eq(b.objective_hold_target, 5)

func test_unit_fields_survive() -> void:
	var a: BattleState = _populated_state()
	var assault: Unit = a.get_unit(2)
	assault.hp = 55
	assault.ap = 7
	assault.drones_left = 1
	assault.has_fired = true
	var b: BattleState = BattleSerializer.from_dict(BattleSerializer.to_dict(a))
	var restored: Unit = b.get_unit(2)
	assert_eq(restored.hp, 55)
	assert_eq(restored.ap, 7)
	assert_eq(restored.drones_left, 1)
	assert_true(restored.has_fired)
	assert_eq(restored.facing, assault.facing)

func test_ap_before_retaliation_round_trips() -> void:
	var a: BattleState = _populated_state()
	a.get_unit(1).ap_before_retaliation = 28
	var b: BattleState = BattleSerializer.from_dict(BattleSerializer.to_dict(a))
	assert_eq(b.get_unit(1).ap_before_retaliation, 28)
	assert_eq(b.get_unit(2).ap_before_retaliation, -1, "юніт, що не відповідав, лишається без запису")

func test_a_save_without_ap_before_retaliation_loads_as_unset() -> void:
	var d: Dictionary = BattleSerializer.to_dict(_populated_state())
	for u_data in d["units"]:
		u_data.erase("ap_before_retaliation")
	var b: BattleState = BattleSerializer.from_dict(d)
	assert_not_null(b, "старі збереження мусять відкриватися")
	assert_eq(b.get_unit(1).ap_before_retaliation, -1)

func test_fog_is_restored_per_player() -> void:
	var a: BattleState = _populated_state()
	for p in a.player_count:
		a.refresh_vision(p)
	var b: BattleState = BattleSerializer.from_dict(BattleSerializer.to_dict(a))
	for p in a.player_count:
		assert_eq(b.vision[p].seen, a.vision[p].seen, "памʼять карти гравця %d" % p)

func test_rng_continues_where_it_stopped() -> void:
	var a: BattleState = _populated_state()
	for i in 17:
		Rules.roll(a.rng, 100)
	var expected: int = Rules.roll(a.rng, 100)
	for i in 17:
		pass
	var a2: BattleState = _populated_state()
	for i in 17:
		Rules.roll(a2.rng, 100)
	var b: BattleState = BattleSerializer.from_dict(BattleSerializer.to_dict(a2))
	assert_eq(Rules.roll(b.rng, 100), expected, "зберігається стан RNG, а не сід")

func test_save_and_load_a_file() -> void:
	var path := "user://test_save.json"
	var a: BattleState = _populated_state()
	assert_eq(BattleSerializer.save_to(a, path), OK)
	var b: BattleState = BattleSerializer.load_from(path)
	assert_not_null(b)
	assert_eq(b.units.size(), a.units.size())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func test_hidden_information_is_not_leaked_or_collapsed_on_round_trip() -> void:
	var a: BattleState = _populated_state()
	# Player 0 has explored a tile player 1 has not.
	a.vision[0].seen[0] = 1
	a.vision[1].seen[0] = 0
	a.vision[0].seen[5] = 0
	a.vision[1].seen[5] = 1
	# The mine is known only to its owner (player 0).
	var mine: Mines.Mine = a.mines[0]
	assert_true(mine.known_to[0])
	assert_false(mine.known_to[1])
	assert_false(mine.known_to[2])
	# The objective is seen only by player 2.
	var obj: Objectives.Objective = a.objectives[0]
	obj.seen_by[0] = false
	obj.seen_by[1] = false
	obj.seen_by[2] = true

	var b: BattleState = BattleSerializer.from_dict(BattleSerializer.to_dict(a))

	assert_eq(b.vision[0].seen[0], 1, "гравець 0 бачив тайл 0")
	assert_eq(b.vision[1].seen[0], 0, "гравець 1 не бачив тайл 0")
	assert_eq(b.vision[0].seen[5], 0, "гравець 0 не бачив тайл 5")
	assert_eq(b.vision[1].seen[5], 1, "гравець 1 бачив тайл 5")

	var restored_mine: Mines.Mine = b.mines[0]
	assert_true(restored_mine.known_to[0], "власник знає про міну")
	assert_false(restored_mine.known_to[1], "гравець 1 не знає про міну")
	assert_false(restored_mine.known_to[2], "гравець 2 не знає про міну")

	var restored_obj: Objectives.Objective = b.objectives[0]
	assert_false(restored_obj.seen_by[0], "гравець 0 не бачив ціль")
	assert_false(restored_obj.seen_by[1], "гравець 1 не бачив ціль")
	assert_true(restored_obj.seen_by[2], "тільки гравець 2 бачив ціль")

func test_rng_state_round_trip_matches_fresh_draws() -> void:
	var a: BattleState = _populated_state()
	for i in 5:
		Rules.roll(a.rng, 1000)
	var saved: Dictionary = BattleSerializer.to_dict(a)
	var expected: Array[int] = []
	for i in 10:
		expected.append(Rules.roll(a.rng, 1000))

	var b: BattleState = BattleSerializer.from_dict(saved)
	var actual: Array[int] = []
	for i in 10:
		actual.append(Rules.roll(b.rng, 1000))

	assert_eq(actual, expected, "після відновлення RNG продовжує, а не перезапускає послідовність")

func test_to_dict_snapshot_is_immune_to_later_mutation() -> void:
	## to_dict() мусить копіювати кожен per-player масив, а не посилатись на живий.
	## Інакше знімок, узятий на ходу 3, тихо почне повідомляти про розкриття міни
	## чи елімінацію, що сталися на ходу 7 — той самий клас бага, що й витік туману,
	## лише через інші двері (реплей замість збереження).
	var a: BattleState = _populated_state()
	var snapshot: Dictionary = BattleSerializer.to_dict(a)

	var mine: Mines.Mine = a.mines[0]
	mine.known_to[1] = true
	a.objectives[0].seen_by[0] = true
	a.eliminated[1] = true
	var snap_xp: Array = (snapshot["experience"][0]["xp"] as Array).duplicate()
	var snap_level: Array = (snapshot["experience"][0]["level"] as Array).duplicate()
	a.experience[0].add_damage(UnitTypes.UnitClass.INFANTRY, 500)

	var snap_mine: Dictionary = snapshot["mines"][0]
	assert_false((snap_mine["known_to"] as Array)[1], "знімок не бачить пізнішого розкриття міни")
	var snap_obj: Dictionary = snapshot["objectives"][0]
	assert_false((snap_obj["seen_by"] as Array)[0], "знімок не бачить пізнішого виявлення цілі")
	assert_false((snapshot["eliminated"] as Array)[1], "знімок не бачить пізнішої елімінації")
	assert_eq(snapshot["experience"][0]["xp"], snap_xp, "знімок не бачить пізнішого набору досвіду")
	assert_eq(snapshot["experience"][0]["level"], snap_level, "знімок не бачить пізнішого підвищення рівня")

# --- Збереження, частини якого не погоджуються між собою, відкидається ------
#
# from_dict() повертає null, а не стан, що падає пізніше (check_elimination(),
# туман, get_type()). «Unexpected Errors» від GUT тут теж провал: відмова мусить
# бути тихою, без SCRIPT ERROR. Усі випадки — від справжнього збереження
# _populated_state() (3 гравці, дошка 8×8), зіпсованого рівно в одному місці.

func _save() -> Dictionary:
	# Через JSON, як із файла: числа приходять float, і перевірки мусять це приймати.
	return JSON.parse_string(JSON.stringify(BattleSerializer.to_dict(_populated_state())))

func _assert_rejected(d: Dictionary, why: String) -> void:
	assert_null(BattleSerializer.from_dict(d), why)

func test_a_valid_save_through_json_still_loads() -> void:
	assert_not_null(BattleSerializer.from_dict(_save()), "передумова: справжнє збереження відкривається")

func test_eliminated_shorter_than_player_count_is_rejected() -> void:
	var d: Dictionary = _save()
	d["eliminated"] = [false]
	_assert_rejected(d, "eliminated на 1 гравця при player_count 3 — раніше приймалось і падало в check_elimination()")

func test_vision_shorter_than_player_count_is_rejected() -> void:
	var d: Dictionary = _save()
	d["vision"] = [d["vision"][0]]
	_assert_rejected(d, "vision на 1 гравця при player_count 3")

func test_experience_shorter_than_player_count_is_rejected() -> void:
	var d: Dictionary = _save()
	d["experience"] = [d["experience"][0]]
	_assert_rejected(d, "experience на 1 гравця")

func test_damage_dealt_of_the_wrong_size_is_rejected() -> void:
	var d: Dictionary = _save()
	d["damage_dealt"] = [1, 2]
	_assert_rejected(d, "damage_dealt на 2 гравців при player_count 3")

func test_mine_known_to_of_the_wrong_size_is_rejected() -> void:
	var d: Dictionary = _save()
	d["mines"][0]["known_to"] = [true]
	_assert_rejected(d, "known_to міни на 1 гравця")

func test_objective_seen_by_of_the_wrong_size_is_rejected() -> void:
	var d: Dictionary = _save()
	d["objectives"][0]["seen_by"] = [true, false]
	_assert_rejected(d, "seen_by цілі на 2 гравців")

func test_tiles_not_matching_the_board_size_are_rejected() -> void:
	var d: Dictionary = _save()
	(d["board"]["tiles"] as Array).pop_back()
	_assert_rejected(d, "63 тайли на дошці 8×8")

func test_a_vision_grid_not_matching_the_board_size_is_rejected() -> void:
	var d: Dictionary = _save()
	(d["vision"][1]["seen"] as Array).pop_back()
	_assert_rejected(d, "сітка seen на 63 клітинки при дошці 8×8")

func test_active_player_out_of_range_is_rejected() -> void:
	var d: Dictionary = _save()
	d["active_player"] = 3
	_assert_rejected(d, "active_player 3 при трьох гравцях (0..2)")
	d["active_player"] = -1
	_assert_rejected(d, "active_player −1")

func test_an_unknown_unit_type_is_rejected() -> void:
	var d: Dictionary = _save()
	d["units"][0]["type_id"] = 99
	_assert_rejected(d, "type_id 99 немає в ростері")

func test_a_facing_out_of_range_is_rejected() -> void:
	var d: Dictionary = _save()
	d["units"][0]["facing"] = 8
	_assert_rejected(d, "facing 8 — поза 0..7")

func test_a_missing_board_is_rejected() -> void:
	var d: Dictionary = _save()
	d.erase("board")
	_assert_rejected(d, "без board")

func test_units_of_the_wrong_type_are_rejected() -> void:
	var d: Dictionary = _save()
	d["units"] = "units"
	_assert_rejected(d, "units — рядок, а не масив")

func test_a_unit_missing_a_field_is_rejected() -> void:
	var d: Dictionary = _save()
	(d["units"][0] as Dictionary).erase("hp")
	_assert_rejected(d, "юніт без hp")

func test_a_scalar_of_the_wrong_type_is_rejected() -> void:
	var d: Dictionary = _save()
	d["player_count"] = "3"
	_assert_rejected(d, "player_count рядком")

func test_a_unit_owner_out_of_range_is_rejected() -> void:
	var d: Dictionary = _save()
	d["units"][0]["owner"] = 3
	_assert_rejected(d, "власник 3 при трьох гравцях")

# _populated_state(): юніти 1 (1,1), 2 (6,6), 3 (2,6), next_unit_id 4.

func test_duplicate_unit_ids_are_rejected() -> void:
	var d: Dictionary = _save()
	d["units"][1]["id"] = 1
	_assert_rejected(d, "два юніти з id 1 — другий мовчки затер би першого в словнику units")

func test_two_living_units_on_one_tile_are_rejected() -> void:
	var d: Dictionary = _save()
	d["units"][1]["x"] = 1
	d["units"][1]["y"] = 1
	_assert_rejected(d, "двоє живих на (1,1) — unit_at() бачив би лише одного")

func test_a_dead_unit_may_share_a_tile_with_a_living_one() -> void:
	# Мертві лишаються в units (уламки), тож тайл під ними займає хтось інший законно.
	var d: Dictionary = _save()
	d["units"][1]["x"] = 1
	d["units"][1]["y"] = 1
	d["units"][1]["hp"] = 0
	assert_not_null(BattleSerializer.from_dict(d))

func test_next_unit_id_not_above_every_id_is_rejected() -> void:
	var d: Dictionary = _save()
	d["next_unit_id"] = 3
	_assert_rejected(d, "next_unit_id 3 при наявному id 3 — наступний add_unit() видав би той самий id")
