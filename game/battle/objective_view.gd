class_name ObjectiveView
extends Node3D
## Маркери цілей для ОДНОГО спостерігача (§3.5, §3.10): лише ті, що
## o.seen_by[observer] — ціль під нерозвіданою землею не отримує вузла взагалі.
## Читає лише стан, ніколи потік подій (§6: події не фільтруються за спостерігачем).

const MARKER_Y: float = 0.06

## Нейтральна — сірий; зруйнована — вугільна, окрема від усіх власників.
const _NEUTRAL: Color = Color("8a8a8a")
const _DESTROYED: Color = Color("2b2b2b")

var _markers: Dictionary[Vector2i, MeshInstance3D] = {}
var _state: Dictionary[Vector2i, Dictionary] = {}
var _meshes: Dictionary = {}
var _materials: Dictionary = {}


func rebuild(state: BattleState, observer: int) -> void:
	for n: MeshInstance3D in _markers.values():
		n.free()
	_markers.clear()
	_state.clear()
	for o in state.objectives:
		if o.seen_by[observer]:
			_add(o)


func marker_at(p: Vector2i) -> Node3D:
	return _markers.get(p, null)


func marker_state(p: Vector2i) -> Dictionary:
	return _state.get(p, {})


func _add(o: Objectives.Objective) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Objective_%d_%d" % [o.pos.x, o.pos.y]
	mi.mesh = _mesh(o.intact)
	mi.material_override = _material(o.owner, o.intact)
	mi.position = IsoCameraRig.cell_to_world(o.pos) + Vector3(0.0, MARKER_Y + (0.2 if o.intact else 0.02), 0.0)
	add_child(mi)
	_markers[o.pos] = mi
	_state[o.pos] = {"owner": o.owner, "intact": o.intact}


func _mesh(intact: bool) -> Mesh:
	if not _meshes.has(intact):
		if intact:
			var c := CylinderMesh.new()
			c.top_radius = 0.1
			c.bottom_radius = 0.25
			c.height = 0.4
			_meshes[intact] = c
		else:
			var b := BoxMesh.new()
			b.size = Vector3(0.5, 0.04, 0.5)
			_meshes[intact] = b
	return _meshes[intact]


func _material(owner: int, intact: bool) -> StandardMaterial3D:
	var key: int = -2 if not intact else owner
	if not _materials.has(key):
		var mat := StandardMaterial3D.new()
		if not intact:
			mat.albedo_color = _DESTROYED
		elif owner < 0:
			mat.albedo_color = _NEUTRAL
		else:
			mat.albedo_color = UnitView.PLAYER_COLORS[owner % UnitView.PLAYER_COLORS.size()]
		_materials[key] = mat
	return _materials[key]
