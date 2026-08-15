extends GutTest

var rig: Node3D

func before_each() -> void:
	rig = load("res://game/camera/iso_camera_rig.tscn").instantiate()
	add_child_autofree(rig)
	rig.set_bounds(Vector2i(20, 20))

func test_cell_to_world_does_not_bake_the_isometric_angle() -> void:
	assert_eq(rig.cell_to_world(Vector2i(3, 4)), Vector3(3, 0, 4), "§3.1: 45° дає камера, не дані")

func test_world_to_cell_round_trips() -> void:
	for c in [Vector2i(0, 0), Vector2i(7, 2), Vector2i(19, 19)]:
		assert_eq(rig.world_to_cell(rig.cell_to_world(c)), c)

# --- Зум: ціль/поточне значення, а не миттєвий стрибок --------------------
#
# zoom_by() лише зсуває _zoom_target; camera.zoom_level наздоганяє його у
# _process() (експоненційне наближення). simulate() — штатний засіб GUT для
# детермінованого прокручування кадрів наперед без реального очікування.

func test_zoom_by_sets_a_target_without_moving_the_current_value_that_same_frame() -> void:
	var before: float = rig.zoom_level
	rig.zoom_by(0.5)
	assert_eq(rig.zoom_level, before, "zoom_by() сам по собі не мусить міняти поточне значення — лише ціль, яку _process() ще не встиг наздогнати")

func test_zoom_eases_toward_the_target_and_settles_exactly_on_it() -> void:
	rig.zoom_by(0.5)  # ціль: clamp(12*0.5, 6, 20) = 6.0 (MIN_ZOOM)
	simulate(rig, 120, 1.0 / 60.0)
	assert_eq(rig.zoom_level, 6.0, "після достатньої кількості кадрів згладжування мусить дозійти РІВНО до цілі, не барражувати біля неї")

func test_zoom_is_clamped() -> void:
	for i in 50:
		rig.zoom_by(0.5)
	simulate(rig, 120, 1.0 / 60.0)
	assert_eq(rig.zoom_level, rig.MIN_ZOOM)
	for i in 50:
		rig.zoom_by(2.0)
	simulate(rig, 120, 1.0 / 60.0)
	assert_eq(rig.zoom_level, rig.MAX_ZOOM)

## Рішення власника: зум у точку під пальцем/курсором, а не в центр екрана —
## та сама світова точка, що була під якорем ДО зміни розміру фрустума,
## мусить лишитись під ним і ПІСЛЯ (з точністю до похибки плаваючої коми:
## is_equal_approx, а не голе ==, бо тут дві проекції променя й одне
## додавання — досить, щоб останній біт мантиси розійшовся).
func test_zoom_keeps_the_world_point_under_the_anchor_fixed_on_screen() -> void:
	rig.center_on(Vector2i(10, 10))
	var anchor := Vector2(300.0, 180.0)
	var before: Vector3 = rig._ray_ground_point(anchor)
	rig.zoom_by(0.5, anchor)
	simulate(rig, 120, 1.0 / 60.0)
	var after: Vector3 = rig._ray_ground_point(anchor)
	assert_true(before.is_equal_approx(after),
		"точка під якорем мусить лишитись під ним після зуму: до=%s, після=%s" % [before, after])

# --- Пан: масштаб і напрям геометрії рига ----------------------------------

func test_pan_is_clamped_to_board() -> void:
	# Правильний масштаб (проекція променя, не 1px==1world unit) означає, що
	# один-єдиний драг більше не долітає до межі дошки сам собою — женемо
	# камеру туди повторним паном, як довгим реальним жестом. Знак делти
	# від'ємний навмисно: pan() тепер реалізує пряме маніпулювання (світова
	# точка йде ЗА пальцем) — додатний screen-y штовхає камеру до НИЖНЬОЇ
	# межі (перевірено окремо нижче, у тестах інерції), тож сюди йде
	# від'ємний, щоб перевірити саме ВЕРХНЮ межу.
	for i in 50:
		rig.pan(Vector2(0, -2000))
	var focus: Vector3 = rig.global_position
	assert_almost_eq(focus.x, 21.0, 0.01, "R12: межа — (board_size - 1) + BOARD_MARGIN, не board_size + BOARD_MARGIN")
	assert_almost_eq(focus.z, 21.0, 0.01, "R12: межа — (board_size - 1) + BOARD_MARGIN, не board_size + BOARD_MARGIN")

