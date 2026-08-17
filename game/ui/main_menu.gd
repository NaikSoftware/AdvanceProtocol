class_name MainMenu
extends Control
## Task 3.2: головне меню. Пункти: Продовжити (лише за наявності збереження),
## Новий матч, Налаштування, Про гру, Вийти (лише десктоп/Android).
##
## Уся навігація — крізь SceneRouter (єдина точка перемикання сцен, §6).
##
## Фон живий (Background: Photo → Puddles → FireGlow → Smoke → Rain → Darken →
## LeftScrim → Vignette) поверх статичного живопису — дощ малює GPU-шейдер;
## брижі від крапель у намальованих калюжах — теж шейдер (puddle_ripples);
## кадр під собою він НЕ читає, тож порядок тримається не цим, а тим, що брижі
## мусять бути над Photo (вони частина води на картині) і під
## Darken/LeftScrim/Vignette (їх має приглушувати те саме, що й усе інше,
## інакше вони світять крізь затемнення як наклейки) — це закріплено тестом;
## вогонь і дим на горизонті збираються цим скриптом у _ready() з масиву
## FIRE_POINTS (виміряних по картині): кожна точка — вогняні частинки (полум'я
## + іскри) під FireGlow і окрема колонка диму GPUParticles2D під Smoke.
## Скрипт також відповідає за випадкові спалахи артилерії на
## горизонті (тайм-реалізація дешевша за шейдер для рідкісної нерегулярної
## події) і перф-бюджет (§8 CLAUDE.md — «battery life is a feature»).

const SAVE_PATH: String = "user://save.json"

## Перф-бюджет: анімований фон не має саджати батарею. Поки меню активне,
## кепуємо кадри й вимикаємо low-processor mode (інакше він може заморозити
## анімацію нижче цієї стелі); обидва відновлюються при виході зі сцени.
const FRAME_CAP_FPS: int = 45
const _LOW_PROCESSOR_PROPERTY: String = "low_processor_usage_mode"

## Смуга далеких пожеж на арт-фоні меню: x ≈ 48%..97%, y ≈ 33%..40%.
## Спалах з'являється в цій самій смузі — інакше він не читається як частина
## тих самих пожеж, що мерехтять шейдером.
const FLASH_X_MIN_FRAC: float = 0.48
const FLASH_X_MAX_FRAC: float = 0.97
const FLASH_Y_MIN_FRAC: float = 0.30
const FLASH_Y_MAX_FRAC: float = 0.35
const FLASH_INTERVAL_MIN: float = 5.0
const FLASH_INTERVAL_MAX: float = 12.0
const FLASH_FADE_IN_TIME: float = 0.05
const FLASH_FADE_OUT_TIME: float = 0.35
const FLASH_PEAK_ALPHA: float = 0.85
const FLASH_SIZE: Vector2 = Vector2(128.0, 70.0)
const FLASH_COLOR: Color = Color(1.0, 0.68, 0.24, 1.0)
const GLOW_TEXTURE: Texture2D = preload("res://game/ui/theme/glow_radial.tres")
## Фонова картина (Photo) тягнеться KEEP_ASPECT_COVERED — при зміні аспекту вона
## масштабується й обрізається, тож намальований горизонт з'їжджає відносно
## частки вікна. Ефекти позиціюємо в ТІЙ САМІЙ системі (cover-перенос по цій
## текстурі), а не по частці вікна, інакше вони злазять з пожеж при ресайзі.
const BG_TEXTURE: Texture2D = preload("res://assets/ui/menu_background.jpg")

## Точки вогню на арт-фоні меню: виміряні як найяскравіші пікселі
## вздовж лінії пожеж (x, y — частки ширини/висоти екрана). П'ять точок,
## кожна — окреме мале полум'я + окрема колонка диму, а не суцільна смуга.
const FIRE_POINTS: Array[Vector2] = [
	Vector2(0.577, 0.352),
	Vector2(0.628, 0.348),
	Vector2(0.708, 0.352),
	Vector2(0.793, 0.336),
	Vector2(0.892, 0.348),
]

