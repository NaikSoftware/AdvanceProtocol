extends GutTest

## Контракт вершинних даних бібліотек рослинності (tools/blender/vegetation/veg_build.py), на який
## спирається veg_body.gdshaderinc:
## - G — ідентифікатор пучка: дерева в нижній половині [0; 0,5) (їх тримає fade_floor), решта —
##   у верхній [0,5; 1);
## - поверхня 1 (пляма затінення) — у всіх, крім снопів очерету й рогозу;
## - бюджет трикутників: дерево 800 (гола крона пізньої пори — 1500: щільна мережа гілочок), кущ біля хати 400, інший кущ 600, сніп 300.

const LIBS: Array[String] = [
	"bank_veg_late", "bank_veg_summer", "bank_veg_early",
	"yard_veg_late", "yard_veg_summer", "yard_veg_early",
	"meadow_veg_late", "meadow_veg_summer", "meadow_veg_early",
]
const TREES: Array[String] = ["yard_apple", "yard_cherry", "yard_walnut", "meadow_pear", "meadow_oak", "meadow_willow"]
const SHEAVES: Array[String] = ["bank_reed", "bank_cattail"]


static func _starts(name: String, prefixes: Array[String]) -> bool:
	for p in prefixes:
		if name.begins_with(p):
			return true
	return false


func test_vertex_contract(p = use_parameters(LIBS)) -> void:
	var path := "res://assets/props/vegetation/%s.glb" % p
	var scene: PackedScene = load(path) as PackedScene
	assert_not_null(scene, "нема %s" % path)
	if scene == null:
		return
	var root: Node3D = scene.instantiate()
	add_child_autofree(root)
	var nodes: int = 0
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		nodes += 1
		var name := String(mi.name)
		var fallen: bool = name.ends_with("_fallen")
		var tree: bool = _starts(name, TREES)
		var sheaf: bool = _starts(name, SHEAVES)
		# G перевіряється на поверхні 0: її шейдери (veg, veg_fade*) читають G; пляма затінення
		# (поверхня 1, veg_shade.gdshader) G не читає — лише R (сила) й B (висота крони).
		var a: Array = mi.mesh.surface_get_arrays(0)
		var col: PackedColorArray = a[Mesh.ARRAY_COLOR]
		var bad_g: int = 0
		for i in col.size():
			if (col[i].g < 0.5) != tree:
				bad_g += 1
		assert_eq(bad_g, 0, "%s/%s: G (дерево/решта) не за контрактом у %d вершин" % [p, name, bad_g])
		var want_surfaces: int = 1 if sheaf else 2
		assert_eq(mi.mesh.get_surface_count(), want_surfaces, "%s/%s: поверхонь" % [p, name])
		var tris: int = 0
		for s in mi.mesh.get_surface_count():
			tris += (mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		var limit: int = (1500 if p.ends_with("_late") else 800) if tree else (300 if sheaf else (400 if p.begins_with("yard") else 600))
		assert_lte(tris, limit, "%s/%s: трикутників %d" % [p, name, tris])
	assert_gt(nodes, 0, "%s: нема вузлів" % p)


## Береговий кущ — приглушений оливковий, як верболіз і трава поруч: середній колір непрозорих
## текселів його пучків має насиченість (max − min) / max каналів sRGB не вищу за BUSH_SATURATION.
## Верболіз — 0,17–0,27, вільха — 0,14–0,37. Розтяг контрасту кожного каналу від сірого (GAIN у
## veg_atlas.py) множить насиченість разом із яскравістю: вільха виходить салатовою, ~0,72.
const BUSH_SATURATION: float = 0.45
## Гілля в пучку — кольору кори, не світле: текселів листя пучка з яскравістю (середнє каналів
## sRGB) вище BUSH_PALE — менше за BUSH_PALE_SHARE. Розтяг контрасту робить із гілочок,
## світліших за листя, майже білі цятки.
const BUSH_PALE: float = 0.8
const BUSH_PALE_SHARE: float = 0.01


func test_bank_bushes_are_muted(p = use_parameters(["bank_veg_late", "bank_veg_summer", "bank_veg_early"])) -> void:
	# Сам PNG, а не імпортована текстура: та стиснута у VRAM-формат із втратами.
	var img := Image.new()
	assert_eq(img.load_png_from_buffer(FileAccess.get_file_as_bytes("res://assets/props/vegetation/%s.png" % p)), OK, "атлас %s" % p)
	var root: Node3D = (load("res://assets/props/vegetation/%s.glb" % p) as PackedScene).instantiate()
	add_child_autofree(root)
	var size := Vector2(img.get_size())
	var bushes: int = 0
	for mi: MeshInstance3D in root.find_children("bank_bush_*", "MeshInstance3D", true, false):
		if String(mi.name).ends_with("_fallen"):
			continue
		bushes += 1
		var a: Array = mi.mesh.surface_get_arrays(0)
		var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
		var uv2: PackedVector2Array = a[Mesh.ARRAY_TEX_UV2]
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		# Прямокутник спрайта — межі UV трикутника картки (UV2 ≠ 0); кора й гілки (UV2 = 0) — не листя.
		var rects := {}
		for t in range(0, idx.size(), 3):
			if uv2[idx[t]].length() < 1e-3:
				continue
			var r := Rect2(uv[idx[t]], Vector2.ZERO).expand(uv[idx[t + 1]]).expand(uv[idx[t + 2]])
			rects[Rect2i(Vector2i((r.position * size).round()), Vector2i((r.size * size).round()))] = true
		var sum := Vector3.ZERO
		var n: int = 0
		var pale: int = 0
		for r: Rect2i in rects:
			for y in range(r.position.y, r.end.y):
				for x in range(r.position.x, r.end.x):
					var c := img.get_pixel(x, y)
					if c.a > 0.5:
						sum += Vector3(c.r, c.g, c.b)
						n += 1
						if (c.r + c.g + c.b) / 3.0 > BUSH_PALE:
							pale += 1
		assert_gt(n, 0, "%s/%s: нема непрозорих текселів листя" % [p, mi.name])
		var m := sum / maxf(n, 1) * 255.0
		var hi: float = maxf(m.x, maxf(m.y, m.z))
		var sat: float = (hi - minf(m.x, minf(m.y, m.z))) / maxf(hi, 1.0)
		var share: float = float(pale) / maxf(n, 1)
		assert_lt(share, BUSH_PALE_SHARE, "%s/%s: світлих текселів %.4f" % [p, mi.name, share])
		assert_lte(sat, BUSH_SATURATION, "%s/%s: насиченість листя %.2f, середній колір %s" % [p, mi.name, sat, m])
	assert_gt(bushes, 0, "%s: нема кущів" % p)
