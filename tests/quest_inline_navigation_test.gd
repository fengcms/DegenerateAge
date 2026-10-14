extends Node

var failures: Array[String] = []

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

func _entry(qid: String) -> Dictionary:
	for entry in Quest.list_states():
		if String(entry.get("id", "")) == qid:
			return entry
	return {}

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
