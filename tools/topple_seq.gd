extends Node
## Знімає миті повалення (BattleFx.spawn_topple_hit / spawn_topple_land) справжнім екраном бою в
## реальному часі: на клітинці стоїть брусок-замінник опори чи паркану, після удару він падає
## як стрижень, що обертається навколо основи, і ховається тієї миті, коли ляже. Спершу всі миті
## програються раз без запису (розігрів шейдерів), потім кожен випадок — із записом. Кадри
## лежать у пам'яті й пишуться в кінці (збереження блокує). Не входить у гру. Запуск (вікно):
##   $GODOT --path . --position 6000,0 res://tools/topple_seq.tscn -- <out_dir> <map> <zoom> <кадрів/с> <poles|fences|all|ім'я випадку> [x,y|-] [unit]
## unit — перший юніт дошки стає на сусідню клітинку, куди падає опора: чи не ховає його пил.
## slow — гра в 10 разів повільніша (Engine.time_scale), кадри/с і секунди — у часі гри: спалах дуги
## (30–60 мс) інакше падає між знятими кадрами.

const WINDOW: Vector2i = Vector2i(1600, 900)
const SETTLE_FRAMES: int = 120
const CROP: Vector2i = Vector2i(640, 640)
## Скільки знімати після падіння: пил осідає за 2–3 с.
const AFTER_SEC: float = 3.4
const POLE_M: float = 10.0
const FENCE_M: float = 1.8
## Випадки: ім'я, матеріал, опора (інакше паркан), дріт під напругою.
const CASES: Array = [
	["pole_concrete_live", BattleFx.Debris.CONCRETE, true, true],
	["pole_wood_live", BattleFx.Debris.WOOD, true, true],
	["fence_concrete", BattleFx.Debris.CONCRETE, false, false],
	["fence_wood", BattleFx.Debris.WOOD, false, false],
	["fence_sheet", BattleFx.Debris.SHEET, false, false],
	["fence_mesh", BattleFx.Debris.MESH, false, false],
]


func _ready() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	if a.size() < 5:
		push_error("topple_seq: <out_dir> <map> <zoom> <fps> <poles|fences|all> [x,y]")
		get_tree().quit(1)
		return
	get_window().size = WINDOW
	var screen: BattleScreen = (load("res://game/battle/battle_screen.tscn") as PackedScene).instantiate()
	add_child(screen)
	var map := load("res://maps/%s.tres" % a[1]) as MapData
	screen.setup(map, 2, 1)
	# Те, що екран бою ставить сам із вигляду мапи: мокра земля бризкає грязю, а не куриться.
	BattleFx.wetness = BattleLook.for_map_path("res://maps/%s.tres" % a[1]).wetness
	var cell := Vector2i(map.width / 2, map.height / 2)
	if a.size() > 5 and a[5] != "-":
		var xy: PackedStringArray = a[5].split(",")
		cell = Vector2i(int(xy[0]), int(xy[1]))
	var base: Vector3 = IsoCameraRig.cell_to_world(cell) + Vector3(-0.3, 0, 0.2)
	base.y = TerrainHeight.ground_y(base.x, base.z)
	var rig: IsoCameraRig = screen.get_node("%CameraRig")
	for f in SETTLE_FRAMES:
		await get_tree().process_frame
	rig.center_on(cell)
	rig.zoom_by(float(a[2]) / rig.zoom_level)
	for f in SETTLE_FRAMES:
		await get_tree().process_frame
	var units: Node = screen.get("_units")
	var slow: bool = "slow" in a
	if a.size() > 6 and a[6] == "unit":
		for u: Node in units.get_children():
			if u is UnitView and (u as UnitView).visible:
				var spot: Vector3 = base + Vector3(0.93, 0, 0.37).normalized() * 0.75 + Vector3(0.0, 0, 0.45)
				spot.y = TerrainHeight.ground_y(spot.x, spot.z)
				(u as UnitView).position = spot
				break
	var pick: Array = []
	for c: Array in CASES:
		if a[4] == "all" or a[4] == c[0] or (a[4] in ["poles", "fences"] and (a[4] == "poles") == bool(c[2])):
			pick.append(c)
	# Розігрів: кожна мить раз, нікуди не записана.
	for c: Array in pick:
		BattleFx.spawn_topple_hit(units, base, base + Vector3(0, 1, 0), c[1], c[3])
		BattleFx.spawn_topple_land(units, base, base + Vector3(1, 0, 0), c[1], c[3])
	for f in 240:
		await get_tree().process_frame
	BattleFx.clear_all(get_tree())
	var out: Dictionary = {}
	if slow:
		Engine.time_scale = 0.1
	for c: Array in pick:
		out[c[0]] = await _play(screen, units, base, c, float(a[3]))
	for k: String in out:
		var dir: String = "%s/%s" % [a[0], k]
		DirAccess.make_dir_recursive_absolute(dir)
		var frames: Array = out[k]
		for i in frames.size():
			(frames[i] as Image).save_jpg("%s/f_%04d.jpg" % [dir, i], 0.92)
	get_tree().quit()


