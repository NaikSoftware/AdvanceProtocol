class_name ResultsScreen
extends Control
## Task 3.5: екран результату. Усі числа виводяться зі стану, який лишив
## MatchService, — core/ тут нічого не доповнюється (summarize нижче).
## «Реванш» — той самий матч (карта, гравці, ґрунт), новий випадковий сід.

const PLAYER_COLOURS: Array[Color] = [
	Color(0.82, 0.66, 0.32), Color(0.32, 0.6, 0.62), Color(0.68, 0.4, 0.32),
]
const CLASS_KEYS: Array[String] = [
	"results_class_infantry", "results_class_light_vehicle",
	"results_class_tank", "results_class_artillery",
]

## Підміняється тестом до додавання у дерево; null — автолоад.
var match_service: Node = null
## Те саме для навігації: null — автолоад SceneRouter.
var router: Node = null


## Рядок на гравця: втрати (мертві юніти), завдана шкода, утримані цілі, рівні
## досвіду за класами. Шкода: Experience.xp зберігає лише залишок після
## підвищень рівня, тож повна сума = залишок + пороги вже пройдених рівнів.
static func summarize(state: BattleState) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for p in state.player_count:
		var losses: int = 0
		for u in state.units.values():
			if u.owner == p and not u.is_alive():
				losses += 1
		var pool: Experience = state.experience[p]
		var damage: int = 0
		var levels: Array[int] = []
		for c in UnitTypes.UnitClass.values():
			var spent: int = 0
			for i in pool.level[c]:
				spent += int(Experience.THRESHOLDS[c][i])
			damage += pool.xp[c] + spent
			levels.append(pool.level[c])
		rows.append({
			"player": p,
			"losses": losses,
			"damage": damage,
			"objectives": Objectives.held_by(state, p),
			"levels": levels,
		})
	return rows


func _ready() -> void:
	if match_service == null:
		match_service = MatchService
	if router == null:
		router = SceneRouter
	%RematchButton.pressed.connect(_on_rematch_pressed)
	%ToMenuButton.pressed.connect(func() -> void: router.goto_main_menu())
	var state: BattleState = match_service.state
	if state == null:
		return
	(%Winner as Label).text = _winner_text(state)
	_build_table(summarize(state))


func _winner_text(state: BattleState) -> String:
	if state.winner == BattleState.DRAW:
		return tr("results_draw")
	if state.winner == BattleState.NO_WINNER:
		return tr("results_not_finished")
	return "%s: %s" % [tr("results_winner"), tr("results_player") % (state.winner + 1)]


func _build_table(rows: Array[Dictionary]) -> void:
	var table: GridContainer = %Table
	for child in table.get_children():
		table.remove_child(child)
		child.free()
	table.columns = rows.size() + 1
	_cell(table, " ", Color(0.55, 0.6, 0.64), HORIZONTAL_ALIGNMENT_LEFT)
	for r in rows:
		_cell(table, str(int(r["player"]) + 1), PLAYER_COLOURS[r["player"]], HORIZONTAL_ALIGNMENT_CENTER)
	for spec in [["results_losses", "losses"], ["results_damage", "damage"], ["results_objectives", "objectives"]]:
		_cell(table, tr(spec[0]), Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
		for r in rows:
			_cell(table, str(r[spec[1]]), Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_cell(table, tr("results_levels"), Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	for r in rows:
		_cell(table, _levels_text(r["levels"]), Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)


## Лише класи з ненульовим рівнем; інженери досвіду не мають (§3.7).
func _levels_text(levels: Array) -> String:
	var lines: PackedStringArray = []
	for i in CLASS_KEYS.size():
		if levels[i] > 0:
			lines.append("%s %d" % [tr(CLASS_KEYS[i]), levels[i]])
	return "\n".join(lines) if not lines.is_empty() else "—"


func _cell(table: GridContainer, text: String, colour: Color, align: HorizontalAlignment) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_color_override("font_color", colour)
	table.add_child(l)


func _on_rematch_pressed() -> void:
	# Реванш можливий лише на карті, яку ще можна завантажити і яка тягне
	# стільки гравців; інакше — до налаштувань, а не в падіння чи чужий матч.
	var map: MapData = null
	if match_service.map_path != "" and ResourceLoader.exists(match_service.map_path):
		map = load(match_service.map_path) as MapData
	if not MatchSetup.map_supports(map, match_service.players):
		router.goto_match_setup()
		return
	match_service.rematch()
	router.goto_battle()
