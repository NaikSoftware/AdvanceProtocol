class_name ReplayOverlay
extends Control
## Оверлей повтору ходів противників — вигляд запису з розвідувального дрона: пригашений холодний
## світ, зерно й віньєтка, кутові рамки, «ЗАПИС» із червоною крапкою, таймкод, підпис такту й
## «Пропустити». Корінь і все, крім кнопки, пропускають дотики (MOUSE_FILTER_IGNORE): тап повз кнопку
## доходить до дошки й прискорює такт.
##
## Грейд — коригування `environment` (його дає екран бою): воно йде в уже наявному проході тонмапу й
## не потребує копії кадру, але лягає лише на 3D, тож написи й рамки над ним лишаються чисті. Смугу HP,
## яка показує сторону, шейдер заздалегідь обертає тим самим грейдом (replay_ungrade.gdshaderinc) — вона
## виходить у своєму кольорі; самі юніти пригашені разом зі світом.

signal skip_pressed

## Яскравість, контраст, насиченість — у порядку, в якому їх застосовує Godot. Межа — смуга HP: обернений
## грейд її кольорів сторін мусить лишатися в межах 0..1, інакше він обрізається, і смуга таки пригасає.
const GRADE_BCS := Vector3(1.0, 1.1, 0.5)
## Рампа каналів lo..hi: тіні в синяву, світло без теплого краю — холодний кадр без синього фільтра.
const GRADE_LO := Vector3(0.02, 0.035, 0.06)
const GRADE_HI := Vector3(0.93, 0.965, 1.0)
const _GRAIN_HZ: float = 24.0
const _BLINK_MS: int = 500
const _FPS: int = 25
const BRACKET_ARM: float = 44.0
const BRACKET_WIDTH: float = 3.0
const BRACKET_COLOR := Color(0.92, 0.95, 0.92, 0.85)
## Рамки стоять рівно на полях безпеки (ті самі 56/24, що в hud.tscn).
const BRACKET_INSET := Vector2(56.0, 24.0)

## Світ, який пригашує повтор; без нього (окремий тест оверлея) грейду просто нема.
var environment: Environment

const _ADJUSTMENTS: Array[StringName] = [&"adjustment_enabled", &"adjustment_brightness",
	&"adjustment_contrast", &"adjustment_saturation", &"adjustment_color_correction"]

## Значення середовища до повтору: повертаються ті, що були, а не «вимкнено».
var _saved: Dictionary = {}
var _graded: bool = false
var _started_ms: int = 0

@onready var _turn_label: Label = %TurnLabel
@onready var _skip_button: Button = %SkipButton
@onready var _progress: Range = %Progress
@onready var _timecode: Label = %Timecode
@onready var _rec_dot: Control = %RecDot
@onready var _grain: ShaderMaterial = ($Grain as CanvasItem).material


func _ready() -> void:
	set_process(false)
	_skip_button.pressed.connect(skip_pressed.emit)


## total_beats — скільки видимих дій покаже повтор: поступ рахує лише їх.
func begin(total_beats: int) -> void:
	_turn_label.text = ""
	_progress.max_value = total_beats
	_progress.value = 0
	_started_ms = Time.get_ticks_msec()
	_grade(true)
	visible = true
	set_process(true)
	_process(0.0)


## actor — 0-based, як скрізь у BattleState; на екрані 1-based.
func show_beat(index: int, actor: int, turn: int) -> void:
	_turn_label.text = tr("replay_turn") % [turn, actor + 1]
	_progress.value = index + 1


func finish() -> void:
	visible = false
	set_process(false)
	_grade(false)


## Таймкод — власний годинник запису, від його початку й за годинником стіни: Engine.time_scale
## повтору (2,5, тап — 20) розганяв би цифри так, що їх не прочитати.
func _process(_delta: float) -> void:
	var ms: int = Time.get_ticks_msec() - _started_ms
	_timecode.text = "%02d:%02d:%02d:%02d" % [ms / 3600000, ms / 60000 % 60, ms / 1000 % 60, ms % 1000 * _FPS / 1000]
	_rec_dot.visible = ms / _BLINK_MS % 2 == 0
	_grain.set_shader_parameter("seed", floorf(ms * _GRAIN_HZ / 1000.0))


## Глобалі шейдерів живуть довше за екран, а середовище — спільний ресурс: хоч би як екран пішов
## посеред повтору, світ не лишається пригашеним.
func _exit_tree() -> void:
	_grade(false)


## Усі вісім відрізків рамок — один виклик малювання; горизонтальний відрізок заходить на півтовщини за
## кут, щоб кут був повний, а не з вищербленою вершиною.
func _draw() -> void:
	var r := Rect2(BRACKET_INSET, size - BRACKET_INSET * 2.0)
	var lines := PackedVector2Array()
	for corner in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var sx: float = 1.0 if corner.x < r.get_center().x else -1.0
		var sy: float = 1.0 if corner.y < r.get_center().y else -1.0
		lines.append_array([corner, corner + Vector2(0.0, sy * BRACKET_ARM),
			corner - Vector2(sx * BRACKET_WIDTH * 0.5, 0.0), corner + Vector2(sx * BRACKET_ARM, 0.0)])
	draw_multiline(lines, BRACKET_COLOR, BRACKET_WIDTH)


func _grade(on: bool) -> void:
	if on == _graded:
		return
	_graded = on
	if environment != null:
		if on:
			for key: StringName in _ADJUSTMENTS:
				_saved[key] = environment.get(key)
			environment.adjustment_enabled = true
			environment.adjustment_brightness = GRADE_BCS.x
			environment.adjustment_contrast = GRADE_BCS.y
			environment.adjustment_saturation = GRADE_BCS.z
			environment.adjustment_color_correction = _ramp()
		else:
			for key: StringName in _saved:
				environment.set(key, _saved[key])
	RenderingServer.global_shader_parameter_set(&"replay_grade_bcs", GRADE_BCS if on else Vector3.ONE)
	RenderingServer.global_shader_parameter_set(&"replay_grade_lo", GRADE_LO if on else Vector3.ZERO)
	RenderingServer.global_shader_parameter_set(&"replay_grade_hi", GRADE_HI if on else Vector3.ONE)


static func _ramp() -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, Color(GRADE_LO.x, GRADE_LO.y, GRADE_LO.z))
	g.set_color(1, Color(GRADE_HI.x, GRADE_HI.y, GRADE_HI.z))
	var t := GradientTexture1D.new()
	t.gradient = g
	return t
