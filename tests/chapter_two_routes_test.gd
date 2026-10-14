extends Node
## Second-chapter data/route contract without writing a player save.

var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("[ChapterTwoRoutesTest] " + message)

func _ready() -> void:
	GameState.reset_to_defaults()
	check(DataLoader.validate_all().is_empty(), "所有数据表通过引用校验")
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
	print("[ChapterTwoRoutesTest] ", "全部通过 ✅" if failures.is_empty() else str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
