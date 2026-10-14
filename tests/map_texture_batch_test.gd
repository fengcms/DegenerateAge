extends Node

func _ready() -> void:
	GameState.reset_to_defaults()
	for map_id in ["camp", "wild_trial", "ash_land", "corruption_source"]:
		GameState.current_map = map_id
		var ground := IsoGround.new()
		add_child(ground)
		await get_tree().process_frame
		await get_tree().process_frame
		assert(ground._tile_mesh != null and ground._tile_mesh.get_surface_count() == 1)
		var cells := ground.grid_size.x * ground.grid_size.y - ground.cave.blocked_cells().size()
		assert(ground._tile_mesh.surface_get_array_len(0) == cells * 4, "Texture batching retains every walkable tile")
		var atlas := ground._tile_atlas.get_image()
		for i in range(ground._atlas_tiles.size()):
			var source := (ground._atlas_tiles[i] as Texture2D).get_image()
			source.convert(Image.FORMAT_RGBA8)
			assert(atlas.get_region(Rect2i(i * 64, 0, 64, 32)).get_data() == source.get_data(), "Atlas retains original tile pixels")
		var arrays := ground._tile_mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		for offset in range(0, vertices.size(), 4):
			var center := Vector2(vertices[offset].x + 32, vertices[offset].y + 16)
			var cell := Vector2i(Iso.world_to_grid(center).round())
			assert(ground.cave.is_walkable(cell))
			var variation := posmod(cell.x * 73 + cell.y * 37 + cell.x * cell.y * 11, 19)
			var tile := 1 if variation < 4 else 2 if variation == 5 else 0
			if map_id == "camp" and (absi(cell.y - ground.grid_size.y / 2) <= 1 or absi(cell.x - ground.grid_size.y / 2) <= 1):
				tile = 3
			if map_id in ["wild_trial", "ash_land"] and absi(cell.y - ground.grid_size.y / 2) <= 1:
				tile = 3
			assert(is_equal_approx(uvs[offset].x, float(tile) / 4.0), "Tile variation and road selection must stay unchanged")
		ground.queue_free()
		await get_tree().process_frame
	print("[MapTextureBatchTest] PASS")
	get_tree().quit()
