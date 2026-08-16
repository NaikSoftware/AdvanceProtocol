extends Node
## Допоміжний тул для перевірки АНІМОВАНОГО фону: на відміну від ui_shot.gd
## (один кадр), тут — послідовність кадрів у часі, бо один скріншот не може
## довести рух (дощ, дим, мерехтіння/спалахи пожеж). НЕ входить у гру.
##
## Запуск:
##   $GODOT --path . res://tools/ui_seq.tscn -- <scene> <out_dir> [w] [h] [locale]
##
## Зберігає <out_dir>/menu_live_1.png .. _4.png за накопиченим часом від
## старту сцени: ≈ 0.5s, 1.5s, 3.0s, 5.0s (ELAPSED_POINTS нижче).
##
## Автолоади присутні (звичайний main loop), тож _ready екранів не падає на
## SceneRouter — той самий прийом, що й tools/ui_shot.gd. Той самий пастка й
## тут: НІКОЛИ не add_child під час _ready цього тула — інстанс сцени
## додається через call_deferred.

const ELAPSED_POINTS: Array[float] = [0.5, 1.5, 3.0, 5.0]


func _ready() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	if a.size() < 2:
		push_error("ui_seq: очікую <scene> <out_dir> [w] [h] [locale]")
		get_tree().quit(1)
		return
	var scene_path: String = a[0]
	var out_dir: String = a[1]
	var w: int = int(a[2]) if a.size() > 2 else 1280
	var h: int = int(a[3]) if a.size() > 3 else 720
	var locale: String = a[4] if a.size() > 4 else "uk"
	# Опційно: сховати вузол (напр. "Background/Photo"), щоб бачити САМІ ефекти
	# над темним фоном, а не поверх уже намальованих у картині диму/вогню.
	var hide_path: String = a[5] if a.size() > 5 else ""
	# Опційно "WxH": після 2-го кадру змінити розмір вікна на цей — щоб перевірити,
	# що ефекти лишаються на своїх місцях відносно фону при ресайзі.
	var resize_spec: String = a[6] if a.size() > 6 else ""

	DirAccess.make_dir_recursive_absolute(out_dir)

	TranslationServer.set_locale(locale)
	var win: Window = get_window()
	win.size = Vector2i(w, h)

	var inst: Node = (load(scene_path) as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(inst)

	await get_tree().process_frame
	await get_tree().process_frame

	if hide_path != "":
		var hidden: Node = inst.get_node_or_null(hide_path)
		if hidden and hidden is CanvasItem:
			(hidden as CanvasItem).visible = false
		RenderingServer.set_default_clear_color(Color(0.04, 0.05, 0.06, 1.0))

	var elapsed: float = 0.0
	for i in ELAPSED_POINTS.size():
		var target: float = ELAPSED_POINTS[i]
		var wait_for: float = target - elapsed
		if wait_for > 0.0:
			await get_tree().create_timer(wait_for).timeout
			elapsed += wait_for
		# Кадр щойно відмальований — знімок відповідає саме цьому моменту часу.
		await RenderingServer.frame_post_draw

		var img: Image = get_viewport().get_texture().get_image()
		var out_path: String = out_dir.path_join("menu_live_%d.png" % (i + 1))
		var err: int = img.save_png(out_path)
		if err != OK:
			push_error("ui_seq: не зберігся PNG %s (%d)" % [out_path, err])
		else:
			print("ui_seq: saved %s at t≈%.2fs" % [out_path, target])

		# Ресайз посеред запису: кадри 1-2 у старому розмірі, 3-4 — у новому.
		if resize_spec != "" and i == 1:
			var wh: PackedStringArray = resize_spec.split("x")
			if wh.size() == 2:
				win.size = Vector2i(int(wh[0]), int(wh[1]))
				print("ui_seq: resized window to %s" % resize_spec)
				await get_tree().process_frame
				await get_tree().process_frame

	get_tree().quit()
