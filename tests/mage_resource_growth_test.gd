extends Node
## 工程 103：法师红少蓝多、法力词条独立性，以及旧档的一次性蓝量比例结转。

var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("[MageResourceGrowthTest] " + label)

func _ready() -> void:
	_test_level_curve()
	_test_common_equipment_ratio()
	_test_stat_independence()
	_test_legacy_save_migration()
	_test_level_up_keeps_ratio()
	GameState.reset_to_defaults()
	if failures.is_empty():
		print("[MageResourceGrowthTest] 全部通过 ✅")
		get_tree().quit(0)
	else:
		print("[MageResourceGrowthTest] 失败 %d 项" % failures.size())
		get_tree().quit(1)

func _test_level_curve() -> void:
	for level in [1, 20, 40, 60, 61, 100, 160]:
		GameState.reset_to_defaults("warrior")
		GameState.player.level = level
		GameState.player.attack = Balance.base_attack(level)
		GameState.player.defense = Balance.base_defense(level)
		var warrior_mp := GameState.max_mp()
		check(warrior_mp == 30 + 5 * level, "武士 L%d 蓝量逐位不变" % level)
		GameState.player.classId = "mage"
		var hp := GameState.max_hp()
		var mp := GameState.max_mp()
		check(float(mp) / float(hp) >= 1.19,
			"法师 L%d 裸装应维持蓝多于血（HP %d / MP %d）" % [level, hp, mp])
		check(mp >= warrior_mp * 2, "法师 L%d 不得低于旧蓝池" % level)
		print("[MANA] L%d 裸装 HP=%d MP=%d 比值=%.3f" % [level, hp, mp, float(mp) / float(hp)])

## 用现行装备生成器构造常规品质的 14 槽样本；它不能代替真人词条分布，
## 但能抓出「裸装蓝多、穿上普通装备又变高血低蓝」的公式退化。
func _test_common_equipment_ratio() -> void:
	var by_kind := {}
	for raw in DataLoader.get_table("equipments"):
		if not raw is Dictionary:
			continue
		var tpl: Dictionary = raw
		if bool(tpl.get("debug", false)) or not bool(tpl.get("lootable", true)):
			continue
		var bases: Variant = tpl.get("tierBases", {})
		if not bases is Dictionary or not (bases as Dictionary).has(str(ItemFactory.DYNAMIC_BASE_TIER)):
			continue
		var kind := String(tpl.get("slot", ""))
		if not by_kind.has(kind):
			by_kind[kind] = String(tpl.get("id", ""))
	for level in [100, 160]:
		GameState.reset_to_defaults("mage")
		GameState.player.level = level
		GameState.player.attack = Balance.base_attack(level)
		GameState.player.defense = Balance.base_defense(level)
		for raw_slot in Equipment.SLOT_DEFS:
			var slot: Dictionary = raw_slot
			var kind := String(slot.get("kind", ""))
			check(by_kind.has(kind), "动态装备应包含 %s 部位" % kind)
			if not by_kind.has(kind):
				continue
			var item := ItemFactory.make_equip_dynamic(String(by_kind[kind]), level, "common")
			check(not item.is_empty(), "L%d %s 普通品质装备应生成" % [level, kind])
			GameState.equipment[String(slot.get("id", ""))] = item
		var hp := GameState.max_hp()
		var mp := GameState.max_mp()
		var ratio := float(mp) / float(hp)
		print("[MANA] L%d 普通品质满槽 HP=%d MP=%d 比值=%.3f" % [level, hp, mp, ratio])
		check(ratio >= 1.1 and ratio <= 1.4,
			"L%d 普通品质满槽法师蓝/血应在 1.1–1.4（实际 %.3f）" % [level, ratio])

func _test_stat_independence() -> void:
	GameState.reset_to_defaults("mage")
	GameState.player.level = 100
	GameState.player.attack = Balance.base_attack(100)
	GameState.player.defense = Balance.base_defense(100)
	var base_mp := GameState.max_mp()
	GameState.player.hpFlat = 100000
	GameState.player.hpPercent = 1.0
	check(GameState.max_mp() == base_mp, "直接生命词条不得赠送法力")
	GameState.player.hpFlat = 0
	GameState.player.hpPercent = 0.0
	GameState.player.mpFlat = 1234
	check(GameState.max_mp() == base_mp + 2468, "固定法力词条保持原有 2 倍收益")
	GameState.player.mpFlat = 0
	GameState.player.attack = int(GameState.player.attack) + 100
	check(GameState.max_mp() > base_mp, "攻防装备档次提升应抬高法力底数")

func _test_legacy_save_migration() -> void:
	GameState.reset_to_defaults("mage")
	GameState.player.level = 100
	GameState.player.attack = Balance.base_attack(100)
	GameState.player.defense = Balance.base_defense(100)
	var old_cap := GameState.legacy_max_mp()
	var new_cap := GameState.max_mp()
	var data: Dictionary = SaveManager.call("_collect")
	var saved_player: Dictionary = (data.player as Dictionary).duplicate(true)
	saved_player.erase("manaFormulaVersion")
	saved_player["mp"] = int(round(float(old_cap) * 0.5))
	data["player"] = saved_player
	SaveManager.apply_to_game_state(data)
	check(int(GameState.player.get("manaFormulaVersion", -1)) == GameState.MANA_FORMULA_VERSION,
		"旧档只升级一次法力公式标记")
	check(abs(float(GameState.player.mp) / float(GameState.max_mp()) - 0.5) < 0.002,
		"旧档半蓝应结转为新蓝池半蓝（旧 %d / 新 %d / 当前 %d）" % [old_cap, new_cap, int(GameState.player.mp)])
	var migrated_mp := int(GameState.player.mp)
	var migrated_data: Dictionary = SaveManager.call("_collect")
	SaveManager.apply_to_game_state(migrated_data)
	check(int(GameState.player.mp) == migrated_mp, "新版存档再次读取不得重复补蓝")

func _test_level_up_keeps_ratio() -> void:
	GameState.reset_to_defaults("mage")
	GameState.player.level = 60
	GameState.player.attack = Balance.base_attack(60)
	GameState.player.defense = Balance.base_defense(60)
	GameState.player.mp = int(round(float(GameState.max_mp()) * 0.37))
	GameState.call("_level_up")
	check(abs(float(GameState.player.mp) / float(GameState.max_mp()) - 0.37) < 0.002,
		"60→61 升级后蓝量按比例结转")
