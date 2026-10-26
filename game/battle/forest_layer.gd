class_name ForestLayer
extends Node3D
## Ліс на клітинках FOREST дошки й кільця: розкид `ForestScatter.plan()`, по MultiMesh на
## вузол бібліотеки (forest_conifer.glb, forest_broadleaf_<сезон>.glb).
##
## - Дошка: дерева, кущі, підріст, смуги узлісся, колоди, по дві форми на породу. Проломи — ті,
##   що знає глядач (`BattleState.known_broken_map`), а не правда: інакше ліс видав би, де
##   пройшов ворог. Розкид має зерно на кожну точку, тож новий пролам змінює лише дерева біля нього.
## - Кільце: лише намет, по одній формі на породу сітками проксі (~16 трикутників замість 50–100),
##   удвічі рідше й ширшими кронами — та сама зімкнутість. Туди юніти не заходять, і камера
##   дивиться здаля. Один MultiMesh на породу на все кільце: ~10 тис. трикутників дешевші за
##   зайві виклики малювання.
## - Понад `DETAIL_ZOOM` підлісок під наметом не малюється: з такої висоти його не видно.
## - Підріст і низькі дерева (нижче `UNDER_TOP`) — однією сіткою проксі на породу: з такої
##   висоти пучків не розрізнити, а вони найчисленніші.
## - Тінь лісу запечена (§8: справжню тінь кидають лише юніти): маска плям крон у напрямку сонця
##   карти лягає на землю одним напівпрозорим шаром (`_bake_shadow`).
## - Крони між камерою й показаним юнітом стають напівпрозорими — цілими деревами, без растру;
##   показані — ті самі, що й під дахами (`set_reveal_cells`), тож невидимий ворог себе не видає.

const _SHADER: Shader = preload("res://assets/props/forest/forest_crown.gdshader")
const _DIR: String = "res://assets/props/forest/"
## Типовий зум гри — 12 (IsoCameraRig.zoom_level); до цього зуму включно ліс повний.
const DETAIL_ZOOM: float = 15.0
## Розчинення над юнітом: відстань від променя «юніт → камера» до центру крони (тайли),
## ширина м'якого переходу й найменша непрозорість.
const FADE_RADIUS: float = 0.6
const FADE_SOFT: float = 0.3
const FADE_ALPHA: float = 0.35
const FADE_REACH_EXTRA: float = 0.5
const UNIT_HALF: float = 0.4
## Розчинення перераховується, коли зум змінився більше ніж на стільки.
const FADE_ZOOM_STEP: float = 0.5
## Склад лісу клітинки за MapData.ForestSurface (MIXED, PINE, DECIDUOUS).
const WOOD_OF_SURFACE: PackedStringArray = ["mixed", "pine", "deciduous"]
const TREES: PackedStringArray = ["Pine", "Spruce", "Birch", "Oak"]
## Форми порід у бою: по дві на породу (кожна форма — виклик малювання).
const FORMS: PackedStringArray = ["Pine_A", "Pine_B", "Spruce_A", "Spruce_B", "Birch_A", "Birch_B", "Oak_A", "Oak_B"]
## Нижче цієї висоти (тайли) і глибше `UNDER_DEPTH` у лісі — підлісок під наметом.
const UNDER_TOP: float = 0.45
const UNDER_DEPTH: float = 0.7
## Кільце: у смузі `RING_NEAR` клітинок від дошки (її камера бачить біля краю) — повна густота,
## крона ширша в `RING_NEAR_WIDE` раза (у кільці немає поясу кущів, смуг узлісся й підросту, що на
## дошці закривають просвіти); далі кожне друге дерево з кроною, ширшою ще в √2 раза.
const RING_NEAR: float = 5.0
const RING_NEAR_WIDE: float = 1.3
const RING_KEEP: int = 2
const RING_WIDE: float = 1.84
## Шматок землі просіки — сітка DRAPE × DRAPE по рельєфу, на DRAPE_LIFT над землею.
const DRAPE: int = 10
const DRAPE_LIFT: float = 0.01
## Запечена тінь: пікселів маски на тайл, підйом над землею (над шматками просіки; квад на тайл
## рельєф між кутами не повторює) і розмиття.
const SHADOW_PX: int = 4
const SHADOW_LIFT: float = 0.05
const SHADOW_BLUR: int = 2