## R13: дельта — це палець на екрані, не світові осі; ріг мусить сам довести
## її до площини дошки крізь свою власну проекцію. Рух лише по одній
## екранній осі, що не зрушив би обидві світові осі, доводив би, що поворот
## не застосовується (кут "просочився" би назовні, у контролер вводу — саме
## те, що §3.1 забороняє).
func test_pan_rotates_screen_delta_by_the_rig_yaw() -> void:
	rig.center_on(Vector2i(10, 10))
	rig.pan(Vector2(1, 0))
	var focus: Vector3 = rig.global_position
	assert_false(is_equal_approx(focus.x, 10.0), "рух по одній осі екрана мусить зрушити фокус по світовому x")
	assert_false(is_equal_approx(focus.z, 10.0), "і по світовому z — це і є сенс 45°-рига (R13)")

## Регресія на справжній причині «не плавно»: pan() раніше додавав екранні
## ПІКСЕЛІ до світових одиниць 1:1 (без жодного перетворення масштабу) —
## драг у 50px на zoom_level=12 (вьюпорт 720px) миттєво впирав камеру у
## клемп дошки й лишав її там до кінця жесту. Заміряно в реальному вікні
## (не здогад): 5px руху миші зсували камеру рівно на 5 світових одиниць.
func test_pan_does_not_blow_past_a_modest_board_on_a_small_screen_drag() -> void:
	rig.center_on(Vector2i(10, 10))
	rig.pan(Vector2(50, 0))
	assert_true(rig.global_position.distance_to(Vector3(10.0, 0.0, 10.0)) < 2.0,
		"50px екранного руху не мусять кидати камеру через півкарти — старий баг тлумачив px як world unit 1:1, тут відстань = %s" % rig.global_position.distance_to(Vector3(10.0, 0.0, 10.0)))

## Пряме маніпулювання «під пальцем»: точка світу, що була під анкорною
## екранною позицією ДО pan(delta), мусить опинитись під анкор+delta ПІСЛЯ —
## це і є означення 1:1-стеження, перевірене геометрично, а не приблизно.
func test_pan_keeps_the_world_point_under_the_moved_anchor_fixed() -> void:
	rig.center_on(Vector2i(10, 10))
	var viewport_size: Vector2 = rig.get_viewport().get_visible_rect().size
	var anchor: Vector2 = viewport_size * 0.5
	var before: Vector3 = rig._ray_ground_point(anchor)
	var delta := Vector2(37.0, -19.0)
	rig.pan(delta)
	var after: Vector3 = rig._ray_ground_point(anchor + delta)
	assert_true(before.is_equal_approx(after),
		"світова точка під anchor до руху мусить опинитись під anchor+delta після pan(): до=%s, після=%s" % [before, after])

func test_center_on_moves_focus() -> void:
	rig.center_on(Vector2i(10, 10))
	assert_almost_eq(rig.global_position.x, 10.0, 0.01)
	assert_almost_eq(rig.global_position.z, 10.0, 0.01)

