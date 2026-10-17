extends Node
## 小地图局部视野（非整图缩放）：视野格数、跟随位移、圆内可见性、路线截断与大地图零影响。
## 依据工程文档《小地图局部视野（非整图缩放）可行性与实施方案》§7 T1–T7。
##
## 隔离性：只实例化 Main.tscn 于测试场景内并冻结处理循环，手工写入人物坐标与寻路状态，
## 不依赖真实按帧行为；小地图画布用代码创建、尺寸固定，避免受 HUD 布局与界面倍率影响。
## 画布尺寸 240×180 → 圆盘半径 87，裁剪半径 84，18 格视野 → 每格 ≈ 9.3 控件像素。

const MINI_SIZE := Vector2(240.0, 180.0)

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
	var canvas := MapCanvas.new()
	canvas.size = MINI_SIZE
	canvas.minimap = true
	add_child(canvas)
	canvas.set_process(false)
	await frames()
	_check(canvas.background_draw_count > 0, "小地图首次显示应绘制地形")
	_test_view_scale(canvas)
	await _test_follow(player, canvas)
	await _test_clamp(player, canvas)
	_test_view_predicate(canvas)
	await _test_route_clip(player, canvas)
	await _test_big_map_unchanged(canvas)
	_finish()

## T1/A2：圆内直径恰好为固定格数，且倍率明显大于改动前的整图适配。
func _test_view_scale(canvas: MapCanvas) -> void:
	var expected := MapCanvas.MINIMAP_VIEW_GRIDS * Iso.TILE_W * 0.5
	_check(is_equal_approx(canvas.view_radius_world(), expected),
		"小地图可见半径应为 %.1f 世界像素（%.0f 格直径），实际 %.1f"
			% [expected, MapCanvas.MINIMAP_VIEW_GRIDS, canvas.view_radius_world()])
	var rect := canvas.world_rect()
	var fit := minf((MINI_SIZE.x - 40.0) / rect.size.x, (MINI_SIZE.y - 40.0) / rect.size.y)
	_check(canvas.map_scale() >= fit * 2.0, "局部视野倍率应明显大于整图适配倍率（%.4f vs %.4f）"
		% [canvas.map_scale(), fit])

## T3：人物移动只改内容层位移（底图不重建），且视野恒锁人物居中。
func _test_follow(player: PlayerCharacter, canvas: MapCanvas) -> void:
	var center := canvas.world_rect().get_center()
	player.global_position = center
	canvas.refresh()
	await frames()
	_check(canvas.view_center_world().is_equal_approx(center), "人物在地图中央时视野中心应等于人物坐标")
	_check(canvas.world_to_canvas(center).distance_to(canvas.size * 0.5) < 0.5, "视野应恒锁人物于圆心")
	var baseline := canvas.background_draw_count
	var fixed := center + Vector2(32.0, -16.0)
	var before := canvas.world_to_canvas(fixed)
	var delta := Vector2(320.0, -160.0)
	player.global_position = center + delta
	canvas.refresh()
	await frames()
	_check(canvas.background_draw_count == baseline, "小地图跟随不得重建静态底图")
	_check((before - canvas.world_to_canvas(fixed)).is_equal_approx(delta * canvas.map_scale()),
		"跟随位移应等于人物位移 × 视野倍率")
	_check(canvas.world_to_canvas(player.global_position).distance_to(canvas.size * 0.5) < 0.5,
		"移动后人物仍应位于圆心")

## T4（D5②）：人物贴到地图角落时视野夹紧在地图外框内，不露出空底。
func _test_clamp(player: PlayerCharacter, canvas: MapCanvas) -> void:
	var rect := canvas.world_rect()
	var half := canvas.view_radius_world()
	var corner := rect.position
	player.global_position = corner
	canvas.refresh()
	await frames()
	var center := canvas.view_center_world()
	_check(center.x - half >= rect.position.x - 0.01 and center.x + half <= rect.end.x + 0.01,
		"视野横向不得越出地图外框（中心 %.1f，半径 %.1f，外框 %s）" % [center.x, half, rect])
	_check(center.y - half >= rect.position.y - 0.01 and center.y + half <= rect.end.y + 0.01,
		"视野纵向不得越出地图外框（中心 %.1f，半径 %.1f，外框 %s）" % [center.y, half, rect])
	_check(not canvas.in_minimap_view(corner), "地图角落（在视野外）不应显示")

