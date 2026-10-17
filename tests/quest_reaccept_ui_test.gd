extends Node
## 任务可接判定与支线重接按钮的隔离回归，覆盖 NPC 身份、任务上限和放弃后重接。
## 测试只改临时 GameState；隔离运行器使用独立 user://，不触碰真实存档。

var failures: Array[String] = []

## 从新角色的营地任务状态出发，验证显示查询与实际接受按钮遵循同一规则。
func _ready() -> void:
	GameState.reset_to_defaults()
	GameState.current_map = "camp"
	check(Quest.can_accept("S001", "elder"), "初始支线可向长老接取")
	check(not Quest.can_accept("S001", "peddler_camp"), "错误 NPC 不能接取")
	check(Quest.available_givers_on_map("camp").has("elder"), "营地可接发布人按稳定 ID 查询")
	check(not Quest.available_givers_on_map("camp").has("peddler_camp"), "无任务 NPC 不误报")
	check(Quest.accept("S001", "elder").ok, "首次接取成功")
	check(not Quest.can_accept("S001", "elder"), "进行中任务不可重复接取")
	check(Quest.abandon("S001").ok, "支线允许放弃")
	check(Quest.can_accept("S001", "elder"), "放弃后允许立即重接")
	var panel := (load("res://scripts/ui/quest_panel.gd") as Script).new() as Control
	panel.set("_current_npc_id", "elder")
	var button := panel.call("_make_action_button", "S001", Quest.STATE_ABANDONED) as Button
	check(not button.disabled and button.text == Localization.tr_key("ui.quest_panel.p012"), "放弃态呈现可用的接受按钮")
	button.pressed.emit()
	check(Quest.state_of("S001") == Quest.STATE_ACTIVE and Quest.progress_of("S001").cur == 0,
		"任务面板按钮可重接且进度归零")
	check(Quest.abandon("S001").ok, "再次放弃以检查任务数量上限")
	for i in range(Quest.MAX_ACTIVE):
		GameState.quest_states["cap_test_%d" % i] = {"state": Quest.STATE_ACTIVE, "progress": 0}
	check(not Quest.can_accept("S001", "elder"), "任务数量已满时不可接")
	check(Quest.available_givers_on_map("camp").is_empty(), "任务数量已满时不显示可接发布人")
	for i in range(Quest.MAX_ACTIVE):
		GameState.quest_states.erase("cap_test_%d" % i)
	check(Quest.can_accept("S001", "elder"), "腾出任务名额后可重新接取")
	check(Quest.available_givers_on_map("wild_trial").is_empty(), "不为其他地图返回当前 NPC 标记")
	if failures.is_empty():
		print("QuestReacceptUiTest: PASS")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		get_tree().quit(1)

## 汇总断言，让任一交互或可接判定回退都会使本场景失败。
func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
