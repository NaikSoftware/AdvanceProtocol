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
	for locale in ["uk", "en"]:
		TranslationServer.set_locale(locale)
		for key in ["replay_rec", "replay_skip", "replay_turn"]:
			assert_ne(tr(key), key, "немає перекладу %s для %s" % [key, locale])
	TranslationServer.set_locale("uk")
	assert_eq(tr("replay_rec"), "ЗАПИС")
	TranslationServer.set_locale("en")
	assert_eq(tr("replay_rec"), "REC")
	TranslationServer.set_locale("uk")


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
	_overlay.free()
