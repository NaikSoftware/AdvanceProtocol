extends GutTest
## Task 2.4, рішення R11: живий бій з'являється лише в Task 2.10, тож усе тут —
## headless перевірка вузла самого по собі: силует за класом, поворот,
## HP-бар, лічильник дронів, приглушення і твіни. Останній тест — контракт
## тумана: UnitView не читає Vision і не приховує ворога сам (§3.5) —
## існування вузла для чужого юніта вирішує контейнер (Task 2.10).

const UnitViewScene := preload("res://game/battle/unit_view.tscn")

var view: Node3D


func before_each() -> void:
	view = UnitViewScene.instantiate()
	add_child_autofree(view)


func after_each() -> void:
	# Статичне поле на весь процес: тест, що впав посередині, не сміє лишити рельєф решті набору.
	TerrainHeight.active = null
	WeatherRig.unit_contact = 0.0


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
	var type_ids: Array[int] = [0, 2, 5, 9, 11]  # по одному представнику на кожен з п'яти класів
	var seen_sizes: Dictionary = {}
	for type_id in type_ids:
		view.bind(_unit(type_id))
		var hull: MeshInstance3D = view.get_node("Silhouette/Hull")
		var size: Vector3 = (hull.mesh as BoxMesh).size
		seen_sizes[size] = true
	assert_eq(seen_sizes.size(), type_ids.size(), "кожен клас мусить мати власний, ні на який інший не схожий силует")


## Тінь-контакт: плаский квад під корпусом, ширший за його слід, сам тіні від сонця не кидає;
## лежить у силуеті, тож нахиляється й ховається разом із юнітом.
func test_unit_has_a_flat_contact_shadow_under_its_hull() -> void:
	WeatherRig.unit_contact = 0.6
	for type_id: int in [0, 5, 11]:
		view.bind(_unit(type_id))
		var blob: MeshInstance3D = view.get_node("Silhouette/ContactShadow")
		var hull: Vector3 = (view.get_node("Silhouette/Hull").mesh as BoxMesh).size
		var size: Vector2 = (blob.mesh as PlaneMesh).size
		assert_gt(size.x, hull.x)
		assert_gt(size.y, hull.z)
		assert_between(blob.position.y, 0.0, 0.05, "на ґрунті, під корпусом")
		assert_eq(blob.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)


## Без тіні-контакту у вигляді карти пляму не будують зовсім: прозорий квад під кожним юнітом —
## зайвий виклик малювання.
func test_no_contact_shadow_when_the_look_has_none() -> void:
	WeatherRig.unit_contact = 0.0
	for type_id: int in [0, 5]:
		view.bind(_unit(type_id))
		assert_null(view.get_node_or_null("Silhouette/ContactShadow"))


## Загиблі фігури лежать на ґрунті, тож пляма під відділенням зникає разом зі стоячими.
func test_squad_contact_shadow_goes_with_the_squad() -> void:
	WeatherRig.unit_contact = 0.6
	view.bind(_unit(0))
	view.play_destroyed()
	assert_false((view.get_node("Silhouette/ContactShadow") as Node3D).visible)


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
	_assert_faces(view, 5, "bind() мусить виставити факінг миттєво, без твіна")
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
	_assert_faces(view, 2, "новий bind() виставляє факінг миттєво, ігноруючи недограний твін")


## Колір, прогнаний через ту саму 8-бітну текстуру, що й у виду: RGBA8
## квантує 0.5 у 127/255, тож пряме порівняння з Color.RED.lerp(...) було б
## хибно-червоним не через баг реалізації, а через формат зберігання.
func _as_rgba8(color: Color) -> Color:
	var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return image.get_pixel(0, 0)


func _hp_bar_image(unit_view: UnitView) -> Image:
	return unit_view._hp_bar.texture.get_image()


func test_set_hp_reflects_ratio_including_full_and_zero() -> void:
	view.bind(_unit(5))
	view.set_hp(400, 400)
	assert_eq(view.hp_ratio(), 1.0, "повне HP — повна смуга")
	view.set_hp(0, 400)
	assert_eq(view.hp_ratio(), 0.0, "нуль HP — порожня смуга")
	view.set_hp(200, 400)
	assert_eq(view.hp_ratio(), 0.5, "проміжне HP — пропорційна смуга")


func test_set_hp_handles_zero_max_hp_without_dividing_by_zero() -> void:
	view.bind(_unit(5))
	view.set_hp(0, 0)
	assert_eq(view.hp_ratio(), 0.0, "max_hp=0 не мусить кинути помилку ділення на нуль")


## Скарга власника: «полоска квадратна, має бути тонша і довша, з рамкою».
## Рамка й тло — всередині ОДНІЄЇ текстури, а не три накладені спрайти
## (z-fighting білбордів на одній висоті + бюджет ~100 draw call'ів, §8).
func test_hp_bar_texture_is_framed_and_long_not_square() -> void:
	view.bind(_unit(5))
	view.set_hp(200, 400)
	var image: Image = _hp_bar_image(view)
	# Точні числа, не «принаймні вшестеро довша»: м'яка нерівність лишалась би
	# зеленою і для 36×6, хоча форма задана рівно як 48×6, — тобто стерегла б
	# менше, ніж обіцяє її ж назва.
	assert_eq(Vector2i(image.get_width(), image.get_height()), Vector2i(48, 6),
		"смуга мусить бути рівно 48×6 — довга й тонка, а не квадрат")
	assert_eq(image.get_pixel(0, 0), _as_rgba8(UnitView._HP_BAR_FRAME_COLOR), "лівий верхній кут — рамка")
	assert_eq(image.get_pixel(image.get_width() - 1, image.get_height() - 1), _as_rgba8(UnitView._HP_BAR_FRAME_COLOR),
		"правий нижній кут — рамка")
	assert_eq(image.get_pixel(1, image.get_height() / 2), _as_rgba8(Color.RED.lerp(Color.GREEN, 0.5)),
		"всередині, від лівого краю — заливка кольору поточного співвідношення")


