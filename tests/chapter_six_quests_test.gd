extends Node
## 第六章 51—60 任务链与结局（34 §5 批次 6.3 准出）：
##   · 18 条任务的数据一致性（发布人 / 交付人可定位、击杀 / 收集目标在其 mapScope 图内真实刷新）；
##   · 旧档 C5Q14 领奖后 12 条主线全部可完成，逐步解除 `c6_access_02/03/04/05` 与 `campaign_complete`；
##   · **三态分离**：核心击杀（C6Q10）→ 回前哨交付（C6Q11/C6Q12）→ 正式结局，击杀不直接写 `campaign_complete`；
##   · 主线未领奖时出口封锁，文案指名交付人与产出任务；
##   · **结局幂等且不清成长**：重复读档奖励只一次、等级 / 金币 / 装备不回退，旧图与支线仍可达；
##   · 支线可放弃 / 重接，计数与任务袋物品清零。

const C6_MAIN := ["C6Q01", "C6Q02", "C6Q03", "C6Q04", "C6Q05", "C6Q06",
	"C6Q07", "C6Q08", "C6Q09", "C6Q10", "C6Q11", "C6Q12"]
const C6_SIDE := ["C6S01", "C6S02", "C6S03", "C6S04", "C6S05", "C6S06"]
## 门禁与产出任务的对应（34 §1 / §4）；镇脉前哨由第五章收尾任务产出。
const GATES := {
	"c6_map00": ["chapter6", "C5Q14", "c5_npc08"],
	"c6_map02": ["c6_access_02", "C6Q03", "c6_npc09"],
	"c6_map03": ["c6_access_03", "C6Q05", "c6_npc01"],
	"c6_map04": ["c6_access_04", "C6Q06", "c6_npc01"],
	"c6_map05": ["c6_access_05", "C6Q09", "c6_npc10"],
}

var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("[ChapterSixQuestsTest] " + message)

func _ready() -> void:
	GameState.reset_to_defaults()
	var issues := DataLoader.validate_all()
	check(issues.is_empty(), "所有数据表通过引用校验：%s" % str(issues))
	_test_cross_refs()
	_test_gate_text()
	_test_main_chain_from_old_save()
	_test_side_abandon_and_reaccept()
	_test_ending_idempotent_without_growth_reset()
	print("[ChapterSixQuestsTest] ", "全部通过 ✅" if failures.is_empty() else str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)

# ---- ① 数据一致性 ----

func _c6_quests() -> Array:
	var out: Array = []
	for tpl in Quest.all():
		if tpl is Dictionary and String((tpl as Dictionary).get("id", "")).begins_with("C6"):
			out.append(tpl)
	return out

func _test_cross_refs() -> void:
	check(_c6_quests().size() == 18, "本章登记 12 主线 + 6 支线")
	for tpl in _c6_quests():
		var qid := String(tpl.get("id", ""))
		var giver := String(tpl.get("giver", ""))
		var turn_in := String(tpl.get("turnIn", giver))
		check(not MapService.map_for_npc(giver).is_empty(), "%s 发布人 %s 可定位" % [qid, giver])
		check(not MapService.map_for_npc(turn_in).is_empty(), "%s 交付人 %s 可定位" % [qid, turn_in])
		var obj: Dictionary = tpl.get("objective", {})
		var kind := String(obj.get("kind", ""))
		if kind == "kill":
			check(_monster_spawns_in_scope(String(obj.get("targetId", "")), tpl.get("mapScope", [])),
				"%s 击杀目标在允许范围内真实刷新" % qid)
		elif kind == "collect" and not String(obj.get("sourceMonster", "")).is_empty():
			check(_monster_spawns_in_scope(String(obj.get("sourceMonster", "")), tpl.get("mapScope", [])),
				"%s 收集来源怪在允许范围内真实刷新" % qid)
		elif kind == "talk":
			check(_npc_in_scope(String(obj.get("targetId", "")), tpl.get("mapScope", [])),
				"%s 交谈目标在允许范围内" % qid)

