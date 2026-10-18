extends GutTest
## Налаштування проєкту, від яких залежить вигляд на телефоні.

## Фаза 5a: дощ, відбиття й текстурна земля — під Mobile (Vulkan), а не під
## gl_compatibility; той лишається запасним для старих пристроїв (§5).
func test_phones_use_the_mobile_renderer() -> void:
	assert_eq(ProjectSettings.get_setting("rendering/renderer/rendering_method.mobile"), "mobile")