## Смуга витрачається ЗЛІВА НАПРАВО (як у референсі), а не стискається до
## центру — саме те, що робив старий scale.x.
func test_hp_bar_fill_runs_from_the_left_edge_and_shrinks_rightwards() -> void:
	view.bind(_unit(5))
	var mid_y: int = _hp_bar_image(view).get_height() / 2
	var width: int = _hp_bar_image(view).get_width()

	view.set_hp(400, 400)
	assert_eq(_hp_bar_image(view).get_pixel(width - 2, mid_y), _as_rgba8(Color.GREEN),
		"повне HP — заливка доходить до внутрішнього правого краю")

	view.set_hp(200, 400)
	assert_eq(_hp_bar_image(view).get_pixel(1, mid_y), _as_rgba8(Color.RED.lerp(Color.GREEN, 0.5)),
		"половина HP — лівий внутрішній піксель усе ще залитий")
	assert_eq(_hp_bar_image(view).get_pixel(width - 2, mid_y), _as_rgba8(UnitView._HP_BAR_BACK_COLOR),
		"половина HP — правий внутрішній піксель порожній")

	view.set_hp(0, 400)
	assert_eq(_hp_bar_image(view).get_pixel(1, mid_y), _as_rgba8(UnitView._HP_BAR_BACK_COLOR),
		"нуль HP — жодного пікселя заливки, лише тло")


## Точна ширина заливки, а не «десь приблизно»: рамка забирає рівно по
## одному пікселю з кожного боку, тож внутрішня ширина — width-2.
func test_hp_bar_fill_width_is_exactly_the_ratio_of_the_inner_width() -> void:
	view.bind(_unit(5))
	view.set_hp(100, 400)  # рівно чверть
	var image: Image = _hp_bar_image(view)
	var mid_y: int = image.get_height() / 2
	var filled: int = 0
	for x in range(1, image.get_width() - 1):
		if image.get_pixel(x, mid_y) != _as_rgba8(UnitView._HP_BAR_BACK_COLOR):
			filled += 1
	# Число написане явно, а не зібране тією ж формулою, що й код: 48 пікселів
	# текстури, рамка по 1 з кожного боку, чверть від 46 — це 12. Очікування,
	# пораховане тим самим roundi(inner * ratio), лишалось би зеленим і при
	# зміненій рамці, і при підміні roundi на floori, тобто повторювало б код
	# замість перевіряти його (та сама пастка, що вже ловила цей проєкт на
	# факінгу).
	assert_eq(filled, 12, "чверть від внутрішніх 46 пікселів — це рівно 12 залитих")


## «Треба вказати скільки було і скільки стало, по типу 88/400» — числа
## поточне/максимум, тим самим текстом, який справді видно на екрані.
func test_hp_label_shows_current_over_max() -> void:
	view.bind(_unit(5))
	view.set_hp(88, 400)
	assert_eq(view._hp_label.text, "88/400", "підпис мусить показувати поточне HP і максимум")
	view.set_hp(0, 400)
	assert_eq(view._hp_label.text, "0/400", "знищений юніт показує нуль, а не порожній підпис")


## Підпис мусить читатись на світлій місцевості — без контуру світлі цифри
## губляться (§1.5: кожне правило-число мусить бути видиме).
func test_hp_label_has_an_outline_and_billboards() -> void:
	view.bind(_unit(5))
	assert_true(view._hp_label.outline_size > 0, "цифри без контуру губляться на світлому тлі")
	assert_ne(view._hp_label.outline_modulate, view._hp_label.modulate, "контур мусить контрастувати із самими цифрами")
	assert_ne(view._hp_label.billboard, BaseMaterial3D.BILLBOARD_DISABLED, "підпис мусить дивитись у камеру, як і сама смуга")


## Стереже ПОРЯДОК трьох висот у сцені: смуга, над нею підпис, ще вище
## лічильник дронів. Свідомо НЕ перевіряє перекриття габаритів — порівнюються
## центри вузлів, тож роздутий контур підпису чи масштаб іконки дронів цей тест
## не спіймає (назва раніше обіцяла саме це й уводила в оману). Реальні
## габарити Label3D headless не міряються; це лишається на око в живому вікні.
func test_hp_label_and_drone_icon_are_stacked_above_the_bar_in_order() -> void:
	view.bind(_unit(5))
	assert_true(view._hp_bar.position.y < view._hp_label.position.y, "підпис сидить над смугою")
	assert_true(view._hp_label.position.y < view._drone_icon.position.y, "лічильник дронів сидить над підписом")


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


## Task 2, вимога «легко прибрати одним рухом»: одна очевидна точка
## вимкнення, а не десяток вкраплень по коду — рівно ОДНЕ місце будує
## стрілку (виклик _build_facing_arrow), а не кілька розкиданих додавань.
func test_debug_facing_arrow_has_a_single_build_call_site() -> void:
	var source: String = FileAccess.get_file_as_string("res://game/battle/unit_view.gd")
	var call_count: int = source.count("_build_facing_arrow(")
	assert_eq(call_count, 2, "рівно одне визначення й рівно один виклик _build_facing_arrow — жодних розкиданих додавань стрілки по файлу")


