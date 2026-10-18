class_name UiScale
extends RefCounted
## Логічний px ≈ dp на будь-якому екрані: stretch "canvas_items" уже вписує
## BASE у вікно, а content_scale_factor докручує решту до dpi/160. Формула
## загальна — жодного конкретного пристрою; ПК і планшет не зменшуються (≥ 1.0).

const BASE := Vector2i(1280, 720)
const DP_DPI: float = 160.0
const _DPI_ARG: String = "--ui-dpi="


static func factor(screen_px: Vector2i, dpi: float) -> float:
	if dpi <= 0.0 or screen_px.x <= 0 or screen_px.y <= 0:
		return 1.0
	var stretch: float = minf(float(screen_px.x) / BASE.x, float(screen_px.y) / BASE.y)
	return maxf(1.0, (dpi / DP_DPI) / stretch)


## `--ui-dpi=N` після `--` у командному рядку — емуляція телефона на ПК.
static func dpi_override(args: PackedStringArray) -> float:
	for arg: String in args:
		if arg.begins_with(_DPI_ARG):
			return arg.substr(_DPI_ARG.length()).to_float()
	return -1.0


static func apply(window: Window) -> void:
	# headless-вікно 64×64 без екрана: фактор 12 перекроїв би кожен тест сцени.
	if DisplayServer.get_name() == "headless":
		return
	var dpi: float = dpi_override(OS.get_cmdline_user_args())
	if dpi <= 0.0:
		# screen_get_scale() на Android не підтримується в Godot 4 — лише DPI.
		dpi = DisplayServer.screen_get_dpi()
	var update := func() -> void:
		window.content_scale_factor = factor(window.size, dpi)
	update.call()
	window.size_changed.connect(update)
