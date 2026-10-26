extends GutTest
## Об'їзд дошки за гейтом: точки, з яких камера бачить усю карту, щоб жоден матеріал не
## з'явився в кадрі вперше посеред першого скролу.


func test_stops_are_block_centres_clamped_to_the_board() -> void:
	# 26 колонок блоками по 8: центри 4, 12, 20 і останній блок (24..25) — на краю 25.
	# 22 рядки: блоки 0, 8, 16 з центрами 4, 12, 20 (блок 24 уже за межею).
	var stops: Array[Vector2i] = BoardWarmUp.stops(Vector2i(26, 22), 8)
	assert_eq(stops.size(), 12)
	assert_eq(stops[0], Vector2i(4, 4))
	assert_eq(stops[3], Vector2i(25, 4))
	assert_eq(stops[4], Vector2i(4, 12))
	assert_eq(stops[11], Vector2i(25, 20))


func test_board_smaller_than_one_block_has_a_single_stop_inside_it() -> void:
	var stops: Array[Vector2i] = BoardWarmUp.stops(Vector2i(5, 3), 8)
	assert_eq(stops, [Vector2i(4, 2)] as Array[Vector2i])
