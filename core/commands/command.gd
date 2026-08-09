class_name Command
extends RefCounted
## База для всіх дій. validate() повертає порожній рядок, якщо дія дозволена,
## або ключ перекладу помилки — щоб UI показав причину без власної логіки правил.

func validate(_state: BattleState) -> String:
	return "ERR_NOT_IMPLEMENTED"

func apply(_state: BattleState) -> Array[Events.BattleEvent]:
	return []
