extends Node
## 第四章 31—40 地图与交通：六图掩码/导航/出口、NPC/首领/刷新位连通、
## 沉井镇→根驿营地步行边与正向门禁（32 §5 批次 4.1 准出）。

var failures: Array[String] = []

const C4_MAPS := ["c4_map00", "c4_map01", "c4_map02", "c4_map03", "c4_map04", "c4_map05"]

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("[ChapterFourRoutesTest] " + message)

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
	for map_id in C4_MAPS:
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
		check(spawn_cells == 0 if map_id == "c4_map00" else spawn_cells > 0, "%s 刷新位数量符合枢纽/野外口径" % map_id)

	# ② 沉井镇追加边：本批唯一旧图交通改动，落点须在当前实图上真能走到。
	var town := MapService.data_for("c3_map00")
	var town_layout := CaveLayout.new(String(town.get("layoutPath", "")))
	var edge_cell := Vector2i(-1, -1)
	for exit_data in town.get("exits", []):
		if String(exit_data.get("toMap", "")) == "c4_map00":
			edge_cell = _cell(exit_data.cell)
	var town_anchor := town_layout.nearest_walkable(Vector2i(town_layout.size.x / 2, town_layout.size.y / 2))
	check(edge_cell.x >= 0 and edge_cell.y >= 0, "下街水市有通往根驿营地的步行边")
	check(town_layout.is_walkable(edge_cell), "追加边落点 %s 落在可走格" % edge_cell)
	check(town_layout.reachable(town_anchor, edge_cell), "追加边可从镇内走到")
	for npc in town.get("npcs", []):
		check(_cell(npc.cell).distance_to(Vector2(edge_cell)) > 3.0, "追加边不压在 NPC %s 身上" % npc.get("npcId", "?"))

	# ③ 走通追加边与往返：正向进根驿营地，返回边不锁。
	GameState.unlocks["chapter3"] = true
	GameState.unlocks["chapter4"] = true
	GameState.current_map = "c3_map00"
	var forward := _walk("c3_map00_exit03", edge_cell)
	check(bool(forward.get("ok", false)), "下街水市可步行进根驿营地：%s" % forward.get("reason", ""))
	check(GameState.current_map == "c4_map00" and MapService.commit_arrival(), "落进根驿营地")
	var back_exit := MapService.walk_exit("c4_map00_exit01")
	var back := _walk("c4_map00_exit01", _cell(back_exit.cell))
	check(bool(back.get("ok", false)), "返回边不锁：%s" % back.get("reason", ""))
	check(GameState.current_map == "c3_map00" and MapService.commit_arrival(), "退回下街水市")

	# ④ 正向门禁：第四章出口自带锁，未领到旗标时禁止通行；领到后放行。
	GameState.current_map = "c4_map01"
	var gate_exit := MapService.walk_exit("c4_map01_exit02")
	check(not gate_exit.is_empty(), "倒根驿路有通往失声哨林的出口")
	GameState.unlocks.erase("c4_access_02")
	var locked := _walk("c4_map01_exit02", _cell(gate_exit.cell))
	check(not bool(locked.get("ok", false)) and GameState.current_map == "c4_map01", "未解锁的出口禁止通行")
	GameState.unlocks["c4_access_02"] = true
	var opened := _walk("c4_map01_exit02", _cell(gate_exit.cell))
	check(bool(opened.get("ok", false)), "解锁后同一出口放行：%s" % opened.get("reason", ""))
	check(GameState.current_map == "c4_map02" and MapService.commit_arrival(), "落进失声哨林")

	# ⑤ 车夫：门未开不给目的地；已开但没走过不能跳关；到访后按报价扣费。
	GameState.current_map = "c4_map00"
	check(not bool(MapService.travel_to("c4_map05").get("ok", false)), "门禁未开时车夫不给目的地")
	GameState.unlocks["c4_access_05"] = true
	check(not bool(MapService.travel_to("c4_map05").get("ok", false)), "未访问的野外不能车夫跳关")
	GameState.mark_visited("c4_map05")
	GameState.gold = 1000
	var expected_fare := MapService.fee_to("c4_map05")
	var fare := MapService.travel_to("c4_map05")
	check(bool(fare.get("ok", false)), "已访问且门开后可车夫直达：%s" % fare.get("reason", ""))
	check(GameState.gold == 1000 - expected_fare, "车费按枢纽报价扣除")
	check(MapService.fee_to("c4_map00") == expected_fare, "枢纽↔首领图双向报价一致")
	MapService.commit_arrival()

	# ⑥ 运行世界装配：每图按布局装配地面、出口与 NPC。
	for map_id in C4_MAPS:
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

	print("[ChapterFourRoutesTest] ", "全部通过 ✅" if failures.is_empty() else str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
