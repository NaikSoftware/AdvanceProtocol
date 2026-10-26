extends GutTest
## Заступники юнітів мають реальні розміри (1 тайл = 8 м): ширина × висота × довжина корпусу.

const _METRES := {
	2: Vector3(2.6, 2.4, 6.0), 3: Vector3(3.0, 2.6, 7.0), 4: Vector3(2.4, 2.0, 5.0),
	5: Vector3(3.6, 1.6, 7.0), 6: Vector3(3.5, 1.5, 7.5), 7: Vector3(3.3, 1.5, 6.5),
	8: Vector3(3.8, 2.0, 7.2), 11: Vector3(3.4, 2.8, 7.0),
}


func test_hull_sizes_are_real_world_metres() -> void:
	for id: int in _METRES:
		assert_almost_eq((UnitSilhouettes.spec(id).hull as Vector3) * 8.0, _METRES[id], Vector3.ONE * 0.0001, "тип %d" % id)


func test_tank_is_hull_plus_08m_turret_and_gun_overhangs() -> void:
	var root: Node3D = UnitSilhouettes.build(5, Color.WHITE)
	var turret := root.get_node("Turret") as MeshInstance3D
	assert_almost_eq((turret.mesh as BoxMesh).size.y * 8.0, 0.8, 0.0001)
	assert_almost_eq(turret.position.y + (turret.mesh as BoxMesh).size.y * 0.5, 0.3, 0.0001)  # 2,4 м
	var barrel := root.get_node("Barrel") as MeshInstance3D
	assert_almost_eq(barrel.position.z - (barrel.mesh as BoxMesh).size.z * 0.5, -0.69, 0.0001)  # 5,5 м від центру башти
	root.free()
