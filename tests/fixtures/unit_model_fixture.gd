extends RefCounted
## Сітка-замінник GLB юніта за контрактом моделей: низ по центру на y = 0, COLOR і UV2 як у
## справжньої моделі. Верх — панель власника (R), правий бік — колесо (B, вісь у UV2, альфа 0,5 — швидкість опорного котка),
## лівий — трак (G, довжина по контуру в UV2.x). Тести не залежать від файлів на диску.

const SPECULAR: float = 0.3


static func mesh(size: Vector3) -> ArrayMesh:
	var box := BoxMesh.new()
	box.size = size
	var a: Array = box.get_mesh_arrays()
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var c := PackedColorArray()
	var uv2 := PackedVector2Array()
	for i in v.size():
		v[i].y += size.y * 0.5
		var col := Color.BLACK
		var u2 := Vector2.ZERO
		if n[i].y > 0.5:
			col.r = 1.0
		elif n[i].x > 0.5:
			col.b = 1.0
			col.a = 0.5
			u2 = Vector2(size.y * 0.5, 0.0)
		elif n[i].x < -0.5:
			col.g = 1.0
			u2 = Vector2(-v[i].z, 0.0)
		c.append(col)
		uv2.append(u2)
	a[Mesh.ARRAY_VERTEX] = v
	a[Mesh.ARRAY_COLOR] = c
	a[Mesh.ARRAY_TEX_UV2] = uv2
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	var mat := StandardMaterial3D.new()
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.5, 0.45, 0.4))
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.metallic_specular = SPECULAR
	out.surface_set_material(0, mat)
	return out


## Корпус машини за розміром `_SPECS.hull` типу.
static func vehicle(type_id: int) -> ArrayMesh:
	return mesh(UnitSilhouettes.spec(type_id).hull)


## Один боєць: 1,8 м заввишки, ступні на y = 0.
static func soldier() -> ArrayMesh:
	return mesh(UnitSilhouettes.FIGURE_SIZE)


## Скільки вершин сітки несуть знак власника (COLOR.r).
static func marked_vertices(m: Mesh) -> int:
	var count: int = 0
	for col: Color in m.surface_get_arrays(0)[Mesh.ARRAY_COLOR]:
		if col.r > 0.5:
			count += 1
	return count