## Розмір квада полум'я (пікселі, фіксований — точка лишається малою й
## далекою на будь-якому екрані). Точка FIRE_POINTS — приблизно основа
## язика: квад росте здебільшого вгору від неї.
## Різний масштаб вогню на кожну точку — однакові вогні читаються штучно;
## нерівний розмір робить лінію вогню природною.
const FIRE_SIZE_VARIATION: Array[float] = [1.0, 0.72, 1.15, 0.8, 0.95]
## Вогонь — ЧАСТИНКОВА система (не шейдер-силует, що завжди читався трикутником):
## хмара дрібних яскравих іскор на кожну точку, що піднімаються й гаснуть.
const FIRE_PARTICLES_PER_POINT: int = 34
const FIRE_SPARKS_PER_POINT: int = 8

## Дим: одна GPUParticles2D-колонка на точку вогню. Багато дрібних частинок
## з низькою альфою (густина складається з накладання, не з великих
## "ватних кульок") — деталі підібрані під критерій із брифу.
const SMOKE_TEXTURE: Texture2D = preload("res://assets/vfx/smoke_puff.png")
const SMOKE_PARTICLES_PER_POINT: int = 110
const SMOKE_LIFETIME: float = 11.0

@onready var _continue_button: Button = %ContinueButton
@onready var _quit_button: Button = %QuitButton
@onready var _about_panel: Control = %AboutPanel
@onready var _fire_glow: Control = %FireGlow
@onready var _smoke: Control = %Smoke
@onready var _flash_timer: Timer = %FlashTimer

var _prev_max_fps: int = 0
var _has_low_processor_property: bool = false
var _prev_low_processor_mode: bool = false
var _flash_rng: RandomNumberGenerator = RandomNumberGenerator.new()
## Маркери ефектів вогню/диму: {marker: Control, frac: Vector2 (частка КАРТИНИ)}.
## Перепозиціонуються за cover-переносом фону при кожному ресайзі вікна.
var _effect_markers: Array[Dictionary] = []


func _ready() -> void:
	# «Продовжити» показуємо лише коли є що продовжувати — задісейблена кнопка
	# лише смітить екран, тож ховаємо її повністю, якщо збереження немає.
	_continue_button.visible = FileAccess.file_exists(SAVE_PATH)
	# «Вийти» не має сенсу у веб-збірці — там немає куди виходити.
	_quit_button.visible = not OS.has_feature("web")
	_about_panel.visible = false

	_continue_button.pressed.connect(_on_continue_pressed)
	%NewMatchButton.pressed.connect(SceneRouter.goto_match_setup)
	%SettingsButton.pressed.connect(SceneRouter.goto_settings)
	%AboutButton.pressed.connect(_on_about_pressed)
	%QuitButton.pressed.connect(_on_quit_pressed)
	%AboutBackButton.pressed.connect(_on_about_back_pressed)

	_cap_frame_rate()
	_build_fire_points()
	_build_smoke_columns()
	# Позиціюємо ефекти за cover-переносом фону й перераховуємо при кожному
	# ресайзі — інакше при зміні аспекту вікна вони злазять з намальованих пожеж.
	_reposition_effects()
	get_viewport().size_changed.connect(_reposition_effects)

	_flash_rng.randomize()
	_flash_timer.timeout.connect(_on_flash_timer_timeout)
	_schedule_next_flash()


func _exit_tree() -> void:
	_restore_frame_rate()


func _on_continue_pressed() -> void:
	# Реальне завантаження збереження — Task 3.5 (MatchService.load_saved).
	# Скелет лише веде в бій, щоб потік був клікабельним.
	SceneRouter.goto_battle()


func _on_about_pressed() -> void:
	_about_panel.visible = true


func _on_about_back_pressed() -> void:
	_about_panel.visible = false


func _on_quit_pressed() -> void:
	get_tree().quit()


# --- Перф-бюджет: §8 CLAUDE.md ------------------------------------------


