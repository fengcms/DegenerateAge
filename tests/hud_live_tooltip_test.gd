extends Node
## HUD 血蓝与经验提示回归：在提示持续打开时，通过真实角色数值事件检查文字即时变化。
## 在隔离测试项目中运行，不读写玩家正式存档，也不验证窗口管理器的视觉放置。

var failures: Array[String] = []

## 装配正式 HUD 后持续保留提示，验证数值变化与升级均无需移开鼠标。
func _ready() -> void:
	GameState.reset_to_defaults()
	GameState.menu_mode = "world"
	var main := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(main)
	await get_tree().process_frame
	var hp_bar := main.get_node("UI/Hud/StatusPanel/HpBar") as HudStatusBar
	var mp_bar := main.get_node("UI/Hud/StatusPanel/MpBar") as HudStatusBar
	var exp_bar := main.get_node("UI/Hud/ExpBar") as HudExperienceBar
	var hp_tooltip := hp_bar._make_custom_tooltip(hp_bar.tooltip_text) as PanelContainer
	var mp_tooltip := mp_bar._make_custom_tooltip(mp_bar.tooltip_text) as PanelContainer
	var exp_tooltip := exp_bar._make_custom_tooltip(exp_bar.tooltip_text) as PanelContainer
	add_child(hp_tooltip)
	add_child(mp_tooltip)
	add_child(exp_tooltip)
	var hp_label := hp_tooltip.get_child(0) as Label
	var mp_label := mp_tooltip.get_child(0) as Label
	var exp_label := exp_tooltip.get_child(0) as Label
	_check(hp_label.text.contains("%d / %d" % [int(GameState.player.hp), GameState.max_hp()]), "初始血量提示正确")
	_check(mp_label.text.contains("%d / %d" % [int(GameState.player.mp), GameState.max_mp()]), "初始法力提示正确")
	_check(exp_label.text == "%d / %d" % [int(GameState.player.xp), GameState.xp_to_next(int(GameState.player.level))], "初始经验提示正确")
	GameState.damage_player(7)
	_check(hp_label.text.contains("%d / %d" % [int(GameState.player.hp), GameState.max_hp()]), "受伤时已打开的血量提示更新")
	GameState.heal_player(3)
	_check(hp_label.text.contains("%d / %d" % [int(GameState.player.hp), GameState.max_hp()]), "回血时已打开的血量提示更新")
	_check(GameState.spend_mp(5), "测试角色可以消耗法力")
	_check(mp_label.text.contains("%d / %d" % [int(GameState.player.mp), GameState.max_mp()]), "耗蓝时已打开的法力提示更新")
	GameState.restore_mp(2)
	_check(mp_label.text.contains("%d / %d" % [int(GameState.player.mp), GameState.max_mp()]), "回蓝时已打开的法力提示更新")
	GameState.add_xp(13)
	_check(exp_label.text == "%d / %d" % [int(GameState.player.xp), GameState.xp_to_next(int(GameState.player.level))], "获得经验时已打开的提示更新")
	GameState.add_xp(GameState.xp_to_next(int(GameState.player.level)))
	_check(exp_label.text == "%d / %d" % [int(GameState.player.xp), GameState.xp_to_next(int(GameState.player.level))], "升级后已打开的经验提示更新当前值与上限")
	hp_tooltip.queue_free()
	mp_tooltip.queue_free()
	exp_tooltip.queue_free()
	await get_tree().process_frame
	GameState.heal_player(1)
	GameState.restore_mp(1)
	GameState.add_xp(1)
	var reopened_exp_tooltip := exp_bar._make_custom_tooltip(exp_bar.tooltip_text) as PanelContainer
	add_child(reopened_exp_tooltip)
	var reopened_exp_label := reopened_exp_tooltip.get_child(0) as Label
	_check(reopened_exp_label.text == "%d / %d" % [int(GameState.player.xp), GameState.xp_to_next(int(GameState.player.level))], "重新悬停时经验提示仍显示最新数字")
	reopened_exp_tooltip.queue_free()
	if failures.is_empty():
		print("HudLiveTooltipTest: PASS")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		get_tree().quit(1)

## 汇总断言，确保任一失败都会令隔离测试以非零状态结束。
func _check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
