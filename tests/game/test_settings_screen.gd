extends GutTest
## Повзунки гучності пишуть на диск лише по відпусканню, а не на кожен крок драгу.

var _saves: int = 0
var _screen: SettingsScreen
var _music_before: float
var _sfx_before: float


func before_each() -> void:
	_music_before = SettingsService.music_volume
	_sfx_before = SettingsService.sfx_volume
	_screen = preload("res://game/ui/settings_screen.tscn").instantiate()
	add_child_autofree(_screen)
	_screen.overlay = true
	_saves = 0
	# Ніколи не пишемо в справжній user://settings.cfg.
	_screen._persist = func() -> void: _saves += 1


func after_each() -> void:
	SettingsService.music_volume = _music_before
	SettingsService.sfx_volume = _sfx_before


func test_slider_drag_saves_once_on_drag_ended_not_per_value_change() -> void:
	var music: HSlider = _screen.get_node("%MusicSlider")
	for v in [0.1, 0.2, 0.3, 0.4, 0.5]:
		music.value = v
	assert_eq(SettingsService.music_volume, 0.5, "гучність застосовується наживо")
	assert_eq(_saves, 0, "жодного запису посеред драгу")
	music.drag_ended.emit(true)
	assert_eq(_saves, 1)
	var sfx: HSlider = _screen.get_node("%SfxSlider")
	sfx.value = 0.3
	assert_eq(_saves, 1)
	sfx.drag_ended.emit(true)
	assert_eq(_saves, 2)


## Клавіатура/геймпад міняють значення без драгу — Назад страхує від втрати.
func test_back_persists() -> void:
	(_screen.get_node("%MusicSlider") as HSlider).value = 0.2
	_screen._on_back_pressed()
	assert_eq(_saves, 1)


func test_back_without_changes_or_after_drag_end_does_not_save() -> void:
	var scr := preload("res://game/ui/settings_screen.tscn").instantiate() as SettingsScreen
	add_child_autofree(scr)
	scr.overlay = true
	var n: Array = [0]
	scr._persist = func() -> void: n[0] += 1
	var music: HSlider = scr.get_node("%MusicSlider")
	music.value = 0.3
	music.drag_ended.emit(true)
	assert_eq(n[0], 1)
	scr._on_back_pressed()
	assert_eq(n[0], 1, "після drag_ended нічого незбереженого — Назад не пише вдруге")
