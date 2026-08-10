class_name Vision
extends RefCounted
## Туман війни (§3.5). Один екземпляр на гравця; visible завжди з нуля.
##
## Дві сітки, і навантажена — seen. Розвідка НЕЗВОРОТНА: тайл, який гравець колись
## накрив ромбом огляду, лишається йому відкритим до кінця матчу, і ворог, що на
## ньому стоїть, — видимий: по ньому можна стріляти (§3.3), його можна оглянути
## (§3.13), і він може відповісти (§3.3.1). Саме seen читають правила.
##
## visible — це тайли всередині чийогось ромба ПРЯМО ЗАРАЗ, і єдина його робота —
## доростати seen. Жодне правило його більше не читає: розвідник, що загинув на
## другому ході, однаково купив власникові все, що встиг побачити. Ціна записана
## в docs/rules/vision-and-fog.md — безкарність із §3.3.1 діє лише над землею,
## якої супротивник не розвідував ЖОДНОГО разу, і тане з ходами.

var width: int = 0
var height: int = 0
var visible: PackedByteArray = PackedByteArray()
var seen: PackedByteArray = PackedByteArray()

static func create(p_width: int, p_height: int) -> Vision:
	var v := Vision.new()
	v.width = p_width
	v.height = p_height
	v.visible.resize(p_width * p_height)
	v.seen.resize(p_width * p_height)
	return v

func _index(p: Vector2i) -> int:
	return p.y * width + p.x

func _in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < width and p.y < height

func is_visible(p: Vector2i) -> bool:
	## Лише «під наглядом зараз». Правила цим не гейтяться — див. is_seen().
	## Лишається для вигляду (підсвітка активного огляду) і для того, щоб seen росло.
	return _in_bounds(p) and visible[_index(p)] == 1

func is_seen(p: Vector2i) -> bool:
	## Гейт усіх правил, які питають «чи бачить це гравець» (§3.5). Монотонна:
	## одиниця тут ніколи не стає нулем, бо розвідка — інвестиція, а не оренда.
	return _in_bounds(p) and seen[_index(p)] == 1

func recompute(board: Board, units: Array[Unit], player: int) -> Array[Vector2i]:
	visible.fill(0)
	var revealed: Array[Vector2i] = []
	for u in units:
		if u.owner != player or not u.is_alive():
			continue
		var r: int = u.vision()
		# §3.1: огляд — ромб. Рамка сканування лишається квадратною навмисне:
		# ромб — її підмножина, а форма живе рівно в одному місці — у предикаті
		# Rules.in_vision_diamond(). Звузити dx до |dy| означало б продублювати
		# ту саму геометрію тут, де вона мовчки розійдеться з предикатом при
		# наступній зміні. Найгірший випадок у грі — r = 5: рамка 11×11 = 121
		# клітинка проти 61 у ромбі, тобто 60 порожніх ітерацій на юніт, і то
		# лише при перерахунку огляду. Дешевше за ризик розсинхрону двох копій.
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var p: Vector2i = u.pos + Vector2i(dx, dy)
				if not board.in_bounds(p):
					continue
				if not Rules.in_vision_diamond(u.pos, p, r):
					continue
				var i: int = _index(p)
				visible[i] = 1
				if seen[i] == 0:
					seen[i] = 1
					revealed.append(p)
	return revealed
