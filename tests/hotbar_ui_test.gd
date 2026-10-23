extends Node
## M4-8 拖放契约；不写玩家存档。

var _errors: Array[String] = []

func _ready() -> void:
	GameState.reset_to_defaults()
	var main := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(main)
	var inventory: Control = main.get_node("UI/InventoryPanel")
	var hud: Control = main.get_node("UI/Hud")
	GameState.inventory[0] = {"kind": "potion", "itemId": "potion_hp_small", "count": 4}
	GameState.inventory[1] = {"kind": "misc", "itemId": "misc_town_scroll", "count": 2}
	EventBus.inventory_changed.emit()
	inventory.set_open(true)
	_check(hud._hotbar.z_index == 100, "背包打开时快捷栏可接收拖放")
	for _i in range(3):
		await get_tree().process_frame
	var from: Vector2 = inventory._bag_buttons[0].get_global_rect().get_center()
	var to: Vector2 = hud._hotbar_buttons[7].get_global_rect().get_center()
	await _drag_real(from, to)
	_check(GameState.hotbar[7] is Dictionary and GameState.hotbar[7].id == "potion_hp_small",
		"真实鼠标拖拽从背包落到快捷格")
	# 工程 71 §2.2 实证：拖放**落到已绑定药品的格子**时只应替换绑定，不得顺带触发一次点击把药吃掉。
	# 目标格 hotbar[0] 默认绑的是自动红药，若拖放真会发出 pressed，这里就会消耗库存并让下一条断言变红。
	GameState.player.hp = GameState.max_hp() - 50
	var stock_before := int(GameState.inventory[0].count)
	await _drag_real(inventory._bag_buttons[0].get_global_rect().get_center(),
		hud._hotbar_buttons[0].get_global_rect().get_center())
	_check(GameState.hotbar[0] is Dictionary and GameState.hotbar[0].id == "potion_hp_small",
		"拖放落到已绑定药品的格子应完成替换绑定")
	_check(int(GameState.inventory[0].count) == stock_before,
		"拖放替换绑定不得顺带消耗药品（拖放不产生 pressed）")
	inventory.set_open(false)
	var skills: Control = main.get_node("UI/SkillPanel")
	skills.set_open(true)
	for _i in range(2):
		await get_tree().process_frame
	var skill_button: Control = skills._list.get_child(0).get_child(0)
	from = skill_button.get_global_rect().get_center()
	to = hud._hotbar_buttons[8].get_global_rect().get_center()
	await _drag_real(from, to)
	_check(GameState.hotbar[8] is Dictionary and GameState.hotbar[8].id == "basic_slash",
		"真实鼠标拖拽从技能面板落到快捷格")
	skills.set_open(false)
	inventory.set_open(true)
	var bag_slot: ItemSlot = inventory._bag_buttons[0]
	_check(bag_slot.draggable, "药品背包格可拖动")
	var payload: Variant = bag_slot._get_drag_data(Vector2.ZERO)
	var target: HotbarSlot = hud._hotbar_buttons[4]
	_check(target._can_drop_data(Vector2.ZERO, payload), "快捷格接受背包药品")
	target._drop_data(Vector2.ZERO, payload)
	_check(GameState.hotbar[4].id == "potion_hp_small" and GameState.inventory[0].count == 4,
		"拖入绑定模板而不取走背包物品")
	var town: ItemSlot = inventory._bag_buttons[1]
	_check(town.draggable, "回城卷可拖动")
	hud._hotbar_buttons[5]._drop_data(Vector2.ZERO, town._get_drag_data(Vector2.ZERO))
	_check(GameState.hotbar[5].id == "misc_town_scroll", "回城卷绑定成功")
	var source: HotbarSlot = hud._hotbar_buttons[4]
	target = hud._hotbar_buttons[5]
	target._drop_data(Vector2.ZERO, source._get_drag_data(Vector2.ZERO))
	_check(GameState.hotbar[4].id == "misc_town_scroll" and GameState.hotbar[5].id == "potion_hp_small", "两格拖放交换")
	hud._hotbar_buttons[6]._drop_data(Vector2.ZERO, {"kind": "hotbar_skill", "id": "basic_slash"})
	_check(GameState.hotbar[6].id == "basic_slash", "已接通技能可拖入")
	_check(hud._hotbar_buttons[6]._can_drop_data(Vector2.ZERO, {"kind": "hotbar_skill", "id": "earth_cleave"}),
		"裂地斩接通后可拖入")
	_check(hud._hotbar_buttons[6]._can_drop_data(Vector2.ZERO, {"kind": "hotbar_skill", "id": "whirlwind"}),
		"旋风斩接通后可拖入")
	_check(hud._hotbar_buttons[6]._can_drop_data(Vector2.ZERO, {"kind": "hotbar_skill", "id": "battle_focus"}),
		"战意觉醒接通后可拖入")
	_check(hud._hotbar_buttons[6]._can_drop_data(Vector2.ZERO, {"kind": "hotbar_skill", "id": "armor_break"}),
		"破甲重击接通后可拖入")
	_check(hud._hotbar_buttons[6]._can_drop_data(Vector2.ZERO, {"kind": "hotbar_skill", "id": "spirit_storm"}),
		"灵刃风暴接通后可拖入")
	_check(HotbarConfig.ACTIVE_SKILLS.size() == 12,
		"可装备技能共 12 条（两职业各 6），与 skills.json 全量一致（无未接线残留）")
	# 工程 98：单职业视角必须各自 6 条且互不串味 —— 只断并集大小会漏掉
	# 「法师技能混进武士快捷栏」这类错误（并集仍然是 12）。
	_check(HotbarConfig.active_skills("warrior").size() == 6, "武士应 6 条技能（含普攻）")
	_check(HotbarConfig.active_skills("mage").size() == 6, "法师应 6 条技能（含普攻）")
	_check(not HotbarConfig.usable_skill("meteor", "warrior"), "武士不得使用法师的陨石术")
	_check(not HotbarConfig.usable_skill("spirit_storm", "mage"), "法师不得使用武士的灵刃风暴")
	var right := InputEventMouseButton.new()
	right.position = hud._hotbar_buttons[6].get_global_rect().get_center()
	right.global_position = right.position
	right.button_index = MOUSE_BUTTON_RIGHT
	right.button_mask = MOUSE_BUTTON_MASK_RIGHT
	right.pressed = true
	get_viewport().push_input(right, true)
	await get_tree().process_frame
	_check(GameState.hotbar[6] == null, "右键清空绑定")
	# 永久来源：清掉默认自动药项后，仍可从技能面板重新绑定。
	skills.set_open(true)
	var source_red: SkillDragButton = skills._potion_buttons["red"]
	var source_blue: SkillDragButton = skills._potion_buttons["blue"]
	GameState.set_hotbar_entry(0, null)
	GameState.set_hotbar_entry(1, null)
	var red_payload: Dictionary = source_red._get_drag_data(Vector2.ZERO)
	var blue_payload: Dictionary = source_blue._get_drag_data(Vector2.ZERO)
	_check(hud._hotbar_buttons[0]._can_drop_data(Vector2.ZERO, red_payload), "自动红药可重新拖入")
	_check(hud._hotbar_buttons[1]._can_drop_data(Vector2.ZERO, blue_payload), "自动蓝药可重新拖入")
	hud._hotbar_buttons[0]._drop_data(Vector2.ZERO, red_payload)
	hud._hotbar_buttons[1]._drop_data(Vector2.ZERO, blue_payload)
	_check(GameState.hotbar[0] == {"kind": "auto_potion", "id": "red"} and
		GameState.hotbar[1] == {"kind": "auto_potion", "id": "blue"}, "清空后两种自动药都能恢复")
	skills.set_open(false)
	GameState.inventory[0] = null
	EventBus.inventory_changed.emit()
	_check(GameState.hotbar[5].id == "potion_hp_small" and is_equal_approx(hud._hotbar_buttons[5].modulate.a, 0.45),
		"药品耗尽绑定保留且置灰")
	GameState.inventory[8] = {"kind": "potion", "itemId": "potion_hp_small", "count": 3}
	EventBus.inventory_changed.emit()
	_check(hud._hotbar_buttons[5]._count.text == "3" and is_equal_approx(hud._hotbar_buttons[5].modulate.a, 1.0),
		"补货后显示数量并恢复可用")
	GameState.organize_inventory()
	_check(GameState.hotbar[5].id == "potion_hp_small" and hud._hotbar_buttons[5]._count.text == "3",
		"背包整理不破坏模板绑定")
	inventory.set_open(false)
	GameState.player.hp = GameState.max_hp() - 50
	hud._activate_hotbar(5)
	await get_tree().process_frame
	_check(GameState.player.hp == GameState.max_hp() and hud._hotbar_buttons[5]._count.text == "2",
		"拖入的具体药品可使用且库存同步减少")
	_check(not hud._hotbar_buttons[5]._cooldown.text.is_empty(), "药品格显示冷却")
	# 冷却秒数压在图标上，须带深色描边才可辨识（与键位角标同一处理）。
	_check(hud._hotbar_buttons[5]._cooldown.get_theme_constant("outline_size") > 0
		and hud._hotbar_buttons[5]._cooldown.get_theme_color("font_outline_color").a > 0.5,
		"冷却秒数带深色描边便于辨识")
	_check(is_equal_approx(hud._hotbar.size.x, hud._exp_bar.size.x), "经验条与快捷栏整体同宽")
	_check(absf(hud._exp_bar.position.y - (hud._hotbar.position.y + hud._hotbar.size.y) - 7.0) < 0.1,
		"经验槽距快捷栏 7px，与设计稿一致")
	var separator := hud._hotbar.get_node("GroupGap/DiamondSeparator") as TextureRect
	_check(separator != null and separator.texture != null, "操作格与固定入口之间保留菱形区隔符")
	var key_badge := hud._hotbar_buttons[0].get_node("KeyBadge") as Panel
	_check(key_badge.get_theme_stylebox("panel") is StyleBoxEmpty and
		(key_badge.get_node("KeyText") as Label).get_theme_constant("outline_size") > 0,
		"键位文字使用描边而非黑色底牌")
	hud._on_xp(45, 100)
	var fill := hud._exp_bar.get_node("ExperienceFill") as TextureRect
	var frame := hud._exp_bar.get_node("ExperienceFrame") as TextureRect
	_check(fill.get_index() < frame.get_index() and frame.get_index() < hud._exp_bar.get_node("ProgressTip").get_index()
		and absf(fill.size.x - 696.0 * 0.45) < 0.1, "经验填充在边框后方并按进度裁切")
	var tip := hud._exp_bar.get_node("ProgressTip") as TextureRect
	_check(tip.visible and absf(tip.position.x - 318.0) < 2.0 and hud._exp_bar.tooltip_text == "45 / 100",
		"经验填充端点随进度移动，精确数值只在悬停显示")
	SettingsRuntime.set_binding("panel_character", KEY_F1)
	SettingsRuntime.set_binding("hotbar_1", KEY_F2)
	_check((hud._panel_buttons[0].get_node("KeyBadge/KeyText") as Label).text == "F1" and
		(hud._hotbar_buttons[0].get_node("KeyBadge/KeyText") as Label).text == "F2",
		"改键后固定入口与操作格角标同步更新")
	GameState.settings.uiScale = 2.0
	SettingsRuntime.apply_ui_scale_to(main.get_node("UI"))
	await get_tree().process_frame
	_check(hud._hotbar.scale.x < 1.0 and hud._hotbar.scale.is_equal_approx(hud._exp_bar.scale),
		"窄逻辑画布下快捷栏与经验条同步缩放")
	print("[HotbarUiTest] ", "全部通过 ✅" if _errors.is_empty() else str(_errors))
	get_tree().quit(0 if _errors.is_empty() else 1)

func _check(ok: bool, message: String) -> void:
	if not ok:
		_errors.append(message)
		push_error("[HotbarUiTest] " + message)

func _send_mouse(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	get_viewport().push_input(event, true)

func _send_move(point: Vector2, relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.relative = relative
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(event, true)

## 真实鼠标拖放：按下 → 分 8 步移动到目标 → 松开（与原内联写法同一路径）。
func _drag_real(from: Vector2, to: Vector2) -> void:
	_send_move(from, Vector2.ZERO)
	await get_tree().process_frame
	_send_mouse(from, true)
	await get_tree().process_frame
	var previous := from
	for step in range(1, 9):
		var point: Vector2 = from.lerp(to, float(step) / 8.0)
		_send_move(point, point - previous)
		previous = point
		await get_tree().process_frame
	_send_mouse(to, false)
	await get_tree().process_frame
