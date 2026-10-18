extends RefCounted
## Спільне для e2e-тестів. Ім'я без префікса `test_`, тож GUT не вважає файл тестом.
## Тримає посилання на GutTest, щоб кидати assert-и й чекати кадри від його імені.

const BattleScreenScene := preload("res://game/battle/battle_screen.tscn")
const MatchServiceScript := preload("res://game/autoload/match_service.gd")


## Пише всі події, які сцена забрала з черги, — щоб перевіряти ПОРЯДОК подій
## (хто повернувся до пострілу, хто після шкоди), а не лише кінцевий стан.
class RecService extends MatchServiceScript:
	var events: Array[Events.BattleEvent] = []
	func take_events() -> Array[Events.BattleEvent]:
		var e: Array[Events.BattleEvent] = super.take_events()
		events.append_array(e)
		return e


var _t: GutTest
var service: RecService
var screen: BattleScreen
## Viewport, у якому живе екран (null — viewport тесту); opts.viewport_size.
var vp: Viewport = null
## Свій файл на процес: паралельні прогони ділять user://.
var save_path: String = "user://test_e2e_save_%d.json" % OS.get_process_id()
## Control -> початковий mouse_filter; повертаємо в restore_runner_gui(),
## щоб правка не текла в інші тести.
var _saved_filters: Dictionary[Control, int] = {}


func _init(test: GutTest) -> void:
	_t = test


## GUT-раннер вішає на root власний GUI (RichTextLabel з виводом), який перехоплює
## миші й не пускає її до гри — у релізі його нема. Гасимо йому mouse_filter:
## це правка тестового середовища, а не гри. skip — піддерева, які чіпати не можна
## (екран, що його тест сам клікає).
func ignore_runner_gui(skip: Array[Node] = []) -> void:
	var runner: Node = _t.get_tree().root.get_node_or_null("GutRunner")
	if runner != null:
		_ignore_recursive(runner, skip)


func _ignore_recursive(n: Node, skip: Array[Node]) -> void:
	if skip.has(n):
		return
	if n is Control:
		var ctl := n as Control
		if not _saved_filters.has(ctl):
			_saved_filters[ctl] = ctl.mouse_filter
		ctl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c: Node in n.get_children():
		_ignore_recursive(c, skip)


func restore_runner_gui() -> void:
	for c: Control in _saved_filters:
		if is_instance_valid(c):
			c.mouse_filter = _saved_filters[c]
	_saved_filters.clear()


## Справжній клік мишею у viewport: рух, натиск, відпускання.
## vp — для сцен усередині SubViewport; типово viewport тесту.
func click_at(p: Vector2, vp: Viewport = null) -> void:
	if vp == null:
		vp = _t.get_viewport()
	var mv := InputEventMouseMotion.new()
	mv.position = p
	mv.global_position = p
	vp.push_input(mv, true)
	for pressed: bool in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = p
		ev.global_position = p
		ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		vp.push_input(ev, true)


## Гасимо твіни вручну (реального часу не чекаємо).
func step_tweens() -> void:
	for tw: Tween in Engine.get_main_loop().get_processed_tweens():
		if tw.is_valid():
			tw.custom_step(10.0)


## Крутить кадри з прискореними твінами, доки cond не стане true; не став —
## падає голосно, а не зависає.
func wait_until(cond: Callable, what: String, max_frames: int = 120) -> bool:
	for i in max_frames:
		step_tweens()
		await _t.get_tree().process_frame
		if cond.call():
			return true
	_t.assert_true(cond.call(), "не дочекались: " + what)
	return cond.call()


# --- Бій ---------------------------------------------------------------------

