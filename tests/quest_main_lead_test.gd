extends Node
## 主线接续验收：覆盖跨图发布人、支线并行、未领奖提示与重载后的下一步。
## 运行在隔离项目中，只修改测试 GameState，不写入玩家存档。

var failures: Array[String] = []

## 从第一章结算推进到断管坡任务，再验证状态切换与链接权限。
func _ready() -> void:
	GameState.reset_to_defaults()
	for i in range(1, 6):
		GameState.quest_states["Q%03d" % i] = {"state": Quest.STATE_REWARDED, "progress": 1}
	GameState.unlocks["chapter2"] = true
	GameState.current_map = "camp"
	_check(Quest.accept("C2Q01", "elder").ok, "能从长老接取起始主线")
	_check(Quest.next_main_lead().is_empty(), "主线进行中不显示下一步")
	GameState.current_map = "c2_well_town"
	Quest.on_npc_talk("c2_lu_heng")
	_check(Quest.lock_reason("C2Q02").contains("陆衡") and Quest.lock_reason("C2Q02").contains("奖励"),
		"首任务达标但未领奖时锁定原因指出交付人")
	_check(Quest.next_main_lead().is_empty(), "待领奖时不提前显示下一主线")
	_check(Quest.deliver("C2Q01", "c2_lu_heng").ok, "陆衡交付后解锁新主线")
	var lead := Quest.next_main_lead()
	_check(String(lead.get("id", "")) == "C2Q02" and String(lead.get("giverMap", "")) == "c2_pipe_slope",
		"下一步指向断管坡的石岑")
	var markup := QuestInlineText.markup(lead)
	_check(markup.contains("[url=map:c2_pipe_slope]") and markup.contains("[url=npc:c2_shi_cen]"),
		"下一步地图与 NPC 均可点击")
	_check(not bool(Quest.start_link_navigation("C2Q02", "npc", "c2_lu_heng").get("ok", false)),
		"未接取任务不能导航到其他 NPC")
	var route := Quest.start_link_navigation("C2Q02", "npc", "c2_shi_cen")
	_check(bool(route.get("ok", false)) and MapService.quest_nav_map == "c2_pipe_slope"
		and MapService.quest_nav_kind == "npc", "跨图链接走向发布 NPC")
	MapService.clear_quest_navigation()
	GameState.quest_states["C2S01"] = {"state": Quest.STATE_ACTIVE, "progress": 2}
	_check(String(Quest.next_main_lead().get("id", "")) == "C2Q02", "支线进行中不遮挡主线提示")
	var saved := SaveManager._collect()
	GameState.reset_to_defaults()
	SaveManager.apply_to_game_state(saved)
	_check(String(Quest.next_main_lead().get("id", "")) == "C2Q02", "读档后重新推导下一步")
	GameState.current_map = "c2_pipe_slope"
	_check(Quest.accept("C2Q02", "c2_shi_cen").ok and Quest.next_main_lead().is_empty(),
		"石岑接取后下一步提示消失")
	GameState.quest_states["C2Q02"] = {"state": Quest.STATE_REWARDED, "progress": 12}
	_check(String(Quest.next_main_lead().get("id", "")) == "C2Q03", "后续主线可使用同一接续规则")
	for i in range(3, 13):
		GameState.quest_states["C2Q%02d" % i] = {"state": Quest.STATE_REWARDED, "progress": 1}
	_check(Quest.next_main_lead().is_empty(), "章节全部领奖后不显示虚假的下一步")
	MapService.clear_quest_navigation()
	print("[QuestMainLeadTest] ", "全部通过 ✅" if failures.is_empty() else str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)

## 汇总断言，失败时返回非零退出码供隔离测试器识别。
func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("[QuestMainLeadTest] " + message)
