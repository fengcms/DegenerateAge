extends Node
## Chapter-two gear must use its own model pool and current three-axis level bands.

var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("[ChapterTwoLootTest] " + message)

func _ready() -> void:
	GameState.reset_to_defaults()
	var issues := DataLoader.validate_all()
	check(issues.is_empty(), "全量物品引用校验：%s" % str(issues))
	var pool: Dictionary = DataLoader.get_entry("lootPools", "c2_normal")
	check(pool.get("includeIds", []).size() == 10, "本章基础池覆盖十种装备位置")
	var modified: Dictionary = DataLoader.get_entry("lootPools", "c2_modified")
	check(modified.get("includeIds", []).size() == 10, "工坊与井心有十种改装型号")
	for id in modified.get("includeIds", []):
		check(DataLoader.get_entry("equipments", String(id)) is Dictionary, "改装装备有正式模板：%s" % id)
	for spec in [["iron", "c2_foreman_gauntlet"], ["slag", "c2_devourer_heart"], ["final", "c2_extractor_eye"]]:
		var exclusive: Dictionary = DataLoader.get_entry("lootPools", "c2_legendary_" + spec[0])
		check(exclusive.get("includeIds", []) == [spec[1]], "三首领各有独立传说型号：%s" % spec[0])
	check(DataLoader.get_entry("monsters", "c2_boss_slag_devourer").dropTableId == "DT_C2_Boss_Slag", "吞噬者绑定自身专属池")
	for map_id in ["c2_lower_works", "c2_ember_furnace"]:
		for point in MapService.data_for(map_id).get("spawnPoints", []):
			check(String(point.get("dropTableId", "")).begins_with("DT_C2_Industrial_"), "%s 使用区域改装池" % map_id)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261014
	var found_normal := false
	var found_final := false
	for _i in range(25):
		for item in Loot.roll("DT_C2_Normal", rng, "c2_spirit_larva"):
			if item is Dictionary and String(item.get("kind", "")) == "equip":
				found_normal = true
				check(String(item.itemId).begins_with("c2_") and int(item.requiredLevel) == 10,
					"普通怪仅出本章 Lv10 档三轴装备")
		for item in Loot.roll("DT_C2_Boss_Final", rng, "c2_boss_hundred_arm_extractor"):
			if item is Dictionary and String(item.get("kind", "")) == "equip":
				found_final = true
				check(String(item.itemId).begins_with("c2_") and int(item.requiredLevel) == 20,
					"主机 Boss 产出本章 Lv20 档三轴装备")
	check(found_normal and found_final, "普通与最终 Boss 均能实际掉装备")
	for pool_id in ["c2_modified", "c2_legendary_iron", "c2_legendary_slag", "c2_legendary_final"]:
		var picked: Dictionary = Loot._pick_equip_template(20, rng, pool_id)
		check(not picked.is_empty() and DataLoader.get_entry("lootPools", pool_id).includeIds.has(picked.get("id", "")),
			"Lv20 装备按指定池选型号：%s" % pool_id)
	var mount: Dictionary = DataLoader.get_entry("mounts", "mount_furnace_beast")
	check(mount.get("dropBossId", "") == "c2_boss_hundred_arm_extractor" and int(mount.get("levelReq", 0)) == 20,
		"驮炉兽只关联最终 Boss，20 级可骑")
	print("[ChapterTwoLootTest] ", "全部通过 ✅" if failures.is_empty() else str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
