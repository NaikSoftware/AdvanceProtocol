extends GutTest
## Task 2.4, ruling R11: живий бій зʼявляється лише в Task 2.10, тож усе тут —
## headless перевірка вузла самого по собі: силует за класом, поворот,
## HP-бар, лічильник дронів, приглушення і твіни. Останній тест — контракт
## тумана: UnitView не читає Vision і не приховує ворога сам (§3.5) —
## існування вузла для чужого юніта вирішує контейнер (Task 2.10).

const UnitViewScene := preload("res://game/battle/unit_view.tscn")

var view: Node3D


func before_each() -> void:
	view = UnitViewScene.instantiate()
	add_child_autofree(view)


func _unit(type_id: int, owner: int = 0, pos: Vector2i = Vector2i(2, 3), facing: int = 0) -> Unit:
	return Unit.create(1, type_id, owner, pos, facing)


func test_bind_places_node_at_cell_world_position() -> void:
	var unit := _unit(5, 0, Vector2i(4, 7))
	view.bind(unit)
	assert_eq(view.position, IsoCameraRig.cell_to_world(unit.pos))


## Один силует на клас, і жоден не збігається з іншим (§1.5). Порівнюємо
## розмір Hull-меша, який справді зібрав bind(), а не число, продубльоване
## з _HULL_SIZES у самому unit_view.gd.
func test_bind_picks_a_distinct_silhouette_per_class() -> void:
	var type_ids: Array[int] = [0, 2, 5, 9, 11]  # по одному представнику на кожен з пʼяти класів
	var seen_sizes: Dictionary = {}
	for type_id in type_ids:
		view.bind(_unit(type_id))
		var hull: MeshInstance3D = view.get_node("Silhouette/Hull")
		var size: Vector3 = (hull.mesh as BoxMesh).size
		seen_sizes[size] = true
	assert_eq(seen_sizes.size(), type_ids.size(), "кожен клас мусить мати власний, ні на який інший не схожий силует")


## R14: face() твінується (не клацає миттєво), тож перевіряємо ціль твіна
## через custom_step — той самий прийом, що й для move_along/play_destroyed,
## а не читаємо rotation_degrees.y одразу після виклику.
func test_face_produces_eight_distinct_orientations() -> void:
	view.bind(_unit(5))
	var seen: Dictionary = {}
	for d in 8:
		view.face(d)
		view._face_tween.custom_step(10.0)
		seen[view.rotation_degrees.y] = true
	assert_eq(seen.size(), 8, "вісім напрямків мусять дати вісім різних поворотів")


## R14: з 315° (NW) на 0°/360° (N) — сусідні напрямки через межу кола.
## Короткий шлях — 45°; в обхід було б 315°. Перевіряємо саму подорож
## (різницю між початковим і кінцевим кутом), а не конкретне число з
## формули найкоротшої дельти — інакше тест лише повторив би реалізацію.
func test_face_takes_the_short_way_around_the_wrap() -> void:
	view.bind(_unit(5))
	view.face(7)  # NW, 315°
	view._face_tween.custom_step(10.0)
	var start: float = view.rotation_degrees.y

	view.face(0)  # N, 0°/360° — прямий сусід NW через межу 360°/0°
	view._face_tween.custom_step(10.0)
	var travelled: float = absf(view.rotation_degrees.y - start)

	assert_true(travelled <= 180.0, "поворот через межу кола мусить іти коротким шляхом (45°), не в обхід (315°)")


## Другий face(), що прийшов поки перший ще крутиться, не мусить лишити два
## твіни, які тягнуть rotation_degrees.y кожен у свій бік — переривання
## вбиває попередній твін і замінює його новим.
func test_face_interrupting_face_kills_the_previous_tween() -> void:
	view.bind(_unit(5))
	view.face(1)
	var first_tween: Tween = view._face_tween

	view.face(3)  # перериваємо на півдорозі новим поворотом
	assert_false(first_tween.is_valid(), "перший твін мусить бути вбитий другим face(), а не лишитись живим")
	assert_ne(view._face_tween, first_tween, "після переривання лишається лише новий твін")
	view._face_tween.custom_step(10.0)

	# Контрольний вузол без переривання — довести, що фінальна ціль та сама,
	# що й у чистого виклику face(3), а не проміжний стан першого твіна.
	var reference: Node3D = UnitViewScene.instantiate()
	add_child_autofree(reference)
	reference.bind(_unit(5))
	reference.face(3)
	reference._face_tween.custom_step(10.0)

	assert_eq(view.rotation_degrees.y, reference.rotation_degrees.y, "фінальний поворот — ціль останнього виклику face(), не проміжний")


