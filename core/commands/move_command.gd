class_name MoveCommand
extends Command

var unit_id: int = 0
var target: Vector2i = Vector2i.ZERO
var facing: int = -1

static func create(p_unit_id: int, p_target: Vector2i, p_facing: int) -> MoveCommand:
	var c := MoveCommand.new()
	c.unit_id = p_unit_id
	c.target = p_target
	c.facing = p_facing
	return c

func validate(state: BattleState) -> String:
	if state.is_over():
		return "ERR_MATCH_OVER"
	var u: Unit = state.get_unit(unit_id)
	if u == null or not u.is_alive():
		return "ERR_NO_SUCH_UNIT"
	if u.owner != state.active_player:
		return "ERR_NOT_YOUR_UNIT"
	if u.has_fired:
		return "ERR_ALREADY_FIRED"
	if not state.board.in_bounds(target):
		return "ERR_OFF_BOARD"
	var occupied: Dictionary = state.occupied_map()
	occupied.erase(u.pos)
	var zones: Pathing.Zones = Pathing.compute_zones(state.board, u, occupied)
	if not zones.can_reach(target):
		return "ERR_OUT_OF_RANGE"
	return ""

func apply(state: BattleState) -> Array[Events.BattleEvent]:
	assert(validate(state) == "", "apply() без успішного validate()")
	var out: Array[Events.BattleEvent] = []
	var u: Unit = state.get_unit(unit_id)
	var occupied: Dictionary = state.occupied_map()
	occupied.erase(u.pos)
	var zones: Pathing.Zones = Pathing.compute_zones(state.board, u, occupied)
	var path: Array[Vector2i] = Pathing.path_to(zones, target)

	# §3.11: перший замінований тайл на шляху зупиняє рух — інакше мінне поле
	# можна було б переїхати, просто не зупиняючись на ньому. Умова тут мусить
	# бути рівно тою, за якою детонує Mines.step_on(), інакше рух обірветься
	# там, де нічого не вибухне, або вибухне там, де рух не обірвався.
	var stop_index: int = -1
	for i in path.size():
		var m: Mines.Mine = Mines.mine_at(state, path[i])
		if m != null and m.owner != u.owner:
			stop_index = i
			break
	var walked: Array[Vector2i] = path if stop_index < 0 else path.slice(0, stop_index + 1)
	var final_pos: Vector2i = target if walked.is_empty() else walked[walked.size() - 1]

	# cost_to() кличеться лише під can_reach(). У release-збірці assert вирізано,
	# тож недосяжна ціль повернула б −1, а spend_ap(−1) ДОДАВ би юнітові очко дії:
	# нелегальний хід ставав би вигіднішим за легальний. Запасний шлях — списати
	# все, що є: помилка не має винагороджуватись.
	var spent: int = zones.cost_to(final_pos) if zones.can_reach(final_pos) else u.ap

	var final_facing: int = facing
	if final_facing < 0:
		final_facing = Board.facing_towards(
			walked[walked.size() - 2] if walked.size() >= 2 else u.pos,
			final_pos) if not walked.is_empty() else u.facing

	u.pos = final_pos
	u.facing = final_facing
	u.spend_ap(spent)

	# Поворот на місці — це UnitTurned, а не UnitMoved з порожнім шляхом:
	# інакше вигляд мусив би сам розрізняти ці випадки за довжиною масиву.
	if walked.is_empty():
		out.append(Events.UnitTurned.new(unit_id, final_facing))
	else:
		out.append(Events.UnitMoved.new(unit_id, walked, final_facing))
	out.append(Events.ApChanged.new(unit_id, u.ap))

	# §3.5/§6: туман оновлюється ЩОЙНО юніт став на нове місце — до всього, що
	# на тому тайлі станеться. Інакше подія про тайл (MineTriggered, MineRevealed)
	# випереджає TileRevealed цього ж тайла, і вигляд, програючи список по черзі,
	# малює вибух чи міну на клітинці, яка для гравця ще в тумані. Кінцевий стан
	# від порядку не залежить — залежить рівно потік подій, а він і є контрактом
	# з виглядом.
	out.append_array(state.refresh_vision(u.owner))
	out.append_array(Mines.step_on(state, u))
	# Смерть на міні гасить власний огляд юніта, тож перерахунок потрібен ще раз —
	# і лише на цій гілці: нових тайлів він не відкриває, отже й подій не додає,
	# але visible мертвого юніта мусить згаснути.
	if not u.is_alive():
		out.append_array(state.refresh_vision(u.owner))
	# Стоїть ПІСЛЯ перерахунку туману: розкрита міна завжди лежить на тайлі, який
	# гравець бачить, і потік подій має говорити те саме, що й кінцевий стан.
	out.append_array(Mines.reveal_near(state, u.owner))
	# §3.10: цілі підкоряються туману, як і все інше, — а отже мусять позначатися
	# побаченими там само, де оновлюється туман. Доти єдиним викликачем
	# refresh_seen() був begin_turn(), тож ціль, повз яку юніт проїхав СЕРЕДИНОЮ
	# ходу, не позначалася до початку наступного ходу цього гравця — а якщо юніт
	# до того встиг відійти, не позначалася ніколи. Виходила розбіжність усередині
	# одного тайла: місцевість гравець памʼятає, а ціль на ній — ні.
	out.append_array(Objectives.refresh_seen(state, u.owner))
	return out
