extends GutTest

## Локалізація з першого дня (§3, Task 3.1).
## Ключі беруться з РЕАЛЬНОГО коду: назви юнітів — з UnitTypes, ключі помилок —
## скануванням сирців core/. Жорсткого списку немає навмисно: новий ERR_-ключ,
## доданий у команду, автоматично мусить мати переклад, інакше цей тест червоніє.
## Це і є той запобіжник, що не дає "ERR_SOMETHING" просочитися на екран.

const LOCALES: Array[String] = ["uk", "en"]

var _orig_locale: String = ""


func before_all() -> void:
	_orig_locale = TranslationServer.get_locale()


func after_all() -> void:
	# Не залишаємо змінену локаль іншим тестовим файлам того ж прогону.
	TranslationServer.set_locale(_orig_locale)


func _scan_core_error_keys() -> Array[String]:
	# Межа сканера: ловить лише інлайн-літерали "ERR_..." у сирцях core/. Ключ,
	# зібраний конкатенацією, винесений у const, з цифрою в імені, або емітований
	# із шару game/ — пройде повз. Наразі всі 26 ключів є інлайн-літералами.
	var re := RegEx.new()
	re.compile('"(ERR_[A-Z_]+)"')
	var found := {}
	_scan_dir("res://core", re, found)
	var keys: Array[String] = []
	for k in found:
		keys.append(k)
	keys.sort()
	return keys


func _scan_dir(path: String, re: RegEx, found: Dictionary) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := path.path_join(entry)
		if dir.current_is_dir():
			_scan_dir(full, re, found)
		elif entry.ends_with(".gd"):
			var text := FileAccess.get_file_as_string(full)
			for m in re.search_all(text):
				found[m.get_string(1)] = true
		entry = dir.get_next()
	dir.list_dir_end()


func test_every_unit_name_key_is_translated() -> void:
	for i in UnitTypes.count():
		var key: String = UnitTypes.get_type(i)["name_key"]
		for locale in LOCALES:
			TranslationServer.set_locale(locale)
			assert_ne(tr(key), key, "немає перекладу %s для %s" % [key, locale])


func test_every_error_key_is_translated() -> void:
	var keys := _scan_core_error_keys()
	assert_gt(keys.size(), 0, "у core/ не знайдено жодного ERR_ ключа — сканер зламався")
	for locale in LOCALES:
		TranslationServer.set_locale(locale)
		for key in keys:
			assert_ne(tr(key), key, "немає перекладу %s для %s" % [key, locale])