## Скарга власника: «якщо я клікнув для атаки на чужого юніта, то треба це
## якось позначити». Приціл — власність цього вузла, але НЕ його рішення:
## вмикає його контейнер із готового прев'ю (battle_screen), тож тут
## перевіряється лише сам перемикач і те, що свіжий вузол ніколи не
## народжується вже прицільованим.
func test_crosshair_is_hidden_by_default_and_after_bind() -> void:
	assert_false(view._crosshair.visible, "свіжий вузол не мусить бути прицільований")
	view.set_targeted(true)
	view.bind(_unit(5))
	assert_false(view._crosshair.visible, "bind() мусить лишати приціл згашеним — новий юніт не ціль")


func test_set_targeted_toggles_the_crosshair() -> void:
	view.bind(_unit(5))
	view.set_targeted(true)
	assert_true(view._crosshair.visible, "позначена ціль мусить показувати приціл")
	view.set_targeted(false)
	assert_false(view._crosshair.visible, "знята позначка мусить гасити приціл")


## Приціл читається поверх корпусу, але мусить лишатись нижче HP-бару й
## лічильника дронів — ті вже підняті над силуетом саме заради читабельності
## (§1.5), і накладання перетворило б обидва на кашу на телефоні.
func test_crosshair_sits_below_hp_bar_and_drone_icon() -> void:
	view.bind(_unit(5))
	assert_true(view._crosshair.position.y < view._hp_bar.position.y, "приціл мусить лишатись нижче HP-бару")
	assert_true(view._crosshair.position.y < view._drone_icon.position.y, "приціл мусить лишатись нижче лічильника дронів")


## Колір прицілу — рівно той самий, яким UnitInspector.MODULATE_HIT підсвічує
## сектор влучання (game/ui/unit_inspector.gd:40): один сигнал «сюди
## прилетить» на панелі й на дошці, а не два різні кольори про одне влучання.
func test_crosshair_uses_the_same_hit_colour_as_the_inspector_sector() -> void:
	view.bind(_unit(5))
	assert_eq(view._crosshair.modulate, Color("ff7a4a"), "приціл мусить нести рівно колір влучання UnitInspector.MODULATE_HIT")
	assert_eq(view._crosshair.modulate, UnitInspector.MODULATE_HIT, "і саме той самий, а не схожий")


## Форма, а не пляма: процедурна текстура мусить лишати центр порожнім (крізь
## приціл видно сам силует, який гравець і намагається впізнати, §1.5) і при
## цьому щось таки малювати. Порожня чи суцільна текстура — обидві помилки
## виглядають на дошці як «приціл не працює», і жоден інший тест їх не ловить.
func test_crosshair_texture_is_a_ring_not_a_blob() -> void:
	var image: Image = view._crosshair.texture.get_image()
	assert_eq(image.get_pixel(image.get_width() / 2, image.get_height() / 2).a, 0.0, "центр прицілу мусить лишатись прозорим")
	var opaque: int = 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.5:
				opaque += 1
	var total: int = image.get_width() * image.get_height()
	assert_true(opaque > 0, "текстура прицілу не мусить бути порожньою")
	assert_true(opaque < total / 2, "і не мусить бути залитим квадратом")


## Корпус фарбує ВЛАСНИК і більше ніщо. Раніше bind() ще й приглушував
## корпус юніта, який уже стріляв, — власник цього не замовляв і прибрав
## («прибери приглушення взагалі»). Тест тримає саме це: жоден стан юніта,
## крім власника, не має права чіпати колір корпусу.
func test_hull_colour_comes_from_owner_and_nothing_else() -> void:
	var fresh := _unit(5)
	view.bind(fresh)
	var base_color: Color = view._hull_material.albedo_color

	var fired := _unit(5)
	fired.exhaust()
	fired.hp = fired.max_hp() / 2
	view.bind(fired)
	assert_eq(view._hull_material.albedo_color, base_color,
		"постріл і поранення не мусять міняти колір корпусу")


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


## Виправлення 3: юніт довертається НА МІСЦІ ПЕРЕД кожним кроком шляху, що
## справді міняє напрямок (Board.facing_towards, чиста функція core/), а не
## паралельно з рухом. Крок 1 — на схід (facing=2), крок 2 — на південь
## (facing=4); обидва — доворот (FACE_TURN_DURATION=0.15) стартовий з
## facing=0, тож кожен крок шляху займає 0.15+0.1=0.25с сумарно.
func test_move_along_turns_the_unit_at_each_step() -> void:
	view.bind(_unit(5, 0, Vector2i(0, 0), 0))  # дивиться на північ (facing=0)
	var path: Array[Vector2i] = [Vector2i(1, 0), Vector2i(1, 1)]
	var finished: Signal = view.move_along(path, 0.1)
	var tween: Tween = finished.get_object()

	tween.custom_step(0.25)  # рівно перший крок: доворот + рух
	assert_eq(view.position, IsoCameraRig.cell_to_world(Vector2i(1, 0)), "перший крок довозить до першої клітинки")
	_assert_faces(view, 2, "після кроку на схід юніт дивиться на схід (facing=2)")

	tween.custom_step(0.25)  # рівно другий крок: доворот + рух
	assert_eq(view.position, IsoCameraRig.cell_to_world(Vector2i(1, 1)), "другий крок довозить до другої клітинки")
	_assert_faces(view, 4, "після кроку на південь юніт дивиться на південь (facing=4)")