## center_on() лишається миттєвим (контракт гейта передачі ходу вимагає
## синхронності — game/ui/handover_gate.gd) навіть якщо перед ним стартував
## плавний fly_to(): убитий твін не сміє дотягнути позицію до СТАРОЇ цілі
## вже після того, як center_on() встановив нову.
func test_center_on_cancels_an_in_flight_fly_to() -> void:
	rig.center_on(Vector2i(0, 0))
	rig.fly_to(Vector2i(19, 19))
	rig.center_on(Vector2i(5, 5))
	assert_eq(rig.global_position, Vector3(5.0, 0.0, 5.0))
	simulate(rig, 60, 1.0 / 60.0)
	assert_eq(rig.global_position, Vector3(5.0, 0.0, 5.0),
		"твін від попереднього fly_to() мусить бути вбитий — інакше він дотягнув би позицію до (19,19) вже ПІСЛЯ миттєвого center_on()")

# --- fly_to(): плавне програмне рецентрування (не гейтове) -----------------

func test_fly_to_eases_toward_the_target_instead_of_teleporting() -> void:
	rig.center_on(Vector2i(0, 0))
	var tween: Tween = rig.fly_to(Vector2i(10, 10))
	assert_false(rig.global_position.is_equal_approx(Vector3(10.0, 0.0, 10.0)),
		"одразу після виклику камера ще НЕ на цілі — інакше fly_to() нічим не відрізнявся б від center_on()")
	tween.custom_step(10.0)  # з запасом понад RECENTER_DURATION — детермінований прогін до кінця, без реального очікування
	assert_eq(rig.global_position, Vector3(10.0, 0.0, 10.0), "а зрештою — точно на цілі")

# --- Інерція: кидок після відпускання, тертя, жорсткий клемп без ривка -----
#
# Швидкість вимірюється по КАДРАХ (game/camera/iso_camera_rig.gd, _process()),
# не по годиннику між pan()-подіями — тож тут кожен pan() чергується з одним
# simulate()-кадром, як і виглядав би реальний драг: подія, кадр, подія,
# кадр. Виклик pan() у щільному циклі БЕЗ кроків кадру між ними (як робив
# старий варіант цього тесту) не міряв би жодної швидкості — рівно тому
# «швидкість з годинника між подіями» відкинута на користь кадрового diff.

func _drag_frames(delta_per_frame: Vector2, frames: int, dt: float = 1.0 / 60.0) -> void:
	for i in frames:
		rig.pan(delta_per_frame)
		simulate(rig, 1, dt)

## Ревʼю, головна поломка 1: палець зупинився, полежав на екрані ПЕРЕД
## відпусканням — _process() раніше вимикав сам себе в першому ж кадрі без
## руху, тож _pan_velocity заморожувалась на останньому виміряному значенні
## й ніколи не згасала (замір рецензента: 55.71 одразу після драга, і
## 55.71 ще через 30 кадрів простою). begin_hold()/end_hold() тримають
## _process() увімкненим на весь час натиску, саме щоб цей нерухомий
## простій продовжував вимірювати diff==0 і гасити швидкість.
func test_holding_still_before_release_lets_the_fling_speed_decay_to_nothing() -> void:
	rig.center_on(Vector2i(10, 10))
	rig.begin_hold()
	# Швидкий, впевнений драг (той самий крок, що й у тесті жорсткого клемпу
	# нижче) — велике початкове значення, щоб «одненький кадр згасання, і
	# застрягло» (поведінка без фікса) лишався ЧІТКО вищим за поріг, а не
	# випадково впав під нього сам по собі.
	_drag_frames(Vector2(60.0, 0.0), 8)
	assert_true(rig._pan_velocity.length() > IsoCameraRig.MIN_FLING_SPEED * 10.0,
		"передумова: драг розігнав вимірювану швидкість помітно вище порогу")

	# Палець зупинився, але лишається притиснутим (held, не відпущений) —
	# півсекунди простою. check_is_processing=true навмисно: цей тест
	# перевіряє САМЕ те, чи рушій продовжує кликати _process() (is_processing()
	# == true) поки held — без нього simulate() кличе _process() напряму,
	# байдуже до set_process(), і тест не ловив би регресію взагалі
	# (перевірено: без цього прапорця тест лишався зеленим і на зламаному коді).
	simulate(rig, 30, 1.0 / 60.0, true)

	rig.end_pan()
	assert_false(rig._inertia_active,
		"пів секунди нерухомого притиснутого пальця мусить погасити виміряну швидкість до нуля — end_pan() не сміє кидати дошку")
	rig.end_hold()