## Напрям НА сонце (WeatherRig: sun.basis.z) і сила тіні (частка світла, яку забирає крона);
## ставить дошка з вигляду карти до build().
var sun_dir := Vector3(0.5, 0.7071, 0.5)
var shadow_strength: float = 0.15

var _season: String = ""
var _seed: int = 0
var _cells: Dictionary = {}  ## Vector2i -> true: увесь ліс (дошка й кільце), координати дошки
var _wood: Dictionary = {}  ## Vector2i -> склад лісу
var _board := Rect2i()
var _world := Rect2i()  ## дошка разом із кільцем, координати дошки
var _lib: Dictionary = {}  ## ім'я вузла -> {"h", "half"}
var _mesh: Dictionary = {}  ## ім'я вузла -> Mesh (і проксі `<вузол>_Shadow`)
var _mat: Dictionary = {}  ## Mesh -> ShaderMaterial
var _soft_mat: Dictionary = {}  ## Mesh -> ShaderMaterial (прозорість)
var _ground_mesh: Mesh
var _signature: String = ""
var _broken: Dictionary = {}
var _ring_crowns: Array[Dictionary] = []  ## крони кільця для запеченої тіні
var _ring_nodes: Array[Node] = []
var _board_nodes: Array[Node] = []
var _soft_nodes: Array[Node] = []
var _shadow: MeshInstance3D
## Вузол дерева -> {"mmi": MultiMeshInstance3D, "list": Array[Dictionary]} — крони, що розчиняються.
var _canopy: Dictionary = {}
var _under: Array[MultiMeshInstance3D] = []
var _reveal: Array[Vector2i] = []
var _zoom: float = 12.0
var _fade_zoom: float = -100.0  ## зум, з яким розчинення рахували востаннє
## Записи плану дошки після останньої перебудови — для тестів і бюджету.
var board_plan: Array[Dictionary] = []


## `world` — дошка разом із кільцем (Surroundings.world_board), `ring` — ширина кільця;
## клітинка дошки (x, y) лежить у світі на (x + ring, y + ring).
func build(world: Board, world_surface: PackedByteArray, ring: int, board_size: Vector2i, season: StringName, seed: int) -> void:
	var cells: Dictionary = {}
	var wood: Dictionary = {}
	for y in world.height:
		for x in world.width:
			if world.kind_at(Vector2i(x, y)) != Terrain.Kind.FOREST:
				continue
			var c := Vector2i(x - ring, y - ring)
			cells[c] = true
			var i: int = y * world.width + x
			var s: int = world_surface[i] if i < world_surface.size() else 0
			wood[c] = WOOD_OF_SURFACE[clampi(s, 0, WOOD_OF_SURFACE.size() - 1)]
	var signature: String = "%s:%d:%d:%d:%s:%f" % [season, seed, hash(cells.keys()), hash(wood.values()), sun_dir, shadow_strength]
	if signature == _signature:
		return
	_signature = signature
	_cells = cells
	_wood = wood
	_board = Rect2i(Vector2i.ZERO, board_size)
	_world = Rect2i(-Vector2i(ring, ring), Vector2i(world.width, world.height))
	_seed = seed
	if String(season) != _season:
		_season = String(season)
		_load_library()
	_build_ring()
	_rebuild_board()


## Проломи, які знає глядач: перебудова лише якщо вони змінились (порядок ключів — ні).
func set_broken(known: Dictionary) -> void:
	if known.size() == _broken.size() and known.keys().all(func(k: Vector2i) -> bool: return _broken.has(k)):
		return
	_broken = known.duplicate()
	if not _cells.is_empty():
		_rebuild_board()


## Клітинки показаних глядачеві юнітів: крони між ними й камерою стають напівпрозорими.
func set_reveal_cells(cells: Array[Vector2i]) -> void:
	_reveal = cells.duplicate()
	_apply_fade()


## Зум камери (IsoCameraRig.zoom_level): підлісок лише до DETAIL_ZOOM. Розчинення залежить
## від нахилу камери (з зумом), а не від пану — камера не обертається (`_cover`); тож воно
## перераховується лише на помітну зміну зуму, а не на кожен кадр перетягування.
func set_zoom(zoom: float) -> void:
	_zoom = zoom
	for n in _under:
		n.visible = zoom <= DETAIL_ZOOM
	if absf(zoom - _fade_zoom) > FADE_ZOOM_STEP:
		_apply_fade()


