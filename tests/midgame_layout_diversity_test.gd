extends Node
## 第三至第六章地图差异化验收：检查尺寸唯一、具名点可达以及真实寻路可用。
## 只读运行地图与掩码；耗时仅作诊断，不设置依赖测试机器速度的通过门槛。

var failures: Array[String] = []

## 记录所有失败图，避免第一张有问题时隐藏后续地图的问题。
func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("[MidgameLayoutDiversityTest] " + message)

## 将地图配置中的 `[x,y]` 格坐标转成寻路所用整数格。
func _cell(raw: Variant) -> Vector2i:
	return Vector2i(int(raw[0]), int(raw[1]))

## 汇总入口、出口、NPC、刷新和首领点，确保地形调整不封住玩法目标。
func _fixed_points(data: Dictionary) -> Array[Vector2i]:
	var points: Array[Vector2i] = []
	for exit_data in data.get("exits", []):
		points.append(_cell(exit_data.cell))
	for value in data.get("entrances", {}).values():
		points.append(_cell(value))
	for npc in data.get("npcs", []):
		points.append(_cell(npc.cell))
	for spec in data.get("spawnPoints", []):
		for value in spec.get("cells", []):
			points.append(_cell(value))
	var boss: Variant = data.get("bossSpawn", null)
	if boss is Dictionary:
		for value in boss.get("cells", []):
			points.append(_cell(value))
	points.append(_cell(data.carterArrival))
	return points

## 对全部中段图做真实运行布局与路线验收，输出一次总加载诊断值。
func _ready() -> void:
	GameState.reset_to_defaults()
	var sizes := {}
	var count := 0
	var total_cells := 0
	var start_usec := Time.get_ticks_usec()
	for chapter in range(3, 7):
		for entry in DataLoader.get_table("maps"):
			if not entry is Dictionary:
				continue
			var data: Dictionary = entry
			var map_id := String(data.get("id", ""))
			if not map_id.begins_with("c%d_map" % chapter):
				continue
			count += 1
			var layout := CaveLayout.new(String(data.get("layoutPath", "")))
			layout.prepare_connectivity()
			var size := MapService.grid_size(map_id)
			var size_key := "%dx%d" % [size.x, size.y]
			_check(not sizes.has(size_key), "%s 与 %s 尺寸重复" % [map_id, sizes.get(size_key, "")])
			sizes[size_key] = map_id
			_check(layout.size == size, "%s 运行布局与地图尺寸一致" % map_id)
			total_cells += size.x * size.y
			var fixed := _fixed_points(data)
			var anchor := fixed[0]
			for point in fixed:
				_check(layout.is_walkable(point) and layout.reachable(anchor, point),
					"%s 剧情或交互点 %s 可走且连通" % [map_id, point])
			var farthest := anchor
			for point in fixed:
				if point.distance_squared_to(anchor) > farthest.distance_squared_to(anchor):
					farthest = point
			if farthest != anchor:
				_check(not layout.path(anchor, farthest).is_empty(), "%s 跨图远端可构建实际路线" % map_id)
	_check(count == 25, "第三至第六章共验收 25 张地图，实际 %d" % count)
	print("[MidgameLayoutDiversityTest] %d 图、%d 格，加载与连通准备 %.1f ms；%s" % [
		count, total_cells, float(Time.get_ticks_usec() - start_usec) / 1000.0,
		"全部通过" if failures.is_empty() else str(failures)])
	# 最大轮廓图做一次真实世界装配，记录静态碰撞和装配时间的当前成本。
	GameState.current_map = "c6_map03"
	GameState.save_pos = MapService.entry_point(GameState.current_map)
	GameState.has_save_pos = true
	var assembly_start := Time.get_ticks_usec()
	var world := preload("res://scenes/Game.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
	var walls := world.get_node_or_null("Ground/CaveWalls")
	_check(walls != null, "最大轮廓图装配静态碰撞")
	print("[MidgameLayoutDiversityTest] c6_map03 世界装配 %.1f ms，边界碰撞 %d 个" % [
		float(Time.get_ticks_usec() - assembly_start) / 1000.0,
		walls.get_child_count() if walls != null else -1])
	world.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)
