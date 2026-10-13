extends Node
## 加载状态、配置异常与首次引导均有可见界面，不写真实槽位。

var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)

func _ready() -> void:
	GameState.reset_to_defaults()
	GameState.menu_mode = "world"
	var feedback: Control = load("res://scripts/ui/flow_feedback.gd").new()
	add_child(feedback)
	await get_tree().process_frame
	check(feedback._guide.visible, "新角色看得到首屏操作提示")
	feedback._dismiss_guide()
	check(bool(GameState.settings.tutorialSeen) and not feedback._guide.visible, "提示可关闭并记忆")
	feedback._maybe_first_guide()
	check(not feedback._guide.visible, "已关闭的提示不重复出现")
	var errors: Array[String] = ["缺失测试配置"]
	feedback.show_config_errors(errors)
	check(feedback._warning.visible and feedback._warning_text.text.contains("缺失测试配置"), "配置错误玩家可见")
	EventBus.loading_changed.emit(true, "正在载入测试地图")
	check(feedback._loading.visible and feedback._loading_title.text.contains("测试地图"), "加载状态带真实目的地")
	EventBus.loading_changed.emit(false, "")
	check(not feedback._loading.visible, "加载完成撤去提示")
	EventBus.quest_accepted.emit("Q002")
	check(feedback._guide.visible and feedback._guide_text.text.contains("F"), "首战提示自动战斗快捷键")
	feedback._dismiss_guide()
	check(bool(GameState.settings.firstBattleHintSeen), "首战提示状态写入角色设置")
	if failures.is_empty():
		print("FlowFeedbackTest: PASS")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		get_tree().quit(1)