## Баг-звіт: «на старті вибираю танк, вказую їхати вперед — він їде спиною».
## Причина — минула версія тягнула поворот і рух паралельно в тому самому
## кроці, тож юніт в'їжджав у новий тайл носом ще в СТАРУ сторону і лише
## дорогою довертався; на 180° це виглядає рівно як задній хід. Правильно —
## юніт спершу довертається НА МІСЦІ (позиція не зрушена), і лише потім їде;
## позиція мусить лишитись у стартовому тайлі, поки триває лише поворот.
func test_move_along_turns_in_place_before_moving_when_direction_reverses() -> void:
	view.bind(_unit(5, 0, Vector2i(0, 0), 4))  # дивиться на південь (facing=4)
	var path: Array[Vector2i] = [Vector2i(0, -1)]  # крок на північ — рівно 180° від поточного факінгу
	var finished: Signal = view.move_along(path, 0.1)
	var tween: Tween = finished.get_object()

	tween.custom_step(0.15)  # рівно тривалість довороту на місці, ще без руху
	assert_eq(view.position, IsoCameraRig.cell_to_world(Vector2i(0, 0)), "поки триває доворот, юніт мусить лишатись на стартовій клітинці — не їхати заднім ходом")
	_assert_faces(view, 0, "доворот на 180° мусить завершитись ДО того, як юніт зрушить з місця")

	tween.custom_step(0.1)  # рівно duration_per_step руху
	assert_eq(view.position, IsoCameraRig.cell_to_world(Vector2i(0, -1)), "після довороту юніт доїжджає до цільової клітинки носом уперед")


## Поворот додає час рівно тоді, коли кут справді змінюється (на старті руху
## й на поворотах маршруту) — і НЕ додає жодного часу на прямій ділянці, де
## напрямок кроку збігається з уже виставленим факінгом. Юніт уже дивиться на
## схід (facing=2, той самий, що й перший крок шляху) — обидва кроки йдуть
## строго на схід, тож жодного довороту не потрібно взагалі.
func test_move_along_adds_no_time_when_direction_does_not_change() -> void:
	view.bind(_unit(5, 0, Vector2i(0, 0), 2))  # вже дивиться на схід (facing=2)
	var path: Array[Vector2i] = [Vector2i(1, 0), Vector2i(2, 0)]  # обидва кроки — на схід
	var finished: Signal = view.move_along(path, 0.1)
	var tween: Tween = finished.get_object()
	tween.custom_step(0.2)  # рівно path.size() * duration_per_step, без жодного довороту
	assert_eq(view.position, IsoCameraRig.cell_to_world(Vector2i(2, 0)), "без жодного повороту сумарний час лишається path.size() * duration_per_step")


## Поворот маршруту (не старт) теж мусить довертати ПЕРЕД рухом у тайл,
## де напрямок міняється — не лише перший крок шляху.
func test_move_along_turns_in_place_at_a_route_turn_not_only_at_the_start() -> void:
	view.bind(_unit(5, 0, Vector2i(0, 0), 2))  # дивиться на схід (facing=2) — перший крок не потребує довороту
	var path: Array[Vector2i] = [Vector2i(1, 0), Vector2i(1, 1)]  # схід, потім поворот на південь
	var finished: Signal = view.move_along(path, 0.1)
	var tween: Tween = finished.get_object()

	tween.custom_step(0.1)  # перший крок — без довороту, рівно duration_per_step
	assert_eq(view.position, IsoCameraRig.cell_to_world(Vector2i(1, 0)), "перший крок співпадає з поточним факінгом — жодної паузи")

	tween.custom_step(0.15)  # доворот на другому кроці (схід -> південь), позиція ще на першому тайлі
	assert_eq(view.position, IsoCameraRig.cell_to_world(Vector2i(1, 0)), "доворот на повороті маршруту теж іде ДО руху в нову клітинку")
	_assert_faces(view, 4, "доворот на повороті маршруту завершується перед в'їздом у клітинку")

	tween.custom_step(0.1)
	assert_eq(view.position, IsoCameraRig.cell_to_world(Vector2i(1, 1)), "після довороту юніт доїжджає до другої клітинки")


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
	_assert_faces(view, 6, "фінальна орієнтація — переданий facing, а не напрямок останнього кроку")


func test_move_along_with_empty_path_still_finishes_without_moving() -> void:
	view.bind(_unit(5, 0, Vector2i(2, 2)))
	var start_pos: Vector3 = view.position
	var empty_path: Array[Vector2i] = []
	var finished: Signal = view.move_along(empty_path, 0.05)
	var tween: Tween = finished.get_object()
	tween.custom_step(10.0)
	assert_eq(view.position, start_pos, "порожній шлях не мусить зрушити юніт")


func test_destroyed_squad_lays_all_figures_down_instead_of_shrinking() -> void:
	view.bind(_unit(0))
	var finished: Signal = view.play_destroyed()
	(finished.get_object() as Tween).custom_step(10.0)
	assert_eq(view.standing_figures(), 0)
	assert_eq(view.scale, Vector3.ONE, "відділення не стискається в точку — фігури падають")
	assert_false(view._hp_bar.visible)


func _figures() -> MultiMeshInstance3D:
	return view.get_node("Silhouette/Figures") as MultiMeshInstance3D


## Відділення — чотири фігури одним викликом малювання; стоїть одна на кожну чверть HP, що
## лишилась (`ceil(4 · hp / max_hp)`), решта лежить на тій самій основі.
func test_squad_shows_one_standing_figure_per_quarter_of_hp() -> void:
	view.bind(_unit(0))
	assert_eq(_figures().multimesh.instance_count, UnitView.SQUAD_FIGURES)
	assert_eq(UnitView.SQUAD_FIGURES, 4)
	var cases: Dictionary = {100: 4, 76: 4, 75: 3, 74: 3, 50: 2, 26: 2, 25: 1, 1: 1, 0: 0}
	for hp: int in cases:
		view.set_hp(hp, 100)
		assert_eq(view.standing_figures(), cases[hp], "hp %d" % hp)


