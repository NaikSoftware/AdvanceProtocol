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

## Моделі зі збільшенням ~×9 (docs/art-direction.md, «Mines»): справжня міна 0,3 м на дошці
## тайл = 8 м — це 3 px. Своя — лише міна на розритому ґрунті; розкрита ворожа — ще квадратна
## огорожа з червоно-білої стрічки на кілках (позначка сапера): відрізняються формою й кольором.
const _MODELS: Dictionary = {
	Style.OWN: "res://assets/props/ordnance/mine_own.glb",
	Style.ENEMY_REVEALED: "res://assets/props/ordnance/mine_enemy.glb",
}

static var _meshes: Dictionary = {}
static var _material: StandardMaterial3D

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
