class_name EngineerCommand
extends Command
## §3.8. Верби замість гармати. Усе — на ортогонально сусідньому тайлі за fire_cost AP.

enum Action { LAY_MINE, CLEAR_MINE, REPAIR_BRIDGE, DEMOLISH_BRIDGE, REPAIR_UNIT }

var unit_id: int = 0
var action: int = Action.LAY_MINE
var target_pos: Vector2i = Vector2i.ZERO

static func create(p_unit_id: int, p_action: int, p_target_pos: Vector2i) -> EngineerCommand:
	var c := EngineerCommand.new()
	c.unit_id = p_unit_id
	c.action = p_action
	c.target_pos = p_target_pos
	return c

static func repair_amount(rng: RandomNumberGenerator, engineer: Unit) -> int:
	## §3.8: (40 + rand(0, ap_left - fire_cost)) / 2 — інженер, що весь хід їхав, ремонтує погано.
	return (40 + Rules.roll(rng, engineer.ap - engineer.fire_cost())) / 2

static func repair_bounds(engineer: Unit, target: Unit) -> Vector2i:
	## Межі ремонту без кидка (для панелі): x — мінімум, y — максимум, обидва з кепом на бракуючі HP.
	var missing: int = target.max_hp() - target.hp
	return Vector2i(mini(20, missing), mini((40 + maxi(0, engineer.ap - engineer.fire_cost())) / 2, missing))

static func action_status(state: BattleState, unit_id: int, action: int) -> Dictionary:
	## Допустимі сусідні тайли дії та причина відмови. Лише читає стан — правила
	## беруться з validate(), не дублюються.
	## Причина: однакова на всіх сусідах — вона й є (так завжди виходить із причиною
	## рівня юніта: AP, уже стріляв, не твій хід — validate() перевіряє їх першими);
	## різні причини тайлів — жодна не головна, тож ERR_NO_ADJACENT_TARGET, а не
	## випадкова причина першого сусіда в порядку DIRS_4.
	var tiles: Array[Vector2i] = []
	var reasons: Dictionary = {}
	var e: Unit = state.get_unit(unit_id)
	for d in Board.DIRS_4:
		var p: Vector2i = (e.pos if e != null else Vector2i.ZERO) + d
		if e != null and not state.board.in_bounds(p):
			continue
		var r: String = create(unit_id, action, p).validate(state)
		if r == "":
			tiles.append(p)
		else:
			reasons[r] = true
	var reason: String = ""
	if tiles.is_empty():
		reason = reasons.keys()[0] if reasons.size() == 1 else "ERR_NO_ADJACENT_TARGET"
	return {"tiles": tiles, "reason": reason}

func validate(state: BattleState) -> String:
	if state.is_over():
		return "ERR_MATCH_OVER"
	var e: Unit = state.get_unit(unit_id)
	if e == null or not e.is_alive():
		return "ERR_NO_SUCH_UNIT"
	if e.owner != state.active_player:
		return "ERR_NOT_YOUR_UNIT"
	if e.unit_class() != UnitTypes.UnitClass.ENGINEER:
		return "ERR_NOT_AN_ENGINEER"
	if e.has_fired:
		return "ERR_ALREADY_FIRED"
	if e.ap < e.fire_cost():
		return "ERR_NOT_ENOUGH_AP"
	if not state.board.in_bounds(target_pos):
		return "ERR_OFF_BOARD"
	var delta: Vector2i = target_pos - e.pos
	if absi(delta.x) + absi(delta.y) != 1:
		return "ERR_NOT_ADJACENT"

	match action:
		Action.LAY_MINE:
			if Mines.mine_at(state, target_pos) != null:
				return "ERR_MINE_ALREADY_THERE"
			if state.unit_at(target_pos) != null:
				return "ERR_TILE_OCCUPIED"
		Action.CLEAR_MINE:
			if Mines.mine_at(state, target_pos) == null:
				return "ERR_NO_MINE_THERE"
		Action.DEMOLISH_BRIDGE:
			if state.board.kind_at(target_pos) != Terrain.Kind.BRIDGE:
				return "ERR_NO_BRIDGE_THERE"
			# Рішення власника: ворога на мосту можна скинути разом із мостом, свого — ні.
			# Сусідній тайл завжди в ромбі огляду інженера, тож відмова нічого не виказує.
			var on_bridge: Unit = state.unit_at(target_pos)
			if on_bridge != null and on_bridge.owner == e.owner:
				return "ERR_TILE_OCCUPIED"
		Action.REPAIR_BRIDGE:
			if state.board.kind_at(target_pos) != Terrain.Kind.BRIDGE_DESTROYED:
				return "ERR_NOTHING_TO_REPAIR"
		Action.REPAIR_UNIT:
			var t: Unit = state.unit_at(target_pos)
			if t == null or t.owner != e.owner:
				return "ERR_NO_FRIENDLY_UNIT_THERE"
			if t.hp >= t.max_hp():
				return "ERR_UNIT_UNDAMAGED"
	return ""

