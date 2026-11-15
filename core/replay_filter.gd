class_name ReplayFilter
extends RefCounted
## Повтор ходів противників для одного глядача (§3.5): з повного потоку подій повторного
## прогону лишається рівно те, що бік глядача бачив би наживо, і все, що влучило в його
## власне. Це фільтр повтору, а не живий фільтр на спостерігача (§6): він бачить увесь
## відрізок наперед, бо загін, що врешті сховався в будинку, ховає й дорогу до нього.

## Юніт з'являється на екрані глядача тут: виходить із туману або його відкрило влучання.
class Appeared extends Events.BattleEvent:
	var unit_id: int
	var pos: Vector2i
	var facing: int
	func _init(p_unit_id: int, p_pos: Vector2i, p_facing: int) -> void:
		unit_id = p_unit_id
		pos = p_pos
		facing = p_facing
	func describe() -> String:
		return "Appeared(unit=%d at %s, facing=%d)" % [unit_id, pos, facing]

## Юніт зникає з екрана глядача: пішов у туман або в укриття.
class Vanished extends Events.BattleEvent:
	var unit_id: int
	func _init(p_unit_id: int) -> void:
		unit_id = p_unit_id
	func describe() -> String:
		return "Vanished(unit=%d)" % unit_id

## Одна видима дія: події однієї команди (до чи після передачі ходу), кадр камери, чий хід, і
## стан після команди. `after` — ПРАВДА, а не те, що на екрані: посеред схованого маршруту
## загону він каже, що загін видно. Хто намальований, вигляд бере лише з `on_screen`, ніколи
## з `can_see_unit()` на `after`.
class Beat extends RefCounted:
	var events: Array[Events.BattleEvent] = []
	var focus: Vector2i = Vector2i.ZERO
	var actor: int = 0
	var turn: int = 0
	var after: BattleState = null
	## id -> true: кожен юніт, намальований після подій цього такту, і свої, і чужі.
	var on_screen: Dictionary = {}

## `on_screen_start` — хто намальований на початку відрізка; з ним, а не з `can_see_unit()` на
## `start`, вигляд будує перший кадр.
class Result extends RefCounted:
	var start: BattleState = null
	var on_screen_start: Dictionary = {}
	var beats: Array[Beat] = []


## null — повтору немає: глядач без знімка, матч скінчився у відрізку, глядач уже вибув (у грі на
## трьох матч триває, але ходу в нього немає), або нічого не видно.
static func build(log: ReplayLog, viewer: int) -> Result:
	var start: BattleState = log.start_state(viewer)
	if start == null:
		return null
	var commands: Array[Command] = log.span(viewer)
	var entries: Array[Dictionary] = log.rerun(viewer)
	# Прогін, що розійшовся з журналом (команда більше не проходить), — це не повтор.
	if entries.size() != commands.size():
		return null
	for en in entries:
		for e in en["events"]:
			if e is Events.MatchEnded:
				return null
	var last: BattleState = entries[entries.size() - 1]["after"] if not entries.is_empty() else start
	if last.eliminated[viewer]:
		return null
	var p := _Pass.new(viewer, start, entries, commands)
	var r := Result.new()
	r.start = start
	r.beats = p.run()
	r.on_screen_start = p.on_screen_start
	return r if not r.beats.is_empty() else null


