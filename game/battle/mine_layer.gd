class_name MineLayer
extends Node3D
## Міни на дошці для ОДНОГО спостерігача (§3.5, §3.11): свої — завжди, ворожі —
## лише ті, що core/ уже позначив known_to[observer]. Нерозкрита ворожа міна не
## отримує вузла взагалі: невидимий маркер чи «порожній» вузол теж був би доносом.
##
## Читає лише стан, ніколи потік подій: події не фільтруються за спостерігачем
## (§6, відомий борг), тож MinePlaced чужого гравця тут нічого не важить.

enum Style { OWN, ENEMY_REVEALED }

## Трохи над тайлом і під контурами зон (BoardView._CONTOUR_Y = 0.07), щоб
## маркер не z-fight'ив ні з тайлом, ні з ризками.
const MARKER_Y: float = 0.06

## Нейтральні плейсхолдери (§2): своя — тьмяний пісочний диск, ворожа — червоний
## ромб. Відрізняються і кольором, і формою, щоб не покладатися на один колір.
const _COLORS: Dictionary = {
	Style.OWN: Color("c9b46a"),
	Style.ENEMY_REVEALED: Color("c0392b"),
}

var _markers: Dictionary[Vector2i, Node3D] = {}
var _meshes: Dictionary = {}
var _materials: Dictionary = {}


func rebuild(state: BattleState, observer: int) -> void:
	for n: Node3D in _markers.values():
		n.free()
	_markers.clear()
	for m in state.mines:
		if m.owner == observer:
			_add(m.pos, Style.OWN)
		elif m.known_to[observer]:
			_add(m.pos, Style.ENEMY_REVEALED)


func marker_count() -> int:
	return _markers.size()


func marker_at(p: Vector2i) -> Node3D:
	return _markers.get(p, null)


func _add(p: Vector2i, style: int) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Mine_%d_%d" % [p.x, p.y]
	mi.mesh = _mesh(style)
	mi.material_override = _material(style)
	mi.position = IsoCameraRig.cell_to_world(p) + Vector3(0.0, MARKER_Y, 0.0)
	if style == Style.ENEMY_REVEALED:
		mi.rotation.y = PI * 0.25
	mi.set_meta("style", style)
	add_child(mi)
	_markers[p] = mi


func _mesh(style: int) -> Mesh:
	if not _meshes.has(style):
		if style == Style.OWN:
			var c := CylinderMesh.new()
			c.top_radius = 0.2
			c.bottom_radius = 0.2
			c.height = 0.04
			_meshes[style] = c
		else:
			var b := BoxMesh.new()
			b.size = Vector3(0.32, 0.04, 0.32)
			_meshes[style] = b
	return _meshes[style]


func _material(style: int) -> StandardMaterial3D:
	if not _materials.has(style):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = _COLORS[style]
		_materials[style] = mat
	return _materials[style]