func _load_library() -> void:
	_lib.clear()
	_mesh.clear()
	_mat.clear()
	_soft_mat.clear()
	var soft := Shader.new()
	soft.code = _SHADER.code.replace("depth_draw_opaque, ", "").replace(", alpha_to_coverage", "").replace(
			"|| (!shadow_pass && piece_hash > COLOR.a)", "").replace(
			"ROUGHNESS = 1.0;", "ROUGHNESS = 1.0;\n\tALPHA = COLOR.a;").replace(
			"ALPHA = t.a; ALPHA_SCISSOR_THRESHOLD = cut; ALPHA_ANTIALIASING_EDGE = a2c_edge; ALPHA_TEXTURE_COORDINATE = UV * vec2(textureSize(albedo_tex, 0));",
			"if (t.a < cut) { discard; }")
	assert(soft.code.contains("ALPHA = COLOR.a;") and soft.code.contains("if (t.a < cut)"), "шейдер розчинення крон не зібрався: змінився forest_crown.gdshader")
	for path: String in [_DIR + "forest_conifer.glb", _DIR + "forest_broadleaf_%s.glb" % _season]:
		var root: Node = (load(path) as PackedScene).instantiate()
		for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
			var name: String = String(mi.name)
			var base: String = name.trim_suffix("_Shadow")
			if name.begins_with("Hero") or (base.get_slice("_", 0) in TREES and not base in FORMS):
				continue  # поодинокі дерева ставить рука; третя форма породи — лише стенд
			_mesh[name] = mi.mesh
			if not name.ends_with("_Shadow"):
				var a: AABB = mi.mesh.get_aabb()
				_lib[name] = {"h": a.end.y, "half": maxf(maxf(-a.position.x, a.end.x), maxf(-a.position.z, a.end.z))}
			var src: StandardMaterial3D = mi.mesh.surface_get_material(0) as StandardMaterial3D
			for pair: Array in [[_SHADER, _mat], [soft, _soft_mat]]:
				var m := ShaderMaterial.new()
				m.shader = pair[0]
				m.set_shader_parameter("albedo_tex", src.albedo_texture)
				m.set_shader_parameter("alpha_cutoff", src.alpha_scissor_threshold)
				(pair[1] as Dictionary)[mi.mesh] = m
		root.free()
	var g: Node = (load(_DIR + "forest_ground.glb") as PackedScene).instantiate()
	for mi: MeshInstance3D in g.find_children("*", "MeshInstance3D", true, false):
		if String(mi.name) == "Soil_Lane":
			_ground_mesh = mi.mesh
	g.free()


func _wood_at(p: Vector2) -> String:
	return _wood.get(Vector2i(roundi(p.x), roundi(p.y)), "mixed")


func _in_board(p: Vector2) -> bool:
	return p.x >= -0.5 and p.y >= -0.5 and p.x < _board.size.x - 0.5 and p.y < _board.size.y - 0.5


## Відстань від точки до дошки (тайли), 0 — на дошці.
func _board_distance(p: Vector2) -> float:
	var lo := Vector2(-0.5, -0.5)
	return p.distance_to(p.clamp(lo, lo + Vector2(_board.size)))


func _free(nodes: Array[Node]) -> void:
	for n in nodes:
		n.free()
	nodes.clear()


## Кільце: намет проксі-кронами однієї форми на породу, по MultiMesh на (бік, порода).
func _build_ring() -> void:
	_free(_ring_nodes)
	_ring_crowns.clear()
	var groups: Dictionary = {}  ## проксі -> Array[Dictionary]
	for e: Dictionary in ForestScatter.plan(_cells, _wood_at, {}, _season, _seed, _lib):
		var p: Vector2 = e["pos"]
		var species: String = String(e["node"]).get_slice("_", 0)
		var proxy: String = species + "_A_Shadow"
		if _in_board(p) or not species in TREES or not _mesh.has(proxy):
			continue
		var xf: Transform3D = e["xf"]
		if xf.basis.get_scale().y < 0.5:
			continue  # підріст у кільці не видно
		var far: bool = _board_distance(p) > RING_NEAR
		if far and hash(p) % RING_KEEP != 0:
			continue
		var wide: float = RING_WIDE if far else RING_NEAR_WIDE
		xf.basis = xf.basis.scaled(Vector3(wide, 1.0, wide))
		var key: String = proxy
		if not groups.has(key):
			groups[key] = []
		var it: Dictionary = {"xf": _on_ground(xf), "rgb": e["rgb"], "pos": p, "r": float(e["r"]) * wide,
				"top": float(_lib[String(e["node"])]["h"]) * xf.basis.get_scale().y}
		(groups[key] as Array).append(it)
		_ring_crowns.append(it)
	for key: String in groups:
		var mesh: Mesh = _mesh[key]
		var n := _multimesh(mesh, groups[key], _mat[mesh])
		n.name = "Ring_" + key
		_ring_nodes.append(n)


