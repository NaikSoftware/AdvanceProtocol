extends GutTest
## Task 2.4, рішення R11: живий бій з'являється лише в Task 2.10, тож усе тут —
## headless перевірка вузла самого по собі: силует за класом, поворот,
## HP-бар, лічильник дронів, приглушення і твіни. Останній тест — контракт
## тумана: UnitView не читає Vision і не приховує ворога сам (§3.5) —
## існування вузла для чужого юніта вирішує контейнер (Task 2.10).

const UnitModelFixture := preload("res://tests/fixtures/unit_model_fixture.gd")

const UnitViewScene := preload("res://game/battle/unit_view.tscn")

var view: Node3D


func before_each() -> void:
	UnitView._travel_by_unit.clear()
	# Коробки, хай що лежить в assets/units: тести моделей підставляють свою сітку самі.
	UnitSilhouettes.use_models({})
	view = UnitViewScene.instantiate()
	add_child_autofree(view)


func after_each() -> void:
	UnitView._travel_by_unit.clear()
	# Статичне поле на весь процес: тест, що впав посередині, не сміє лишити рельєф решті набору.
	TerrainHeight.active = null
	WeatherRig.unit_contact = 0.0
	WeatherRig.sun_ground = Vector2.ZERO
	UnitSilhouettes.reset_models()


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
		assert_eq(hull.mesh.get_surface_count(), 1, "тіло — одна сітка")
		seen_sizes[UnitSilhouettes.spec(type_id).hull] = true
	assert_eq(seen_sizes.size(), type_ids.size(), "кожен клас мусить мати власний, ні на який інший не схожий силует")


## Тінь-контакт: плаский квад під корпусом, ширший за його слід; сам тіні від сонця не кидає. Усі
## плями одного екрана — один MultiMesh (`UnitContacts`), а не вузол і виклик малювання на юніт.
func _with_contacts() -> UnitContacts:
	var contacts := UnitContacts.new()
	add_child_autofree(contacts)
	view.contacts = contacts
	return contacts


func test_unit_has_a_flat_contact_shadow_under_its_hull() -> void:
	WeatherRig.unit_contact = 0.6
	var contacts := _with_contacts()
	for type_id: int in [5, 11]:
		view.bind(_unit(type_id))
		assert_eq(contacts.count(), 1, "одна пляма на юніта, не більше")
		assert_eq(view.contact_slots(), 1)
		assert_eq(contacts.custom_of(0).g, 1.0, "у даних екземпляра техніки — повна сила карти")
		var hull: Vector3 = UnitSilhouettes.spec(type_id).hull
		var xf: Transform3D = contacts.transform_of(0)
		assert_almost_eq(xf.basis.x.length(), hull.x * UnitView.CONTACT_SPREAD, 0.0001, "ширша за слід по x")
		assert_almost_eq(xf.basis.z.length(), hull.z * UnitView.CONTACT_SPREAD, 0.0001, "і по z")
		assert_almost_eq(xf.origin.y - view.position.y, 0.01, 0.0001, "на ґрунті, під корпусом")
		assert_almost_eq(xf.origin.x, view.position.x, 0.0001)
		assert_almost_eq(xf.origin.z, view.position.z, 0.0001)
		assert_eq(contacts.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)


## Під відділенням — не одна пляма на весь слід (вона читалась чорною), а мала слабка тінь під
## ногами кожного стоячого бійця, усі в тому самому `MultiMesh`; загиблий тіні не має.
func test_squad_contact_is_a_small_weak_shadow_under_each_standing_figure() -> void:
	WeatherRig.unit_contact = 0.6
	WeatherRig.sun_ground = Vector2.ZERO
	var contacts := _with_contacts()
	view.bind(_unit(0))
	assert_eq(contacts.count(), 1, "один юніт")
	assert_eq(view.contact_slots(), UnitView.SQUAD_FIGURES)
	for i in UnitView.SQUAD_FIGURES:
		assert_almost_eq(contacts.custom_of(i).g, view.contact_strength(), 0.0001, "сила бійця в даних екземпляра")
	assert_almost_eq(view.contact_strength() * WeatherRig.unit_contact, UnitView.FIGURE_CONTACT_ALPHA, 0.0001, "стала непрозорість бійця")
	WeatherRig.unit_contact = 0.78
	assert_almost_eq(view.contact_strength() * 0.78, UnitView.FIGURE_CONTACT_ALPHA, 0.0001, "і на карті з густішою тінню техніки")
	WeatherRig.sun_ground = Vector2(0.6, 0.8)
	assert_almost_eq(view.contact_strength() * 0.78, UnitView.FIGURE_CONTACT_ALPHA * UnitView.FIGURE_CONTACT_SUNNY, 0.0001,
			"під сонцем — слабша: є ще справжня тінь")
	WeatherRig.sun_ground = Vector2.ZERO
	WeatherRig.unit_contact = 0.6
	for i in UnitView.SQUAD_FIGURES:
		var xf: Transform3D = contacts.transform_of(i)
		assert_true(contacts.is_shown(i))
		assert_almost_eq(xf.basis.x.length(), UnitView.FIGURE_CONTACT_SIZE, 0.0001, "~0,9 м квад, не 5 м")
		var feet: Vector3 = view.global_transform * UnitSilhouettes.figure_transform(i, true, view.layout()).origin
		assert_almost_eq(Vector2(xf.origin.x, xf.origin.z), Vector2(feet.x, feet.z), Vector2.ONE * 0.0001, "під ногами бійця %d" % i)
	view.set_hp(30, 100)
	contacts.sync()
	assert_true(contacts.is_shown(0))
	assert_true(contacts.is_shown(1))
	assert_false(contacts.is_shown(2), "загиблий тіні не має")
	assert_false(contacts.is_shown(3))
	view.bind(_unit(5))
	assert_eq(view.contact_slots(), 1, "перев'язаний на техніку — знову одна пляма")
	assert_eq(contacts.custom_of(0).g, 1.0)
	assert_almost_eq(contacts.transform_of(0).basis.x.length(), UnitSilhouettes.spec(5).hull.x * UnitView.CONTACT_SPREAD, 0.0001)


