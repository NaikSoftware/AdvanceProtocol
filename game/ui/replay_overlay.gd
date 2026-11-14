class_name ReplayOverlay
extends Control
## Оверлей повтору ходів противників — вигляд запису з розвідувального дрона: пригашений холодний
## світ, зерно й віньєтка, кутові рамки, «ЗАПИС» із червоною крапкою, таймкод, підпис такту з кольором
## сторони й «Пропустити». Корінь і все, крім кнопки, пропускають дотики (MOUSE_FILTER_IGNORE): тап повз
## кнопку доходить до дошки й прискорює такт.
##
## Грейд — коригування `environment` (його дає екран бою): воно йде в уже наявному проході тонмапу й
## не потребує копії кадру, але лягає лише на 3D, тож написи й рамки над ним лишаються чисті. Смугу HP,
## яка показує сторону, шейдер заздалегідь обертає тим самим грейдом (replay_ungrade.gdshaderinc) — вона
## виходить у своєму кольорі; самі юніти пригашені разом зі світом.
##
## Усе незмінне — підкладки, рамки, крапка, колір сторони, смуга поступу — малює сам корінь (_draw): один
## елемент полотна замість вузла на кожну деталь, бо повтор не сміє коштувати більше викликів малювання,
## ніж HUD, який він заступає (§8).

signal skip_pressed

## Яскравість, контраст, насиченість — у порядку, в якому їх застосовує Godot. Межа — смуга HP: обернений
## грейд її кольорів сторін мусить лишатися в межах 0..1, інакше він обрізається, і смуга таки пригасає.
const GRADE_BCS := Vector3(1.0, 1.1, 0.5)
## gl_compatibility малює землю темнішою, і контраст 1,1 перетворює там похмурий день на сутінки. Без
## контрасту червона смуга вийшла б за межі оберненого грейду, тож яскравість 1,05 — і запас, і трохи світла.
const GRADE_BCS_GL := Vector3(1.05, 1.0, 0.5)
## Рампа каналів lo..hi: тіні в синяву, світло без теплого краю — холодний кадр без синього фільтра.
const GRADE_LO := Vector3(0.02, 0.035, 0.06)
const GRADE_HI := Vector3(0.93, 0.965, 1.0)
## Глобалі шейдерів без повтору: обернений грейд смуги HP тоді тотожний.
const NEUTRAL_GLOBALS: Dictionary = {
	&"replay_grade_bcs": Vector3.ONE, &"replay_grade_lo": Vector3.ZERO, &"replay_grade_hi": Vector3.ONE,
}
const _GRAIN_HZ: float = 24.0
## Рядків зерна на висоту екрана; стовпців — за справжнім співвідношенням сторін, щоб на 20:9 зернина
## й віньєтка не розтягувались.
const GRAIN_ROWS: float = 360.0
const _BLINK_MS: int = 500
const _FPS: int = 25
const BRACKET_ARM: float = 44.0
const BRACKET_WIDTH: float = 3.0
const BRACKET_COLOR := Color(0.92, 0.95, 0.92, 0.85)
## Рамки стоять рівно на полях безпеки (ті самі 56/24, що в hud.tscn).
const BRACKET_INSET := Vector2(56.0, 24.0)
## Підкладка під написами: смуга HP юніта позаду не змішується з цифрами.
const PLATE_COLOR := Color(0.0, 0.0, 0.0, 0.58)
const PLATE_PAD: float = 6.0
const DOT_COLOR := Color(0.86, 0.16, 0.12)
const TRACK_COLOR := Color(0.92, 0.95, 0.92, 0.2)
const FILL_COLOR := Color(0.92, 0.95, 0.92, 0.85)

const _ADJUSTMENTS: Array[StringName] = [&"adjustment_enabled", &"adjustment_brightness",
	&"adjustment_contrast", &"adjustment_saturation", &"adjustment_color_correction"]

## Світ, який пригашує повтор; без нього (окремий тест оверлея) грейду просто нема.
var environment: Environment
## Колір заливки смуги HP сторони, чий хід показано; до першого такту — прозорий.
var side_color: Color = Color.TRANSPARENT
## Останні значення глобалей шейдерів: під headless їх назад не прочитати.
var applied_globals: Dictionary = NEUTRAL_GLOBALS.duplicate()

## Значення середовища до повтору: повертаються ті, що були, а не «вимкнено».
var _saved: Dictionary = {}
var _graded: bool = false
var _started_ms: int = 0
var _dot_on: bool = true

@onready var _turn_label: Label = %TurnLabel
@onready var _skip_button: Button = %SkipButton
@onready var _progress: Range = %Progress
@onready var _timecode: Label = %Timecode
@onready var _rec_dot: Control = %RecDot
@onready var _rec_group: Control = %RecGroup
@onready var _turn_row: Control = %TurnRow
@onready var _swatch: Control = %Swatch
@onready var _grain: ShaderMaterial = ($Grain as CanvasItem).material


func _ready() -> void:
	set_process(false)
	_skip_button.pressed.connect(skip_pressed.emit)
	resized.connect(_fit_grain)
	for c: Control in [_rec_group, _timecode, _turn_row, _progress]:
		c.item_rect_changed.connect(queue_redraw)
	_fit_grain()


## Яскравість, контраст і насиченість грейду для рендерера.
static func grade_bcs(method: String) -> Vector3:
	return GRADE_BCS_GL if method == "gl_compatibility" else GRADE_BCS


## total_beats — скільки видимих дій покаже повтор: поступ рахує лише їх.
func begin(total_beats: int) -> void:
	_turn_label.text = ""
	side_color = Color.TRANSPARENT
	_progress.max_value = total_beats
	_progress.value = 0
	_started_ms = Time.get_ticks_msec()
	_grade(true)
	visible = true
	set_process(true)
	_tick(0)
	queue_redraw()


