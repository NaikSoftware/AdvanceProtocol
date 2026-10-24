class_name BattleLook
extends Resource
## Світло й погода карти — суто вигляд, жодне число тут не торкається правил (§3.12). Ґрунт
## (сухо / багно / мерзлота) — правило з `MapData.ground_state`; вигляд лише не суперечить
## йому: на сухій карті нема ні дощу, ні мокрої землі. Типові значення — рівне похмуре світло
## без дощу, для карти без власного вигляду.

## Сонце (одне напрямлене світло з тінями, §8). Кут — над обрієм; поворот 45° — світло йде
## туди ж, куди дивиться камера (з-за спини), 225° — назустріч камері, з дальнього боку.
@export var light_color: Color = Color(1, 1, 1)
@export var light_energy: float = 1.0
@export var light_pitch_deg: float = 45.0
@export var light_yaw_deg: float = 45.0
## Розсіяне світло неба.
@export var ambient_energy: float = 0.5
@export var rain: bool = false
## Частинок дощу в кадрі (на будь-якому віддаленні камери).
@export var rain_amount: int = 0
## 0..1: темніша й глянцевіша земля, калюжі в коліях, кола від крапель на воді.
@export_range(0.0, 1.0) var wetness: float = 0.0
## 0..1: наскільки темніє земля під хмарою, що пропливає.
@export_range(0.0, 1.0) var cloud_shadow_strength: float = 0.0

const _DIR: String = "res://game/battle/look/%s.tres"


## Вигляд карти — файл з тим самим іменем у game/battle/look/; без нього — типовий.
static func for_map_path(path: String) -> BattleLook:
	var own: String = _DIR % path.get_file().get_basename()
	if path != "" and ResourceLoader.exists(own):
		return load(own) as BattleLook
	return BattleLook.new()
