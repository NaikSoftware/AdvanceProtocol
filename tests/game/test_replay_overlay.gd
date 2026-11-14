extends GutTest
## Оверлей повтору ходів противників: вигляд запису з дрона поверх дошки.

const OverlayScene := preload("res://game/ui/replay_overlay.tscn")

## Поля безпеки — ті самі, що в hud.tscn (SafeArea): кнопка не сміє заїхати під виріз екрана.
const SAFE_LEFT: float = 56.0
const SAFE_TOP: float = 24.0
const SAFE_RIGHT: float = 56.0
const SAFE_BOTTOM: float = 24.0

var _holder: Control
var _overlay: ReplayOverlay


## Розмір телефона в альбомній орієнтації, вужчий за базу 1280×720: кнопка мусить лишитись у полях і там.
func before_each() -> void:
	_holder = Control.new()
	_holder.size = Vector2(1066.0, 600.0)
	add_child_autofree(_holder)
	_overlay = OverlayScene.instantiate()
	_holder.add_child(_overlay)


func _skip() -> Button:
	return _overlay.get_node("%SkipButton")


func test_skip_button_is_at_least_48dp_and_inside_safe_area() -> void:
	_overlay.begin(3)
	_overlay.show_beat(0, 1, 2)
	await wait_process_frames(2)
	var r: Rect2 = _skip().get_global_rect()
	assert_gte(r.size.x, 48.0, "ширина кнопки")
	assert_gte(r.size.y, 48.0, "висота кнопки")
	var safe := Rect2(SAFE_LEFT, SAFE_TOP,
		_holder.size.x - SAFE_LEFT - SAFE_RIGHT, _holder.size.y - SAFE_TOP - SAFE_BOTTOM)
	assert_true(safe.encloses(r), "кнопка %s мусить уміститись у полях безпеки %s" % [r, safe])


func test_labels_come_from_translation_keys() -> void:
	_overlay.begin(2)
	_overlay.show_beat(1, 0, 3)
	assert_eq((_overlay.get_node("%RecLabel") as Label).text, "replay_rec")
	assert_eq(_skip().text, "replay_skip")
	assert_eq((_overlay.get_node("%TurnLabel") as Label).text, tr("replay_turn") % [3, 1])
	var prior: String = TranslationServer.get_locale()
	for locale in ["uk", "en"]:
		TranslationServer.set_locale(locale)
		for key in ["replay_rec", "replay_skip", "replay_turn"]:
			assert_ne(tr(key), key, "немає перекладу %s для %s" % [key, locale])
	TranslationServer.set_locale("uk")
	assert_eq(tr("replay_rec"), "ЗАПИС")
	TranslationServer.set_locale("en")
	assert_eq(tr("replay_rec"), "REC")
	TranslationServer.set_locale(prior)


## Сторону юніта показує смуга HP, і шейдер обертає для неї грейд (replay_ungrade.gdshaderinc). Обернений колір
## заливки кожної сторони мусить лишитись у 0..1: інакше його обріже, і смуга таки пригасне під грейдом.
## Та сама арифметика, що в шейдері, у sRGB: рампа, насиченість (середнє каналів), контраст, яскравість — навпаки.
## Обидва набори: Mobile і gl_compatibility (там контраст інший).
func test_grade_keeps_every_side_colour_invertible() -> void:
	var lo: Vector3 = ReplayOverlay.GRADE_LO
	var hi: Vector3 = ReplayOverlay.GRADE_HI
	for method in ["mobile", "gl_compatibility"]:
		var bcs: Vector3 = ReplayOverlay.grade_bcs(method)
		for owner in UnitView.PLAYER_COLORS.size():
			var f: Color = UnitView.hp_fill_color(owner)
			var c := (Vector3(f.r, f.g, f.b) - lo) / (hi - lo)
			var avg: float = (c.x + c.y + c.z) / 3.0
			c = Vector3.ONE * avg + (c - Vector3.ONE * avg) / bcs.z
			c = (Vector3.ONE * 0.5 + (c - Vector3.ONE * 0.5) / bcs.y) / bcs.x
			for ch in 3:
				assert_between(c[ch], 0.0, 1.0, "%s, сторона %d, канал %d: %s" % [method, owner, ch, c])
	assert_eq(ReplayOverlay.grade_bcs("gl_compatibility").y, 1.0, "на gl_compatibility контраст 1,0")
	assert_eq(ReplayOverlay.grade_bcs("gl_compatibility").z, ReplayOverlay.GRADE_BCS.z, "насиченість та сама")


## Поступ — лише такти, тобто видимі дії: ні ходів, ні команд, яких глядач не бачив.
func test_progress_counts_beats_only() -> void:
	var bar: Range = _overlay.get_node("%Progress")
	_overlay.begin(4)
	assert_eq(bar.max_value, 4.0)
	assert_eq(bar.value, 0.0)
	_overlay.show_beat(0, 1, 1)
	assert_eq(bar.value, 1.0)
	_overlay.show_beat(3, 1, 2)
	assert_eq(bar.value, 4.0)
	_overlay.begin(7)
	assert_eq(bar.max_value, 7.0)
	assert_eq(bar.value, 0.0, "новий повтор починає поступ з нуля")