## Ревʼю, головна поломка 2: спроба зупинити рухому дошку пальцем знову її
## запускає. _prev_frame_position раніше не скидався в cancel_inertia(),
## тож перший кадр ПІСЛЯ скасування міряв diff від СТАРОЇ (ще з польоту)
## позиції — замір рецензента: pan_v=0.0 одразу після cancel_inertia(), але
## pan_v=20.16 вже через один кадр з рухом пальця лише на 1px, і дошка
## їхала ще ~5 світових одиниць уже ПІСЛЯ відпускання.
##
## Справжнє 1px руху пальця й саме по собі дає крихітну, ненульову «швидкість»
## (кілька сотих світової одиниці за секунду — фізично чесний вимір, не
## помилка), тож тест звіряє не голий прапорець _inertia_active, а те, що
## сам рецензент назвав симптомом: скільки ЩЕ проїжджає дошка після того, як
## палець її зловив. «Ще ~5 одиниць» — поломка; соті частки одиниці, що
## згасають за частку секунди, — уже ні.
func test_catching_a_moving_camera_and_barely_moving_it_does_not_relaunch_a_fling() -> void:
	rig.center_on(Vector2i(10, 10))
	rig.begin_hold()
	_drag_frames(Vector2(20.0, 0.0), 8)
	rig.end_pan()
	rig.end_hold()
	assert_true(rig._inertia_active, "передумова: дошка котиться сама")

	simulate(rig, 10, 1.0 / 60.0)  # дошка встигла проїхати кілька кадрів сама

	# Гравець ляскає пальцем, щоб зупинити рухому дошку — і ворухнув на
	# піксель, як завжди буває в реальному натиску.
	rig.begin_hold()
	rig.cancel_inertia()
	rig.pan(Vector2(1.0, 0.0))
	simulate(rig, 1, 1.0 / 60.0)

	assert_true(rig._pan_velocity.length() < 1.0,
		"1px руху одразу після зупинки жестом не сміє прочитатись як швидкість залишкового польоту — виміряно %s" % rig._pan_velocity)

	var pos_at_catch: Vector3 = rig.global_position
	rig.end_pan()
	if rig._inertia_active:
		simulate(rig, 60, 1.0 / 60.0)  # дати будь-якому залишку часу згаснути дощенту
	rig.end_hold()

	var extra_travel: float = rig.global_position.distance_to(pos_at_catch)
	assert_true(extra_travel < 0.2,
		"«схопив і зупинив» не сміє знову запустити ПОМІТНИЙ кидок — проїхало ще %s одиниць (поломка з ревʼю давала ~5)" % extra_travel)


func test_end_pan_starts_a_fling_that_keeps_moving_the_camera() -> void:
	rig.center_on(Vector2i(10, 10))
	_drag_frames(Vector2(20.0, 0.0), 8)
	var at_release: Vector3 = rig.global_position
	rig.end_pan()

	simulate(rig, 3, 1.0 / 60.0)

	assert_true(rig.global_position.distance_to(at_release) > 0.0001,
		"після end_pan() камера мусить ще проїхати за інерцією кидка, а не спинитись миттєво")

func test_fling_decays_with_friction_and_eventually_stops() -> void:
	rig.center_on(Vector2i(10, 10))
	_drag_frames(Vector2(20.0, 0.0), 8)
	rig.end_pan()
	assert_true(rig._inertia_active, "передумова: кидок стартував")

	# Експоненційне тертя (PAN_FRICTION) — достатньо кадрів (10с) гарантовано
	# заводить швидкість нижче MIN_FLING_SPEED незалежно від того, наскільки
	# швидким був сам кидок; перевіряємо точний прапорець, а не відстань між
	# двома довільними знімками (та залежала б від того, які саме кадри обрані).
	simulate(rig, 600, 1.0 / 60.0)

	assert_false(rig._inertia_active, "тертя мусить погасити кидок — інерція врешті вимикається сама")
	assert_eq(rig._inertia_velocity, Vector3.ZERO, "і швидкість обнуляється разом із прапорцем, а не просто стає малою")

