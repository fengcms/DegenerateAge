extends Node
## HUD 血蓝提示回归：在提示持续打开时，通过真实角色数值事件检查文字即时变化。
## 在隔离测试项目中运行，不读写玩家正式存档，也不验证窗口管理器的视觉放置。

var failures: Array[String] = []

## 装配正式 HUD 后持续保留两种提示，分别验证扣除和恢复均无需移开鼠标。
func _ready() -> void:
	GameState.reset_to_defaults()
	GameState.menu_mode = "world"
	var main := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(main)
	await get_tree().process_frame
	var hp_bar := main.get_node("UI/Hud/StatusPanel/HpBar") as HudStatusBar
	var mp_bar := main.get_node("UI/Hud/StatusPanel/MpBar") as HudStatusBar
	var hp_tooltip := hp_bar._make_custom_tooltip(hp_bar.tooltip_text) as PanelContainer
	var mp_tooltip := mp_bar._make_custom_tooltip(mp_bar.tooltip_text) as PanelContainer
	add_child(hp_tooltip)
	add_child(mp_tooltip)
	var hp_label := hp_tooltip.get_child(0) as Label
	var mp_label := mp_tooltip.get_child(0) as Label
	_check(hp_label.text.contains("%d / %d" % [int(GameState.player.hp), GameState.max_hp()]), "初始血量提示正确")
	_check(mp_label.text.contains("%d / %d" % [int(GameState.player.mp), GameState.max_mp()]), "初始法力提示正确")
	GameState.damage_player(7)
	_check(hp_label.text.contains("%d / %d" % [int(GameState.player.hp), GameState.max_hp()]), "受伤时已打开的血量提示更新")
	GameState.heal_player(3)
	_check(hp_label.text.contains("%d / %d" % [int(GameState.player.hp), GameState.max_hp()]), "回血时已打开的血量提示更新")
	_check(GameState.spend_mp(5), "测试角色可以消耗法力")
	_check(mp_label.text.contains("%d / %d" % [int(GameState.player.mp), GameState.max_mp()]), "耗蓝时已打开的法力提示更新")
	GameState.restore_mp(2)
	_check(mp_label.text.contains("%d / %d" % [int(GameState.player.mp), GameState.max_mp()]), "回蓝时已打开的法力提示更新")
	hp_tooltip.queue_free()
	mp_tooltip.queue_free()
	await get_tree().process_frame
	GameState.heal_player(1)
	GameState.restore_mp(1)
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
