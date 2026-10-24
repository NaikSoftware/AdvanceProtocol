class_name WaterSurface
extends MeshInstance3D
## Річка: одна площина над усією землею, шейдер лишає воду на
## WATER, BRIDGE і BRIDGE_DESTROYED — річка тече й під мостом;
## сам міст — окремий меш над водою (BoardView).
##
## §3.5: вода нічого не знає про туман; відбиття бере зонд BoardView, який не
## бачить шару юнітів.

## Рівень води — на 0.4 м нижче верху берега (TerrainHeight): вода стоїть там, де земля
## нижча за цей рівень, берег видно над нею.
const WATER_Y: float = TerrainHeight.WATER_LEVEL

const _SHADER: Shader = preload("res://game/battle/shaders/water.gdshader")
## Дві карти нормалей брижі (tools/water_normals.py), стиснені з міпмапами.
const _WAVE_A: Texture2D = preload("res://assets/water/water_normal_a.png")
const _WAVE_B: Texture2D = preload("res://assets/water/water_normal_b.png")



## height — карта висот, за якою шейдер лишає воду там, де земля нижча за рівень (null — за видом клітинки).
## ring > 0: board — світ разом із кільцем (як у GroundSurface.build): річка тече крізь кільце.
func build(board: Board, margin: int, kind_map: ImageTexture, height: TerrainHeight = null, ring: int = 0) -> void:
	var has_water := false
	# Пари сусідніх клітинок води вздовж X і вздовж Y: річка тече вздовж довшої осі.
	var along_x := 0
	var along_y := 0
	var lo := Vector2i(board.width, board.height)
	var hi := Vector2i(-1, -1)
	for y in board.height:
		for x in board.width:
			if _is_water(board, Vector2i(x, y)):
				has_water = true
				lo = Vector2i(mini(lo.x, x), mini(lo.y, y))
				hi = Vector2i(maxi(hi.x, x), maxi(hi.y, y))
				along_x += 1 if _is_water(board, Vector2i(x + 1, y)) else 0
				along_y += 1 if _is_water(board, Vector2i(x, y + 1)) else 0
	visible = has_water
	if not has_water:
		return

	# Площина — лише над клітинками води з запасом у клітинку (берег, виступи русла), у межах
	# світу: кожен її фрагмент рахує висоту й серпанок, а суша під рештою кільця й дошки — ні.
	var pad := Vector2.ONE * (0.5 + margin)
	var a: Vector2 = Vector2(maxi(lo.x - 1, 0), maxi(lo.y - 1, 0)) - pad
	var b: Vector2 = Vector2(mini(hi.x + 1, board.width - 1), mini(hi.y + 1, board.height - 1)) + pad
	var plane := PlaneMesh.new()
	plane.size = b - a
	mesh = plane
	position = Vector3((a.x + b.x) * 0.5 - ring, WATER_Y, (a.y + b.y) * 0.5 - ring)
	layers = 1
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var mat := ShaderMaterial.new()
	mat.shader = _SHADER
	mat.set_shader_parameter("kind_map", kind_map)
	mat.set_shader_parameter("map_origin", Vector2(-margin - ring, -margin - ring))
	if ring > 0:
		Surroundings.apply(mat, Vector2i(board.width - 2 * ring, board.height - 2 * ring))
	mat.set_shader_parameter("water_kind", Terrain.Kind.WATER)
	mat.set_shader_parameter("bridge_kind", Terrain.Kind.BRIDGE)
	mat.set_shader_parameter("broken_bridge_kind", Terrain.Kind.BRIDGE_DESTROYED)
	mat.set_shader_parameter("wave_a", _WAVE_A)
	mat.set_shader_parameter("wave_b", _WAVE_B)
	# shortcut: одна вісь течії на карту, бо річки на картах прямі; для звивистої
	# річки — напрямок із карти видів на фрагмент.
	mat.set_shader_parameter("use_height", height != null)
	if height != null:
		mat.set_shader_parameter("height_map", height.texture())
		mat.set_shader_parameter("height_samples", float(height.samples))
		mat.set_shader_parameter("height_origin", Vector2(-0.5 - margin - ring, -0.5 - margin - ring))
		mat.set_shader_parameter("water_level", WATER_Y)
	mat.set_shader_parameter("flow_dir", Vector2(1, 0) if along_x >= along_y else Vector2(0, 1))
	material_override = mat


static func _is_water(board: Board, cell: Vector2i) -> bool:
	if cell.x >= board.width or cell.y >= board.height:
		return false
	var kind: int = board.kind_at(cell)
	return kind == Terrain.Kind.WATER or kind == Terrain.Kind.BRIDGE or kind == Terrain.Kind.BRIDGE_DESTROYED
