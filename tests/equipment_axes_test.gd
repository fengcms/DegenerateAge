extends Node
## 两档同名装备的目录、生成、掉落、任务和旧档迁移回归。
## 使用隔离项目运行，不读取玩家真实存档；只验证规则与实例数据，不评估实际战斗平衡。

var failures: Array[String] = []

## 逐型号验证唯一档位和五品质，再检查来源池及旧实例转换。
func _ready() -> void:
	check(DataLoader.validate_all().is_empty(), "装备与掉落配置应通过启动校验")
	var rng := RandomNumberGenerator.new()
	rng.seed = 190021
	var qualities := ["common", "uncommon", "rare", "epic", "legendary"]
	var templates: Array = DataLoader.get_table("equipments")
	check(templates.size() == 20, "正式型号仅有二十种")
	var coverage := {1: {}, 11: {}}
	for tpl in templates:
		var bases: Dictionary = tpl.get("tierBases", {})
		check(bases.size() == 1, "%s 只有一个穿戴档" % tpl.id)
		if bases.size() != 1:
			continue
		var tier := int(bases.keys()[0])
		check(coverage.has(tier), "%s 档位合法" % tpl.id)
		if not coverage.has(tier):
			continue
		check(not coverage[tier].has(tpl.slot), "Lv%d %s 只有一个型号" % [tier, tpl.slot])
		coverage[tier][tpl.slot] = tpl.id
		for i in range(qualities.size()):
			var item := ItemFactory.make_equip_roll(String(tpl.id), tier, qualities[i], rng)
			check(not item.is_empty(), "%s %s 可生成" % [tpl.id, qualities[i]])
			if item.is_empty():
				continue
			check(int(item.requiredLevel) == tier and int(item.level) == tier and item.rawBaseAttrs == bases[str(tier)],
				"装备名称、门槛和基础值共用唯一档")
			check(item.affixes.size() + item.pctAttrs.size() == i and int(item.star) == 0,
				"品质词条数和初始星级")
			check(SaveManager._valid_item(item), "生成实例可存档")
		check(not bases.has("11" if tier == 1 else "1"), "错档型号没有可借用的基底")
	for tier in coverage:
		check(coverage[tier].size() == 10, "Lv%d 覆盖十类部位" % tier)
	for pool_id in ["normal", "legendary", "c2_normal", "c2_legendary"]:
		var pool: Dictionary = DataLoader.get_entry("lootPools", pool_id)
		check(pool.get("includeIds", []).size() == 10, "%s 显式限定十种型号" % pool_id)
	for table in DataLoader.get_table("dropTables"):
		var tier := 11 if String(table.id).begins_with("DT_C2_") else 1
		for entry in table.entries:
			if entry.get("kind") == "equip":
				check(int(entry.get("requiredLevel", 0)) == tier, "%s 来源固定档位" % table.id)
				var expected_pool := "c2_legendary" if tier == 11 else "legendary"
				var weights: Dictionary = entry.get("qualityWeight", {})
				if not (weights.size() == 1 and weights.has("legendary")):
					expected_pool = "c2_normal" if tier == 11 else "normal"
				check(entry.get("templatePool") == expected_pool, "%s 使用本档型号池" % table.id)
	for _i in range(250):
		for table_id in ["DT_Wild_L1", "DT_Boss_L1", "DT_C2_Normal", "DT_C2_Boss_Final"]:
			var expected_tier := 11 if table_id.begins_with("DT_C2_") else 1
			for item in Loot.roll(table_id, rng):
				if item.get("kind") == "equip":
					check(int(item.requiredLevel) == expected_tier and coverage[expected_tier].values().has(item.itemId),
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
	check(int(migrated.schemaVersion) == 12 and migrated.inventory[0].itemId == "weapon_iron"
		and int(migrated.inventory[0].requiredLevel) == 1 and int(migrated.inventory[0].star) == 7
		and migrated.inventory[0].instanceId == old.instanceId, "旧装备归档且保留实例、星级")
	check(SaveManager._migrate(migrated) == migrated, "迁移重复执行不改变结果")
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

## 记录失败并继续收集同轮规则错误，便于一次修完配置。
func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
