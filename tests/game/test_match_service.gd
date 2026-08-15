extends GutTest

var service: Node

func before_each() -> void:
	service = load("res://game/autoload/match_service.gd").new()
	add_child_autofree(service)
	service.start_match(Board.create(8, 8, Terrain.GroundState.DRY), 2, 1)

func test_rejected_command_produces_no_events() -> void:
	var enemy_unit: Unit = service.state.add_unit(5, 1, Vector2i(4, 4), 0)
	var err: String = service.submit(MoveCommand.create(enemy_unit.id, Vector2i(4, 5), -1))
	assert_ne(err, "", "чужий юніт не рухається")
	assert_eq(service.take_events().size(), 0, "відхилена команда не змінює нічого")

func test_accepted_command_queues_events() -> void:
	var u: Unit = service.state.add_unit(5, 0, Vector2i(4, 4), 0)
	assert_eq(service.submit(MoveCommand.create(u.id, Vector2i(4, 5), -1)), "")
	assert_true(service.take_events().size() > 0)
	assert_eq(service.take_events().size(), 0, "черга спорожняється після забору")

## §3.5/core/battle_state.gd:44 — без другої фази старту vision[p] для гравця,
## чий хід ще не наставав, лишається порожньою сіткою, і його юніти не можуть
## відповісти на постріл узагалі (FireCommand._retaliate() гейтить саме на
## state.vision[target.owner].is_seen(...)). begin() мусить це виправляти.
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
