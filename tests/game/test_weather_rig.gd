extends GutTest
## Небо, світло й погода бою. Шейдери GUT не компілює, тож перевіряються оточення, світло й
## частинки, які отримує сцена. Погода й час доби — суто вигляд (§3.12).

const MAPS: Array[String] = ["res://maps/river.tres", "res://maps/crossroads.tres",
		"res://maps/ridge.tres"]


func _rig() -> WeatherRig:
	var rig := WeatherRig.new()
	add_child_autofree(rig)
	return rig


func test_weather_rig_gives_a_shader_sky_colour_ambient_and_no_fog() -> void:
	var env: Environment = _rig().environment
	assert_not_null(env)
	assert_eq(env.background_mode, Environment.BG_SKY)
	assert_not_null(env.sky)
	var mat := env.sky.sky_material as ShaderMaterial
	assert_not_null(mat, "небо — шейдер, не процедурне блакитне")
	assert_eq(mat.shader.resource_path, "res://game/battle/shaders/overcast_sky.gdshader")
	assert_eq(env.ambient_light_source, Environment.AMBIENT_SOURCE_COLOR)
	assert_eq(env.reflected_light_source, Environment.REFLECTION_SOURCE_SKY)
	# Земля пише власний FOG, тож туман оточення сірив би лише юніти над чіткою землею.
	assert_false(env.fog_enabled)


func test_battle_screen_has_one_weather_rig_and_one_sun_with_shadows() -> void:
	var screen: Node = (load("res://game/battle/battle_screen.tscn") as PackedScene).instantiate()
	add_child_autofree(screen)
	assert_eq(screen.find_children("*", "WorldEnvironment", true, false).size(), 1)
	assert_true(screen.get_node("WeatherRig") is WeatherRig)
	var suns: Array[Node] = screen.find_children("*", "DirectionalLight3D", true, false)
	assert_eq(suns.size(), 1, "§8: одне напрямлене світло")
	assert_true((suns[0] as DirectionalLight3D).shadow_enabled)


func test_river_rains_and_the_other_maps_stay_dry() -> void:
	assert_true(BattleLook.for_map_path("res://maps/river.tres").rain)
	for path: String in ["res://maps/crossroads.tres", "res://maps/ridge.tres", ""]:
		var look: BattleLook = BattleLook.for_map_path(path)
		assert_false(look.rain, path)
		assert_eq(look.wetness, 0.0, path)


## Дощ чи мокра земля на карті з ґрунтом «сухо» суперечили б значку ґрунту в HUD (§3.12).
func test_only_a_map_whose_ground_is_not_dry_looks_wet() -> void:
	for path: String in MAPS:
		var look: BattleLook = BattleLook.for_map_path(path)
		if (load(path) as MapData).ground_state == Terrain.GroundState.DRY:
			assert_false(look.rain, path)
			assert_eq(look.wetness, 0.0, path)


func test_each_map_has_its_own_light() -> void:
	var seen: Dictionary = {}
	for path: String in MAPS:
		var look: BattleLook = BattleLook.for_map_path(path)
		seen[[look.light_color, look.light_pitch_deg, look.light_yaw_deg]] = path
	assert_eq(seen.size(), MAPS.size())


func test_apply_sets_the_sun_from_the_look() -> void:
	var rig: WeatherRig = _rig()
	var look: BattleLook = BattleLook.for_map_path("res://maps/ridge.tres")
	rig.apply(look)
	assert_eq(rig.sun.light_color, look.light_color)
	assert_almost_eq(rig.sun.light_energy, look.light_energy, 1e-5)
	assert_almost_eq(rig.sun.rotation_degrees.x, -look.light_pitch_deg, 1e-3)
	assert_almost_eq(rig.sun.rotation_degrees.y, look.light_yaw_deg, 1e-3)
	assert_true(rig.sun.shadow_enabled)
	assert_almost_eq(rig.sun.shadow_opacity, look.shadow_opacity, 1e-5)
	assert_almost_eq(rig.sun.shadow_blur, look.shadow_blur, 1e-5)
	assert_almost_eq(rig.environment.ambient_light_energy, look.ambient_energy, 1e-5)
	assert_eq(rig.environment.ambient_light_color, look.ambient_color)
	var sky := rig.environment.sky.sky_material as ShaderMaterial
	assert_almost_eq(float(sky.get_shader_parameter("clear_amount")), look.sky_clear, 1e-5)
	# Запечене світло-тінь рельєфу мусить дивитись на те саме сонце, що кидає тіні юнітів.
	var to_sun: Vector3 = rig.applied_globals[&"sun_dir"]
	assert_almost_eq(to_sun, -(rig.sun.basis * Vector3.FORWARD), Vector3.ONE * 1e-4)
	assert_gt(to_sun.y, 0.0, "сонце над обрієм")