func test_contact_shadow_shifts_along_the_sun_ground_direction() -> void:
	WeatherRig.unit_contact = 0.6
	WeatherRig.sun_ground = Vector2(1.0, 0.0)
	var contacts := _with_contacts()
	view.bind(_unit(5))
	var hull: Vector3 = UnitSilhouettes.spec(5).hull
	var xf: Transform3D = contacts.transform_of(0)
	assert_almost_eq(xf.origin.x - view.position.x, UnitView.CONTACT_SUN_SHIFT * maxf(hull.x, hull.z), 0.0001)
	assert_almost_eq(xf.origin.z, view.position.z, 0.0001)


## Зсув іде у світових осях: поворот юніта його не крутить.
func test_contact_shadow_shift_is_world_space_for_a_turned_unit() -> void:
	WeatherRig.unit_contact = 0.6
	WeatherRig.sun_ground = Vector2(0.6, 0.8)
	var contacts := _with_contacts()
	view.bind(_unit(5, 0, Vector2i(2, 3), 2))
	var hull: Vector3 = UnitSilhouettes.spec(5).hull
	var xf: Transform3D = contacts.transform_of(0)
	var k: float = UnitView.CONTACT_SUN_SHIFT * maxf(hull.x, hull.z)
	assert_almost_eq(xf.origin.x - view.position.x, 0.6 * k, 0.0001)
	assert_almost_eq(xf.origin.z - view.position.z, 0.8 * k, 0.0001)


func test_contact_road_factor_follows_the_tile_under_the_unit() -> void:
	WeatherRig.unit_contact = 0.6
	var map := MapData.new()
	map.width = 4
	map.height = 4
	map.tiles = PackedInt32Array()
	map.tiles.resize(16)
	map.tiles.fill(Terrain.Kind.FIELD)
	map.tiles[3 * 4 + 2] = Terrain.Kind.ROAD
	map.tiles[1 * 4 + 1] = Terrain.Kind.BRIDGE
	var contacts := _with_contacts()
	contacts.map = map
	view.bind(_unit(5, 0, Vector2i(2, 3)))
	assert_eq(contacts.road_of(0), 1.0, "дорога")
	view.bind(_unit(5, 0, Vector2i(1, 1)))
	assert_eq(contacts.road_of(0), 1.0, "міст")
	view.bind(_unit(5, 0, Vector2i(0, 0)))
	assert_eq(contacts.road_of(0), 0.0, "поле")


## Пляма реєструється вже після повороту: перша синхронізація бачить facing юніта.
func test_contact_shadow_starts_in_the_units_facing() -> void:
	WeatherRig.unit_contact = 0.6
	var contacts := _with_contacts()
	view.bind(_unit(5, 0, Vector2i(2, 2), 2))
	assert_eq(contacts.transform_of(0), view.contact_transform())
	assert_almost_eq(contacts.transform_of(0).basis.x.normalized().dot(view.global_transform.basis.x.normalized()), 1.0, 0.0001, "пляма повернута разом з юнітом")


## Без тіні-контакту у вигляді карти пляму не будують зовсім: прозорий квад під кожним юнітом —
## зайвий виклик малювання.
func test_no_contact_shadow_when_the_look_has_none() -> void:
	WeatherRig.unit_contact = 0.0
	var contacts := _with_contacts()
	for type_id: int in [0, 5]:
		view.bind(_unit(type_id))
		assert_eq(contacts.count(), 0)


## Загиблі фігури лежать на ґрунті, тож пляма під відділенням зникає разом зі стоячими.
func test_squad_contact_shadow_goes_with_the_squad() -> void:
	WeatherRig.unit_contact = 0.6
	var contacts := _with_contacts()
	view.bind(_unit(0))
	assert_true(contacts.is_shown(0))
	view.play_destroyed()
	contacts.sync()
	assert_false(contacts.is_shown(0))


## Пляма їде за юнітом: позицію вузла твін міняє щокадру, а пляма — спільна, тож її сітка
## синхронізується окремо (UnitContacts._process).
func test_contact_shadow_follows_the_unit_and_dies_with_its_node() -> void:
	WeatherRig.unit_contact = 0.6
	var contacts := _with_contacts()
	view.bind(_unit(5, 0, Vector2i(2, 2)))
	var path: Array[Vector2i] = [Vector2i(3, 2)]
	(view.move_along(path, 0.05).get_object() as Tween).custom_step(10.0)
	contacts.sync()
	assert_almost_eq(contacts.transform_of(0).origin.x, view.position.x, 0.0001)
	var other: UnitView = UnitViewScene.instantiate()
	add_child_autofree(other)
	other.contacts = contacts
	other.bind(_unit(5, 1, Vector2i(6, 6)))
	assert_eq(contacts.count(), 2)
	other.free()
	assert_eq(contacts.count(), 1, "звільнений юніт плями не лишає")


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
	assert_eq(image.get_pixel(1, image.get_height() / 2), _as_rgba8(UnitView.hp_fill_color(0)),
		"всередині, від лівого краю — заливка кольору власника")


