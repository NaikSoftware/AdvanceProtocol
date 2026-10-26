extends Node
## Контраст дах/стіна хат у справжньому бою: кожна хата дошки на зумі 8, точка посеред скату до камери
## й точка рівної стіни під ним (між вікнами) проєктуються камерою гри; медіана гамма-яскравості sRGB
## (0.2126 R' + 0.7152 G' + 0.0722 B') ділянки 7 x 7 px. Друкує ROOF <карта> <модель> <клітинка> дах= стіна= дах/стіна=,
## кадри з позначеними ділянками — в <out_dir>. Не входить у гру.
## Запуск (потрібне вікно; вікно — за межами екрана):
##   $GODOT --path . --position 6000,0 res://tools/roof_contrast.tscn -- <out_dir> river crossroads

const WINDOW: Vector2i = Vector2i(1600, 900)
const SETTLE_FRAMES: int = 60
const ZOOM: float = 8.0
const HALF: int = 3
## Точки моделей у метрах збирача Blender (x, y, z): дах посеред скату з боку -Y і стіна під ним між вікнами;
## бік +Y — дзеркально по y зі своїм x стіни. Дах — вздовж осі X, скати до ±Y.
const POINTS: Dictionary = {
	&"house_h5": {"roof": Vector3(0.0, -1.4, 4.75), "wall_s": Vector3(0.85, -2.62, 1.6), "wall_n": Vector3(0.3, 2.62, 1.6)},
	&"house_h6": {"roof": Vector3(0.0, -1.6, 7.75), "wall_s": Vector3(-0.9, -3.02, 3.1), "wall_n": Vector3(0.0, 3.02, 3.1)},
	&"house_h7": {"roof": Vector3(0.0, -1.62, 4.1), "wall_s": Vector3(-1.1, -2.82, 1.6), "wall_n": Vector3(0.0, 2.82, 1.6)},
	&"house_h8": {"roof": Vector3(0.0, -1.37, 4.15), "wall_s": Vector3(-2.7, -2.42, 1.6), "wall_n": Vector3(0.0, 2.42, 1.6)},
}


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var out: String = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	get_window().size = WINDOW
	var shots: Array = []
	for i in range(1, args.size()):
		var map: String = args[i]
		var screen: BattleScreen = (load("res://game/battle/battle_screen.tscn") as PackedScene).instantiate()
		add_child(screen)
		screen.setup(load("res://maps/%s.tres" % map) as MapData, 2, 1)
		var props: PropLayer = (screen.get_node("%BoardView") as BoardView).props()
		var rig: IsoCameraRig = screen.get_node("%CameraRig")
		for model: StringName in POINTS:
			var mmi: MultiMeshInstance3D = props.get_node_or_null(String(model)) as MultiMeshInstance3D
			if mmi == null:
				continue
			for k in mmi.multimesh.instance_count:
				var xf: Transform3D = mmi.global_transform * mmi.multimesh.get_instance_transform(k)
				var cell := Vector2i(floori(xf.origin.x), floori(xf.origin.z))
				rig.center_on(cell)
				rig.zoom_by(ZOOM / rig.zoom_level)
				for f in SETTLE_FRAMES:
					await get_tree().process_frame
				await RenderingServer.frame_post_draw
				var img: Image = get_viewport().get_texture().get_image()
				var cam: Camera3D = get_viewport().get_camera_3d()
				var p: Dictionary = POINTS[model]
				# скат до камери: той, чия зовнішня нормаль дивиться на камеру
				var best: Array = []
				for side in [-1.0, 1.0]:
					var r0: Vector3 = p["roof"]
					var r := Vector3(r0.x, absf(r0.y) * side, r0.z)
					var w: Vector3 = p["wall_s"] if side < 0 else p["wall_n"]
					var rp: Vector3 = xf * _local(r)
					var nrm: Vector3 = (xf.basis * Vector3(0, 1, -side)).normalized()          # бік -Y збирача — +Z у Godot
					var facing: float = nrm.dot((cam.global_position - rp).normalized())
					if best.is_empty() or facing > best[0]:
						best = [facing, rp, xf * _local(w)]
				# unproject_position дає точки в базовій роздільності вікна (розтяг), кадр — у справжній
				var sc := Vector2(img.get_width(), img.get_height()) / get_viewport().get_visible_rect().size
				var rs: Vector2 = cam.unproject_position(best[1]) * sc
				var ws: Vector2 = cam.unproject_position(best[2]) * sc
				var lr: float = _luma(img, rs)
				var lw: float = _luma(img, ws)
				print("ROOF %s %s %s roof=%.3f wall=%.3f ratio=%.2f" % [map, model, cell, lr, lw, lr / maxf(lw, 1e-4)])
				_mark(img, rs, Color(1, 0, 0))
				_mark(img, ws, Color(0, 1, 1))
				shots.append(["%s_%s_%d_%d" % [map, model, cell.x, cell.y], img])
		screen.free()
		await get_tree().process_frame
	for s: Array in shots:
		(s[1] as Image).save_png("%s/%s.png" % [out, s[0]])
	get_tree().quit()


## Метри збирача (x, y, z-вгору) → локальні координати GLB у тайлах: Godot Y вгору, -Z — колишня +Y.
func _local(v: Vector3) -> Vector3:
	return Vector3(v.x, v.z, -v.y) / 8.0


func _luma(img: Image, at: Vector2) -> float:
	var vals: Array[float] = []
	for dy in range(-HALF, HALF + 1):
		for dx in range(-HALF, HALF + 1):
			var x: int = clampi(int(at.x) + dx, 0, img.get_width() - 1)
			var y: int = clampi(int(at.y) + dy, 0, img.get_height() - 1)
			var c: Color = img.get_pixel(x, y)
			vals.append(0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b)
	vals.sort()
	return vals[vals.size() / 2]


func _mark(img: Image, at: Vector2, col: Color) -> void:
	for d in range(-HALF - 1, HALF + 2):
		for e in [-HALF - 1, HALF + 1]:
			for q in [Vector2i(int(at.x) + d, int(at.y) + e), Vector2i(int(at.x) + e, int(at.y) + d)]:
				if q.x >= 0 and q.y >= 0 and q.x < img.get_width() and q.y < img.get_height():
					img.set_pixelv(q, col)