## Кінець повтору прибирає й оверлей, і грейд світу, повертаючи саме ті значення, що були до нього.
func test_finish_hides_everything() -> void:
	var env := Environment.new()
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.25
	env.adjustment_contrast = 0.875
	env.adjustment_saturation = 1.5
	var lut := GradientTexture1D.new()
	env.adjustment_color_correction = lut
	_overlay.environment = env
	_overlay.begin(2)
	assert_true(_overlay.visible)
	assert_true(_overlay.is_processing(), "годинник запису йде")
	assert_ne(env.adjustment_saturation, 1.5, "світ під грейдом")
	# Повторний begin не сміє запам'ятати вже пригашений світ як «до повтору».
	_overlay.begin(2)
	_overlay.finish()
	assert_false(_overlay.visible)
	assert_false(_overlay.is_processing(), "схований оверлей не тримає кадр")
	assert_true(env.adjustment_enabled)
	assert_eq(env.adjustment_brightness, 1.25)
	assert_eq(env.adjustment_contrast, 0.875)
	assert_eq(env.adjustment_saturation, 1.5)
	assert_eq(env.adjustment_color_correction, lut)


## Екран пішов посеред повтору (пауза → зберегти й вийти): світ не лишається пригашеним.
func test_leaving_the_tree_mid_replay_restores_the_world() -> void:
	var env := Environment.new()
	_overlay.environment = env
	_overlay.begin(2)
	assert_true(env.adjustment_enabled)
	_holder.remove_child(_overlay)
	assert_false(env.adjustment_enabled)
	assert_eq(_overlay.applied_globals, ReplayOverlay.NEUTRAL_GLOBALS, "глобалі шейдерів знову тотожні")
	_overlay.free()


## Глобалі обернення смуги HP живуть довше за екран: після повтору вони тотожні, і жива смуга не змінюється.
func test_shader_globals_return_to_neutral_after_finish() -> void:
	_overlay.begin(2)
	assert_ne(_overlay.applied_globals, ReplayOverlay.NEUTRAL_GLOBALS, "на повторі смуга обертає грейд")
	_overlay.finish()
	assert_eq(_overlay.applied_globals, ReplayOverlay.NEUTRAL_GLOBALS)


## Крапка блимає, а «ЗАПИС» стоїть на місці: місце під крапку лишається й тоді, коли її не видно.
func test_rec_label_keeps_its_place_across_a_blink() -> void:
	var rec: Control = _overlay.get_node("%RecLabel")
	_overlay.begin(2)
	_overlay.set_process(false)  # годинник веде тест, а не стіна
	_overlay._tick(0)
	await wait_process_frames(2)
	var x: float = rec.global_position.x
	assert_true(_overlay._dot_on, "передумова: крапка горить")
	_overlay._tick(ReplayOverlay._BLINK_MS + 1)
	await wait_process_frames(2)
	assert_false(_overlay._dot_on, "передумова: крапка згасла")
	assert_eq(rec.global_position.x, x)


## Поруч із підписом такту — колір сторони, як заливка її смуги HP.
func test_swatch_shows_the_actors_side_colour() -> void:
	_overlay.begin(2)
	assert_eq(_overlay.side_color.a, 0.0, "до першого такту кольору нема")
	for actor in UnitView.PLAYER_COLORS.size():
		_overlay.show_beat(0, actor, 1)
		assert_eq(_overlay.side_color, UnitView.hp_fill_color(actor))


## Зерно й віньєтка беруть справжнє співвідношення сторін: на 20:9 зернина не розтягнута.
func test_grain_cells_follow_the_screen_aspect() -> void:
	_holder.size = Vector2(1200.0, 540.0)
	await wait_process_frames(2)
	_overlay.begin(2)
	var cells: Vector2 = (_overlay.get_node("Grain") as CanvasItem).material.get_shader_parameter("cells")
	assert_almost_eq(cells.x / cells.y, 1200.0 / 540.0, 0.001)
	assert_eq(cells.y, ReplayOverlay.GRAIN_ROWS)


## Кадр такту: якщо другий учасник ліг би під написи чи кнопку — камера на середину між ними.
func test_beat_is_framed_with_its_other_party() -> void:
	_holder.size = Vector2(1280.0, 720.0)
	_overlay.begin(2)
	_overlay.show_beat(0, 0, 1)
	await wait_process_frames(2)
	var free: Rect2 = _overlay.clear_rect()
	assert_gt(free.position.y, 60.0, "верхній рядок не у вільній частині")
	assert_lt(free.end.y, 640.0, "нижній рядок не у вільній частині")
	var focus := Vector2i(10, 10)
	var other := Vector2i(10, 16)
	assert_eq(_overlay.frame_for(focus, other, Vector2(0.0, 100.0)), focus, "ціль поруч — кадр на фокусі")
	assert_eq(_overlay.frame_for(focus, other, Vector2(0.0, 320.0)), Vector2i(10, 13), "ціль під кнопкою — середина")
	assert_eq(_overlay.frame_for(focus, focus, Vector2.ZERO), focus)