## Смуга витрачається ЗЛІВА НАПРАВО (як у референсі), а не стискається до
## центру — саме те, що робив старий scale.x.
func test_hp_bar_fill_runs_from_the_left_edge_and_shrinks_rightwards() -> void:
	view.bind(_unit(5))
	var mid_y: int = _hp_bar_image(view).get_height() / 2
	var width: int = _hp_bar_image(view).get_width()

	view.set_hp(400, 400)
	assert_eq(_hp_bar_image(view).get_pixel(width - 2, mid_y), _as_rgba8(UnitView.hp_fill_color(0)),
		"повне HP — заливка доходить до внутрішнього правого краю")

	view.set_hp(200, 400)
	assert_eq(_hp_bar_image(view).get_pixel(1, mid_y), _as_rgba8(UnitView.hp_fill_color(0)),
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
	view.bind(_unit(1))
	assert_true(view._hp_bar.position.y < view._hp_label.position.y, "підпис сидить над смугою")
	assert_false(view._drone_icon.fixed_size, "значок росте й меншає разом зі смугою")
	assert_true(view._drone_icon.no_depth_test, "значок поверх розчиненої крони, як смуга")
	assert_eq(view._drone_icon.position.y, view._hp_label.position.y, "значок — над числом HP")
	assert_eq(view._hp_label.horizontal_alignment, HORIZONTAL_ALIGNMENT_CENTER, "число HP — посередині, як без дронів")
	assert_eq(view._hp_label.offset, Vector2.ZERO)
	var r: Rect2 = _icon_rect(Vector2.ZERO)
	assert_almost_eq(r.get_center().x, 0.0, 0.001, "посередині, над числом")
	assert_gt(r.position.y, 0.1, "вище за число HP")
	# цятка 10 текселів, проміжок 7; на найдальшому зумі ~45 пк на одиницю світу
	var px_per_texel: float = UnitView.DRONE_ICON_PIXEL * 45.0
	assert_gte(10.0 * px_per_texel, 3.0, "цятка щонайменше 3 × 3 пікселі")
	assert_gte(7.0 * px_per_texel, 2.0, "між цятками щонайменше 2 пікселі")


## Прямокутник значка дронів у площині екрана (одиниці світу) відносно точки його рядка.
func _icon_rect(anchor: Vector2) -> Rect2:
	var px: float = UnitView.DRONE_ICON_PIXEL
	var tex: Vector2 = Vector2(UnitView.drone_texture(2).get_size())
	var centre: Vector2 = anchor + UnitView.DRONE_ICON_OFFSET * px
	return Rect2(centre - tex * px * 0.5, tex * px)


## Фігура, що впала, перекидається навзнак за FALL_TIP_SEC і зникає — далі тіло лежить у шарі тіл.
func test_fallen_figures_tip_over_then_go() -> void:
	UnitSilhouettes.use_models({0: UnitModelFixture.soldier(), 1: UnitModelFixture.tube_soldier()})
	view.bind(_unit(0))
	var before: int = view._silhouette.get_node("Hull").get_child_count()
	view.set_hp(40, 100)
	var tipping: Array = view._silhouette.get_node("Hull").get_children().slice(before)
	assert_eq(tipping.size(), 2, "з чотирьох стоячих лишилось два — два перекидаються")
	# твін — вручну, без реального часу: посеред перекидання кут — чверть кінцевого (EASE_IN, квадрат)
	for t: Tween in get_tree().get_processed_tweens():
		t.custom_step(UnitView.FALL_TIP_SEC * 0.5)
	assert_almost_eq((tipping[0] as Node3D).rotation.x, UnitView.FALL_TIP_ANGLE * 0.25, 0.05, "посеред перекидання")
	for t: Tween in get_tree().get_processed_tweens():
		t.custom_step(UnitView.FALL_TIP_SEC)
	await get_tree().process_frame
	assert_eq(view._silhouette.get_node("Hull").get_child_count(), before, "перекинувшись, зникає")


## Місця бійців стоять у світі, тож на будь-якому з 8 напрямів жодні двоє не стають один за одним уздовж
## погляду: поперек екрана між будь-якими двома щонайменше MIN_SCREEN_GAP (0,6 м); повертаються лише фігури.
func test_figures_never_line_up_along_the_view_at_any_facing() -> void:
	UnitSilhouettes.use_models({0: UnitModelFixture.soldier(), 1: UnitModelFixture.tube_soldier()})
	var cam: float = deg_to_rad(IsoCameraRig.YAW_DEGREES)
	var across := Vector3(cos(cam), 0.0, -sin(cam))
	for unit_id in 6:
		var u: Unit = _unit(0)
		u.id = unit_id
		view.bind(u)
		for f in 8:
			view.rotation.y = deg_to_rad(UnitView._degrees_for_facing(f))
			view._set_standing(UnitView.SQUAD_FIGURES)
			var hull := view._silhouette.get_node("Hull") as Node3D
			var xs: Array[float] = []
			for i in UnitView.SQUAD_FIGURES:
				var at: Vector3 = (hull.global_transform * UnitSilhouettes.model_figure_transform(i, view.layout(), view.rotation.y)).origin
				xs.append(at.dot(across))
			xs.sort()
			for i in range(1, xs.size()):
				assert_gte(xs[i] - xs[i - 1], UnitSilhouettes.MIN_SCREEN_GAP - 0.0001,
						"відділення %d, напрям %d: двоє бійців один за одним уздовж погляду" % [unit_id, f])
	UnitSilhouettes.use_models({})


## Значок дронів — публічне число саме цього відділення (§3.9): у площині екрана він не налазить ні на свій
## підпис, ні на смугу, підпис чи бійців жодного з восьми сусідів, на обох нахилах камери. Розміри — з
## констант смуги й справжнього шрифту підпису.
func test_drone_icon_never_overlaps_a_neighbours_bar_or_label() -> void:
	view.bind(_unit(1))
	var label: Label3D = view._hp_label
	var font: Font = label.font if label.font != null else ThemeDB.fallback_font
	var text_w: float = font.get_string_size("100/100", HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size).x * label.pixel_size
	var pad: float = label.outline_size * label.pixel_size * 0.5  # обведення — по пів товщини з кожного боку
	var label_h: float = label.font_size * label.pixel_size + 2.0 * pad
	var bar_size := Vector2(UnitView.HP_BAR_HALF * 2.0, UnitView._HP_BAR_SIZE.y * UnitView.HP_BAR_PIXEL_SIZE)
	for pitch_deg: float in [IsoCameraRig.PITCH_NEAR_DEG, IsoCameraRig.PITCH_FAR_DEG]:
		var yaw := Basis(Vector3.UP, deg_to_rad(IsoCameraRig.YAW_DEGREES))
		var cam_basis: Basis = yaw * Basis(Vector3.RIGHT, -deg_to_rad(pitch_deg))
		var right: Vector3 = cam_basis.x
		var up: Vector3 = cam_basis.y
		var bar_y: float = view._hp_bar.position.y * up.y
		var row_y: float = label.position.y * up.y
		var own: Rect2 = _icon_rect(Vector2(0.0, row_y))
		var label_rect := func(at: Vector2) -> Rect2:
			return Rect2(at + Vector2(-text_w * 0.5 - pad, row_y - label_h * 0.5), Vector2(text_w + 2.0 * pad, label_h))
		assert_false(own.intersects(label_rect.call(Vector2.ZERO)), "свій підпис HP значок не накриває")
		assert_false(own.intersects(Rect2(Vector2(-bar_size.x * 0.5, bar_y - bar_size.y * 0.5), bar_size)), "свою смугу значок не накриває")
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dz == 0:
					continue
				var w := Vector3(dx, 0.0, dz)
				var at := Vector2(w.dot(right), w.dot(up))
				var bar := Rect2(at + Vector2(-bar_size.x * 0.5, bar_y - bar_size.y * 0.5), bar_size)
				var figures := Rect2(at + Vector2(-0.2, 0.0), Vector2(0.4, 0.225 * up.y))
				var icon_n: Rect2 = _icon_rect(at + Vector2(0.0, row_y))
				var tag: String = "нахил %d°, сусід (%d, %d)" % [pitch_deg, dx, dz]
				assert_false(own.intersects(bar), tag + ": значок на його смузі")
				assert_false(own.intersects(label_rect.call(at)), tag + ": значок на його підписі")
				assert_false(own.intersects(figures), tag + ": значок на його бійцях")
				assert_false(own.intersects(icon_n), tag + ": значок на його значку")


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
	assert_same(view_a._drone_icon.texture, view_b._drone_icon.texture, "лічильник не має гілки на власника")
	assert_false(view_a._drone_icon.fixed_size, "росте й меншає разом зі смугою HP")
	# Число — цятками під силуетом: у 2 дронів жовтого більше, ніж в 1, а розмір значка той самий.
	var lit := func(t: Texture2D) -> int:
		var img: Image = t.get_image()
		var n: int = 0
		for y in img.get_height():
			for x in range(31, img.get_width()):
				if img.get_pixel(x, y).r > 0.6:
					n += 1
		return n
	assert_gt(lit.call(UnitView.drone_texture(2)), lit.call(UnitView.drone_texture(1)) + 10, "дві цятки — не одна")
	assert_gt(lit.call(UnitView.drone_texture(1)), 10, "одна цятка")
	assert_eq(UnitView.drone_texture(1).get_size(), UnitView.drone_texture(2).get_size())
	view_a.set_drones(1)
	assert_same(view_a._drone_icon.texture, UnitView.drone_texture(1))

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


## Приціл несе колір влучання: гравець читає його як «сюди прилетить».
func test_crosshair_uses_the_hit_colour() -> void:
	view.bind(_unit(5))
	assert_eq(view._crosshair.modulate, Color("ff7a4a"), "приціл мусить нести колір влучання")


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


## Кольори вершин сітки тіла: колір власника живе в них, а не в спільному матеріалі.
func _hull_colors() -> PackedColorArray:
	return (view.get_node("Silhouette/Hull") as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]


## Корпус фарбує ВЛАСНИК і більше ніщо. Раніше bind() ще й приглушував
## корпус юніта, який уже стріляв, — власник цього не замовляв і прибрав
## («прибери приглушення взагалі»). Тест тримає саме це: жоден стан юніта,
## крім власника, не має права чіпати колір корпусу.
func test_hull_colour_comes_from_owner_and_nothing_else() -> void:
	var fresh := _unit(5)
	view.bind(fresh)
	var base_colors: PackedColorArray = _hull_colors()

	var fired := _unit(5)
	fired.exhaust()
	fired.hp = fired.max_hp() / 2
	view.bind(fired)
	assert_false(base_colors.is_empty(), "передумова: у сітці є кольори")
	assert_eq(_hull_colors(), base_colors, "постріл і поранення не мусять міняти колір корпусу")


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


## Поворот маршруту — дуга радіуса TURN_RADIUS, як заокруглення дороги, а не зупинка й
## доворот на місці: юніт не проходить через центр кутової клітинки, посередині дуги
## дивиться навскіс, а час кроку — довжина дуги, без паузи на поворот.
func test_move_along_rounds_a_route_turn_with_an_arc() -> void:
	view.bind(_unit(5, 0, Vector2i(0, 0), 2))  # дивиться на схід — старт без довороту
	var path: Array[Vector2i] = [Vector2i(1, 0), Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 2)]
	var tween: Tween = view.move_along(path, 0.1).get_object()

	tween.custom_step(0.1)
	assert_almost_eq(view.position, IsoCameraRig.cell_to_world(Vector2i(1, 0)), Vector3.ONE * 1e-4, "пряма ділянка до початку дуги")

	tween.custom_step(0.1 * PI / 4.0)  # пів дуги радіуса 1
	var corner: Vector3 = IsoCameraRig.cell_to_world(Vector2i(2, 0))
	assert_almost_eq(view.position.distance_to(corner), sqrt(2.0) - 1.0, 5e-3, "середина дуги — на радіусі від її центру, а не в центрі кута")
	_assert_faces(view, 3, "посередині повороту ніс дивиться навскіс")

	tween.custom_step(0.1 * PI / 4.0)
	assert_almost_eq(view.position, IsoCameraRig.cell_to_world(Vector2i(2, 1)), Vector3.ONE * 5e-3, "дуга виходить у центр наступної клітинки")
	_assert_faces(view, 4, "після дуги юніт їде на південь")

	tween.custom_step(0.1)
	assert_eq(view.position, IsoCameraRig.cell_to_world(Vector2i(2, 2)), "кінець шляху — точно в центрі останньої клітинки")
	assert_false(tween.is_running(), "поворот не додав часу понад довжину кривої")


