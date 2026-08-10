class_name Terrain
extends RefCounted
## Види тайлів і вартість входу (§3.2, §3.12).

enum Kind { ROAD, FIELD, FOREST, HILL, MARSH, WATER, BUILDING, RUBBLE, BRIDGE, BRIDGE_DESTROYED }
enum GroundState { DRY, MUD, FROZEN }

const IMPASSABLE: int = 1_000_000

## Шкала взята з референсу (§4), `GameCanvas.method_68`: там рівно шість кошиків —
## 0 (дорога), 5, 10 (базовий ґрунт), 20 (пересічена місцевість), 100 (забудова)
## і 1000 (непрохідно). Стискати їх не можна: при cross_country 5–13 будь-який
## штраф, менший за 13, повністю зникає під підлогою у max(10, 10 + p - cc), і
## техніка перестає відчувати місцевість узагалі.
const _BASE_PENALTY: Dictionary = {
	Kind.ROAD: 0,
	Kind.BRIDGE: 0,
	Kind.RUBBLE: 5,
	Kind.FIELD: 10,
	Kind.HILL: 20,
	Kind.FOREST: 20,
	Kind.BUILDING: 100,
	Kind.MARSH: IMPASSABLE,
	Kind.WATER: IMPASSABLE,
	Kind.BRIDGE_DESTROYED: IMPASSABLE,
}

const _MUD_OFFSET: int = 10
const _FROZEN_OFFSET: int = -5
const _FROZEN_MARSH_PENALTY: int = 20

static func is_road(kind: int) -> bool:
	return kind == Kind.ROAD or kind == Kind.BRIDGE

static func penalty(kind: int, ground_state: int) -> int:
	if kind == Kind.MARSH and ground_state == GroundState.FROZEN:
		return _FROZEN_MARSH_PENALTY
	var base: int = _BASE_PENALTY[kind]
	if base >= IMPASSABLE or is_road(kind):
		return base
	match ground_state:
		GroundState.MUD:
			return base + _MUD_OFFSET
		GroundState.FROZEN:
			return maxi(0, base + _FROZEN_OFFSET)
		_:
			return base

static func is_passable(kind: int, ground_state: int) -> bool:
	return penalty(kind, ground_state) < IMPASSABLE