## Падіння стрижня, що обертається навколо основи: θ'' = 3g/(2L)·sin θ від нахилу 3°, до
## лежачого; паркан — та сама фізика для висоти полотна. Повертає час вільного падіння, с.
static func fall_sec(length_m: float) -> float:
	var th: float = deg_to_rad(3.0)
	var w: float = 0.0
	var t: float = 0.0
	while th < PI * 0.5:
		w += 1.5 * 9.8 / length_m * sin(th) * 0.001
		th += w * 0.001
		t += 0.001
	return t


func _play(screen: Node, units: Node, base: Vector3, c: Array, fps: float) -> Array[Image]:
	var pole: bool = c[2]
	var h_m: float = POLE_M if pole else FENCE_M
	var dir := Vector3(0.93, 0.0, 0.37).normalized()
	var top: Vector3 = base + Vector3(0, h_m / 8.0, 0)
	var land: Vector3 = base + dir * h_m / 8.0
	land.y = TerrainHeight.ground_y(land.x, land.z)
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	# Опора 0,19 м у перерізі; паркан — полотно 2,5 м завширшки, 4 см завтовшки.
	bm.size = Vector3(0.19, h_m, 0.19) / 8.0 if pole else Vector3(0.04, h_m, 2.5) / 8.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = {BattleFx.Debris.CONCRETE: Color(0.6, 0.59, 0.56), BattleFx.Debris.WOOD: Color(0.33, 0.26, 0.19), BattleFx.Debris.SHEET: Color(0.25, 0.33, 0.24), BattleFx.Debris.MESH: Color(0.3, 0.3, 0.3)}[c[1]]
	bm.material = mat
	box.mesh = bm
	var pivot := Node3D.new()
	pivot.position = base
	# Вісь обертання — поперек напряму падіння.
	var axis: Vector3 = Vector3.UP.cross(dir).normalized()
	pivot.basis = Basis(dir, Vector3.UP, dir.cross(Vector3.UP))
	box.position = Vector3(0, h_m / 16.0, 0)
	pivot.add_child(box)
	units.add_child(pivot)
	# Танк штовхає, тож падає швидше за вільний стрижень: та сама крива кута, стиснута до часу,
	# з яким працює PropLayer (опора 1,5 с, паркан 0,5 с).
	var t_fall: float = 1.5 if pole else 0.5
	var squeeze: float = fall_sec(h_m) / t_fall
	var cam: Camera3D = get_viewport().get_camera_3d()
	var focus: Vector3 = (base + land) * 0.5
	var frames: Array[Image] = []
	# Паркан: півпрольоту полотна 1,25 м уздовж огорожі (поперек напряму падіння).
	var span: Vector3 = Vector3.ZERO if pole else axis * 1.25 / 8.0
	BattleFx.spawn_topple_hit(units, base + Vector3(0, 0.02, 0), top, c[1], c[3], pole, span)
	var t0: int = Time.get_ticks_usec()
	var next: float = 0.0
	var landed: bool = false
	var total: float = t_fall + AFTER_SEC
	while true:
		await RenderingServer.frame_post_draw
		var el: float = float(Time.get_ticks_usec() - t0) / 1e6 * Engine.time_scale
		if not landed:
			# Кут стрижня на el с: інтегруємо ту саму криву, що й fall_sec.
			var th: float = _angle_at(h_m, el * squeeze)
			pivot.basis = Basis(axis, -th) * Basis(dir, Vector3.UP, dir.cross(Vector3.UP))
			if el >= t_fall:
				landed = true
				pivot.visible = false
				BattleFx.spawn_topple_land(units, base, land, c[1], c[3], pole)
		if el >= next:
			var img: Image = get_viewport().get_texture().get_image()
			var k: float = float(img.get_width()) / get_viewport().get_visible_rect().size.x
			var p: Vector2 = cam.unproject_position(focus)
			var pos := Vector2i(int(p.x * k) - CROP.x / 2, int(p.y * k) - CROP.y / 2)
			pos = pos.clamp(Vector2i.ZERO, img.get_size() - CROP)
			frames.append(img.get_region(Rect2i(pos, CROP)))
			next += 1.0 / fps
		if el >= total:
			break
	print("TOPPLE %s fall=%.2fs frames=%d" % [c[0], t_fall, frames.size()])
	pivot.queue_free()
	return frames


static func _angle_at(length_m: float, sec: float) -> float:
	var th: float = deg_to_rad(3.0)
	var w: float = 0.0
	var t: float = 0.0
	while t < sec and th < PI * 0.5:
		w += 1.5 * 9.8 / length_m * sin(th) * 0.002
		th += w * 0.002
		t += 0.002
	return minf(th, PI * 0.5)
