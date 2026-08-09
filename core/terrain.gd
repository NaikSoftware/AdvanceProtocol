class_name Terrain
extends RefCounted
## Види тайлів і вартість входу (§3.2, §3.12).

enum Kind { ROAD, FIELD, FOREST, HILL, MARSH, WATER, BUILDING, RUBBLE, BRIDGE, BRIDGE_DESTROYED }
enum GroundState { DRY, MUD, FROZEN }

const IMPASSABLE: int = 1_000_000

const _BASE_PENALTY: Dictionary = {
	Kind.ROAD: 0,
	Kind.BRIDGE: 0,
	Kind.FIELD: 4,
	Kind.HILL: 8,
	Kind.RUBBLE: 10,
	Kind.FOREST: 12,
	Kind.BUILDING: 14,
	Kind.MARSH: IMPASSABLE,
	Kind.WATER: IMPASSABLE,
	Kind.BRIDGE_DESTROYED: IMPASSABLE,
}

const _MUD_OFFSET: int = 8
const _FROZEN_OFFSET: int = -3
const _FROZEN_MARSH_PENALTY: int = 12

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