func test_fallen_figure_lies_flat_and_low() -> void:
	var standing: Transform3D = UnitSilhouettes.figure_transform(0, true)
	var fallen: Transform3D = UnitSilhouettes.figure_transform(3, false)
	assert_eq(roundi(standing.basis.y.normalized().y), 1, "жива фігура стоїть")
	assert_eq(roundi(fallen.basis.y.normalized().y), 0, "загибла лежить")
	assert_true(fallen.origin.y < standing.origin.y)


func test_vehicles_have_no_figures() -> void:
	view.bind(_unit(5))
	assert_null(view.get_node_or_null("Silhouette/Figures"))
	assert_eq(view.standing_figures(), 0)


func _explosions() -> Array[Node]:
	return view.get_parent().find_children("Explosion*", "", false, false)


## Техніка не стискається в точку: спалах і вогняна куля над тайлом, а сам юніт
## зникає під ними — уламки на тому самому тайлі ставить WreckLeft, а не цей вузол.
func test_vehicle_destruction_flashes_and_hides_the_unit_under_the_fireball() -> void:
	view.bind(_unit(5, 1, Vector2i(4, 2)))
	var finished: Signal = view.play_destroyed()
	assert_false(view._hp_bar.visible, "HP-бар зникає в мить загибелі, а не з кулею")
	assert_false(view._hp_label.visible)
	var boom: Array[Node] = _explosions()
	assert_eq(boom.size(), 1, "рівно одна вогняна куля")
	assert_eq((boom[0] as Node3D).position, view.position)
	var ended: Array[bool] = [false]
	finished.connect(func() -> void: ended[0] = true)
	(finished.get_object() as Tween).custom_step(UnitView.KILL_HIDE_DELAY + 0.001)
	assert_false(view._silhouette.visible, "під кулею юніта вже нема")
	# Анімація закінчується тим самим кроком, яким ховає юніт: наступна подія, WreckLeft,
	# ставить уламки в тому самому кадрі — порожнього тайла між ними не видно.
	assert_true(ended[0])
	assert_eq(view.scale, Vector3.ONE, "техніку не стискає")


## Вибух — одноразовий: чекати його повністю не треба (уламки мусять з'явитися ще
## під кулею), але й лишатися в кадрі він не сміє — звільняє себе сам.
func test_explosion_is_one_shot_and_frees_itself() -> void:
	view.bind(_unit(5))
	view.play_destroyed()
	var boom: Node = _explosions()[0]
	for t in Engine.get_main_loop().get_processed_tweens():
		if t.is_valid():
			t.custom_step(BattleFx.EXPLOSION_SEC + 0.01)
	assert_true(boom.is_queued_for_deletion())
	assert_true(BattleFx.EXPLOSION_SEC <= 2.0, "куля знищення разом із темним хвостом — до 2 с")


## §3.5: невидимий ворог не має вузла взагалі — рішення контейнера
## (Task 2.10), не цього вузла. UnitView свідомо не має фог-подібного методу
## і не посилається на Vision у власному коді.
func test_no_fog_shaped_method_and_no_vision_reference() -> void:
	assert_false(view.has_method("apply_fog"), "UnitView не приховує сам себе — це робота контейнера")
	assert_false(view.has_method("is_visible_to"), "видимість вирішує Task 2.10, не цей вузол")
	var source: String = FileAccess.get_file_as_string("res://game/battle/unit_view.gd")
	assert_false(source.contains("Vision"), "UnitView не має споживати Vision узагалі")


## Перевіряємо НАПРЯМОК У СВІТІ, а не число градусів. Саме звірка кута з
## формулою `facing * 45` і дозволила помилці зі знаком прожити стільки: тест
## повторював ту саму помилку, що й код, і тому був завжди зелений. Board.DIRS_8
## — незалежне джерело правди, і воно ловить дзеркальний схід/захід.
func _forward_cell_dir(view: UnitView) -> Vector2i:
	var f: Vector3 = -view.transform.basis.z
	return Vector2i(roundi(f.x), roundi(f.z))


func _assert_faces(view: UnitView, facing: int, msg: String) -> void:
	assert_eq(_forward_cell_dir(view), Board.DIRS_8[facing], msg)


## Перебудова юнітів після кожної дії створює десяток вузлів: текстури й
## матеріали того самого власника мусять бути спільними екземплярами.
func test_views_of_same_owner_share_textures_and_materials() -> void:
	var other: UnitView = preload("res://game/battle/unit_view.tscn").instantiate()
	add_child_autofree(other)
	view.bind(_unit(5, 0))
	other.bind(_unit(5, 0))
	assert_same(view._crosshair.texture, other._crosshair.texture)
	assert_same(view._hp_bar.texture, other._hp_bar.texture)
	assert_same(view._hull_material, other._hull_material)
	assert_same(view.get_node("Silhouette/Barrel").material_override, other.get_node("Silhouette/Barrel").material_override)
	other.bind(_unit(5, 1))
	assert_not_same(view._hull_material, other._hull_material, "інший власник — інший колір")


func test_no_debug_facing_arrow_in_shipped_build() -> void:
	view.bind(_unit(5, 0))
	assert_null(view.get_node_or_null("Silhouette/DebugFacingArrow"))


