extends GutTest

## Довжина — рівно переправа на карті River (клітинок); зруйнований стан не довший за неї.
const BRIDGES: Dictionary = {
	"bridge_river_centre": 3, "bridge_river_west": 2, "bridge_river_east": 2,
}
const TRIS_MAX: int = 1500
## Крила устоїв центрального мосту виходять за край переправи в насип (build_bridges.py, WING).
const WING: float = 0.15
const GROUND_TOLERANCE: float = 0.02
## Уламки можуть зсунутись за течією за клітинку мосту, але не далі за сусідню.
const HALF_WIDTH_MAX: float = 0.75
## Понтон плаває за 0.075 над дном, тож рештки відсіку можуть сидіти нижче нуля моделі, не пробиваючи русла.
const BROKEN_BELOW_GROUND: Dictionary = {"bridge_river_east": 0.1}

func _bounds(name: String) -> Dictionary:
	var scene: PackedScene = load("res://assets/props/%s.glb" % name) as PackedScene
	assert_not_null(scene, "нема assets/props/%s.glb" % name)
	var root: Node3D = scene.instantiate()
	add_child_autofree(root)
	var box := AABB()
	var first := true
	var tris: int = 0
	for m: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = m.global_transform * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
		for s in m.mesh.get_surface_count():
			tris += (m.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return {"box": box, "tris": tris}

func test_intact_bridge_has_exact_length_and_sits_on_ground(p = use_parameters(BRIDGES.keys())) -> void:
	var r: Dictionary = _bounds(p)
	var box: AABB = r["box"]
	assert_almost_eq(box.position.y, 0.0, GROUND_TOLERANCE, "%s: має стояти на y = 0" % p)
	assert_lte(box.size.z, float(BRIDGES[p]) + 2.0 * WING + 0.02, "%s: довжина з крилами" % p)
	var road := AABB()
	var first := true
	var by_mat: Dictionary = _verts_by_material(p)
	for key: String in ["bridge_asphalt", "bridge_asphalt1", "bridge_deckplate"]:
		for v: Vector3 in by_mat.get(key, PackedVector3Array()):
			road = AABB(v, Vector3.ZERO) if first else road.expand(v)
			first = false
	assert_almost_eq(road.size.z, float(BRIDGES[p]), 0.02, "%s: довжина настилу" % p)
	assert_almost_eq(road.get_center().z, 0.0, 0.01, "%s: настил не по центру" % p)
	assert_lte(box.size.x, 1.0, "%s: ширина" % p)
	assert_lte(r["tris"], TRIS_MAX, "%s: трикутників %d" % [p, r["tris"]])

func test_broken_bridge_stays_in_footprint(p = use_parameters(BRIDGES.keys())) -> void:
	var r: Dictionary = _bounds(p + "_broken")
	var box: AABB = r["box"]
	assert_gte(box.position.y, -float(BROKEN_BELOW_GROUND.get(p, GROUND_TOLERANCE)), "%s: руїна нижче дна" % p)
	assert_lte(box.size.z, float(BRIDGES[p]) + 2.0 * WING + 0.02, "%s: руїна довша за переправу з крилами" % p)
	assert_lte(maxf(absf(box.position.x), absf(box.end.x)), HALF_WIDTH_MAX, "%s: уламки далеко вбік" % p)
	assert_lte(r["tris"], TRIS_MAX, "%s: трикутників %d" % [p, r["tris"]])


## Вершини моделі (у її просторі, y = 0 — низ), розкладені за матеріалом.
func _verts_by_material(name: String) -> Dictionary:
	var root: Node3D = (load("res://assets/props/%s.glb" % name) as PackedScene).instantiate()
	add_child_autofree(root)
	var out: Dictionary = {}
	for m: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		for s in m.mesh.get_surface_count():
			var key: String = m.mesh.surface_get_material(s).resource_name
			var pts: PackedVector3Array = out.get(key, PackedVector3Array())
			for v: Vector3 in m.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				pts.append(m.global_transform * v)
			out[key] = pts
	return out


## Кінець мосту вбудований у насип (TerrainHeight.SEAT_*): покриття на кінці на 1.6 см нижче за
## насип (deck_top + SEAT_TOP), тож торця плити не видно; під настилом бетонна опора від краю клітинки
## до SEAT_END углиб, не вужча за насип у клітинці мосту (SEAT_SIDE): її стіна ховає місце, де насип
## сходить до берега. Обрізи стіни обабіч настилу теж під насипом — згори не видно коробки.
func test_intact_bridge_ends_sit_flush_on_concrete_seats(p = use_parameters(BRIDGES.keys())) -> void:
	var by_mat: Dictionary = _verts_by_material(p)
	var top: float = float(PropLayer.spec_of(StringName(p))["deck_top"])
	var half: float = float(BRIDGES[p]) * 0.5
	for sgn: float in [-1.0, 1.0]:
		var road := -INF
		for key: String in ["bridge_asphalt", "bridge_asphalt1", "bridge_deckplate"]:
			for v: Vector3 in by_mat.get(key, PackedVector3Array()):
				if sgn * v.z > half - 0.02:
					road = maxf(road, v.y)
		assert_almost_eq(road, top + TerrainHeight.SEAT_TOP - 0.002, 0.0005, "%s: покриття на кінці %+d" % [p, sgn])
		var crest := -INF
		for v: Vector3 in by_mat.get("bridge_abutment", PackedVector3Array()):
			if sgn * v.z > half - TerrainHeight.SEAT_END - 0.01:
				crest = maxf(crest, v.y)
		# Лише опорні подушки під фермою стоять на 2.4 см над насипом.
		assert_lt(crest, top + TerrainHeight.SEAT_TOP + 0.004, "%s: опора виступає з насипу на кінці %+d" % [p, sgn])
		var seat := AABB()
		var first := true
		for v: Vector3 in by_mat.get("bridge_abutment", PackedVector3Array()):
			if sgn * v.z > half - TerrainHeight.SEAT_END - 0.05 and v.y < top - 0.01:
				seat = AABB(v, Vector3.ZERO) if first else seat.expand(v)
				first = false
		assert_false(first, "%s: нема бетонної опори на кінці %+d" % [p, sgn])
		if first:
			continue
		var inner: float = half - sgn * (seat.end.z if sgn < 0.0 else seat.position.z)
		assert_almost_eq(inner, TerrainHeight.SEAT_END, 0.01, "%s: стіна опори на кінці %+d" % [p, sgn])
		assert_gte(seat.size.x, 2.0 * TerrainHeight.SEAT_SIDE - 0.001, "%s: опора вужча за насип на кінці %+d" % [p, sgn])


## Парапет центрального мосту не обривається над берегом: за краєм переправи — крило, що сходить до
## насипу й сидить у ньому нижче настилу.
func test_centre_parapets_end_in_wing_walls() -> void:
	var by_mat: Dictionary = _verts_by_material("bridge_river_centre")
	var top: float = float(PropLayer.spec_of(&"bridge_river_centre")["deck_top"])
	for sgn: float in [-1.0, 1.0]:
		for sx: float in [-1.0, 1.0]:
			var wing: Array = Array(by_mat["bridge_concrete"] as PackedVector3Array).filter(
					func(v: Vector3) -> bool: return sgn * v.z > 1.5 + 0.01 and sx * v.x > 0.3)
			assert_gt(wing.size(), 0, "крило на кінці %+d, бік %+d" % [sgn, sx])
			if wing.is_empty():
				continue
			var lo := INF
			var tip := -INF
			for v: Vector3 in wing:
				lo = minf(lo, v.y)
				if sgn * v.z > 1.5 + WING - 0.01:
					tip = maxf(tip, v.y)
			assert_lt(lo, top - 0.1, "крило на кінці %+d, бік %+d не сидить у насипі" % [sgn, sx])
			assert_almost_eq(tip, top + TerrainHeight.SEAT_TOP, 0.002, "крило на кінці %+d, бік %+d не сходить до насипу" % [sgn, sx])


## Кінцеві стійки панельного мосту стоять на бетонних подушках устою, що виступають із насипу.
func test_truss_end_posts_stand_on_concrete() -> void:
	var by_mat: Dictionary = _verts_by_material("bridge_river_west")
	var top: float = float(PropLayer.spec_of(&"bridge_river_west")["deck_top"])
	for sgn: float in [-1.0, 1.0]:
		for sx: float in [-1.0, 1.0]:
			var crest := -INF
			for v: Vector3 in by_mat["bridge_abutment"]:
				if sgn * v.z > 0.9 and sx * v.x > 0.2 and sx * v.x < 0.3:
					crest = maxf(crest, v.y)
			assert_gt(crest, top + TerrainHeight.SEAT_TOP, "стійка на кінці %+d, бік %+d стоїть на ґрунті" % [sgn, sx])


## Борти понтона не обриваються коробкою на березі: за стіною опори вони заходять у насип і там не
## вищі за нього.
func test_pontoon_girders_end_in_the_embankment() -> void:
	var by_mat: Dictionary = _verts_by_material("bridge_river_east")
	var top: float = float(PropLayer.spec_of(&"bridge_river_east")["deck_top"])
	var wall: float = 1.0 - TerrainHeight.SEAT_END
	for sgn: float in [-1.0, 1.0]:
		for sx: float in [-1.0, 1.0]:
			var tip := -INF
			for v: Vector3 in by_mat["bridge_steel_grey"]:
				if sgn * v.z > wall + 0.03 and sx * v.x > 0.42:
					tip = maxf(tip, v.y)
			assert_gt(tip, top - 0.05, "борт на кінці %+d, бік %+d не заходить у насип" % [sgn, sx])
			assert_lt(tip, top + TerrainHeight.SEAT_TOP, "борт на кінці %+d, бік %+d стирчить над насипом" % [sgn, sx])


## У руїні панельного мосту нема окремої плити настилу у воді: плоский уламок у руслі читався
## темним трикутником, що плаває на поверхні.
func test_broken_truss_has_no_loose_deck_slab() -> void:
	assert_false(_verts_by_material("bridge_river_west_broken").has("bridge_asphalt_wet"), "плита настилу у воді")
