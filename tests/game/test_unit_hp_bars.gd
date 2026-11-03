extends GutTest
## Смуги HP усіх юнітів екрана — один MultiMesh (`UnitHpBars`), а не спрайт і виклик малювання на
## юніта (§8). Спрайт `HpBar` лишається вузлом стану (текстура, видимість), але сам не малюється.

const UnitViewScene := preload("res://game/battle/unit_view.tscn")

var bars: UnitHpBars


func before_each() -> void:
	bars = UnitHpBars.new()
	add_child_autofree(bars)


func _view(type_id: int = 5, pos: Vector2i = Vector2i(2, 3)) -> UnitView:
	var view: UnitView = UnitViewScene.instantiate()
	view.hp_bars = bars
	add_child_autofree(view)
	view.bind(Unit.create(1, type_id, 0, pos, 0))
	return view


func test_all_bars_share_one_multimesh() -> void:
	var a := _view(5, Vector2i(1, 1))
	_view(0, Vector2i(2, 2))
	_view(8, Vector2i(3, 3))
	assert_eq(bars.count(), 3)
	assert_eq(bars.get_child_count(), 0, "один вузол, а не спрайт на юніта")
	assert_eq(a._hp_bar.layers, 0, "спрайт-носій стану не малюється")


func test_layer_is_the_fill_width_of_the_hp_ratio() -> void:
	var view := _view()
	var inner: int = UnitView._HP_BAR_SIZE.x - 2
	for case: Array in [[100, 100, inner], [50, 100, 23], [1, 100, 0], [0, 100, 0], [75, 100, 35]]:
		view.set_hp(case[0], case[1])
		bars.sync()
		assert_eq(bars.layer_of(0), case[2], "hp %d/%d" % [case[0], case[1]])
	assert_eq(UnitHpBars.layer_count(), inner + 1, "по шару на ширину заливки")
	assert_eq(UnitHpBars.layer_image(23).get_pixel(1, 3), UnitView._hp_bar_texture(0.5).get_image().get_pixel(1, 3), "той самий малюнок, що й у спрайта")


func test_bar_hangs_over_the_unit_and_follows_it() -> void:
	var view := _view(5, Vector2i(2, 2))
	assert_eq(bars.position_of(0), view.global_position + Vector3(0.0, view._hp_bar.position.y, 0.0))
	var path: Array[Vector2i] = [Vector2i(3, 2)]
	(view.move_along(path, 0.05).get_object() as Tween).custom_step(10.0)
	bars.sync()
	assert_eq(bars.position_of(0), view.global_position + Vector3(0.0, view._hp_bar.position.y, 0.0))


func test_bar_hides_with_the_unit_and_goes_with_its_node() -> void:
	var a := _view(5, Vector2i(1, 1))
	var b := _view(0, Vector2i(2, 2))
	assert_true(bars.is_shown(0))
	a.play_destroyed()
	bars.sync()
	assert_false(bars.is_shown(0), "загиблий юніт — без смуги")
	assert_true(bars.is_shown(1))
	b.free()
	assert_eq(bars.count(), 1, "звільнений юніт смуги не лишає")


func test_without_a_shared_batch_the_sprite_still_draws() -> void:
	var view: UnitView = UnitViewScene.instantiate()
	add_child_autofree(view)
	view.bind(Unit.create(1, 5, 0, Vector2i(2, 3), 0))
	assert_ne(view._hp_bar.layers, 0, "без батча смугу малює сам спрайт")
