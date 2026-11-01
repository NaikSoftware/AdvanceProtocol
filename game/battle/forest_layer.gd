class_name ForestLayer
extends Node3D
## Ліс на клітинках FOREST дошки й кільця: розкид `ForestScatter.plan()`, форми з бібліотек
## (forest_conifer.glb, forest_broadleaf_<сезон>.glb) злиті в один меш на атлас (`FoliageBatch`).
##
## - Дошка: дерева, кущі, підріст, смуги узлісся, колоди, по дві форми на породу. Проломи — ті,
##   що знає глядач (`BattleState.known_broken_map`), а не правда: інакше ліс видав би, де
##   пройшов ворог. Розкид має зерно на кожну точку, тож новий пролам змінює лише дерева біля нього.
## - Кільце: намет по одній формі на породу сітками проксі (~16 трикутників замість 50–100),
##   далі від дошки — удвічі рідше й ширшими кронами, та сама зімкнутість. Біля дошки
##   (`RING_NEAR`) — ще смуги узлісся й пояс кущів, а листяні в смузі `RING_DETAIL` — справжніми
##   сітками: проксі пожовклої крони з камери читалась пласкою латкою. Туди юніти не заходять.
##   Дошка — один меш на атлас: ~10 тис. трикутників дешевші за зайві виклики.
## - Крони кільця тонуть в імлі (`Surroundings.apply`), як земля й будинки.
## - Понад `DETAIL_ZOOM` підлісок під наметом не малюється: з такої висоти його не видно.
## - Підріст і низькі дерева (нижче `UNDER_TOP`) — однією сіткою проксі на породу: з такої
##   висоти пучків не розрізнити, а вони найчисленніші.
## - Тінь лісу запечена (§8: справжню тінь кидають лише юніти): маска плям крон у напрямку сонця
##   карти лягає на землю одним напівпрозорим шаром (`_bake_shadow`).
## - Усе листя (крони, узлісся, кущі, підріст — дошки й кільця) між камерою й показаним юнітом
##   стає напівпрозорим — цілими деревами й кущами, без растру; показані — ті самі, що й під
##   дахами (`set_reveal_cells`), тож невидимий ворог себе не видає.

const _SHADER: Shader = preload("res://assets/props/forest/forest_crown.gdshader")
const _DIR: String = "res://assets/props/forest/"
## Типовий зум гри — 12 (IsoCameraRig.zoom_level); до цього зуму включно ліс повний.
const DETAIL_ZOOM: float = 15.0
## Розчинення над юнітом — лише крони, що на екрані справді його перекривають: центр крони в
## циліндрі вздовж променя «юніт → камера» радіусом у півсилует юніта (`UNIT_HALF`) плюс
## `FADE_MARGIN`, і лише на тій відстані вздовж променя, де він проходить крізь висоту крони (від
## `CROWN_LOW` висоти дерева до верху; нижня частина крони — рідкі гілочки): 1–4 дерева на юніта. Ширший вибір (радіус крони й поле
## довкола клітинки) розчиняв шмат лісу 6 × 4 клітинки — пляму-«привид» довкола юніта.
const UNIT_HALF: float = 0.25
const FADE_MARGIN: float = 0.1
const CROWN_LOW: float = 0.5
const FADE_SOFT: float = 0.08
const FADE_ALPHA: float = 0.35
## Розчинення перераховується, коли зум змінився більше ніж на стільки.
const FADE_ZOOM_STEP: float = 0.5
## Склад лісу клітинки за MapData.ForestSurface (MIXED, PINE, DECIDUOUS).
const WOOD_OF_SURFACE: PackedStringArray = ["mixed", "pine", "deciduous"]
const TREES: PackedStringArray = ["Pine", "Spruce", "Birch", "Oak"]
## Форми порід у бою: по дві на породу (кожна форма — виклик малювання).
## `*_R` — лише в бібліотеці пізньої осені: листяні, що ще тримають буре листя.
const FORMS: PackedStringArray = ["Pine_A", "Pine_B", "Spruce_A", "Spruce_B", "Birch_A", "Birch_B", "Oak_A", "Oak_B", "Birch_R", "Oak_R"]
const BROADLEAF: PackedStringArray = ["Birch", "Oak"]
## Нижче цієї висоти (тайли) і глибше `UNDER_DEPTH` у лісі — підлісок під наметом.
const UNDER_TOP: float = 0.45
const UNDER_DEPTH: float = 0.7
## Кільце: у смузі `RING_NEAR` клітинок від дошки (її камера бачить біля краю) — повна густота,
## крона ширша в `RING_NEAR_WIDE` раза (у кільці немає поясу кущів, смуг узлісся й підросту, що на
## дошці закривають просвіти); далі кожне друге дерево з кроною, ширшою ще в √2 раза.
const RING_NEAR: float = 5.0
## Смуга кільця з узліссям і поясом кущів (її камера бачить біля краю дошки) і смуга, де листяні
## в сезон листя — справжніми сітками (голі дерева пізньої осені проксі передають і так).
const RING_EDGE: float = 3.0
const RING_DETAIL: float = 1.5
## Розчиняється листя від цієї висоти (тайли, ~1,6 м): нижчий підріст юніта не ховає, а кожна
## група розчинення — виклик малювання.
const FADE_MIN_TOP: float = 0.2
## Новий пролам перепланує лише клітинки в межах стількох від зміни (ForestScatter.LANE_NEAR + крона).
## Напівширина просіки й смуга розрідження за нею, тайли (1 тайл ≈ 8 м): вісім метрів в обидва боки.
const CORRIDOR_HALF: float = 1.0
const CORRIDOR_FEATHER: float = 0.6
## Зазор між краєм крони й проводом: дерево з широкою кроною (проксі кільця) просіка відсуває далі за CORRIDOR_HALF.
const CROWN_MARGIN: float = 0.6
## Висота проводу над землею (тайли) і частка висоти дерева, де кінчається голий стовбур: крона, що лежить за
## проводом ближче до камери, на екрані перекриває його — вище точка зсувається в плані вглиб, на висоту·ctg(нахилу).
const WIRE_HEIGHT: float = 1.2
const TRUNK_FRAC: float = 0.35
## Низьким вважається підлісок не вищий за стільки (тайли): йому просіка не дає півширини крони, лише дивиться, де він
## лежить на екрані відносно дроту.
const LOW_KEEP: float = 0.4
const REPLAN_MARGIN: int = 3
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
## Проліти ЛЕП (PropLayer.span_lines(), тайли дошки): уздовж них ліс вирубано смугою, а підлісок
## і кущі лишаються — справжні лінії йдуть через ліс просікою.
var spans: Array = []
## Прямокутники XZ секцій парканів (VegetationLayer.obstacles): крона не нависає над жодною.
var fences: Array[Rect2] = []