## Дуга, що починається в стартовій клітинці й кінчається в останній: юніт, який уже
## дивиться вздовж першого кроку, рушає одразу, а в кінці стоїть точно за своїм facing.
func test_move_along_l_turn_starts_without_a_pause_and_ends_on_facing() -> void:
	view.bind(_unit(5, 0, Vector2i(0, 0), 2))
	var path: Array[Vector2i] = [Vector2i(1, 0), Vector2i(1, 1)]
	var tween: Tween = view.move_along(path, 0.1).get_object()
	tween.custom_step(0.01)
	assert_ne(view.position, IsoCameraRig.cell_to_world(Vector2i(0, 0)), "жодного довороту на місці перед стартом")
	tween.custom_step(10.0)
	assert_eq(view.facing, 4)
	assert_almost_eq(fposmod(view.rotation_degrees.y, 360.0), fposmod(UnitView._degrees_for_facing(4), 360.0), 0.1, "ніс точно на південь, а не на хорду дуги")


## Сходинку з одиничних кроків юніт проходить навскіс: посередині ніс тримає діагональ, а
## не хитається ±45° щопівтайла, як змійка з малих дуг.
func test_move_along_takes_a_staircase_as_one_diagonal() -> void:
	view.bind(_unit(5, 0, Vector2i(0, 0), 2))
	var path: Array[Vector2i] = [Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1), Vector2i(2, 2), Vector2i(3, 2), Vector2i(3, 3), Vector2i(4, 3)]
	var tween: Tween = view.move_along(path, 0.1).get_object()
	var checked: int = 0
	while tween.is_running():
		tween.custom_step(0.005)
		var c: Vector2i = IsoCameraRig.world_to_cell(view.position)
		if c == Vector2i(2, 1) or c == Vector2i(2, 2):
			checked += 1
			assert_almost_eq(fposmod(view.rotation_degrees.y, 360.0), fposmod(UnitView._degrees_for_facing(3), 360.0), 1.0, "посередині сходинки ніс — на південний схід")
			assert_almost_eq(view.position.z - view.position.x, -0.5, 1e-3, "центр іде однією прямою через середини ребер")
	assert_gt(checked, 0)


