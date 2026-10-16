extends Node
## 第三章 21—30 装备与掉落（31 §5 批次 3.4 准出）：
##   · 10 型号同档位可生成五品质（common / uncommon / rare / epic / legendary），词条数符合品质配置；
##   · 三档掉落表只产出第三章制式型号、穿戴等级与模板一致、套起点恒为 21；
##   · Boss 传说追加槽可覆盖不同部位；
##   · 任务装备奖励持久发奖：满包失败不洗词条、清出空间后领取同一实例。

var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("[ChapterThreeLootTest] " + message)

func _ready() -> void:
	GameState.reset_to_defaults()
	var issues := DataLoader.validate_all()
	check(issues.is_empty(), "全量物品引用校验：%s" % str(issues))
	_test_five_qualities()
	_test_drop_tables()
	_test_quest_reward_persistence()
	print("[ChapterThreeLootTest] ", "全部通过 ✅" if failures.is_empty() else str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)

# ---- ① 同型号同档五品质 ----

func _c3_models() -> Array:
	var pool: Dictionary = DataLoader.get_entry("lootPools", "c3_normal")
	return pool.get("includeIds", []) if pool is Dictionary else []

func _test_five_qualities() -> void:
	var models := _c3_models()
	check(models.size() == 10, "第三章制式池登记 10 型号")
	var qualities: Array = ItemUtil.QUALITIES
	var cfg: Dictionary = ItemFactory.rules().get("qualities", {})
	for id in models:
		var mid := String(id)
		var tpl: Dictionary = DataLoader.get_entry("equipments", mid)
		check(tpl is Dictionary, "%s 模板存在" % mid)
		var req := int(tpl.get("requiredLevel", 0))
		check(req >= 21 and req <= 30, "%s 穿戴等级落在 21—30（实际 %d）" % [mid, req])
		var bases: Dictionary = tpl.get("tierBases", {})
		check(bases.size() == 1 and bases.has("21"), "%s 只登记第 21 套基底" % mid)
		for q in qualities:
			var qs := String(q)
			var inst := ItemFactory.make_equip_roll(mid, 21, qs)
			check(not inst.is_empty(), "%s 可生成 %s 品质" % [mid, qs])
			if inst.is_empty():
				continue
			check(String(inst.get("quality", "")) == qs, "%s 实例品质为 %s" % [mid, qs])
			check(int(inst.get("requiredLevel", 0)) == req, "%s %s 实例穿戴等级与模板一致" % [mid, qs])
			check(int(inst.get("equipmentRuleVersion", 0)) == int(ItemFactory.rules().get("ruleVersion", -1)),
				"%s %s 实例沿用统一规则版本" % [mid, qs])
			var need_affix := int((cfg.get(qs, {}) as Dictionary).get("affixCount", 0))
			var got := (inst.get("affixes", []) as Array).size() + (inst.get("pctAttrs", []) as Array).size()
			check(got == need_affix, "%s %s 词条数 %d 符合品质配置 %d" % [mid, qs, got, need_affix])

# ---- ② 掉落表 ----

