extends Node
## 城镇车夫落点验收：检查每座城镇的配置落点、实际出行落点与 NPC 的邻近关系。
## 仅在无头测试运行，复用正式地图与出行服务，不修改玩家磁盘存档。

const TOWNS := ["camp", "c2_well_town", "c3_map00", "c4_map00", "c5_map00", "c6_map00"]
var failures: Array[String] = []

## 记录不符合城镇落点口径的情况，让单个地图错误不阻断后续地图检查。
func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("[TownCarterArrivalTest] " + message)

## 逐座城镇验证可走和距离，并用正式车夫出行入口检查写入的世界坐标。
func _ready() -> void:
	GameState.reset_to_defaults()
	for town_id in TOWNS:
		var data := MapService.data_for(town_id)
		var carters: Array = (data.get("npcs", []) as Array).filter(func(npc: Dictionary) -> bool:
			return String(npc.get("role", "")) == "carter")
		_check(carters.size() == 1, "%s 恰有一名车夫" % town_id)
		if carters.size() != 1:
			continue
		var npc_cell := Vector2i(int(carters[0].cell[0]), int(carters[0].cell[1]))
		var arrival: Array = data.get("carterArrival", [])
		_check(arrival.size() == 2, "%s 配置车夫落点" % town_id)
		if arrival.size() != 2:
			continue
		var arrival_cell := Vector2i(int(arrival[0]), int(arrival[1]))
		var layout := CaveLayout.new(String(data.get("layoutPath", "")))
		_check(layout.is_walkable(arrival_cell), "%s 落点可走" % town_id)
		_check(layout.reachable(arrival_cell, npc_cell), "%s 落点与车夫连通" % town_id)
		_check(arrival_cell.distance_to(npc_cell) >= 1.0 and arrival_cell.distance_to(npc_cell) <= 3.0,
			"%s 落点在车夫身边且不重叠" % town_id)
		_check(MapService.carter_arrival(town_id).is_equal_approx(Iso.grid_to_world(arrival_cell)),
			"%s 运行时车夫落点与配置一致" % town_id)
		if town_id != "camp":
			GameState.current_map = "camp"
			GameState.unlocks[String(data.get("requiresUnlock", ""))] = true
			GameState.mark_visited(town_id)
			GameState.gold = 999999
			var result := MapService.travel_anywhere(town_id)
			_check(bool(result.get("ok", false)), "%s 随身车夫可抵达：%s" % [town_id, result.get("reason", "")])
			if bool(result.get("ok", false)):
				_check(GameState.save_pos.is_equal_approx(Iso.grid_to_world(arrival_cell)),
					"%s 实际出行写入车夫旁落点" % town_id)
				MapService.commit_arrival()
	print("[TownCarterArrivalTest] ", "全部通过" if failures.is_empty() else str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
