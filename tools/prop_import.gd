@tool
extends EditorScenePostImport
## Пост-імпорт GLB будівель: glTF не несе specular (Godot не читає KHR_materials_specular),
## а типові 0,5 дають мінеральним поверхням рівний пластиковий відблиск. Штукатурка, цегла,
## шифер і бетон мають F0 близько 2-3 %, тож specular 0,3 на всіх поверхнях атласу.

const MINERAL_SPECULAR: float = 0.3


func _post_import(scene: Node) -> Object:
	_walk(scene)
	return scene


func _walk(n: Node) -> void:
	var mi := n as MeshInstance3D
	if mi != null and mi.mesh != null:
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i) as BaseMaterial3D
			if m != null:
				m.metallic_specular = MINERAL_SPECULAR
	for c in n.get_children():
		_walk(c)