func test_cancel_inertia_stops_a_rolling_fling_immediately() -> void:
	rig.center_on(Vector2i(10, 10))
	_drag_frames(Vector2(20.0, 0.0), 8)
	rig.end_pan()

	rig.cancel_inertia()
	var pos: Vector3 = rig.global_position
	simulate(rig, 30, 1.0 / 60.0)

	assert_eq(rig.global_position, pos, "cancel_inertia() мусить спинити кидок одразу — жодного додаткового зсуву в наступних кадрах")

## Власник відмовився від пружного опору — межа лишається жорстким клемпом
## навіть під час кидка. «Без ривка» тут означає: коли межа гасить рух по
## осі, гаситься й швидкість по ній, а не лишається намагатись проштовхнути
## позицію крізь клемп щокадру.
func test_fling_stops_cleanly_at_the_hard_bound_without_jitter() -> void:
	# Знак навмисно такий: pan(Vector2(60,0)) (пряме маніпулювання — світова
	# точка йде за пальцем) штовхає камеру до ЗРОСТАННЯ z і СПАДАННЯ x — тут
	# перевіряється саме вісь z, яку цей напрям справді впирає в межу.
	rig.center_on(Vector2i(10, 10))
	_drag_frames(Vector2(60.0, 0.0), 20)  # впевнено женемо камеру за z-межу
	rig.end_pan()

	simulate(rig, 10, 1.0 / 60.0)
	var at_bound: Vector3 = rig.global_position
	assert_almost_eq(at_bound.z, 21.0, 0.01, "R12: клемп по z лишається на (board_size-1)+MARGIN")

	simulate(rig, 10, 1.0 / 60.0)
	assert_almost_eq(rig.global_position.z, 21.0, 0.01,
		"після клемпа позиція не сіпається туди-сюди навколо межі — швидкість по z загашена одразу")

# --- view_changed: єдиний спосіб для вигляду дізнатись, що екран поїхав ------
#
# Прив'язані до дошки елементи HUD (панель характеристик, game/ui/hud.gd) не
# сміють опитувати камеру щокадру (§8 — екран здебільшого статичний, батарея
# це фіча), тож ріг сам звітує про кожну зміну своєї екранної геометрії. Джерел
# руху рівно п'ять — і кожне мусить дати сигнал, інакше панель відклеїться саме
# на тому русі, який забули.

func test_pan_reports_that_the_view_changed() -> void:
	rig.center_on(Vector2i(10, 10))
	watch_signals(rig)

	rig.pan(Vector2(40.0, 0.0))

	assert_signal_emitted(rig, "view_changed")

func test_zoom_reports_that_the_view_changed() -> void:
	rig.center_on(Vector2i(10, 10))
	watch_signals(rig)

	rig.zoom_by(0.5)
	simulate(rig, 5, 1.0 / 60.0)

	assert_signal_emitted(rig, "view_changed")

func test_inertia_reports_that_the_view_changed() -> void:
	rig.center_on(Vector2i(10, 10))
	_drag_frames(Vector2(20.0, 0.0), 8)
	rig.end_pan()
	assert_true(rig._inertia_active, "передумова: кидок стартував")
	watch_signals(rig)

	simulate(rig, 3, 1.0 / 60.0)

	assert_signal_emitted(rig, "view_changed")

func test_center_on_reports_that_the_view_changed() -> void:
	rig.center_on(Vector2i(0, 0))
	watch_signals(rig)

	rig.center_on(Vector2i(10, 10))

	assert_signal_emitted(rig, "view_changed")

