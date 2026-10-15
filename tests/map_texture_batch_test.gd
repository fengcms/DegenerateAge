extends Node
## 第一章地面回归：营地检查整体白盒绘制，其余三图核对纹理图集合批。

## 逐图检查白盒事实源或网格顶点、UV 与源图像素，避免道路错位。
func _ready() -> void:
	GameState.reset_to_defaults()
	for map_id in ["camp", "wild_trial", "ash_land", "corruption_source"]:
		GameState.current_map = map_id
		var ground := IsoGround.new()
		add_child(ground)
		await get_tree().process_frame
		await get_tree().process_frame
		if map_id == "camp":
			assert(ground._tile_mesh == null and ground._camp_whitebox.get("id", "") == "camp_whitebox_v1"
				and ground._camp_ground_texture != null and ground._camp_foreground_count == 6,
				"营地应使用矩形整图及六个前景，而非旧菱形瓦片网格")
			assert(ground.get_world_bounds().size == Vector2(3200, 1800), "营地画幅必须是矩形")
			ground.queue_free()
			await get_tree().process_frame
			continue
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
		assert(ground._atlas_tiles.size() == 12, "第一章图集包含四张基础砖与八张道路过渡砖")
		var transition_count := 0
		for offset in range(0, vertices.size(), 4):
			var center := Vector2(vertices[offset].x + 32, vertices[offset].y + 16)
			var cell := Vector2i(Iso.world_to_grid(center).round())
			assert(ground.cave.is_walkable(cell))
			var variation := posmod(cell.x * 73 + cell.y * 37 + cell.x * cell.y * 11, 19)
			var tile := 1 if variation < 4 else 2 if variation == 5 else 0
			var road_tile := ground._chapter_one_road_tile_index(cell)
			if road_tile >= 0:
				tile = road_tile
			if tile >= 4:
				transition_count += 1
			assert(is_equal_approx(uvs[offset].x, float(tile) / 12.0), "地面 UV 必须采用新版道路与过渡砖")
		assert(transition_count > 0, "地图应包含至少一段道路过渡")
		ground.queue_free()
		await get_tree().process_frame
	print("[MapTextureBatchTest] PASS")
	get_tree().quit()
