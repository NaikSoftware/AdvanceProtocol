extends Node
## Допоміжний тул для скріншотів екранів UI на заданому розмірі вікна.
## НЕ входить у гру — лише для візуальної перевірки респонсивності.
## Запуск:
##   $GODOT --path . res://tools/ui_shot.tscn -- <scene> <out.png> <w> <h> [locale]
## Автолоади присутні (звичайний main loop), тож _ready екранів не падає на
## SceneRouter.

func _ready() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	if a.size() < 4:
		push_error("ui_shot: очікую <scene> <out> <w> <h> [locale]")
		get_tree().quit(1)
		return
	var scene_path: String = a[0]
	var out_path: String = a[1]
	var w: int = int(a[2])
	var h: int = int(a[3])
	var locale: String = a[4] if a.size() > 4 else "uk"

	TranslationServer.set_locale(locale)
	var win: Window = get_window()
	win.size = Vector2i(w, h)

	var inst: Node = (load(scene_path) as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(inst)

	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout

	var img: Image = get_viewport().get_texture().get_image()
	var err: int = img.save_png(out_path)
	if err != OK:
		push_error("ui_shot: не зберігся PNG (%d)" % err)
	get_tree().quit()
