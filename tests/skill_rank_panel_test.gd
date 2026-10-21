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
	first_row.grab_focus()
	_check(panel._focus_tooltip != null and panel._focus_tooltip.skill_id == "earth_cleave",
		"键盘聚焦技能行时显示同一张详情卡")
	source_icon.grab_focus()
	_check(panel._focus_tooltip != null and panel._focus_tooltip.skill_id == "earth_cleave",
		"键盘聚焦技能图标时详情不中断")
	source_icon.release_focus()
	_check(panel._focus_tooltip == null, "键盘焦点离开后释放临时详情卡")
	var summary := first_row.get_child(1) as Label
	var tooltip := source_icon._make_custom_tooltip(source_icon.tooltip_text) as SkillDetailTooltip
	add_child(tooltip)
	_check(summary.text.contains("1/5") and not summary.text.contains("下阶")
		and tooltip._next.text.contains("下阶") and tooltip._next.text.contains("1500"),
		"紧凑行卡仅保留阶数，效果和价格进入结构化浮层")
	_check(tooltip._cooldown.text.contains("基础冷却 4.0")
		and tooltip._cooldown.text.contains("%.1f" % GameState.cooldown_after_cdr(4.0)),
		"浮层分别说明基础冷却与当前属性下次施放冷却")
	var player := get_tree().get_first_node_in_group("player") as PlayerCharacter
	GameState.skill_cooldowns["earth_cleave"] = 2.8
	panel._refresh_cooldowns()
	tooltip._refresh_live()
	_check(player != null and tooltip._remaining.visible and tooltip._remaining.text.contains("2.8")
		and (source_icon.get_node("CooldownOverlay") as Label).text == "3s",
		"运行中冷却取同一状态；浮层保留一位小数，图标秒数向上取整")
	GameState.skill_cooldowns["earth_cleave"] = 0.0
	panel._refresh_cooldowns()
	tooltip._refresh_live()
	_check(not tooltip._remaining.visible and (source_icon.get_node("CooldownOverlay") as Label).text.is_empty(),
		"冷却归零后两处倒计时同步消失")
	GameState.active_buffs["battle_focus"] = {"remaining": 3.3, "effects": {"attackSpeedPct": 0.15}}
	GameState.skill_cooldowns["battle_focus"] = 7.0
	var focus_tip := SkillDetailTooltip.for_skill("battle_focus")
	add_child(focus_tip)
	panel._refresh_cooldowns()
	_check(focus_tip._remaining.visible and focus_tip._remaining.text.contains("增益剩余")
		and (panel._cooldown_labels["battle_focus"] as Label).text == "7s"
		and panel._basic_interval_label.text.contains("%.1f" % player.effective_attack_interval()),
		"战意浮层同时报告增益和冷却，普攻间隔跟随攻速")
	remove_child(focus_tip)
	focus_tip.free()
	GameState.active_buffs.erase("battle_focus")
	GameState.skill_cooldowns["battle_focus"] = 0.0
	remove_child(tooltip)
	tooltip.free()
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
	var updated_tooltip := updated_icon._make_custom_tooltip(updated_icon.tooltip_text) as SkillDetailTooltip
	add_child(updated_tooltip)
	_check(updated_summary.text.contains("2/5") and updated_tooltip._effect.text.contains("1.44"),
		"购买后阶数更新且悬停说明给出 2 阶实际系数")
	remove_child(updated_tooltip)
	updated_tooltip.free()
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
		"200%% 界面和文字下技能面板完整落在逻辑视口：%s / %s" % [box.get_global_rect(), logical])
	var scroll := panel._center.content_scroll as ScrollContainer
	_check(scroll != null and scroll.size.y > 0 and scroll.get_child(0).get_combined_minimum_size().y > scroll.size.y,
		"200% 极端倍率下内容应留在可滚动区，而非撑出屏幕")
	var large_tip := updated_icon._make_custom_tooltip(updated_icon.tooltip_text) as SkillDetailTooltip
	add_child(large_tip)
	await get_tree().process_frame
	var tip_size := large_tip.get_combined_minimum_size()
	_check(large_tip._description.get_theme_font_size("font_size") >= 30
		and tip_size.x <= logical.x and tip_size.y >= 100.0 and tip_size.y <= logical.y * 0.7,
		"200%% 文字倍率下浮层字号放大且外框不超逻辑视口：%s / %s" % [tip_size, logical])
	remove_child(large_tip)
	large_tip.free()
	updated_row.grab_focus()
	var keyboard_tip: SkillDetailTooltip = panel._focus_tooltip
	var focus_rect := keyboard_tip.get_global_rect() if keyboard_tip != null else Rect2()
	_check(keyboard_tip != null and keyboard_tip.position.x >= 0.0 and keyboard_tip.position.y >= 0.0
		and keyboard_tip.position.x + keyboard_tip.size.x <= logical.x + 1.0
		and keyboard_tip.position.y + keyboard_tip.size.y <= logical.y + 1.0,
		"200%% 下键盘焦点卡片保持在逻辑视口内：%s / %s" % [focus_rect, logical])
	updated_row.release_focus()
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