## T5：圆内可见性判定与投影互逆（标记与虚线复用同一判定）。
func _test_view_predicate(canvas: MapCanvas) -> void:
	var center := canvas.view_center_world()
	var radius := canvas.view_radius_world()
	_check(canvas.in_minimap_view(center), "视野中心应在圆内")
	_check(canvas.in_minimap_view(center + Vector2(radius * 0.9, 0.0)), "半径内的点应可见")
	_check(not canvas.in_minimap_view(center + Vector2(radius * 1.1, 0.0)), "半径外的点不可见")
	var cell := Vector2(120.0, 67.0)
	_check(canvas.canvas_to_grid(canvas.world_to_canvas(Iso.grid_pt(cell.x, cell.y))).distance_to(cell) < 0.001,
		"小地图投影与反算应互为逆映射")

## T6（D4①）：终点在视野外时虚线在圆边截断，且不画终点金环。
func _test_route_clip(player: PlayerCharacter, canvas: MapCanvas) -> void:
	var origin := canvas.world_rect().get_center()
	player.global_position = origin
	player.map_move_active = true
	player._map_destination = origin + Vector2(4000.0, 0.0)
	var waypoints: Array[Vector2] = [origin + Vector2(1200.0, 0.0)]
	player._cave_path = waypoints
	player._cave_path_index = 0
	canvas.refresh()
	await frames()
	_check(player.map_move_route().size() == 3, "玩家侧路线应为 当前+路点+终点 三点")
	_check(not canvas.route_target_visible(), "终点在视野外时不应画终点金环")
	var clipped := canvas.visible_route_points()
	_check(clipped.size() >= 2, "视野外路线应保留圆内片段，实际 %d 点" % clipped.size())
	if clipped.size() >= 2:
		_check(clipped[clipped.size() - 1].distance_to(canvas.view_center_world()) <= canvas.view_radius_world() + 0.5,
			"截断后的路线末点应落在圆内")
	player.clear_travel_intent()

## T2/T7：大地图与今日逐值一致 —— 整图适配、位移恒 0、无裁剪材质。
func _test_big_map_unchanged(canvas: MapCanvas) -> void:
	canvas.minimap = false
	canvas.refresh()
	await frames()
	_check(is_zero_approx(canvas.view_radius_world()), "大地图不裁剪（可见半径应为 0）")
	_check(canvas.clip_material() == null, "大地图不应挂圆形裁剪材质")
	_check(canvas.in_minimap_view(Vector2(0.0, -1000000.0)), "大地图任意点都在可见范围内")
	_check(canvas.visible_route_points().is_empty(), "无寻路时大地图不应有路线")
	var rect := canvas.world_rect()
	var scale := canvas.map_scale()
	for point in [rect.position, rect.get_center(), rect.end, rect.get_center() + Vector2(500.0, 500.0)]:
		var expected: Vector2 = canvas.size * 0.5 + (point - rect.get_center()) * scale
		_check(canvas.world_to_canvas(point).distance_to(expected) < 0.001, "大地图投影应与整图适配公式逐值一致")
	var cell := Vector2(120.0, 67.0)
	_check(canvas.canvas_to_grid(canvas.world_to_canvas(Iso.grid_pt(cell.x, cell.y))).distance_to(cell) < 0.001,
		"大地图投影反算一致")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("[MinimapViewportTest] 全部通过 ✅")
	else:
		for failure in _failures:
			push_error("[MinimapViewportTest] 失败：" + failure)
	get_tree().quit(0 if _failures.is_empty() else 1)