## 目标怪是否出现在 scope 内任一图的 spawnPoints / bossSpawn。
func _monster_spawns_in_scope(monster_id: String, scope: Variant) -> bool:
	if not scope is Array:
		return false
	for map_id in (scope as Array):
		var map_data := MapService.data_for(String(map_id))
		for spec in map_data.get("spawnPoints", []):
			if spec is Dictionary and String((spec as Dictionary).get("monsterId", "")) == monster_id:
				return true
		var boss: Variant = map_data.get("bossSpawn", null)
		if boss is Dictionary and String((boss as Dictionary).get("monsterId", "")) == monster_id:
			return true
	return false

func _npc_in_scope(npc_id: String, scope: Variant) -> bool:
	if not scope is Array:
		return false
	for map_id in (scope as Array):
		for npc in MapService.data_for(String(map_id)).get("npcs", []):
			if npc is Dictionary and String((npc as Dictionary).get("npcId", "")) == npc_id:
				return true
	return false

# ---- ② 门禁文案（未领奖时）----

func _test_gate_text() -> void:
	for map_id in GATES:
		var spec: Array = GATES[map_id]
		var flag := String(spec[0])
		check(not MapService.is_unlocked(map_id), "%s 初始锁住" % map_id)
		var reason := MapService.locked_reason(map_id)
		var deliverer := MapService.npc_name(String(spec[2]))
		check(not deliverer.is_empty() and reason.contains(deliverer), "%s 封锁文案指名交付人 %s" % [map_id, deliverer])
		check(reason.contains(String(Quest.template(String(spec[1])).get("name", ""))), "%s 封锁文案指明产出任务" % map_id)
		check(MapService.unlock_source(flag) == Quest.template(String(spec[1])), "%s 解锁键产出自 %s" % [flag, spec[1]])

# ---- ③ 旧档接第六章：12 主线全通 + 三态分离 ----