var _season: String = ""
var _seed: int = 0
var _cells: Dictionary = {}  ## Vector2i -> true: увесь ліс (дошка й кільце), координати дошки
var _wood: Dictionary = {}  ## Vector2i -> склад лісу
var _board := Rect2i()
var _world := Rect2i()  ## дошка разом із кільцем, координати дошки
var _lib: Dictionary = {}  ## ім'я вузла -> {"h", "half"}
var _mesh: Dictionary = {}  ## ім'я вузла -> Mesh (і проксі `<вузол>_Shadow`)
## Злиті сітки: шейдер із таблицею даних екземплярів і поріг альфи на атлас.
var _batch_shader: Shader
var _atlas_cut: Dictionary = {}
## Розчинення: атлас -> ShaderMaterial прохід лише глибини, а в його next_pass — прохід кольору
## з прозорістю. Mesh -> атлас; Mesh -> масиви поверхні (для злиття розчинених екземплярів).
var _fade_mat: Dictionary = {}
var _atlas_of: Dictionary = {}
var _arrays: Dictionary = {}
var _ground_mesh: Mesh
var _signature: String = ""
var _broken: Dictionary = {}
var _ring: int = 0
var _ring_crowns: Array[Dictionary] = []  ## крони кільця для запеченої тіні
## Групи листя, що розчиняються: {"mmi" (вузол батча), "batch", "first" (номер першого
## екземпляра групи в батчі), "list", "mesh"} — кільця й дошки.
var _ring_fadable: Array[Dictionary] = []
var _fadable: Array[Dictionary] = []
var _ring_nodes: Array[Node] = []
var _board_nodes: Array[Node] = []
var _soft_nodes: Array[Node] = []
var _shadow: MeshInstance3D
var _under: Array[Node3D] = []
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
	var signature: String = "%s:%d:%d:%d:%s:%f:%d:%d" % [season, seed, hash(cells.keys()), hash(wood.values()), sun_dir, shadow_strength, hash(spans), hash(fences)]
	if signature == _signature:
		return
	_signature = signature
	_cells = cells
	_wood = wood
	_board = Rect2i(Vector2i.ZERO, board_size)
	_world = Rect2i(-Vector2i(ring, ring), Vector2i(world.width, world.height))
	_ring = ring
	_seed = seed
	if String(season) != _season:
		_season = String(season)
		_load_library()
	if ring > 0:
		var mats: Array = []
		for fm: ShaderMaterial in _fade_mat.values():
			mats.append_array([fm, fm.next_pass])
		for m: ShaderMaterial in mats:
			Surroundings.apply(m, board_size)
	_build_ring()
	_rebuild_board()


