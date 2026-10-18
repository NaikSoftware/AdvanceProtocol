extends SceneTree
## Конвертує tools/maps/*.txt у maps/*.tres.
## Запуск: $GODOT --headless --path . -s res://tools/build_maps.gd

const SRC: String = "res://tools/maps"
const DST: String = "res://maps"


func _init() -> void:
	var failed: bool = false
	var files: PackedStringArray = DirAccess.get_files_at(SRC) if DirAccess.dir_exists_absolute(SRC) else PackedStringArray()
	var any: bool = false
	for f in files:
		if f.get_extension() != "txt":
			continue
		any = true
		var m: MapData = MapAscii.parse(FileAccess.get_file_as_string(SRC + "/" + f))
		if m == null or ResourceSaver.save(m, "%s/%s.tres" % [DST, f.get_basename()]) != OK:
			printerr("не вдалося: " + f)
			failed = true
		else:
			print("ok: " + f)
	if not any:
		print("tools/maps/ порожня — нічого конвертувати")
	quit(1 if failed else 0)
