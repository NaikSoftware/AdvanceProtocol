class_name MatchSetup
extends Control
## Task 3.3: налаштування матчу (скелет). Обирається кількість гравців (2/3),
## карта зі списку maps/, стан ґрунту й кольори гравців.
##
## Сід на екрані НЕ показується: він генерується випадково під капотом при
## старті матчу (детермінізм лишається — крок логіки Task 3.3). Гравцеві в
## хот-сит сирий сід не потрібен.
##
## Скелет: розкладка й вибір працюють; фактичний виклик
## MatchService.start_match(map.to_board(), players, seed) з тестом на те, що
## сід потрапляє в state.seed_value — окремий крок Task 3.3, не цей скелет.

const MAPS_DIR: String = "res://maps"

@onready var _map_options: OptionButton = %MapOptions
var _map_paths: Array[String] = []


func _ready() -> void:
	_populate_maps()
	%BackButton.pressed.connect(SceneRouter.goto_main_menu)
	%StartButton.pressed.connect(_on_start_pressed)


func _populate_maps() -> void:
	_map_paths.clear()
	_map_options.clear()
	var dir: DirAccess = DirAccess.open(MAPS_DIR)
	if dir == null:
		return
	for file in dir.get_files():
		# .tres у редакторі, .tres.remap у експортованій збірці — беремо базове ім'я.
		var map_name: String = file.trim_suffix(".remap")
		if not map_name.ends_with(".tres"):
			continue
		_map_paths.append("%s/%s" % [MAPS_DIR, map_name])
		_map_options.add_item(map_name.trim_suffix(".tres"))


func _on_start_pressed() -> void:
	# Реальний старт (MatchService + інʼєкція карти в бій, сід випадковий) — крок
	# логіки Task 3.3. Скелет веде в бій, щоб потік був клікабельним для апруву UX.
	SceneRouter.goto_battle()