## Крива руху не зачіпає клітинок поза маршрутом — ні на одиночному повороті, ні на
## сходинці, ні на зсуві на одну смугу, ні на повороті одразу після сходинки; ніс ніколи
## не скаче, а on_step(i) приходить, коли юніт саме в клітинці path[i], і по порядку.
func test_move_along_curve_stays_on_route_cells() -> void:
	var routes: Array = [
		[Vector2i(1, 0), Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 2)],
		[Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1), Vector2i(2, 2), Vector2i(3, 2)],
		[Vector2i(1, 0), Vector2i(2, 0), Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1)],
		[Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1), Vector2i(3, 2), Vector2i(3, 3)],
	]
	for route: Array in routes:
		var path: Array[Vector2i] = []
		path.assign(route)
		view.bind(_unit(5, 0, Vector2i(0, 0), 2))
		var allowed: Array[Vector2i] = [Vector2i(0, 0)]
		allowed.append_array(path)
		var reached: Array[Vector2i] = []
		var record := func(_i: int) -> void: reached.append(IsoCameraRig.world_to_cell(view.position))
		var tween: Tween = view.move_along(path, 0.1, -1, record).get_object()
		var yaw: float = view.rotation_degrees.y
		while tween.is_running():
			tween.custom_step(0.005)
			assert_has(allowed, IsoCameraRig.world_to_cell(view.position), "%s: юніт у клітинці поза маршрутом" % [route])
			assert_lt(absf(view.rotation_degrees.y - yaw), 10.0, "%s: ніс повертає плавно" % [route])
			yaw = view.rotation_degrees.y
		assert_eq(view.position, IsoCameraRig.cell_to_world(path[path.size() - 1]))
		assert_eq(reached, path, "%s: on_step(i) — у клітинці path[i], по порядку" % [route])


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


