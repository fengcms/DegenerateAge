extends Node
## 固定正式掩码和蛇形顺序，对比7/12格一轮真实绕墙规划长度与A*次数；无战斗，非FPS基准。

## 使用正式Ground.route求完整路线，累积实际平滑折线长度，避免用直线估算绕墙成本。
func measure(ground: IsoGround, points: Array, origin: Vector2) -> Dictionary:
	var length := 0.0
	var times: Array[float] = []
	var cursor := origin
	var empty := 0
	for point in points:
		var started := Time.get_ticks_usec()
		var path := ground.route(cursor, point)
		times.append((Time.get_ticks_usec() - started) / 1000.0)
		if path.is_empty():
			empty += 1
		for next in path:
			length += cursor.distance_to(next)
			cursor = next
	times.sort()
	return {"points":points.size(), "length_px":roundi(length), "astar_calls":points.size(), "unreachable":empty, "route_ms":{"p50":times[int(times.size() * 0.5)], "p95":times[int(times.size() * 0.95)], "p99":times[int(times.size() * 0.99)], "max":times[-1]}}

## 固定起点与地图，输出可重复的CPU/几何证据；新方案细补点单独计入未知地图一轮。
func _ready() -> void:
	for id in ["corruption_source", "c2_ember_furnace", "c7_arena", "c7_boss_field"]:
		var ground := IsoGround.new()
		ground.cave = CaveLayout.new("res://data/layouts/" + id + ".json")
		ground.grid_size = ground.cave.size
		ground.cave.prepare_connectivity()
		var cell := ground.cave.nearest_walkable(Vector2i(8, 8))
		var origin := Iso.grid_to_world(cell)
		var old := AutoRoamPlan.build(ground, cell, 7)
		var modern := AutoRoamPlan.build(ground, cell, 12)
		var full: Array = []
		full.append_array(modern.primary)
		full.append_array(modern.supplements)
		var baseline := measure(ground, old.primary, origin)
		var coarse := measure(ground, modern.primary, origin)
		var with_fill := measure(ground, full, origin)
		assert(baseline.unreachable == 0 and coarse.unreachable == 0 and with_fill.unreachable == 0, "主点与补点均应有真实路线")
		print("[PERF] ", JSON.stringify({"map":id, "old_7":baseline, "new_12":coarse, "new_with_fill":with_fill}))
		ground.free()
	print("[AutoRoamRouteBenchmark] 全部通过 ✅")
	get_tree().quit()
