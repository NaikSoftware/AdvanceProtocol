class_name ReplayLog
extends RefCounted
## Журнал застосованих команд і знімки стану по гравцях. Із знімка гравця та команд
## після нього відтворюється все, що сталося, поки він не грав.
##
## Команди лежать словниками (CommandCodec), а не об'єктами: журнал береться з диска
## так само, як і живе в пам'яті, без другого шляху.

var _base: int = 0  # абсолютний індекс commands[0]
var _commands: Array[Dictionary] = []
var _snapshots: Dictionary = {}  # player -> {"state": Dictionary, "index": int}


func mark(player: int, state: BattleState) -> void:
	_snapshots[player] = {"state": BattleSerializer.to_dict(state), "index": _base + _commands.size()}
	# Хто вибув чи здався, більше не ходить і знімка не оновить: його старий знімок тримав би
	# журнал до кінця матчу, а повтор йому не потрібен.
	for p in _snapshots.keys():
		if state.eliminated[p]:
			_snapshots.erase(p)
	# Команди глибше за найстаріший знімок ніхто вже не програє.
	var oldest: int = _base + _commands.size()
	for p in _snapshots:
		oldest = mini(oldest, int(_snapshots[p]["index"]))
	_commands = _commands.slice(oldest - _base)
	_base = oldest


func record(c: Command) -> void:
	var d: Dictionary = CommandCodec.to_dict(c)
	# Невідомий підклас дав би порожній словник і тихо зіпсував повтор.
	assert(not d.is_empty(), "команду не можна серіалізувати")
	_commands.append(d)


func span(viewer: int) -> Array[Command]:
	var out: Array[Command] = []
	if not _snapshots.has(viewer):
		return out
	for i in range(int(_snapshots[viewer]["index"]) - _base, _commands.size()):
		out.append(CommandCodec.from_dict(_commands[i]))
	return out


func start_state(viewer: int) -> BattleState:
	if not _snapshots.has(viewer):
		return null
	return BattleSerializer.from_dict(_snapshots[viewer]["state"])


func rerun(viewer: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var state: BattleState = start_state(viewer)
	if state == null:
		return out
	for c in span(viewer):
		var actor: int = state.active_player
		var turn: int = state.turn_number
		# Журнал може прийти з диска застарілим: недозволену команду не застосовуємо в жодній збірці.
		if c.validate(state) != "":
			return []
		var events: Array[Events.BattleEvent] = c.apply(state)
		out.append({
			"actor": actor,
			"turn": turn,
			"events": events,
			"after": BattleSerializer.from_dict(BattleSerializer.to_dict(state)),
		})
	return out


## Чи журнал закінчується рівно на `state`: відрізок найстаршого знімка йде до кінця журналу.
## Порожній журнал без знімків збігається завжди — повторювати нічого.
func matches(state: BattleState) -> bool:
	var oldest: int = -1
	for p in _snapshots:
		if oldest < 0 or int(_snapshots[p]["index"]) < int(_snapshots[oldest]["index"]):
			oldest = p
	if oldest < 0:
		return true
	var entries: Array[Dictionary] = rerun(oldest)
	if entries.size() != span(oldest).size():
		return false
	var end: BattleState = entries[-1]["after"] if not entries.is_empty() else start_state(oldest)
	return JSON.stringify(BattleSerializer.to_dict(end), "", true) \
			== JSON.stringify(BattleSerializer.to_dict(state), "", true)


func to_dict() -> Dictionary:
	var snaps: Dictionary = {}
	for p in _snapshots:
		snaps[str(p)] = _snapshots[p].duplicate()
	return {"base": _base, "commands": _commands.duplicate(), "snapshots": snaps}


## null, якщо щось не так: журнал — файл на диску, межа довіри.
static func from_dict(d: Dictionary) -> ReplayLog:
	if not (d.get("base") is int or d.get("base") is float) or not d.get("commands") is Array \
			or not d.get("snapshots") is Dictionary:
		return null
	var log: ReplayLog = ReplayLog.new()
	log._base = int(d["base"])
	if log._base < 0:
		return null
	for c in d["commands"]:
		if not c is Dictionary or CommandCodec.from_dict(c) == null:
			return null
		log._commands.append(c)
	for k in d["snapshots"]:
		var s: Variant = d["snapshots"][k]
		if not str(k).is_valid_int() or not s is Dictionary or not s.get("state") is Dictionary \
				or not (s.get("index") is int or s.get("index") is float):
			return null
		var idx: int = int(s["index"])
		if idx < log._base or idx > log._base + log._commands.size() \
				or BattleSerializer.from_dict(s["state"]) == null:
			return null
		log._snapshots[int(k)] = {"state": s["state"], "index": idx}
	return log
