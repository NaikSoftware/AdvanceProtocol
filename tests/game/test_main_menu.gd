extends GutTest
## Головне меню оживає: дощ + брижі в калюжах + дим + мерехтіння/спалахи пожеж
## поверх статичної картинки (Background/Puddles, FireGlow, Smoke, Rain). Тут —
## лише те, що безпечно
## перевірити headless: кепування частоти кадрів (§8 CLAUDE.md, «battery life
## is a feature»), детермінований розкид «спалахів» за затравленим RNG,
## і структура фонових шарів. Сам дрейф диму й мерехтіння шейдера — рух на
## GPU, який перевіряється окремо знімками через tools/ui_seq.gd, не тут.

const MainMenuScene := preload("res://game/ui/main_menu.tscn")

var menu: MainMenu


func before_each() -> void:
	menu = MainMenuScene.instantiate()


func after_each() -> void:
	if is_instance_valid(menu) and not menu.is_queued_for_deletion():
		menu.free()
	menu = null


## Емітери-частинки висять під якірними Control-маркерами (щоб їхати з фоном при
## ресайзі), тож шукаємо їх рекурсивно, а не лише прямими дітьми шару.
func _collect_gpu_particles(node: Node, out: Array) -> void:
	for child in node.get_children():
		if child is GPUParticles2D:
			out.append(child)
		_collect_gpu_particles(child, out)


## Емітер має сидіти під Control-маркером (позицію якого задає cover-перенос
## фону) — саме це тримає ефект на місці відносно намальованих пожеж при ресайзі.
func _assert_under_marker(emitter: Node) -> void:
	var parent: Node = emitter.get_parent()
	assert_true(parent is Control, "емітер має висіти під Control-маркером (щоб їхати з фоном)")


## Рекурсивно: чи є десь під вузлом ColorRect із ShaderMaterial (старий
## шейдер-«трикутник» вогню, який відхилив product owner).
func _has_shader_colorrect(node: Node) -> bool:
	for child in node.get_children():
		if child is ColorRect and (child as ColorRect).material is ShaderMaterial:
			return true
		if _has_shader_colorrect(child):
			return true
	return false


# --- Кепування частоти кадрів (перф-бюджет §8) --------------------------

func test_caps_frame_rate_while_menu_is_active() -> void:
	var previous: int = Engine.max_fps
	Engine.max_fps = 0
	add_child_autofree(menu)

	assert_eq(Engine.max_fps, MainMenu.FRAME_CAP_FPS)

	Engine.max_fps = previous


func test_restores_previous_frame_rate_on_exit() -> void:
	Engine.max_fps = 30
	get_tree().root.add_child(menu)

	assert_eq(Engine.max_fps, MainMenu.FRAME_CAP_FPS)

	get_tree().root.remove_child(menu)
	menu.free()
	assert_eq(Engine.max_fps, 30)
	menu = null


func test_disables_low_processor_mode_while_active() -> void:
	OS.low_processor_usage_mode = true
	add_child_autofree(menu)

	assert_false(OS.low_processor_usage_mode)

	OS.low_processor_usage_mode = false


func test_restores_low_processor_mode_on_exit() -> void:
	OS.low_processor_usage_mode = true
	get_tree().root.add_child(menu)

	get_tree().root.remove_child(menu)
	menu.free()

	assert_true(OS.low_processor_usage_mode)
	OS.low_processor_usage_mode = false
	menu = null


# --- Розкид «спалахів» артилерії: чиста функція від rng, без сцени -------

func test_flash_x_fraction_reproduces_exact_seeded_value() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var got: float = MainMenu.flash_x_fraction(rng)

	var expected := RandomNumberGenerator.new()
	expected.seed = 42
	assert_eq(got, expected.randf_range(MainMenu.FLASH_X_MIN_FRAC, MainMenu.FLASH_X_MAX_FRAC))


func test_flash_y_fraction_reproduces_exact_seeded_value() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var got: float = MainMenu.flash_y_fraction(rng)

	var expected := RandomNumberGenerator.new()
	expected.seed = 7
	assert_eq(got, expected.randf_range(MainMenu.FLASH_Y_MIN_FRAC, MainMenu.FLASH_Y_MAX_FRAC))


func test_next_flash_wait_reproduces_exact_seeded_value() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var got: float = MainMenu.next_flash_wait(rng)

	var expected := RandomNumberGenerator.new()
	expected.seed = 99
	assert_eq(got, expected.randf_range(MainMenu.FLASH_INTERVAL_MIN, MainMenu.FLASH_INTERVAL_MAX))