## Task 4.3: силует-заступник на кожен із 12 типів (до асетів Фази 5.2).
func test_every_type_has_a_distinct_silhouette() -> void:
	var seen := {}
	for id in UnitTypes.count():
		var key := var_to_str(UnitSilhouettes.spec(id))
		assert_false(seen.has(key), "тип %d повторює силует типу %s" % [id, seen.get(key)])
		seen[key] = id


func _footprint(id: int) -> float:
	var h: Vector3 = UnitSilhouettes.spec(id).hull
	return h.x * h.z


## Мобільність light(7) → medium(5) → TD(6) → heavy(8) за AP спадає, тож і корпус росте.
func test_heavier_tank_has_larger_hull_footprint() -> void:
	assert_lt(_footprint(7), _footprint(5))
	assert_lt(_footprint(5), _footprint(6))
	assert_lt(_footprint(6), _footprint(8))


func test_silhouette_stays_within_four_meshes() -> void:
	for id in UnitTypes.count():
		var root := UnitSilhouettes.build(id, Color.RED)
		assert_between(root.get_child_count(), 1, 4, "тип %d" % id)
		root.free()


func test_silhouette_fits_one_tile() -> void:
	for id in UnitTypes.count():
		var root := UnitSilhouettes.build(id, Color.RED)
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		for m: Node3D in root.get_children():
			if m is MultiMeshInstance3D:
				# Фігури відділення: і стоячі, і лежачі мусять лишатись у тайлі.
				for i in UnitView.SQUAD_FIGURES:
					for up: bool in [true, false]:
						var fb: AABB = UnitSilhouettes.figure_transform(i, up) * AABB(-UnitSilhouettes.FIGURE_SIZE * 0.5, UnitSilhouettes.FIGURE_SIZE)
						lo = lo.min(fb.position)
						hi = hi.max(fb.end)
				continue
			var box: AABB = (m as MeshInstance3D).mesh.get_aabb()
			if m.name == "Barrel":
				# Ствол реальної довжини (5–6 м від центру башти) смій виступати за тайл.
				assert_gte(m.position.z + box.position.z, -0.75, "ствол типу %d" % id)
				continue
			lo = lo.min(m.position + box.position)
			hi = hi.max(m.position + box.end)
		assert_lte(hi.x - lo.x, 1.0, "x типу %d" % id)
		assert_lte(hi.z - lo.z, 1.0, "z типу %d" % id)
		assert_gte(lo.y, 0.0, "низ типу %d" % id)
		root.free()


## Task 10: заборонена ціль дрона (піхота) — окрема позначка, не приціл.
func test_set_forbidden_toggles_its_own_mark_and_bind_clears_it() -> void:
	view.bind(_unit(0))
	assert_false(view._forbidden.visible, "свіжий вузол не позначений")
	view.set_forbidden(true)
	assert_true(view._forbidden.visible)
	assert_false(view._crosshair.visible, "заборона — не приціл")
	view.set_forbidden(false)
	assert_false(view._forbidden.visible)
	view.set_forbidden(true)
	view.bind(_unit(0))
	assert_false(view._forbidden.visible, "bind() знімає позначку — режим дрона перебудову не переживає")


## Task 14: позначки огляду — гармата й дрон окремо, різні форма й колір, і юніт
## у обох списках показує обидві.
func test_gun_and_drone_threat_marks_are_independent_and_distinct() -> void:
	view.bind(_unit(5))
	view.set_threatened(true)
	view.set_drone_threatened(true)
	assert_true(view.is_threatened())
	assert_true(view.is_drone_threatened())
	view.set_threatened(false)
	assert_false(view.is_threatened())
	assert_true(view.is_drone_threatened(), "дронова позначка не залежить від гарматної")
	assert_ne(view._threatened.texture, view._drone_threatened.texture, "різна форма")
	assert_ne(view._threatened.modulate, view._drone_threatened.modulate, "різний колір")
	assert_ne(view._drone_threatened.texture, view._forbidden.texture, "не хрест заборони")
	assert_ne(view._threatened.transform.origin, view._drone_threatened.transform.origin, "не накладаються")


## Фаза 5a: юніти живуть на власному шарі рендеру — освітлення й відбиття
## можуть виключити їх маскою, не знаючи про жоден конкретний вузол.
func test_unit_meshes_are_on_the_unit_layer_only() -> void:
	view.bind(_unit(5))
	var expected: int = 1 << (UnitView.UNIT_LAYER - 1)
	var found: int = 0
	var stack: Array[Node] = [view]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is VisualInstance3D:
			found += 1
			assert_eq((n as VisualInstance3D).layers, expected, "%s мусить бути лише на шарі юнітів" % n.name)
	assert_gt(found, 4, "передумова: силует і позначки справді знайдено")


# --- Юніт на рельєфі ----------------------------------------------------

const _CM: float = TerrainHeight.M * 0.01
static var _river: TerrainHeight = null
static var _river_board: Board = null


func _relief() -> TerrainHeight:
	if _river == null:
		var m: MapData = load("res://maps/river.tres")
		_river_board = m.to_board()
		_river = TerrainHeight.bake(_river_board, 0, m.name_key.hash())
	return _river


## Кути основи корпусу у світі: низ Hull, ±половина його розміру.
func _base_corners(v: UnitView) -> Array[Vector3]:
	var sil: Node3D = v.get_node("Silhouette")
	var size: Vector3 = ((sil.get_node("Hull") as MeshInstance3D).mesh as BoxMesh).size
	var out: Array[Vector3] = []
	for sx: float in [-0.5, 0.5]:
		for sz: float in [-0.5, 0.5]:
			out.append(sil.global_transform * Vector3(size.x * sx, 0.0, size.z * sz))
	return out


