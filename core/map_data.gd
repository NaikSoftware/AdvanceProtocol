class_name MapData
extends Resource
## Дані готової карти (Task 2.10): тайли, старт юнітів, цілі. Ресурс, не Node —
## §6 забороняє лише вузли Godot під core/, а Resource лишається чистими даними
## без дерева сцени, тож правило не порушене.
##
## Дві функції, дві відповідальності: to_board() виробляє Board — саму лише
## геометрію (§3.1), populate() наповнює вже створений BattleState — юнітів і
## цілі. Жодна з них не створює BattleState сама: це робить MatchService.start_match()
## окремим кроком (R1, task-2.10-brief.md), а populate() лише додає в те, що вже є.

## §3.12: ґрунт — правило, а не декор, тож одне значення на карту.
@export var width: int = 0
@export var height: int = 0
@export var ground_state: int = Terrain.GroundState.DRY
## Плаский масив виду тайлу, індекс y*width+x — той самий порядок, що й
## Board._index(), тож перенесення в to_board() лишається прямим копіюванням.
@export var tiles: PackedInt32Array = PackedInt32Array()
## Кожен запис: {"type_id": int, "owner": int, "pos": Vector2i, "facing": int}.
@export var spawns: Array[Dictionary] = []
## §3.10: до 15 позначок на карту; карта задає лише позиції — нейтральними,
## володіння вирішує гра, не дані карти.
@export var objectives: Array[Vector2i] = []
## 0 — на цій карті немає умови перемоги за цілі (той самий дефолт, що й
## BattleState.objective_hold_target, core/battle_state.gd:24-27).
@export var hold_target: int = 0
## Ключ перекладу назви карти (§9 — жодних хардкод-рядків), не сам текст.
@export var name_key: String = ""


func to_board() -> Board:
	var board: Board = Board.create(width, height, ground_state)
	assert(tiles.size() == width * height,
		"MapData.tiles (%d) не збігається з width*height (%d)" % [tiles.size(), width * height])
	if tiles.size() == width * height:
		board.tiles = tiles.duplicate()
	return board


func populate(state: BattleState) -> void:
	for spawn in spawns:
		state.add_unit(
			int(spawn["type_id"]),
			int(spawn["owner"]),
			spawn["pos"] as Vector2i,
			int(spawn.get("facing", 0))
		)
	for pos in objectives:
		# owner -1: нейтральна ціль (Objectives.Objective, core/objectives.gd) —
		# карта заявляє лише де вони стоять, не хто ними володіє на старті.
		Objectives.add(state, pos, -1)
	state.objective_hold_target = hold_target