## Лежачі фігури — вершини кольору загиблих у сітці тіла (кожна фігура — коробка в 24 вершини).
## Скільки коробок-фігур у сітці відділення, без плити-основи.
func _figures_in_mesh() -> int:
	var colors: PackedColorArray = (view.get_node("Silhouette/Hull") as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	return colors.size() / 24 - 1


## Відділення — плита й стоячі фігури в одній сітці; стоїть одна на кожну чверть HP, що
## лишилась (`ceil(4 · hp / max_hp)`). Загиблих відділення з собою не несе: вони лежать у шарі тіл.
func test_squad_shows_one_standing_figure_per_quarter_of_hp() -> void:
	view.bind(_unit(0))
	assert_eq(UnitView.SQUAD_FIGURES, 4)
	assert_eq(view.get_node("Silhouette").get_child_count(), 1, "тіло — одна сітка")
	var cases: Dictionary = {100: 4, 76: 4, 75: 3, 74: 3, 50: 2, 26: 2, 25: 1, 1: 1, 0: 0}
	for hp: int in cases:
		view.set_hp(hp, 100)
		assert_eq(view.standing_figures(), cases[hp], "hp %d" % hp)
		assert_eq(_figures_in_mesh(), cases[hp], "hp %d: у сітці лише стоячі" % hp)
		assert_eq(view.standing_figures(), Casualties.figures(hp, 100), "вигляд і core рахують однаково")


## Пущений дрон знімає трубу зі спини (§3.9: число публічне); значок залишку лишається.
func test_a_used_drone_takes_a_tube_off_the_squad() -> void:
	UnitSilhouettes.use_models({0: UnitModelFixture.soldier(), 1: UnitModelFixture.tube_soldier()})
	view.bind(_unit(1))
	var hull := view.get_node("Silhouette/Hull") as MeshInstance3D
	assert_same(hull.mesh, UnitSilhouettes.merged_mesh(1, 4, 0, 2, view.layout()), "дві труби з початку матчу")
	view.set_drones(1)
	assert_same(hull.mesh, UnitSilhouettes.merged_mesh(1, 4, 0, 1, view.layout()))
	assert_true(view.get_node("DroneIcon").visible)
	view.set_hp(30, 100)
	assert_same(hull.mesh, UnitSilhouettes.merged_mesh(1, 2, 0, 1, view.layout()), "трубу несе стоячий")
	view.set_drones(0)
	assert_same(hull.mesh, UnitSilhouettes.merged_mesh(1, 2, 0, 0, view.layout()))
	assert_false(view.get_node("DroneIcon").visible)


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
## під кулею), а його дим, розвіявшись за 3–6 с, звільняє себе сам.
func test_explosion_is_one_shot_and_frees_itself() -> void:
	view.bind(_unit(5))
	view.play_destroyed()
	var boom: Node = _explosions()[0]
	for t in Engine.get_main_loop().get_processed_tweens():
		if t.is_valid():
			t.custom_step(BattleFx.EXPLOSION_SEC + 0.01)
	assert_true(boom.is_queued_for_deletion())
	assert_true(BattleFx.EXPLOSION_SEC <= 6.0, "куля знищення разом із димом — до 6 с")


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
	assert_same(view.get_node("Silhouette/Hull").mesh, other.get_node("Silhouette/Hull").mesh, "той самий власник — та сама сітка")
	other.bind(_unit(5, 1))
	assert_same(view.get_node("Silhouette/Hull").mesh, other.get_node("Silhouette/Hull").mesh, "інший власник — те саме тіло")
	other.set_hp(400, 400)
	view.set_hp(400, 400)
	assert_not_same(view._hp_bar.texture, other._hp_bar.texture, "інший власник — інша смуга")


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
		var root := UnitSilhouettes.build(id)
		assert_between(root.get_child_count(), 1, 4, "тип %d" % id)
		root.free()


func test_silhouette_fits_one_tile() -> void:
	for id in UnitTypes.count():
		var root := UnitSilhouettes.build(id)
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
				# Ствол реальної довжини (5–7 м від центру тайла) смій виступати за тайл: найдовший —
				# у винищувача танків, бо зверху його впізнають саме за стволом.
				assert_gte(m.position.z + box.position.z, -0.875, "ствол типу %d" % id)
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
	var size: Vector3 = UnitSilhouettes.spec(v._type_id).hull
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
	# Відділення: ступні бійців на 0,05 над початком, тож початок — на `SQUAD_SINK` під настилом, як і на ґрунті.
	view.bind(_unit(0, 0, bridge, 1))
	assert_almost_eq(view.position.y, t.deck_y(bridge) - UnitView.SQUAD_SINK, 0.0001)


## Тіло на мосту лежить уздовж настилу на його висоті й не звисає над річкою: від осі мосту не далі за
## 0,18 тайла (найвужча проїжджа частина — 0,46).
func test_bodies_on_a_bridge_lie_along_the_deck_at_its_height() -> void:
	var t := _relief()
	TerrainHeight.active = t
	var bridge := Vector2i(-1, -1)
	for y in _river_board.height:
		for x in _river_board.width:
			if _river_board.kind_at(Vector2i(x, y)) == Terrain.Kind.BRIDGE:
				bridge = Vector2i(x, y)
	assert_ne(bridge, Vector2i(-1, -1), "передумова: на Річці є міст")
	var water_x: bool = WreckLayer._is_water(_river_board, bridge + Vector2i(1, 0)) or WreckLayer._is_water(_river_board, bridge + Vector2i(-1, 0))
	var along := Vector2(0.0, 1.0) if water_x else Vector2(1.0, 0.0)
	var widest: float = 0.0
	for facing in 8:
		for seq in 3:
			var b := Casualties.Body.new(7 + facing * 3 + seq, bridge, 0, 0, facing, 0, 4)
			b.seq = seq
			var strips: Array = []  # [середина вздовж настилу, смуга]
			for slot in 4:
				var xf: Transform3D = WreckLayer.body_transform(b, slot, _river_board)
				var mid: float = Vector2(xf.origin.x - bridge.x, xf.origin.z - bridge.y).dot(along)
				assert_almost_eq(xf.origin.y, t.deck_y(bridge), 0.0001, "на настилі, не під ним і не над ним")
				var rel := Vector2(xf.origin.x - bridge.x, xf.origin.z - bridge.y)
				var across: float = absf(rel.x * along.y - rel.y * along.x)
				var axis := Vector2(xf.basis.z.x, xf.basis.z.z).normalized()
				var off: float = absf(axis.x * along.y - axis.y * along.x)  # синус кута до осі мосту
				# поперек настилу: половина довжини тіла вздовж його осі й половина ширини впоперек — у межах поручнів
				var half_across: float = 0.5 * (WreckLayer.BODY_LENGTH * off + WreckLayer.BODY_WIDTH * sqrt(maxf(1.0 - off * off, 0.0)))
				assert_lte(across + half_across, 0.23, "тіло між поручнями (поперек %.3f)" % across)
				# поперек настилу під кутом: уздовж нього займає ширину й частку довжини
				var span: float = WreckLayer.BODY_WIDTH * off + WreckLayer.BODY_LENGTH * sqrt(maxf(1.0 - off * off, 0.0))
				strips.append([mid, span])
				assert_lte(absf(mid) + span * 0.5, 0.5, "у межах свого тайла мосту")
				widest = maxf(widest, acos(minf(off, 1.0)))
			strips.sort_custom(func(p: Array, q: Array) -> bool: return p[0] < q[0])
			for i in range(1, strips.size()):
				var gap: float = strips[i][0] - strips[i - 1][0] - (strips[i][1] + strips[i - 1][1]) * 0.5
				assert_gte(gap, 0.05 - 0.0001, "між тілами на настилі щонайменше 0,4 м")
	assert_gt(widest, deg_to_rad(15.0), "тіла лежать під різними кутами, не рівною шеренгою")


## Тіло лягає на ґрунт під собою — і на схилі; біля води воно в межах 0,3 тайла від середини клітинки, куди
## видима вода не заходить.
func test_bodies_sit_on_sloped_ground_and_stay_out_of_the_water() -> void:
	var t := _relief()
	TerrainHeight.active = t
	var shore := Vector2i(-1, -1)
	var dry := Vector2i(-1, -1)
	for y in range(1, _river_board.height - 1):
		for x in range(1, _river_board.width - 1):
			var p := Vector2i(x, y)
			if _river_board.kind_at(p) != Terrain.Kind.FIELD:
				continue
			var wet: bool = false
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				wet = wet or _river_board.kind_at(p + d) == Terrain.Kind.WATER
			if wet and shore.x < 0:
				shore = p
			if not wet and dry.x < 0 and absf(t.at(x - 0.3, y) - t.at(x + 0.3, y)) > 0.005:
				dry = p
	assert_ne(shore, Vector2i(-1, -1), "передумова: поле над водою")
	assert_ne(dry, Vector2i(-1, -1), "передумова: поле на схилі")
	for facing in 8:
		for slot in 4:
			var on_slope: Transform3D = WreckLayer.body_transform(Casualties.Body.new(3, dry, 0, 0, facing, 0, 4), slot, _river_board)
			assert_almost_eq(on_slope.origin.y, t.at(on_slope.origin.x, on_slope.origin.z), 0.0001, "на ґрунті під тілом")
			var xf: Transform3D = WreckLayer.body_transform(Casualties.Body.new(3, shore, 0, 0, facing, 0, 4), slot, _river_board)
			var half: Vector3 = xf.basis.z.normalized() * 0.1125
			for end: Vector3 in [xf.origin + half, xf.origin - half]:
				var r: float = Vector2(end.x - shore.x, end.z - shore.y).length()
				assert_lte(r, 0.3 + 0.01, "біля води тіло не заходить у воду (кінець за %.3f)" % r)


## Два записи на тому самому тайлі й місці (влучання, лікування, знову влучання) лягають не одне на одному.
func test_two_records_on_one_tile_and_slot_lie_apart() -> void:
	var a := Casualties.Body.new(4, Vector2i(3, 3), 0, 0, 2, 3, 1)
	var b := Casualties.Body.new(4, Vector2i(3, 3), 0, 0, 2, 3, 1)
	b.seq = 1
	var pa: Vector3 = WreckLayer.body_transform(a, 3).origin
	var pb: Vector3 = WreckLayer.body_transform(b, 3).origin
	assert_gt(pa.distance_to(pb), 0.03, "друге тіло не на першому")


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
	assert_true(UnitView.OVERLAY_PRIORITY > BoardView.CONTOUR_PRIORITY, "вище за контури зон, вогонь і дощ")


## Колеса й траки моделі крутяться за пройденим шляхом: крок на сусідню клітинку — тайл шляху.
func test_walking_advances_travel_on_a_model_body() -> void:
	UnitSilhouettes.use_models({5: UnitModelFixture.vehicle(5)})
	view.bind(_unit(5, 0, Vector2i(2, 2)))
	var hull := view.get_node("Silhouette/Hull") as GeometryInstance3D
	assert_eq(hull.get_instance_shader_parameter("travel"), 0.0)
	var path: Array[Vector2i] = [Vector2i(3, 2), Vector2i(4, 2)]
	(view.move_along(path, 0.05).get_object() as Tween).custom_step(10.0)
	assert_almost_eq(float(hull.get_instance_shader_parameter("travel")), 2.0, 0.001)
	# Перебудова дошки після дії дає новий вузол: колеса лишаються, де зупинились.
	var rebuilt: UnitView = UnitViewScene.instantiate()
	add_child_autofree(rebuilt)
	rebuilt.bind(_unit(5, 0, Vector2i(4, 2)))
	assert_almost_eq(float((rebuilt.get_node("Silhouette/Hull") as GeometryInstance3D).get_instance_shader_parameter("travel")), 2.0, 0.001)
	UnitView._travel_by_unit.clear()


## Моделі одного типу в різних власників — та сама сітка й той самий матеріал: юніт лишається
## одним викликом малювання, а власника видно лише по смузі HP.
func test_model_bodies_share_mesh_and_material_across_owners() -> void:
	UnitSilhouettes.use_models({5: UnitModelFixture.vehicle(5)})
	var other: UnitView = UnitViewScene.instantiate()
	add_child_autofree(other)
	view.bind(_unit(5, 0))
	other.bind(_unit(5, 1))
	var a := view.get_node("Silhouette/Hull") as MeshInstance3D
	var b := other.get_node("Silhouette/Hull") as MeshInstance3D
	assert_same(a.mesh, b.mesh)
	assert_same(a.material_override, b.material_override)


## Сторону юніта показує лише заливка смуги HP: тіла двох власників однакові, заливки різні, і
## кожна заливка читається на темному тлі смуги.
func test_owners_differ_by_hp_fill_colour_not_by_body_colour() -> void:
	var other: UnitView = UnitViewScene.instantiate()
	add_child_autofree(other)
	view.bind(_unit(5, 0))
	other.bind(_unit(5, 1))
	view.set_hp(400, 400)
	other.set_hp(400, 400)
	var body_a: PackedColorArray = (view.get_node("Silhouette/Hull") as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var body_b: PackedColorArray = (other.get_node("Silhouette/Hull") as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	assert_eq(body_a, body_b, "тіла однакові")
	var mid_y: int = _hp_bar_image(view).get_height() / 2
	assert_eq(_hp_bar_image(view).get_pixel(1, mid_y), _as_rgba8(UnitView.hp_fill_color(0)))
	assert_eq(_hp_bar_image(other).get_pixel(1, mid_y), _as_rgba8(UnitView.hp_fill_color(1)))
	assert_ne(UnitView.hp_fill_color(0), UnitView.hp_fill_color(1))
	# Золоті значення, не через сам hp_fill_color: блок власника 1 починається з 47, повна смуга — 46.
	assert_eq(view.hp_bar_layer(), 46)
	assert_eq(other.hp_bar_layer(), 93)
	assert_eq(_hp_bar_image(other).get_pixel(1, mid_y), _as_rgba8(Color("#a54a3a").lerp(Color.WHITE, 0.3)))
	var decoded: Image = UnitHpBars.layer_image(93)
	assert_eq(decoded.get_pixel(46, mid_y), _as_rgba8(Color("#a54a3a").lerp(Color.WHITE, 0.3)), "шар 93 — власник 1, заливка на всю ширину")
	assert_eq(decoded.get_pixel(47, mid_y), _as_rgba8(UnitView._HP_BAR_FRAME_COLOR), "після заливки — рамка")
	assert_ne(view.hp_bar_layer(), other.hp_bar_layer(), "у спільному MultiMesh шари різних власників різні")
	for o in UnitView.PLAYER_COLORS.size():
		assert_eq(UnitHpBars.layer_image(o * UnitHpBars.fills_per_owner() + 20).get_pixel(1, mid_y), _as_rgba8(UnitView.hp_fill_color(o)), "власник %d" % o)
		var f: Color = UnitView.hp_fill_color(o)
		assert_gt((_lum(f) + 0.05) / (_lum(UnitView._HP_BAR_BACK_COLOR) + 0.05), 3.0, "заливка власника %d відрізняється від тла" % o)


static func _lum(c: Color) -> float:
	var l := c.srgb_to_linear()
	return 0.2126 * l.r + 0.7152 * l.g + 0.0722 * l.b


## Рівень води в шейдері плями — копія `TerrainHeight.WATER_LEVEL`: розбіжність тихо вимкне послаблення над водою.
func test_contact_shadow_shader_water_level_matches_terrain() -> void:
	var src: String = FileAccess.get_file_as_string("res://game/battle/shaders/unit_contact_shadow.gdshader")
	assert_true(src.contains("const float WATER_LEVEL = %s;" % str(TerrainHeight.WATER_LEVEL)), "WATER_LEVEL у шейдері")


## Фігура, що перекидається, за час перекидання сповзає туди, де ляже тіло: тіло з'являється там, де падіння
## скінчилось, а не за метр від нього.
func test_tipping_figure_ends_where_its_body_lies() -> void:
	UnitSilhouettes.use_models({0: UnitModelFixture.soldier(), 1: UnitModelFixture.tube_soldier()})
	view.bind(_unit(0))
	var hull := view._silhouette.get_node("Hull") as Node3D
	var before: int = hull.get_child_count()
	view.set_hp(70, 100)
	var tipping: Array = hull.get_children().slice(before)
	assert_eq(tipping.size(), 1, "передумова: перекидається один")
	var slot: int = view._tipping.keys()[0]
	var spot := Vector3(view.global_position.x + 0.3, 0.0, view.global_position.z - 0.2)
	view.aim_tips({slot: Transform3D(Basis(), spot)})
	for t: Tween in get_tree().get_processed_tweens():
		t.custom_step(UnitView.FALL_TIP_SEC * 0.999)
	var at: Vector3 = (tipping[0] as Node3D).global_position
	assert_almost_eq(Vector2(at.x, at.z), Vector2(spot.x, spot.z), Vector2(0.01, 0.01), "наприкінці — над місцем тіла")
	UnitSilhouettes.use_models({})