func _cap_frame_rate() -> void:
	_prev_max_fps = Engine.max_fps
	Engine.max_fps = FRAME_CAP_FPS

	_has_low_processor_property = _low_processor_property_exists()
	if _has_low_processor_property:
		_prev_low_processor_mode = OS.low_processor_usage_mode
		if _prev_low_processor_mode:
			OS.low_processor_usage_mode = false


func _restore_frame_rate() -> void:
	Engine.max_fps = _prev_max_fps
	if _has_low_processor_property:
		OS.low_processor_usage_mode = _prev_low_processor_mode


## `OS.low_processor_usage_mode` — властивість рушія, не гарантований API на
## всіх білдах; перевіряємо її наявність, щоб не впасти, якщо колись зникне.
func _low_processor_property_exists() -> bool:
	for prop in OS.get_property_list():
		if prop.get("name", "") == _LOW_PROCESSOR_PROPERTY:
			return true
	return false


# --- Вогонь і дим на горизонті --------------------------------------------


## Вогонь на кожній точці FIRE_POINTS — ЧАСТИНКИ (не шейдер-силует, що завжди
## читався трикутником). На точку: сталий м'який підсвіт основи + щільна хмара
## дрібних адитивних частинок полум'я (накладання дає яскраве біло-жовте ядро
## й рвану кипливу масу без силуету) + кілька швидких іскор угору-вправо.
## Різний `seed` на точку — щоб вогні не пульсували в унісон.
func _build_fire_points() -> void:
	for i in FIRE_POINTS.size():
		var point: Vector2 = FIRE_POINTS[i]
		var scale: float = FIRE_SIZE_VARIATION[i % FIRE_SIZE_VARIATION.size()]

		# Маркер-Control у точці КАРТИНИ (позицію задає _reposition_effects за
		# cover-переносом). Сяйво + емітери висять під ним у локальних (0,0), тож
		# усе їде разом при ресайзі вікна.
		var marker: Control = _point_marker()
		_fire_glow.add_child(marker)
		_effect_markers.append({"marker": marker, "frac": point})

		# Сталий теплий підсвіт основи вогнища (центр — у маркері).
		var glow := TextureRect.new()
		glow.texture = GLOW_TEXTURE
		glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		glow.stretch_mode = TextureRect.STRETCH_SCALE
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var gsize: Vector2 = Vector2(74.0, 48.0) * scale
		glow.size = gsize
		glow.position = Vector2(-gsize.x * 0.5, -gsize.y * 0.62)
		glow.modulate = Color(1.0, 0.4, 0.13, 0.26)
		glow.material = _additive_material()
		marker.add_child(glow)

		# Полум'я — щільна хмара дрібних адитивних частинок.
		var flame := GPUParticles2D.new()
		flame.position = Vector2.ZERO
		flame.amount = int(round(FIRE_PARTICLES_PER_POINT * scale))
		flame.lifetime = 2.7
		flame.preprocess = 2.7
		flame.randomness = 0.5
		flame.use_fixed_seed = true
		flame.seed = i * 7411 + 3
		flame.texture = GLOW_TEXTURE
		flame.material = _additive_material()
		flame.process_material = _make_flame_material(scale)
		marker.add_child(flame)

		# Іскри — кілька дрібних яскравих швидких цяток угору-вправо.
		var sparks := GPUParticles2D.new()
		sparks.position = Vector2.ZERO
		sparks.amount = int(round(FIRE_SPARKS_PER_POINT * scale)) + 1
		sparks.lifetime = 4.2
		sparks.preprocess = 4.2
		sparks.randomness = 0.8
		sparks.use_fixed_seed = true
		sparks.seed = i * 5209 + 41
		sparks.texture = GLOW_TEXTURE
		sparks.material = _additive_material()
		sparks.process_material = _make_spark_material(scale)
		marker.add_child(sparks)


func _additive_material() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return m


