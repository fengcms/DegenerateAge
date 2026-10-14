extends Node
## Simulate the complete chapter-two main quest chain with explicit NPC delivery.

var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("[ChapterTwoQuestsTest] " + message)

func _ready() -> void:
	GameState.reset_to_defaults()
	var issues := DataLoader.validate_all()
	check(issues.is_empty(), "任务/装备/怪物引用合法：%s" % str(issues))
	for i in range(1, 6):
		GameState.quest_states["Q%03d" % i] = {"state": Quest.STATE_REWARDED, "progress": 1}
	GameState.unlocks["chapter2"] = true
	check(Quest.state_of("C2Q01") == Quest.STATE_AVAILABLE, "第一章结算后开放第二章任务")
	check(Quest.accept("C2Q01", "elder").ok, "长老发布第二章起始任务")
	check(Quest.state_of("C2Q01") == Quest.STATE_ACTIVE, "指定 NPC 交谈不能接取即完成")
	GameState.current_map = "c2_well_town"
	Quest.on_npc_talk("c2_lu_heng")
	check(Quest.state_of("C2Q01") == Quest.STATE_COMPLETED, "和陆衡交谈推进任务")
	check(not Quest.deliver("C2Q01", "elder").ok, "不能向发布人冒领异地交付")
	check(Quest.deliver("C2Q01", "c2_lu_heng").ok, "陆衡交付首任务")
	_run_kill("C2Q02", "c2_shi_cen", "c2_shi_cen", "c2_pipe_slope", "c2_spirit_larva", 12)
	GameState.current_map = "c2_pipe_slope"
	check(Quest.accept("C2Q03", "c2_shi_cen").ok, "石岑发布调压片任务")
	for i in range(4):
		Quest.on_monster_died_for_items("c2_broken_guard")
	check(Quest.state_of("C2Q03") == Quest.STATE_COMPLETED and int(GameState.quest_items.get("c2_pressure_plate", 0)) == 4,
		"确定来源任务物进入独立任务袋")
	check(not Quest.deliver("C2Q03", "c2_shi_cen").ok, "指定陆衡交付")
	GameState.current_map = "c2_well_town"
	check(Quest.deliver("C2Q03", "c2_lu_heng").ok, "领取固定奖励")
	check(not GameState.quest_items.has("c2_pressure_plate"), "交付消耗任务袋物品")
	var reward_found := false
	for item in GameState.inventory:
		if item is Dictionary and String(item.get("itemId", "")) == "c2_road_armor":
			reward_found = int(item.get("requiredLevel", 0)) == 11
	check(reward_found, "任务装备使用统一 Lv11 档")
	_run_kill("C2Q04", "c2_lu_heng", "c2_lu_heng", "c2_old_well", "c2_boss_iron_foreman", 1)
	_run_collect("C2Q05", "c2_qi_yan", "c2_qi_yan", "c2_lower_works", "c2_badge_wraith", 5)
	_run_collect("C2Q06", "c2_xu_zhu", "c2_xu_zhu", "c2_ember_furnace", "c2_copper_worm", 3)
	_run_kill("C2Q07", "c2_mi_cang", "c2_mi_cang", "c2_ember_furnace", "c2_ash_beast", 10)
	GameState.current_map = "c2_well_town"
	check(Quest.accept("C2Q08", "c2_bai_zhi").ok, "白芷发布备用炉交谈")
	check(Quest.state_of("C2Q08") == Quest.STATE_ACTIVE, "交谈前保持进行中")
	Quest.on_npc_talk("c2_lu_heng")
	check(Quest.deliver("C2Q08", "c2_lu_heng").ok and bool(GameState.unlocks.get("c2_backup_furnace", false)),
		"备用炉领奖后开放井心")
	check(MapService.is_unlocked("c2_well_core"), "井心地图解锁")
	_run_kill("C2Q09", "c2_lu_heng", "c2_lu_heng", "c2_well_core", "c2_broken_guard", 8)
	_run_kill("C2Q10", "c2_lu_heng", "c2_lu_heng", "c2_well_core", "c2_elite_spirit_guard", 1)
	check(bool(GameState.unlocks.get("c2_core_access", false)), "主机场地安全锁开放")
	_run_kill("C2Q11", "c2_lu_heng", "c2_lu_heng", "c2_well_core", "c2_boss_hundred_arm_extractor", 1)
	check(bool(GameState.unlocks.get("c2_machine_stopped", false)), "主机停转状态持久化标记")
	GameState.current_map = "c2_well_town"
	check(Quest.accept("C2Q12", "c2_qi_yan").ok, "记录员发布尾声")
	check(Quest.deliver("C2Q12", "c2_qi_yan").ok and bool(GameState.unlocks.get("chapter3", false)),
		"第二章完成，仅写入第三章解锁标记")
	check(not Quest.deliver("C2Q12", "c2_qi_yan").ok, "不能重复领奖")
	_run_kill("C2S01", "c2_miao_miao", "c2_miao_miao", "c2_pipe_slope", "c2_copper_worm", 8)
	_run_collect("C2S02", "c2_qi_yan", "c2_qi_yan", "c2_lower_works", "c2_badge_wraith", 3)
	_run_kill("C2S03", "c2_xu_zhu", "c2_xu_zhu", "c2_lower_works", "c2_elite_broken_inspector", 1)
	_run_kill("C2S04", "c2_bai_zhi", "c2_bai_zhi", "c2_ember_furnace", "c2_elite_copper_matriarch", 1)
	GameState.current_map = "c2_ember_furnace"
	Quest.on_event("monster_died", "c2_boss_slag_devourer")
	GameState.first_clear["c2_boss_slag_devourer"] = true
	GameState.current_map = "c2_well_town"
	check(Quest.accept("C2S05", "c2_bai_zhi").ok, "可选炉房 Boss 支线可接取")
	check(Quest.state_of("C2S05") == Quest.STATE_COMPLETED, "任务接取前的 Boss 首杀可回溯")
	check(Quest.deliver("C2S05", "c2_bai_zhi").ok, "回溯后仍需指定 NPC 交付")
	_run_kill("C2S06", "c2_lao_zhe", "c2_lao_zhe", "c2_pipe_slope", "c2_elite_broken_inspector", 1)
	var saved := SaveManager._collect()
	check(SaveManager._is_valid_save(saved), "两章任务结算后存档结构合法")
	GameState.reset_to_defaults()
	SaveManager.apply_to_game_state(saved)
	check(Quest.state_of("C2Q12") == Quest.STATE_REWARDED and Quest.state_of("C2S06") == Quest.STATE_REWARDED
		and bool(GameState.unlocks.get("chapter3", false)), "重载后主支线与章节标记不倒退")
	check(not Quest.deliver("C2S06", "c2_lao_zhe").ok, "重载后不能重复领取支线奖励")
	print("[ChapterTwoQuestsTest] ", "全部通过 ✅" if failures.is_empty() else str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)

func _run_kill(qid: String, giver: String, turn_in: String, map_id: String, monster_id: String, count: int) -> void:
	GameState.current_map = MapService.map_for_npc(giver)
	check(Quest.accept(qid, giver).ok, "%s 可接取" % qid)
	GameState.current_map = map_id
	for i in range(count):
		Quest.on_event("monster_died", monster_id)
	check(Quest.state_of(qid) == Quest.STATE_COMPLETED, "%s 达成" % qid)
	GameState.current_map = MapService.map_for_npc(turn_in)
	check(Quest.deliver(qid, turn_in).ok, "%s 领奖" % qid)

func _run_collect(qid: String, giver: String, turn_in: String, map_id: String, monster_id: String, count: int) -> void:
	GameState.current_map = MapService.map_for_npc(giver)
	check(Quest.accept(qid, giver).ok, "%s 可接取" % qid)
	GameState.current_map = map_id
	for i in range(count):
		Quest.on_monster_died_for_items(monster_id)
	check(Quest.state_of(qid) == Quest.STATE_COMPLETED, "%s 收集达成" % qid)
	GameState.current_map = MapService.map_for_npc(turn_in)
	check(Quest.deliver(qid, turn_in).ok, "%s 交付" % qid)
