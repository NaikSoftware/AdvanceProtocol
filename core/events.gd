class_name Events
extends RefCounted
## Усе, що core/ повідомляє вигляду. Жодних сигналів Godot — лише значення.

class BattleEvent extends RefCounted:
	func describe() -> String:
		return "BattleEvent"

class UnitMoved extends BattleEvent:
	var unit_id: int
	var path: Array[Vector2i]
	var facing: int
	func _init(p_unit_id: int, p_path: Array[Vector2i], p_facing: int) -> void:
		unit_id = p_unit_id
		path = p_path
		facing = p_facing
	func describe() -> String:
		return "UnitMoved(unit=%d, steps=%d, facing=%d)" % [unit_id, path.size(), facing]

class UnitTurned extends BattleEvent:
	var unit_id: int
	var facing: int
	func _init(p_unit_id: int, p_facing: int) -> void:
		unit_id = p_unit_id
		facing = p_facing
	func describe() -> String:
		return "UnitTurned(unit=%d, facing=%d)" % [unit_id, facing]

class MoveBlocked extends BattleEvent:
	## §3.2/§3.5: хід урвався ПЕРЕД тайлом, у який юніт не зміг увійти. Окремий клас,
	## а не висновок вигляду: інакше вигляд мусив би звіряти наказ гравця з довжиною
	## UnitMoved.path, щоб зрозуміти, доїхали чи ні, — а обрив на першому ж кроці не
	## відрізнити взагалі, бо він дає той самий UnitTurned, що й навмисний поворот на
	## місці. Причина та сама, що й у ShotRetaliated: вигляд не має здогадуватись про
	## подію з порядку чи довжини сусідніх.
	##
	## Несе тайл, але НЕ того, хто на ньому стоїть, і це межа навмисна. Тайл гравець
	## і так бачить: юніт спиняється ортогонально поруч із ним, а найменший огляд у
	## грі — ромб радіуса 3 (§3.5), тож сусідній тайл лежить усередині огляду самого
	## мовця. Id блокувальника такої підстави не має — постріл у відповідь і показ
	## ворога гейтяться на visible, і подія не має бути обхідним шляхом до того, що
	## гравець мусив би заслужити оком.
	var unit_id: int
	var pos: Vector2i
	func _init(p_unit_id: int, p_pos: Vector2i) -> void:
		unit_id = p_unit_id
		pos = p_pos
	func describe() -> String:
		return "MoveBlocked(unit=%d, at %s)" % [unit_id, pos]

class ShotFired extends BattleEvent:
	var attacker_id: int
	var target_id: int
	var sector: int
	func _init(p_attacker_id: int, p_target_id: int, p_sector: int) -> void:
		attacker_id = p_attacker_id
		target_id = p_target_id
		sector = p_sector
	func describe() -> String:
		return "ShotFired(%d -> %d, sector=%d)" % [attacker_id, target_id, sector]

class ShotRetaliated extends BattleEvent:
	## §3.3.1: ціль, що вижила, стріляє у відповідь. Окремий клас, а не
	## прапорець у ShotFired — вигляд мусить відрізняти відповідь від
	## пострілу, не здогадуючись про це з порядку подій.
	var attacker_id: int
	var target_id: int
	var sector: int
	func _init(p_attacker_id: int, p_target_id: int, p_sector: int) -> void:
		attacker_id = p_attacker_id
		target_id = p_target_id
		sector = p_sector
	func describe() -> String:
		return "ShotRetaliated(%d -> %d, sector=%d)" % [attacker_id, target_id, sector]

class DroneLaunched extends BattleEvent:
	var attacker_id: int
	var target_id: int
	var drones_left: int
	func _init(p_attacker_id: int, p_target_id: int, p_drones_left: int) -> void:
		attacker_id = p_attacker_id
		target_id = p_target_id
		drones_left = p_drones_left
	func describe() -> String:
		return "DroneLaunched(%d -> %d, drones_left=%d)" % [attacker_id, target_id, drones_left]

class DamageDealt extends BattleEvent:
	var unit_id: int
	var amount: int
	var hp_left: int
	func _init(p_unit_id: int, p_amount: int, p_hp_left: int) -> void:
		unit_id = p_unit_id
		amount = p_amount
		hp_left = p_hp_left
	func describe() -> String:
		return "DamageDealt(unit=%d, -%d, hp=%d)" % [unit_id, amount, hp_left]

