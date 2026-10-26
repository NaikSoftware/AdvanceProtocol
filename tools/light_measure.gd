extends Node
## Кадри для виміру світла карти в справжньому бою: кожен вигляд — двічі, як є (<name>.png) і без
## справжньої тіні сонця від будівель (<name>_off.png; контактні плями лишаються), щоб тінь на
## землі мірялась проти тієї самої ділянки без неї. Камера й геометрія не залежать від світла, тож ті самі
## пікселі до й після зміни вигляду — одні й ті самі місця (tools/light_measure.py).
## Запуск (потрібне вікно; вікно — за межами екрана):
##   $GODOT --path . --position 6000,0 res://tools/light_measure.tscn -- <out_dir> <map> <x,y,zoom> …
## Друкує LIGHT_FRAME <name> lstar=<середня L* кадру>. Не входить у гру.

const WINDOW: Vector2i = Vector2i(1600, 900)
const SETTLE_FRAMES: int = 60


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var out: String = args[0]
	var map: String = args[1]
	DirAccess.make_dir_recursive_absolute(out)
	get_window().size = WINDOW
	var screen: BattleScreen = (load("res://game/battle/battle_screen.tscn") as PackedScene).instantiate()
	add_child(screen)
	screen.setup(load("res://maps/%s.tres" % map) as MapData, 2, 1)
	var props: PropLayer = (screen.get_node("%BoardView") as BoardView).props()
	var rig: IsoCameraRig = screen.get_node("%CameraRig")
	var shots: Array = []
	for suffix in ["", "_off"]:
		if suffix == "_off":
			for mmi: MultiMeshInstance3D in props.find_children("*", "MultiMeshInstance3D", false, false):
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for i in range(2, args.size()):
			var v: PackedStringArray = args[i].split(",")
			rig.center_on(Vector2i(int(v[0]), int(v[1])))
			rig.zoom_by(float(v[2]) / rig.zoom_level)
			for f in SETTLE_FRAMES:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var img: Image = get_viewport().get_texture().get_image()
			var name := "%s_%s_%s_z%s%s" % [map, v[0], v[1], v[2], suffix]
			shots.append([name, img])
			print("LIGHT_FRAME %s lstar=%.2f" % [name, _mean_l(img)])
	for s: Array in shots:
		(s[1] as Image).save_png("%s/%s.png" % [out, s[0]])
	get_tree().quit()


func _mean_l(img: Image) -> float:
	var sum: float = 0.0
	var n: int = 0
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			var c: Color = img.get_pixel(x, y)
			var lin: float = 0.2126729 * _lin(c.r) + 0.7151522 * _lin(c.g) + 0.0721750 * _lin(c.b)
			sum += 116.0 * (pow(lin, 1.0 / 3.0) if lin > 0.008856 else 7.787 * lin + 16.0 / 116.0) - 16.0
			n += 1
	return sum / n


func _lin(v: float) -> float:
	return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)