func apply(state: BattleState) -> Array[Events.BattleEvent]:
	assert(validate(state) == "", "apply() без успішного validate()")
	var out: Array[Events.BattleEvent] = []
	var e: Unit = state.get_unit(unit_id)

	match action:
		Action.LAY_MINE:
			out.append_array(Mines.place(state, target_pos, e.owner))
		Action.CLEAR_MINE:
			out.append_array(Mines.clear(state, target_pos))
		Action.DEMOLISH_BRIDGE:
			# Той самий запобіжник, що й для REPAIR_UNIT нижче:
			# без цієї перевірки релізний виклик apply() без validate() перетворив би
			# звичайне поле на непрохідний BRIDGE_DESTROYED — це не «нічого не
			# сталося за AP», а мапа, переформована з нізвідки. Подія теж під
			# охороною: BridgeChanged для мосту, що не змінився, змусила б вигляд
			# анімувати брехню.
			if state.board.kind_at(target_pos) == Terrain.Kind.BRIDGE:
				state.board.set_kind(target_pos, Terrain.Kind.BRIDGE_DESTROYED)
				out.append(Events.BridgeChanged.new(target_pos, true))
				# Ворог на мосту падає разом із ним (рішення власника): та сама низка
				# подій, що й від смертельного влучання. Шкода — власникові інженера, як
				# від міни.
				var victim: Unit = state.unit_at(target_pos)
				if victim != null:
					state.damage_dealt[e.owner] += victim.hp
					out.append(Events.DamageDealt.new(victim.id, victim.hp, 0))
					victim.hp = 0
					out.append(Events.UnitDestroyed.new(victim.id, victim.pos))
					out.append_array(state.check_elimination())
		Action.REPAIR_BRIDGE:
			if state.board.kind_at(target_pos) == Terrain.Kind.BRIDGE_DESTROYED:
				state.board.set_kind(target_pos, Terrain.Kind.BRIDGE)
				out.append(Events.BridgeChanged.new(target_pos, false))
		Action.REPAIR_UNIT:
			# assert(validate()) вище гарантує ціль у debug-збірці; у релізі, де
			# assert вирізано, unit_at() досі може повернути null. Мовчазний
			# no-op тут не вигідніший за легальну дію — AP однаково спишеться
			# нижче, просто без ефекту, а не крашем чи безкоштовним лікуванням.
			var t: Unit = state.unit_at(target_pos)
			if t != null:
				# рахуємо ДО списання AP: у формулі бере участь саме залишок ходу
				var healed: int = mini(repair_amount(state.rng, e), t.max_hp() - t.hp)
				t.hp += healed
				out.append(Events.UnitRepaired.new(t.id, healed, t.hp))

	e.exhaust()
	out.append(Events.ApChanged.new(unit_id, 0))
	# BattleState.refresh_vision_all()'s doc: лише смерть чужого юніта здатна
	# змінити чужу видимість. Убити може тільки підрив мосту з ворогом на ньому —
	# тоді прохід по всіх гравцях; решта дій HP не віднімає, і досить оновити
	# видимість власника юніта, що діяв.
	var killed: bool = out.any(func(ev: Events.BattleEvent) -> bool: return ev is Events.UnitDestroyed)
	out.append_array(state.refresh_vision_all() if killed else state.refresh_vision(e.owner))
	return out
