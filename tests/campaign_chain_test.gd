extends Node
## E6-1 整链回归：主线单链结构 + 第三～六章 50 个逐节点接取/交付 + 结局解锁 + 支线零扰动。
## 运行在隔离子项目，只改本测试的 GameState，不读写玩家存档（测试只写槽 3）。
##
## 为什么要有这一条：章内 5 个场景（Routes/Combat/Quests/Loot/Map）全绿也证明不了跨章能走通，
## `prev` 被改坏、某个交付人换图、最后一环的解锁字段写成单数，都不会有任何测试变红。

var failures: Array[String] = []

## 第三～六章的起点；它之前的 17 个节点（序章 + 第二章）由本测试直接置为已领奖。
const LATE_CHAPTER_START := "C3Q01"
## 第三～六章主线数（67 - 17）；改主线总量时应同步这条断言，而不是放宽它。
const LATE_CHAPTER_COUNT := 50
## 序章 Q001–Q005（5）+ 第二章 C2Q01–C2Q12（12）；常量而非 `chain.size()-50`，
## 否则链断在中间时会出现「应有 -3 个前置节点」这种读不懂的文案。
const PROLOGUE_COUNT := 17

func _ready() -> void:
	GameState.reset_to_defaults()
	GameState.player.level = 21
	GameState.current_map = "camp"

	var chain := _main_chain()
	var sides_before := _side_records()

	# ① 链结构：67 个节点、单链无分叉、无孤立、末节点是结局章最后一个。
	_check(chain.size() == _main_count(),
		"主线链应覆盖全部 %d 个节点，实际走到 %d 个（存在断层或分叉）" % [_main_count(), chain.size()])
	_check(not chain.is_empty() and chain[chain.size() - 1] == "C6Q12",
		"主线链末节点应为 C6Q12，实际 %s" % (chain[chain.size() - 1] if not chain.is_empty() else "（空链）"))
	var late := 0
	for qid in chain:
		if _is_late_chapter(qid):
			late += 1
	_check(late == LATE_CHAPTER_COUNT,
		"第三～六章主线应为 %d 个，实际 %d" % [LATE_CHAPTER_COUNT, late])

	var start_index := chain.find(LATE_CHAPTER_START)
	_check(start_index >= 0, "链上找不到 %s（前置段被删或 prev 断裂）" % LATE_CHAPTER_START)
	if start_index < 0:
		_finish()
		return
	_check(start_index == PROLOGUE_COUNT,
		"%s 之前应恰有 %d 个前置节点（序章 5 + 第二章 12），实际 %d" % [LATE_CHAPTER_START, PROLOGUE_COUNT, start_index])

	# 前置段置为已领奖：本测试只跑第三～六章，前面 17 个节点的实际行为由 QuestMainLeadTest 覆盖。
	for i in range(start_index):
		GameState.quest_states[chain[i]] = {"state": Quest.STATE_REWARDED, "progress": 1}

	# ② 逐节点可接可取：任一失败立即停下并报 qid + 原因（不接受「整体 ok」）。
	var blocked := ""
	for i in range(start_index, chain.size()):
		var qid := chain[i]
		var tpl := Quest.template(qid)
		if tpl.is_empty():
			blocked = "%s 模板缺失" % qid
			break
		var giver := String(tpl.get("giver", ""))
		var turn_in := String(tpl.get("turnIn", giver))
		var giver_map := MapService.map_for_npc(giver)
		if giver_map.is_empty():
			blocked = "%s 的发布人 %s 不在任何地图上" % [qid, giver]
			break
		GameState.current_map = giver_map
		var accepted: Dictionary = Quest.accept(qid, giver)
		if not bool(accepted.get("ok", false)):
			blocked = "%s 接取失败（发布人 %s）：%s" % [qid, giver, String(accepted.get("reason", ""))]
			break
		# 整链测试必须模拟任务物品：不补的话第 3 个任务（C3Q03）就会卡在「任务物品不足」。
		var objective: Dictionary = tpl.get("objective", {})
		if not String(objective.get("sourceMonster", "")).is_empty():
			GameState.quest_items[String(objective.get("targetId", ""))] = int(objective.get("count", 1))
		if Quest.state_of(qid) != Quest.STATE_COMPLETED:
			Quest._complete(qid, maxi(1, int(objective.get("count", 1))))
		if Quest.state_of(qid) != Quest.STATE_COMPLETED:
			blocked = "%s 接取后无法进入已完成（目标类型 %s）" % [qid, String(objective.get("kind", ""))]
			break
		var turn_map := MapService.map_for_npc(turn_in)
		if turn_map.is_empty():
			blocked = "%s 的交付人 %s 不在任何地图上" % [qid, turn_in]
			break
		GameState.current_map = turn_map
		# 交付会真实发装备；不清包会在几十个任务内撞「背包已满」——那是测试构造问题，不是任务链问题。
		_clear_inventory()
		var delivered: Dictionary = Quest.deliver(qid, turn_in)
		if not bool(delivered.get("ok", false)):
			blocked = "%s 交付失败（交付人 %s）：%s" % [qid, turn_in, String(delivered.get("reason", ""))]
			break
	_check(blocked.is_empty(), "整链逐节点应全部通过，中断于 %s" % blocked)

	# ③ 结局达成：`campaign_complete` 由 C6Q12 的 `reward.unlocks` 数组写入。
	_check(bool(GameState.unlocks.get("campaign_complete", false)),
		"最后一章交付后应解锁 campaign_complete（写成单数 unlock 会静默失败）")

	# ④ 无残留：第三～六章 50 个必须全部 rewarded，不允许停在 available/active/completed。
	var residual: Array[String] = []
	for i in range(start_index, chain.size()):
		var state := Quest.state_of(chain[i])
		if state != Quest.STATE_REWARDED:
			residual.append("%s=%s" % [chain[i], state])
	_check(residual.is_empty(), "第三～六章应全部 rewarded，残留：%s" % "、".join(residual))

	# ⑤ 无支线也行：全程不碰任何 side 任务，跑完**落档记录**必须逐字不变。
	# 注意判据是「落档」而不是「推导态」—— locked→available 由 `prev` 推导，主线推进后本就该变，
	# 那不算副作用；真正的副作用是整链给支线写进了状态。
	_check(_side_records() == sides_before, "整链推进不应给任何支线写入状态（locked/available 只由 prev 推导）")
	_check(Quest.state_of("C6S07") == Quest.STATE_AVAILABLE,
		"C6S07 在主线和 C6Q12 交付后应由 prev 推导为 available，实际 %s" % Quest.state_of("C6S07"))

	# ⑥ 存档往返：只测运行态不够 —— 单数 `reward.unlock` 在 deliver 里**照样生效**，
	# 但读档白名单只登记 `reward.unlocks` 数组键 ⇒ 存进去就是毁档。这一条守住「能存能读」。
	# 必须放在 ④⑤ 之后：`apply_to_game_state` 会重置 quest_states。
	var snapshot := SaveManager._collect()
	_check(SaveManager._is_valid_save(snapshot),
		"整链结局后的存档应通过校验（unlock 白名单只认 reward.unlocks 数组键）")
	GameState.reset_to_defaults()
	SaveManager.apply_to_game_state(snapshot)
	_check(bool(GameState.unlocks.get("campaign_complete", false)), "读档后 campaign_complete 应仍然存在")

	_finish()