func _test_drop_tables() -> void:
	var normal: Dictionary = DataLoader.get_entry("lootPools", "c3_normal")
	var legendary: Dictionary = DataLoader.get_entry("lootPools", "c3_legendary")
	check(legendary.get("includeIds", []) == normal.get("includeIds", []), "传说追加池与制式池同用十种型号")
	for row in DataLoader.get_table("monsters"):
		if not row is Dictionary:
			continue
		var mid := String((row as Dictionary).get("id", ""))
		if not mid.begins_with("c3_"):
			continue
		var table := String((row as Dictionary).get("dropTableId", ""))
		var expected := "DT_C3_Elite" if mid.contains("elite") else ("DT_C3_Boss" if mid.contains("boss") else "DT_C3_Normal")
		check(table == expected, "%s 使用 %s（实际 %s）" % [mid, expected, table])

	var rng := RandomNumberGenerator.new()
	rng.seed = 20261016
	var seen := {}
	for table_id in ["DT_C3_Normal", "DT_C3_Elite", "DT_C3_Boss"]:
		for _i in range(120):
			for item in Loot.roll(table_id, rng):
				if item.get("kind") != "equip":
					continue
				seen[table_id] = true
				var iid := String(item.get("itemId", ""))
				var tpl: Dictionary = DataLoader.get_entry("equipments", iid)
				check(tpl is Dictionary and normal.includeIds.has(iid), "%s 只产出第三章制式装备（%s）" % [table_id, iid])
				check(int(item.get("requiredLevel", 0)) == int(tpl.get("requiredLevel", -1)),
					"%s 产出 %s 实例穿戴等级与模板一致" % [table_id, iid])
				var level := int(item.get("level", 0))
				check(level >= 21 and level <= 30, "%s 产出等级落在 21—30（%d）" % [table_id, level])
	for table_id in ["DT_C3_Normal", "DT_C3_Elite", "DT_C3_Boss"]:
		check(seen.has(table_id), "%s 实际产生装备" % table_id)

	var legendary_slots := {}
	for _i in range(2000):
		for item in Loot.roll("DT_C3_Boss", rng):
			if item.get("kind") == "equip" and item.get("quality") == "legendary":
				legendary_slots[Equipment.item_kind(item)] = true
	check(legendary_slots.size() > 1 and legendary_slots.has("weapon"), "Boss 传说追加槽可产出不同部位")

# ---- ③ 任务装备奖励持久发奖 ----

func _test_quest_reward_persistence() -> void:
	var qid := "C3Q12"
	var tpl := Quest.template(qid)
	var reward: Dictionary = tpl.get("reward", {})
	check(reward.has("item") and reward.has("tierStart"), "章末任务配置随机装备奖励")
	GameState.quest_states[qid] = {"state": Quest.STATE_COMPLETED, "progress": 1}
	_fill_bag(4)
	var gold_before := int(GameState.gold)
	var first := Quest.deliver(qid)
	check(not bool(first.get("ok", false)), "满包交付必须失败（不静默丢奖）")
	check(Quest.state_of(qid) == Quest.STATE_COMPLETED, "满包失败不得置 rewarded")
	check(int(GameState.gold) == gold_before, "满包失败不得发放金币")
	var plan: Variant = GameState.quest_reward_plans.get(qid, null)
	check(plan is Dictionary, "首次失败尝试即写下待发计划")
	if not plan is Dictionary:
		return
	var planned: Dictionary = (plan as Dictionary).get("item", {})
	var planned_uid := String(planned.get("instanceId", ""))
	var planned_affixes: Array = (planned.get("affixes", []) as Array).duplicate(true)
	check(not planned_uid.is_empty(), "计划内装备实例应有 instanceId")
	check(String(planned.get("itemId", "")) == String(reward.get("item", "")), "计划型号与任务奖励一致")
	Quest.deliver(qid)
	Quest.deliver(qid)
	var again: Variant = (GameState.quest_reward_plans.get(qid, {}) as Dictionary).get("item", {})
	var retried: Dictionary = again if again is Dictionary else {}
	check(String(retried.get("instanceId", "")) == planned_uid, "失败重试必须复用同一实例")
	check((retried.get("affixes", []) as Array) == planned_affixes, "失败重试必须复用同一词条")
	check(Quest.state_of(qid) == Quest.STATE_COMPLETED, "反复失败重试仍不得置 rewarded")
	GameState.inventory = Inventory.create(40)
	var done := Quest.deliver(qid)
	check(bool(done.get("ok", false)), "清出空间后可正常领奖：%s" % done.get("reason", ""))
	check(Quest.state_of(qid) == Quest.STATE_REWARDED, "领奖后置 rewarded")
	check(String((done.get("item", {}) as Dictionary).get("instanceId", "")) == planned_uid, "入包实例与计划一致（未重抽）")
	check(not GameState.quest_reward_plans.has(qid), "领奖成功后清除待发计划")
	check(bool(GameState.unlocks.get("chapter4", false)), "章末任务领奖同时解锁第四章")

func _fill_bag(size: int) -> void:
	GameState.inventory = Inventory.create(size)
	for i in range(size):
		GameState.inventory[i] = ItemFactory.make_equip("weapon_iron")
