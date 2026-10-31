extends Node
## 巡游稀疏化契约：对正式掩码和没有粗采样点的窄支路验证完整探索区块覆盖。
var failures: Array[String] = []

## 收集失败，使测试仅在所有异步及覆盖检查完成后输出成功标记。
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

## 不入树的Ground仅提供真实掩码；不加载装饰或渲染资源。
func ground_for(path: String) -> IsoGround:
	var ground := IsoGround.new()
	ground.cave = CaveLayout.new(path)
	ground.grid_size = ground.cave.size
	ground.cave.prepare_connectivity()
	return ground

## 通过真实Fog.reveal复核所有可达块，而非使用规划器自己的覆盖函数验证自己。
func verify(ground: IsoGround, map_id: String, origin: Vector2i, plan: Dictionary) -> void:
	var old := GameState.explored_maps.duplicate(true)
	GameState.explored_maps.erase(map_id)
	var combined: Array = []
	combined.append_array(plan.primary)
	combined.append_array(plan.supplements)
	var seen := {}
	for point in combined:
		var cell := Vector2i(Iso.world_to_grid(point).round())
		check(ground.is_walkable_cell(cell) and ground.cave.reachable(origin, cell), "只选择可达走格")
		check(not seen.has(cell), "主点与补点不重复")
		seen[cell] = true
		Fog.reveal(map_id, cell)
	var missed := 0
	for y in range(ground.grid_size.y):
		for x in range(ground.grid_size.x):
			var cell := Vector2i(x, y)
			if ground.is_walkable_cell(cell) and ground.cave.reachable(origin, cell) and not Fog.is_explored(map_id, cell):
				missed += 1
	check(missed == 0, "可达区域没有永久探索漏块 " + map_id)
	GameState.explored_maps = old

## 正式地图数量/生成成本输出供开发记录；合成支路必须由补点覆盖，动态门禁重建后改变范围。
func _ready() -> void:
	GameState.reset_to_defaults()
	for id in ["corruption_source", "c2_lower_works", "c2_ember_furnace", "c7_arena", "c7_boss_field"]:
		var ground := ground_for("res://data/layouts/" + id + ".json")
		var origin := ground.cave.nearest_walkable(Vector2i(8, 8))
		var before := GameState.explored_maps.duplicate(true)
		var start := Time.get_ticks_usec()
		var plan := AutoRoamPlan.build(ground, origin)
		var elapsed := (Time.get_ticks_usec() - start) / 1000.0
		check(GameState.explored_maps == before, "构建计划不提前揭图")
		var incremental := AutoRoamPlan.new(ground, origin)
		var slices: Array[float] = []
		var finished := false
		while not finished:
			var tick := Time.get_ticks_usec()
			finished = incremental.advance()
			slices.append((Time.get_ticks_usec() - tick) / 1000.0)
		check(incremental.primary == plan.primary and incremental.supplements == plan.supplements, "分帧与同步结果一致")
		slices.sort()
		print("[AutoRoamPlanTest] slices=", slices.size(), " p95_ms=", slices[int(slices.size() * 0.95)], " max_ms=", slices[-1])
		verify(ground, id, origin, plan)
		print("[AutoRoamPlanTest] ", id, " primary=", plan.primary.size(), " supplements=", plan.supplements.size(), " build_ms=", elapsed)
		ground.free()
	var rows: Array[String] = []
	for y in range(40):
		var row := ""
		for x in range(40):
			var walk := (x < 16 and y < 32) or (y == 20 and x >= 15 and x < 36) or (x >= 30 and x < 39 and y >= 18 and y < 25) or (x >= 36 and y < 3)
			row += "1" if walk else "0"
		rows.append(row)
	var file := FileAccess.open("user://roam_branch.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"grid_size":[40,40], "walkable_rows":rows}))
	file.close()
	var branch := ground_for("user://roam_branch.json")
	var plan := AutoRoamPlan.build(branch, Vector2i(3, 3))
	check(not plan.supplements.is_empty(), "未命中12格采样的窄支路有补点")
	# 复用正式40以上地图的Fog边界；合成布局只占其左上40×40。
	verify(branch, "corruption_source", Vector2i(3, 3), plan)
	var pilot := AutoBattle.new()
	GameState.current_map = "corruption_source"
	GameState.explored_maps.erase(GameState.current_map)
	pilot._roam_points.assign(plan.primary)
	pilot._roam_primary_count = plan.primary.size()
	pilot._roam_points.append_array(plan.supplements)
	pilot._roam_blocks = plan.blocks
	pilot._roam_index = pilot._roam_primary_count - 1
	pilot._advance_roam()
	check(pilot._roam_fill_active and pilot._roam_index == pilot._roam_primary_count, "粗巡后未知支路进入补漏")
	for point in pilot._roam_points:
		Fog.reveal(GameState.current_map, Vector2i(Iso.world_to_grid(point).round()))
	pilot._roam_fill_active = false
	pilot._roam_index = pilot._roam_primary_count - 1
	pilot._advance_roam()
	check(not pilot._roam_fill_active and pilot._roam_index == 0, "已探索地图跳过细补点")
	pilot.free()
	branch.free()
	var gate := ground_for("res://data/layouts/c2_well_core.json")
	gate.cave.set_access_gate_open(false)
	var gate_origin := gate.cave.nearest_walkable(Vector2i(8, 8))
	var closed := AutoRoamPlan.build(gate, gate_origin)
	verify(gate, "c2_well_core", gate_origin, closed)
	gate.cave.set_access_gate_open(true)
	var opened := AutoRoamPlan.build(gate, gate_origin)
	check(opened.blocks.size() > closed.blocks.size(), "门禁打开后重建扩大巡游区域")
	verify(gate, "c2_well_core", gate_origin, opened)
	gate.free()
	print("[AutoRoamPlanTest] ", "全部通过 ✅" if failures.is_empty() else str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
