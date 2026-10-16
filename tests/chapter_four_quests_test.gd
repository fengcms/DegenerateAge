extends Node
## 第四章 31—40 任务链与门禁（32 §5 批次 4.3 准出）：
##   · 18 条任务的数据一致性（发布人 / 交付人可定位、击杀 / 收集目标在其 mapScope 图内真实刷新）；
##   · 旧档 C3Q12 领奖后 12 条主线全部可完成，逐步解除 `c4_access_02/03/04/05` 与 `chapter5`；
##   · **不依赖可选 Boss c4_boss02** 也能推进主线；
##   · 主线未领奖时出口封锁，文案指名交付人与产出任务；
##   · 支线可放弃 / 重接，计数与任务袋物品清零；
##   · 章末存档重载后状态与门禁不倒退。

const C4_MAIN := ["C4Q01", "C4Q02", "C4Q03", "C4Q04", "C4Q05", "C4Q06",
	"C4Q07", "C4Q08", "C4Q09", "C4Q10", "C4Q11", "C4Q12"]
const C4_SIDE := ["C4S01", "C4S02", "C4S03", "C4S04", "C4S05", "C4S06"]
## 门禁与产出任务的对应（32 §4）；根驿营地由第三章收尾任务产出。
const GATES := {
	"c4_map00": ["chapter4", "C3Q12", "c3_npc08"],
	"c4_map02": ["c4_access_02", "C4Q03", "c4_npc09"],
	"c4_map03": ["c4_access_03", "C4Q05", "c4_npc01"],
	"c4_map04": ["c4_access_04", "C4Q06", "c4_npc08"],
	"c4_map05": ["c4_access_05", "C4Q09", "c4_npc10"],
}

var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("[ChapterFourQuestsTest] " + message)

func _ready() -> void:
	GameState.reset_to_defaults()
	var issues := DataLoader.validate_all()
	check(issues.is_empty(), "所有数据表通过引用校验：%s" % str(issues))
	_test_cross_refs()
	_test_gate_text()
	_test_main_chain_from_old_save()
	_test_side_abandon_and_reaccept()
	_test_save_roundtrip()
	print("[ChapterFourQuestsTest] ", "全部通过 ✅" if failures.is_empty() else str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)

# ---- ① 数据一致性 ----

func _c4_quests() -> Array:
	var out: Array = []
	for tpl in Quest.all():
		if tpl is Dictionary and String((tpl as Dictionary).get("id", "")).begins_with("C4"):
			out.append(tpl)
	return out

func _test_cross_refs() -> void:
	check(_c4_quests().size() == 18, "本章登记 12 主线 + 6 支线")
	for tpl in _c4_quests():
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

# ---- ③ 旧档接第四章：12 主线全通 ----

