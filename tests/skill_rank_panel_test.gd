extends Node
## 技能面板升阶回归：检查金币/等级灰态、真实购买、属性对比与快捷栏阶数提示。
## 装配正式主场景，不写正式玩家存档。

var _failures: Array[String] = []

## 在真实技能面板购买裂地斩 2 阶，并验证其余操作不受影响。
func _ready() -> void:
	GameState.reset_to_defaults()
	GameState.menu_mode = "world"
	GameState.player.level = 15
	GameState.gold = 1499
	var main := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(main)
	await get_tree().process_frame
	var panel := main.get_node("UI/SkillPanel") as Control
	var hud := main.get_node("UI/Hud") as Control
	panel.set_open(true)
	var upgrade := panel._upgrade_buttons.get("earth_cleave") as Button
	_check(upgrade != null and upgrade.disabled and upgrade.tooltip_text.contains("金币"),
		"金币不足时按钮置灰并解释原因")
	GameState.gold = 1500
	EventBus.gold_changed.emit(GameState.gold)
	_check(not upgrade.disabled, "金币达到价格后不重建列表即可点亮按钮")
	var first_row: Control = panel._list.get_child(1)
	var source_icon := first_row.get_child(0) as SkillDragButton
	_check(source_icon.skill_id == "earth_cleave" and not source_icon.disabled,
		"升阶按钮不破坏原有拖放图标")
	var summary := first_row.get_child(1) as Label
	_check(summary.text.contains("1/5") and not summary.text.contains("下阶")
		and source_icon.tooltip_text.contains("下阶") and source_icon.tooltip_text.contains("1500"),
		"紧凑行卡仅保留阶数，效果和价格进入悬停提示")
	_check((first_row.get_child(2) as Label).text.contains("CD 4"), "行卡显示基础冷却")
	upgrade.pressed.emit()
	_check(GameState.skill_rank("earth_cleave") == 2 and GameState.gold == 0,
		"面板升级按钮调用真实购买入口")
	var next_button := panel._upgrade_buttons.get("earth_cleave") as Button
	_check(next_button != null and next_button.disabled and next_button.tooltip_text.contains("Lv25"),
		"购买后刷新为下一阶等级门槛")
	var updated_row: Control = panel._list.get_child(1)
	var updated_summary := updated_row.get_child(1) as Label
	var updated_icon := updated_row.get_child(0) as SkillDragButton
	_check(updated_summary.text.contains("2/5") and updated_icon.tooltip_text.contains("1.44"),
		"购买后阶数更新且悬停说明给出 2 阶实际系数")
	GameState.set_hotbar_entry(4, {"kind": "skill", "id": "earth_cleave"})
	var hotbar_tip := (hud._hotbar_buttons[4] as HotbarSlot).tooltip_text
	_check(hotbar_tip.contains("2 阶"),
		"快捷栏绑定不变且悬停提示显示当前阶数，实际：%s" % hotbar_tip)
	# 极端倍率下技能行可滚动，标题与购买入口仍留在逻辑视口内。
	var ui := main.get_node("UI") as CanvasLayer
	GameState.settings["uiScale"] = 2.0
	GameState.settings["textScale"] = 2.0
	SettingsRuntime.apply_ui_scale_to(ui)
	SettingsRuntime.apply_text_scale_to(ui)
	EventBus.settings_changed.emit()
	await get_tree().process_frame
	panel._center._layout()
	await get_tree().process_frame
	var box := panel._center.panel_box as Control
	var logical: Vector2 = panel._center.layout_space()
	_check(box.global_position.x >= -1 and box.global_position.y >= -1
		and box.global_position.x + box.size.x <= logical.x + 1
		and box.global_position.y + box.size.y <= logical.y + 1,
		"200% 界面和文字下技能面板完整落在逻辑视口：%s / %s" % [box.get_global_rect(), logical])
	var scroll := panel._center.content_scroll as ScrollContainer
	_check(scroll != null and scroll.size.y > 0 and scroll.get_child(0).get_combined_minimum_size().y > scroll.size.y,
		"200% 极端倍率下内容应留在可滚动区，而非撑出屏幕")
	panel.set_open(false)
	if _failures.is_empty():
		print("SkillRankPanelTest: PASS")
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		get_tree().quit(1)

## 累积面板断言失败，避免一处文字问题遮蔽购买问题。
func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures.append(label)
