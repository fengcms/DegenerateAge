extends Node
## 自动寻路路线虚线（大地图与小地图）：路线数据源与地图绘制源的一致性。
## 依据工程文档《自动寻路路线虚线显示（大地图与小地图）规划》§6 T1–T8。
##
## 隔离性：只实例化 Main.tscn 于测试场景内，冻结其处理循环后手工写入寻路状态，
## 不依赖真实按帧寻路，避免路径结果随地图内容漂移。
## 断言覆盖：未寻路无路线（T1）、路线未算出时不画穿墙直线（T2）、绕障路点序列（T3）、
## 已走路点裁剪（T4）、无布局掩码退化为两点直线（T5）、手动接管后清空（T6）、
## 画布缓存的路线与玩家侧一致（T7）、路线变化不重建静态底图（T8）。

var _failures: Array[String] = []

func frames() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children():
		freeze(child)

func _ready() -> void:
	GameState.reset_to_defaults()
	GameState.current_map = "c2_lower_works"
	var main := preload("res://scenes/Main.tscn").instantiate()
	add_child(main)
	freeze(main)
	await frames()
	var player := main.get_node("Game/Entities/Player") as PlayerCharacter
	var ground := main.get_node("Game/Ground") as IsoGround
	_test_idle_has_no_route(player)
	_test_pending_route_is_empty(player)
	_test_path_waypoints(player)
	_test_path_trimmed(player)
	_test_manual_takeover_clears_route(player)
	_test_straight_without_layout(player, ground)
	await _test_canvas_mirrors_route(player)
	_finish()

## T1：未发起寻路时路线为空（大地图/小地图都不应画出任何虚线）。
func _test_idle_has_no_route(player: PlayerCharacter) -> void:
	player.map_move_active = false
	_check(player.map_move_route().is_empty(), "未寻路时路线应为空")

## T2：刚下发目标、绕障路线尚未算出时返回空数组——宁可短暂不显示，也不画穿墙直线。
func _test_pending_route_is_empty(player: PlayerCharacter) -> void:
	var origin := player.global_position
	player.request_map_move(origin + Vector2(256, 64))
	_check(player.map_move_active, "下发目标后应进入寻路态")
	_check(player.map_move_route().is_empty(), "路线未算出时不应给出直线")
	player.clear_travel_intent()

## T3：洞穴/掩码地图返回「当前坐标 + 绕障路点 + 终点」的折线。
func _test_path_waypoints(player: PlayerCharacter) -> void:
	var origin := player.global_position
	var first := origin + Vector2(64, 0)
	var second := origin + Vector2(128, 0)
	var destination := origin + Vector2(192, 0)
	player.map_move_active = true
	player._map_destination = destination
	var waypoints: Array[Vector2] = [first, second]
	player._cave_path = waypoints
	player._cave_path_index = 0
	var route := player.map_move_route()
	_check(route.size() == 4, "有路点时应为 当前+2路点+终点 共 4 点，实际 %d" % route.size())
	if route.size() == 4:
		_check(route[0] == origin, "首点应为人物当前坐标")
		_check(route[1] == first and route[2] == second, "中段应为绕障路点")
		_check(route[3] == destination, "末点应为目标坐标")

## T4：已走过的路点被裁掉，虚线只画剩余行程。
func _test_path_trimmed(player: PlayerCharacter) -> void:
	var origin := player.global_position
	var destination := origin + Vector2(192, 0)
	var remaining := origin + Vector2(128, 0)
	player._cave_path_index = 1
	var route := player.map_move_route()
	_check(route.size() == 3, "裁掉首段后应为 3 点，实际 %d" % route.size())
	if route.size() == 3:
		_check(route[0] == origin, "裁剪后首点仍是人物当前坐标")
		_check(route[1] == remaining, "裁剪后首个路点应为未走过的路点")
		_check(route[2] == destination, "裁剪后末点仍是目标坐标")

## T6：手动接管（WASD / 攻击）后 map_move_active 关闭，虚线随之消失。
func _test_manual_takeover_clears_route(player: PlayerCharacter) -> void:
	player.map_move_active = false
	_check(player.map_move_route().is_empty(), "手动接管后路线应清空")

## T5：无布局掩码的地图退化为「当前坐标 → 目标」两点直线。
func _test_straight_without_layout(player: PlayerCharacter, ground: IsoGround) -> void:
	var saved_cave := ground.cave
	ground.cave = null
	var origin := player.global_position
	var destination := origin + Vector2(192, 0)
	player.map_move_active = true
	player._map_destination = destination
	var route := player.map_move_route()
	_check(route.size() == 2, "无布局掩码时应为两点直线，实际 %d 点" % route.size())
	if route.size() == 2:
		_check(route[0] == origin and route[1] == destination, "两直线端点应为人物与目标")
	ground.cave = saved_cave
	player.clear_travel_intent()

## T7/T8：MapCanvas.refresh() 读到同一份路线，且路线变化不重建静态底图。
func _test_canvas_mirrors_route(player: PlayerCharacter) -> void:
	var canvas := MapCanvas.new()
	canvas.size = Vector2(240, 180)
	canvas.minimap = true
	add_child(canvas)
	canvas.set_process(false)
	await frames()
	_check(canvas.background_draw_count > 0, "画布首次显示应绘制静态底图")
	var baseline := canvas.background_draw_count
	_check(canvas.route_points().is_empty(), "未寻路时画布路线应为空")
	var origin := player.global_position
	var destination := origin + Vector2(192, 0)
	var waypoints: Array[Vector2] = [origin + Vector2(64, 0), origin + Vector2(128, 0)]
	player.map_move_active = true
	player._map_destination = destination
	player._cave_path = waypoints
	player._cave_path_index = 0
	# 小地图模式：路线应与玩家侧完全一致。
	canvas.refresh()
	await frames()
	_check(canvas.route_points() == player.map_move_route(), "小地图路线应与玩家侧一致")
	_check(canvas.background_draw_count == baseline, "路线变化不应重建静态底图")
	baseline = canvas.background_draw_count
	# 大地图模式（minimap = false）：同一份路线，绘制规格不同但数据源不变。
	canvas.minimap = false
	canvas.refresh()
	await frames()
	_check(canvas.route_points() == player.map_move_route(), "大地图路线应与玩家侧一致")
	baseline = canvas.background_draw_count
	# 抵达/接管后路线清空，画布随之不再持有路线。
	player.map_move_active = false
	canvas.refresh()
	await frames()
	_check(canvas.route_points().is_empty(), "寻路结束后画布路线应清空")
	_check(canvas.background_draw_count == baseline, "路线清空同样不应重建静态底图")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("[MapRouteOverlayTest] 全部通过 ✅")
	else:
		for failure in _failures:
			push_error("[MapRouteOverlayTest] 失败：" + failure)
	get_tree().quit(0 if _failures.is_empty() else 1)
