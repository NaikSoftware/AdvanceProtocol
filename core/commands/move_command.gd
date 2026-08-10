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
	# §3.5: планування — з того, що гравець знає, а не з того, що є. Тайл, зайнятий
	# невидимим ворогом, лишається законною ціллю: команда проходить перевірку, а
	# рух зупиниться перед ним у apply(). Помилки на це немає навмисно — вона
	# повідомляла б рівно те, чого гравець не має знати. «Невидимим» тут означає
	# «на нерозвіданій землі»: ворог на давно розвіданому тайлі у карту знання
	# входить, і маршрут законно його обходить.
	var occupied: Dictionary = state.known_occupied_map(u.owner)
	occupied.erase(u.pos)
	var zones: Pathing.Zones = Pathing.compute_zones(state.board, u, occupied)
	if not zones.can_reach(target):
		return "ERR_OUT_OF_RANGE"
	return ""

func apply(state: BattleState) -> Array[Events.BattleEvent]:
	assert(validate(state) == "", "apply() без успішного validate()")
	var out: Array[Events.BattleEvent] = []
	var u: Unit = state.get_unit(unit_id)
	# Маршрут будується з тієї ж неправдивої карти, що й у validate(): гравець веде
	# юніт крізь землю, яка ВИГЛЯДАЄ порожньою. Правда перевіряється потайлово нижче.
	var occupied: Dictionary = state.known_occupied_map(u.owner)
	occupied.erase(u.pos)
	var zones: Pathing.Zones = Pathing.compute_zones(state.board, u, occupied)
	var path: Array[Vector2i] = Pathing.path_to(zones, target)

	var start_pos: Vector2i = u.pos
	var walked: Array[Vector2i] = []
	var spent: int = 0
	# Усе, що сталося ДОРОГОЮ, збирається окремо: подія руху йде заголовком, а цей
	# хвіст — за нею, у порядку кроків. Складати одразу в out не можна, бо UnitMoved
	# знає свій шлях лише тоді, коли хід уже завершився.
	var trail: Array[Events.BattleEvent] = []

	# Хід крокує тайл за тайлом, і кожен крок може виявитись останнім. Обидва
	# обриви — заблокований тайл і міна — живуть у цьому одному циклі навмисно:
	# два окремі проходи по шляху мусили б повторювати умови одне одного й
	# розійшлися б при першій же правці.
	for step: Vector2i in path:
		# §3.5: правдива зайнятість, а не та, з якої будувався маршрут. Юніт, якого
		# гравець не бачив, спиняє колону перед собою — рівно так само, як міна
		# спиняє її на собі: рух обривається там, де дійсність не збіглася з планом.
		#
		# Зайнятість перевіряється ДО міни на тому ж тайлі, і це свідомий вибір: юніт,
		# який не може туди вʼїхати, не може там і підірватися. Міна лишається лежати,
		# а шкоду дістає лише той, хто справді став на неї.
		if state.unit_at(step) != null:
			# Обрив — це подія, а не мовчанка. Без неї вигляд відрізняв би недоїзд від
			# коротшого наказу лише порівнянням target із довжиною шляху, а обрив на
			# першому кроці не відрізнив би від повороту на місці ніяк. Міна собі такої
			# події не потребує: MineTriggered уже називає і юніт, і тайл, на якому все
			# скінчилось, тобто говорить те саме й ще й причину.
			trail.append(Events.MoveBlocked.new(unit_id, step))
			break
		spent += Rules.entry_cost_at(u, state.board, step)
		u.pos = step
		walked.append(step)

		# §3.5/§6: туман оновлюється ЩОЙНО юніт став на новий тайл — до всього, що
		# на тому тайлі станеться, і на КОЖНОМУ кроці, а не лише на останньому.
		# Інакше подія про тайл (MineTriggered, MineRevealed) випереджає TileRevealed
		# цього ж тайла, і вигляд, програючи список по черзі, малює вибух чи міну на
		# клітинці, яка для гравця ще в тумані. Перерахунок саме покроковий, бо seen
		# накопичується: те, що юніт побачив із середини шляху й лишив позаду, з
		# кінцевої позиції вже не видно — при перерахунку раз на хід воно зникло б
		# із памʼяті гравця, хоч юніт повз нього й проїхав.
		trail.append_array(state.refresh_vision(u.owner))
		# §3.11: детонація — на вході в тайл, а не в кінці шляху, тож мінне поле не
		# переїдеш, просто не спиняючись на ньому. Умова обриву — рівно та, за якою
		# детонує Mines.step_on(): порожній список означає, що не вибухнуло нічого.
		var blast: Array[Events.BattleEvent] = Mines.step_on(state, u)
		trail.append_array(blast)
		# Смерть на міні гасить власний огляд юніта, тож перерахунок потрібен ще раз —
		# і лише на цій гілці: нових тайлів він не відкриває, отже й подій не додає,
		# але visible мертвого юніта мусить згаснути.
		if not u.is_alive():
			trail.append_array(state.refresh_vision(u.owner))
		# Стоїть ПІСЛЯ перерахунку туману: розкрита міна завжди лежить на тайлі, який
		# гравець бачить, і потік подій має говорити те саме, що й кінцевий стан.
		trail.append_array(Mines.reveal_near(state, u.owner))
		# §3.10: цілі підкоряються туману, як і все інше, — а отже мусять позначатися
		# побаченими там само, де оновлюється туман. Доти єдиним викликачем
		# refresh_seen() був begin_turn(), тож ціль, повз яку юніт проїхав СЕРЕДИНОЮ
		# ходу, не позначалася до початку наступного ходу цього гравця — а якщо юніт
		# до того встиг відійти, не позначалася ніколи. Виходила розбіжність усередині
		# одного тайла: місцевість гравець памʼятає, а ціль на ній — ні.
		trail.append_array(Objectives.refresh_seen(state, u.owner))
		if not blast.is_empty() or not u.is_alive():
			break

	# AP списується за тайли, у які юніт СПРАВДІ ввійшов, — тому воно й додається
	# покроково, а не береться з zones.cost_to(): обірваний хід не має коштувати як
	# запланований. Ця сума заразом закриває те, заради чого тут раніше стояла
	# перевірка can_reach(): cost_to() для недосяжного тайла повертає −1 (assert
	# вирізається в release-збірці), а spend_ap(−1) ДОДАВ би юнітові очко дії —
	# нелегальний хід ставав би вигіднішим за легальний. Вартість входу завжди
	# додатна, отже spent >= 0 і жоден обрив не може нагородити рухом; а що кожен
	# крок оплачується рівно своєю ціною, обірваний хід коштує рівно стільки ж, як
	# коштував би окремий законний хід до тієї самої точки.
	assert(spent <= u.ap, "хід не може коштувати більше за наявний AP: %d > %d" % [spent, u.ap])

	var final_facing: int = facing
	if final_facing < 0:
		# Обличчя — від того, де юніт СПРАВДІ став, а не куди його вели: після обриву
		# останній крок шляху може так і не відбутися, а саме він задає напрямок.
		final_facing = Board.facing_towards(
			walked[walked.size() - 2] if walked.size() >= 2 else start_pos,
			u.pos) if not walked.is_empty() else u.facing

	u.facing = final_facing
	u.spend_ap(spent)

	# Поворот на місці — це UnitTurned, а не UnitMoved з порожнім шляхом:
	# інакше вигляд мусив би сам розрізняти ці випадки за довжиною масиву. Сюди ж
	# потрапляє обрив на першому ж кроці: юніт нікуди не зрушив, і потік подій має
	# сказати саме це.
	if walked.is_empty():
		out.append(Events.UnitTurned.new(unit_id, final_facing))
	else:
		out.append(Events.UnitMoved.new(unit_id, walked, final_facing))
	out.append(Events.ApChanged.new(unit_id, u.ap))
	out.append_array(trail)
	return out