## Проломи, які знає глядач: перебудова лише якщо вони змінились (порядок ключів — ні).
func set_broken(known: Dictionary) -> void:
	if known.size() == _broken.size() and known.keys().all(func(k: Vector2i) -> bool: return _broken.has(k)):
		return
	# Перепланується лише ділянка навколо змінених клітинок: пролам змінює дерева не далі
	# `ForestScatter.LANE_NEAR` + крона (~3 клітинки), а весь план дошки — ривок посеред руху танка.
	var changed: Array[Vector2i] = []
	for c: Vector2i in known:
		if not _broken.has(c):
			changed.append(c)
	for c: Vector2i in _broken:
		if not known.has(c):
			changed.append(c)
	_broken = known.duplicate()
	if _cells.is_empty():
		return
	var region := Rect2i(changed[0], Vector2i.ONE)
	for c in changed:
		region = region.expand(c).expand(c + Vector2i.ONE)
	_rebuild_board(region.grow(REPLAN_MARGIN))


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
	_fade_mat.clear()
	_atlas_cut.clear()
	_atlas_of.clear()
	_arrays.clear()
	# Розчинення: розчинені екземпляри всіх форм одного атласу — одна злита сітка (тон — у CUSTOM0,
	# прозорість — в альфі кольору вершини). Два проходи: спершу лише глибина розчинених крон,
	# потім колір із прозорістю — проходить лише найближча поверхня, тож над юнітом лягає один
	# шар 30–40 %, а не стос із трьох-чотирьох крон, крізь який юніта вже не видно.
	var color_code: String = _replace_checked(_SHADER.code, [
			["depth_draw_opaque, ", ""], [", alpha_to_coverage", ""],
			["|| (!shadow_pass && piece_hash > COLOR.a)", ""],
			["ROUGHNESS = 1.0;", "ROUGHNESS = 1.0;\n\tALPHA = COLOR.a;"],
			["ALPHA = t.a; ALPHA_SCISSOR_THRESHOLD = cut; ALPHA_ANTIALIASING_EDGE = a2c_edge; ALPHA_TEXTURE_COORDINATE = UV * vec2(textureSize(albedo_tex, 0));", "if (t.a < cut) { discard; }"],
			["inst_tone = dot(INSTANCE_CUSTOM.rgb, INSTANCE_CUSTOM.rgb) > 0.0 ? INSTANCE_CUSTOM.rgb : vec3(1.0);", "inst_tone = CUSTOM0.rgb;"]])
	var depth_code: String = _replace_checked(color_code, [
			["render_mode cull_disabled, skip_vertex_transform", "render_mode cull_disabled, depth_draw_always, skip_vertex_transform"],
			["ALPHA = COLOR.a;", "ALPHA = 0.0;"]])
	# Злита сітка: тон, масштаб картки й видимість екземпляра беруться з таблиці за номером у
	# CUSTOM0.x (у MultiMesh це були б INSTANCE_CUSTOM і масштаб матриці).
	var fetch: String = FoliageBatch.glsl_fetch() + "\n\tinst_tone = batch_a.rgb;\n\tCOLOR.a *= batch_a.a;"
	_batch_shader = Shader.new()
	_batch_shader.code = _replace_checked(_SHADER.code, [
			["varying flat float piece_hash;", "varying flat float piece_hash;\n" + FoliageBatch.glsl_decl()],
			["inst_tone = dot(INSTANCE_CUSTOM.rgb, INSTANCE_CUSTOM.rgb) > 0.0 ? INSTANCE_CUSTOM.rgb : vec3(1.0);", fetch],
			["float s = length(MODEL_MATRIX[0].xyz);", "float s = batch_scale;"]])
	var color_shader := Shader.new()
	color_shader.code = color_code
	var depth_shader := Shader.new()
	depth_shader.code = depth_code
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
			_atlas_of[mi.mesh] = src.albedo_texture
			_atlas_cut[src.albedo_texture] = src.alpha_scissor_threshold
			if not _fade_mat.has(src.albedo_texture):
				var color := ShaderMaterial.new()
				color.shader = color_shader
				var depth := ShaderMaterial.new()
				depth.shader = depth_shader
				depth.render_priority = -1
				depth.next_pass = color
				for fm: ShaderMaterial in [color, depth]:
					fm.set_shader_parameter("albedo_tex", src.albedo_texture)
					fm.set_shader_parameter("alpha_cutoff", src.alpha_scissor_threshold)
				_fade_mat[src.albedo_texture] = depth
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


