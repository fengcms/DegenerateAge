extends Node
## 第五章 41—50 任务链与门禁（33 §5 批次 5.3 准出）：
##   · 21 条任务的数据一致性（发布人 / 交付人可定位、击杀 / 收集目标在其 mapScope 图内真实刷新）；
##   · 旧档 C4Q12 领奖后 14 条主线全部可完成，逐步解除 `c5_access_02/03/04/05/06` 与 `chapter6`；
##   · **不依赖可选 Boss c5_boss02** 也能推进主线；
##   · 主线未领奖时出口封锁，文案指名交付人与产出任务；
##   · 支线可放弃 / 重接，计数与任务袋物品清零；
##   · 章末存档重载后状态与门禁不倒退。

const C5_MAIN := ["C5Q01", "C5Q02", "C5Q03", "C5Q04", "C5Q05", "C5Q06", "C5Q07",
	"C5Q08", "C5Q09", "C5Q10", "C5Q11", "C5Q12", "C5Q13", "C5Q14"]
const C5_SIDE := ["C5S01", "C5S02", "C5S03", "C5S04", "C5S05", "C5S06", "C5S07"]
## 门禁与产出任务的对应（33 §4）；断旗关由第四章收尾任务产出。
const GATES := {
	"c5_map00": ["chapter5", "C4Q12", "c4_npc08"],
	"c5_map02": ["c5_access_02", "C5Q03", "c5_npc09"],
	"c5_map03": ["c5_access_03", "C5Q05", "c5_npc01"],
	"c5_map04": ["c5_access_04", "C5Q06", "c5_npc05"],
	"c5_map05": ["c5_access_05", "C5Q09", "c5_npc10"],
	"c5_map06": ["c5_access_06", "C5Q11", "c5_npc11"],
}

var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("[ChapterFiveQuestsTest] " + message)

func _ready() -> void:
	GameState.reset_to_defaults()
	var issues := DataLoader.validate_all()
	check(issues.is_empty(), "所有数据表通过引用校验：%s" % str(issues))
	_test_cross_refs()
	_test_gate_text()
	_test_main_chain_from_old_save()
	_test_side_abandon_and_reaccept()
	_test_save_roundtrip()
	print("[ChapterFiveQuestsTest] ", "全部通过 ✅" if failures.is_empty() else str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)

# ---- ① 数据一致性 ----

func _c5_quests() -> Array:
	var out: Array = []
	for tpl in Quest.all():
		if tpl is Dictionary and String((tpl as Dictionary).get("id", "")).begins_with("C5"):
			out.append(tpl)
	return out

func _test_cross_refs() -> void:
	check(_c5_quests().size() == 21, "本章登记 14 主线 + 7 支线")
	for tpl in _c5_quests():
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

# ---- ③ 旧档接第五章：14 主线全通 ----

