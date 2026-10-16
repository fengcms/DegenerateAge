extends Node
## E1 持久任务发奖计划回归（工程文档 30 §4；创意 第五章/04）。
##
## 口径：带随机成分的任务奖励实例在**首次有效交付尝试**时一次抽定并落档；满包等失败原因重试
## 必须复用同一实例与词条（失败重试不得成为洗词条入口）；领奖成功后才清除计划；跨档保留。

var failures: Array[String] = []


func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		print("[QuestRewardPlan] 失败：", message)


func _ready() -> void:
	GameState.reset_to_defaults()
	var quest_id := _equip_reward_quest()
	check(not quest_id.is_empty(), "任务表应存在带装备奖励且不依赖任务物品的条目")
	if not quest_id.is_empty():
		_test_full_bag_then_reuse(quest_id)
	_test_save_round_trip(quest_id)
	_test_migration_pruning()
	GameState.reset_to_defaults()
	print("[QuestRewardPlan] ", "全部通过 ✅" if failures.is_empty() else str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)


## 取第一个「装备 + tierStart」奖励的任务。不写死 ID，避免后续数据调整让测试失效。
## 排除需要先交任务物品的 collect 任务 —— 那种任务在发奖计划之前就会因计数不足失败。
func _equip_reward_quest() -> String:
	for row in DataLoader.get_table("quests"):
		if not row is Dictionary:
			continue
		var reward: Variant = (row as Dictionary).get("reward", {})
		var objective: Variant = (row as Dictionary).get("objective", {})
		if not reward is Dictionary or not objective is Dictionary:
			continue
		if not (reward as Dictionary).has("item") or not (reward as Dictionary).has("tierStart"):
			continue
		if (objective as Dictionary).has("sourceMonster"):
			continue
		return String((row as Dictionary).get("id", ""))
	return ""


## 用不可堆叠装备塞满背包；装备奖励需要空格，故该状态必然装不下。
func _fill_bag(size: int) -> void:
	GameState.inventory = Inventory.create(size)
	for i in range(size):
		GameState.inventory[i] = ItemFactory.make_equip("weapon_iron")


func _test_full_bag_then_reuse(quest_id: String) -> void:
	GameState.quest_states = {quest_id: {"state": Quest.STATE_COMPLETED, "progress": 0}}
	_fill_bag(4)
	var gold_before := int(GameState.gold)
	var first := Quest.deliver(quest_id)
	check(not bool(first.get("ok", false)), "满包交付必须失败（不静默丢奖）")
	check(Quest.state_of(quest_id) == Quest.STATE_COMPLETED, "满包失败不得置 rewarded")
	check(int(GameState.gold) == gold_before, "满包失败不得发放金币")
	var plan: Variant = GameState.quest_reward_plans.get(quest_id, null)
	check(plan is Dictionary, "首次失败尝试即写下待发计划")
	if not plan is Dictionary:
		return
	var planned: Dictionary = (plan as Dictionary).get("item", {})
	var planned_uid := String(planned.get("instanceId", ""))
	var planned_affixes: Array = (planned.get("affixes", []) as Array).duplicate(true)
	check(not planned_uid.is_empty(), "计划内装备实例应有 instanceId")
	Quest.deliver(quest_id)
	Quest.deliver(quest_id)
	var again: Variant = (GameState.quest_reward_plans.get(quest_id, {}) as Dictionary).get("item", {})
	var retried: Dictionary = again if again is Dictionary else {}
	check(String(retried.get("instanceId", "")) == planned_uid, "失败重试必须复用同一实例")
	check((retried.get("affixes", []) as Array) == planned_affixes, "失败重试必须复用同一词条")
	check(Quest.state_of(quest_id) == Quest.STATE_COMPLETED, "反复失败重试仍不得置 rewarded")
	GameState.inventory = Inventory.create(40)
	var done := Quest.deliver(quest_id)
	check(bool(done.get("ok", false)), "清出空间后可正常领奖：%s" % done.get("reason", ""))
	check(Quest.state_of(quest_id) == Quest.STATE_REWARDED, "领奖后置 rewarded")
	check(String((done.get("item", {}) as Dictionary).get("instanceId", "")) == planned_uid,
		"入包实例与计划一致（未重抽）")
	check(not GameState.quest_reward_plans.has(quest_id), "领奖成功后清除待发计划")


func _test_save_round_trip(quest_id: String) -> void:
	GameState.reset_to_defaults()
	var qid := quest_id if not quest_id.is_empty() else "Q001"
	var made := ItemFactory.make_equip("weapon_iron")
	GameState.quest_reward_plans = {qid: {"item": made, "bonus": [
		{"kind": "potion", "itemId": "potion_hp_mid", "count": 2}]}}
	check(SaveManager.save_slot(3, true), "带待发计划的存档应写入成功")
	var stored := SaveManager.read_slot(3)
	check(int(stored.data.get("schemaVersion", 0)) == SaveManager.CURRENT_SCHEMA,
		"存档 schemaVersion 应为 CURRENT_SCHEMA（%d）" % SaveManager.CURRENT_SCHEMA)
	GameState.quest_reward_plans.clear()
	SaveManager.apply_to_game_state(stored.data)
	var restored: Variant = GameState.quest_reward_plans.get(qid, null)
	check(restored is Dictionary, "读档后待发计划应保留")
	if restored is Dictionary:
		var kept: Dictionary = (restored as Dictionary).get("item", {})
		check(String(kept.get("instanceId", "")) == String(made.get("instanceId", "")),
			"读档后待发实例 ID 不变")
		check(((restored as Dictionary).get("bonus", []) as Array).size() == 1, "读档后附加奖励保留")
	SaveManager.delete_slot(3)


func _test_migration_pruning() -> void:
	# 旧档（schema 13 及以下）没有该键：补空字典，不得因此判坏档。
	var legacy: Dictionary = SaveManager._collect()
	legacy.schemaVersion = 13
	legacy.erase("questRewardPlans")
	var migrated: Dictionary = SaveManager._migrate(legacy)
	check(int(migrated.get("schemaVersion", 0)) == SaveManager.CURRENT_SCHEMA, "schema 13 旧档迁移到当前版本")
	check(migrated.questRewardPlans is Dictionary and (migrated.questRewardPlans as Dictionary).is_empty(),
		"旧档缺该键时补空字典（不判坏档）")
	# 未知任务 ID、非法实例、空计划逐条丢弃，不因单条坏数据拒绝整档。
	var broken: Dictionary = SaveManager._collect()
	broken.questRewardPlans = {
		"quest_not_exists": {"item": {}, "bonus": []},
		"Q001": {"item": {"kind": "equip", "itemId": "weapon_iron"}, "bonus": []},
		"Q002": {"item": {}, "bonus": []},
	}
	var pruned: Dictionary = SaveManager._migrate(broken)
	check((pruned.questRewardPlans as Dictionary).is_empty(), "未知任务 / 非法实例 / 空计划应逐条丢弃")
	# 合法计划在迁移中原样保留，且整档仍通过校验。
	var kept: Dictionary = SaveManager._collect()
	kept.questRewardPlans = {"Q001": {"item": ItemFactory.make_equip("weapon_iron"), "bonus": []}}
	var survived: Dictionary = SaveManager._migrate(kept)
	check((survived.questRewardPlans as Dictionary).size() == 1, "合法待发计划应保留")
	check(SaveManager._is_valid_save(survived), "含待发计划的存档应通过校验")
