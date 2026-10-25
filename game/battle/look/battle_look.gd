class_name BattleLook
extends Resource
## Світло й погода карти — суто вигляд, жодне число тут не торкається правил (§3.12). Ґрунт
## (сухо / багно / мерзлота) — правило з `MapData.ground_state`; вигляд лише не суперечить
## йому: на сухій карті нема ні дощу, ні мокрої землі. Хмарне чи ясне небо задає все світло
## разом: похмуре — розсіяне світло, слабкі м'які тіні, сильне холодне світло неба; ясне —
## сильне сонце, чіткі тіні, синє небо. Типові значення — рівне похмуре світло без дощу, для
## карти без власного вигляду.

## Пора року: з неї дошка добиратиме сезонні асети (`&"summer"`, `&"early"` — рання осінь,
## `&"late"` — пізня осінь).
@export var season: StringName = &"late"

## Сонце (одне напрямлене світло з тінями, §8). Кут — над обрієм; поворот 45° — світло йде
## туди ж, куди дивиться камера (з-за спини), 225° — назустріч камері, з дальнього боку.
@export var light_color: Color = Color(1, 1, 1)
@export var light_energy: float = 1.0
@export var light_pitch_deg: float = 45.0
@export var light_yaw_deg: float = 45.0
## Тіні юнітів: під хмарами вони бліді й розмиті, на сонці — темні й чіткі.
@export_range(0.0, 1.0) var shadow_opacity: float = 1.0
@export var shadow_blur: float = 1.0
## Розсіяне світло неба, однакове на дошці й довкола неї: холодно-сіре під хмарами, синє
## під ясним небом.
@export var ambient_color: Color = Color(0.62, 0.67, 0.75)
@export var ambient_energy: float = 1.0
## 0 — суцільні хмари, 1 — ясне синє небо з поодинокими хмарами; те саме небо відбивають
## вода й калюжі.
@export_range(0.0, 1.0) var sky_clear: float = 0.0
## Колір імли за краєм дошки, лінійний: з тим самим світлом, що й поле.
@export var haze_color: Color = Color(0.10, 0.135, 0.155)
## Множник кольору трави й листя за порою року; дорогу й воду не зачіпає.
@export var foliage_tint: Color = Color(1, 1, 1)
## 0..1: каламутна вода під ясним небом — відбите небо сіріше й тьмяніше, товща оливкова.
@export_range(0.0, 1.0) var water_murk: float = 0.0
## Вітер над водою: 1 — брижа Річки; менше — дрібніша й повільніша брижа тихого дня.
@export_range(0.0, 1.0) var water_wind: float = 1.0
@export var rain: bool = false
## Крапель у коробці дощу довкола кадру; на будь-якому віддаленні камери їх видно стільки ж.
@export var rain_amount: int = 0
## 0..1: темніша й глянцевіша земля, калюжі в коліях, кола від крапель на воді.
@export_range(0.0, 1.0) var wetness: float = 0.0
## 0..1: наскільки темніє земля під хмарою, що пропливає.
@export_range(0.0, 1.0) var cloud_shadow_strength: float = 0.0
## Сила вітру: горизонтальний знос на одиницю падіння краплі. Ним зносить і дощ, і дим
## (`WeatherRig.wind()`); у безвітряну погоду стовп диму стоїть майже прямо.
@export_range(0.0, 1.0) var wind: float = 0.25

const _DIR: String = "res://game/battle/look/%s.tres"


## Вигляд карти — файл з тим самим іменем у game/battle/look/; без нього — типовий.
static func for_map_path(path: String) -> BattleLook:
	var own: String = _DIR % path.get_file().get_basename()
	if path != "" and ResourceLoader.exists(own):
		return load(own) as BattleLook
	return BattleLook.new()