func test_apply_sends_the_haze_foliage_and_sky_to_every_material() -> void:
	var rig: WeatherRig = _rig()
	var look: BattleLook = BattleLook.for_map_path("res://maps/crossroads.tres")
	rig.apply(look)
	var c: Color = look.haze_color
	assert_eq(rig.applied_globals[&"haze_color"], Vector3(c.r, c.g, c.b))
	c = look.foliage_tint
	assert_eq(rig.applied_globals[&"foliage_tint"], Vector3(c.r, c.g, c.b))
	assert_almost_eq(rig.applied_globals[&"sky_clear"], look.sky_clear, 1e-5)
	assert_almost_eq(rig.applied_globals[&"water_murk"], look.water_murk, 1e-5)
	for g: String in ["sun_dir", "sky_clear", "foliage_tint", "haze_color", "water_murk"]:
		assert_true(ProjectSettings.has_setting("shader_globals/" + g), g)


## Хмарне чи ясне небо задає світло: під хмарами тіні бліді й м'які, а світло неба сильне
## відносно сонця; на ясному небі — навпаки.
func test_the_sky_type_decides_shadows_and_ambient() -> void:
	var overcast: BattleLook = BattleLook.for_map_path("res://maps/river.tres")
	assert_lt(overcast.sky_clear, 0.5, "Річка похмура")
	for path: String in ["res://maps/crossroads.tres", "res://maps/ridge.tres"]:
		var clear: BattleLook = BattleLook.for_map_path(path)
		assert_gt(clear.sky_clear, 0.5, path)
		assert_lt(overcast.shadow_opacity, clear.shadow_opacity, path)
		assert_gt(overcast.shadow_blur, clear.shadow_blur, path)
		assert_gt(overcast.ambient_energy / overcast.light_energy,
				clear.ambient_energy / clear.light_energy, path)


## Похмура вода Річки затверджена як є: каламутність її не торкається. Під ясним небом став
## мусить бути темним, а не блакитним.
func test_only_clear_sky_water_is_murky() -> void:
	assert_eq(BattleLook.for_map_path("res://maps/river.tres").water_murk, 0.0)
	for path: String in ["res://maps/crossroads.tres", "res://maps/ridge.tres"]:
		assert_gt(BattleLook.for_map_path(path).water_murk, 0.0, path)


## Брижа йде з погодою: Річка під вітром і дощем, Хребет — легкий вітерець, Перехрестя — майже
## тихе повітря. Брижа Річки затверджена як є.
func test_water_waves_follow_the_weather() -> void:
	var river: BattleLook = BattleLook.for_map_path("res://maps/river.tres")
	var ridge: BattleLook = BattleLook.for_map_path("res://maps/ridge.tres")
	var crossroads: BattleLook = BattleLook.for_map_path("res://maps/crossroads.tres")
	assert_eq(river.water_wind, 1.0)
	assert_gt(river.water_wind, ridge.water_wind)
	assert_gt(ridge.water_wind, crossroads.water_wind)
	assert_gt(crossroads.water_wind, 0.0, "вода не мертва")
	var rig: WeatherRig = _rig()
	rig.apply(ridge)
	assert_almost_eq(rig.applied_globals[&"water_wind"], ridge.water_wind, 1e-5)
	assert_true(ProjectSettings.has_setting("shader_globals/water_wind"))


func test_each_map_names_its_season() -> void:
	var want: Dictionary = {"res://maps/river.tres": &"late",
			"res://maps/crossroads.tres": &"summer", "res://maps/ridge.tres": &"early"}
	for path: String in want:
		assert_eq(BattleLook.for_map_path(path).season, want[path], path)


func test_apply_turns_rain_and_wetness_on_and_off() -> void:
	var rig: WeatherRig = _rig()
	var wet: BattleLook = BattleLook.for_map_path("res://maps/river.tres")
	rig.apply(wet)
	assert_true(rig.rain.visible)
	assert_eq(rig.rain_drops(), wet.rain_amount)
	assert_almost_eq(rig.applied_globals[&"weather_wetness"], wet.wetness, 1e-5)
	assert_almost_eq(rig.applied_globals[&"cloud_shadow_strength"], wet.cloud_shadow_strength, 1e-5)
	rig.apply(BattleLook.for_map_path("res://maps/crossroads.tres"))
	assert_false(rig.rain.visible)
	assert_eq(rig.rain_drops(), 0)
	assert_eq(rig.applied_globals[&"weather_wetness"], 0.0)


