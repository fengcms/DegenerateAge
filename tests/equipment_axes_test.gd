extends Node
## 两档同名装备的目录、生成、掉落、任务和旧档迁移回归。
## 使用隔离项目运行，不读取玩家真实存档；只验证规则与实例数据，不评估实际战斗平衡。

var failures: Array[String] = []

## 逐型号验证唯一档位和五品质，再检查来源池及旧实例转换。
func _ready() -> void:
	check(DataLoader.validate_all().is_empty(), "装备与掉落配置应通过启动校验")
	# 战斗词条中仅 cdr（冷却缩减）已接线并开放（D7：基础 + 装备按加法累加、截断上限 50%）；
	# 其余（暴击/暴伤/攻速/闪避/格挡/移速）执行链尚未接线，配置层仍不产出。
	# cdr 开放后人物面板与战斗结算已同口径（面板 cdr 显示 total_cdr()），故不再构成可失败闸门。
	var rules: Dictionary = DataLoader.get_table("equipmentRules")
	var producible := {}
	var fixed: Dictionary = rules.get("fixedAffixes", {})
	var percent: Dictionary = rules.get("percentAffixes", {})
	for key in fixed.keys():
		producible[String(key)] = true
	for key in percent.keys():
		producible[String(key)] = true
	check(producible.has("cdr"), "冷却缩减已接线并开放（D7）")
	for key in ["criticalChance", "criticalMultiplier", "attackInterval", "dodge", "block", "movementSpeed"]:
		check(not producible.has(key), "战斗词条 %s 暂不开放（执行链未接线）" % key)
	var rng := RandomNumberGenerator.new()
	rng.seed = 190021
	var qualities := ["common", "uncommon", "rare", "epic", "legendary"]
	var templates: Array = DataLoader.get_table("equipments")
	check(templates.size() == 30, "正式型号为三档共三十种")
	var coverage := {1: {}, 11: {}, 21: {}}
	var expected_order := ["weapon", "shoes", "armor", "helmet", "bracer", "knee", "shield", "bracelet", "ring", "necklace"]
	for tpl in templates:
		var bases: Dictionary = tpl.get("tierBases", {})
		check(bases.size() == 1, "%s 只有一个穿戴档" % tpl.id)
		check((tpl.get("affixPool", []) as Array).has("cdr"), "%s 词条池含冷却缩减（D7）" % tpl.id)
		if bases.size() != 1:
			continue
		var tier := int(bases.keys()[0])
		check(coverage.has(tier), "%s 档位合法" % tpl.id)
		if not coverage.has(tier):
			continue
		check(int(tpl.requiredLevel) == tier + expected_order.find(String(tpl.slot)), "%s 按部位逐级开放" % tpl.id)
		check(not coverage[tier].has(tpl.slot), "Lv%d %s 只有一个型号" % [tier, tpl.slot])
		coverage[tier][tpl.slot] = tpl.id
		for i in range(qualities.size()):
			var item := ItemFactory.make_equip_roll(String(tpl.id), tier, qualities[i], rng)
			check(not item.is_empty(), "%s %s 可生成" % [tpl.id, qualities[i]])
			if item.is_empty():
				continue
			check(int(item.requiredLevel) == int(tpl.requiredLevel) and int(item.level) == int(tpl.requiredLevel) and item.rawBaseAttrs == bases[str(tier)],
				"装备名称、门槛和基础值共用唯一档")
			check(item.affixes.size() + item.pctAttrs.size() == i and int(item.star) == 0,
				"品质词条数和初始星级")
			check(SaveManager._valid_item(item), "生成实例可存档")
		for other in [1, 11, 21]:
			if other != tier:
				check(not bases.has(str(other)), "错档型号没有可借用的基底")
	for tier in coverage:
		check(coverage[tier].size() == 10, "Lv%d 覆盖十类部位" % tier)
	for pool_id in ["normal", "legendary", "c2_normal", "c2_legendary", "c3_normal", "c3_legendary"]:
		var pool: Dictionary = DataLoader.get_entry("lootPools", pool_id)
		check(pool.get("includeIds", []).size() == 10, "%s 显式限定十种型号" % pool_id)
	var pool_of := {
		1: {"legendary": "legendary", "normal": "normal"},
		11: {"legendary": "c2_legendary", "normal": "c2_normal"},
		21: {"legendary": "c3_legendary", "normal": "c3_normal"},
	}
	for table in DataLoader.get_table("dropTables"):
		var tier := _tier_of(String(table.id))
		for entry in table.entries:
			if entry.get("kind") == "equip":
				check(int(entry.get("tierStart", 0)) == tier, "%s 来源固定档位" % table.id)
				var weights: Dictionary = entry.get("qualityWeight", {})
				var only_legendary := weights.size() == 1 and weights.has("legendary")
				check(entry.get("templatePool") == pool_of[tier]["legendary" if only_legendary else "normal"],
					"%s 使用本档型号池" % table.id)
	for _i in range(250):
		for table_id in ["DT_Wild_L1", "DT_Boss_L1", "DT_C2_Normal", "DT_C2_Boss_Final", "DT_C3_Normal", "DT_C3_Elite", "DT_C3_Boss"]:
			var expected_tier := _tier_of(table_id)
			for item in Loot.roll(table_id, rng):
				if item.get("kind") == "equip":
					check(int(item.requiredLevel) == int(DataLoader.get_entry("equipments", item.itemId).requiredLevel) and coverage[expected_tier].values().has(item.itemId),
						"%s 不跨档混入其他型号" % table_id)
	var sample := ItemFactory.make_equip_roll("shoes_cloth", 1, "legendary", rng)
	var white := ItemFactory.make_equip_roll("shoes_cloth", 1, "common", rng)
	check(is_equal_approx(float(EquipmentMath.base_attrs(sample).def),
		float(EquipmentMath.base_attrs(white).def) * 2.4), "品质只放大基础")
	var base := EquipmentMath.effective_attrs(sample)
	sample.star = 12
	var boosted := EquipmentMath.effective_attrs(sample)
	for stat in base:
		check(is_equal_approx(float(boosted[stat]), float(base[stat]) * 2.2), "12 星整件贡献放大：%s" % stat)
	check(not Equipment.meets_level(ItemFactory.make_equip("c2_road_blade"), 10)
		and Equipment.meets_level(ItemFactory.make_equip("c2_road_blade"), 11), "Lv11 穿戴门槛")
	check(Shop.base_value(ItemFactory.make_equip("c2_road_blade")) > Shop.base_value(ItemFactory.make_equip("weapon_iron")),
		"第二档基础售价较高")
	var necklace := ItemFactory.make_equip("necklace_basic")
	check(int(necklace.requiredLevel) == 10 and Shop.base_value(necklace) == int(DataLoader.get_entry("equipments", "necklace_basic").price),
		"Lv10 项链依然按第一套定价")
	var road_shoes := ItemFactory.make_equip("c2_road_shoes")
	check(not Equipment.meets_level(road_shoes, 11) and Equipment.meets_level(road_shoes, 12), "山路靴须达到 Lv12")
	var save := SaveManager._collect()
	check(SaveManager._is_valid_save(save), "当前版本可存档")
	var old := ItemFactory.make_equip("weapon_iron")
	old.equipmentRuleVersion = 2
	old.itemId = "weapon_wolfking"
	old.requiredLevel = 10
	old.level = 10
	old.rawBaseAttrs = {"atk": 12}
	old.star = 7
	save.inventory[0] = old
	save.schemaVersion = 11
	check(SaveManager._is_valid_save(save), "v11 存档可迁移")
	var migrated := SaveManager._migrate(save)
	check(int(migrated.schemaVersion) == 13 and migrated.inventory[0].itemId == "weapon_iron"
		and int(migrated.inventory[0].requiredLevel) == 1 and int(migrated.inventory[0].star) == 7
		and migrated.inventory[0].instanceId == old.instanceId, "旧装备归档且保留实例、星级")
	check(SaveManager._migrate(migrated) == migrated, "迁移重复执行不改变结果")
	var previous_save := SaveManager._collect()
	previous_save.schemaVersion = 12
	previous_save.player.level = 11
	var previous_shoes := ItemFactory.make_equip("c2_road_shoes")
	previous_shoes.equipmentRuleVersion = 3
	previous_shoes.requiredLevel = 11
	previous_shoes.level = 11
	previous_shoes.star = 5
	previous_save.equipment.shoes = previous_shoes
	var stored_ring := ItemFactory.make_equip("c2_road_ring")
	stored_ring.equipmentRuleVersion = 3
	stored_ring.requiredLevel = 11
	stored_ring.level = 11
	previous_save.warehouse[0] = stored_ring
	var ground_necklace := ItemFactory.make_equip("necklace_basic")
	ground_necklace.equipmentRuleVersion = 3
	ground_necklace.requiredLevel = 1
	ground_necklace.level = 1
	previous_save.unclaimedLoot = {"camp": [{"uid": "old_necklace", "batchId": "old_batch",
		"item": ground_necklace, "pos": [0.0, 0.0]}]}
	var previous_attrs: Dictionary = previous_shoes.rawBaseAttrs.duplicate(true)
	check(SaveManager._is_valid_save(previous_save), "v12 越级已穿装备可安全迁移")
	var updated_save := SaveManager._migrate(previous_save)
	check(updated_save.equipment.shoes == null and updated_save.inventory[0].instanceId == previous_shoes.instanceId,
		"Lv11 已穿山路靴提高到 Lv12 后返还背包")
	check(int(updated_save.inventory[0].requiredLevel) == 12 and int(updated_save.inventory[0].star) == 5
		and updated_save.inventory[0].rawBaseAttrs == previous_attrs and int(updated_save.inventory[0].equipmentRuleVersion) == 4,
		"迁移保留实例、星级和基础数值快照")
	check(int(updated_save.warehouse[0].requiredLevel) == 19 and updated_save.warehouse[0].instanceId == stored_ring.instanceId
		and int(updated_save.unclaimedLoot.camp[0].item.requiredLevel) == 10
		and updated_save.unclaimedLoot.camp[0].item.instanceId == ground_necklace.instanceId,
		"仓库与未领取战利品也同步型号穿戴等级")
	check(SaveManager._migrate(updated_save) == updated_save, "v12 迁移再次读取不重复卸装")
	var full_save := SaveManager._collect()
	full_save.schemaVersion = 11
	full_save.player.level = 1
	var old_worn := ItemFactory.make_equip("c2_road_blade")
	old_worn.itemId = "c2_road_blade_modified"
	old_worn.equipmentRuleVersion = 2
	old_worn.requiredLevel = 10
	old_worn.level = 10
	old_worn.rawBaseAttrs = {"atk": 20}
	old_worn.star = 6
	full_save.equipment.weapon = old_worn
	var old_ground := old_worn.duplicate(true)
	old_ground.instanceId = "old_ground_unique"
	full_save.unclaimedLoot = {"camp": [{"uid": "old_ground_uid", "batchId": "old_batch",
		"item": old_ground, "pos": [0.0, 0.0]}]}
	for i in range(full_save.inventory.size()):
		full_save.inventory[i] = {"kind": "potion", "itemId": "potion_hp_small", "count": 1}
	for i in range(full_save.warehouse.size()):
		full_save.warehouse[i] = {"kind": "potion", "itemId": "potion_hp_small", "count": 1}
	check(SaveManager._is_valid_save(full_save), "背包和仓库已满的低等级旧档可迁移")
	var full_migrated := SaveManager._migrate(full_save)
	check(full_migrated.equipment.weapon == null and full_migrated.unclaimedLoot.camp.size() == 2,
		"不足等级的旧穿戴装备卸下并保存在地面")
	check(full_migrated.unclaimedLoot.camp[0].item.itemId == "c2_road_blade"
		and full_migrated.unclaimedLoot.camp[1].item.instanceId == old_worn.instanceId
		and int(full_migrated.unclaimedLoot.camp[1].item.star) == 6,
		"旧地面物与卸下物均保留实例和星级")
	var bag_space := full_save.duplicate(true)
	bag_space.inventory[0] = null
	var bag_migrated := SaveManager._migrate(bag_space)
	check(bag_migrated.equipment.weapon == null and bag_migrated.inventory[0].instanceId == old_worn.instanceId
		and bag_migrated.unclaimedLoot.camp.size() == 1, "有背包空格时优先返还旧穿戴装备")
	var warehouse_space := full_save.duplicate(true)
	warehouse_space.warehouse[0] = null
	var warehouse_migrated := SaveManager._migrate(warehouse_space)
	check(warehouse_migrated.equipment.weapon == null and warehouse_migrated.warehouse[0].instanceId == old_worn.instanceId
		and warehouse_migrated.unclaimedLoot.camp.size() == 1, "背包满时返还到仓库空格")
	save.schemaVersion = 10
	check(not SaveManager._is_valid_save(save), "更老的存档仍明确拒绝")
	if failures.is_empty():
		print("[EquipmentAxesTest] 全部通过 ✅")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	get_tree().quit(0 if failures.is_empty() else 1)

## 掉落表名前缀 → 套起点：DT_C3_* 第三档（21）、DT_C2_* 第二档（11）、其余第一档（1）。
func _tier_of(table_id: String) -> int:
	if table_id.begins_with("DT_C3_"):
		return 21
	if table_id.begins_with("DT_C2_"):
		return 11
	return 1

## 记录失败并继续收集同轮规则错误，便于一次修完配置。
func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