func _test_main_chain_from_old_save() -> void:
	# 旧档：仅 C5Q14 已领奖（chapter6 由该任务 reward 写入）。
	GameState.quest_states["C5Q14"] = {"state": Quest.STATE_REWARDED, "progress": 1}
	GameState.unlocks["chapter5"] = true
	GameState.unlocks["chapter6"] = true
	check(Quest.state_of("C6Q01") == Quest.STATE_AVAILABLE, "C5Q14 领奖后才开放第六章起始任务")
	check(Quest.state_of("C6S01") == Quest.STATE_LOCKED, "附属支线按前置任务锁定")

	# C6Q01 交谈（接取即达标）
	_accept("C6Q01", "c6_npc01")
	check(Quest.state_of("C6Q01") == Quest.STATE_COMPLETED, "交谈任务接取即达标")
	_deliver("C6Q01", "c6_npc01")
	check(Quest.state_of("C6S01") == Quest.STATE_AVAILABLE, "C6Q01 领奖后开放附属支线")
	# C6Q02 交谈（前哨外廊）
	_accept("C6Q02", "c6_npc09")
	_deliver("C6Q02", "c6_npc09")
	# C6Q03 收集守护誓条 ×4 → 解开守誓兵库
	_accept("C6Q03", "c6_npc09")
	_collect("C6Q03", "c6_map01", "c6_normal05", 4, "c6_item_q03")
	_deliver("C6Q03", "c6_npc09")
	check(bool(GameState.unlocks.get("c6_access_02", false)) and MapService.is_unlocked("c6_map02"),
		"C6Q03 领奖解除守誓兵库门禁")
	# C6Q04 击杀裂纹卫体 ×10
	_accept("C6Q04", "c6_npc09")
	_kill("C6Q04", "c6_map02", "c6_normal01", 10)
	_deliver("C6Q04", "c6_npc09")
	# C6Q05 击杀守誓审判体 → 解开分流环室
	_accept("C6Q05", "c6_npc09")
	_kill("C6Q05", "c6_map02", "c6_boss01", 1)
	_deliver("C6Q05", "c6_npc01")
	check(bool(GameState.unlocks.get("c6_access_03", false)) and MapService.is_unlocked("c6_map03"),
		"C6Q05 领奖解除分流环室门禁")
	# C6Q06 收集旁路校验片 ×6 → 解开旧誓回廊
	_accept("C6Q06", "c6_npc01")
	_collect("C6Q06", "c6_map03", "c6_normal08", 6, "c6_item_q06")
	_deliver("C6Q06", "c6_npc01")
	check(bool(GameState.unlocks.get("c6_access_04", false)) and MapService.is_unlocked("c6_map04"),
		"C6Q06 领奖解除旧誓回廊门禁")
	# C6Q07 交谈（三份记录）
	_accept("C6Q07", "c6_npc08")
	_deliver("C6Q07", "c6_npc08")
	# C6Q08 击杀空环重体 ×14
	_accept("C6Q08", "c6_npc07")
	_kill("C6Q08", "c6_map03", "c6_normal07", 14)
	_deliver("C6Q08", "c6_npc10")
	# C6Q09 交谈 → 解开屏障心台
	_accept("C6Q09", "c6_npc10")
	_deliver("C6Q09", "c6_npc10")
	check(bool(GameState.unlocks.get("c6_access_05", false)) and MapService.is_unlocked("c6_map05"),
		"C6Q09 领奖解除屏障心台门禁")
	# C6Q10 击杀空天之眼 —— **核心击杀态**：目标达成，但正式结局尚未发生。
	_accept("C6Q10", "c6_npc10")
	_kill("C6Q10", "c6_map05", "c6_boss03", 1)
	check(not bool(GameState.unlocks.get("campaign_complete", false)), "击杀不直接写 campaign_complete")
	_deliver("C6Q10", "c6_npc01")
	check(not bool(GameState.unlocks.get("campaign_complete", false)), "击杀交付奖励仍不写 campaign_complete")
	# C6Q11 回前哨确认（**回流交付态**）
	_accept("C6Q11", "c6_npc01")
	_deliver("C6Q11", "c6_npc01")
	check(not bool(GameState.unlocks.get("campaign_complete", false)), "回流确认仍不写 campaign_complete")
	# C6Q12 读最后一页 —— 正式结局
	_accept("C6Q12", "c6_npc08")
	_deliver("C6Q12", "c6_npc08")
	check(bool(GameState.unlocks.get("campaign_complete", false)), "C6Q12 领奖写 campaign_complete")

	for qid in C6_MAIN:
		check(Quest.state_of(qid) == Quest.STATE_REWARDED, "%s 已完成领奖" % qid)
	check(not bool(GameState.first_clear.get("c6_boss02", false)), "主线不依赖可选首领 c6_boss02")
	check(Quest.state_of("C6S05") == Quest.STATE_LOCKED, "可选首领支线未做也不影响主线")

# ---- ④ 支线放弃 / 重接 ----

func _test_side_abandon_and_reaccept() -> void:
	check(not bool(Quest.template("C6Q01").get("abandonable", false)), "主线不可放弃")
	check(bool(Quest.template("C6S01").get("abandonable", false)), "支线可放弃")
	GameState.current_map = MapService.map_for_npc("c6_npc05")
	check(Quest.accept("C6S01", "c6_npc05").ok, "支线可接取")
	check(Quest.abandon("C6S01").ok and Quest.state_of("C6S01") == Quest.STATE_ABANDONED, "支线可放弃")
	check(Quest.accept("C6S01", "c6_npc05").ok, "放弃后可立即重接")
	check(int(Quest.progress_of("C6S01").get("cur", 0)) == 0, "重接后收集计数清零")
	Quest.abandon("C6S01")
	# 收集支线：放弃须一并清空任务袋物品。
	GameState.current_map = MapService.map_for_npc("c6_npc05")
	check(Quest.accept("C6S01", "c6_npc05").ok, "收集支线可重接")
	GameState.current_map = "c6_map01"
	for _i in range(2):
		Quest.on_monster_died_for_items("c6_normal02")
	check(int(GameState.quest_items.get("c6_item_s01", 0)) == 2, "收集支线累计任务袋物品")
	check(Quest.abandon("C6S01").ok, "收集支线可放弃")
	check(not GameState.quest_items.has("c6_item_s01"), "放弃清空任务袋物品")
	GameState.current_map = MapService.map_for_npc("c6_npc05")
	check(Quest.accept("C6S01", "c6_npc05").ok and int(Quest.progress_of("C6S01").get("cur", 0)) == 0,
		"重接后收集计数清零")