class UnitDestroyed extends BattleEvent:
	var unit_id: int
	var pos: Vector2i
	func _init(p_unit_id: int, p_pos: Vector2i) -> void:
		unit_id = p_unit_id
		pos = p_pos
	func describe() -> String:
		return "UnitDestroyed(unit=%d at %s)" % [unit_id, pos]

class TileRevealed extends BattleEvent:
	var player: int
	var tiles: Array[Vector2i]
	func _init(p_player: int, p_tiles: Array[Vector2i]) -> void:
		player = p_player
		tiles = p_tiles
	func describe() -> String:
		return "TileRevealed(player=%d, tiles=%d)" % [player, tiles.size()]

class MinePlaced extends BattleEvent:
	var pos: Vector2i
	var owner: int
	func _init(p_pos: Vector2i, p_owner: int) -> void:
		pos = p_pos
		owner = p_owner
	func describe() -> String:
		return "MinePlaced(%s, owner=%d)" % [pos, owner]

class MineCleared extends BattleEvent:
	var pos: Vector2i
	func _init(p_pos: Vector2i) -> void:
		pos = p_pos
	func describe() -> String:
		return "MineCleared(%s)" % [pos]

class MineTriggered extends BattleEvent:
	var pos: Vector2i
	var unit_id: int
	func _init(p_pos: Vector2i, p_unit_id: int) -> void:
		pos = p_pos
		unit_id = p_unit_id
	func describe() -> String:
		return "MineTriggered(%s, unit=%d)" % [pos, unit_id]

class MineRevealed extends BattleEvent:
	var pos: Vector2i
	var player: int
	func _init(p_pos: Vector2i, p_player: int) -> void:
		pos = p_pos
		player = p_player
	func describe() -> String:
		return "MineRevealed(%s, player=%d)" % [pos, player]

class BridgeChanged extends BattleEvent:
	var pos: Vector2i
	var destroyed: bool
	func _init(p_pos: Vector2i, p_destroyed: bool) -> void:
		pos = p_pos
		destroyed = p_destroyed
	func describe() -> String:
		return "BridgeChanged(%s, destroyed=%s)" % [pos, destroyed]

class UnitRepaired extends BattleEvent:
	var unit_id: int
	var amount: int
	var hp_left: int
	func _init(p_unit_id: int, p_amount: int, p_hp_left: int) -> void:
		unit_id = p_unit_id
		amount = p_amount
		hp_left = p_hp_left
	func describe() -> String:
		return "UnitRepaired(unit=%d, +%d, hp=%d)" % [unit_id, amount, hp_left]

class ObjectiveCaptured extends BattleEvent:
	var index: int
	var owner: int
	func _init(p_index: int, p_owner: int) -> void:
		index = p_index
		owner = p_owner
	func describe() -> String:
		return "ObjectiveCaptured(index=%d, owner=%d)" % [index, owner]

class ObjectiveDestroyed extends BattleEvent:
	var index: int
	func _init(p_index: int) -> void:
		index = p_index
	func describe() -> String:
		return "ObjectiveDestroyed(index=%d)" % [index]

class VeterancyGained extends BattleEvent:
	var player: int
	var unit_class: int
	var level: int
	func _init(p_player: int, p_unit_class: int, p_level: int) -> void:
		player = p_player
		unit_class = p_unit_class
		level = p_level
	func describe() -> String:
		return "VeterancyGained(player=%d, class=%d, level=%d)" % [player, unit_class, level]

class ApChanged extends BattleEvent:
	var unit_id: int
	var ap: int
	func _init(p_unit_id: int, p_ap: int) -> void:
		unit_id = p_unit_id
		ap = p_ap
	func describe() -> String:
		return "ApChanged(unit=%d, ap=%d)" % [unit_id, ap]

class TurnEnded extends BattleEvent:
	var player: int
	func _init(p_player: int) -> void:
		player = p_player
	func describe() -> String:
		return "TurnEnded(player=%d)" % [player]

class TurnStarted extends BattleEvent:
	var player: int
	var turn_number: int
	func _init(p_player: int, p_turn_number: int) -> void:
		player = p_player
		turn_number = p_turn_number
	func describe() -> String:
		return "TurnStarted(player=%d, turn=%d)" % [player, turn_number]

class PlayerEliminated extends BattleEvent:
	var player: int
	func _init(p_player: int) -> void:
		player = p_player
	func describe() -> String:
		return "PlayerEliminated(player=%d)" % [player]

class MatchEnded extends BattleEvent:
	var winner: int
	func _init(p_winner: int) -> void:
		winner = p_winner
	func describe() -> String:
		return "MatchEnded(winner=%d)" % winner