func _rain_uniforms() -> Array[String]:
	var names: Array[String] = []
	var shader := load("res://game/battle/shaders/rain.gdshader") as Shader
	for u: Dictionary in shader.get_shader_uniform_list():
		names.append(String(u.name))
	# Порожній список зробив би перевірки «нема такого uniform» порожніми.
	assert_true("cell_origin" in names and "exposure" in names, "uniform шейдера дощу прочитано")
	return names


## Краплі прив'язані до світу: де крапля, вирішує світовий номер її клітинки, а не фокус камери.
## Шейдер не бачить фокуса; кутова клітинка решітки — ціле кратне кроку, тож пан менший за
## клітинку нічого не міняє, а більший зсуває решітку на цілі кроки — кожна крапля лишається на
## своєму місці світу. Розмір клітинки не залежить ні від фокуса, ні від зуму.
func test_rain_drops_stay_in_the_world_when_the_camera_pans() -> void:
	var names: Array[String] = _rain_uniforms()
	assert_false("focus" in names, "шейдер дощу не мусить рахувати краплі від фокуса")
	assert_false("box_size" in names)
	var rig: WeatherRig = _rig()
	rig.apply(BattleLook.for_map_path("res://maps/river.tres"))
	var mat := rig.rain.material_override as ShaderMaterial
	rig.follow(Vector3(5.0, 0.0, 7.0), 12.0)
	var o1: Vector3 = mat.get_shader_parameter("cell_origin")
	var s: float = mat.get_shader_parameter("stride")
	var cell: Vector3 = mat.get_shader_parameter("cell")
	assert_eq(fposmod(o1.x, s), 0.0)
	assert_eq(fposmod(o1.z, s), 0.0)
	# Пан на чверть кроку від кута коробки посередині клітинки: решітка та сама.
	var box: AABB = WeatherRig.rain_box(Vector3(5.0, 0.0, 7.0), 12.0)
	var step: float = cell.x * s
	var mid: float = (floorf(box.position.x / step) + 0.5) * step - box.position.x
	rig.follow(Vector3(5.0 + mid, 0.0, 7.0), 12.0)
	var o_mid: Vector3 = mat.get_shader_parameter("cell_origin")
	rig.follow(Vector3(5.0 + mid + step * 0.25, 0.0, 7.0), 12.0)
	assert_eq(mat.get_shader_parameter("cell_origin"), o_mid)
	# Пан на кілька клітинок: решітка зсувається на цілі кроки, клітинка та сама.
	for pan: float in [1.37, 4.9, -3.3]:
		rig.follow(Vector3(5.0 + pan, 0.0, 7.0 - pan * 0.5), 12.0)
		var o2: Vector3 = mat.get_shader_parameter("cell_origin")
		assert_eq(fposmod(o2.x - o1.x, s), 0.0, "пан %s" % pan)
		assert_eq(fposmod(o2.z - o1.z, s), 0.0, "пан %s" % pan)
		assert_eq(mat.get_shader_parameter("cell"), cell)


## Зум бере рідшу решітку тих самих світових клітинок (крок — степінь двійки), тож краплі,
## що лишились видимими, не зсуваються.
func test_rain_zoom_thins_the_same_world_lattice() -> void:
	var rig: WeatherRig = _rig()
	rig.apply(BattleLook.for_map_path("res://maps/river.tres"))
	var mat := rig.rain.material_override as ShaderMaterial
	var cell: Vector3 = Vector3.ZERO
	var last: float = 0.0
	for zoom: float in [6.0, 13.0, 20.0]:
		rig.follow(Vector3(5.0, 0.0, 7.0), zoom)
		var s: float = mat.get_shader_parameter("stride")
		assert_eq(s, pow(2.0, roundf(log(s) / log(2.0))), "крок — степінь двійки")
		assert_true(s >= last)
		last = s
		if cell != Vector3.ZERO:
			assert_eq(mat.get_shader_parameter("cell"), cell, "зум %s" % zoom)
		cell = mat.get_shader_parameter("cell")
	assert_eq(mat.get_shader_parameter("stride"), 4.0, "найбільше віддалення бере кожну четверту")


