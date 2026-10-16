extends Node
## 正式营地集成验收：从 Game.tscn 装配分层美术、真实地面、玩家、NPC、出口和训练木桩。
## 在隔离项目运行，不触碰玩家存档；验证矩形视野、旧坐标容错及全部服务点路线。


## 加载正常游戏世界并核对所有正式接入点；失败以断言报告具体目标。
func _ready() -> void:
	GameState.reset_to_defaults()
	GameState.current_map = "camp"
	GameState.save_pos = Iso.grid_to_world(Vector2i(32, 18))
	GameState.has_save_pos = true
	var started := Time.get_ticks_msec()
	var world := preload("res://scenes/Game.tscn").instantiate()
	add_child(world)
	var load_ms := Time.get_ticks_msec() - started
	await get_tree().physics_frame
	var ground := world.get_node("Ground") as IsoGround
	var player := world.get_node("Entities/Player") as PlayerCharacter
	var camera := player.get_node("Camera2D") as Camera2D
	assert(ground.grid_size == Vector2i(110, 110) and ground.get_world_bounds().size == Vector2(3200, 1800),
		"正常游戏应加载矩形营地")
	var source_solids := (ground._camp_whitebox["entities"] as Array).size() + (ground._camp_whitebox["fences"] as Array).size()
	assert(ground.get_node("CaveWalls").get_child_count() == source_solids, "每个实体与围栏应只有一条整体碰撞")
	assert(ground._camp_ground_texture != null and ground._camp_road_texture != null
		and ground._camp_foreground_count == source_solids,
		"正式营地必须装配循环地纹、透明道路与全部原障碍前沿")
	var cave_walls := ground.get_node("CaveWalls") as StaticBody2D
	for raw: Array in [[350, 220], [1100, 200], [450, 450], [1170, 625]]:
		var world_pos := ground._camp_canvas_to_world(raw)
		var blocked_cell := Vector2i(Iso.world_to_grid(world_pos).round())
		assert(not ground.cave.is_walkable(blocked_cell), "保留建筑与马车内部应阻挡：%s" % raw)
		var query := PhysicsPointQueryParameters2D.new()
		query.position = world_pos
		var collided := false
		for hit: Dictionary in world.get_world_2d().direct_space_state.intersect_point(query):
			if hit.get("collider") == cave_walls:
				collided = true
		assert(collided, "建筑与马车必须有对应整体物理碰撞：%s" % raw)
	for raw: Array in [[595, 620], [680, 620], [750, 620]]:
		var free_cell := Vector2i(Iso.world_to_grid(ground._camp_canvas_to_world(raw)).round())
		assert(ground.cave.is_walkable(free_cell), "动态木桩原占地不应留下隐形阻挡：%s" % raw)
	assert(ground.cave.is_walkable(Vector2i(Iso.world_to_grid(player.global_position).round())),
		"旧存档落点应迁至白盒内可走位置")
	assert(camera.limit_left == -1600 and camera.limit_right == 1600
		and camera.limit_top == -2660 and camera.limit_bottom == -860, "镜头边界应采用屏幕矩形")
	var map_canvas := MapCanvas.new()
	map_canvas.size = Vector2(700, 400)
	add_child(map_canvas)
	assert(map_canvas.world_rect() == ground.get_world_bounds(), "大地图底图应采用营地矩形投影")
	assert(world.get_node("Npcs").get_child_count() == 5 and world.get_node("Exits").get_child_count() == 2,
		"营地服务点和出口应正常装配")
	var rows: Array = ground.cave.points.keys()
	assert(rows.size() >= 10, "营地应包含全部服务与出口标记")
	for id: String in ["blacksmith", "warehouse", "shop", "elder", "carter", "lamp", "training", "north_exit", "east_exit"]:
		var raw: Array = ground.cave.points[id]
		var target := Iso.grid_to_world(Vector2i(int(raw[0]), int(raw[1])))
		assert(not ground.route(player.global_position, target).is_empty(), "正式寻路未到达：%s" % id)
	var spawner := world.get_node("Spawner") as MonsterSpawner
	assert(spawner.point_count() == 3, "训练木桩数量应保持三只")
	for spec: Dictionary in MapService.data_for("camp")["spawnPoints"]:
		for raw: Array in spec["cells"]:
			var cell := Vector2i(int(raw[0]), int(raw[1]))
			assert(ground.cave.is_walkable(cell) and not MapService.is_in_safe_area("camp", Iso.grid_to_world(cell)),
				"训练木桩须处于可走的危险区")
	var old_save := {"schemaVersion": 13, "mapLayoutVersion": "2026-10-14-landscape-v2",
		"currentMap": "camp", "playerPos": [448.0, -928.0],
		"unclaimedLoot": {"camp": [{"uid": "old_item", "pos": [448.0, -928.0]}]},
		"exploredMaps": {"camp": [1], "wild_trial": [2]}}
	var migrated: Dictionary = SaveManager._migrate(old_save)
	assert(migrated.playerPos == [0.0, -1696.0] and migrated.unclaimedLoot.camp[0].pos == [0.0, -1696.0],
		"旧营地存档和地面物应迁到白盒出生点")
	assert(not migrated.exploredMaps.has("camp") and migrated.exploredMaps.has("wild_trial"),
		"仅营地旧迷雾需重置")
	assert(SaveManager._migrate(migrated) == migrated, "营地迁移应幂等")
	var previous_camp_save := migrated.duplicate(true)
	previous_camp_save.mapLayoutVersion = SaveManager.PREVIOUS_CAMP_LAYOUT_VERSION
	previous_camp_save.playerPos = [100.0, -1700.0]
	previous_camp_save.unclaimedLoot.camp[0].pos = [110.0, -1710.0]
	previous_camp_save.exploredMaps = {"camp": [1, 2, 3]}
	var open_perimeter_migrated: Dictionary = SaveManager._migrate(previous_camp_save)
	assert(open_perimeter_migrated.mapLayoutVersion == SaveManager.CURRENT_CAMP_LAYOUT_VERSION
		and open_perimeter_migrated.playerPos == previous_camp_save.playerPos
		and open_perimeter_migrated.unclaimedLoot == previous_camp_save.unclaimedLoot
		and open_perimeter_migrated.exploredMaps == previous_camp_save.exploredMaps,
		"从旧白盒升级开放外围时必须保留玩家、地面物和迷雾")
	if DisplayServer.get_name() != "headless":
		for _frame in range(4):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var screenshot := "/tmp/degenerateage_camp_live.png"
		assert(get_viewport().get_texture().get_image().save_png(screenshot) == OK,
			"正式营地窗口截图失败")
		player.global_position = ground._camp_canvas_to_world([450, 400])
		camera.reset_smoothing()
		for _frame in range(4):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		assert(get_viewport().get_texture().get_image().save_png("/tmp/degenerateage_camp_merchant_occlusion.png") == OK,
			"货郎摊前景遮挡截图失败")
		camera.top_level = true
		camera.global_position = ground.get_world_bounds().get_center()
		var viewport_size := get_viewport().get_visible_rect().size
		camera.zoom = Vector2.ONE * minf((viewport_size.x - 24.0) / 3200.0,
			(viewport_size.y - 24.0) / 1800.0)
		camera.make_current()
		for _frame in range(4):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		assert(get_viewport().get_texture().get_image().save_png("/tmp/degenerateage_camp_final_overview.png") == OK,
			"正式营地全图截图失败")
	print("[CampLiveIntegrationTest] PASS · 正式营地场景装配 %d ms · 9 个目标可达" % [load_ms])
	get_tree().quit()