func _rebuild_board() -> void:
	_free(_board_nodes)
	_free(_soft_nodes)
	_canopy.clear()
	_under.clear()
	board_plan.clear()
	# Площа на клітинку ширша за дошку: точки з краю кільця, що зсунулись на дошку, — теж її.
	var area := Rect2i(_board.position - Vector2i.ONE, _board.size + Vector2i(2, 2))
	var groups: Dictionary = {}  ## "клас/вузол" -> Array[Dictionary]
	var lanes: Array[Transform3D] = []
	var crowns: Array[Dictionary] = _ring_crowns.duplicate()
	for e: Dictionary in ForestScatter.plan(_cells, _wood_at, _broken, _season, _seed, _lib, [], area):
		var p: Vector2 = e["pos"]
		if not _in_board(p):
			continue
		board_plan.append(e)
		var xf: Transform3D = _on_ground(e["xf"])
		if e["ground"]:
			lanes.append(xf)
			continue
		var node: String = e["node"]
		if not _mesh.has(node):
			continue
		var top: float = float(_lib[node]["h"]) * xf.basis.get_scale().y
		var tree: bool = node.get_slice("_", 0) in TREES
		var small: String = node.get_slice("_", 0) + "_A_Shadow"
		if top < UNDER_TOP and tree and _mesh.has(small):
			node = small
		var cls: String = "other"
		if tree and top >= UNDER_TOP:
			cls = "canopy"
		elif top < UNDER_TOP and ForestScatter.depth(_cells, p) > UNDER_DEPTH:
			cls = "under"
		var key: String = cls + "/" + node
		if not groups.has(key):
			groups[key] = []
		var it: Dictionary = {"xf": xf, "rgb": e["rgb"], "pos": p, "r": e["r"], "top": top}
		(groups[key] as Array).append(it)
		if cls == "canopy":
			crowns.append(it)
	for key: String in groups:
		var cls: String = key.get_slice("/", 0)
		var node: String = key.get_slice("/", 1)
		var mesh: Mesh = _mesh[node]
		var list: Array = groups[key]
		var n := _multimesh(mesh, list, _mat[mesh])
		n.name = "Forest_" + key.replace("/", "_")
		_board_nodes.append(n)
		if cls == "under":
			n.visible = _zoom <= DETAIL_ZOOM
			_under.append(n)
		if cls == "canopy":
			_canopy[node] = {"mmi": n, "list": list}
	if not lanes.is_empty() and _ground_mesh != null:
		var g := MeshInstance3D.new()
		g.name = "Forest_Soil_Lane"
		g.mesh = _drape(_ground_mesh, lanes)
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(g)
		_board_nodes.append(g)
	_bake_shadow(crowns)
	_apply_fade()


func _multimesh(mesh: Mesh, list: Array, material: Material) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = list.size()
	for i in list.size():
		mm.set_instance_transform(i, list[i]["xf"])
		var c: Color = list[i]["rgb"]
		# Тон крони — у custom data; у кольорі лише розчинення (альфа).
		mm.set_instance_custom_data(i, Color(c.r, c.g, c.b, 1.0))
		mm.set_instance_color(i, Color(1, 1, 1, list[i].get("alpha", 1.0)))
	var n := MultiMeshInstance3D.new()
	n.multimesh = mm
	n.material_override = material
	# Тінь лісу запечена: справжню тінь кидають лише юніти (§8).
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Картки розгортаються в шейдері, тож AABB меша не містить країв пучків.
	n.extra_cull_margin = 0.4
	add_child(n)
	return n


