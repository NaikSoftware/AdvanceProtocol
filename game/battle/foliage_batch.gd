class_name FoliageBatch
extends RefCounted
## Злита сітка листя одного атласу: екземпляри всіх форм — один меш на поверхню, а не MultiMesh на
## форму (кожна форма була окремим викликом малювання, §8). Дані екземпляра — у таблиці `image`
## (три текселі на екземпляр: тон і «цілий», масштаб картки, точка постановки), вершина несе лише
## номер екземпляра в CUSTOM0.x. Розчинення над юнітом — запис у таблицю, а не перебудова меша.

## Ширина таблиці, текселів.
const W: int = 256
const TEXELS: int = 3

var image: Image
var texture: ImageTexture
var dirty: bool = false


static func create(count: int) -> FoliageBatch:
	var b := FoliageBatch.new()
	b.image = Image.create(W, maxi(1, ceili(float(count * TEXELS) / W)), false, Image.FORMAT_RGBAF)
	b.texture = ImageTexture.create_from_image(b.image)
	return b


func _at(id: int, k: int) -> Vector2i:
	var t: int = id * TEXELS + k
	return Vector2i(t % W, t / W)


func is_alive(id: int) -> bool:
	var p: Vector2i = _at(id, 0)
	return image.get_pixel(p.x, p.y).a > 0.5


func set_alive(id: int, alive: bool) -> void:
	var p: Vector2i = _at(id, 0)
	var c: Color = image.get_pixel(p.x, p.y)
	if (c.a > 0.5) != alive:
		c.a = 1.0 if alive else 0.0
		image.set_pixel(p.x, p.y, c)
		dirty = true


## Тільки після зміни: нерухомий екран таблицю не чіпає.
func upload() -> void:
	if dirty:
		texture.update(image)
		dirty = false


func _put(id: int, xf: Transform3D, rgb: Color) -> void:
	var a: Vector2i = _at(id, 0)
	image.set_pixel(a.x, a.y, Color(rgb.r, rgb.g, rgb.b, 1.0))
	var b: Vector2i = _at(id, 1)
	image.set_pixel(b.x, b.y, Color(xf.basis.x.length(), 0.0, 0.0, 0.0))
	var c: Vector2i = _at(id, 2)
	image.set_pixel(c.x, c.y, Color(xf.origin.x, xf.origin.y, xf.origin.z, 0.0))


## Заголовок шейдера: таблиця даних екземплярів.
static func glsl_decl() -> String:
	return "uniform sampler2D inst_data : filter_nearest, repeat_disable;"


## Початок vertex(): `iid` і доступ до таблиці — `batch_a` (тон, видимість) і `batch_scale`; з
## `with_origin` ще й `batch_origin` (точка постановки: потрібна лише плямі затінення).
static func glsl_fetch(with_origin: bool = false) -> String:
	var code: String = ("int iid = int(CUSTOM0.x + 0.5) * {n};\n"
			+ "\tvec4 batch_a = texelFetch(inst_data, ivec2(iid % {w}, iid / {w}), 0);\n"
			+ "\tfloat batch_scale = texelFetch(inst_data, ivec2((iid + 1) % {w}, (iid + 1) / {w}), 0).x;")
	if with_origin:
		code += "\n\tvec3 batch_origin = texelFetch(inst_data, ivec2((iid + 2) % {w}, (iid + 2) / {w}), 0).xyz;"
	return code.format({"n": TEXELS, "w": W})


## Зливає поверхню зі списків екземплярів: `entries` — [{"arrays": масиви поверхні, "list": [{"xf",
## "rgb"}, ...]}]. Номери екземплярів ідуть підряд, початок групи пишеться в entry["first"]; `register`
## — заносити екземпляри в таблицю (раз на батч, а не на кожну його поверхню): наступна поверхня
## (без register) бере ці самі номери з entry["first"] і може пропускати групи без неї. Повертає масиви для
## ArrayMesh.add_surface_from_arrays з CUSTOM0 = номер екземпляра (формат ARRAY_CUSTOM_R_FLOAT).
func merge(entries: Array, register: bool) -> Array:
	var v := PackedVector3Array()
	var nrm := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var col := PackedColorArray()
	var ids := PackedFloat32Array()
	var idx := PackedInt32Array()
	var id: int = 0
	for e: Dictionary in entries:
		if not register:
			id = int(e["first"])  # номери вже роздано поверхнею, що заносила екземпляри
		var a: Array = e["arrays"]
		var src_v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var src_n: Variant = a[Mesh.ARRAY_NORMAL]
		var src_uv: Variant = a[Mesh.ARRAY_TEX_UV]
		var src_uv2: Variant = a[Mesh.ARRAY_TEX_UV2]
		var src_c: Variant = a[Mesh.ARRAY_COLOR]
		var src_i: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		var same_id := PackedFloat32Array()
		same_id.resize(src_v.size())
		if register:
			e["first"] = id
		for it: Dictionary in e["list"]:
			var xf: Transform3D = it["xf"]
			var base: int = v.size()
			v.append_array(xf * src_v)
			if src_n != null:
				nrm.append_array(Transform3D(xf.basis, Vector3.ZERO) * (src_n as PackedVector3Array))
			if src_uv != null:
				uv.append_array(src_uv)
			if src_uv2 != null:
				uv2.append_array(src_uv2)
			if src_c != null:
				col.append_array(src_c)
			same_id.fill(float(id))
			ids.append_array(same_id)
			for i: int in src_i:
				idx.append(base + i)
			if register:
				_put(id, xf, it["rgb"])
			id += 1
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	if not nrm.is_empty():
		arrays[Mesh.ARRAY_NORMAL] = nrm
	if not uv.is_empty():
		arrays[Mesh.ARRAY_TEX_UV] = uv
	if not uv2.is_empty():
		arrays[Mesh.ARRAY_TEX_UV2] = uv2
	if not col.is_empty():
		arrays[Mesh.ARRAY_COLOR] = col
	arrays[Mesh.ARRAY_CUSTOM0] = ids
	arrays[Mesh.ARRAY_INDEX] = idx
	return arrays


## Формат CUSTOM0 для add_surface_from_arrays: номер екземпляра — одне число.
static func custom_flags() -> int:
	return Mesh.ARRAY_CUSTOM_R_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
