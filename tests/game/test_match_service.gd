extends GutTest

var service: Node

func before_each() -> void:
	service = load("res://game/autoload/match_service.gd").new()
	add_child_autofree(service)
	service.start_match(Board.create(8, 8, Terrain.GroundState.DRY), 2, 1)

func test_rejected_command_produces_no_events() -> void:
	var enemy_unit: Unit = service.state.add_unit(5, 1, Vector2i(4, 4), 0)
	var err: String = service.submit(MoveCommand.create(enemy_unit.id, Vector2i(4, 5)))
	assert_ne(err, "", "чужий юніт не рухається")
	assert_eq(service.take_events().size(), 0, "відхилена команда не змінює нічого")

func test_accepted_command_queues_events() -> void:
	var u: Unit = service.state.add_unit(5, 0, Vector2i(4, 4), 0)
	assert_eq(service.submit(MoveCommand.create(u.id, Vector2i(4, 5))), "")
	assert_true(service.take_events().size() > 0)
	assert_eq(service.take_events().size(), 0, "черга спорожняється після забору")

## §3.5/core/battle_state.gd start() — без другої фази старту vision[p] для гравця,
## чий хід ще не наставав, лишається порожньою сіткою. begin() мусить це виправляти.
func test_begin_primes_vision_for_every_player_and_starts_first_turn() -> void:
	var p0_unit: Unit = service.state.add_unit(5, 0, Vector2i(1, 1), 0)
	var p1_unit: Unit = service.state.add_unit(5, 1, Vector2i(6, 6), 0)

	service.begin()

	var events: Array[Events.BattleEvent] = service.take_events()
	var has_turn_started := false
	for e in events:
		if e is Events.TurnStarted:
			has_turn_started = true
	assert_true(has_turn_started, "begin() кладе TurnStarted у чергу")

	# Гравець 0 діє першим — його видимість очевидно свіжа.
	assert_true(service.state.vision[0].is_seen(p0_unit.pos), "видимість гравця 0 навколо його юніта")
	assert_true(service.state.vision[0].is_seen(p0_unit.pos + Vector2i(1, 0)), "ромб огляду гравця 0 ширший за один тайл")

	# Гравець 1 ще не ходив — саме той випадок, який без start() лишався б сліпим.
	assert_true(service.state.vision[1].is_seen(p1_unit.pos), "видимість гравця 1 навколо його юніта, хоч його хід ще не настав")
	assert_true(service.state.vision[1].is_seen(p1_unit.pos + Vector2i(1, 0)), "ромб огляду гравця 1 ширший за один тайл")


# --- повтор ходів противників ---

func _replay_match() -> void:
	service.state.add_unit(5, 0, Vector2i(1, 1), 0)
	service.state.add_unit(5, 1, Vector2i(5, 1), 0)
	service.begin()
	service.take_events()


func _played_turn() -> void:
	_replay_match()
	var mover: Unit = service.state.units_of(0)[0]
	assert_eq(service.submit(MoveCommand.create(mover.id, Vector2i(2, 1))), "")
	assert_eq(service.submit(EndTurnCommand.create()), "")


func _tmp_path() -> String:
	return "user://test_match_service_%d_%d.json" % [Time.get_ticks_usec(), randi()]


func _cleanup(path: String) -> void:
	service.delete_save(path)


func test_replay_for_second_player_after_first_turn() -> void:
	_played_turn()
	var r: ReplayFilter.Result = service.replay_for(1)
	assert_not_null(r, "хід першого гравця видно другому")
	assert_true(_has_move(r, 1), "у повторі є рух юніта першого гравця")
	assert_null(service.replay_for(0), "першому нема чого повторювати: знімок свіжий")


func test_replay_survives_save_and_load() -> void:
	_played_turn()
	var path: String = _tmp_path()
	assert_eq(service.save_current(path), OK)
	var loaded: Node = load("res://game/autoload/match_service.gd").new()
	add_child_autofree(loaded)
	assert_true(loaded.load_saved(path))
	var r: ReplayFilter.Result = loaded.replay_for(1)
	_cleanup(path)
	assert_not_null(r)
	assert_eq(r.beats.size(), service.replay_for(1).beats.size())
	assert_true(_has_move(r, 1))


func test_old_save_without_sidecar_loads_with_no_replay() -> void:
	_played_turn()
	var path: String = _tmp_path()
	service.save_current(path)
	DirAccess.remove_absolute(path + ".replay")
	var loaded: Node = load("res://game/autoload/match_service.gd").new()
	add_child_autofree(loaded)
	assert_true(loaded.load_saved(path))
	_cleanup(path)
	assert_null(loaded.replay_for(1))