# --- Структура шарів (Photo → Puddles → FireGlow → Smoke → Rain → …) ---

func test_background_layer_order() -> void:
	add_child_autofree(menu)
	var background: Node = menu.get_node("Background")
	var names: Array = []
	for child in background.get_children():
		names.append(String(child.name))

	assert_eq(names, ["Photo", "Puddles", "FireGlow", "Smoke", "Rain", "Darken",
		"LeftScrim", "Vignette"])


# --- Брижі від крапель у калюжах ------------------------------------------

func test_puddle_ripples_have_a_mask_texture() -> void:
	# Без маски шейдер бачить усюди нуль і сам себе вимикає (discard) — ефект
	# зникає МОВЧКИ, без жодної помилки в логах. Тому перевіряємо саме це.
	add_child_autofree(menu)
	var puddles: ColorRect = menu.get_node("Background/Puddles")
	var mat: ShaderMaterial = puddles.material

	assert_not_null(mat, "шар калюж має ShaderMaterial")
	var mask: Texture2D = mat.get_shader_parameter("puddle_mask")
	assert_not_null(mask, "шейдеру брижів потрібна маска калюж")
	assert_true(mask.get_width() > 0 and mask.get_height() > 0,
		"маска калюж має бути непорожньою текстурою")


func test_puddle_mask_aspect_matches_the_background_painting() -> void:
	# Шейдер САМ повторює KEEP_ASPECT_COVERED фонової картини, щоб маска лягла
	# на намальовані калюжі за будь-якого аспекту вікна — і для цього знає її
	# пропорції окремою уніформою. Якщо картину колись замінять на іншу за
	# пропорціями, а уніформу забудуть, маска поїде і брижі підуть по багну.
	# Ламатись це має тут, а не на очах у гравця.
	add_child_autofree(menu)
	var puddles: ColorRect = menu.get_node("Background/Puddles")
	var declared: float = puddles.material.get_shader_parameter("image_aspect")
	var photo: TextureRect = menu.get_node("Background/Photo")
	var actual: float = float(photo.texture.get_width()) / float(photo.texture.get_height())

	assert_almost_eq(declared, actual, 0.001,
		"image_aspect має збігатися з пропорціями menu_background.jpg")


func test_puddle_ripples_are_drawn_under_the_darkening_layers() -> void:
	# Брижі — частина картини, а не поверх неї: їх мають приглушувати ті самі
	# Darken/LeftScrim/Vignette, що й усе інше. Інакше вони світитимуть крізь
	# затемнення й читатимуться як наклейки.
	add_child_autofree(menu)
	var background: Node = menu.get_node("Background")
	var order: Array[String] = []
	for child in background.get_children():
		order.append(String(child.name))

	assert_true(order.find("Puddles") > order.find("Photo"),
		"калюжі малюються ПІСЛЯ картини")
	for above in ["Darken", "LeftScrim", "Vignette"]:
		assert_true(order.find("Puddles") < order.find(above),
			"калюжі мають бути ПІД шаром %s" % above)


func test_smoke_layer_has_one_capped_particle_emitter_per_fire_point() -> void:
	# Дим знову частинки (GPUParticles2D) — по одному емітеру на кожну намальовану
	# точку вогню (MainMenu.FIRE_POINTS), а не суцільний шейдер-band. Кожен
	# емітер має обмежену кількість частинок (перф-бюджет §8 CLAUDE.md).
	add_child_autofree(menu)
	var smoke: Node = menu.get_node("Background/Smoke")
	var emitters: Array = []
	_collect_gpu_particles(smoke, emitters)

	assert_eq(emitters.size(), MainMenu.FIRE_POINTS.size(),
		"один емітер диму на кожну точку вогню")

	var total: int = 0
	for emitter in emitters:
		var particles: GPUParticles2D = emitter
		assert_true(particles.amount <= MainMenu.SMOKE_PARTICLES_PER_POINT,
			"кількість частинок на емітер має бути в межах перф-бюджету")
		assert_true(particles.amount > 0, "емітер має справді щось випускати")
		assert_not_null(particles.process_material, "емітер має мати ParticleProcessMaterial")
		assert_not_null(particles.texture, "емітер має мати текстуру диму")
		_assert_under_marker(particles)
		total += particles.amount

	assert_true(total <= 600, "сумарна кількість частинок диму має лишатись у перф-бюджеті")


