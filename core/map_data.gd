class_name MapData
extends Resource
## Дані готової карти (Task 2.10): тайли, старт юнітів. Ресурс, не Node —
## §6 забороняє лише вузли Godot під core/, а Resource лишається чистими даними
## без дерева сцени, тож правило не порушене.
##
## Дві функції, дві відповідальності: to_board() виробляє Board — саму лише
## геометрію (§3.1), populate() наповнює вже створений BattleState — юнітами.
## Жодна з них не створює BattleState сама: це робить MatchService.start_match()
## окремим кроком (R1, task-2.10-brief.md), а populate() лише додає в те, що вже є.

## Значення surface для кожного виду, що має варіанти; для решти видів підтип завжди 0.
enum RoadSurface { ASPHALT, DIRT, COBBLE }
enum FieldSurface { MEADOW, PLOUGHED }
enum ForestSurface { MIXED, PINE, DECIDUOUS }

@export var width: int = 0
@export var height: int = 0
## §3.12: ґрунт — правило, а не декор, тож одне значення на карту.
@export var ground_state: int = Terrain.GroundState.DRY
## Плаский масив виду тайлу, індекс y*width+x — той самий порядок, що й
## Board._index(), тож перенесення в to_board() лишається прямим копіюванням.
@export var tiles: PackedInt32Array = PackedInt32Array()
## Кожен запис: {"type_id": int, "owner": int, "pos": Vector2i, "facing": int}.
@export var spawns: Array[Dictionary] = []
## Косметичний підтип тайла, той самий порядок y*width+x; 0 — типовий вигляд виду.
## Лише різноманіття картинки (рішення власника 2026-10-21): жодне правило його не читає,
## тому в Board він не переноситься. Порожній масив (карти до 2026-10-21) — усюди 0.
@export var surface: PackedByteArray = PackedByteArray()
## Ключ перекладу назви карти (§9 — жодних хардкод-рядків), не сам текст.
@export var name_key: String = ""
## Зовнішнє кільце (рішення власника 2026-10-22): пейзаж за краєм дошки, щоб край світу
## не було видно за найбільшого віддалення. Суто косметика — жодне правило, Board чи Rules
## його не читає, юніт туди не ступає, і to_board() його не копіює. 0 — кільця немає.
@export var outer_margin: int = 0
## Вид клітинки розширеної сітки (width+2m)×(height+2m), рядками; на місці дошки — OUTER_HOLE,
## бо дошка записана один раз, у tiles, і другої копії, що могла б розійтися з нею, немає.
@export var outer_tiles: PackedByteArray = PackedByteArray()
## Косметичний підтип кільця, той самий порядок, що й outer_tiles; порожній — усюди 0.
@export var outer_surface: PackedByteArray = PackedByteArray()

## Заглушка на місці дошки в outer_tiles / outer_surface.
const OUTER_HOLE: int = 255


## Скільки підтипів має вид; вид без варіантів має лише типовий вигляд 0.
static func surface_variants(kind: int) -> int:
	match kind:
		Terrain.Kind.ROAD:
			return RoadSurface.size()
		Terrain.Kind.FIELD:
			return FieldSurface.size()
		Terrain.Kind.FOREST:
			return ForestSurface.size()
	return 1


func surface_at(p: Vector2i) -> int:
	if p.x < 0 or p.x >= width or p.y < 0 or p.y >= height:
		return 0
	var i: int = p.y * width + p.x
	return surface[i] if i < surface.size() else 0


## Вид у координатах дошки, продовжених у кільце (x від -outer_margin до width-1+outer_margin):
## одне суцільне поле для вигляду. Усередині — вид самої дошки; далі за кільцем — найближчий
## його край, тож без кільця це просто край дошки.
func outer_kind_at(p: Vector2i) -> int:
	var m: int = outer_margin
	var q := Vector2i(clampi(p.x, -m, width - 1 + m), clampi(p.y, -m, height - 1 + m))
	if q.x >= 0 and q.x < width and q.y >= 0 and q.y < height:
		return tiles[q.y * width + q.x]
	var i: int = (q.y + m) * (width + 2 * m) + q.x + m
	return outer_tiles[i] if i < outer_tiles.size() else Terrain.Kind.FIELD


func to_board() -> Board:
	var board: Board = Board.create(width, height, ground_state)
	assert(tiles.size() == width * height,
		"MapData.tiles (%d) не збігається з width*height (%d)" % [tiles.size(), width * height])
	if tiles.size() == width * height:
		board.tiles = tiles.duplicate()
	return board


## Повертає false і не додає НІЧОГО, якщо старт юніта має facing поза 0..7: так само,
## як BattleSerializer відкидає збереження цілим, а не відкриває його частково.
func populate(state: BattleState) -> bool:
	for spawn in spawns:
		var f: int = int(spawn.get("facing", 0))
		if f < 0 or f > 7:
			return false
	for spawn in spawns:
		# Рішення власника: карта на трьох, зіграна вдвох, просто не ставить юнітів
		# зайвого гравця — окремих варіантів карти на кожну кількість немає.
		if int(spawn["owner"]) >= state.player_count:
			continue
		state.add_unit(
			int(spawn["type_id"]),
			int(spawn["owner"]),
			spawn["pos"] as Vector2i,
			int(spawn.get("facing", 0))
		)
	return true