## Виправлення 1: свіжий вузол не мав попередньої орієнтації, з якої мало б
## сенс анімувати «доведення» — bind() виставляє факінг миттєво, не через
## твінований face().
func test_bind_sets_facing_instantly_without_animating() -> void:
	var unit := _unit(5, 0, Vector2i(2, 3), 5)
	view.bind(unit)
	# almost_eq, не eq: Godot зберігає обертання як Basis, тож round-trip
	# градуси->радіани->Basis->градуси на цьому значенні вносить похибку
	# порядку 1e-5° (перевірено — не наслідок нашої формули).
	assert_almost_eq(view.rotation_degrees.y, 5.0 * 45.0, 0.001, "bind() мусить виставити факінг миттєво, без твіна")
	assert_true(view._face_tween == null or not view._face_tween.is_valid(), "bind() не має лишати живий твін повороту")


## Перебудова вузлів (battle_screen._rebuild_units_for_active_player) створює
## новий UnitView і одразу кличе bind() — але контракт тут перевіряється й на
## живому вузлі: повторний bind() під час незавершеного face()-твіна мусить
## убити його, а не лишити два джерела правди для rotation_degrees.y.
func test_bind_kills_a_live_face_tween_from_previous_bind() -> void:
	view.bind(_unit(5, 0, Vector2i(0, 0), 0))
	view.face(4)  # запускаємо твін, який ще не встиг дограти
	var live_tween: Tween = view._face_tween
	assert_true(live_tween.is_valid())

	view.bind(_unit(5, 0, Vector2i(0, 0), 2))
	assert_false(live_tween.is_valid(), "повторний bind() мусить убити живий твін попереднього повороту")
	assert_almost_eq(view.rotation_degrees.y, 2.0 * 45.0, 0.001, "новий bind() виставляє факінг миттєво, ігноруючи недограний твін")


func test_set_hp_reflects_ratio_including_full_and_zero() -> void:
	view.bind(_unit(5))
	view.set_hp(400, 400)
	assert_eq(view._hp_bar.scale.x, 1.0, "повне HP — повна смуга")
	view.set_hp(0, 400)
	assert_eq(view._hp_bar.scale.x, 0.0, "нуль HP — порожня смуга")
	view.set_hp(200, 400)
	assert_eq(view._hp_bar.scale.x, 0.5, "проміжне HP — пропорційна смуга")


func test_set_hp_handles_zero_max_hp_without_dividing_by_zero() -> void:
	view.bind(_unit(5))
	view.set_hp(0, 0)
	assert_eq(view._hp_bar.scale.x, 0.0, "max_hp=0 не мусить кинути помилку ділення на нуль")


## §3.9: залишок дронів публічний — метод навіть не має доступу до owner,
## тож ця перевірка доводить «байдуже, чий юніт» буквально, а не за словами.
func test_set_drones_shows_count_regardless_of_owner() -> void:
	var view_a: Node3D = UnitViewScene.instantiate()
	var view_b: Node3D = UnitViewScene.instantiate()
	add_child_autofree(view_a)
	add_child_autofree(view_b)
	view_a.bind(_unit(1, 0))
	view_b.bind(_unit(1, 1))

	view_a.set_drones(2)
	view_b.set_drones(2)
	assert_true(view_a._drone_icon.visible, "власник 0 бачить лічильник")
	assert_true(view_b._drone_icon.visible, "власник 1 бачить той самий лічильник")
	assert_eq(view_a._drone_icon.scale, view_b._drone_icon.scale, "лічильник не має гілки на власника")

	view_a.set_drones(0)
	assert_false(view_a._drone_icon.visible, "нуль дронів — лічильник ховається")


func test_set_dimmed_toggles_and_is_reversible() -> void:
	view.bind(_unit(5))
	var base_color: Color = view._hull_material.albedo_color
	view.set_dimmed(true)
	var dimmed_color: Color = view._hull_material.albedo_color
	assert_ne(dimmed_color, base_color, "приглушення мусить змінити колір корпусу")
	view.set_dimmed(false)
	assert_eq(view._hull_material.albedo_color, base_color, "зняття приглушення повертає точнісінько вихідний колір")


## Await на tween.finished крихкий у headless-тестах — прокручуємо твін
## вручну через custom_step замість очікування реального часу.
func test_move_along_tweens_position_to_final_cell() -> void:
	view.bind(_unit(5, 0, Vector2i(0, 0)))
	var path: Array[Vector2i] = [Vector2i(1, 0), Vector2i(1, 1)]
	var finished: Signal = view.move_along(path, 0.05)
	var tween: Tween = finished.get_object()
	assert_not_null(tween, "move_along мусить повертати сигнал живого твіна")
	tween.custom_step(10.0)
	assert_eq(view.position, IsoCameraRig.cell_to_world(Vector2i(1, 1)), "після прокрутки твіна юніт стоїть на останній клітинці шляху")