## Частка решітки, що малюється в коробці дощу на цьому зумі: клітинки з рангом нижче `keep`,
## чий центр у коробці (за дзеркалом рангу шейдера).
func _drawn_in_box(grid: Vector3, focus: Vector3, zoom: float) -> float:
	var lat: Dictionary = WeatherRig.rain_lattice(focus, zoom, grid)
	var box: AABB = WeatherRig.rain_box(focus, zoom)
	var cell: Vector3 = lat.cell
	var n: int = 0
	for gz in int(grid.z):
		for gy in int(grid.y):
			for gx in int(grid.x):
				var wc: Vector3 = lat.origin + Vector3(gx, gy, gz) * float(lat.stride)
				if WeatherRig.rain_rank(wc) >= lat.keep:
					continue
				var c: Vector3 = (wc + Vector3(0.5, 0.5, 0.5)) * cell
				if box.has_point(c):
					n += 1
	return float(n) / (grid.x * grid.y * grid.z)


## Густота дощу на екрані неперервна по зуму: частка крапель, що малюються в коробці кадру, та
## сама по обидва боки порогів кроку (6 і 12 — 12 ще й типовий зум) і на всьому діапазоні.
## Без рангу з фіксованою кількістю квадів крок, що подвоюється, лишав би в кадрі восьму частину.
func test_rain_density_on_screen_is_continuous_across_zoom() -> void:
	var grid := Vector3(32, WeatherRig.RAIN_LAYERS, 32)
	# Кілька фокусів: на крупному кроці в коробці ~17 вузлів решітки по осі, і чи потрапляє
	# крайній, залежить від того, де стоїть камера.
	var foci: Array[Vector3] = [Vector3(7.3, 0.0, 5.1), Vector3(-4.6, 0.0, 12.2),
			Vector3(18.9, 0.0, -2.7), Vector3(1.1, 0.0, 1.9)]
	var at := func(zoom: float) -> float:
		var sum: float = 0.0
		for f: Vector3 in foci:
			sum += _drawn_in_box(grid, f, zoom)
		return sum / foci.size()
	# Пороги кроку із запасом у клітинку — 6·(G-1)/G·{1, 2}: пари стоять по обидва їхні боки.
	var t1: float = IsoCameraRig.MIN_ZOOM * (grid.x - 1.0) / grid.x
	for pair: Array in [[t1 - 0.02, t1 + 0.02], [2.0 * t1 - 0.02, 2.0 * t1 + 0.02]]:
		var sa: int = WeatherRig.rain_lattice(foci[0], pair[0], grid).stride
		var sb: int = WeatherRig.rain_lattice(foci[0], pair[1], grid).stride
		assert_eq(sb, sa * 2, "пара %s мусить перетинати поріг кроку" % [pair])
		var a: float = at.call(pair[0])
		var b: float = at.call(pair[1])
		assert_almost_eq(b / a, 1.0, 0.1, "зум %s / %s" % pair)
	var all: Array[float] = []
	for z in range(6, 21):
		all.append(at.call(float(z)))
	var mean: float = 0.0
	for f: float in all:
		mean += f / all.size()
	for i in all.size():
		assert_almost_eq(all[i] / mean, 1.0, 0.1, "зум %d" % (i + 6))


## `keep` має замкнену форму й ніколи не перевищує 8^-log2(крок): інакше клітинка з рангом під
## порогом могла б лежати поза решіткою кроку, і густота на порозі просідала б.
func test_rain_keep_never_exceeds_the_stride_bound() -> void:
	for side: float in [32.0, 40.0, 46.0, 60.0]:
		var grid := Vector3(side, WeatherRig.RAIN_LAYERS, side)
		var m: float = (side - 1.0) / side
		for i in 1401:
			var zoom: float = 6.0 + i * 0.01
			var lat: Dictionary = WeatherRig.rain_lattice(Vector3(3.3, 0, -2.1), zoom, grid)
			var want: float = m * m * m / 8.0 * pow(IsoCameraRig.MIN_ZOOM / zoom, 3.0)
			assert_almost_eq(float(lat.keep), want, 1e-12)
			var bound: float = pow(8.0, -log(float(lat.stride)) / log(2.0))
			if float(lat.keep) > bound + 1e-9:
				fail_test("решітка %d, зум %.2f: keep %.6f > %.6f" % [side, zoom, lat.keep, bound])
				return