# ---- ⑤ 结局幂等且不清成长（终章专属）----

func _test_ending_idempotent_without_growth_reset() -> void:
	# 结算后记录成长快照：等级 / 金币 / 背包件数 / 已开地图。
	GameState.player["level"] = 60
	GameState.gold = 123456
	var bonus := ItemFactory.make_equip("c6_equip_weapon")
	check(not bonus.is_empty() and GameState.add_item(bonus), "背包装入一件镇脉装备")
	var level_before := int(GameState.player.get("level", 0))
	var gold_before := GameState.gold
	var bag_before := GameState.inventory_used()
	var saved := SaveManager._collect()
	check(SaveManager._is_valid_save(saved), "第六章结局后存档结构合法")

	# 重复读档：结局与奖励只一次。
	GameState.reset_to_defaults()
	SaveManager.apply_to_game_state(saved)
	check(Quest.state_of("C6Q12") == Quest.STATE_REWARDED, "重载后章末主线状态不倒退")
	check(bool(GameState.unlocks.get("campaign_complete", false)), "重载后正式结局标记保持")
	check(not Quest.deliver("C6Q12", "c6_npc08").ok, "重载后不能重复领奖（结局只一次）")

	# 不清成长：等级 / 金币 / 背包不回退。
	check(int(GameState.player.get("level", 0)) == level_before, "重载后等级不回退")
	check(GameState.gold == gold_before, "重载后金币不回退")
	check(GameState.inventory_used() == bag_before, "重载后背包件数不回退")
	# 旧图与支线仍可达：第五章门禁保持、章末支线开放、上一章枢纽仍解锁。
	check(bool(GameState.unlocks.get("chapter5", false)) and MapService.is_unlocked("c5_map00"),
		"旧章枢纽仍可达")
	check(MapService.is_unlocked("camp"), "营地仍可达")
	check(Quest.state_of("C6S06") == Quest.STATE_AVAILABLE, "结局后章末支线仍可接取")

# ---- 驱动辅助 ----

func _accept(qid: String, giver: String) -> void:
	GameState.current_map = MapService.map_for_npc(giver)
	check(Quest.accept(qid, giver).ok, "%s 由 %s 发布" % [qid, giver])

func _deliver(qid: String, npc_id: String) -> void:
	GameState.current_map = MapService.map_for_npc(npc_id)
	check(Quest.deliver(qid, npc_id).ok, "%s 由 %s 交付" % [qid, npc_id])

func _kill(qid: String, map_id: String, monster_id: String, count: int) -> void:
	GameState.current_map = map_id
	for _i in range(count):
		Quest.on_event("monster_died", monster_id)
	check(Quest.state_of(qid) == Quest.STATE_COMPLETED, "%s 击杀 %s ×%d 达成" % [qid, monster_id, count])

func _collect(qid: String, map_id: String, monster_id: String, count: int, item_id: String) -> void:
	GameState.current_map = map_id
	for _i in range(count):
		Quest.on_monster_died_for_items(monster_id)
	check(Quest.state_of(qid) == Quest.STATE_COMPLETED, "%s 收集 %s ×%d 达成" % [qid, item_id, count])
	check(int(GameState.quest_items.get(item_id, 0)) == count, "%s 任务袋累计 %d 件" % [item_id, count])