func test_fire_points_render_localized_flame_quads_not_a_band() -> void:
	# Вогонь — ЧАСТИНКИ в точках FIRE_POINTS (полум'я + іскри), а не шейдер-квад
	# з трикутним силуетом (те, що раз за разом відхиляв product owner) і не
	# суцільна смуга на весь горизонт. Полум'яний емітер на кожну точку має
	# additive-бленд (яскраве ядро складається з накладання частинок).
	add_child_autofree(menu)
	var glow: Node = menu.get_node("Background/FireGlow")
	var flame_emitters: Array = []
	_collect_gpu_particles(glow, flame_emitters)

	# Жодного шейдер-квада полум'я НІДЕ під FireGlow (трикутників більше нема).
	assert_false(_has_shader_colorrect(glow),
		"жодного шейдер-квада полум'я — вогонь тепер частинки")
	# Полум'я + іскри = мінімум по одному емітеру на точку (тут два на точку).
	assert_true(flame_emitters.size() >= MainMenu.FIRE_POINTS.size(),
		"щонайменше один вогняний емітер на кожну точку вогню")
	for emitter in flame_emitters:
		var p: GPUParticles2D = emitter
		assert_true(p.amount > 0, "вогняний емітер має щось випускати")
		assert_not_null(p.process_material, "вогняний емітер має мати ParticleProcessMaterial")
		assert_true(p.material is CanvasItemMaterial
			and (p.material as CanvasItemMaterial).blend_mode == CanvasItemMaterial.BLEND_MODE_ADD,
			"вогонь має рендеритись адитивно (яскраве ядро з накладання)")
		_assert_under_marker(p)


func test_cover_map_matches_hand_computed_values() -> void:
	# Незалежний оракул: числа пораховані руками, НЕ викликом тієї ж функції.
	# Картина 2000x1000 у вікні 1000x500 — той самий аспект (2:1), тож cover
	# нічого не обрізає: s = max(1000/2000, 500/1000) = 0.5, disp = 1000x500,
	# off = (0,0) → точка (0.5, 0.35) лягає в (500, 175).
	var img := Vector2(2000.0, 1000.0)
	var same_aspect := MainMenu.cover_map(Vector2(0.5, 0.35), img, Vector2(1000.0, 500.0))
	assert_almost_eq(same_aspect.x, 500.0, 0.01, "X за однакового аспекту")
	assert_almost_eq(same_aspect.y, 175.0, 0.01, "Y за однакового аспекту")

	# Картина 1000x500 у квадратному вікні 1000x1000: s = max(1.0, 2.0) = 2.0,
	# disp = 2000x1000, off = (-500, 0) → точка (0.25, 0.8) лягає в (0, 800).
	var tall := MainMenu.cover_map(Vector2(0.25, 0.8), Vector2(1000.0, 500.0), Vector2(1000.0, 1000.0))
	assert_almost_eq(tall.x, 0.0, 0.01, "X за обрізання по ширині")
	assert_almost_eq(tall.y, 800.0, 0.01, "Y за обрізання по ширині")


func test_wider_window_moves_point_up_not_to_a_fixed_window_fraction() -> void:
	# САМЕ ця регресія: фон тягнеться KEEP_ASPECT_COVERED, тож у ШИРШОМУ вікні
	# картина масштабується по ширині й обрізається зверху/знизу — намальований
	# горизонт піднімається. Ефект, прибитий до частки ВІКНА, лишився б на місці
	# й «поїхав би вниз» відносно пожеж (репорт product owner).
	#
	# Руками: картина 2000x1000, вікно 2000x500 (аспект 4:1).
	#   s = max(2000/2000, 500/1000) = 1.0; disp = 2000x1000;
	#   off.y = (500 - 1000)/2 = -250 → точка y=0.35 лягає в 0.35*1000 - 250 = 100.
	# Наївна частка вікна дала б 0.35 * 500 = 175, тобто на 75 px НИЖЧЕ.
	var wide := MainMenu.cover_map(Vector2(0.5, 0.35), Vector2(2000.0, 1000.0), Vector2(2000.0, 500.0))
	assert_almost_eq(wide.y, 100.0, 0.01, "у ширшому вікні точка має піднятись разом із картиною")
	assert_true(absf(wide.y - 175.0) > 1.0,
		"позиція НЕ сміє збігатися з наївною часткою вікна (0.35 * висоту)")