## opts: tiles {Vector2i: Terrain.Kind} (решта — FIELD), ground (Terrain.GroundState),
## viewport_size Vector2i (екран у SubViewport цього розміру),
## seed (7), players (2),
## prepare Callable(state: BattleState) — після setup(), до першого кадру тесту.
func boot(width: int, height: int, spawns: Array, opts: Dictionary = {}) -> void:
	var m := MapData.new()
	m.width = width
	m.height = height
	m.ground_state = opts.get("ground", Terrain.GroundState.DRY)
	var t := PackedInt32Array()
	t.resize(width * height)
	t.fill(Terrain.Kind.FIELD)
	var tiles: Dictionary = opts.get("tiles", {})
	for p: Vector2i in tiles:
		t[p.y * width + p.x] = tiles[p]
	m.tiles = t
	var typed: Array[Dictionary] = []
	for s: Dictionary in spawns:
		typed.append(s)
	m.spawns = typed
	# таблиця рухів піднімає матч у циклі — не тримаємо десяток екранів одразу
	if is_instance_valid(screen):
		screen.free()
	if is_instance_valid(service):
		service.free()
	service = RecService.new()
	_t.add_child_autofree(service)
	screen = BattleScreenScene.instantiate()
	vp = null
	if opts.has("viewport_size"):
		var sub := SubViewport.new()
		sub.size = opts["viewport_size"]
		_t.add_child_autofree(sub)
		sub.add_child(screen)
		vp = sub
	else:
		_t.add_child_autofree(screen)
	screen.save_path = save_path
	screen.setup(m, opts.get("players", 2), opts.get("seed", 7), service)
	var prepare: Callable = opts.get("prepare", Callable())
	if prepare.is_valid():
		prepare.call(service.state)
		# prepare міняє стан повз команди (позиції, міни), тож знання активного
		# гравця перераховується так само, як на початку ходу (begin_turn()):
		# туман, пошук мін. Події відкидаються — як у setup().
		var st: BattleState = service.state
		st.refresh_vision(st.active_player)
		Mines.reveal_near(st, st.active_player)
		screen._rebuild_units_for_active_player()
	ignore_runner_gui([screen])
	await settle()


## Твіни камери й подій гасимо вручну, доки програвач не скаже, що закінчив.
func settle() -> void:
	await wait_until(func() -> bool: return not screen._event_player.is_playing(), "програвання подій")


func hud() -> Hud:
	return screen.get_node("%Hud")


func gate() -> HandoverGate:
	return screen.get_node("%HandoverGate")


func press(button: BaseButton) -> void:
	_t.assert_false(button.disabled, "кнопка мусить бути натискною: %s" % button.name)
	button.pressed.emit()


func px(cell: Vector2i) -> Vector2:
	var rig: IsoCameraRig = screen.get_node("%CameraRig")
	return rig.unproject(IsoCameraRig.cell_to_world(cell))


## Справжній тап: миша вниз/вгору в центрі тайла через viewport.
func tap(cell: Vector2i) -> void:
	click_at(px(cell), vp)


func confirm() -> void:
	press(hud().get_node("%ConfirmButton"))
	await settle()


func end_turn() -> void:
	press(hud().get_node("%EndTurnButton"))
	await settle()


func confirm_gate() -> void:
	press(gate().get_node("%ConfirmButton"))
	await settle()


## Вибрати юніт, тапнути ціль, підтвердити.
func act(from: Vector2i, to: Vector2i) -> void:
	tap(from)
	tap(to)
	await confirm()


## Верба інженера кнопками панелі: вибрати інженера, натиснути вербу, тапнути
## тайл, підтвердити.
func engineer_act(from: Vector2i, action: int, to: Vector2i) -> void:
	tap(from)
	press(engineer_panel().button_for(action))
	tap(to)
	await confirm()


func engineer_panel() -> EngineerPanel:
	return hud().get_node("%EngineerPanel")


func events_of(cls: Variant) -> Array[Events.BattleEvent]:
	var out: Array[Events.BattleEvent] = []
	for e in service.events:
		if is_instance_of(e, cls):
			out.append(e)
	return out