## Нульовий Control-маркер. Позицію не фіксуємо якорем (частка ВІКНА не збігається
## з обрізаною cover-картиною) — її задає _reposition_effects за cover-переносом.
## Node2D-емітери висять під ним у локальних (0,0) і їдуть разом із маркером.
func _point_marker() -> Control:
	var marker := Control.new()
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return marker


## Частка КАРТИНИ (frac) → піксель вікна з урахуванням KEEP_ASPECT_COVERED — той
## самий перенос, що застосовує Photo: масштаб cover + центроване обрізання. Саме
## тому ефекти лишаються на намальованих пожежах при будь-якому аспекті вікна.
##
## Чиста функція від розмірів (статична) — щоб її можна було перевірити тестом
## проти вручну порахованих чисел, а не проти неї ж самої.
static func cover_map(frac: Vector2, img: Vector2, win: Vector2) -> Vector2:
	var s: float = maxf(win.x / img.x, win.y / img.y)
	var disp: Vector2 = img * s
	var off: Vector2 = (win - disp) * 0.5
	return off + Vector2(frac.x * disp.x, frac.y * disp.y)


func _image_frac_to_window(frac: Vector2) -> Vector2:
	return cover_map(
		frac,
		Vector2(BG_TEXTURE.get_width(), BG_TEXTURE.get_height()),
		get_viewport_rect().size)


## Перепозиціонувати всі маркери ефектів за поточним розміром вікна (виклик на
## старті й на кожен size_changed).
func _reposition_effects() -> void:
	for entry in _effect_markers:
		(entry["marker"] as Control).position = _image_frac_to_window(entry["frac"])


func _make_flame_material(scale: float) -> ParticleProcessMaterial:
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(1.0, -1.0, 0.0)
	mat.spread = 24.0
	# ПОВІЛЬНО: це ДАЛЕКЕ багаття на горизонті — здалеку рух читається повільним.
	# Малі швидкості + довге життя частинки (2.2с) дають ту саму висоту, але
	# вдвічі повільніший темп, ніж близьке вогнище.
	mat.initial_velocity_min = 6.0 * scale
	mat.initial_velocity_max = 14.0 * scale
	# ~45° управо: рівні складові прискорення по діагоналі вгору-вправо.
	mat.gravity = Vector3(3.0, -3.0, 0.0)
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 5.0 * scale
	mat.angle_min = -180.0
	mat.angle_max = 180.0
	mat.angular_velocity_min = -18.0
	mat.angular_velocity_max = 18.0
	mat.scale_min = 0.05 * scale
	mat.scale_max = 0.12 * scale
	mat.scale_curve = _fire_scale_curve()
	mat.lifetime_randomness = 0.4
	mat.color_ramp = _fire_color_ramp()
	return mat


func _make_spark_material(scale: float) -> ParticleProcessMaterial:
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(1.0, -1.0, 0.0)
	mat.spread = 34.0
	mat.initial_velocity_min = 14.0 * scale
	mat.initial_velocity_max = 34.0 * scale
	mat.gravity = Vector3(3.0, -3.0, 0.0)
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 3.0 * scale
	mat.scale_min = 0.012 * scale
	mat.scale_max = 0.03 * scale
	mat.lifetime_randomness = 0.6
	mat.color_ramp = _spark_color_ramp()
	return mat


## Криві/градієнти вогню. Масштаб частинки росте на старті, тане під кінець
## (охолодження). Колір за віком: гаряче біло-жовте ядро → жовто-помаранчеве →
## помаранчеве → темно-червоне → згасання (з адитивним блендом накладання дає
## біле розжарене ядро в щільній основі).
func _fire_scale_curve() -> CurveTexture:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.7))
	curve.add_point(Vector2(0.35, 1.0))
	curve.add_point(Vector2(1.0, 0.2))
	var tex := CurveTexture.new()
	tex.curve = curve
	return tex


