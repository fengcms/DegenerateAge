extends Node
## Second-chapter data/route contract without writing a player save.

var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("[ChapterTwoRoutesTest] " + message)

func _ready() -> void:
	GameState.reset_to_defaults()
	var issues := DataLoader.validate_all()
	check(issues.is_empty(), "所有数据表通过引用校验：%s" % str(issues))
	var ids := ["camp", "wild_trial", "ash_land", "corruption_source",
		"c2_well_town", "c2_pipe_slope", "c2_old_well", "c2_lower_works",
		"c2_ember_furnace", "c2_well_core"]
	for map_id in ids:
		var map_data := MapService.data_for(map_id)
		var layout := CaveLayout.new(String(map_data.get("layoutPath", "")))
		check(layout.size == MapService.grid_size(map_id), "%s 网格尺寸一致" % map_id)
		for entry in map_data.get("exits", []):
			var cell := Vector2i(int(entry.cell[0]), int(entry.cell[1]))
			check(layout.is_walkable(cell), "%s 出口落在可走格" % map_id)
			var target := MapService.data_for(String(entry.toMap))
			check(target.get("entrances", {}).has(String(entry.toEntrance)), "%s 出口有目标落点" % map_id)
		for cell in map_data.get("entrances", {}).values():
			check(layout.is_walkable(Vector2i(int(cell[0]), int(cell[1]))), "%s 入口落在可走格" % map_id)
	GameState.current_map = "camp"
	check(not MapService.is_unlocked("c2_well_town"), "未完成第一章不能入镇")
	GameState.unlocks["chapter2"] = true
	var gate := MapService.walk_exit("to_c2")
	check(not gate.is_empty(), "营地有第二章入口")
	var gate_cell := Vector2i(int(gate.cell[0]), int(gate.cell[1]))
	var travel := MapService.request_walk("to_c2", Iso.grid_to_world(gate_cell))
	check(bool(travel.get("ok", false)), "完成第一章后能步行入镇")
	check(GameState.current_map == "c2_well_town", "入镇切图")
	check(GameState.save_pos == Iso.grid_to_world(Vector2i(6, 27)), "落在新版沉井镇入口")
	check(MapService.commit_arrival(), "到站事务完成")
	check(not MapService.is_unlocked("c2_well_core"), "井心仍由剧情锁控制")
	var main := preload("res://scenes/Main.tscn").instantiate()
	add_child(main)
	var ground := main.get_node("Game/Ground") as IsoGround
	check(ground.map_id == "c2_well_town" and ground.cave != null, "沉井镇世界按新版布局装配")
	check(main.get_node("Game/Npcs").get_child_count() == 8, "沉井镇装配八名故事 NPC")
	check(main.get_node("Game/Exits").get_child_count() == 2, "沉井镇装配双向道路")
	main.queue_free()
	await get_tree().process_frame
	GameState.current_map = "c2_well_core"
	GameState.unlocks["c2_backup_furnace"] = true
	var core := preload("res://scenes/Game.tscn").instantiate()
	add_child(core)
	var core_ground := core.get_node("Ground") as IsoGround
	var boss_point := Iso.grid_to_world(Vector2i(177, 58))
	check(core_ground.is_locked_boss_area(boss_point), "Q10 交付前主机场地被锁住")
	check(core_ground.route(Iso.grid_to_world(Vector2i(143, 58)), boss_point).is_empty(), "门禁与寻路使用同一阻挡网格")
	check(not core.request_map_move(boss_point), "点击封锁区给出拒绝，不会自动绕行穿门")
	GameState.unlocks["c2_core_access"] = true
	EventBus.quest_rewarded.emit("C2Q10")
	check(not core_ground.is_locked_boss_area(boss_point), "领奖后主机场地即时开放")
	check(not core_ground.route(Iso.grid_to_world(Vector2i(143, 58)), boss_point).is_empty(), "领奖后寻路可穿过安全锁")
	var old_pos := Iso.grid_to_world(Vector2i(20, 20))
	var save := SaveManager._collect()
	save.erase("mapLayoutVersion")
	save.currentMap = "camp"
	save.playerPos = [old_pos.x, old_pos.y]
	save.spawnRespawn = {"camp#dummy#0": {"readyAt": 25.0, "pos": [old_pos.x, old_pos.y]}}
	save.unclaimedLoot = {"camp": [{"uid": "layout-test", "batchId": "old",
		"item": {"kind": "coin", "itemId": "coin", "gold": 5, "count": 1}, "pos": [old_pos.x, old_pos.y]}]}
	check(SaveManager._is_valid_save(save), "未标布局版本的 schema11 第一章存档仍可读取")
	var migrated := SaveManager._migrate(save)
	check(migrated.mapLayoutVersion == SaveManager.CURRENT_CAMP_LAYOUT_VERSION, "迁移后标记新版布局")
	check(migrated.playerPos != save.playerPos and migrated.spawnRespawn["camp#dummy#0"].pos == migrated.playerPos
		and migrated.unclaimedLoot.camp[0].pos == migrated.playerPos, "玩家、墓碑与未领掉落同步迁移")
	check(SaveManager._migrate(migrated).playerPos == migrated.playerPos, "重复读取不会再次迁移坐标")
	core.queue_free()
	await get_tree().process_frame
	for map_id in ids.slice(4):
		GameState.current_map = map_id
		GameState.save_pos = MapService.entry_point(map_id)
		GameState.has_save_pos = true
		var live := preload("res://scenes/Game.tscn").instantiate()
		add_child(live)
		await get_tree().process_frame
		var map_data := MapService.data_for(map_id)
		var ground_live := live.get_node("Ground") as IsoGround
		check(ground_live.map_id == map_id and ground_live.cave != null, "%s 可装配运行世界" % map_id)
		check(live.get_node("Exits").get_child_count() == map_data.exits.size(), "%s 双向道路数量正确" % map_id)
		check(live.get_node("Npcs").get_child_count() == map_data.npcs.size(), "%s NPC 数量正确" % map_id)
		for exit_data in map_data.exits:
			var to_cell := Vector2i(int(exit_data.cell[0]), int(exit_data.cell[1]))
			var start := Vector2i(Iso.world_to_grid(ground_live.get_map_center_world()).round())
			check(not ground_live.cave.path(start, to_cell).is_empty(), "%s 的 %s 出口可抵达" % [map_id, exit_data.id])
		live.queue_free()
		await get_tree().process_frame
	print("[ChapterTwoRoutesTest] ", "全部通过 ✅" if failures.is_empty() else str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
