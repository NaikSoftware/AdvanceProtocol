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

## Моделі справжнього розміру (docs/art-direction.md, «Mines»): міна 0,3 м, на дошці тайл = 8 м —
## це 2 px, тож читається вона плямою ґрунту. Своя закопана врівень, знайдена ворожа відкопана
## й лежить на поверхні. Чия міна — тонке плоске кільце кольору HP-смуги власника, як і юніт
## (UnitView.hp_fill_color): це накладка в стилі контурів зон, а не предмет на землі.
const _MODELS: Dictionary = {
	Style.OWN: "res://assets/props/ordnance/mine_own.glb",
	Style.ENEMY_REVEALED: "res://assets/props/ordnance/mine_enemy.glb",
}

static var _meshes: Dictionary = {}
static var _material: StandardMaterial3D
static var _ring_material: StandardMaterial3D
static var _ring_mesh: ArrayMesh

const RING_RADIUS: float = 0.3
## Та сама товщина лінії, що в контурів зон (BoardView._CONTOUR_WIDTH).
const RING_WIDTH: float = 0.02
const _RING_SEGMENTS: int = 32

var _markers: Dictionary[Vector2i, Node3D] = {}


## Усі міни одного вигляду — один MultiMesh: десять мін це два виклики малювання, а не десять.
func rebuild(state: BattleState, observer: int) -> void:
	for n: Node in get_children():
		n.free()
	_markers.clear()
	var cells: Dictionary = {Style.OWN: [], Style.ENEMY_REVEALED: []}
	for m in state.mines:
		if m.owner == observer:
			cells[Style.OWN].append(m.pos)
		elif Mines.is_known(state, m.pos, observer):
			cells[Style.ENEMY_REVEALED].append(m.pos)
	for style: int in cells:
		var list: Array = cells[style]
		if not list.is_empty():
			_add_style(style, list)
	if not _markers.is_empty():
		_add_rings(state)


func marker_count() -> int:
	return _markers.size()


func marker_at(p: Vector2i) -> Node3D:
	return _markers.get(p, null)


static func mesh_of(style: int) -> Mesh:
	if not _meshes.has(style):
		var root: Node = (load(_MODELS[style]) as PackedScene).instantiate()
		var mi: MeshInstance3D = root.find_children("*", "MeshInstance3D", true, false)[0]
		_meshes[style] = mi.mesh
		root.free()
	return _meshes[style]


static func _shared_material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.roughness = 1.0
	return _material


func _add_style(style: int, list: Array) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh_of(style)
	mm.instance_count = list.size()
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Mines_%d" % style
	mmi.multimesh = mm
	mmi.material_override = _shared_material()
	mmi.layers = 1 << (MARKER_LAYER - 1)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	for i in list.size():
		var p: Vector2i = list[i]
		var w: Vector3 = IsoCameraRig.cell_to_world(p)
		w.y = TerrainHeight.ground_y(w.x, w.z) + MARKER_Y
		# Поворот лише косметичний (хеш клітинки): ряд мін не виглядає штампом.
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, float(hash(p) % 628) / 100.0 if style == Style.OWN else 0.0), w))
		var n := Node3D.new()
		n.name = "Mine_%d_%d" % [p.x, p.y]
		n.position = w
		n.set_meta("style", style)
		mmi.add_child(n)
		_markers[p] = n


## Усі кільця — один MultiMesh із кольором на екземпляр: зайвого виклику малювання за гравця нема.
func _add_rings(state: BattleState) -> void:
	var cells: Array[Mines.Mine] = []
	for m in state.mines:
		if _markers.has(m.pos):
			cells.append(m)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = ring_mesh()
	mm.instance_count = cells.size()
	for i in cells.size():
		mm.set_instance_transform(i, Transform3D(Basis(), _markers[cells[i].pos].position))
		mm.set_instance_color(i, UnitView.hp_fill_color(cells[i].owner))
		_markers[cells[i].pos].set_meta("ring_color", UnitView.hp_fill_color(cells[i].owner))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Rings"
	mmi.multimesh = mm
	mmi.material_override = _ring_mat()
	mmi.layers = 1 << (MARKER_LAYER - 1)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


static func ring_mesh() -> ArrayMesh:
	if _ring_mesh == null:
		var verts := PackedVector3Array()
		var idx := PackedInt32Array()
		for i in _RING_SEGMENTS:
			var d := Vector3(cos(TAU * i / _RING_SEGMENTS), 0.0, sin(TAU * i / _RING_SEGMENTS))
			verts.append(d * (RING_RADIUS - RING_WIDTH * 0.5))
			verts.append(d * (RING_RADIUS + RING_WIDTH * 0.5))
			var j: int = (i + 1) % _RING_SEGMENTS
			idx.append_array([2 * i, 2 * i + 1, 2 * j, 2 * i + 1, 2 * j + 1, 2 * j])
		var arr: Array = []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_INDEX] = idx
		_ring_mesh = ArrayMesh.new()
		_ring_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return _ring_mesh


static func _ring_mat() -> StandardMaterial3D:
	if _ring_material == null:
		_ring_material = StandardMaterial3D.new()
		_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ring_material.vertex_color_use_as_albedo = true
		_ring_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _ring_material
