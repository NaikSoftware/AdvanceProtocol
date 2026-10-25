extends GutTest
## Заступник флипбука до справжніх атласів: та сама сітка 8×8, що в справжніх, клуби з
## твердим краєм (не розмита пляма) і кадри, що справді рухаються.

func _edge_share(img: Image) -> float:
	var soft: int = 0
	var any: int = 0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var a: float = img.get_pixel(x, y).a
			if a > 0.02:
				any += 1
				if a < 0.9:
					soft += 1
	return float(soft) / float(maxi(any, 1))


func test_atlases_are_eight_by_eight_frames() -> void:
	for img: Image in [FxPlaceholder.smoke_atlas(), FxPlaceholder.fire_atlas()]:
		assert_eq(img.get_width(), FxPlaceholder.CELL * 8)
		assert_eq(img.get_height(), FxPlaceholder.CELL * 8)


## Розмиті клуби — головна вада, яку цей заступник прибирає: напівпрозора смуга на
## краю клуби — лише кілька пікселів згладження, а не половина площі.
func test_puffs_have_hard_edges() -> void:
	assert_lt(_edge_share(FxPlaceholder.smoke_atlas()), 0.2)
	assert_lt(_edge_share(FxPlaceholder.fire_atlas()), 0.25)


func test_consecutive_frames_differ() -> void:
	var img: Image = FxPlaceholder.smoke_atlas()
	var c: int = FxPlaceholder.CELL
	var a: Image = img.get_region(Rect2i(0, 0, c, c))
	var b: Image = img.get_region(Rect2i(c, 0, c, c))
	assert_ne(a.get_data(), b.get_data(), "кадри мусять котитися, а не стояти")
