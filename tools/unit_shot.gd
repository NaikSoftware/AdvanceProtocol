extends Node
## Знімає модель юніта на справжньому екрані бою: обидва власники й коробка-заступник поруч для
## масштабу, на найближчому й найдальшому зумі, і два кадри з інтервалом 0,5 с, поки один танк
## їде на тайл уперед (гусениці й колеса мають крутитися). Кадри тримаються в пам'яті й пишуться
## в кінці (save_png блокує ~1 с). Не входить у гру.
## Запуск (вікно, не --headless):
##   $GODOT --path . res://tools/unit_shot.tscn -- <out_dir> <map> <type_id> [tag] [owner_a,owner_b]
## owner_a,owner_b — індекси PLAYER_COLORS для двох моделей (типово 0,1), щоб зняти й третій колір.

const WINDOW: Vector2i = Vector2i(1600, 900)
const SETTLE_FRAMES: int = 60
## Скільки триває проїзд на один тайл і коли знімати два кадри руху.
const MOVE_SEC: float = 1.2
const MOVE_SHOTS: Array[float] = [0.35, 0.85]


func _ready() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	if a.size() < 3:
		push_error("unit_shot: <out_dir> <map> <type_id> [tag]")
		get_tree().quit(1)
		return
	var out: String = a[0]
	var tag: String = a[3] if a.size() > 3 else a[1]
	var type_id: int = int(a[2])
	DirAccess.make_dir_recursive_absolute(out)
	get_window().size = WINDOW
	var screen: BattleScreen = (load("res://game/battle/battle_screen.tscn") as PackedScene).instantiate()
	add_child(screen)
	var map := load("res://maps/%s.tres" % a[1]) as MapData
	screen.setup(map, 2, 1)
	var cell := _field_near_centre(map)
	var owners: PackedStringArray = (a[4] if a.size() > 4 else "0,1").split(",")
	var c0: Color = UnitView.PLAYER_COLORS[int(owners[0])]
	var c1: Color = UnitView.PLAYER_COLORS[int(owners[1])]
	# Власник 1 дивиться на північ, власник 2 — на південний схід, коробка-заступник — ліворуч.
	_place(UnitSilhouettes.build_merged(type_id, c0), cell, 0)
	_place(UnitSilhouettes.build_merged(type_id, c1), cell + Vector2i(1, 0), 3)
	_place(UnitSilhouettes.build(type_id, c0), cell + Vector2i(-1, 0), 0)
	var mover: Node3D = UnitSilhouettes.build_merged(type_id, c1)
	_place(mover, cell + Vector2i(0, 2), 0)
	print("UNIT placed at %s" % cell)
	var rig: IsoCameraRig = screen.get_node("%CameraRig")
	for f in SETTLE_FRAMES:
		await get_tree().process_frame
	rig.center_on(cell + Vector2i(0, 1))
	var shots: Array = []
	for z: float in [IsoCameraRig.MIN_ZOOM, IsoCameraRig.MAX_ZOOM]:
		rig.zoom_by(z / rig.zoom_level)
		for f in SETTLE_FRAMES:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		shots.append(["%s/%s_z%d.png" % [out, tag, int(z)], get_viewport().get_texture().get_image()])
	rig.zoom_by(IsoCameraRig.MIN_ZOOM / rig.zoom_level)
	for f in SETTLE_FRAMES:
		await get_tree().process_frame
	# Проїзд: вузол рухається на тайл до -Z, `travel` — пройдений шлях, як у UnitView.
	var hull := mover.get_node("Hull") as GeometryInstance3D
	var start: Vector3 = mover.position
	var t0: int = Time.get_ticks_usec()
	var next: int = 0
	while true:
		await get_tree().process_frame
		var el: float = float(Time.get_ticks_usec() - t0) / 1e6
		var k: float = clampf(el / MOVE_SEC, 0.0, 1.0)
		mover.position = start + Vector3(0.0, 0.0, -k)
		mover.position.y = _ground(mover.position)
		hull.set_instance_shader_parameter("travel", k)
		if next < MOVE_SHOTS.size() and el >= MOVE_SHOTS[next]:
			await RenderingServer.frame_post_draw
			shots.append(["%s/%s_move%d.png" % [out, tag, next], get_viewport().get_texture().get_image()])
			print("UNIT move shot %d at %.2f s, travel %.3f" % [next, el, k])
			next += 1
		if k >= 1.0:
			break
	for s: Array in shots:
		(s[1] as Image).save_png(s[0])
	print("UNIT %s type %d cell %s: %d frames" % [a[1], type_id, cell, shots.size()])
	get_tree().quit()


func _place(n: Node3D, cell: Vector2i, facing: int) -> void:
	add_child(n)
	n.position = IsoCameraRig.cell_to_world(cell)
	n.rotation.y = -float(facing) * PI / 4.0
	n.position.y = _ground(n.position)


## Найвища точка рельєфу під кутами тайла навколо центру: модель не тоне в схилі.
func _ground(p: Vector3) -> float:
	var th: TerrainHeight = TerrainHeight.active
	if th == null:
		return 0.0
	var y: float = th.at(p.x, p.z)
	for d: Vector2 in [Vector2(-0.25, -0.45), Vector2(0.25, -0.45), Vector2(-0.25, 0.45), Vector2(0.25, 0.45)]:
		y = maxf(y, th.at(p.x + d.x, p.z + d.y))
	return y


## Найближча до центру клітинка поля, у якої поле й три сусіди праворуч, ліворуч і нижче.
func _field_near_centre(map: MapData) -> Vector2i:
	var c := Vector2i(map.width / 2, map.height / 2)
	var best := c
	var best_d: int = 1 << 30
	for y in range(1, map.height - 3):
		for x in range(1, map.width - 1):
			var ok: bool = true
			for d: Vector2i in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 1)]:
				if map.tiles[(y + d.y) * map.width + x + d.x] != Terrain.Kind.FIELD:
					ok = false
			var dd: int = (x - c.x) * (x - c.x) + (y - c.y) * (y - c.y)
			if ok and dd < best_d:
				best_d = dd
				best = Vector2i(x, y)
	return best
