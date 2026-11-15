extends SceneTree
## Складає таблицю дозволених місць тіл розрахунку гармати (див. crew_body_legal.gd).
##   $GODOT --headless --path . -s tools/crew_body_table.gd -- table      # body_legal для рядків 9 і 10
##   $GODOT --headless --path . -s tools/crew_body_table.gd -- scan 9     # сітка кандидатів: скільки напрямів дозволяє
## `table` друкує масиви для `_SPECS`; `scan` допомагає вибрати `body_spots`.

const Legal := preload("res://tools/crew_body_legal.gd")


func _init() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	if a.size() > 0 and a[0] == "scan":
		_scan(int(a[1]))
	else:
		for id: int in [9, 10]:
			var masks: PackedInt32Array = Legal.legal_masks(id, 0)
			print("TABLE type %d body_legal: %s" % [id, Array(masks)])
			var spots: Array = UnitSilhouettes.spec(id).get("body_spots", [])
			for facing in 8:
				var legal: Array[int] = []
				for i in spots.size():
					if masks[facing] & (1 << i) != 0:
						legal.append(i)
				print("  facing %d legal %s" % [facing, legal])
	quit()


func _scan(id: int) -> void:
	var per_facing: Array = []
	for facing in 8:
		var tilts: Array = []
		for tx: float in [-Legal.TILT_DEG, Legal.TILT_DEG]:
			for tz: float in [-Legal.TILT_DEG, Legal.TILT_DEG]:
				tilts.append(Legal.ground_index(Legal.wreck_tris(id, 0, facing, Vector2(tx, tz))))
		var plain: PackedVector3Array = Legal.wreck_tris(id, 0, facing, Vector2.ZERO)
		tilts.append(Legal.ground_index(plain))
		per_facing.append([tilts, [Legal.silhouette(plain, IsoCameraRig.PITCH_NEAR_DEG), Legal.silhouette(plain, IsoCameraRig.PITCH_FAR_DEG)]])
	var rows: Array = []
	for xi in range(-9, 10):
		for zi in range(-9, 10):
			for h: float in [0.0, 45.0, 90.0, 135.0]:
				var spot := Vector3(float(xi) * 0.04, float(zi) * 0.04, h)
				var n: int = 0
				var which: String = ""
				for facing in 8:
					var rep: Dictionary = Legal.spot_report(spot, facing, per_facing[facing][0], per_facing[facing][1])
					if rep.tile and rep.clear and rep.cover <= Legal.TABLE_COVER:
						n += 1
						which += str(facing)
				if n >= 4:
					rows.append([n, spot, which])
	rows.sort_custom(func(p: Array, q: Array) -> bool: return p[0] > q[0])
	for r: Array in rows.slice(0, 80):
		print("SCAN %d  spot %s  facings %s" % [r[0], r[1], r[2]])
