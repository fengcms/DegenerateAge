extends Node
## 第二章装备来源回归：所有区域共用 Lv11 十种制式，首领传说可出任意部位。

var failures: Array[String] = []

## 记录错误并继续测试其余来源，便于定位混池配置。
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("[ChapterTwoLootTest] " + message)

## 验证池、掉落档位、改装型号退场和首领额外传说槽。
func _ready() -> void:
	GameState.reset_to_defaults()
	var issues := DataLoader.validate_all()
	check(issues.is_empty(), "全量物品引用校验：%s" % str(issues))
	var normal: Dictionary = DataLoader.get_entry("lootPools", "c2_normal")
	var legendary: Dictionary = DataLoader.get_entry("lootPools", "c2_legendary")
	check(normal.get("includeIds", []).size() == 10 and legendary.get("includeIds", []) == normal.get("includeIds", []),
		"制式与传说同用十种第二档型号")
	check(DataLoader.get_entry("lootPools", "c2_modified") == null, "改装池已退场")
	for map_id in ["c2_lower_works", "c2_ember_furnace"]:
		for point in MapService.data_for(map_id).get("spawnPoints", []):
			check(String(point.get("dropTableId", "")).begins_with("DT_C2_Industrial_"), "%s 仍使用区域掉落次数" % map_id)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261014
	var seen := {}
	for table_id in ["DT_C2_Normal", "DT_C2_Industrial_Elite", "DT_C2_Core_Normal", "DT_C2_Boss_Final"]:
		for _i in range(100):
			for item in Loot.roll(table_id, rng):
				if item.get("kind") != "equip":
					continue
				seen[table_id] = true
				check(int(item.requiredLevel) == 11 and normal.includeIds.has(item.itemId),
					"%s 只生成 Lv11 制式" % table_id)
	for table_id in ["DT_C2_Normal", "DT_C2_Industrial_Elite", "DT_C2_Core_Normal", "DT_C2_Boss_Final"]:
		check(seen.has(table_id), "%s 实际产生装备" % table_id)
	var legendary_slots := {}
	for _i in range(1500):
		for item in Loot.roll("DT_C2_Boss_Final", rng):
			if item.get("kind") == "equip" and item.get("quality") == "legendary":
				legendary_slots[Equipment.item_kind(item)] = true
	check(legendary_slots.size() > 1 and legendary_slots.has("shoes"), "传说追加槽可产出不同部位")
	var mount: Dictionary = DataLoader.get_entry("mounts", "mount_furnace_beast")
	check(mount.get("dropBossId", "") == "c2_boss_hundred_arm_extractor" and int(mount.get("levelReq", 0)) == 20,
		"坐骑来源和穿戴要求不受装备调整影响")
	print("[ChapterTwoLootTest] ", "全部通过 ✅" if failures.is_empty() else str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