func _fire_color_ramp() -> GradientTexture1D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.2, 0.5, 0.8, 1.0])
	grad.colors = PackedColorArray([
		Color(1.0, 0.95, 0.72, 0.85),
		Color(1.0, 0.72, 0.28, 0.80),
		Color(1.0, 0.42, 0.12, 0.55),
		Color(0.65, 0.14, 0.03, 0.28),
		Color(0.25, 0.04, 0.02, 0.0),
	])
	var tex := GradientTexture1D.new()
	tex.gradient = grad
	return tex


func _spark_color_ramp() -> GradientTexture1D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	grad.colors = PackedColorArray([
		Color(1.0, 0.85, 0.45, 1.0),
		Color(1.0, 0.5, 0.15, 0.8),
		Color(0.6, 0.12, 0.03, 0.0),
	])
	var tex := GradientTexture1D.new()
	tex.gradient = grad
	return tex


## Одна колонка диму (GPUParticles2D) на кожну точку вогню. Параметри
## реалізують критерій із брифу: багато дрібних частинок з низькою альфою
## (густина складається з накладання — не «ватні кульки»), клубіння через
## кут розльоту (spread) + випадкові стартовий поворот і кутова швидкість
## (не через built-in turbulence — див. коментар у _make_smoke_material),
## довге життя, `preprocess` — щоб колона стояла повною вже в кадрі 0,
## а не наростала на очах.
func _build_smoke_columns() -> void:
	for i in FIRE_POINTS.size():
		var point: Vector2 = FIRE_POINTS[i]
		# Той самий cover-маркер, що й у вогню — колона диму їде з фоном при ресайзі.
		var marker: Control = _point_marker()
		_smoke.add_child(marker)
		_effect_markers.append({"marker": marker, "frac": point})
		var particles := GPUParticles2D.new()
		particles.position = Vector2.ZERO
		particles.amount = SMOKE_PARTICLES_PER_POINT
		particles.lifetime = SMOKE_LIFETIME
		particles.preprocess = SMOKE_LIFETIME
		particles.explosiveness = 0.0
		particles.randomness = 0.6
		particles.use_fixed_seed = true
		# Різний seed на колону — інакше однаковий amount/lifetime дають
		# однаковий псевдовипадковий патерн і всі п'ять колон клубляться
		# однаково (турбулентність теж лягає по позиції, але seed прибирає
		# й останню синхронність по обертанню/швидкості часток).
		particles.seed = i * 9973 + 17
		particles.texture = SMOKE_TEXTURE
		particles.process_material = _make_smoke_material()
		marker.add_child(particles)


func _make_smoke_material() -> ParticleProcessMaterial:
	var mat := ParticleProcessMaterial.new()
	# Нахил ~45° УПРАВО (вітер) — напрямок емісії й прискорення по діагоналі
	# вгору-вправо, щоб дим збігався з намальованим на фоні знесенням.
	mat.direction = Vector3(1.0, -1.0, 0.0)
	mat.spread = 20.0
	# Колона МУСИТЬ піднятись високо: без damping (він гасив швидкість — колона
	# не відривалась від основи) і з реальною швидкістю підйому + слабким
	# прискоренням угору-вліво. Частинки згасають по альфі під кінець життя
	# (color_ramp), тож не встигають вилетіти з екрана видимими.
	mat.initial_velocity_min = 26.0
	mat.initial_velocity_max = 46.0
	# Рівні складові = стабільні ~45° (прискорення по тій самій діагоналі).
	mat.gravity = Vector3(3.5, -3.5, 0.0)
	mat.damping_min = 0.0
	mat.damping_max = 0.0
	mat.angle_min = -180.0
	mat.angle_max = 180.0
	mat.angular_velocity_min = -20.0
	mat.angular_velocity_max = 20.0
	mat.scale_min = 0.6
	mat.scale_max = 1.0
	mat.scale_curve = _smoke_scale_curve()
	mat.lifetime_randomness = 0.5
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 5.0
	# ВАЖЛИВО (виміряно скріншотами, не здогадка): builtin turbulence в цій
	# версії рушія майже повністю гасить чистий вертикальний дрейф навіть на
	# мінімальних strength/influence — з ним колона ледь відривається від
	# основи вогню, незалежно від initial_velocity (перевірено від 10 до 50
	# px/s — та сама висота). Білдо натомість дає spread (кут розльоту) +
	# випадкова кутова швидкість + зростання масштабу + сама неправильна
	# форма спрайту диму — досить для «клубіння» без турбулентності, що
	# з'їдає підйом.
	mat.turbulence_enabled = false
	mat.color_ramp = _smoke_color_ramp()
	return mat


