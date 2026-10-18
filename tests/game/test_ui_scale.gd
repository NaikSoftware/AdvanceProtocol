extends GutTest
## Task 4.1: логічний px ≈ dp на будь-якому телефоні — формула від розміру
## екрана й DPI, без жодного конкретного пристрою. Pixel 10 Pro XL — лише зразок.


func test_large_phone_gets_dp_factor() -> void:   # приклад: Pixel 10 Pro XL
	assert_almost_eq(UiScale.factor(Vector2i(2992, 1344), 486.0), 1.627, 0.005)


func test_desktop_1080p_keeps_current_look() -> void:
	assert_eq(UiScale.factor(Vector2i(1920, 1080), 96.0), 1.0)


func test_tablet_2560x1600_is_not_shrunk() -> void:
	assert_eq(UiScale.factor(Vector2i(2560, 1600), 276.0), 1.0)


func test_logical_height_is_dp_on_any_phone() -> void:   # 2400×1080 @ 480 → 360 dp; Pixel → 442 dp; 1600×720 @ 320 → 360 dp
	for c: Array in [[Vector2i(2400, 1080), 480.0], [Vector2i(2992, 1344), 486.0], [Vector2i(1600, 720), 320.0]]:
		var f: float = UiScale.factor(c[0], c[1])
		var logical_h: float = 720.0 / f
		assert_almost_eq(logical_h, c[0].y / (c[1] / 160.0), 1.0)


func test_half_size_pixel_emulation_matches_pixel() -> void:
	assert_almost_eq(UiScale.factor(Vector2i(1496, 672), 243.0), UiScale.factor(Vector2i(2992, 1344), 486.0), 0.001)


func test_zero_dpi_falls_back_to_one() -> void:   # headless повертає 96 або 0 — не ділити на нуль
	assert_eq(UiScale.factor(Vector2i(1280, 720), 0.0), 1.0)


func test_dpi_override_parsed_from_user_args() -> void:
	assert_eq(UiScale.dpi_override(PackedStringArray(["--ui-dpi=486"])), 486.0)
	assert_eq(UiScale.dpi_override(PackedStringArray()), -1.0)