## Перепад висот під кутами тайла: скільки схилу під юнітом.
func _spread(t: TerrainHeight, c: Vector2i) -> float:
	var lo := INF
	var hi := -INF
	for d: Vector2 in [Vector2(-0.4, -0.4), Vector2(0.4, -0.4), Vector2(-0.4, 0.4), Vector2(0.4, 0.4)]:
		var h: float = t.at(c.x + d.x, c.y + d.y)
		lo = minf(lo, h)
		hi = maxf(hi, h)
	return hi - lo


func _land_cells(t: TerrainHeight) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in _river_board.height:
		for x in _river_board.width:
			var k: int = _river_board.kind_at(Vector2i(x, y))
			if k != Terrain.Kind.WATER and k != Terrain.Kind.BRIDGE and k != Terrain.Kind.BRIDGE_DESTROYED:
				out.append(Vector2i(x, y))
	return out


## Наскільки земля під основою юніта відходить від площини: скрут (діагоналі на різній
## висоті) і горб чи западина під центром. Жорстка основа на такій землі неминуче висить
## частиною країв — 10 см там недосяжні за будь-якого нахилу.
func _off_plane(t: TerrainHeight, v: UnitView) -> float:
	var g: Array[float] = []
	for p in _base_corners(v):
		g.append(t.at(p.x, p.z))
	var mean: float = (g[0] + g[1] + g[2] + g[3]) / 4.0
	var twist: float = absf(g[0] + g[3] - g[1] - g[2]) / 4.0
	return maxf(twist, absf(t.at(v.position.x, v.position.z) - mean))


## Схил не крутіший за межу нахилу, від рівнини до помірного. Де земля під основою рівна,
## основа лежить на ній усіма кутами: не глибше 2 см у ґрунті й не вище 10 см над ним. На
## скруті чи горбі жорстка основа неминуче висить частиною країв — там межа ширша на
## подвійний відступ землі від площини, але кути однаково не входять у ґрунт. Діагональний
## facing, щоб кути справді крутились разом із юнітом.
func test_vehicle_base_lies_on_the_ground_up_to_the_tilt_limit() -> void:
	var t := _relief()
	TerrainHeight.active = t
	var planar := 0
	for c in _land_cells(t):
		if _spread(t, c) > tan(deg_to_rad(UnitView.MAX_TILT_DEG)) * 0.6:
			continue
		view.bind(_unit(5, 0, c, 1))
		var off: float = _off_plane(t, view)
		var bound: float = 10.0 * _CM if off <= 4.0 * _CM else 10.0 * _CM + 2.0 * off
		if off <= 4.0 * _CM:
			planar += 1
		for p in _base_corners(view):
			var g: float = t.at(p.x, p.z)
			assert_gte(p.y - g, -2.0 * _CM, "кут у ґрунті на %s: %.1f см" % [c, (p.y - g) / _CM])
			assert_lte(p.y - g, bound, "кут висить на %s: %.1f см (межа %.1f)" % [c, (p.y - g) / _CM, bound / _CM])
	gut.p("рівних клітинок під основою перевірено: %d" % planar)
	assert_gte(planar, 15, "передумова: на Річці досить рівних клітинок")


## Відділення стоїть на одній основі з кількома фігурами: нахил перекидав би їх разом із
## підставкою. Тому воно лишається рівним (лише поворот) і трохи втоплене в ґрунт, щоб
## край основи на схилі не висів.
func test_infantry_squad_stays_level_and_sunk_on_a_slope() -> void:
	var t := _relief()
	TerrainHeight.active = t
	var steepest := Vector2i.ZERO
	for c in _land_cells(t):
		if _spread(t, c) > _spread(t, steepest):
			steepest = c
	for id in UnitTypes.count():
		if UnitTypes.is_vehicle(UnitTypes.get_type(id)["unit_class"]):
			continue
		view.bind(_unit(id, 0, steepest, 1))
		var sil: Node3D = view.get_node("Silhouette")
		assert_eq(sil.rotation, Vector3.ZERO, "тип %d рівний" % id)
		assert_almost_eq(view.position.y, t.at(steepest.x, steepest.y) - UnitView.SQUAD_SINK, 0.0001, "тип %d втоплений" % id)
		assert_almost_eq(view.rotation_degrees.y, -45.0, 0.0001, "поворот лишається")


## Найкрутіший берег: нахил обмежено, і жоден кут однаково не входить у ґрунт.
func test_tilt_is_clamped_and_nothing_sinks_on_the_steepest_bank() -> void:
	var t := _relief()
	TerrainHeight.active = t
	var steepest := Vector2i.ZERO
	for c in _land_cells(t):
		if _spread(t, c) > _spread(t, steepest):
			steepest = c
	assert_gt(_spread(t, steepest), tan(deg_to_rad(UnitView.MAX_TILT_DEG)) * 0.8, "передумова: схил крутіший за межу")
	view.bind(_unit(8, 0, steepest, 3))
	var sil: Node3D = view.get_node("Silhouette")
	var up: Vector3 = sil.global_basis.y.normalized()
	assert_gt(up.angle_to(Vector3.UP), deg_to_rad(1.0), "на схилі юніт нахилений")
	assert_lte(absf(sil.rotation.x), deg_to_rad(UnitView.MAX_TILT_DEG) + 0.0001, "тангаж у межі")
	assert_lte(absf(sil.rotation.z), deg_to_rad(UnitView.MAX_TILT_DEG) + 0.0001, "крен у межі")
	for p in _base_corners(view):
		assert_gte(p.y - t.at(p.x, p.z), -2.0 * _CM, "кут у ґрунті: %.1f см" % ((p.y - t.at(p.x, p.z)) / _CM))


