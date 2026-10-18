class_name GroundSurface
extends MeshInstance3D
## Суцільна земля під дошкою (Phase 5a): один меш, один draw call (§8), колір і
## рельєф дає шейдер з карти видів, а не плитки на вид.
##
## §3.5: місцевість публічна й на повній яскравості — тут немає і не може бути
## жодного зв'язку з туманом. Земля плоска (y = 0): висота поховала б контури зон.

## Порядок шарів Texture2DArray — тут, поруч із TEX_LAYER_FOR_KIND, а не в
## окремому .tres, щоб відповідність вид -> шар читалась в одному місці.
const TEX_LAYERS: Array[String] = ["road", "field", "forest", "hill", "marsh", "mud", "rubble", "bank"]

const TEX_LAYER_FOR_KIND: Dictionary = {
	Terrain.Kind.ROAD: 0,
	# Річка тече під мостом: під цілим мостом — русло, як під водою.
	Terrain.Kind.BRIDGE: 7,
	Terrain.Kind.FIELD: 1,
	Terrain.Kind.FOREST: 2,
	Terrain.Kind.HILL: 3,
	Terrain.Kind.MARSH: 4,
	Terrain.Kind.WATER: 7,
	Terrain.Kind.BRIDGE_DESTROYED: 7,
	Terrain.Kind.BUILDING: 6,
	Terrain.Kind.RUBBLE: 6,
}

## Частка поля й пагорба, що при GroundState.MUD вкрита плямами багна далеко від
## доріг (біля доріг шейдер додає ще 0.2). §3.12: стан ґрунту — правило, і земля
## мусить його показувати, не лише іконка HUD; але поле лишається полем.
const MUD_BLEND: float = 0.3

const _SHADER: Shader = preload("res://game/battle/shaders/ground.gdshader")

## Масиви текстур (~17 МБ стиснених) належать цьому вузлу: вантажаться при першому
## build(), повторний build() (підірваний міст) їх не чіпає, а вийшли з бою —
## звільнились разом із землею. BoardView тримає землю між перебудовами.
var _albedo_array: Texture2DArray
var _normal_array: Texture2DArray

var _kind_image: Image


func build(board: Board, margin: int) -> void:
	var w: int = board.width + 2 * margin
	var h: int = board.height + 2 * margin
	if w <= 0 or h <= 0:
		_kind_image = Image.new()
		mesh = null
		material_override = null
		return
	_kind_image = Image.create(w, h, false, Image.FORMAT_R8)
	for py in h:
		for px in w:
			var cell := Vector2i(clampi(px - margin, 0, board.width - 1), clampi(py - margin, 0, board.height - 1))
			_kind_image.set_pixel(px, py, Color8(board.kind_at(cell), 0, 0))

	var plane := PlaneMesh.new()
	plane.size = Vector2(w, h)
	mesh = plane
	position = Vector3((board.width - 1) * 0.5, 0.0, (board.height - 1) * 0.5)
	layers = 1
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var table := PackedInt32Array()
	table.resize(Terrain.Kind.size())
	for kind: int in TEX_LAYER_FOR_KIND:
		table[kind] = TEX_LAYER_FOR_KIND[kind]

	var mat := ShaderMaterial.new()
	mat.shader = _SHADER
	mat.set_shader_parameter("kind_map", ImageTexture.create_from_image(_kind_image))
	mat.set_shader_parameter("map_origin", Vector2(-margin, -margin))
	mat.set_shader_parameter("layer_for_kind", table)
	mat.set_shader_parameter("mud_amount", MUD_BLEND if board.ground_state == Terrain.GroundState.MUD else 0.0)
	if _albedo_array == null:
		_albedo_array = _load_array("albedo")
		_normal_array = _load_array("normal")
	mat.set_shader_parameter("albedo_array", _albedo_array)
	mat.set_shader_parameter("normal_array", _normal_array)
	material_override = mat


func kind_image() -> Image:
	return _kind_image


static func _load_array(suffix: String) -> Texture2DArray:
	var images: Array[Image] = []
	for layer_name in TEX_LAYERS:
		var tex: Texture2D = load("res://assets/terrain/%s_%s.png" % [layer_name, suffix])
		# Імпорт — VRAM-стиснений із міпмапами (S3TC/RGTC на ПК, ETC2 на телефоні):
		# шари однакового формату йдуть у масив як є, без розпаковки й CPU-міпмап.
		images.append(tex.get_image())
	var arr := Texture2DArray.new()
	arr.create_from_images(images)
	return arr