func _test_main_chain_from_old_save() -> void:
	# 旧档：仅 C3Q12 已领奖（chapter4 由该任务 reward 写入）。
	GameState.quest_states["C3Q12"] = {"state": Quest.STATE_REWARDED, "progress": 1}
	GameState.unlocks["chapter3"] = true
	GameState.unlocks["chapter4"] = true
	check(Quest.state_of("C4Q01") == Quest.STATE_AVAILABLE, "C3Q12 领奖后才开放第四章起始任务")
	check(Quest.state_of("C4S01") == Quest.STATE_LOCKED, "附属支线按前置任务锁定")

	# C4Q01 交谈（接取即达标）
	_accept("C4Q01", "c4_npc01")
	check(Quest.state_of("C4Q01") == Quest.STATE_COMPLETED, "交谈任务接取即达标")
	_deliver("C4Q01", "c4_npc01")
	check(Quest.state_of("C4S01") == Quest.STATE_AVAILABLE, "C4Q01 领奖后开放附属支线")
	# C4Q02 收集倒根皮 ×4（倒根驿路）
	_accept("C4Q02", "c4_npc09")
	_collect("C4Q02", "c4_map01", "c4_normal03", 4, "c4_item_q02")
	_deliver("C4Q02", "c4_npc09")
	# C4Q03 交谈 → 解开失声哨林
	_accept("C4Q03", "c4_npc09")
	_deliver("C4Q03", "c4_npc09")
	check(bool(GameState.unlocks.get("c4_access_02", false)) and MapService.is_unlocked("c4_map02"),
		"C4Q03 领奖解除失声哨林门禁")
	# C4Q04 击杀巡林者 ×10
	_accept("C4Q04", "c4_npc09")
	_kill("C4Q04", "c4_map02", "c4_normal08", 10)
	_deliver("C4Q04", "c4_npc09")
	# C4Q05 击杀无声巡林者 → 解开观测站外环
	_accept("C4Q05", "c4_npc09")
	_kill("C4Q05", "c4_map02", "c4_boss01", 1)
	_deliver("C4Q05", "c4_npc01")
	check(bool(GameState.unlocks.get("c4_access_03", false)) and MapService.is_unlocked("c4_map03"),
		"C4Q05 领奖解除观测站外环门禁")
	# C4Q06 收集峰值表 ×6 → 解开孢灯深圃
	_accept("C4Q06", "c4_npc08")
	_collect("C4Q06", "c4_map03", "c4_normal05", 6, "c4_item_q06")
	_deliver("C4Q06", "c4_npc08")
	check(bool(GameState.unlocks.get("c4_access_04", false)) and MapService.is_unlocked("c4_map04"),
		"C4Q06 领奖解除孢灯深圃门禁")
	# C4Q07 交谈
	_accept("C4Q07", "c4_npc08")
	_deliver("C4Q07", "c4_npc08")
	# C4Q08 击杀缠根巡卫 ×14
	_accept("C4Q08", "c4_npc08")
	_kill("C4Q08", "c4_map03", "c4_normal04", 14)
	_deliver("C4Q08", "c4_npc10")
	# C4Q09 交谈 → 解开回流观测台
	_accept("C4Q09", "c4_npc10")
	_deliver("C4Q09", "c4_npc10")
	check(bool(GameState.unlocks.get("c4_access_05", false)) and MapService.is_unlocked("c4_map05"),
		"C4Q09 领奖解除回流观测台门禁")
	# C4Q10 击杀缠根守门者
	_accept("C4Q10", "c4_npc10")
	_kill("C4Q10", "c4_map05", "c4_boss03", 1)
	_deliver("C4Q10", "c4_npc01")
	# C4Q11 / C4Q12 交谈收尾
	_accept("C4Q11", "c4_npc01")
	_deliver("C4Q11", "c4_npc01")
	_accept("C4Q12", "c4_npc08")
	_deliver("C4Q12", "c4_npc08")
	check(bool(GameState.unlocks.get("chapter5", false)), "C4Q12 领奖解锁通往第五章")

	for qid in C4_MAIN:
		check(Quest.state_of(qid) == Quest.STATE_REWARDED, "%s 已完成领奖" % qid)
	check(not bool(GameState.first_clear.get("c4_boss02", false)), "主线不依赖可选首领 c4_boss02")
	check(Quest.state_of("C4S05") == Quest.STATE_LOCKED, "可选首领支线未做也不影响主线")

# ---- ④ 支线放弃 / 重接 ----

func _test_side_abandon_and_reaccept() -> void:
	check(not bool(Quest.template("C4Q01").get("abandonable", false)), "主线不可放弃")
	check(bool(Quest.template("C4S01").get("abandonable", false)), "支线可放弃")
	GameState.current_map = MapService.map_for_npc("c4_npc07")
	check(Quest.accept("C4S01", "c4_npc07").ok, "支线可接取")
	check(Quest.abandon("C4S01").ok and Quest.state_of("C4S01") == Quest.STATE_ABANDONED, "支线可放弃")
	check(Quest.accept("C4S01", "c4_npc07").ok, "放弃后可立即重接")
	check(int(Quest.progress_of("C4S01").get("cur", 0)) == 0, "重接后击杀计数清零")
	Quest.abandon("C4S01")
	# 收集支线：放弃须一并清空任务袋物品。
	GameState.current_map = MapService.map_for_npc("c4_npc05")
	check(Quest.accept("C4S03", "c4_npc05").ok, "商店 NPC 也可发布支线")
	GameState.current_map = "c4_map02"
	for _i in range(2):
		Quest.on_monster_died_for_items("c4_normal02")
	check(int(GameState.quest_items.get("c4_item_s03", 0)) == 2, "收集支线累计任务袋物品")
	check(Quest.abandon("C4S03").ok, "收集支线可放弃")
	check(not GameState.quest_items.has("c4_item_s03"), "放弃清空任务袋物品")
	GameState.current_map = MapService.map_for_npc("c4_npc05")
	check(Quest.accept("C4S03", "c4_npc05").ok and int(Quest.progress_of("C4S03").get("cur", 0)) == 0,
		"重接后收集计数清零")

# ---- ⑤ 存档往返 ----

func _test_save_roundtrip() -> void:
	var saved := SaveManager._collect()
	check(SaveManager._is_valid_save(saved), "第四章任务结算后存档结构合法")
	GameState.reset_to_defaults()
	SaveManager.apply_to_game_state(saved)
	check(Quest.state_of("C4Q12") == Quest.STATE_REWARDED, "重载后章末主线状态不倒退")
	check(bool(GameState.unlocks.get("chapter5", false)), "重载后第五章门禁保持开放")
	check(not Quest.deliver("C4Q12", "c4_npc08").ok, "重载后不能重复领奖")

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