## Запис плану після просіки під прольотом ЛЕП: дерево в смузі напівширини CORRIDOR_HALF заміщене
## низьким кущем (смуга не лисіє), у смузі розрідження за нею частину дерев пропущено, решта —
## як було. Порожній словник — запису нема. Відводи до хат сюди не входять: ліс вони не рубають.
## widen — у скільки разів проксі розширить крону пізніше (кільце): просіка рахується за кроною, яку побачать.
func _cleared(e: Dictionary, widen: float = 1.0) -> Dictionary:
	var node: String = e["node"]
	if not e["ground"] and fences.any(func(r: Rect2) -> bool:
			return VegetationLayer._rect_dist(r, e["pos"]) < float(e["r"]) + VegetationLayer.FENCE_CROWN_PAD):
		return {}
	var species: String = node.get_slice("_", 0)
	if spans.is_empty() or e["ground"] or not (species in TREES or species == "Shrub" or species == "Hedge") or not _lib.has(node):
		return e
	var p: Vector2 = e["pos"]
	var top: float = float(_lib[node]["h"]) * e["xf"].basis.get_scale().y
	var d: float = _sweep_to_spans(p, top)
	# Низький підлісок не має півширини просіки: його ховає лише те, що він на екрані лежить під проводом.
	var half: float = float(e["r"]) * widen + CROWN_MARGIN
	if top > LOW_KEEP:
		half = maxf(CORRIDOR_HALF, half)
	if d >= half + CORRIDOR_FEATHER:
		return e
	var u: float = float(absi(hash(p)) % 1000) / 1000.0
	if d >= half:
		# Край смуги тоншає поступово: що ближче до просіки, то менше дерев лишається.
		return e if u < (d - half) / CORRIDOR_FEATHER else {}
	if top <= LOW_KEEP:
		return {}
	var shrubs: Array[String] = []
	for k: String in _lib:
		if k.begins_with("Shrub_"):
			shrubs.append(k)
	if shrubs.is_empty():
		return {}
	shrubs.sort()
	var out: Dictionary = e.duplicate()
	out["node"] = shrubs[int(u * 997.0) % shrubs.size()]
	out["xf"] = Transform3D(Basis(Vector3.UP, u * TAU), (e["xf"] as Transform3D).origin)
	out["r"] = 0.3
	# Кущ замість дерева теж не лягає під дріт на екрані.
	var sd: float = _sweep_to_spans(p, float(_lib[out["node"]]["h"]))
	return out if sd >= float(out["r"]) + CROWN_MARGIN else {}


## Найменша відстань у плані від зсуву крони (з основою в p, заввишки top) до проліту: так, як вона лежить на екрані.
func _sweep_to_spans(p: Vector2, top: float) -> float:
	var sh: Vector2 = crown_shift(top)
	var fwd: Vector2 = _view_fwd()
	var d: float = INF
	for w: Array in spans:
		if p.distance_to(Geometry2D.get_closest_point_to_segment(p, w[0], w[1])) > 8.0:
			continue
		d = minf(d, _sweep_dist(p + fwd * sh.x, p + fwd * sh.y, w[0], w[1]))
	return d


## Клітинка лісу, з якої просіка зняла все, лишається лісом: один кущ — той, що найдалі від проводу на екрані, —
## повертається (cover), щоб клітина не читалась лугом (рід місцевості видно з кожної клітинки).
func _keep_cover(plan: Array[Dictionary], lost: Array[Dictionary]) -> void:
	var has: Dictionary = {}
	for e: Dictionary in plan:
		if not e["ground"]:
			has[Vector2i(roundi(e["pos"].x), roundi(e["pos"].y))] = true
	var best: Dictionary = {}
	for e: Dictionary in lost:
		var c := Vector2i(roundi(e["pos"].x), roundi(e["pos"].y))
		if has.has(c) or e["ground"] or fences.any(func(r: Rect2) -> bool:
				return VegetationLayer._rect_dist(r, e["pos"]) < float(e["r"]) + VegetationLayer.FENCE_CROWN_PAD):
			continue
		if spans.all(func(w: Array) -> bool: return Vector2(c).distance_to(Geometry2D.get_closest_point_to_segment(Vector2(c), w[0], w[1])) >= 1.5):
			continue
		var d: float = _sweep_to_spans(e["pos"], float(_lib[e["node"]]["h"]) * e["xf"].basis.get_scale().y) if _lib.has(e["node"]) else 0.0
		if not best.has(c) or d > float(best[c][0]):
			best[c] = [d, e]
	var shrub: String = ""
	for k: String in _lib:
		if k.begins_with("Shrub_") and (shrub.is_empty() or k < shrub):
			shrub = k
	if shrub.is_empty():
		return
	for c: Vector2i in best:
		var out: Dictionary = (best[c][1] as Dictionary).duplicate()
		out["node"] = shrub
		out["xf"] = Transform3D(Basis.IDENTITY, ((best[c][1] as Dictionary)["xf"] as Transform3D).origin)
		out["r"] = 0.3
		out["cover"] = true
		plan.append(out)