## §3.4: нахил не повертає юніт. Напрям, кут корпусу навколо осі й те, куди дивиться
## ніс у плані, — ті самі, що й на рівній землі.
func test_tilt_does_not_change_facing() -> void:
	var t := _relief()
	TerrainHeight.active = t
	var steepest := Vector2i.ZERO
	for c in _land_cells(t):
		if _spread(t, c) > _spread(t, steepest):
			steepest = c
	for f in 8:
		view.bind(_unit(5, 0, steepest, f))
		var sil: Node3D = view.get_node("Silhouette")
		var nose: Vector3 = -sil.global_basis.z
		var flat_nose: Vector3 = -view.global_basis.z
		assert_eq(view.facing, f)
		assert_almost_eq(view.rotation_degrees.y, -45.0 * f, 0.0001, "кут вузла — лише напрям")
		assert_almost_eq(Vector2(nose.x, nose.z).normalized().dot(Vector2(flat_nose.x, flat_nose.z)), 1.0, 0.0001,
				"ніс у плані дивиться туди ж, facing %d" % f)


func test_flat_ground_keeps_the_unit_level() -> void:
	view.bind(_unit(8, 0, Vector2i(4, 4), 1))
	var sil: Node3D = view.get_node("Silhouette")
	assert_eq(sil.rotation, Vector3.ZERO)
	assert_eq(view.position, Vector3(4, 0, 4))


## Кожен кадр ходу юніт лежить на схилі, а не лише на кінцевій клітинці.
func test_unit_keeps_the_pose_while_moving() -> void:
	var t := _relief()
	TerrainHeight.active = t
	var steepest := Vector2i.ZERO
	for c in _land_cells(t):
		if _spread(t, c) > _spread(t, steepest):
			steepest = c
	var start := steepest + Vector2i(-1, 0)
	view.bind(_unit(5, 0, start, 2))
	var path: Array[Vector2i] = [steepest]
	var tween: Tween = view.move_along(path, 1.0).get_object()
	var sil: Node3D = view.get_node("Silhouette")
	var tilted := 0
	for i in 10:
		tween.custom_step(0.1)
		for p in _base_corners(view):
			assert_gte(p.y - t.at(p.x, p.z), -2.0 * _CM, "кут у ґрунті на кроці %d" % i)
		if sil.rotation.length() > deg_to_rad(1.0):
			tilted += 1
	assert_gt(tilted, 0, "дорогою юніт нахиляється за схилом")


## Поворот на місці: твін крутить вузол, нахил іде слідом кожен кадр.
func test_turn_in_place_keeps_the_base_on_the_slope() -> void:
	var t := _relief()
	TerrainHeight.active = t
	var steepest := Vector2i.ZERO
	for c in _land_cells(t):
		if _spread(t, c) > _spread(t, steepest):
			steepest = c
	view.bind(_unit(8, 0, steepest, 0))
	view.face(2)
	for i in 5:
		view._face_tween.custom_step(0.04)
		view._process(0.04)
		for p in _base_corners(view):
			assert_gte(p.y - t.at(p.x, p.z), -2.0 * _CM, "кут у ґрунті посеред повороту, крок %d" % i)


## Міст: юніт стоїть рівно на настилі, а не на руслі під ним.
func test_unit_on_a_bridge_stands_level_on_the_deck() -> void:
	var t := _relief()
	TerrainHeight.active = t
	var bridge := Vector2i(-1, -1)
	for y in _river_board.height:
		for x in _river_board.width:
			if _river_board.kind_at(Vector2i(x, y)) == Terrain.Kind.BRIDGE:
				bridge = Vector2i(x, y)
	assert_ne(bridge, Vector2i(-1, -1), "передумова: на Річці є міст")
	view.bind(_unit(5, 0, bridge, 1))
	assert_almost_eq(view.position.y, t.deck_y(bridge), 0.0001)
	assert_eq(view.get_node("Silhouette").rotation, Vector3.ZERO)


## Кадр юніта працює лише поки живий твін повороту чи ходу: у спокої десятки юнітів не
## роблять нічого щокадру (§8).
func test_unit_processes_only_while_turning() -> void:
	view.bind(_unit(5, 0, Vector2i(2, 2), 0))
	assert_false(view.is_processing(), "після bind кадр вимкнено")
	view.face(2)
	assert_true(view.is_processing(), "поворот вмикає кадр")
	view._face_tween.custom_step(10.0)
	view._process(0.0)
	assert_false(view.is_processing(), "твін скінчився — кадр вимкнено")
	var path: Array[Vector2i] = [Vector2i(3, 2)]
	var tween: Tween = view.move_along(path, 0.1).get_object()
	assert_true(view.is_processing(), "хід вмикає кадр")
	tween.custom_step(10.0)
	view._process(0.0)
	assert_false(view.is_processing())



## HP-бар і підпис — поверх усіх ефектів, завжди однаково: полум'я уламків не сміє
## перекривати один підпис і лишати інший зверху.
func test_hp_bar_and_label_draw_over_every_effect() -> void:
	view.bind(_unit(5))
	for n: GeometryInstance3D in [view._hp_bar, view._hp_label]:
		assert_true(n.get("no_depth_test"), n.name)
		assert_eq(n.get("render_priority"), UnitView.OVERLAY_PRIORITY, n.name)
	assert_true(UnitView.OVERLAY_PRIORITY > 1, "вище за вогонь (1)")
