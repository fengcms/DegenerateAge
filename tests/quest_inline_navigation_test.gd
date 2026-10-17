extends Node
## 任务行内链接回归：验证状态切换、跨图导航和 NPC 地点的显示一致性。
## 使用隔离测试工程中的任务数据，不写入正式存档。

var failures: Array[String] = []

## 准备任务状态并执行行内文案与导航断言，最后以退出码汇报结果。
func _ready() -> void:
	GameState.current_map = "camp"
	GameState.quest_states["Q002"] = {"state": Quest.STATE_ACTIVE, "progress": 2}
	var entry := _entry("Q002")
	var active := QuestInlineText.markup(entry)
	check(active.contains("2/5") and active.contains("[url=monster:wolf_corrupted]")
		and active.contains("[url=map:wild_trial]"), "进行中文案包含可点目标、地图与实时进度")
	var route := Quest.start_link_navigation("Q002", "monster", "wolf_corrupted")
	check(bool(route.get("ok", false)) and MapService.quest_nav_kind == "monster"
		and MapService.quest_nav_map == "wild_trial", "怪物链接沿步行图导航")
	check(not bool(Quest.start_link_navigation("Q002", "npc", "elder").get("ok", false)), "进行中不能提前导航交付")
	GameState.quest_states["Q002"] = {"state": Quest.STATE_COMPLETED, "progress": 5}
	entry = _entry("Q002")
	var completed := QuestInlineText.markup(entry)
	check(completed.contains("[url=npc:elder]") and not completed.contains("[url=monster:"),
		"完成态只保留交付 NPC 链接")
	check(completed.count("[url=map:camp]") == 1, "显式写出交付地图时不重复补地点")
	var chapter_three_npc := "c3_npc01"
	var chapter_three_map := MapService.map_for_npc(chapter_three_npc)
	var chapter_three_text := QuestInlineText.markup({
		"state": Quest.STATE_COMPLETED,
		"turnInText": "到 {npc:c3_npc01} 交付任务。",
	})
	check(not chapter_three_map.is_empty()
		and chapter_three_text.contains("[url=map:%s]" % chapter_three_map)
		and chapter_three_text.find("[url=map:%s]" % chapter_three_map) < chapter_three_text.find("[url=npc:c3_npc01]"),
		"未配置地图的交付文案在 NPC 前补齐真实所在地图")
	var other_map_text := QuestInlineText.markup({
		"state": Quest.STATE_ACTIVE,
		"trackerText": "从 {map:wild_trial} 去找 {npc:elder}。",
	})
	check(other_map_text.contains("[url=map:camp]")
		and other_map_text.find("[url=map:camp]") < other_map_text.find("[url=npc:elder]"),
		"文案中的其他地图不能掩盖 NPC 实际位置")
	var unknown_npc := QuestInlineText.markup({
		"state": Quest.STATE_ACTIVE,
		"trackerText": "找 {npc:missing_npc}。",
	})
	check(not unknown_npc.contains("[url=map:") and unknown_npc.contains("{npc:missing_npc}"),
		"未知 NPC 不伪造地图信息")
	route = Quest.start_link_navigation("Q002", "map", "camp")
	check(bool(route.get("ok", false)) and MapService.quest_nav_kind == "map"
		and MapService.quest_nav_map == "camp", "交付地图链接仍可单独导航到城镇")
	route = Quest.start_link_navigation("Q002", "npc", "elder")
	check(bool(route.get("ok", false)) and MapService.quest_nav_kind == "npc"
		and MapService.quest_nav_map == "camp", "交付 NPC 导航到营地")
	check(not bool(Quest.start_link_navigation("Q002", "monster", "wolf_corrupted").get("ok", false)),
		"完成态不能继续沿旧怪物链接导航")
	MapService.clear_quest_navigation()
	if failures.is_empty():
		print("[QuestInlineNavigationTest] 全部通过 ✅")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	get_tree().quit(0 if failures.is_empty() else 1)

## 从实际任务状态列表取指定条目，用于检验与游戏相同的文案选择路径。
func _entry(qid: String) -> Dictionary:
	for entry in Quest.list_states():
		if String(entry.get("id", "")) == qid:
			return entry
	return {}

## 累积断言失败，使测试退出时同时报告所有文案或导航问题。
func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