func _test_main_chain_from_old_save() -> void:
	# 旧档：仅 C4Q12 已领奖（chapter5 由该任务 reward 写入）。
	GameState.quest_states["C4Q12"] = {"state": Quest.STATE_REWARDED, "progress": 1}
	GameState.unlocks["chapter4"] = true
	GameState.unlocks["chapter5"] = true
	check(Quest.state_of("C5Q01") == Quest.STATE_AVAILABLE, "C4Q12 领奖后才开放第五章起始任务")
	check(Quest.state_of("C5S01") == Quest.STATE_LOCKED, "附属支线按前置任务锁定")

	# C5Q01 交谈（接取即达标）
	_accept("C5Q01", "c5_npc01")
	check(Quest.state_of("C5Q01") == Quest.STATE_COMPLETED, "交谈任务接取即达标")
	_deliver("C5Q01", "c5_npc01")
	check(Quest.state_of("C5S01") == Quest.STATE_AVAILABLE, "C5Q01 领奖后开放附属支线")
	# C5Q02 击杀潮甲步卒 ×12（越堤路）
	_accept("C5Q02", "c5_npc01")
	_kill("C5Q02", "c5_map01", "c5_normal01", 12)
	_deliver("C5Q02", "c5_npc09")
	# C5Q03 收集号台残签 ×4 → 解开号台旧址
	_accept("C5Q03", "c5_npc09")
	_collect("C5Q03", "c5_map01", "c5_normal04", 4, "c5_item_q03")
	_deliver("C5Q03", "c5_npc09")
	check(bool(GameState.unlocks.get("c5_access_02", false)) and MapService.is_unlocked("c5_map02"),
		"C5Q03 领奖解除号台旧址门禁")
	# C5Q04 交谈
	_accept("C5Q04", "c5_npc09")
	_deliver("C5Q04", "c5_npc09")
	# C5Q05 击杀号将 → 解开战地营道
	_accept("C5Q05", "c5_npc09")
	_kill("C5Q05", "c5_map02", "c5_boss01", 1)
	_deliver("C5Q05", "c5_npc01")
	check(bool(GameState.unlocks.get("c5_access_03", false)) and MapService.is_unlocked("c5_map03"),
		"C5Q05 领奖解除战地营道门禁")
	# C5Q06 收集营道标片 ×6 → 解开观察哨所
	_accept("C5Q06", "c5_npc05")
	_collect("C5Q06", "c5_map03", "c5_normal07", 6, "c5_item_q06")
	_deliver("C5Q06", "c5_npc05")
	check(bool(GameState.unlocks.get("c5_access_04", false)) and MapService.is_unlocked("c5_map04"),
		"C5Q06 领奖解除观察哨所门禁")
	# C5Q07 交谈
	_accept("C5Q07", "c5_npc01")
	_deliver("C5Q07", "c5_npc01")
	# C5Q08 击杀旗索猎手 ×14
	_accept("C5Q08", "c5_npc05")
	_kill("C5Q08", "c5_map03", "c5_normal02", 14)
	_deliver("C5Q08", "c5_npc10")
	# C5Q09 交谈 → 解开逆风关楼
	_accept("C5Q09", "c5_npc10")
	_deliver("C5Q09", "c5_npc10")
	check(bool(GameState.unlocks.get("c5_access_05", false)) and MapService.is_unlocked("c5_map05"),
		"C5Q09 领奖解除逆风关楼门禁")
	# C5Q10 击杀军团长
	_accept("C5Q10", "c5_npc10")
	_kill("C5Q10", "c5_map05", "c5_boss03", 1)
	_deliver("C5Q10", "c5_npc11")
	# C5Q11 交谈 → 解开裂隙深处
	_accept("C5Q11", "c5_npc11")
	_deliver("C5Q11", "c5_npc11")
	check(bool(GameState.unlocks.get("c5_access_06", false)) and MapService.is_unlocked("c5_map06"),
		"C5Q11 领奖解除裂隙深处门禁")
	# C5Q12 击杀裂隙统帅 → C5Q13 / C5Q14 交谈收尾
	_accept("C5Q12", "c5_npc11")
	_kill("C5Q12", "c5_map06", "c5_boss04", 1)
	_deliver("C5Q12", "c5_npc01")
	_accept("C5Q13", "c5_npc07")
	_deliver("C5Q13", "c5_npc07")
	_accept("C5Q14", "c5_npc08")
	_deliver("C5Q14", "c5_npc08")
	check(bool(GameState.unlocks.get("chapter6", false)), "C5Q14 领奖解锁通往第六章")

	for qid in C5_MAIN:
		check(Quest.state_of(qid) == Quest.STATE_REWARDED, "%s 已完成领奖" % qid)
	check(not bool(GameState.first_clear.get("c5_boss02", false)), "主线不依赖可选首领 c5_boss02")
	check(Quest.state_of("C5S05") == Quest.STATE_LOCKED, "可选首领支线未做也不影响主线")

# ---- ④ 支线放弃 / 重接 ----

func _test_side_abandon_and_reaccept() -> void:
	check(not bool(Quest.template("C5Q01").get("abandonable", false)), "主线不可放弃")
	check(bool(Quest.template("C5S01").get("abandonable", false)), "支线可放弃")
	GameState.current_map = MapService.map_for_npc("c5_npc07")
	check(Quest.accept("C5S01", "c5_npc07").ok, "支线可接取")
	check(Quest.abandon("C5S01").ok and Quest.state_of("C5S01") == Quest.STATE_ABANDONED, "支线可放弃")
	check(Quest.accept("C5S01", "c5_npc07").ok, "放弃后可立即重接")
	check(int(Quest.progress_of("C5S01").get("cur", 0)) == 0, "重接后击杀计数清零")
	Quest.abandon("C5S01")
	# 收集支线：放弃须一并清空任务袋物品。
	GameState.current_map = MapService.map_for_npc("c5_npc05")
	check(Quest.accept("C5S03", "c5_npc05").ok, "商店 NPC 也可发布支线")
	GameState.current_map = "c5_map03"
	for _i in range(2):
		Quest.on_monster_died_for_items("c5_normal07")
	check(int(GameState.quest_items.get("c5_item_s03", 0)) == 2, "收集支线累计任务袋物品")
	check(Quest.abandon("C5S03").ok, "收集支线可放弃")
	check(not GameState.quest_items.has("c5_item_s03"), "放弃清空任务袋物品")
	GameState.current_map = MapService.map_for_npc("c5_npc05")
	check(Quest.accept("C5S03", "c5_npc05").ok and int(Quest.progress_of("C5S03").get("cur", 0)) == 0,
		"重接后收集计数清零")

# ---- ⑤ 存档往返 ----

func _test_save_roundtrip() -> void:
	var saved := SaveManager._collect()
	check(SaveManager._is_valid_save(saved), "第五章任务结算后存档结构合法")
	GameState.reset_to_defaults()
	SaveManager.apply_to_game_state(saved)
	check(Quest.state_of("C5Q14") == Quest.STATE_REWARDED, "重载后章末主线状态不倒退")
	check(bool(GameState.unlocks.get("chapter6", false)), "重载后第六章门禁保持开放")
	check(not Quest.deliver("C5Q14", "c5_npc08").ok, "重载后不能重复领奖")

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