## Виправлення 2: юніт довертається на кожному кроці шляху, паралельно з
## рухом (Board.facing_towards, чиста функція core/). Крок 1 — на схід
## (facing=2), крок 2 — на південь (facing=4); прокручуємо твін по одному
## кроку за раз, щоб зловити орієнтацію саме там, де вона мала б змінитись.
func test_move_along_turns_the_unit_at_each_step() -> void:
	view.bind(_unit(5, 0, Vector2i(0, 0), 0))  # дивиться на північ (facing=0)
	var path: Array[Vector2i] = [Vector2i(1, 0), Vector2i(1, 1)]
	var finished: Signal = view.move_along(path, 0.1)
	var tween: Tween = finished.get_object()

	tween.custom_step(0.1)  # рівно перший крок
	assert_eq(view.position, IsoCameraRig.cell_to_world(Vector2i(1, 0)), "перший крок довозить до першої клітинки")
	assert_eq(view.rotation_degrees.y, 2.0 * 45.0, "після кроку на схід юніт дивиться на схід (facing=2)")

	tween.custom_step(0.1)  # рівно другий крок
	assert_eq(view.position, IsoCameraRig.cell_to_world(Vector2i(1, 1)), "другий крок довозить до другої клітинки")
	assert_eq(view.rotation_degrees.y, 4.0 * 45.0, "після кроку на південь юніт дивиться на південь (facing=4)")


## Поворот іде ПАРАЛЕЛЬНО з рухом, не додаючи часу до кроку: рівно
## path.size() * duration_per_step повністю прокручує твін до кінця шляху.
## Якби поворот додавав час послідовно, цієї прокрутки не вистачило б.
func test_move_along_turning_does_not_add_time_to_the_step() -> void:
	view.bind(_unit(5, 0, Vector2i(0, 0), 0))
	var path: Array[Vector2i] = [Vector2i(1, 0), Vector2i(1, 1)]
	var finished: Signal = view.move_along(path, 0.1)
	var tween: Tween = finished.get_object()
	tween.custom_step(0.2)
	assert_eq(view.position, IsoCameraRig.cell_to_world(Vector2i(1, 1)), "рух і поворот ідуть паралельно — сумарний час лишається path.size() * duration_per_step")


## MoveCommand.facing (core/commands/move_command.gd) — явний параметр, і
## подія несе його як останнє слово: фінальна орієнтація мусить бути саме
## ним, навіть коли він навмисно відрізняється від напрямку останнього кроку.
func test_move_along_final_facing_overrides_last_step_direction() -> void:
	view.bind(_unit(5, 0, Vector2i(0, 0), 0))
	var path: Array[Vector2i] = [Vector2i(1, 0)]  # крок на схід (facing=2)
	var finished: Signal = view.move_along(path, 0.1, 6)  # явний фінальний facing — захід
	var tween: Tween = finished.get_object()
	tween.custom_step(10.0)
	assert_eq(view.position, IsoCameraRig.cell_to_world(Vector2i(1, 0)), "позиція визначається шляхом, не фінальним факінгом")
	# fposmod: формула найкоротшого шляху (та сама, що й у face()) законно
	# лишає значення поза [0, 360) — наприклад -90.0 замість еквівалентного
	# 270.0 — це той самий кут, коротшим шляхом.
	assert_almost_eq(fposmod(view.rotation_degrees.y, 360.0), fposmod(6.0 * 45.0, 360.0), 0.001,
		"фінальна орієнтація — переданий facing, а не напрямок останнього кроку")


func test_move_along_with_empty_path_still_finishes_without_moving() -> void:
	view.bind(_unit(5, 0, Vector2i(2, 2)))
	var start_pos: Vector3 = view.position
	var empty_path: Array[Vector2i] = []
	var finished: Signal = view.move_along(empty_path, 0.05)
	var tween: Tween = finished.get_object()
	tween.custom_step(10.0)
	assert_eq(view.position, start_pos, "порожній шлях не мусить зрушити юніт")


func test_play_destroyed_returns_a_finishing_tween() -> void:
	view.bind(_unit(5))
	var finished: Signal = view.play_destroyed()
	var tween: Tween = finished.get_object()
	tween.custom_step(10.0)
	assert_eq(view.scale, Vector3.ZERO, "знищення — твін масштабу до нуля")


## §3.5: невидимий ворог не має вузла взагалі — рішення контейнера
## (Task 2.10), не цього вузла. UnitView свідомо не має фог-подібного методу
## і не посилається на Vision у власному коді.
func test_no_fog_shaped_method_and_no_vision_reference() -> void:
	assert_false(view.has_method("apply_fog"), "UnitView не приховує сам себе — це робота контейнера")
	assert_false(view.has_method("is_visible_to"), "видимість вирішує Task 2.10, не цей вузол")
	var source: String = FileAccess.get_file_as_string("res://game/battle/unit_view.gd")
	assert_false(source.contains("Vision"), "UnitView не має споживати Vision узагалі")
