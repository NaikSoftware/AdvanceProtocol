class_name WaterSurface
extends MeshInstance3D
## Річка (Phase 5a, Task 6): одна площина над усією землею, шейдер лишає воду на
## WATER, BRIDGE і BRIDGE_DESTROYED — річка тече й під мостом (рішення власника);
## сам міст — окремий меш над водою (BoardView, згодом Task 8).
##
## §3.5: вода нічого не знає про туман; відбиття бере зонд BoardView, який не
## бачить шару юнітів.

## Над землею (y = 0) і під маркерами мін (MineLayer.MARKER_Y = 0.06).
const WATER_Y: float = 0.02

const _SHADER: Shader = preload("res://game/battle/shaders/water.gdshader")

var _wave_normal: NoiseTexture2D


func build(board: Board, margin: int, kind_map: ImageTexture) -> void:
	var has_water := false
	# Пари сусідніх клітинок води вздовж X і вздовж Y: річка тече вздовж довшої осі.
	var along_x := 0
	var along_y := 0
	for y in board.height:
		for x in board.width:
			if _is_water(board, Vector2i(x, y)):
				has_water = true
				along_x += 1 if _is_water(board, Vector2i(x + 1, y)) else 0
				along_y += 1 if _is_water(board, Vector2i(x, y + 1)) else 0
	visible = has_water
	if not has_water:
		return

	var plane := PlaneMesh.new()
	plane.size = Vector2(board.width + 2 * margin, board.height + 2 * margin)
	mesh = plane
	position = Vector3((board.width - 1) * 0.5, WATER_Y, (board.height - 1) * 0.5)
	layers = 1
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	if _wave_normal == null:
		var noise := FastNoiseLite.new()
		noise.frequency = 0.02
		noise.fractal_octaves = 3
		_wave_normal = NoiseTexture2D.new()
		_wave_normal.width = 256
		_wave_normal.height = 256
		_wave_normal.seamless = true
		_wave_normal.as_normal_map = true
		_wave_normal.bump_strength = 4.0
		_wave_normal.generate_mipmaps = true
		_wave_normal.noise = noise

	var mat := ShaderMaterial.new()
	mat.shader = _SHADER
	mat.set_shader_parameter("kind_map", kind_map)
	mat.set_shader_parameter("map_origin", Vector2(-margin, -margin))
	mat.set_shader_parameter("water_kind", Terrain.Kind.WATER)
	mat.set_shader_parameter("bridge_kind", Terrain.Kind.BRIDGE)
	mat.set_shader_parameter("broken_bridge_kind", Terrain.Kind.BRIDGE_DESTROYED)
	mat.set_shader_parameter("wave_normal", _wave_normal)
	# shortcut: одна вісь течії на карту, бо річки на картах прямі; для звивистої
	# річки — напрямок із карти видів на фрагмент.
	mat.set_shader_parameter("flow_dir", Vector2(1, 0) if along_x >= along_y else Vector2(0, 1))
	material_override = mat


static func _is_water(board: Board, cell: Vector2i) -> bool:
	if cell.x >= board.width or cell.y >= board.height:
		return false
	var kind: int = board.kind_at(cell)
	return kind == Terrain.Kind.WATER or kind == Terrain.Kind.BRIDGE or kind == Terrain.Kind.BRIDGE_DESTROYED
