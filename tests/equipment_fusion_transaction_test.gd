extends Node
## 铁匠合成交易回归：快照重核、金币校验、唯一产物与 12 星新词条。

var failures: Array[String] = []

## 每个案例使用隔离背包；仅验证实际 GameState 命令，不触碰玩家正式存档。
func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 91244
	GameState.reset_to_defaults()
	var gold_items: Array[Dictionary] = []
	for level in [51, 61, 71, 81]:
		var item := ItemFactory.make_equip_dynamic("c6_equip_weapon", level, "epic", rng)
		gold_items.append(item.duplicate(true))
		GameState.inventory[gold_items.size() - 1] = item
	var stale := gold_items.duplicate(true)
	GameState.inventory[0].star = 1
	var before := GameState.inventory.duplicate(true)
	check(not bool(GameState.forge_equipment(EquipmentFusion.GOLD_TO_PURPLE, stale, "", rng).get("ok", false))
		and GameState.inventory == before, "材料星级变化使整笔合成失败")
	gold_items[0] = GameState.inventory[0].duplicate(true)
	var result := GameState.forge_equipment(EquipmentFusion.GOLD_TO_PURPLE, gold_items, "", rng)
	check(bool(result.get("ok", false)) and GameState.inventory_used() == 1
		and EquipmentFusion.tier_start(result.get("item", {})) == 51
		and SaveManager._valid_item(result.get("item", {})), "混档四金只产一件最低档有效紫装")
	check(not bool(GameState.forge_equipment(EquipmentFusion.GOLD_TO_PURPLE, gold_items, "", rng).get("ok", false))
		and GameState.inventory_used() == 1, "重复点击不能复制合成产物")
	GameState.reset_to_defaults()
	var purples: Array[Dictionary] = []
	for i in range(4):
		var item := ItemFactory.make_equip_dynamic("c6_equip_ring", 61, "legendary", rng)
		item.star = i
		purples.append(item.duplicate(true))
		GameState.inventory[i] = item
	var specified := GameState.forge_equipment(EquipmentFusion.PURPLE_TARGET, purples, "weapon", rng)
	check(bool(specified.get("ok", false)) and Equipment.item_kind(specified.get("item", {})) == "weapon"
		and EquipmentFusion.tier_start(specified.get("item", {})) == 61
		and int(specified.item.star) == 0, "四紫定向生成指定类型 0 星紫装")
	GameState.reset_to_defaults()
	var old := ItemFactory.make_equip_roll("c6_equip_weapon", 51, "legendary", rng)
	old.star = 12
	var fresh := ItemFactory.make_equip_dynamic("c6_equip_weapon", 61, "legendary", rng)
	GameState.inventory[0] = old
	GameState.inventory[1] = fresh
	var pair: Array[Dictionary] = [old.duplicate(true), fresh.duplicate(true)]
	var low_money := GameState.forge_equipment(EquipmentFusion.STAR_TRANSFER, pair, "", rng)
	check(not bool(low_money.get("ok", false)) and GameState.inventory[0] == old
		and GameState.inventory[1] == fresh, "保星金币不足不消耗素材")
	GameState.gold = EquipmentFusion.full_star_cost()
	var advanced := GameState.forge_equipment(EquipmentFusion.STAR_TRANSFER, pair, "", rng)
	var output: Dictionary = advanced.get("item", {})
	check(bool(advanced.get("ok", false)) and GameState.gold == 0 and GameState.inventory_used() == 1
		and int(output.get("star", -1)) == 12 and EquipmentFusion.tier_start(output) == 61
		and String(output.get("instanceId", "")) != String(old.instanceId)
		and String(output.get("instanceId", "")) != String(fresh.instanceId)
		and SaveManager._valid_item(output), "保星消耗两件和全部金币，产出全新 61 档 12 星紫装")
	check(SaveManager.save_slot(3, true), "保星结果可写入隔离槽 3")
	var loaded: Dictionary = SaveManager.read_slot(3)
	var inventory_loaded: Array = (loaded.get("data", {}) as Dictionary).get("inventory", [])
	var saved_item: Dictionary = {}
	for entry in inventory_loaded:
		if entry is Dictionary and String(entry.get("instanceId", "")) == String(output.get("instanceId", "")):
			saved_item = entry
			break
	check(bool(loaded.get("ok", false)) and not saved_item.is_empty()
		and String(saved_item.get("instanceId", "")) == String(output.get("instanceId", ""))
		and int(saved_item.get("requiredLevel", -1)) == int(output.get("requiredLevel", -2))
		and int(saved_item.get("star", -1)) == 12
		and _same_roll(saved_item, output), "读档后保星装备的档位、词条和星级完整保留")
	SaveManager.delete_slot(3)
	if failures.is_empty():
		print("[EquipmentFusionTransactionTest] 全部通过 ✅")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	get_tree().quit(0 if failures.is_empty() else 1)

## 收集失败断言以便一次呈现所有事务边界问题。
func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)

## JSON 读回会把整数写成浮点数，词条按类型和值比较。
func _same_roll(loaded: Dictionary, original: Dictionary) -> bool:
	for key in ["affixes", "pctAttrs"]:
		var actual: Array = loaded.get(key, [])
		var expected: Array = original.get(key, [])
		if actual.size() != expected.size():
			return false
		for i in range(actual.size()):
			if String(actual[i].get("stat", "")) != String(expected[i].get("stat", "")) \
					or not is_equal_approx(float(actual[i].get("value", 0)), float(expected[i].get("value", 0))):
				return false
	return true