## Запечена тінь лісу: на кожну крону — м'яка пляма, зсунута від сонця на висоту крони ·
## котангенс висоти сонця; маска лягає на землю сіткою по рельєфу напівпрозорим чорним.
## Плями не додаються, а беруть більшу: у зімкнутому лісі тінь одна, а не темніша в кілька шарів.
func _bake_shadow(crowns: Array[Dictionary]) -> void:
	if _shadow != null:
		_shadow.free()
		_shadow = null
	if crowns.is_empty() or shadow_strength <= 0.0:
		return
	var w: int = _world.size.x * SHADOW_PX
	var h: int = _world.size.y * SHADOW_PX
	var mask := PackedFloat32Array()
	mask.resize(w * h)
	var flat := Vector2(sun_dir.x, sun_dir.z)
	var away: Vector2 = -flat.normalized() * flat.length() / maxf(sun_dir.y, 0.2)
	for c: Dictionary in crowns:
		# Центр крони — на ~0,6 висоти дерева; пляма — ~0,8 її радіуса, край м'який.
		var at: Vector2 = (c["pos"] as Vector2) + away * float(c["top"]) * 0.6 - Vector2(_world.position)
		var r: float = float(c["r"]) * 0.8 * SHADOW_PX
		var cx: float = (at.x + 0.5) * SHADOW_PX
		var cy: float = (at.y + 0.5) * SHADOW_PX
		for y in range(maxi(0, floori(cy - r)), mini(h, ceili(cy + r) + 1)):
			for x in range(maxi(0, floori(cx - r)), mini(w, ceili(cx + r) + 1)):
				var d: float = Vector2(x + 0.5 - cx, y + 0.5 - cy).length() / maxf(r, 0.01)
				if d < 1.0:
					var i: int = y * w + x
					mask[i] = maxf(mask[i], smoothstep(1.0, 0.55, d))
	var img := Image.create(w, h, false, Image.FORMAT_L8)
	for y in h:
		for x in w:
			img.set_pixel(x, y, Color(mask[y * w + x], 0, 0))
	for k in SHADOW_BLUR:
		img.resize(w / 2, h / 2, Image.INTERPOLATE_BILINEAR)
		img.resize(w, h, Image.INTERPOLATE_BILINEAR)
	# Сітка лише на тайлах із тінню, квад на тайл, кути — на рельєфі.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n: int = 0
	for ty in _world.size.y:
		for tx in _world.size.x:
			var any: bool = false
			for y in range(ty * SHADOW_PX, (ty + 1) * SHADOW_PX):
				for x in range(tx * SHADOW_PX, (tx + 1) * SHADOW_PX):
					if img.get_pixel(x, y).r > 0.02:
						any = true
						break
				if any:
					break
			if not any:
				continue
			var o := Vector2(_world.position) + Vector2(tx, ty) - Vector2(0.5, 0.5)
			var q: Array[Vector2] = [o, o + Vector2(1, 0), o + Vector2(1, 1), o + Vector2(0, 1)]
			for k: int in [0, 1, 2, 0, 2, 3]:
				st.set_uv((q[k] + Vector2(0.5, 0.5) - Vector2(_world.position)) / Vector2(_world.size))
				st.add_vertex(Vector3(q[k].x, TerrainHeight.ground_y(q[k].x, q[k].y) + SHADOW_LIFT, q[k].y))
			n += 1
	if n == 0:
		return
	var mat := ShaderMaterial.new()
	mat.shader = _shadow_shader()
	mat.set_shader_parameter("mask", ImageTexture.create_from_image(img))
	mat.set_shader_parameter("strength", shadow_strength)
	_shadow = MeshInstance3D.new()
	_shadow.name = "Forest_Shadow"
	_shadow.mesh = st.commit()
	# Раніше за напівпрозорі крони: тінь лягає лише на землю, а не на розчинену крону над нею.
	mat.render_priority = -1
	_shadow.material_override = mat
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shadow)


static var _shadow_shader_cache: Shader


static func _shadow_shader() -> Shader:
	if _shadow_shader_cache == null:
		_shadow_shader_cache = Shader.new()
		# Чорне з прозорістю strength · маска — те саме, що множення кольору землі на (1 − a): тінь
		# лягає й на шрами, колії та просіку. blend_mul на мобільному рендері малювався не множенням.
		_shadow_shader_cache.code = """shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;
uniform sampler2D mask : filter_linear, repeat_disable;
uniform float strength = 0.15;
void fragment() {
	ALBEDO = vec3(0.0);
	ALPHA = strength * texture(mask, UV).r;
}
"""
	return _shadow_shader_cache


