class_name TravelItem
extends RefCounted
## 回城卷：背包双击和快捷栏共用的使用入口。

static func use_town_scroll(inv_index: int, reload_scene: bool = true) -> Dictionary:
	if inv_index < 0 or inv_index >= GameState.inventory.size() or not GameState.inventory[inv_index] is Dictionary:
		return _fail("背包中没有回城卷")
	var item: Dictionary = GameState.inventory[inv_index]
	if item.get("kind") != "misc" or item.get("itemId") != HotbarConfig.TOWN_SCROLL:
		return _fail("该物品不是回城卷")
	if GameState.current_map == "camp":
		return _fail("已在幸存者营地，无需回城")
	var player := GameState.get_tree().get_first_node_in_group("player") as PlayerCharacter
	if int(GameState.player.get("hp", 0)) <= 0 or (player != null and player.is_dead):
		return _fail("倒下时不能使用回城卷")
	if not MapService.exists("camp"):
		return _fail("营地地图不可用，回城卷未消耗")
	if reload_scene:
		var scene := GameState.get_tree().current_scene
		if scene == null or not scene.has_node("Game"):
			return _fail("当前世界不可用，回城卷未消耗")
	# 所有可能失败的条件先验证；成功后才扣 1 张并安排场景重载。
	var from_map := GameState.current_map
	if int(item.get("count", 1)) > 1:
		item.count = int(item.get("count", 1)) - 1
		EventBus.inventory_changed.emit()
	else:
		GameState.remove_item_at(inv_index)
	GameState.current_map = "camp"
	GameState.save_pos = MapService.entry_point("camp")
	GameState.has_save_pos = true
	GameState.close_all_panels()
	EventBus.map_traveled.emit(from_map, "camp")
	EventBus.map_changed.emit("camp")
	EventBus.toast_requested.emit("使用回城卷，返回幸存者营地", "info")
	if reload_scene:
		MapService.reload_world()
	return {"ok": true, "reason": "", "itemId": HotbarConfig.TOWN_SCROLL}

static func _fail(reason: String) -> Dictionary:
	EventBus.toast_requested.emit(reason, "danger")
	return {"ok": false, "reason": reason}
