extends GutTest

func test_gut_runs() -> void:
	assert_eq(1 + 1, 2, "арифметика жива")

func test_core_dir_exists() -> void:
	assert_true(DirAccess.dir_exists_absolute("res://core"), "каталог core/ має існувати")
