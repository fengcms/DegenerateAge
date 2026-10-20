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
	var upgrade_materials: Array[Dictionary] = []
	for i in range(4):
		var material := ItemFactory.make_equip_dynamic("c6_equip_ring", 61, "legendary", rng)
		GameState.inventory[i] = material
		upgrade_materials.append(material.duplicate(true))
	var upgrade_stale := upgrade_materials.duplicate(true)
	GameState.inventory[0].favorite = true
	var protected_bag := GameState.inventory.duplicate(true)
	check(not bool(GameState.forge_equipment(EquipmentFusion.PURPLE_UP_TIER, upgrade_stale, "", rng).get("ok", false))
		and GameState.inventory == protected_bag, "收藏状态变化后四紫升档不吞材料")
	GameState.inventory[0].favorite = false
	upgrade_materials[0].star = 11
	GameState.inventory[0].star = 11
	var upgraded := GameState.forge_equipment(EquipmentFusion.PURPLE_UP_TIER, upgrade_materials, "", rng)
	var upgraded_item: Dictionary = upgraded.get("item", {})
	check(bool(upgraded.get("ok", false)) and GameState.inventory_used() == 1
		and EquipmentFusion.tier_start(upgraded_item) == 71
		and String(upgraded_item.get("quality", "")) == "legendary"
		and int(upgraded_item.get("star", -1)) == 0 and SaveManager._valid_item(upgraded_item),
		"四紫升档消耗四件，生成随机部位的 71 档全新 0 星紫装")
	check(not bool(GameState.forge_equipment(EquipmentFusion.PURPLE_UP_TIER, upgrade_materials, "", rng).get("ok", false))
		and GameState.inventory_used() == 1, "四紫升档重复提交不会复制产物")
	check(SaveManager.save_slot(3, true), "四紫升档结果可写入隔离槽 3")
	var upgraded_loaded: Dictionary = SaveManager.read_slot(3)
	var upgraded_inventory: Array = (upgraded_loaded.get("data", {}) as Dictionary).get("inventory", [])
	check(bool(upgraded_loaded.get("ok", false)) and upgraded_inventory[0] is Dictionary
		and int((upgraded_inventory[0] as Dictionary).get("requiredLevel", 0)) == int(upgraded_item.get("requiredLevel", -1)),
		"四紫升档结果读档后保留新档穿戴等级")
	SaveManager.delete_slot(3)
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
	# ---- 工程 65：材料来自身上穿戴 ----
	GameState.reset_to_defaults()
	var worn_old := ItemFactory.make_equip_roll("c6_equip_weapon", 51, "legendary", rng)
	worn_old.star = 12
	var bag_fresh := ItemFactory.make_equip_dynamic("c6_equip_weapon", 61, "legendary", rng)
	GameState.equipment["weapon"] = worn_old
	GameState.inventory[0] = bag_fresh
	GameState.gold = EquipmentFusion.full_star_cost()
	check(String(GameState.find_owned_item(String(worn_old.instanceId)).get("loc", "")) == "worn"
		and int(GameState.find_owned_item(String(worn_old.instanceId)).get("index", 0)) == -1,
		"find_owned_item 能定位身上穿戴的那件")
	var worn_pair: Array[Dictionary] = [worn_old.duplicate(true), bag_fresh.duplicate(true)]
	var worn_result := GameState.forge_equipment(EquipmentFusion.STAR_TRANSFER, worn_pair, "", rng)
	var worn_output: Dictionary = worn_result.get("item", {})
	check(bool(worn_result.get("ok", false)) and GameState.equipment.get("weapon") == null
		and GameState.gold == 0 and GameState.inventory_used() == 1
		and String(GameState.inventory[0].get("instanceId", "")) == String(worn_output.get("instanceId", ""))
		and int(worn_output.get("star", -1)) == 12,
		"身上旧件被消耗、该槽清空、产物进背包且金币只扣一次")
	check(String(GameState.find_owned_item(String(worn_old.instanceId)).get("loc", "")) == "",
		"被消耗的穿戴件不再能被定位")
	check(SaveManager.save_slot(3, true), "穿戴件被消耗后仍可写入隔离槽 3")
	var worn_loaded: Dictionary = SaveManager.read_slot(3)
	var worn_slots_loaded: Dictionary = (worn_loaded.get("data", {}) as Dictionary).get("equipment", {})
	check(bool(worn_loaded.get("ok", false)) and worn_slots_loaded.get("weapon", "missing") == null,
		"读档后穿戴槽为空且整档未被判毁")
	SaveManager.delete_slot(3)
	# 背包已满 + 两件材料都在身上：正常玩法不可达（保星两件同部位、第二格只收背包），
	# 这条守的是「先判落点、再扣费」的顺序，属于防御性分支，用构造状态验证。
	GameState.reset_to_defaults()
	var full_a := ItemFactory.make_equip_roll("c6_equip_weapon", 51, "legendary", rng)
	full_a.star = 12
	var full_b := ItemFactory.make_equip_dynamic("c6_equip_weapon", 61, "legendary", rng)
	GameState.equipment["weapon"] = full_a
	GameState.equipment["weapon_bak"] = full_b
	for i in range(GameState.inventory.size()):
		GameState.inventory[i] = {"kind": "misc", "itemId": "filler", "count": 1}
	GameState.gold = EquipmentFusion.full_star_cost()
	var blocked: Array[Dictionary] = [full_a.duplicate(true), full_b.duplicate(true)]
	var full_result := GameState.forge_equipment(EquipmentFusion.STAR_TRANSFER, blocked, "", rng)
	check(not bool(full_result.get("ok", false)) and String(full_result.get("reason", "")).contains("背包已满")
		and GameState.gold == EquipmentFusion.full_star_cost()
		and GameState.equipment.get("weapon") == full_a and GameState.equipment.get("weapon_bak") == full_b,
		"背包无空位时在扣费前拒绝，材料与金币原样不动")
	# 既不在背包也不在身上：必须报「材料已变化」，不能悄悄当成背包件处理。
	GameState.reset_to_defaults()
	var ghost_a := ItemFactory.make_equip_roll("c6_equip_weapon", 51, "legendary", rng)
	ghost_a.star = 12
	var ghost_b := ItemFactory.make_equip_dynamic("c6_equip_weapon", 61, "legendary", rng)
	var ghosts: Array[Dictionary] = [ghost_a.duplicate(true), ghost_b.duplicate(true)]
	var ghost_result := GameState.forge_equipment(EquipmentFusion.STAR_TRANSFER, ghosts, "", rng)
	check(not bool(ghost_result.get("ok", false))
		and String(ghost_result.get("reason", "")).contains("材料已变化"),
		"背包与身上都找不到的实例不能当材料")
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
