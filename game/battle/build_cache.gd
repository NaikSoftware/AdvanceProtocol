class_name BuildCache
extends RefCounted
## Дисковий кеш чистих обчислень побудови дошки: результат залежить лише від переданих даних, тож
## той самий ключ дає ті самі байти. Ключ — SHA-256 від вхідних даних і коду скриптів, що рахують
## результат: правка алгоритму чи карти сама стає іншим ключем, ручної інвалідації нема.
## Кеш у user:// не входить у репозиторій. Будь-яка помилка читання чи запису — просто промах.

## Тека кешу; змінна, щоб тести писали в окрему, а не в справжню.
static var dir: String = "user://build_cache"
## Файлів на тег: три карти й запас на варіанти; найстаріші витісняються.
const KEEP_PER_TAG: int = 8


## parts — вхідні дані (будь-які значення, що серіалізуються), scripts — скрипти, чий код рахує результат.
## "" — кешу нема: в експорті source_code порожній, ключ не бачив би правки алгоритму після оновлення
## гри, а user:// оновлення переживає, тож без коду скриптів кешувати не можна.
static func key(parts: Array, scripts: PackedStringArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(var_to_bytes(parts))
	for path in scripts:
		var script: GDScript = load(path) as GDScript if ResourceLoader.exists(path) else null
		if script == null or script.source_code.is_empty():
			return ""
		ctx.update(script.source_code.to_utf8_buffer())
	ctx.update(str(Engine.get_version_info().get("hex", 0)).to_utf8_buffer())
	return ctx.finish().hex_encode().substr(0, 32)


static func _path(tag: String, k: String) -> String:
	return "%s/%s_%s.bin" % [dir, tag, k]


## Значення з кешу або null.
static func fetch(tag: String, k: String) -> Variant:
	if k.is_empty():
		return null
	var f := FileAccess.open(_path(tag, k), FileAccess.READ)
	if f == null:
		return null
	var raw_size: int = f.get_32()
	var packed: PackedByteArray = f.get_buffer(f.get_length() - 4)
	f.close()
	var bytes: PackedByteArray = packed.decompress(raw_size, FileAccess.COMPRESSION_ZSTD)
	if bytes.size() != raw_size:
		return null
	return bytes_to_var(bytes)


static func store(tag: String, k: String, value: Variant) -> void:
	if k.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(dir)
	var bytes: PackedByteArray = var_to_bytes(value)
	# Номер процесу в імені: два запуски гри не пишуть в один тимчасовий файл.
	var tmp: String = "%s.%d.tmp" % [_path(tag, k), OS.get_process_id()]
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_32(bytes.size())
	f.store_buffer(bytes.compress(FileAccess.COMPRESSION_ZSTD))
	f.close()
	# Запис через тимчасовий файл: обірваний запис не лишає надірваного кешу під справжнім ім'ям.
	if DirAccess.rename_absolute(tmp, _path(tag, k)) != OK:
		DirAccess.remove_absolute(tmp)
	_prune(tag)


static func _prune(tag: String) -> void:
	var files: Array[String] = []
	for name in DirAccess.get_files_at(dir):
		if not name.begins_with(tag + "_"):
			continue
		if name.ends_with(".tmp"):
			# Залишок обірваного запису (процес помер до rename).
			DirAccess.remove_absolute("%s/%s" % [dir, name])
		elif name.ends_with(".bin"):
			files.append(name)
	if files.size() <= KEEP_PER_TAG:
		return
	files.sort_custom(func(a: String, b: String) -> bool:
		return FileAccess.get_modified_time("%s/%s" % [dir, a]) > FileAccess.get_modified_time("%s/%s" % [dir, b]))
	for i in range(KEEP_PER_TAG, files.size()):
		DirAccess.remove_absolute("%s/%s" % [dir, files[i]])


## Усі змінні скрипта об'єкта (крім skip та самих об'єктів) — для зліпка стану, який кешується.
static func dump_vars(obj: Object, skip: PackedStringArray = PackedStringArray()) -> Dictionary:
	var out: Dictionary = {}
	for p: Dictionary in obj.get_property_list():
		if not (int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) or skip.has(p["name"]):
			continue
		var v: Variant = obj.get(p["name"])
		if typeof(v) != TYPE_OBJECT:
			out[p["name"]] = v
	return out


static func load_vars(obj: Object, vars: Dictionary) -> void:
	for name: String in vars:
		obj.set(name, vars[name])


## Image <-> масив для var_to_bytes (Image сам не серіалізується без об'єктів).
static func pack_image(img: Image) -> Array:
	return [img.get_width(), img.get_height(), img.get_format(), img.get_data()]


static func unpack_image(a: Array) -> Image:
	return Image.create_from_data(a[0], a[1], false, a[2], a[3])
