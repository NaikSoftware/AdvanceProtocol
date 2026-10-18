extends GutTest
## Task 4.6: шар цілей малює лише те, що спостерігач уже розвідав (§3.5, §3.10).

var layer: ObjectiveView
var state: BattleState


func before_each() -> void:
	layer = ObjectiveView.new()
	add_child_autofree(layer)
	state = BattleState.create(Board.create(8, 8, Terrain.GroundState.DRY), 2, 7)


func test_unseen_objective_not_drawn() -> void:
	Objectives.add(state, Vector2i(2, 2), -1)
	layer.rebuild(state, 0)
	assert_null(layer.marker_at(Vector2i(2, 2)))
	assert_eq(layer.get_child_count(), 0)


func test_neutral_owned_destroyed_states_distinct() -> void:
	for i in 3:
		Objectives.add(state, Vector2i(i, 0), [-1, 0, 1][i])
	var destroyed: int = Objectives.add(state, Vector2i(3, 0), 1)
	state.objectives[destroyed].intact = false
	for o in state.objectives:
		o.seen_by[0] = true
	layer.rebuild(state, 0)
	assert_eq(layer.marker_state(Vector2i(0, 0)), {"owner": -1, "intact": true})
	assert_eq(layer.marker_state(Vector2i(1, 0)), {"owner": 0, "intact": true})
	assert_eq(layer.marker_state(Vector2i(3, 0)), {"owner": 1, "intact": false})
	var neutral: MeshInstance3D = layer.marker_at(Vector2i(0, 0))
	var own: MeshInstance3D = layer.marker_at(Vector2i(1, 0))
	var enemy: MeshInstance3D = layer.marker_at(Vector2i(2, 0))
	var dead: MeshInstance3D = layer.marker_at(Vector2i(3, 0))
	assert_eq(neutral.material_override.albedo_color, Color("8a8a8a"))
	assert_eq(own.material_override.albedo_color, UnitView.PLAYER_COLORS[0])
	assert_eq(enemy.material_override.albedo_color, UnitView.PLAYER_COLORS[1])
	assert_ne(dead.mesh, enemy.mesh, "зруйнована ціль — окремий меш")
	assert_ne(dead.material_override, enemy.material_override, "і окремий матеріал")


func test_objective_layer_rebuilt_for_incoming_player() -> void:
	Objectives.add(state, Vector2i(4, 4), -1)
	state.objectives[0].seen_by[0] = true
	layer.rebuild(state, 0)
	assert_not_null(layer.marker_at(Vector2i(4, 4)))
	layer.rebuild(state, 1)
	assert_null(layer.marker_at(Vector2i(4, 4)))
	assert_eq(layer.get_child_count(), 0)
