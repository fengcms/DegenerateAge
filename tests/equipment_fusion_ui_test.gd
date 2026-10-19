extends Node
## 铁匠菜单至共用合成窗口的接线、确认行为与 200% 窗口边界测试。

var failures: Array[String] = []

## 在隔离场景创建真实菜单与窗口，选择四件材料完成一次合成。
func _ready() -> void:
	GameState.reset_to_defaults()
	var rng := RandomNumberGenerator.new()
	rng.seed = 425
	for i in range(4):
		GameState.inventory[i] = ItemFactory.make_equip_roll("c6_equip_weapon", 51, "epic", rng)
	var dialogue := preload("res://scenes/ui/BlacksmithPanel.tscn").instantiate()
	var bag := preload("res://scenes/ui/InventoryPanel.tscn").instantiate()
	var panel := preload("res://scenes/ui/EquipmentFusionPanel.tscn").instantiate()
	add_child(dialogue)
	add_child(bag)
	add_child(panel)
	EventBus.blacksmith_panel_requested.emit("铁匠", "试试新服务")
	dialogue._show_menu()
	check(dialogue._fusion_buttons.size() == 3 and dialogue._upgrade.visible and dialogue._reforge.visible,
		"铁匠对话提供三种合成及原有升星、重铸")
	GameState.settings.uiScale = 2.0
	dialogue._resize()
	await get_tree().process_frame
	check(dialogue._root.size.y <= dialogue._center.size.y + 1.0,
		"200% 界面倍率下铁匠菜单保持在逻辑视口内")
	dialogue._open_fusion(EquipmentFusion.GOLD_TO_PURPLE)
	check(panel.visible and not dialogue.visible, "铁匠菜单可打开四金合紫窗口")
	check(bag.visible and GameState.npc_dialog_open(), "合成会话并开背包并暂停自动战斗")
	for i in range(4):
		panel._pickers[i].select(i + 1)
		panel._on_item_selected(i + 1, i)
	check(not panel._confirm.disabled and panel._summary.text.contains("51—60"),
		"材料选齐显示输出最低档并允许确认")
	panel._resize()
	await get_tree().process_frame
	panel._resize()
	check(panel._box.size.x <= panel._center.size.x + 1.0
		and panel._box.size.y <= panel._center.size.y + 1.0,
		"200% 界面倍率下合成窗口保持在逻辑视口内")
	panel._on_confirm()
	check(GameState.inventory_used() == 1 and GameState.inventory[0] is Dictionary
		and String(GameState.inventory[0].get("quality", "")) == "legendary",
		"点击确认只产一件紫装并消耗四件金装")
	panel.set_open(false)
	check(bag.visible and not GameState.npc_dialog_open(), "关闭合成窗保留背包并结束 NPC 会话")
	bag.set_open(false)
	GameState.reset_to_defaults()
	for i in range(4):
		GameState.inventory[i] = ItemFactory.make_equip_dynamic("c6_equip_ring", 61, "legendary", rng)
	panel._on_requested(EquipmentFusion.PURPLE_TARGET)
	for i in range(4):
		panel._pickers[i].select(i + 1)
		panel._on_item_selected(i + 1, i)
	panel._target.select(1)
	panel._refresh_preview()
	check(not panel._confirm.disabled, "四紫同档并选目标类型后可确认")
	panel._on_confirm()
	check(GameState.inventory_used() == 1 and Equipment.item_kind(GameState.inventory[0]) == "weapon",
		"四紫界面可产出指定武器")
	panel.set_open(false)
	GameState.reset_to_defaults()
	var old := ItemFactory.make_equip_roll("c6_equip_weapon", 51, "legendary", rng)
	old.star = 12
	GameState.inventory[0] = old
	GameState.inventory[1] = ItemFactory.make_equip_dynamic("c6_equip_weapon", 61, "legendary", rng)
	GameState.gold = EquipmentFusion.full_star_cost()
	panel._on_requested(EquipmentFusion.STAR_TRANSFER)
	panel._pickers[0].select(1)
	panel._on_item_selected(1, 0)
	panel._pickers[1].select(1)
	panel._on_item_selected(1, 1)
	check(not panel._confirm.disabled and panel._summary.text.contains("128747"),
		"保星面板显示现行全部成功费用")
	panel._on_confirm()
	check(GameState.inventory_used() == 2 and GameState.gold == EquipmentFusion.full_star_cost(),
		"保星第一次确认仅显示随机词条风险，不扣材料")
	panel._on_confirm()
	check(GameState.inventory_used() == 1 and GameState.gold == 0
		and int(GameState.inventory[0].get("star", -1)) == 12,
		"保星再次确认产出新档 12 星紫装")
	if failures.is_empty():
		print("[EquipmentFusionUiTest] 全部通过 ✅")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	get_tree().quit(0 if failures.is_empty() else 1)

## 记录界面断言错误并在末尾统一结束测试。
func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
