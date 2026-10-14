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
	var mount: Dictionary = DataLoader.get_entry("mounts", "mount_furnace_beast")
	check(mount.get("dropBossId", "") == "c2_boss_hundred_arm_extractor" and int(mount.get("levelReq", 0)) == 20,
		"驮炉兽只关联最终 Boss，20 级可骑")
	print("[ChapterTwoLootTest] ", "全部通过 ✅" if failures.is_empty() else str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