func test_effect_markers_are_positioned_on_the_horizon_band() -> void:
	# Інтеграція: маркери справді розставлені (а не лишились у (0,0)) і сидять
	# у правій верхній частині екрана — там, де на картині лінія пожеж.
	add_child_autofree(menu)
	assert_true(menu._effect_markers.size() >= MainMenu.FIRE_POINTS.size(),
		"мають бути зареєстровані маркери ефектів (вогонь + дим)")
	var win: Vector2 = menu.get_viewport_rect().size
	for entry in menu._effect_markers:
		var marker: Control = entry["marker"]
		assert_true(marker.position != Vector2.ZERO, "маркер має бути позиціонований, а не в (0,0)")
		assert_true(marker.position.x > win.x * 0.4,
			"пожежі — у правій частині картини, не під меню")
		assert_true(marker.position.y > 0.0 and marker.position.y < win.y * 0.5,
			"пожежі — на горизонті (верхня половина), а не в багні")


func test_rain_shader_defaults_match_spec() -> void:
	add_child_autofree(menu)
	var rain: ColorRect = menu.get_node("Background/Rain")
	var mat: ShaderMaterial = rain.material

	assert_eq(mat.get_shader_parameter("opacity"), 0.16)
	assert_eq(mat.get_shader_parameter("density"), 110.0)
	assert_eq(mat.get_shader_parameter("fall_speed"), 0.9)
	assert_eq(mat.get_shader_parameter("angle"), 0.14)
	assert_eq(mat.get_shader_parameter("streak_length"), 0.18)
	assert_eq(mat.get_shader_parameter("wind"), 0.08)


# --- Спалахи: таймер, спавн, і детермінований fade-out через ручний крок -

func test_flash_timer_starts_within_configured_interval() -> void:
	add_child_autofree(menu)
	var timer: Timer = menu.get_node("FlashTimer")

	assert_true(timer.time_left > 0.0)
	assert_true(timer.wait_time >= MainMenu.FLASH_INTERVAL_MIN and timer.wait_time <= MainMenu.FLASH_INTERVAL_MAX)


func test_flash_timeout_spawns_a_flash_and_reschedules() -> void:
	add_child_autofree(menu)
	var glow: Control = menu.get_node("Background/FireGlow")
	var before: int = glow.get_child_count()

	menu._on_flash_timer_timeout()

	assert_eq(glow.get_child_count(), before + 1)
	var timer: Timer = menu.get_node("FlashTimer")
	assert_true(timer.time_left > 0.0)


func test_flash_glow_fades_out_and_frees_itself() -> void:
	add_child_autofree(menu)
	var glow: Control = menu.get_node("Background/FireGlow")
	var tween: Tween = menu._spawn_flash()
	var flash: Node = glow.get_children().back()
	assert_not_null(flash)

	# Тестова нотатка: не чекаємо tween.finished у реальному часі — прокручуємо
	# сам об'єкт tween вручну на весь час згасання одним детермінованим кроком.
	tween.custom_step(MainMenu.FLASH_FADE_IN_TIME + MainMenu.FLASH_FADE_OUT_TIME + 0.05)
	await get_tree().process_frame

	assert_true(not is_instance_valid(flash) or flash.is_queued_for_deletion())


# --- «Продовжити»: показуємо лише коли є збереження, інакше ховаємо ------
# Обидві гілки перевіряємо явно: тест впаде, якщо умову інвертувати
# (`not file_exists`) — саме та регресія, яку легко пропустити.

## Знімає збереження на час тесту й повертає його вміст (щоб не затерти
## реальний save у пісочниці user://).
func _detach_save() -> Dictionary:
	var existed: bool = FileAccess.file_exists(MainMenu.SAVE_PATH)
	var backup: String = ""
	if existed:
		backup = FileAccess.get_file_as_string(MainMenu.SAVE_PATH)
		DirAccess.remove_absolute(MainMenu.SAVE_PATH)
	return {"existed": existed, "backup": backup}


func _restore_save(state: Dictionary) -> void:
	if state["existed"]:
		var f := FileAccess.open(MainMenu.SAVE_PATH, FileAccess.WRITE)
		f.store_string(state["backup"])
		f.close()
	elif FileAccess.file_exists(MainMenu.SAVE_PATH):
		DirAccess.remove_absolute(MainMenu.SAVE_PATH)


func test_continue_button_hidden_when_no_save() -> void:
	var saved := _detach_save()
	add_child_autofree(menu)

	assert_false((menu.get_node("%ContinueButton") as Button).visible,
		"без збереження кнопку «Продовжити» треба ховати, а не лишати задісейбленою")

	_restore_save(saved)


func test_continue_button_shown_when_save_exists() -> void:
	var saved := _detach_save()
	var f := FileAccess.open(MainMenu.SAVE_PATH, FileAccess.WRITE)
	f.store_string("{}")
	f.close()

	add_child_autofree(menu)

	assert_true((menu.get_node("%ContinueButton") as Button).visible,
		"за наявності збереження «Продовжити» має бути видимою")

	_restore_save(saved)