## Дзеркало рангу в GDScript (`WeatherRig.rain_rank`, `rain_hash3`), за яким рахують густоту, мусить
## збігатися з шейдером: сталі хешу, межа рівня й формула рангу записані в обох.
func test_rain_rank_mirror_matches_the_shader_text() -> void:
	var code: String = (load("res://game/battle/shaders/rain.gdshader") as Shader).code
	for piece: String in ["p3 * 0.1031", "p3.zyx + 31.32", "fract((p3.x + p3.y) * p3.z)",
			"i <= 5", "lvl >= 5.0", "pow(8.0, -(lvl + 1.0)) * (1.0 + 7.0 * u)",
			"u * pow(8.0, -5.0)", "rain_rank(wc) < keep"]:
		assert_true(code.contains(piece), "шейдер: " + piece)
	var src: String = (load("res://game/battle/look/weather_rig.gd") as GDScript).source_code
	for piece: String in ["* 0.1031", "Vector3(p3.z, p3.y, p3.x) + Vector3.ONE * 31.32",
			"range(1, 6)", "lvl >= 5", "pow(8.0, -(lvl + 1.0)) * (1.0 + 7.0 * u)",
			"u * pow(8.0, -5.0)"]:
		assert_true(src.contains(piece), "дзеркало: " + piece)


## Решітка вкриває всю коробку кадру й з від'ємними координатами фокуса: кут прилипає до цілої
## клітинки вниз (`floorf`), а не до нуля (`int()`), інакше дальній край коробки лишався б
## без крапель.
func test_rain_lattice_covers_the_box_at_negative_coordinates() -> void:
	var grid := Vector3(60, WeatherRig.RAIN_LAYERS, 60)
	for focus: Vector3 in [Vector3(-3.3, 0, -7.9), Vector3(-0.2, 0, 4.4), Vector3(13.7, 0, -1.1)]:
		for zoom: float in [6.0, 11.9, 12.1, 20.0]:
			var lat: Dictionary = WeatherRig.rain_lattice(focus, zoom, grid)
			var box: AABB = WeatherRig.rain_box(focus, zoom)
			var lo: Vector3 = lat.origin * lat.cell
			var hi: Vector3 = (lat.origin + grid * float(lat.stride)) * lat.cell
			var tag: String = "фокус %s зум %s" % [focus, zoom]
			assert_true(lo.x <= box.position.x + 1e-4 and lo.z <= box.position.z + 1e-4, tag)
			assert_true(hi.x >= box.end.x - 1e-4 and hi.z >= box.end.z - 1e-4, tag)
			assert_true(hi.y >= box.end.y - 1e-4, tag)


## Довжина штриха — розмиття руху у світі: швидкість × витримка. Жодної довжини в пікселях —
## вона з наближенням лишалась би сталою, а швидкість на екрані росла б («палиці»). Зум не міняє
## ні швидкості, ні витримки.
func test_rain_streak_length_is_world_speed_times_exposure() -> void:
	var names: Array[String] = _rain_uniforms()
	for bad: String in ["streak_px", "min_streak_px", "streak_length"]:
		assert_false(bad in names, bad)
	var code: String = (load("res://game/battle/shaders/rain.gdshader") as Shader).code
	assert_true(code.contains("tail = head - vel * exposure"), "штрих — шлях краплі за витримку")
	var rig: WeatherRig = _rig()
	var mat := rig.rain.material_override as ShaderMaterial
	for zoom: float in [6.0, 13.0, 20.0]:
		rig.follow(Vector3(5.0, 0.0, 7.0), zoom)
		assert_almost_eq(float(mat.get_shader_parameter("fall_speed")),
				-rig.rain_velocity().y, 1e-5)
		assert_almost_eq(float(mat.get_shader_parameter("exposure")), WeatherRig.RAIN_EXPOSURE,
				1e-5)


## Вода й дощ — обидва прозорі без запису глибини; без пріоритету порядок залежав би від пана.
func test_rain_draws_over_the_water() -> void:
	var service: Node = (load("res://game/autoload/match_service.gd") as GDScript).new()
	add_child_autofree(service)
	var screen: Node = (load("res://game/battle/battle_screen.tscn") as PackedScene).instantiate()
	add_child_autofree(screen)
	screen.setup(load("res://maps/river.tres") as MapData, 2, 1, service)
	var water: GeometryInstance3D = screen.get_node("%BoardView").get_node("Water")
	var rig: WeatherRig = screen.get_node("WeatherRig")
	assert_gt((rig.rain.material_override as Material).render_priority,
			(water.material_override as Material).render_priority)