## actor — 0-based, як скрізь у BattleState; на екрані 1-based.
func show_beat(index: int, actor: int, turn: int) -> void:
	_turn_label.text = tr("replay_turn") % [turn, actor + 1]
	_progress.value = index + 1
	side_color = UnitView.hp_fill_color(actor)
	queue_redraw()


func finish() -> void:
	visible = false
	set_process(false)
	_grade(false)


## Клітинка, на яку летить камера в такті: фокус, а якщо другий учасник (offset — його екранний зсув від
## фокуса) тоді опинився б під написами чи кнопкою — середина між ними.
func frame_for(focus: Vector2i, other: Vector2i, offset: Vector2) -> Vector2i:
	var free: Rect2 = clear_rect()
	if other == focus or not free.has_area() or free.has_point(size * 0.5 + offset):
		return focus
	return (focus + other) / 2


## Частина екрана, вільна від оверлея: між верхнім і нижнім рядком написів, у полях вмісту.
func clear_rect() -> Rect2:
	var top: float = _local(%TopRow).end.y + PLATE_PAD
	var bottom: float = _local(%BottomRow).position.y - PLATE_PAD
	var area: Rect2 = _local(%Layout)
	return Rect2(area.position.x, top, area.size.x, maxf(bottom - top, 0.0))


func _process(_delta: float) -> void:
	_tick(Time.get_ticks_msec() - _started_ms)


## Таймкод — власний годинник запису, від його початку й за годинником стіни: Engine.time_scale
## повтору (2,5, тап — 20) розганяв би цифри так, що їх не прочитати. Крапка блимає прозорістю, а не
## видимістю: місце під неї лишається, і «ЗАПИС» не стрибає вбік.
func _tick(ms: int) -> void:
	_timecode.text = "%02d:%02d:%02d:%02d" % [ms / 3600000, ms / 60000 % 60, ms / 1000 % 60, ms % 1000 * _FPS / 1000]
	var on: bool = ms / _BLINK_MS % 2 == 0
	if on != _dot_on:
		_dot_on = on
		queue_redraw()
	_grain.set_shader_parameter("seed", floorf(ms * _GRAIN_HZ / 1000.0))


## Глобалі шейдерів живуть довше за екран, а середовище — спільний ресурс: хоч би як екран пішов
## посеред повтору, світ не лишається пригашеним.
func _exit_tree() -> void:
	_grade(false)


func _draw() -> void:
	for c: Control in [_rec_group, _timecode, _turn_row]:
		if c != _turn_row or _turn_label.text != "":
			draw_rect(_local(c).grow(PLATE_PAD), PLATE_COLOR)
	if _dot_on:
		var dot: Rect2 = _local(_rec_dot)
		draw_circle(dot.get_center(), dot.size.y * 0.5, DOT_COLOR)
	if side_color.a > 0.0:
		draw_rect(_local(_swatch), side_color)
	var bar: Rect2 = _local(_progress)
	draw_rect(bar, TRACK_COLOR)
	if _progress.max_value > 0.0:
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * _progress.ratio, bar.size.y)), FILL_COLOR)
	# Рамки — прямокутники, як і підкладки: в одному елементі полотна вони йдуть разом.
	var r := Rect2(BRACKET_INSET, size - BRACKET_INSET * 2.0)
	for corner: Vector2 in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var sx: float = 1.0 if corner.x < r.get_center().x else -1.0
		var sy: float = 1.0 if corner.y < r.get_center().y else -1.0
		var w: float = BRACKET_WIDTH
		draw_rect(Rect2(corner, Vector2(sx * BRACKET_ARM, sy * w)).abs(), BRACKET_COLOR)
		draw_rect(Rect2(corner + Vector2(0.0, sy * w), Vector2(sx * w, sy * (BRACKET_ARM - w))).abs(), BRACKET_COLOR)


func _local(c: Control) -> Rect2:
	return Rect2(c.global_position - global_position, c.size)


## Вужчий за 16:9 екран — менше стовпців зерна, а не сплюснута зернина.
func _fit_grain() -> void:
	if size.y > 0.0:
		_grain.set_shader_parameter("cells", Vector2(GRAIN_ROWS * size.aspect(), GRAIN_ROWS))
	queue_redraw()


func _grade(on: bool) -> void:
	if on == _graded:
		return
	_graded = on
	var bcs: Vector3 = grade_bcs(RenderingServer.get_current_rendering_method())
	if environment != null:
		if on:
			for key: StringName in _ADJUSTMENTS:
				_saved[key] = environment.get(key)
			environment.adjustment_enabled = true
			environment.adjustment_brightness = bcs.x
			environment.adjustment_contrast = bcs.y
			environment.adjustment_saturation = bcs.z
			environment.adjustment_color_correction = _ramp()
		else:
			for key: StringName in _saved:
				environment.set(key, _saved[key])
	var globals: Dictionary = {&"replay_grade_bcs": bcs, &"replay_grade_lo": GRADE_LO, &"replay_grade_hi": GRADE_HI} \
		if on else NEUTRAL_GLOBALS
	for key: StringName in globals:
		applied_globals[key] = globals[key]
		RenderingServer.global_shader_parameter_set(key, globals[key])


static func _ramp() -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, Color(GRADE_LO.x, GRADE_LO.y, GRADE_LO.z))
	g.set_color(1, Color(GRADE_HI.x, GRADE_HI.y, GRADE_HI.z))
	var t := GradientTexture1D.new()
	t.gradient = g
	return t
