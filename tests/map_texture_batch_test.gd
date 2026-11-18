extends Node
## 第一章地面回归：营地检查模块网格与矩形裁切，其余三图核对纹理图集合批。

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
			assert(ground._tile_mesh == null and ground._camp_whitebox.get("id", "") == "camp_whitebox_v2"
				and ground._camp_modular != null and ground._camp_modular.get_child_count()==3
				and ground._camp_foreground_count == 11,
				"营地应使用三层模块地面及11个实体前沿")
			assert(ground.get_world_bounds().size == Vector2(3200, 1800), "营地画幅必须是矩形")
			for layer in range(3):
				var node := ground._camp_modular.get_child(layer) as MeshInstance2D
				assert(node.mesh.get_surface_count()==1,"每层只能有一个合批面")
				assert(node.mesh.surface_get_array_len(0)==ground._camp_modular.tile_counts[layer]*4,"模块合批未保留全部瓦片")
				var packed: Array = node.mesh.surface_get_arrays(0)
				for vertex: Vector3 in packed[Mesh.ARRAY_VERTEX]:
					assert(ground.get_world_bounds().grow(0.001).has_point(Vector2(vertex.x,vertex.y)),"模块顶点越出正式矩形")
				for uv: Vector2 in packed[Mesh.ARRAY_TEX_UV]:
					assert(uv.x>=0 and uv.x<=1 and uv.y>=0 and uv.y<=1,"模块UV越出图集")
				assert(node.texture.get_size()==Vector2(1024,1536),"模块图集尺寸与UV规格不符")
			ground.queue_free()
			await get_tree().process_frame
			continue
		if map_id=="wild_trial":
			assert(ground._wild_modular!=null and ground._wild_modular.get_child_count()==3,"试炼野外须复用三层模块地面")
			assert(ground._wild_modular.tile_counts[0]==ground.grid_size.x*ground.grid_size.y,"野外模块须覆盖完整地图")
			var roads := 0
			for row: String in ground._chapter_one_road_rows:
				roads += row.count("1")
			assert(ground._wild_modular.tile_counts[2]==roads,"野外道路必须逐格保留既有路线")
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
		# 图集 = 本族地砖 + 1 块道路中心砖 + 八张道路过渡砖；道路槽位固定排在族砖之后，
		# 故族变体数与道路槽位完全无关（见 ground.gd 的 _road_atlas_index 与 43/44 号文档）。
		var atlas_size := ground._atlas_tiles.size()
		var theme_size := atlas_size - 9
		assert(theme_size == (9 if map_id == "corruption_source" else 9 if map_id == "wild_trial" else 8),
			"corruption_source/wild_trial 用 9 变体，ash_land 用 8 变体")
		var transition_count := 0
		for offset in range(0, vertices.size(), 4):
			var center := Vector2(vertices[offset].x + 32, vertices[offset].y + 16)
			var cell := Vector2i(Iso.world_to_grid(center).round())
			assert(ground.cave.is_walkable(cell))
			var tile := ground._pick_theme_tile(cell, theme_size)
			var road_tile := ground._chapter_one_road_tile_index(cell)
			if road_tile >= 0:
				tile = ground._road_atlas_index(road_tile, theme_size)
			if tile >= theme_size:
				transition_count += 1
			assert(is_equal_approx(uvs[offset].x, float(tile) / float(atlas_size)), "地面 UV 必须采用新版道路与过渡砖")
		assert(transition_count > 0, "地图应包含至少一段道路过渡")
		ground.queue_free()
		await get_tree().process_frame
	print("[MapTextureBatchTest] PASS")
	get_tree().quit()
