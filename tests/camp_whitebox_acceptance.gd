extends Node
## 营地独立白盒验收：核对屏幕矩形、全部服务点路径以及真实玩家穿过三处关键路线。
## 在隔离 Godot 项目中运行；截图写入系统临时目录，不接触正式存档或运行地图。

const WHITEBOX_SCENE := preload("res://tests/CampWhitebox.tscn")

var whitebox: Node2D

## 初始化白盒并执行路径、真实移动和窗口截图验收；全部完成才输出 PASS。
func _ready() -> void:
	GameState.reset_to_defaults()
	GameState.current_map = "camp"
	whitebox = WHITEBOX_SCENE.instantiate()
	var load_started := Time.get_ticks_msec()
	add_child(whitebox)
	var load_ms := Time.get_ticks_msec() - load_started
	await get_tree().physics_frame
	var rect: Rect2 = whitebox.world_rect
	assert(is_equal_approx(rect.size.x / rect.size.y, 16.0 / 9.0), "白盒世界画幅必须是屏幕矩形 16:9")
	assert((whitebox.player.get_node("CollisionShape2D").shape as CircleShape2D).radius == 12.0,
		"白盒必须使用正式玩家的 12 像素碰撞体")
	assert(whitebox.walkable_count > 2000, "白盒通行面积不足")
	assert(float(whitebox.walkable_count) / float(whitebox.interior_count) > 0.70,
		"补齐建筑和外围阻挡后，营地内部可行动面积低于设计底线")
	var origin: Vector2 = whitebox.canvas_to_world(whitebox.layout["spawn"])
	for id: String in whitebox.layout["targets"]:
		var target: Vector2 = whitebox.canvas_to_world(whitebox.layout["targets"][id])
		var route: Array[Vector2] = whitebox.route_between(origin, target)
		assert(not route.is_empty(), "白盒服务点不可达：%s" % id)
		for cell_center: Vector2 in route:
			assert(not whitebox._is_blocked_with_clearance(cell_center), "路线穿过实体或安全带：%s" % id)
	await _capture("overview")
	whitebox.set_overview(false)
	await _travel_to("training", origin, 950)
	await _capture("training_play")
	for id: String in ["blacksmith", "warehouse", "shop", "elder", "carter", "lamp", "east_exit", "north_exit"]:
		await _travel_to(id, origin, 1150)
	print("[CampWhiteboxAcceptance] PASS · 可走格 %d/%d · 9 个目标规划和真实玩家移动均通过" % [whitebox.walkable_count, whitebox.interior_count])
	print("[PERF] CampWhitebox 首次布局与导航构建 %d ms；等距格 %d；静态实体 %d" % [load_ms,
		whitebox.grid_size.x * whitebox.grid_size.y, whitebox._solid_polygons.size()])
	get_tree().quit()

## 用正式玩家的移动与碰撞沿白盒路线走到指定目标，帧数上限避免卡住后假通过。
func _travel_to(id: String, origin: Vector2, frame_limit: int) -> void:
	whitebox.player.global_position = origin
	whitebox.player.velocity = Vector2.ZERO
	whitebox.player.set_auto_move(Vector2.ZERO)
	whitebox._route.clear()
	assert(whitebox.navigate_to_target(id), "无法开始实机路线：%s" % id)
	for _frame in range(frame_limit):
		await get_tree().physics_frame
		if whitebox._route.is_empty():
			break
	var destination := Iso.grid_to_world(whitebox._nearest_open(whitebox.canvas_to_world(whitebox.layout["targets"][id])))
	assert(whitebox._route.is_empty() and whitebox.player.global_position.distance_to(destination) < 19.0,
		"真实玩家未走到目标：%s；位置 %s，终点 %s" % [id, whitebox.player.global_position, destination])
	whitebox.player.set_auto_move(Vector2.ZERO)

## 等待真实渲染提交后保存当前窗口，供人工检查矩形边界和实际玩家尺度。
func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	for _frame in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := "/tmp/degenerateage_camp_whitebox_%s.png" % label
	assert(get_viewport().get_texture().get_image().save_png(path) == OK, "白盒截图失败：%s" % path)