## Напрям погляду камери в плані: від камери вглиб.
static func _view_fwd() -> Vector2:
	var yaw: float = deg_to_rad(IsoCameraRig.YAW_DEGREES)
	return -Vector2(sin(yaw), cos(yaw))


## Межі зсуву крони дерева заввишки top на екрані відносно проводу вздовж _view_fwd (тайли в плані): від низу крони до
## верху за найнижчого нахилу рига (там крони «лежать» найдалі); 0 — сама земля — завжди всередині.
static func crown_shift(top: float) -> Vector2:
	var cot: float = 1.0 / tan(deg_to_rad(IsoCameraRig.PITCH_NEAR_DEG))
	if top <= LOW_KEEP:
		# Низький кущ — весь від землі; його місце на екрані — лише тіло, без запасу на землю під ним.
		return Vector2(-WIRE_HEIGHT * cot, (top - WIRE_HEIGHT) * cot)
	return Vector2(minf((TRUNK_FRAC * top - WIRE_HEIGHT) * cot, 0.0), maxf((top - WIRE_HEIGHT) * cot, 0.0))


## Найменша відстань між відрізками a–b та c–d.
static func _sweep_dist(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> float:
	if Geometry2D.segment_intersects_segment(a, b, c, d) != null:
		return 0.0
	return minf(minf(a.distance_to(Geometry2D.get_closest_point_to_segment(a, c, d)), b.distance_to(Geometry2D.get_closest_point_to_segment(b, c, d))),
			minf(c.distance_to(Geometry2D.get_closest_point_to_segment(c, a, b)), d.distance_to(Geometry2D.get_closest_point_to_segment(d, a, b))))


## Відстань від точки до дошки (тайли), 0 — на дошці.
func _board_distance(p: Vector2) -> float:
	var lo := Vector2(-0.5, -0.5)
	return p.distance_to(p.clamp(lo, lo + Vector2(_board.size)))


func _free(nodes: Array[Node]) -> void:
	for n in nodes:
		n.free()
	nodes.clear()


## Кільце: намет проксі-кронами однієї форми на породу; біля дошки — узлісся, пояс кущів і
## листяні справжніми сітками. Власний батч, будується раз.
func _build_ring() -> void:
	_free(_ring_nodes)
	_ring_crowns.clear()
	_ring_fadable.clear()
	var groups: Dictionary = {}  ## вузол -> Array[Dictionary]
	for e: Dictionary in ForestScatter.plan(_cells, _wood_at, {}, _season, _seed, _lib):
		var p: Vector2 = e["pos"]
		var node: String = e["node"]
		if _in_board(p) or e["ground"] or not _lib.has(node):
			continue
		e = _cleared(e, RING_WIDE)
		if e.is_empty():
			continue
		node = e["node"]
		var species: String = node.get_slice("_", 0)
		var d: float = _board_distance(p)
		var xf: Transform3D = e["xf"]
		var top: float = float(_lib[node]["h"]) * xf.basis.get_scale().y
		var key: String = ""
		var crown: bool = false
		if species in TREES and top >= UNDER_TOP:
			crown = true
			if species in BROADLEAF and d <= RING_DETAIL and node in FORMS and _season != "late":
				key = node
			else:
				key = species + "_A_Shadow"
				var far: bool = d > RING_NEAR
				if far and hash(p) % RING_KEEP != 0:
					continue
				var wide: float = RING_WIDE if far else RING_NEAR_WIDE
				xf.basis = xf.basis.scaled(Vector3(wide, 1.0, wide))
		elif d <= RING_EDGE and species == "Hedge":
			key = node
		elif d <= RING_EDGE and top < UNDER_TOP and ForestScatter.depth(_cells, p) <= UNDER_DEPTH:
			# Пояс кущів на краю лісу кільця; підріст під наметом кільця не видно.
			key = (species + "_A_Shadow") if species in TREES else node + "_Shadow"
		if key.is_empty() or not _mesh.has(key):
			continue
		if not groups.has(key):
			groups[key] = []
		var it: Dictionary = {"xf": _on_ground(xf), "rgb": e["rgb"], "pos": p, "r": float(e["r"]) * xf.basis.get_scale().x / maxf(e["xf"].basis.get_scale().x, 1e-3),
				"top": top}
		(groups[key] as Array).append(it)
		if crown:
			_ring_crowns.append(it)
	var entries: Array[Dictionary] = []
	for key: String in groups:
		entries.append({"mesh": _mesh[key], "list": groups[key]})
	# Кільце статичне: власна сітка, щоб кожен пролам не зливав його наново разом із дошкою.
	_ring_fadable.append_array(_batch("Ring", entries, _ring_nodes))


## `region` (клітинки) — перепланувати лише її, решту плану взяти з попереднього; порожня —
## увесь план дошки.
func _rebuild_board(region: Rect2i = Rect2i()) -> void:
	_free(_board_nodes)
	_free(_soft_nodes)
	_fadable.clear()
	_under.clear()
	var plan: Array[Dictionary] = []
	var lost: Array[Dictionary] = []
	if region.has_area() and not board_plan.is_empty():
		# Ділянка в тайлах: клітинка c — [c − 0,5; c + 0,5). Площа плану на клітинку ширша: точки
		# з-за краю ділянки, що зсунулись у неї, — теж її.
		var rr := Rect2(Vector2(region.position) - Vector2(0.5, 0.5), Vector2(region.size))
		for e: Dictionary in board_plan:
			if not rr.has_point(e["pos"]):
				plan.append(e)
		for e: Dictionary in ForestScatter.plan(_cells, _wood_at, _broken, _season, _seed, _lib, [], region.grow(1)):
			if rr.has_point(e["pos"]) and _in_board(e["pos"]):
				var c: Dictionary = _cleared(e)
				if c.is_empty():
					lost.append(e)
				else:
					plan.append(c)
	else:
		# Площа на клітинку ширша за дошку: точки з краю кільця, що зсунулись на дошку, — теж її.
		var area := Rect2i(_board.position - Vector2i.ONE, _board.size + Vector2i(2, 2))
		for e: Dictionary in ForestScatter.plan(_cells, _wood_at, _broken, _season, _seed, _lib, [], area):
			if _in_board(e["pos"]):
				var c: Dictionary = _cleared(e)
				if c.is_empty():
					lost.append(e)
				else:
					plan.append(c)
	_keep_cover(plan, lost)
	board_plan = plan
	var groups: Dictionary = {}  ## "клас/вузол" -> Array[Dictionary]
	var lanes: Array[Transform3D] = []
	var crowns: Array[Dictionary] = _ring_crowns.duplicate()
	for e: Dictionary in board_plan:
		var p: Vector2 = e["pos"]
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
	var main_entries: Array[Dictionary] = []
	var under_entries: Array[Dictionary] = []
	for key: String in groups:
		var entry: Dictionary = {"mesh": _mesh[key.get_slice("/", 1)], "list": groups[key]}
		(under_entries if key.get_slice("/", 0) == "under" else main_entries).append(entry)
	_fadable.append_array(_batch("Forest", main_entries, _board_nodes))
	for g: Dictionary in _batch("Forest_under", under_entries, _board_nodes):
		(g["mmi"] as Node3D).visible = _zoom <= DETAIL_ZOOM
		if not _under.has(g["mmi"]):
			_under.append(g["mmi"])
		_fadable.append(g)
	if not lanes.is_empty() and _ground_mesh != null:
		var g := MeshInstance3D.new()
		g.name = "Forest_Soil_Lane"
		g.mesh = _drape(_ground_mesh, lanes)
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(g)
		_board_nodes.append(g)
	_bake_shadow(crowns)
	_apply_fade()


## Усе листя шару одним мешем на атлас, а не MultiMesh на форму: кожна форма була окремим викликом
## малювання. Вершини екземплярів переносяться у світ масово (`Transform3D * Packed…`), тож
## перебудова дошки після пролому — десятки мілісекунд. Повертає групи для розчинення: номер першого
## екземпляра групи в батчі лежить у "first".
func _batch(label: String, entries: Array[Dictionary], nodes: Array[Node]) -> Array[Dictionary]:
	var by_atlas: Dictionary = {}  ## атлас -> Array[Dictionary]
	for e: Dictionary in entries:
		var atlas: Texture2D = _atlas_of[e["mesh"]]
		if not by_atlas.has(atlas):
			by_atlas[atlas] = []
		if not _arrays.has(e["mesh"]):
			_arrays[e["mesh"]] = (e["mesh"] as Mesh).surface_get_arrays(0)
		e["arrays"] = _arrays[e["mesh"]]
		(by_atlas[atlas] as Array).append(e)
	var out: Array[Dictionary] = []
	var k: int = 0
	for atlas: Texture2D in by_atlas:
		var total: int = 0
		for e: Dictionary in by_atlas[atlas]:
			total += (e["list"] as Array).size()
		if total == 0:
			continue
		var batch: FoliageBatch = FoliageBatch.create(total)
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, batch.merge(by_atlas[atlas], true), [], {}, FoliageBatch.custom_flags())
		batch.texture.update(batch.image)
		var mat := ShaderMaterial.new()
		mat.shader = _batch_shader
		mat.set_shader_parameter("albedo_tex", atlas)
		mat.set_shader_parameter("alpha_cutoff", _atlas_cut[atlas])
		mat.set_shader_parameter("inst_data", batch.texture)
		if _ring > 0:
			Surroundings.apply(mat, _board.size)
		var n := MeshInstance3D.new()
		n.name = "%s_%d" % [label, k]
		k += 1
		n.mesh = m
		n.material_override = mat
		# Тінь лісу запечена: справжню тінь кидають лише юніти (§8).
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Картки розгортаються в шейдері, тож AABB меша не містить країв пучків.
		n.extra_cull_margin = 0.4
		add_child(n)
		nodes.append(n)
		for e: Dictionary in by_atlas[atlas]:
			out.append({"mmi": n, "batch": batch, "first": e["first"], "list": e["list"], "mesh": e["mesh"]})
	return out


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
	if _ring > 0:
		Surroundings.apply(mat, _board.size)
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
#include "res://game/battle/shaders/surroundings.gdshaderinc"
uniform sampler2D mask : filter_linear, repeat_disable;
uniform float strength = 0.15;
varying vec3 world_pos;
void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	ALBEDO = vec3(0.0);
	ALPHA = strength * texture(mask, UV).r;
	// Під імлою кільця тіні немає: темна пляма крізь імлу читалась би брудом.
	if (surround) {
		ALPHA *= 1.0 - fog_bank(world_pos, CAMERA_POSITION_WORLD, normalize(-INV_VIEW_MATRIX[2].xz)).a;
	}
}
"""
	return _shadow_shader_cache


## Наскільки крона закриває показаних юнітів: 1 — не закриває, 0 — повністю. `back` — напрям
## від сцени до камери (вісь погляду): він залежить лише від нахилу, тобто від зуму, а не від
## пану, тож розчинення не треба перераховувати, поки гравець тягне камеру.
func _cover(entry: Dictionary, back: Vector3) -> float:
	var a: float = 1.0
	var flat := Vector2(back.x, back.z)
	var dir: Vector2 = flat.normalized()
	# Висота променя над землею на кожну клітинку вздовж погляду; без нахилу (погляд згори) — без
	# перевірки висоти: крона закриває юніта, лише стоячи над ним.
	var slope: float = back.y / flat.length() if flat.length() > 0.05 else -1.0
	var p: Vector2 = entry["pos"]
	var top: float = entry["top"]
	var reach: float = FADE_MARGIN + UNIT_HALF
	for c in _reveal:
		var u := Vector2(c)
		var t: float = 0.0
		if slope > 0.0:
			t = (p - u).dot(dir)
			var y: float = t * slope
			if t < 0.0 or y < top * CROWN_LOW - 0.1 or y > top:
				continue  # позаду юніта або промінь іде під кроною чи над нею
		var d: float = p.distance_to(u + dir * t)
		a = minf(a, smoothstep(reach, reach + FADE_SOFT, d))
	return a


func _apply_fade() -> void:
	_fade_zoom = _zoom
	_free(_soft_nodes)
	var cam3d: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	var back: Vector3 = cam3d.global_transform.basis.z if cam3d != null else Vector3.UP
	var faded: Dictionary = {}  ## атлас -> Array[{mesh, xf, rgb, alpha}]
	for g: Dictionary in _ring_fadable + _fadable:
		var batch: FoliageBatch = g["batch"]
		var list: Array = g["list"]
		# Альфа екземплярів зберігається і тут: тести читають її, не зазираючи в таблицю батча.
		var alpha := PackedFloat32Array()
		alpha.resize(list.size())
		for i in list.size():
			var k: float = _cover(list[i], back) if not _reveal.is_empty() and float(list[i]["top"]) >= FADE_MIN_TOP else 1.0
			alpha[i] = 1.0 if k >= 0.999 else 0.0
			batch.set_alive(int(g["first"]) + i, alpha[i] >= 1.0)
			if k < 0.999:
				var atlas: Texture2D = _atlas_of[g["mesh"]]
				if not faded.has(atlas):
					faded[atlas] = []
				(faded[atlas] as Array).append({"mesh": g["mesh"], "xf": list[i]["xf"], "rgb": list[i]["rgb"], "alpha": lerpf(FADE_ALPHA, 1.0, k)})
		g["alpha"] = alpha
	for g: Dictionary in _ring_fadable + _fadable:
		(g["batch"] as FoliageBatch).upload()
	_show_fade(faded)


## Прогрів за гейтом (BattleScreen._warm_board): розчинена крона кожного атласу — найближча до
## `near` — показана, щоб прохід глибини й колір розчинення скомпілювались до першого юніта під
## кроною. Повертає клітинку крони (−1, −1 — лісу немає); показане скидає set_reveal_cells.
func warm_fade(near: Vector2i) -> Vector2i:
	var pick: Dictionary = {}  ## атлас -> [відстань², запис]
	for g: Dictionary in _fadable:
		var atlas: Texture2D = _atlas_of[g["mesh"]]
		for it: Dictionary in g["list"]:
			if float(it["top"]) < FADE_MIN_TOP:
				continue
			var d: float = (it["pos"] as Vector2).distance_squared_to(Vector2(near))
			if not pick.has(atlas) or d < float(pick[atlas][0]):
				pick[atlas] = [d, {"mesh": g["mesh"], "xf": it["xf"], "rgb": it["rgb"], "alpha": FADE_ALPHA, "pos": it["pos"]}]
	_free(_soft_nodes)
	var faded: Dictionary = {}
	var cell := Vector2i(-1, -1)
	for atlas: Texture2D in pick:
		var it: Dictionary = pick[atlas][1]
		faded[atlas] = [it]
		var p: Vector2 = it["pos"]
		cell = Vector2i(roundi(p.x), roundi(p.y))
	_show_fade(faded)
	return cell


func _show_fade(faded: Dictionary) -> void:
	var idx: int = 0
	for atlas: Texture2D in faded:
		var n := MeshInstance3D.new()
		n.name = "Fade_%d" % idx
		idx += 1
		n.mesh = _fade_mesh(faded[atlas])
		n.material_override = _fade_mat[atlas]
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.extra_cull_margin = 0.4
		n.set_meta("alphas", (faded[atlas] as Array).map(func(it: Dictionary) -> float: return it["alpha"]))
		add_child(n)
		_soft_nodes.append(n)


## Розчинені екземпляри одного атласу — одна сітка у світових координатах: вершини й нормалі
## перетворені, зсув кута картки (UV2) помножено на горизонтальний масштаб екземпляра (шейдер
## множить на масштаб моделі, а в злитої сітки він 1), тон — у CUSTOM0, прозорість — в альфі кольору.
func _fade_mesh(items: Array) -> ArrayMesh:
	var v := PackedVector3Array()
	var nrm := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var col := PackedColorArray()
	var tone := PackedFloat32Array()
	var idx := PackedInt32Array()
	for it: Dictionary in items:
		var mesh: Mesh = it["mesh"]
		if not _arrays.has(mesh):
			_arrays[mesh] = mesh.surface_get_arrays(0)
		var a: Array = _arrays[mesh]
		var xf: Transform3D = it["xf"]
		var s: float = xf.basis.x.length()
		var rgb: Color = it["rgb"]
		var base: int = v.size()
		var src_v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var src_n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var src_uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
		var src_uv2: PackedVector2Array = a[Mesh.ARRAY_TEX_UV2]
		var src_c: PackedColorArray = a[Mesh.ARRAY_COLOR]
		for i in src_v.size():
			v.append(xf * src_v[i])
			nrm.append((xf.basis * src_n[i]).normalized())
			uv.append(src_uv[i])
			uv2.append(src_uv2[i] * s)
			var c: Color = src_c[i] if not src_c.is_empty() else Color.WHITE
			col.append(Color(c.r, c.g, c.b, float(it["alpha"])))
			tone.append_array([rgb.r, rgb.g, rgb.b, 1.0])
		for i: int in a[Mesh.ARRAY_INDEX]:
			idx.append(base + i)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = nrm
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_COLOR] = col
	arrays[Mesh.ARRAY_CUSTOM0] = tone
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {},
			Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	return m


## Шейдер розчинення збирається заміною рядків forest_crown.gdshader; заміна, що не знайшла
## рядка, — помилка навіть у релізі (assert у релізі зникає), і ліс тоді лишається без розчинення.
static func _replace_checked(code: String, pairs: Array) -> String:
	for pair: Array in pairs:
		if not code.contains(pair[0]):
			push_error("ForestLayer: у forest_crown.gdshader немає рядка «%s» — шейдер розчинення не зібрано" % pair[0])
			continue
		code = code.replace(pair[0], pair[1])
	return code


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