class _Pass extends RefCounted:
	var viewer: int
	var start: BattleState
	var entries: Array[Dictionary]
	var commands: Array[Command]
	## Юніти, які зараз на екрані глядача, свої й чужі. Не виводиться зі стану: загін, чию дорогу
	## до укриття сховано, стан бачить посеред маршруту, а екран — ні.
	var shown: Dictionary = {}
	var on_screen_start: Dictionary = {}
	## id загону -> Vector2i(перша його команда ходу, останній хід, що скінчився в укритті).
	var hidden: Dictionary = {}
	var index: int = 0
	var before: BattleState
	var after: BattleState

	func _init(p_viewer: int, p_start: BattleState, p_entries: Array[Dictionary], p_commands: Array[Command]) -> void:
		viewer = p_viewer
		start = p_start
		entries = p_entries
		commands = p_commands
		assert(entries.size() == commands.size(), "прогін і відрізок розійшлися")

	func run() -> Array[Beat]:
		for id in start.units:
			var u: Unit = start.units[id]
			if u.is_alive() and start.can_see_unit(viewer, u):
				shown[id] = true
		on_screen_start = shown.duplicate()
		_find_hiding()
		var out: Array[Beat] = []
		before = start
		for i in entries.size():
			index = i
			after = entries[i]["after"]
			var events: Array[Events.BattleEvent] = entries[i]["events"]
			var cut: bool = false
			var next: Events.TurnStarted = null
			var next_at: int = events.size()
			# Усе від початку ходу глядача — уже його живий хід, а не повтор.
			for j in events.size():
				var ts: Events.TurnStarted = events[j] as Events.TurnStarted
				if ts == null:
					continue
				if ts.player == viewer:
					events = events.slice(0, j)
					cut = true
					break
				next = ts
				next_at = j
			if commands[i] is MoveCommand:
				_beat(out, _move(events, commands[i]), entries[i]["actor"], entries[i]["turn"])
			else:
				# Кінець ходу несе й початок наступного: загибель від здачі — ще в ході того, хто
				# здався, догоряння після TurnStarted — уже в ході наступного. Один такт не тягнеться
				# через два ходи.
				_beat(out, _other(events.slice(0, next_at), commands[i]), entries[i]["actor"], entries[i]["turn"])
				if next != null:
					_beat(out, _other(events.slice(next_at + 1), commands[i]), next.player, next.turn_number)
			if cut:
				break
			before = after
		return out

	func _beat(out: Array[Beat], kept: Array[Events.BattleEvent], actor: int, turn: int) -> void:
		if kept.is_empty():
			return
		var b := Beat.new()
		b.events = kept
		b.focus = _focus(kept[0])
		b.actor = actor
		b.turn = turn
		b.after = after
		b.on_screen = shown.duplicate()
		out.append(b)

	## §3.5: загін, що закінчив хід у будинку незнайденим, не показує жодного кроку до нього в
	## усьому відрізку, навіть за кілька окремих ходів: інакше видно, до якого будинку він ішов.
	func _find_hiding() -> void:
		var first: Dictionary = {}
		var last: Dictionary = {}
		for i in commands.size():
			var c: MoveCommand = commands[i] as MoveCommand
			if c == null:
				continue
			if not first.has(c.unit_id):
				first[c.unit_id] = i
			var st: BattleState = entries[i]["after"]
			var u: Unit = st.get_unit(c.unit_id)
			if u.owner != viewer and u.is_alive() and Rules.in_cover(st.board, u) and (u.found_by >> viewer) & 1 == 0:
				last[c.unit_id] = i
		for id in last:
			hidden[id] = Vector2i(first[id], last[id])

	func _hidden(id: int) -> bool:
		return hidden.has(id) and hidden[id].x <= index and index <= hidden[id].y

	func _visible(id: int) -> bool:
		var u: Unit = after.get_unit(id)
		return u != null and not _hidden(id) and after.can_see_unit(viewer, u)

	## Видимий чужий юніт, якого ще нема на екрані (стрілець, відкритий влучанням), спершу
	## з'являється — уже розвернутим, тож його поворот перед пострілом зайвий.
	func _show(id: int, out: Array[Events.BattleEvent], appeared: Dictionary) -> bool:
		if not _visible(id):
			return false
		var u: Unit = after.get_unit(id)
		if u.owner != viewer and not shown.has(id):
			out.append(Appeared.new(id, u.pos, u.facing))
			shown[id] = true
			appeared[id] = true
		return true

	## Тіло — з копії стану після команди за (unit_id, seq): об'єкт події вказує в живий стан перегону, і його
	## біти показу — уже кінця проміжку.
	func _body_shown(body: Casualties.Body) -> bool:
		for b: Casualties.Body in after.bodies:
			if b.unit_id == body.unit_id and b.seq == body.seq:
				return b.shown_to(viewer)
		return false

	func _mine_owner(pos: Vector2i) -> int:
		var m: Mines.Mine = Mines.mine_at(before, pos)
		return m.owner if m != null else -1

	func _other(events: Array[Events.BattleEvent], c: Command) -> Array[Events.BattleEvent]:
		var out: Array[Events.BattleEvent] = []
		var appeared: Dictionary = {}
		var engineer: int = (c as EngineerCommand).unit_id if c is EngineerCommand else -1
		var bridge_kept: bool = false
		var wreck_kept: bool = false
		for e in events:
			var keep: bool = false
			if e is Events.UnitTurned:
				keep = _show(e.unit_id, out, appeared) and not appeared.has(e.unit_id)
			elif e is Events.ShotFired or e is Events.ShotRetaliated or e is Events.DroneLaunched:
				var a: bool = _show(e.attacker_id, out, appeared)
				keep = a or _visible(e.target_id)
			elif e is Events.DamageDealt:
				keep = _show(e.unit_id, out, appeared)
			elif e is Events.UnitDestroyed:
				keep = _show(e.unit_id, out, appeared)
				wreck_kept = keep
				shown.erase(e.unit_id)
			elif e is Events.WreckLeft:
				keep = wreck_kept
			elif e is Events.UnitRepaired:
				keep = _visible(engineer) and _visible(e.unit_id)
			elif e is Events.MineCleared:
				keep = _mine_owner(e.pos) == viewer and _visible(engineer)
			elif e is Events.MineTriggered:
				keep = _mine_owner(e.pos) == viewer or _visible(e.unit_id)
			elif e is Events.BridgeChanged:
				# Міст — публічна місцевість, і кінцевий стан однаково покаже обвал, тож обвал видно,
				# коли видно інженера або загиблого з мостом. Самого інженера — лише якщо його видно:
				# влучання відкриває стрільця (§3.3.1), а підрив мосту — не постріл.
				keep = _visible(engineer) or events.any(func(x: Events.BattleEvent) -> bool:
						return x is Events.UnitDestroyed and _visible(x.unit_id))
				bridge_kept = keep
			elif e is Events.WreckRemoved:
				# Уламки, що зникли з мосту разом із ним, показали б підрив, якого не видно.
				keep = bridge_kept if e.reason == Wrecks.Reason.BRIDGE_DEMOLISHED \
						else after.vision[viewer].is_seen(e.pos)
			elif e is Events.ForestBroken:
				keep = after.vision[viewer].is_seen(e.pos)
			elif e is Events.TileRevealed or e is Events.UnitFound:
				keep = e.player == viewer
			elif e is Events.FiguresFell:
				keep = _body_shown(e.body)
			if keep:
				out.append(e)
		return out

	## Хід ріжеться на відрізки видимих кроків. Перед відрізком із туману — Appeared на
	## першому видимому тайлі, після відрізка, що урвався раніше за шлях, — Vanished.
	func _move(events: Array[Events.BattleEvent], c: MoveCommand) -> Array[Events.BattleEvent]:
		var out: Array[Events.BattleEvent] = []
		var id: int = c.unit_id
		var u0: Unit = before.get_unit(id)
		var is_hidden: bool = _hidden(id)
		if is_hidden and shown.has(id):
			out.append(Vanished.new(id))
			shown.erase(id)
		var path: Array[Vector2i] = []
		if events[0] is Events.UnitMoved:
			path = (events[0] as Events.UnitMoved).path
		# Під час ходу seen глядача не змінюється (огляд перераховується лише ходовому),
		# а found_by обнуляється на кожному кроці: знахідку на кроці несе лише UnitFound.
		var found: Dictionary = {}
		for e in events:
			if e is Events.UnitFound and e.unit_id == id and e.player == viewer:
				found[e.at_step] = true
		var vis: Array[bool] = []
		for k in path.size():
			vis.append(not is_hidden and before.vision[viewer].is_seen(path[k])
					and (not Rules.in_cover_at(before.board, u0, path[k]) or found.has(k)))
		var by_step: Dictionary = _steps(events, path)
		var running: bool = shown.has(id)
		var base: int = 0
		var seg: Array[Vector2i] = []
		var tail: Array[Events.BattleEvent] = []
		var wreck_kept: Array[bool] = [false]
		for s in range(-1, path.size()):
			if s >= 0:
				if vis[s] and not running:
					out.append(Appeared.new(id, path[s], _facing_at(u0.pos, path, s)))
					shown[id] = true
					running = true
					base = s + 1
				elif vis[s]:
					seg.append(path[s])
				elif running:
					_flush(out, id, u0.pos, path, base, seg, tail)
					out.append(Vanished.new(id))
					shown.erase(id)
					running = false
			for e: Events.BattleEvent in by_step.get(s, []):
				var k: Events.BattleEvent = _move_event(e, id, running, s - base, wreck_kept)
				if k == null:
					continue
				if running and s >= base:
					tail.append(k)
				else:
					out.append(k)
		if running:
			_flush(out, id, u0.pos, path, base, seg, tail)
		return out

	## Крок шляху для кожної події ходу (−1 — до першого кроку). Події хвоста йдуть у
	## порядку кроків; крок явно несуть лише деякі, решта успадковує крок попередньої.
	func _steps(events: Array[Events.BattleEvent], path: Array[Vector2i]) -> Dictionary:
		var out: Dictionary = {}
		var cur: int = -1
		for j in range(1, events.size()):
			var e: Events.BattleEvent = events[j]
			if e is Events.UnitFound and e.at_step >= 0:
				cur = e.at_step
			elif e is Events.ForestBroken or e is Events.MineTriggered:
				cur = path.find(e.pos)
			elif e is Events.MoveBlocked:
				cur = path.size() - 1
			if not out.has(cur):
				out[cur] = []
			out[cur].append(e)
		# Обрив на першому кроці: заголовок — поворот на місці, а не рух.
		if events[0] is Events.UnitTurned:
			if not out.has(-1):
				out[-1] = []
			out[-1].push_front(events[0])
		return out

	func _move_event(e: Events.BattleEvent, id: int, v: bool, rel: int, wreck_kept: Array[bool]) -> Events.BattleEvent:
		if e is Events.UnitTurned:
			return e if v else null
		if e is Events.MoveBlocked:
			return e if v and _blocker_known(e.pos) else null
		if e is Events.UnitFound:
			if e.player != viewer:
				return null
			if e.unit_id != id:
				return Events.UnitFound.new(e.unit_id, viewer, -1)
			# Крок — у шляху свого відрізка; −1 — на тайлі появи, поза анімацією шляху.
			return Events.UnitFound.new(id, viewer, rel) if v else null
		if e is Events.ForestBroken:
			return e if before.vision[viewer].is_seen(e.pos) else null
		if e is Events.MineTriggered:
			return e if _mine_owner(e.pos) == viewer or v else null
		if e is Events.DamageDealt:
			return e if v else null
		if e is Events.UnitDestroyed:
			wreck_kept[0] = v
			if v:
				shown.erase(id)
			return e if v else null
		if e is Events.WreckLeft:
			return e if wreck_kept[0] else null
		if e is Events.TileRevealed:
			return e if e.player == viewer else null
		if e is Events.FiguresFell:
			return e if _body_shown(e.body) else null
		return null

	## MoveBlocked несе тайл, у який не вдалося в'їхати. Якщо глядач не знає, що там, обрив
	## показав би на невидимий юніт, міну чи уламки.
	func _blocker_known(pos: Vector2i) -> bool:
		var u: Unit = before.unit_at(pos)
		if u != null:
			return before.can_see_unit(viewer, u)
		# Перед міною хід спиняється, лише коли ходовий бік її знайшов: обрив тут — це
		# MineRevealed, а його глядачеві не показують ніколи, хоч би чия була міна.
		if Mines.mine_at(before, pos) != null:
			return false
		return before.vision[viewer].is_seen(pos)

	func _flush(out: Array[Events.BattleEvent], id: int, from: Vector2i, path: Array[Vector2i], base: int,
			seg: Array[Vector2i], tail: Array[Events.BattleEvent]) -> void:
		if not seg.is_empty():
			out.append(Events.UnitMoved.new(id, seg.duplicate(), _facing_at(from, path, base + seg.size() - 1)))
		out.append_array(tail)
		seg.clear()
		tail.clear()

	static func _facing_at(from: Vector2i, path: Array[Vector2i], s: int) -> int:
		return Board.facing_towards(path[s - 1] if s > 0 else from, path[s])

	## Кадр — тайл першої показаної події. Постріл — зі стрільця, якщо його видно, інакше з цілі.
	func _focus(e: Events.BattleEvent) -> Vector2i:
		if e is Appeared:
			return e.pos
		if e is Events.ShotFired or e is Events.ShotRetaliated or e is Events.DroneLaunched:
			var id: int = e.attacker_id if _visible(e.attacker_id) else e.target_id
			return after.get_unit(id).pos
		if e is Events.TileRevealed:
			return e.tiles[0]
		if e is Vanished or e is Events.UnitMoved:
			return before.get_unit(e.unit_id).pos
		# Тайл MoveBlocked — той, куди НЕ в'їхали; кадр — на самому юніті.
		if e is Events.MoveBlocked or e is Events.UnitTurned or e is Events.DamageDealt \
				or e is Events.UnitRepaired or e is Events.UnitFound:
			return after.get_unit(e.unit_id).pos
		return e.pos
