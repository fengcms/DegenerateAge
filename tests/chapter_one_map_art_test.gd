extends Node
## 第一章四图美术实体契约：道路与可走掩码一致，大型障碍一实体一碰撞。
## 逐图载入 IsoGround，检查资源引用、物理接触和旧版固定装饰已退场。


## 在隔离项目中核对四张真实运行地图；每图释放后再测试下一图。
func _ready() -> void:
	GameState.reset_to_defaults()
	for map_id in ["camp", "wild_trial", "ash_land", "corruption_source"]:
		GameState.current_map = map_id
		var ground := IsoGround.new()
		add_child(ground)
		await get_tree().physics_frame
		var art := ground._chapter_one_art as ChapterOneMapArt
		assert(art != null and art.map_id == map_id, "四图必须接入新版美术")
		assert(art.layout.get("layoutVersion", "") == ground.map_data.get("layoutVersion", ""))
		assert(ground.get_node_or_null("ChapterOneMapArt") == art)
		var walls := ground.get_node("CaveWalls") as StaticBody2D
		var blocking := 0
		var sprites := 0
		var known_ids := {}
		for raw in art.layout.get("entities", []):
			var entity: Dictionary = raw
			var instance_id := String(entity.get("instance_id", ""))
			assert(not instance_id.is_empty() and not known_ids.has(instance_id), "大型实体 ID 必须唯一")
			known_ids[instance_id] = true
			var rect: Array = entity.get("footprint", [])
			assert(rect.size() == 2 and int(rect[0]) >= 1 and int(rect[1]) >= 1)
			sprites += (entity.get("visual_cells", []) as Array).size()
			if bool(entity.get("blocking", false)):
				blocking += 1
				assert(walls.get_node_or_null(instance_id) is CollisionPolygon2D,
					"每个多格阻挡只有一条合并碰撞：%s" % instance_id)
				var cell_data: Array = entity.get("visual_cells", [])[0]
				var cell := Vector2i(int(cell_data[0]), int(cell_data[1]))
				assert(not ground.cave.is_walkable(cell), "阻挡外观必须放在阻挡区")
				var query := PhysicsPointQueryParameters2D.new()
				query.position = Iso.grid_to_world(cell)
				var touching := false
				for hit in ground.get_world_2d().direct_space_state.intersect_point(query):
					if hit.collider == walls:
						touching = true
				assert(touching, "合并碰撞必须覆盖实体内格：%s" % instance_id)
		assert(walls.get_child_count() == blocking and art.get_child_count() == sprites,
			"碰撞与精灵实例数必须等于一图摆放记录")
		for y in range(ground.grid_size.y):
			var row := String(ground._chapter_one_road_rows[y])
			assert(row.length() == ground.grid_size.x)
			for x in range(row.length()):
				if row[x] == "1":
					assert(ground.cave.is_walkable(Vector2i(x, y)), "道路不能画在阻挡格")
		ground.queue_free()
		await get_tree().physics_frame
	print("[ChapterOneMapArtTest] PASS")
	get_tree().quit()