## У коробці зонда Mobile бере розсіяне світло з нього, а не з оточення: без цього сила й колір
## розсіяного світла вигляду на дошку не діяли б зовсім.
func test_the_board_probe_gets_the_ambient_light_of_the_look() -> void:
	var service: Node = (load("res://game/autoload/match_service.gd") as GDScript).new()
	add_child_autofree(service)
	var screen: Node = (load("res://game/battle/battle_screen.tscn") as PackedScene).instantiate()
	add_child_autofree(screen)
	screen.setup(load("res://maps/river.tres") as MapData, 2, 1, service)
	var probe: ReflectionProbe = (screen.get_node("%BoardView") as BoardView).reflection_probe()
	var look: BattleLook = BattleLook.for_map_path("res://maps/river.tres")
	assert_eq(probe.ambient_mode, ReflectionProbe.AMBIENT_COLOR)
	assert_eq(probe.ambient_color, look.ambient_color)
	assert_almost_eq(probe.ambient_color_energy, look.ambient_energy, 1e-5)


func test_the_drops_mesh_is_built_once() -> void:
	var a: WeatherRig = _rig()
	var b: WeatherRig = _rig()
	var look: BattleLook = BattleLook.for_map_path("res://maps/river.tres")
	a.apply(look)
	b.apply(look)
	assert_same(a.rain.mesh, b.rain.mesh)
	# Кількість, що не ділиться на решітку: меш будується раз, а не на кожному apply().
	var odd: BattleLook = look.duplicate()
	odd.rain_amount = 5000
	a.apply(odd)
	var mesh: Mesh = a.rain.mesh
	a.apply(odd)
	assert_same(a.rain.mesh, mesh)
	var side: int = WeatherRig.rain_side(5000)
	assert_eq(a.rain_drops(), side * side * WeatherRig.RAIN_LAYERS)


## §3.12: вигляд не тримає жодного числа правил.
func test_a_look_has_no_rule_fields() -> void:
	var banned: Array[String] = ["vision", "range", "ap", "cost", "damage", "penalty", "hp",
			"armour", "armor", "ground", "mud"]
	for prop: Dictionary in BattleLook.new().get_property_list():
		if not (prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		for token: String in String(prop.name).split("_"):
			assert_false(token in banned, "поле %s схоже на правило" % prop.name)


## «Продовжити» бере вигляд з карти збереженої гри, а не типовий.
func test_resume_applies_the_look_of_the_saved_map() -> void:
	var service: Node = (load("res://game/autoload/match_service.gd") as GDScript).new()
	add_child_autofree(service)
	var first: Node = (load("res://game/battle/battle_screen.tscn") as PackedScene).instantiate()
	add_child_autofree(first)
	first.setup(load("res://maps/river.tres") as MapData, 2, 1, service)
	service.map_path = "res://maps/river.tres"
	var screen: Node = (load("res://game/battle/battle_screen.tscn") as PackedScene).instantiate()
	add_child_autofree(screen)
	screen.resume(service)
	var rig: WeatherRig = screen.get_node("WeatherRig")
	var look: BattleLook = BattleLook.for_map_path("res://maps/river.tres")
	assert_true(rig.rain.visible, "типовий вигляд дощу не має")
	assert_almost_eq(rig.applied_globals[&"weather_wetness"], look.wetness, 1e-5)
	assert_eq(rig.environment.ambient_light_color, look.ambient_color)


func test_battle_screen_applies_the_look_of_its_map() -> void:
	var service: Node = (load("res://game/autoload/match_service.gd") as GDScript).new()
	add_child_autofree(service)
	var screen: Node = (load("res://game/battle/battle_screen.tscn") as PackedScene).instantiate()
	add_child_autofree(screen)
	screen.setup(load("res://maps/river.tres") as MapData, 2, 1, service)
	var rig: WeatherRig = screen.get_node("WeatherRig")
	assert_true(rig.rain.visible)
	assert_almost_eq(rig.applied_globals[&"weather_wetness"],
			BattleLook.for_map_path("res://maps/river.tres").wetness, 1e-5)


## Один вітер на вигляд: дощ зносить рівно ним, а сила — з вигляду карти.
func test_rain_drifts_with_the_looks_wind() -> void:
	var rig: WeatherRig = _rig()
	var look := BattleLook.new()
	look.wind = 0.1
	rig.apply(look)
	assert_eq(rig.wind(), WeatherRig.WIND_AXIS * 0.1)
	var v: Vector3 = rig.rain_velocity()
	assert_eq(Vector3(v.x, 0.0, v.z), rig.wind() * WeatherRig.RAIN_FALL)