## Тепле, підсвічене вогнем біля основи (низька альфа) → холодне темно-сіре
## вище → повністю прозоре на кінці життя (верх колони). Індекс градієнта —
## це вік частинки (0 = щойно народилась біля вогню, 1 = майже згасла вгорі).
func _smoke_color_ramp() -> GradientTexture1D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.06, 0.5, 0.8, 1.0])
	grad.colors = PackedColorArray([
		Color(0.55, 0.30, 0.14, 0.0),
		Color(0.55, 0.30, 0.14, 0.12),
		Color(0.30, 0.28, 0.27, 0.11),
		Color(0.17, 0.17, 0.19, 0.08),
		Color(0.13, 0.13, 0.15, 0.0),
	])
	var tex := GradientTexture1D.new()
	tex.gradient = grad
	return tex


## Плавне зростання за життя (без ривка розміру) — два керуючі вузли з
## дефолтними дотичними Curve вже дають плавний ease, не сходинку.
func _smoke_scale_curve() -> CurveTexture:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.5))
	curve.add_point(Vector2(1.0, 1.7))
	var tex := CurveTexture.new()
	tex.curve = curve
	return tex


# --- Спалахи артилерії на горизонті --------------------------------------


## Чисті функції від rng — детерміновані для тестів (затравлений
## RandomNumberGenerator дає точно відтворюване значення), випадкові в грі.
static func flash_x_fraction(rng: RandomNumberGenerator) -> float:
	return rng.randf_range(FLASH_X_MIN_FRAC, FLASH_X_MAX_FRAC)


static func flash_y_fraction(rng: RandomNumberGenerator) -> float:
	return rng.randf_range(FLASH_Y_MIN_FRAC, FLASH_Y_MAX_FRAC)


static func next_flash_wait(rng: RandomNumberGenerator) -> float:
	return rng.randf_range(FLASH_INTERVAL_MIN, FLASH_INTERVAL_MAX)


func _schedule_next_flash() -> void:
	_flash_timer.wait_time = next_flash_wait(_flash_rng)
	_flash_timer.start()


func _on_flash_timer_timeout() -> void:
	_spawn_flash()
	_schedule_next_flash()


## Створює короткий адитивний бурштиновий спалах у випадковій точці смуги
## горизонту й повертає tween, що ним керує — повертається саме tween (а не
## void), щоб тести могли прокрутити згасання вручну (custom_step), а не
## чекати tween.finished у реальному часі.
func _spawn_flash() -> Tween:
	# Центр спалаху — через той самий cover-перенос, що й вогонь/дим, щоб він
	# лягав на намальований горизонт за будь-якого аспекту вікна, а не в багно.
	var center: Vector2 = _image_frac_to_window(
		Vector2(flash_x_fraction(_flash_rng), flash_y_fraction(_flash_rng)))

	var flash := TextureRect.new()
	flash.texture = GLOW_TEXTURE
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.size = FLASH_SIZE
	flash.position = center - FLASH_SIZE * 0.5
	flash.modulate = Color(FLASH_COLOR.r, FLASH_COLOR.g, FLASH_COLOR.b, 0.0)
	var blend := CanvasItemMaterial.new()
	blend.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	flash.material = blend
	_fire_glow.add_child(flash)

	var tween: Tween = create_tween()
	tween.tween_property(flash, "modulate:a", FLASH_PEAK_ALPHA, FLASH_FADE_IN_TIME)
	tween.tween_property(flash, "modulate:a", 0.0, FLASH_FADE_OUT_TIME)
	tween.finished.connect(flash.queue_free)
	return tween
