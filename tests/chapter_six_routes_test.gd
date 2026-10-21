extends Node
## 第六章 51—60 地图与交通：六图掩码/导航/出口、NPC/首领/刷新位连通、
## 断旗关→镇脉前哨步行边与正向门禁（34 §5 批次 6.1 准出）。

var failures: Array[String] = []

const C6_MAPS := ["c6_map00", "c6_map01", "c6_map02", "c6_map03", "c6_map04", "c6_map05"]

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("[ChapterSixRoutesTest] " + message)

func _cell(raw: Variant) -> Vector2i:
	return Vector2i(int(raw[0]), int(raw[1]))

func _spec_cells(spec: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var raw: Variant = spec.get("cells", [])
	if raw is Array:
		for c in (raw as Array):
			out.append(_cell(c))
	return out

## 上一次步行的防抖复位（测试连续走图时会撞上 1 秒冷却）。
func _walk(exit_id: String, cell: Vector2i) -> Dictionary:
	MapService.walk_key_released = true
	MapService.walk_locked_until_msec = 0
	return MapService.request_walk(exit_id, Iso.grid_to_world(cell))

func _ready() -> void:
	GameState.reset_to_defaults()
	var issues := DataLoader.validate_all()
	check(issues.is_empty(), "所有数据表通过引用校验：%s" % str(issues))

	# ① 静态掩码与连通：出口、入口、NPC、首领、刷新位都在可走格且与主区连通。
	for map_id in C6_MAPS:
		var map_data := MapService.data_for(map_id)
		var layout := CaveLayout.new(String(map_data.get("layoutPath", "")))
		check(layout.size == MapService.grid_size(map_id), "%s 网格尺寸与布局一致" % map_id)
		var anchor := layout.nearest_walkable(Vector2i(layout.size.x / 2, layout.size.y / 2))
		for exit_data in map_data.get("exits", []):
			var cell := _cell(exit_data.cell)
			check(layout.is_walkable(cell), "%s 的出口 %s 落在可走格" % [map_id, exit_data.id])
			check(layout.reachable(anchor, cell), "%s 的出口 %s 与主区连通" % [map_id, exit_data.id])
		for entrance_id in map_data.get("entrances", {}):
			var cell := _cell(map_data.entrances[entrance_id])
			check(layout.is_walkable(cell), "%s 的入口 %s 落在可走格" % [map_id, entrance_id])
			check(layout.reachable(anchor, cell), "%s 的入口 %s 与主区连通" % [map_id, entrance_id])
		check(layout.is_walkable(_cell(map_data.carterArrival)), "%s 的车夫抵达点落在可走格" % map_id)
		for npc in map_data.get("npcs", []):
			var cell := _cell(npc.cell)
			check(layout.is_walkable(cell) and layout.reachable(anchor, cell), "%s 的 NPC %s 可走到" % [map_id, npc.get("npcId", "?")])
		var boss: Variant = map_data.get("bossSpawn", null)
		if boss is Dictionary:
			for cell in _spec_cells(boss):
				check(layout.is_walkable(cell) and layout.reachable(anchor, cell), "%s 的首领位 %s 可走到" % [map_id, cell])
		var spawn_cells := 0
		for spec in map_data.get("spawnPoints", []):
			for cell in _spec_cells(spec):
				spawn_cells += 1
				if not layout.is_walkable(cell) or not layout.reachable(anchor, cell):
					check(false, "%s 的刷新位 %s 不可达" % [map_id, cell])
		check(spawn_cells == 0 if map_id == "c6_map00" else spawn_cells > 0, "%s 刷新位数量符合枢纽/野外口径" % map_id)

	# ② 跨章步行先进入野外，再进入新城；旧城不能直接穿到新城。
	var previous := MapService.data_for("c5_map00")
	var previous_layout := CaveLayout.new(String(previous.get("layoutPath", "")))
	var edge_cell := Vector2i(-1, -1)
	for exit_data in previous.get("exits", []):
		check(String(exit_data.get("toMap", "")) != "c6_map00", "相邻城镇没有直连步行边")
		if String(exit_data.get("id", "")) == "c5_map00_exit03":
			check(String(exit_data.get("toMap", "")) == "c6_map01", "跨章出口先通往野外")
			edge_cell = _cell(exit_data.cell)
	check(edge_cell.x >= 0 and previous_layout.is_walkable(edge_cell), "跨章出口落在可走格")
	for npc in previous.get("npcs", []):
		check(_cell(npc.cell).distance_to(Vector2(edge_cell)) > 3.0, "跨章出口不压在 NPC %s 身上" % npc.get("npcId", "?"))

	# ③ 完成四段往返：前城 → 野外 → 新城 → 野外 → 前城。
	GameState.unlocks["chapter5"] = true
	GameState.unlocks["chapter6"] = true
	GameState.current_map = "c5_map00"
	var forward := _walk("c5_map00_exit03", edge_cell)
	check(bool(forward.get("ok", false)), "前城可步行进入野外：%s" % forward.get("reason", ""))
	check(GameState.current_map == "c6_map01" and MapService.commit_arrival(), "先落进跨章野外")
	var into_town := MapService.walk_exit("c6_map01_exit01")
	check(not into_town.is_empty(), "野外存在进入新城的出口")
	if not into_town.is_empty():
		var enter_result := _walk("c6_map01_exit01", _cell(into_town.cell))
		check(bool(enter_result.get("ok", false)), "野外可步行进新城：%s" % enter_result.get("reason", ""))
		check(GameState.current_map == "c6_map00" and MapService.commit_arrival(), "落进新城")
	var back_to_field := MapService.walk_exit("c6_map00_exit02")
	check(not back_to_field.is_empty(), "新城有回野外的出口")
	if not back_to_field.is_empty():
		var back_result := _walk("c6_map00_exit02", _cell(back_to_field.cell))
		check(bool(back_result.get("ok", false)), "新城可返回野外：%s" % back_result.get("reason", ""))
		check(GameState.current_map == "c6_map01" and MapService.commit_arrival(), "退回野外")
	var back_to_previous := MapService.walk_exit("c6_map01_to_previous")
	check(not back_to_previous.is_empty(), "野外有回前城的出口")
	if not back_to_previous.is_empty():
		var previous_result := _walk("c6_map01_to_previous", _cell(back_to_previous.cell))
		check(bool(previous_result.get("ok", false)), "野外可返回前城：%s" % previous_result.get("reason", ""))
		check(GameState.current_map == "c5_map00" and MapService.commit_arrival(), "退回前城")

	# ④ 正向门禁：第六章野外出口自带锁，未领到旗标时禁止通行；领到后放行。
	GameState.current_map = "c6_map01"
	var gate_exit := MapService.walk_exit("c6_map01_exit02")
	check(not gate_exit.is_empty(), "埋光外廊有通往守誓兵库的出口")
	GameState.unlocks.erase("c6_access_02")
	var locked := _walk("c6_map01_exit02", _cell(gate_exit.cell))
	check(not bool(locked.get("ok", false)) and GameState.current_map == "c6_map01", "未解锁的出口禁止通行")
	GameState.unlocks["c6_access_02"] = true
	var opened := _walk("c6_map01_exit02", _cell(gate_exit.cell))
	check(bool(opened.get("ok", false)), "解锁后同一出口放行：%s" % opened.get("reason", ""))
	check(GameState.current_map == "c6_map02" and MapService.commit_arrival(), "落进守誓兵库")

	# ⑤ 车夫：门未开不给目的地；已开但没走过不能跳关；到访后按报价扣费。
	GameState.current_map = "c6_map00"
	GameState.unlocks.erase("c6_access_02")
	check(not bool(MapService.travel_to("c6_map02").get("ok", false)), "门禁未开时车夫不给目的地")
	GameState.unlocks["c6_access_02"] = true
	check(not bool(MapService.travel_to("c6_map02").get("ok", false)), "未访问的野外不能车夫跳关")
	GameState.mark_visited("c6_map02")
	GameState.gold = 1000
	var expected_fare := MapService.fee_to("c6_map02")
	var fare := MapService.travel_to("c6_map02")
	check(bool(fare.get("ok", false)), "已访问且门开后可车夫直达：%s" % fare.get("reason", ""))
	check(GameState.gold == 1000 - expected_fare, "车费按枢纽报价扣除")
	check(MapService.fee_to("c6_map00") == expected_fare, "枢纽↔首领图双向报价一致")
	MapService.commit_arrival()

	# ⑥ 运行世界装配：每图按布局装配地面、出口与 NPC。
	for map_id in C6_MAPS:
		GameState.current_map = map_id
		GameState.save_pos = MapService.entry_point(map_id)
		GameState.has_save_pos = true
		var live := preload("res://scenes/Game.tscn").instantiate()
		add_child(live)
		await get_tree().process_frame
		var map_data := MapService.data_for(map_id)
		var ground := live.get_node("Ground") as IsoGround
		check(ground.map_id == map_id and ground.cave != null, "%s 可装配运行世界" % map_id)
		check(live.get_node("Exits").get_child_count() == map_data.exits.size(), "%s 出口数量正确" % map_id)
		check(live.get_node("Npcs").get_child_count() == map_data.npcs.size(), "%s NPC 数量正确" % map_id)
		live.queue_free()
		await get_tree().process_frame

	print("[ChapterSixRoutesTest] ", "全部通过 ✅" if failures.is_empty() else str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
