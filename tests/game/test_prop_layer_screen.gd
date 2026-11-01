extends GutTest
## Окремий файл: кожна карта тут будується повним BattleScreen (~8 с), тож тест не вкладається
## до загального прогону test_prop_layer.gd.

const BattleScreenScene := preload("res://game/battle/battle_screen.tscn")
const MatchServiceScript := preload("res://game/autoload/match_service.gd")


func _map(name: String) -> MapData:
	return load("res://maps/%s.tres" % name) as MapData


## Сонячна карта вмикає тіні будівель, похмура River — ні.
func test_sunny_map_switches_structure_shadows_on(p = use_parameters([["crossroads", true], ["ridge", true], ["river", false]])) -> void:
	var service: Node = MatchServiceScript.new()
	add_child_autofree(service)
	var screen: BattleScreen = BattleScreenScene.instantiate()
	add_child_autofree(screen)
	screen.setup(_map(p[0]), 2, 1, service)
	assert_eq((screen.get_node("%BoardView") as BoardView).structure_shadows, p[1], p[0])