## Наскільки крона закриває показаних юнітів: 1 — не закриває, 0 — повністю. `back` — напрям
## від сцени до камери (вісь погляду): він залежить лише від нахилу, тобто від зуму, а не від
## пану, тож розчинення не треба перераховувати, поки гравець тягне камеру.
func _cover(entry: Dictionary, back: Vector3) -> float:
	var a: float = 1.0
	var flat := Vector2(back.x, back.z)
	# Крона заввишки top ховає юніта, стоячи до top · (гориз. / верт. складова погляду) ближче.
	var reach: float = float(entry["top"]) * flat.length() / maxf(back.y, 0.1) + FADE_REACH_EXTRA
	var dir: Vector2 = flat.normalized()
	for c in _reveal:
		var u := Vector2(c)
		var p: Vector2 = entry["pos"]
		var t: float = clampf((p - u).dot(dir), 0.0, reach)
		var r0: float = FADE_RADIUS + float(entry["r"]) + UNIT_HALF
		a = minf(a, smoothstep(r0, r0 + FADE_SOFT, p.distance_to(u + dir * t)))
	return a


func _apply_fade() -> void:
	_fade_zoom = _zoom
	_free(_soft_nodes)
	var cam3d: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	var back: Vector3 = cam3d.global_transform.basis.z if cam3d != null else Vector3.UP
	for node: String in _canopy:
		var mm: MultiMesh = (_canopy[node]["mmi"] as MultiMeshInstance3D).multimesh
		var list: Array = _canopy[node]["list"]
		var faded: Array = []
		for i in list.size():
			var k: float = _cover(list[i], back) if not _reveal.is_empty() else 1.0
			mm.set_instance_color(i, Color(1, 1, 1, 1.0 if k >= 0.999 else 0.0))
			if k < 0.999:
				faded.append({"xf": list[i]["xf"], "rgb": list[i]["rgb"], "alpha": lerpf(FADE_ALPHA, 1.0, k)})
		if not faded.is_empty():
			var mesh: Mesh = _mesh[node]
			var n := _multimesh(mesh, faded, _soft_mat[mesh])
			n.name = "Fade_" + node
			_soft_nodes.append(n)


func _on_ground(xf: Transform3D) -> Transform3D:
	xf.origin.y += TerrainHeight.ground_y(xf.origin.x, xf.origin.z)
	return xf


## Плоский шматок землі не може лишатись пласким квадом: рельєф прорізав би його прямими
## лініями. Усі шматки — один меш, один виклик малювання.
func _drape(src: Mesh, xfs: Array[Transform3D]) -> ArrayMesh:
	var a: Array = src.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for t in uv:
		lo = lo.min(t)
		hi = hi.max(t)
	var corner: Dictionary = {}
	for i in v.size():
		corner[Vector2i(int(uv[i].x > (lo.x + hi.x) * 0.5), int(uv[i].y > (lo.y + hi.y) * 0.5))] = v[i]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base: int = 0
	for xf: Transform3D in xfs:
		for j in DRAPE + 1:
			for i in DRAPE + 1:
				var fx: float = float(i) / DRAPE
				var fy: float = float(j) / DRAPE
				var local: Vector3 = (corner[Vector2i(0, 0)] as Vector3).lerp(corner[Vector2i(1, 0)], fx).lerp(
						(corner[Vector2i(0, 1)] as Vector3).lerp(corner[Vector2i(1, 1)], fx), fy)
				var w: Vector3 = xf * local
				w.y = TerrainHeight.ground_y(w.x, w.z) + DRAPE_LIFT
				st.set_uv(Vector2(lerpf(lo.x, hi.x, fx), lerpf(lo.y, hi.y, fy)))
				st.set_normal(Vector3.UP)
				st.add_vertex(w)
		for j in DRAPE:
			for i in DRAPE:
				var k: int = base + j * (DRAPE + 1) + i
				for idx: int in [k, k + 1, k + DRAPE + 2, k, k + DRAPE + 2, k + DRAPE + 1]:
					st.add_index(idx)
		base += (DRAPE + 1) * (DRAPE + 1)
	var m: ArrayMesh = st.commit()
	m.surface_set_material(0, src.surface_get_material(0))
	return m
