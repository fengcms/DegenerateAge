extends Node

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261013
	for table_id in ["DT_Wild_L1", "DT_Shellback_L1", "DT_Elite_L1", "DT_Ash_L1"]:
		var found := false
		for _i in range(300):
			for drop in Loot.roll(table_id, rng):
				if drop is Dictionary and String(drop.get("itemId", "")).begins_with("potion_mp_"):
					found = true
					break
			if found:
				break
		assert(found, "%s should be able to drop blue potions" % table_id)
	var boss_blue := false
	for drop in Loot.roll("DT_Boss_L1", rng, "boss_corrupted_beast"):
		if drop is Dictionary and drop.get("itemId") == "potion_mp_large" and int(drop.get("count", 0)) == 2:
			boss_blue = true
	assert(boss_blue, "Boss must drop two large blue potions")
	print("[BluePotionDropTest] 全部通过 ✅")
	get_tree().quit()
