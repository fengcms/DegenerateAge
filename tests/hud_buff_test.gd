extends Node
## 法师魔法盾与武士战意的 HUD 可见性及活动效果提示回归。

var _failures: Array[String] = []

func _ready() -> void:
	GameState.reset_to_defaults("mage")
	GameState.player.level = 15
	var hud := (load("res://scenes/ui/Hud.tscn") as PackedScene).instantiate()
	add_child(hud)
	_check(not hud._shield_icon.visible, "未开盾时不显示魔法盾图标")
	_check(GameState.start_buff("magic_shield"), "法师能启动魔法盾")
	hud._refresh_buff_icons()
	_check(hud._shield_icon.visible and not hud._focus_icon.visible, "魔法盾图标独立于战意觉醒显示")
	_check(hud._shield_icon.tooltip_text.contains("30.0") and hud._shield_icon.tooltip_text.contains("35%"),
		"图标提示显示剩余时间和本次盾的效果")
	GameState.current_map = "camp"
	hud._refresh_buff_icons()
	_check(hud._shield_icon.visible, "切图保留盾时图标仍可见")
	GameState.skill_ranks["magic_shield"] = 5
	hud._refresh_buff_icons()
	_check(hud._shield_icon.tooltip_text.contains("35%"), "升级技能不会改写已施放盾的提示快照")
	GameState.tick_buffs(2.0)
	hud._refresh_buff_icons()
	_check(hud._shield_icon.tooltip_text.contains("28.0"), "盾计时推进后提示同步更新")
	_check(GameState.start_buff("magic_shield"), "刷新盾时替换效果快照")
	hud._refresh_buff_icons()
	_check(hud._shield_icon.tooltip_text.contains("47%"), "刷新后提示使用新阶效果")
	GameState.tick_buffs(31.0)
	hud._refresh_buff_icons()
	_check(not hud._shield_icon.visible, "魔法盾到期隐藏图标")
	GameState.reset_to_defaults("warrior")
	GameState.player.level = 15
	_check(GameState.start_buff("battle_focus"), "武士能启动战意觉醒")
	hud._refresh_buff_icons()
	_check(hud._focus_icon.visible and not hud._shield_icon.visible, "武士原有战意图标仍显示")
	hud.queue_free()
	GameState.reset_to_defaults()
	if _failures.is_empty():
		print("[HudBuffTest] 全部通过 ✅")
		get_tree().quit(0)
	else:
		get_tree().quit(1)

func _check(ok: bool, reason: String) -> void:
	if not ok:
		_failures.append(reason)
		push_error("[HudBuffTest] " + reason)
