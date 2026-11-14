class_name MineLayer
extends Node3D
## Міни на дошці для ОДНОГО спостерігача (§3.5, §3.11): свої — завжди, ворожі —
## лише ті, що core/ уже позначив known_to[observer]. Нерозкрита ворожа міна не
## отримує вузла взагалі: невидимий маркер чи «порожній» вузол теж був би доносом.
##
## Читає лише стан, ніколи потік подій: події не фільтруються за спостерігачем
## (§6, відомий борг), тож MinePlaced чужого гравця тут нічого не важить.

enum Style { OWN, ENEMY_REVEALED }

## Майже на ґрунті і під контурами зон (BoardView._CONTOUR_Y), щоб ризки не ховались у моделі.
const MARKER_Y: float = 0.02

## Не шар світу (1): зонд відбиттів BoardView знімає шар 1, і маркер власника у
## знімку показав би його міну суперникові у воді чи калюжі (§3.11).
const MARKER_LAYER: int = 3

## Збільшення моделі проти справжніх 0,3 м; одна стала, від зуму не залежить (tools/blender/ordnance/mine.py).
const MINE_FACTOR: float = 5.0

## Міна збільшена в MINE_FACTOR разів проти справжніх 0,3 м (docs/art-direction.md, «Ordnance»):
## на дошці тайл = 8 м, і без цього вона менша за піксель. Своя закопана врівень, знайдена
## ворожа відкопана й лежить на поверхні; на дорозі замість ґрунту — биті шматки асфальту.
## Чия міна — тонке плоске кільце кольору HP-смуги власника, як і юніт (UnitView.hp_fill_color):
## це накладка в стилі контурів зон, а не предмет на землі.
const _MODELS: Dictionary = {
	0: "res://assets/props/ordnance/mine_own.glb",
	1: "res://assets/props/ordnance/mine_enemy.glb",
	2: "res://assets/props/ordnance/mine_own_road.glb",
	3: "res://assets/props/ordnance/mine_enemy_road.glb",
}

static var _meshes: Dictionary = {}
static var _material: StandardMaterial3D
static var _ring_material: StandardMaterial3D

const RING_RADIUS: float = 0.3
## Ширша за контур зони (0,02): на найдальшому зумі 0,02 тайла — менше за піксель, а кільце там
## єдине, що каже, чия міна.
const RING_WIDTH: float = 0.05
const _RING_SEGMENTS: int = 32

var _markers: Dictionary[Vector2i, Node3D] = {}


## Усі міни одного вигляду — один MultiMesh, усі кільця — одна сітка: виклики малювання не
## ростуть із числом мін.
func rebuild(state: BattleState, observer: int) -> void:
	for n: Node in get_children():
		n.free()
	_markers.clear()
	var cells: Dictionary = {}
	for m in state.mines:
		var style: int = -1
		if m.owner == observer:
			style = Style.OWN
		elif Mines.is_known(state, m.pos, observer):
			style = Style.ENEMY_REVEALED
		if style >= 0:
			var model: int = style + (2 if state.board.kind_at(m.pos) == Terrain.Kind.ROAD else 0)
			if not cells.has(model):
				cells[model] = []
			cells[model].append(m)
	for model: int in cells:
		_add_model(model, cells[model])
	if not _markers.is_empty():
		_add_rings(state)


func marker_count() -> int:
	return _markers.size()


func marker_at(p: Vector2i) -> Node3D:
	return _markers.get(p, null)


static func mesh_of(style: int, on_road: bool = false) -> Mesh:
	var key: int = style + (2 if on_road else 0)
	if not _meshes.has(key):
		var root: Node = (load(_MODELS[key]) as PackedScene).instantiate()
		var mi: MeshInstance3D = root.find_children("*", "MeshInstance3D", true, false)[0]
		_meshes[key] = mi.mesh
		root.free()
	return _meshes[key]


static func _shared_material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.roughness = 0.9
	return _material


## Висота землі під клітинкою: на мосту — настил, а не русло під ним (так само, як у юніта й контурів).
static func ground_at(cell: Vector2i) -> float:
	var w: Vector3 = IsoCameraRig.cell_to_world(cell)
	var th: TerrainHeight = TerrainHeight.active
	if th != null:
		var deck: float = th.deck_y(cell)
		if deck > th.at(float(cell.x), float(cell.y)) + 0.001:
			return deck
	return TerrainHeight.ground_y(w.x, w.z)


func _add_model(model: int, list: Array) -> void:
	var style: int = model % 2
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh_of(style, model >= 2)
	mm.instance_count = list.size()
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Mines_%d" % model
	mmi.multimesh = mm
	mmi.material_override = _shared_material()
	mmi.layers = 1 << (MARKER_LAYER - 1)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	for i in list.size():
		var p: Vector2i = list[i].pos
		var w: Vector3 = IsoCameraRig.cell_to_world(p)
		w.y = ground_at(p) + MARKER_Y
		# Поворот лише косметичний (хеш клітинки): ряд мін не виглядає штампом.
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, float(hash(p) % 628) / 100.0), w))
		var n := Node3D.new()
		n.name = "Mine_%d_%d" % [p.x, p.y]
		n.position = w
		n.set_meta("style", style)
		mmi.add_child(n)
		_markers[p] = n


## Усі кільця — одна сітка з висотою землі в кожній вершині, як у контурів зон: на схилі кільце
## не тоне й не висить. Колір кожного — HP-смуга власника.
func _add_rings(state: BattleState) -> void:
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var idx := PackedInt32Array()
	var half: float = RING_WIDTH * 0.5
	for m in state.mines:
		if not _markers.has(m.pos):
			continue
		var c: Color = UnitView.hp_fill_color(m.owner)
		_markers[m.pos].set_meta("ring_color", c)
		var mid: Vector3 = IsoCameraRig.cell_to_world(m.pos)
		var deck: float = ground_at(m.pos)
		var on_deck: bool = deck > TerrainHeight.ground_y(mid.x, mid.z) + 0.001
		var base: int = verts.size()
		for i in _RING_SEGMENTS:
			var d := Vector3(cos(TAU * i / _RING_SEGMENTS), 0.0, sin(TAU * i / _RING_SEGMENTS))
			for r: float in [RING_RADIUS - half, RING_RADIUS + half]:
				var q: Vector3 = mid + d * r
				q.y = (deck if on_deck else TerrainHeight.ground_y(q.x, q.z)) + MARKER_Y
				verts.append(q)
				colors.append(c)
			var j: int = (i + 1) % _RING_SEGMENTS
			idx.append_array([base + 2 * i, base + 2 * i + 1, base + 2 * j, base + 2 * i + 1, base + 2 * j + 1, base + 2 * j])
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = colors
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.name = "Rings"
	mi.mesh = mesh
	mi.material_override = _ring_mat()
	mi.layers = 1 << (MARKER_LAYER - 1)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


static func _ring_mat() -> StandardMaterial3D:
	if _ring_material == null:
		_ring_material = StandardMaterial3D.new()
		_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ring_material.vertex_color_use_as_albedo = true
		# Колір HP-смуги — sRGB: без цього вершинний колір читається лінійним і кільце бліднішає.
		_ring_material.vertex_color_is_srgb = true
		_ring_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _ring_material
