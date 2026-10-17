class_name MatchSetup
extends Control
## Task 3.3: налаштування матчу. Обирається кількість гравців (2/3),
## карта зі списку maps/, стан ґрунту й кольори гравців.
##
## Сід на екрані НЕ показується: він генерується випадково під капотом при
## старті матчу (детермінізм лишається — крок логіки Task 3.3). Гравцеві в
## хот-сит сирий сід не потрібен.
##
## Колір гравців на екрані поки лише показується: у бойовому вигляді його ніхто
## не споживає, тож у конфіг він не йде.

const MAPS_DIR: String = "res://maps"

@onready var _map_options: OptionButton = %MapOptions
var _map_paths: Array[String] = []


func _ready() -> void:
	_populate_maps()
	_map_options.item_selected.connect(func(_i: int) -> void: _sync_player_options())
	_sync_player_options()
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


## Тримачі гравців — не з карти, а з її спавнів: мапа без юнітів третього
## гравця не дає запустити матч утрьох (гравець без юнітів — безглуздя).
func _sync_player_options() -> void:
	var can3: bool = _selected_map_supports_3()
	%P3.disabled = not can3
	if not can3 and %P3.button_pressed:
		%P2.button_pressed = true


func _selected_map_supports_3() -> bool:
	if _map_paths.is_empty():
		return false
	var map: MapData = load(_map_paths[_map_options.selected]) as MapData
	var owners: Dictionary = {}
	for spawn in map.spawns:
		owners[int(spawn["owner"])] = true
	return owners.has(0) and owners.has(1) and owners.has(2)


func _on_start_pressed() -> void:
	if configure_from_choice(MatchService):
		# Новий матч витісняє старе збереження: інакше «Продовжити» після виходу
		# з нового, незбереженого матчу відновило б зовсім інший.
		MatchService.delete_save(MatchService.SAVE_PATH)
		SceneRouter.goto_battle()


## Переносить вибір гравця в сервіс; сід випадковий (configure без сіда).
func configure_from_choice(service: Node) -> bool:
	if _map_paths.is_empty():
		return false
	if _chosen_players() == 3 and not _selected_map_supports_3():
		return false
	service.configure(_map_paths[_map_options.selected], _chosen_players(), _chosen_ground())
	return true


func _chosen_players() -> int:
	return 3 if %P3.button_pressed else 2


func _chosen_ground() -> int:
	if %Mud.button_pressed:
		return Terrain.GroundState.MUD
	if %Frozen.button_pressed:
		return Terrain.GroundState.FROZEN
	return Terrain.GroundState.DRY