## 沿 `prev` 反查构造主线链；发现分叉直接记失败（不静默取其中一个）。
func _main_chain() -> Array[String]:
	var by_prev := {}
	for raw in Quest.all():
		if not raw is Dictionary:
			continue
		var tpl: Dictionary = raw
		if String(tpl.get("type", "")) != "main":
			continue
		var prev := String(tpl.get("prev", ""))
		if prev.is_empty():
			continue
		if by_prev.has(prev):
			failures.append("主线分叉：%s 同时指向 %s 与 %s" % [prev, String(by_prev[prev]), String(tpl.get("id", ""))])
		by_prev[prev] = String(tpl.get("id", ""))
	var chain: Array[String] = ["Q001"]
	var cursor := "Q001"
	# 上界取主线总数：正常时循环自然结束，异常（环）时不会无限转。
	var limit := _main_count() + 1
	while by_prev.has(cursor) and chain.size() <= limit:
		cursor = String(by_prev[cursor])
		chain.append(cursor)
	return chain

func _main_count() -> int:
	var count := 0
	for raw in Quest.all():
		if raw is Dictionary and String((raw as Dictionary).get("type", "")) == "main":
			count += 1
	return count

func _is_late_chapter(qid: String) -> bool:
	return qid.begins_with("C3") or qid.begins_with("C4") \
		or qid.begins_with("C5") or qid.begins_with("C6")

## 支线**落档**快照：只读 `quest_states`，不触发任何推导，用于证明整链不产生副作用。
func _side_records() -> Dictionary:
	var snapshot := {}
	for raw in Quest.all():
		if not raw is Dictionary:
			continue
		var tpl: Dictionary = raw
		if String(tpl.get("type", "")) != "side":
			continue
		var qid := String(tpl.get("id", ""))
		snapshot[qid] = GameState.quest_states.get(qid, null)
	return snapshot

func _clear_inventory() -> void:
	for i in range(GameState.inventory.size()):
		GameState.inventory[i] = null

func _finish() -> void:
	if failures.is_empty():
		print("[CampaignChainTest] 全部通过 ✅")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error("[CampaignChainTest] " + failure)
		print("[CampaignChainTest] ", failures)
		get_tree().quit(1)

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
