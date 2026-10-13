extends RefCounted
## 死亡只随机掉落背包中的一件装备；先保证地面容器可用，再从背包移走。

const GROUND_ITEM := preload("res://scenes/entities/GroundItem.tscn")

static func drop_one(player: Node2D, rng: RandomNumberGenerator = null) -> Dictionary:
	if player == null or not is_instance_valid(player):
		return {}
	var layer := player.get_tree().get_first_node_in_group("loot_root") as Node2D
	if layer == null:
		return {}
	var candidates: Array[int] = []
	for i in range(GameState.inventory.size()):
		var item = GameState.inventory[i]
		if item is Dictionary and String(item.get("kind", "")) == "equip":
			candidates.append(i)
	if candidates.is_empty():
		return {}
	var chosen := rng.randi_range(0, candidates.size() - 1) if rng != null else randi_range(0, candidates.size() - 1)
	var index := candidates[chosen]
	var item: Dictionary = GameState.inventory[index]
	var drop := GROUND_ITEM.instantiate() as GroundItem
	if drop == null:
		return {}
	drop.item = item.duplicate(true)
	drop.auto_claim = false
	drop.persistent = false
	drop.position = layer.to_local(player.global_position)
	layer.add_child(drop)
	GameState.remove_item_at(index)
	EventBus.toast_requested.emit("死亡掉落：%s" % ItemUtil.display_name(item), "danger")
	return {"index": index, "item": item.duplicate(true), "node": drop}
