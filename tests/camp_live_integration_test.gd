extends Node
## 正式营地白盒集成验收：从 Game.tscn 装配真实地面、玩家、NPC、出口和训练木桩。
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
	await get_tree().physics_frame
	var ground := world.get_node("Ground") as IsoGround
	var player := world.get_node("Entities/Player") as PlayerCharacter
	var camera := player.get_node("Camera2D") as Camera2D
	assert(ground.grid_size == Vector2i(110, 110) and ground.get_world_bounds().size == Vector2(3200, 1800),
		"正常游戏应加载矩形营地")
	assert(ground.get_node("CaveWalls").get_child_count() == 16, "实体碰撞应为整体轮廓")
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
	if DisplayServer.get_name() != "headless":
		for _frame in range(4):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var screenshot := "/tmp/degenerateage_camp_live.png"
		assert(get_viewport().get_texture().get_image().save_png(screenshot) == OK,
			"正式营地窗口截图失败")
	print("[CampLiveIntegrationTest] PASS · 正式营地载入 %d ms · 9 个目标可达" % [Time.get_ticks_msec() - started])
	get_tree().quit()
