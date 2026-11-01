extends SceneTree
## Будує BoardView карти й друкує час та відбитки результату (різниця відбитків до й після правки
## означає, що вигляд змінився): godot --headless -s tools/build_profile.gd -- <map>...

func _init() -> void:
	for map: String in OS.get_cmdline_user_args():
		var data: MapData = load("res://maps/%s.tres" % map) as MapData
		var board: Board = data.to_board()
		var view := BoardView.new()
		view.surface = data.surface
		view.relief_seed = data.name_key.hash()
		view.ring_map = data
		view.season = BattleLook.for_map_path(data.resource_path).season
		root.add_child(view)
		var t0: int = Time.get_ticks_usec()
		view.build(board)
		print("PROFILE %s total %.0f ms" % [map, (Time.get_ticks_usec() - t0) / 1000.0])
		var h: TerrainHeight = view.get("_height")
		print("HASH %s height %s" % [map, _hh(h.heights().to_byte_array())])
		var mat := view.get("_ground").material_override as ShaderMaterial
		var pm: Texture2D = mat.get_shader_parameter("path_map") as Texture2D
		print("HASH %s paths %s" % [map, _hh(pm.get_image().get_data()) if pm != null else "none"])
		print("HASH %s props %s" % [map, var_to_str(view.props().all_instances()).sha256_text()])
		print("HASH %s footpaths %s" % [map, var_to_str([view.props().footpaths, view.props().trodden]).sha256_text()])
		print("HASH %s veg %s" % [map, var_to_str(view.vegetation().placements).sha256_text()])
		var props: PropLayer = view.props()
		var size := Vector2i(data.width, data.height)
		var t1: int = Time.get_ticks_usec()
		Footpaths.bake(props.footpaths, props.trodden, size, Callable(), true)
		var t2: int = Time.get_ticks_usec()
		Footpaths.bake(props.footpaths, props.trodden, size, view.call("_dry_grid"), true)
		print("PROFILE %s footpaths cached no-dry %.0f ms, with dry %.0f ms" % [map, (t2 - t1) / 1000.0, (Time.get_ticks_usec() - t2) / 1000.0])
		var ring: int = Surroundings.ring_of(data)
		var world: Board = Surroundings.world_board(board, data) if ring > 0 else board
		var wsurf: PackedByteArray = Surroundings.world_surface(data) if ring > 0 else data.surface
		var fresh: TerrainHeight = TerrainHeight.bake(world, 0, data.name_key.hash(), wsurf, ring)
		var warm: TerrainHeight = TerrainHeight.bake(world, 0, data.name_key.hash(), wsurf, ring, true)
		print("HASH %s cache-equal %s" % [map, var_to_bytes(fresh._to_cache()) == var_to_bytes(warm._to_cache())])
		view.free()
	quit()


func _hh(b: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(b).sha256_text().substr(0, 16)