## fly_to() рухає позицію ТВІНОМ, а не власним кодом рига, тож єдине місце, де
## ріг може помітити цей рух, — його ж _process(). Тому check_is_processing
## тут true: якби ріг вимикав _process() на час польоту (а він вимикав — умова
## виходу нижче знала лише про зум, інерцію й палець), simulate() не покликав
## би _process() взагалі й сигнал не пролунав би жодного разу за весь політ.
func test_fly_to_reports_that_the_view_changed_while_the_tween_runs() -> void:
	rig.center_on(Vector2i(0, 0))
	watch_signals(rig)
	var tween: Tween = rig.fly_to(Vector2i(19, 19))

	tween.custom_step(0.1)
	simulate(rig, 1, 1.0 / 60.0, true)

	assert_signal_emitted(rig, "view_changed")

## §8: політ скінчився — ріг мусить знову замовкнути, інакше утримання
## _process() заради твіна перетворює тимчасову анімацію на постійну роботу
## щокадру.
func test_the_rig_stops_processing_once_the_flight_is_over() -> void:
	var tween: Tween = rig.fly_to(Vector2i(19, 19))
	tween.custom_step(10.0)

	simulate(rig, 2, 1.0 / 60.0)

	assert_false(rig.is_processing(), "після завершення польоту ріг не мусить лишатись у _process")

## Сигнал без цієї умови був би просто «щокадру»: підписник перерахував би
## позицію панелі на нерухомій камері й повернув би витрату, задля уникнення
## якої сигнал і заведений.
func test_a_camera_that_did_not_move_reports_nothing() -> void:
	rig.center_on(Vector2i(10, 10))
	watch_signals(rig)

	rig.center_on(Vector2i(10, 10))
	rig.pan(Vector2.ZERO)
	simulate(rig, 3, 1.0 / 60.0)

	assert_signal_not_emitted(rig, "view_changed")

## R13: уся екранна геометрія рига живе в одному файлі (див. коментар над
## screen_point_to_cell()). Зворотний бік тієї ж проєкції — світова точка на
## екран — мусить бути тут же, а не другою копією у HUD, і мусить збігатися з
## screen_point_to_cell() туди й назад.
func test_unproject_round_trips_with_screen_point_to_cell() -> void:
	rig.center_on(Vector2i(10, 10))
	for c in [Vector2i(10, 10), Vector2i(5, 12), Vector2i(15, 8)]:
		assert_eq(rig.screen_point_to_cell(rig.unproject(rig.cell_to_world(c))), c,
			"клітинка %s мусить пережити unproject() і назад" % c)

func test_screen_point_to_cell_round_trips_through_camera_projection() -> void:
	rig.center_on(Vector2i(10, 10))
	var camera: Camera3D = rig.get_node("Yaw/Camera3D")
	for c in [Vector2i(10, 10), Vector2i(5, 12), Vector2i(15, 8)]:
		var world: Vector3 = rig.cell_to_world(c)
		var screen: Vector2 = camera.unproject_position(world)
		assert_eq(rig.screen_point_to_cell(screen), c, "клітинка %s мусить пережити проєкцію туди й назад" % c)


func test_screen_point_to_cell_degrades_safely_when_the_ray_never_meets_the_board_plane() -> void:
	# Промінь, паралельний площині y=0 (камера дивиться рівно вперед, без
	# нахилу вниз), не має перетину з нею взагалі — деградація мусить бути
	# безпечним значенням поза дошкою (Board.in_bounds() завжди false), а не
	# діленням на нуль чи крашем.
	var camera: Camera3D = rig.get_node("Yaw/Camera3D")
	camera.rotation_degrees = Vector3.ZERO
	var cell: Vector2i = rig.screen_point_to_cell(Vector2(640, 360))
	assert_false(Board.create(20, 20, Terrain.GroundState.DRY).in_bounds(cell))