func test_corrupt_sidecar_loads_with_no_replay() -> void:
	_played_turn()
	var path: String = _tmp_path()
	service.save_current(path)
	var f: FileAccess = FileAccess.open(path + ".replay", FileAccess.WRITE)
	f.store_string("{ not json")
	f.close()
	var loaded: Node = load("res://game/autoload/match_service.gd").new()
	add_child_autofree(loaded)
	assert_true(loaded.load_saved(path))
	_cleanup(path)
	assert_null(loaded.replay_for(1))


func test_delete_save_removes_sidecar() -> void:
	_played_turn()
	var path: String = _tmp_path()
	service.save_current(path)
	assert_true(FileAccess.file_exists(path + ".replay"))
	service.delete_save(path)
	assert_false(FileAccess.file_exists(path + ".replay"))


func test_rejected_command_is_not_recorded() -> void:
	_replay_match()
	var theirs: Unit = service.state.units_of(1)[0]
	assert_ne(service.submit(MoveCommand.create(theirs.id, Vector2i(5, 2))), "")
	assert_eq(service.replay_log.to_dict()["commands"].size(), 0, "відхилена команда не потрапила в журнал")
	assert_eq(service.replay_log.span(1).size(), 0)


func _has_move(r: ReplayFilter.Result, unit_id: int) -> bool:
	for b in r.beats:
		for e in b.events:
			if e is Events.UnitMoved and e.unit_id == unit_id:
				return true
	return false


func _write_sidecar(path: String, text: String) -> void:
	var f: FileAccess = FileAccess.open(path + ".replay", FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _load_fresh(path: String) -> Node:
	var loaded: Node = load("res://game/autoload/match_service.gd").new()
	add_child_autofree(loaded)
	assert_true(loaded.load_saved(path))
	return loaded


func test_stale_sidecar_loads_with_no_replay() -> void:
	_replay_match()
	var mover: Unit = service.state.units_of(0)[0]
	service.submit(MoveCommand.create(mover.id, Vector2i(2, 1)))
	var path: String = _tmp_path()
	service.save_current(path)
	var early: String = FileAccess.get_file_as_string(path + ".replay")
	service.submit(EndTurnCommand.create())
	service.save_current(path)
	_write_sidecar(path, early)  # сайдкар з раніших часів того ж матчу
	var loaded: Node = _load_fresh(path)
	_cleanup(path)
	assert_null(loaded.replay_for(1))
	assert_eq(loaded.replay_log.to_dict()["commands"].size(), 0)


func test_sidecar_failing_from_dict_loads_with_no_replay() -> void:
	_played_turn()
	var path: String = _tmp_path()
	service.save_current(path)
	_write_sidecar(path, "{\"base\": 0}")
	var loaded: Node = _load_fresh(path)
	_cleanup(path)
	assert_null(loaded.replay_for(1))


func test_begin_marks_every_non_active_player() -> void:
	service.start_match(Board.create(8, 8, Terrain.GroundState.DRY), 3, 1)
	for p in 3:
		service.state.add_unit(5, p, Vector2i(1 + p, 1), 0)
	service.begin()
	var snaps: Dictionary = service.replay_log.to_dict()["snapshots"]
	assert_false(snaps.has("0"), "активний гравець без знімка")
	assert_true(snaps.has("1") and snaps.has("2"))


func test_concede_is_marked_before_apply() -> void:
	_replay_match()
	assert_eq(service.submit(ConcedeCommand.create()), "")
	var snaps: Dictionary = service.replay_log.to_dict()["snapshots"]
	assert_true(snaps.has("0"), "знімок гравця, що здався")
	var snap_state: BattleState = service.replay_log.start_state(0)
	assert_eq(snap_state.units_of(0).size(), 1)
	assert_gt(snap_state.units_of(0)[0].hp, 0, "знімок узято до знищення юнітів")


func test_start_match_resets_the_log() -> void:
	_played_turn()
	assert_gt(service.replay_log.to_dict()["commands"].size(), 0)
	service.start_match(Board.create(8, 8, Terrain.GroundState.DRY), 2, 1)
	assert_eq(service.replay_log.to_dict()["commands"].size(), 0)
	assert_eq(service.replay_log.to_dict()["snapshots"].size(), 0)
