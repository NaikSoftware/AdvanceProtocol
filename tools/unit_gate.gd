extends Node
## Кадри для воріт контрасту юніта з ґрунтом (docs/art/unit-models-research.md §5); рахує їх
## tools/unit_gate.py. Не входить у гру.
##   $GODOT --path . res://tools/unit_gate.tscn -- <out_dir> <map> <type_id> [set_id] [tints]
## tints — JSON-список множників альбедо [[r, g, b], ...] (перший — як є): одна збірка моделі
## перевіряє кілька тонів фарби, бо маска й ґрунт від тону не залежать.
## Тіні хмар вимкнено: вони пливуть у реальному часі, і той самий юніт між прогонами давав різницю
## до 5 ΔE; затінення хмарою скрипт аналізу враховує окремо, множником на ґрунт.
## Місця: найближча до центру клітинка поля з полем навколо — лука й рілля; клітинки поля впритул
## до лісу з кожного з чотирьох боків і через одну клітинку від нього (на сонячній мапі одна з них
## у тіні крон — її знаходить аналіз). Пропси сховано.
## На місце — кадри: _B без моделі, _C модель суцільним пурпуровим (маска), _S модель без власної
## тіні (що в _A темніше — затінене), _A<n> модель з n-м тоном. Найдальший зум, модель носом на північ;
## на луці ще _Z<n> — той самий тон на найближчому зумі, для ока.

const WINDOW: Vector2i = Vector2i(1600, 900)
const SETTLE: int = 60


func _ready() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	var out: String = a[0]
	var map := load("res://maps/%s.tres" % a[1]) as MapData
	var type_id: int = int(a[2])
	var set_id: int = int(a[3]) if a.size() > 3 else 0
	var tints: Array = JSON.parse_string(a[4]) if a.size() > 4 else [[1, 1, 1]]
	DirAccess.make_dir_recursive_absolute(out)
	get_window().size = WINDOW
	var screen: BattleScreen = (load("res://game/battle/battle_screen.tscn") as PackedScene).instantiate()
	add_child(screen)
	screen.setup(map, 2, 1)
	RenderingServer.global_shader_parameter_set(&"cloud_shadow_strength", 0.0)
	# Пропси (опори, стоги, паркани) не ґрунт: опора через модель чи стіг у кільці зсувають медіану.
	for n: Node in screen.find_children("Props", "", true, false):
		(n as Node3D).visible = false
	var rig: IsoCameraRig = screen.get_node("%CameraRig")
	for f in SETTLE:
		await get_tree().process_frame
	var places: Dictionary = _places(map)
	for kind: String in places:
		var cell: Vector2i = places[kind]
		var u: Node3D = UnitSilhouettes.build_merged(type_id, -1, set_id)
		add_child(u)
		u.position = IsoCameraRig.cell_to_world(cell)
		u.position.y = _ground(u.position)
		# center_on скидає ціль зуму, тож зум — після нього, щоразу
		rig.center_on(cell)
		rig.zoom_by(IsoCameraRig.MAX_ZOOM / rig.zoom_level)
		var hull := u.get_node("Hull") as MeshInstance3D
		var paint := hull.material_override as ShaderMaterial
		var shots: Array = []
		for i in tints.size():
			var t: Array = tints[i]
			paint.set_shader_parameter("albedo_color", Color(t[0], t[1], t[2]))
			shots.append(["A%d" % i, await _frame(SETTLE if i == 0 else 4)])
		if kind == "meadow":
			# для ока: той самий юніт на найближчому зумі, кожним тоном
			rig.zoom_by(IsoCameraRig.MIN_ZOOM / rig.zoom_level)
			for i in tints.size():
				var t: Array = tints[i]
				paint.set_shader_parameter("albedo_color", Color(t[0], t[1], t[2]))
				shots.append(["Z%d" % i, await _frame(SETTLE if i == 0 else 4)])
			rig.zoom_by(IsoCameraRig.MAX_ZOOM / rig.zoom_level)
			await _frame(SETTLE)
		paint.set_shader_parameter("albedo_color", Color(1, 1, 1))
		hull.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		shots.append(["S", await _frame(4)])
		var mask := StandardMaterial3D.new()
		mask.albedo_color = Color(1, 0, 1)
		mask.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		hull.material_override = mask
		shots.append(["C", await _frame(4)])
		u.visible = false
		shots.append(["B", await _frame(4)])
		for s: Array in shots:
			(s[1] as Image).save_png("%s/%s_t%d_%s_%s.png" % [out, a[1], type_id, kind, s[0]])
		u.queue_free()
		print("GATE %s %s at %s zoom %.2f" % [a[1], kind, cell, rig.zoom_level])
	get_tree().quit()


func _frame(settle: int) -> Image:
	for f in settle:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


func _places(map: MapData) -> Dictionary:
	var out: Dictionary = {}
	var best: Dictionary = {}
	var c := Vector2i(map.width / 2, map.height / 2)
	var sides: Dictionary = {"forest_e": Vector2i(1, 0), "forest_w": Vector2i(-1, 0), "forest_s": Vector2i(0, 1), "forest_n": Vector2i(0, -1)}
	for y in range(4, map.height - 4):
		for x in range(4, map.width - 4):
			var p := Vector2i(x, y)
			if _kind(map, p) != Terrain.Kind.FIELD:
				continue
			var found: Array[String] = []
			var open: bool = true
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if _kind(map, p + Vector2i(dx, dy)) != Terrain.Kind.FIELD:
						open = false
			if open:
				found.append("plough" if map.surface_at(p) == MapData.FieldSurface.PLOUGHED else "meadow")
			for s: String in sides:
				var d: Vector2i = sides[s]
				# поле з цього боку, ліс у два ряди з протилежного: модель на відкритому полі під узліссям
				if _kind(map, p + d) == Terrain.Kind.FOREST and _kind(map, p + 2 * d) == Terrain.Kind.FOREST \
						and _kind(map, p - d) == Terrain.Kind.FIELD:
					found.append(s)
				# клітинка поля між: крони над крайньою клітинкою ховають модель, тінь сягає далі
				if _kind(map, p + d) == Terrain.Kind.FIELD and _kind(map, p + 2 * d) == Terrain.Kind.FOREST \
						and _kind(map, p + 3 * d) == Terrain.Kind.FOREST:
					found.append(s.replace("forest", "gap"))
			for k: String in found:
				var dd: int = (p - c).length_squared()
				if not best.has(k) or dd < best[k]:
					best[k] = dd
					out[k] = p
	return out


func _kind(map: MapData, p: Vector2i) -> int:
	return map.tiles[p.y * map.width + p.x]


## Найвища точка рельєфу під тайлом, як у tools/unit_shot.gd: модель не тоне в схилі.
func _ground(p: Vector3) -> float:
	var th: TerrainHeight = TerrainHeight.active
	if th == null:
		return 0.0
	var y: float = th.at(p.x, p.z)
	for d: Vector2 in [Vector2(-0.25, -0.45), Vector2(0.25, -0.45), Vector2(-0.25, 0.45), Vector2(0.25, 0.45)]:
		y = maxf(y, th.at(p.x + d.x, p.z + d.y))
	return y
