extends Node
## 装备出售预设与收藏保护回归，使用隔离存档环境中的真实装备实例。

var failures: Array[String] = []

## 覆盖预设边界、评分保护、收藏流转与旧实例兼容。
func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 109
	var old_common := ItemFactory.make_equip_roll("shoes_cloth", 1, "common", rng)
	var old_uncommon := ItemFactory.make_equip_roll("shoes_cloth", 1, "uncommon", rng)
	var new_shoes := ItemFactory.make_equip_roll("c2_road_shoes", 11, "common", rng)
	var old_rare := ItemFactory.make_equip_roll("shoes_cloth", 1, "rare", rng)
	GameState.equipment = Equipment.create()
	GameState.equipment.shoes = new_shoes
	GameState.player.level = 15
	var cautious := SellGearPolicy.entry(old_common, 0, 15, GameState.equipment, SellGearPolicy.CAUTIOUS)
	check(bool(cautious.get("default_selected", false)), "谨慎预设选择低十级的普通零星鞋")
	check(not bool(SellGearPolicy.entry(old_uncommon, 1, 15, GameState.equipment, SellGearPolicy.CAUTIOUS).get("default_selected", false)),
		"谨慎预设不默认选择优秀")
	check(bool(SellGearPolicy.entry(old_uncommon, 1, 15, GameState.equipment, SellGearPolicy.STANDARD).get("default_selected", false)),
		"标准预设选择优秀旧装备")
	check(not bool(SellGearPolicy.entry(old_common, 0, 6, GameState.equipment, SellGearPolicy.CAUTIOUS).get("default_selected", false)),
		"谨慎预设仍要求穿戴等级低至少十级")
	GameState.equipment = Equipment.create()
	check(bool(SellGearPolicy.entry(old_rare, 2, 15, GameState.equipment, SellGearPolicy.STANDARD).get("default_selected", false))
		and bool(SellGearPolicy.entry(old_rare, 2, 15, GameState.equipment, SellGearPolicy.AGGRESSIVE).get("default_selected", false)),
		"标准与积极预设均默认选择旧套稀有零星装备")
	GameState.equipment.shoes = new_shoes
	var same_suit := SellGearPolicy.entry(new_shoes, 0, 11, GameState.equipment, SellGearPolicy.STANDARD)
	check(not bool(same_suit.get("default_selected", false))
		and (same_suit.get("reasons") as Array).has("suit")
		and bool(SellGearPolicy.entry(new_shoes, 0, 11, GameState.equipment, SellGearPolicy.AGGRESSIVE).get("default_selected", false)),
		"同套装备：标准按旧套判据排除，积极不限等级默认勾选")
	var starred := old_common.duplicate(true)
	starred.star = 1
	check(not bool(SellGearPolicy.entry(starred, 0, 15, GameState.equipment, SellGearPolicy.CAUTIOUS).get("default_selected", false)),
		"已升星装备不被默认勾选")
	GameState.equipment = Equipment.create()
	var empty_slot := SellGearPolicy.entry(new_shoes, 0, 30, GameState.equipment, SellGearPolicy.AGGRESSIVE)
	check(bool(empty_slot.get("default_selected", false)) and not bool(empty_slot.get("protected_upgrade", false)),
		"空槽不再计入评分保护，积极预设可默认勾选该类装备")
	GameState.inventory[0] = old_common
	check(GameState.set_equipment_favorite(String(old_common.instanceId), true), "背包装备可收藏")
	var locked := SellGearPolicy.entry(GameState.inventory[0], 0, 15, GameState.equipment, SellGearPolicy.CAUTIOUS)
	check(not bool(locked.get("manual_selectable", true)) and not Shop.can_sell(GameState.inventory[0]),
		"收藏装备既不能批选也不能手售")
	check(SaveManager._valid_item(GameState.inventory[0]), "收藏装备可通过存档校验")
	var legacy := old_common.duplicate(true)
	legacy.erase("favorite")
	check(SaveManager._valid_item(legacy) and not bool(legacy.get("favorite", false)), "旧装备无收藏字段仍合法")
	legacy.favorite = "yes"
	check(not SaveManager._valid_item(legacy), "非法收藏字段拒读")
	check(GameState.set_sell_gear_preset(SellGearPolicy.STANDARD) and not GameState.set_sell_gear_preset("unknown"),
		"预设只接受登记值")
	if failures.is_empty():
		print("[SellGearPolicyTest] 全部通过 ✅")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	get_tree().quit(0 if failures.is_empty() else 1)

## 收集失败断言后一次性返回，便于同时定位多个边界问题。
func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
