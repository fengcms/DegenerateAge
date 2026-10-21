extends Node
## 幸存者营地 B 样板真实行走复核，沿正式导航与物理驱动玩家绕过屋檐、树、栅栏和岩带。
## 只在隔离测试项目中运行；窗口模式保存每条路线的中途截图，不修改正式布局或存档。

const SAMPLE := preload("res://tests/CampStyleSample.tscn")
const ROUTES := [
	{"id": "blacksmith", "start": [125, 300], "end": [610, 335]},
	{"id": "elder_tree", "start": [1000, 450], "end": [1185, 345]},
	{"id": "northwest_palisade", "start": [120, 170], "end": [650, 180]},
	{"id": "western_rocks", "start": [125, 610], "end": [125, 780]},
]

## 逐条向真实玩家发出移动命令，并在每个物理帧验证脚底属于既有可走格。
func _ready() -> void:
	var sample := SAMPLE.instantiate()
	add_child(sample)
	await get_tree().physics_frame
	sample._show_style("b")
	sample._set_zoom(1.5)
	sample._help.visible = false
	for route: Dictionary in ROUTES:
		await _walk_route(sample, route)
	print("[CampStyleTraversalTest] PASS")
	print("[CampStyleTraversalTest] 四条真实移动路线没有越过既有障碍")
	get_tree().quit()

## 从布局参考坐标运行一条可达路线；窗口模式在第三十帧保存中途遮挡证据。
func _walk_route(sample: Node2D, route: Dictionary) -> void:
	var id := String(route["id"])
	var start: Vector2 = sample.ground.clamp_to_map(sample._canvas_to_world(route["start"]))
	var destination: Vector2 = sample.ground.clamp_to_map(sample._canvas_to_world(route["end"]))
	sample.player.clear_travel_intent()
	sample.player.global_position = start
	sample.camera.reset_smoothing()
	assert(sample.ground.route(start, destination).size() > 1, "观察路线不可达：%s" % id)
	assert(sample.player.request_map_move(destination), "玩家拒绝移动路线：%s" % id)
	var traversed := 0.0
	for frame in range(720):
		var previous: Vector2 = sample.player.global_position
		await get_tree().physics_frame
		traversed += previous.distance_to(sample.player.global_position)
		var cell := Vector2i(Iso.world_to_grid(sample.player.global_position).round())
		assert(sample.ground.cave.is_walkable(cell), "玩家脚底踏入既有障碍：%s/%s" % [id, cell])
		if frame == 30 and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			assert(get_viewport().get_texture().get_image().save_png(
				"/tmp/camp_style_walk_%s.png" % id) == OK, "路线截图失败：%s" % id)
		if sample.player.global_position.distance_to(destination) <= 35.0:
			break
	assert(traversed > 120.0, "观察路线没有实际走动：%s" % id)
	assert(sample.player.global_position.distance_to(destination) <= 35.0,
		"玩家未能沿现有导航到达观察点：%s" % id)
	print("[PERF] 营地样板路线 ", id, " 实际行走世界像素：", roundi(traversed))
