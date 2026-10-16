class_name TravelItem
extends RefCounted
## 回城卷：背包双击和快捷栏共用的使用入口；按地图所属枢纽返回城镇。

## 使用回城卷返回当前地图所属集群的安全城镇，所有失败条件均在扣卷前验证。
static func use_town_scroll(inv_index: int, reload_scene: bool = true) -> Dictionary:
	if inv_index < 0 or inv_index >= GameState.inventory.size() or not GameState.inventory[inv_index] is Dictionary:
		return _fail(Localization.tr_key("msg.travel_item.p001"))
	var item: Dictionary = GameState.inventory[inv_index]
	if item.get("kind") != "misc" or item.get("itemId") != HotbarConfig.TOWN_SCROLL:
		return _fail(Localization.tr_key("msg.travel_item.p002"))
	var town_id := MapService.safe_town_for(GameState.current_map)
	if town_id == GameState.current_map:
		return _fail(Localization.tr_key("msg.travel_item.p003"))
	var player := GameState.get_tree().get_first_node_in_group("player") as PlayerCharacter
	if int(GameState.player.get("hp", 0)) <= 0 or (player != null and player.is_dead):
		return _fail(Localization.tr_key("msg.travel_item.p004"))
	if town_id.is_empty():
		return _fail(Localization.tr_key("msg.travel_item.p005"))
	if reload_scene and GameState.get_tree().get_first_node_in_group("map_world") == null:
		return _fail(Localization.tr_key("msg.travel_item.p006"))
	# 所有可能失败的条件先验证；成功后才扣 1 张并安排场景重载。
	var from_map := GameState.current_map
	if int(item.get("count", 1)) > 1:
		item.count = int(item.get("count", 1)) - 1
		EventBus.inventory_changed.emit()
	else:
		GameState.remove_item_at(inv_index)
	GameState.current_map = town_id
	GameState.save_pos = MapService.entry_point(town_id)
	GameState.has_save_pos = true
	GameState.close_all_panels()
	EventBus.map_traveled.emit(from_map, town_id)
	EventBus.map_changed.emit(town_id)
	EventBus.toast_requested.emit(Localization.tr_key("msg.travel_item.p007") % MapService.display_name(town_id), "info")
	if reload_scene:
		MapService.reload_world()
	return {"ok": true, "reason": "", "itemId": HotbarConfig.TOWN_SCROLL}

## 随机券只在当前地图移动；先找到有效落点再扣物，不会穿墙或落在不可通行格。
static func use_random_ticket(inv_index: int, rng: RandomNumberGenerator = null) -> Dictionary:
	if inv_index < 0 or inv_index >= GameState.inventory.size() or not GameState.inventory[inv_index] is Dictionary:
		return _fail(Localization.tr_key("msg.travel_item.p008"))
	var item: Dictionary = GameState.inventory[inv_index]
	if item.get("kind") != "misc" or item.get("itemId") != HotbarConfig.RANDOM_TICKET:
		return _fail(Localization.tr_key("msg.travel_item.p009"))
	var player := GameState.get_tree().get_first_node_in_group("player") as PlayerCharacter
	if player == null or player.is_dead or int(GameState.player.get("hp", 0)) <= 0:
		return _fail(Localization.tr_key("msg.travel_item.p010"))
	if not MapService.pending_travel.is_empty():
		return _fail(Localization.tr_key("msg.travel_item.p011"))
	var ground := GameState.get_tree().get_first_node_in_group("map_ground") as IsoGround
	if ground == null:
		return _fail(Localization.tr_key("msg.travel_item.p012"))
	var destination := _random_destination(ground, player.global_position, rng)
	if not destination.is_finite():
		return _fail(Localization.tr_key("msg.travel_item.p013"))
	if int(item.get("count", 1)) > 1:
		item.count = int(item.get("count", 1)) - 1
		EventBus.inventory_changed.emit()
	else:
		GameState.remove_item_at(inv_index)
	player.clear_travel_intent()
	player.begin_manual_command()
	player.global_position = destination
	var camera := GameState.get_tree().get_first_node_in_group("player_camera") as Camera2D
	if camera != null:
		camera.reset_smoothing()
	EventBus.toast_requested.emit(Localization.tr_key("msg.travel_item.p014"), "info")
	SaveManager.request_autosave()
	return {"ok": true, "reason": "", "itemId": HotbarConfig.RANDOM_TICKET, "position": destination}

static func _random_destination(ground: IsoGround, origin: Vector2, rng: RandomNumberGenerator = null) -> Vector2:
	if ground == null or ground.grid_size.x < 5 or ground.grid_size.y < 5:
		return Vector2.INF
	for _attempt in range(128):
		var col := rng.randi_range(2, ground.grid_size.x - 3) if rng != null else randi_range(2, ground.grid_size.x - 3)
		var row := rng.randi_range(2, ground.grid_size.y - 3) if rng != null else randi_range(2, ground.grid_size.y - 3)
		var cell := Vector2i(col, row)
		if not ground.is_walkable_cell(cell):
			continue
		var destination := Iso.grid_to_world(cell)
		if origin.distance_to(destination) < 4.0 * Iso.TILE_W:
			continue
		if ground.cave != null and ground.route(origin, destination).is_empty():
			continue
		return destination
	return Vector2.INF

static func _fail(reason: String) -> Dictionary:
	EventBus.toast_requested.emit(reason, "danger")
	return {"ok": false, "reason": reason}
