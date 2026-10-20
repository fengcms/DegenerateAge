extends Node
## 铁匠双面板、材料拖放、随机预选、保星确认和 200% 窄窗口验收。

var failures: Array[String] = []

## 通过真实背包格载荷模拟拖放，全程使用隔离游戏状态。
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
	check(dialogue._fusion_buttons.size() == 3, "铁匠菜单保留三种服务")
	check(dialogue._leave.get_parent() == dialogue._footer
		and not dialogue._service_scroll.is_ancestor_of(dialogue._leave),
		"离开按钮在底部固定行，不再混进服务网格")
	check(dialogue._service_grids.size() == 2 and dialogue._service_grids.all(
		func(grid: GridContainer) -> bool: return grid.get_child_count() % 2 == 0),
		"两组服务网格各自成对，没有孤格")
	GameState.settings.uiScale = 1.0
	dialogue._resize()
	await get_tree().process_frame
	check(not dialogue._service_scroll.get_v_scroll_bar().visible, "100% 缩放下服务说明无需滚动")
	GameState.settings.uiScale = 2.0
	dialogue._resize()
	await get_tree().process_frame
	check(dialogue._root.size.y <= dialogue._center.size.y + 1.0, "200% 铁匠菜单可见")
	dialogue._open_fusion(EquipmentFusion.GOLD_TO_PURPLE)
	await get_tree().process_frame
	panel._resize()
	check(panel.visible and bag.visible and GameState.npc_dialog_open(), "合成与背包并开并暂停自动战斗")
	var logical: Vector2 = panel.get_viewport_rect().size / SettingsRuntime.ui_scale_value()
	check(panel._center.position.x >= 0.0 and panel._center.position.y >= 0.0
		and panel._center.position.y + panel._center.size.y <= logical.y + 1.0
		and panel._box.size.y <= panel._center.size.y + 1.0,
		"200% 逻辑视口内保留完整合成区域")
	var first: Dictionary = GameState.inventory[0].duplicate(true)
	panel._on_material_dropped(0, _payload(0))
	check(GameState.inventory[0] == first and not panel._selected[0].is_empty()
		and bag._bag_buttons[0].fusion_selected, "拖入格子只预选装备并标记原背包格")
	panel._on_material_dropped(1, _payload(0))
	check(panel._selected[1].is_empty(), "同一装备不能重复放入两格")
	panel._clear_material(0)
	check(panel._selected[0].is_empty() and GameState.inventory[0] == first, "撤下材料不改变背包")
	var gap: Vector2 = panel._slots[0].position + panel._slots[0].size + Vector2(3, 3)
	var gap_target: int = panel._grid.slot_at(gap)
	panel._grid._drop_data(gap, _payload(0))
	check(gap_target >= 0 and String(panel._selected[gap_target].get("instanceId", "")) == String(first.instanceId),
		"投在格间空白也会预选最近的材料格")
	GameState.inventory[0].star = 1
	EventBus.inventory_changed.emit()
	check(panel._selected[gap_target].is_empty(), "背包装备属性变化使旧预选自动失效")
	GameState.inventory[0].star = 0
	EventBus.inventory_changed.emit()
	panel._clear_material(gap_target)
	panel._on_random_fill()
	check(panel._material_snapshots().size() == 4 and not panel._confirm.disabled
		and panel._summary.text.contains("51—60"), "随机放入四件同档材料可预览合成")
	GameState.organize_inventory()
	check(panel._material_snapshots().size() == 4 and not panel._confirm.disabled,
		"背包整理只改变下标时保留材料预选")
	GameState.settings.uiScale = 1.0
	panel._resize()
	await get_tree().process_frame
	panel._resize()
	check(bag._center.position.x + bag._center.size.x <= panel._center.position.x + 1.0,
		"宽视口下背包与合成面板并排且不重叠")
	panel._on_confirm()
	check(GameState.inventory_used() == 1 and String(_only_item().get("quality", "")) == "legendary",
		"合成确认仅产一件紫装")
	panel.set_open(false)
	check(bag.visible and not GameState.npc_dialog_open(), "关闭工作台保留背包并结束 NPC 会话")
	panel._on_requested(EquipmentFusion.GOLD_TO_PURPLE)
	bag.set_open(false)
	check(not panel.visible, "关闭会话中的背包也关闭合成工作台")
	GameState.reset_to_defaults()
	for i in range(4):
		GameState.inventory[i] = ItemFactory.make_equip_dynamic("c6_equip_ring", 61, "legendary", rng)
	panel._on_requested(EquipmentFusion.PURPLE_TARGET)
	GameState.inventory[0].star = 12
	panel._on_material_dropped(0, _payload(0))
	check(panel._selected[0].is_empty(), "12 星紫装不能手动拖进四紫定向格")
	GameState.inventory[0].star = 0
	EventBus.inventory_changed.emit()
	panel._on_random_fill()
	panel._target.select(1)
	panel._refresh_preview()
	check(panel._material_snapshots().size() == 4 and not panel._confirm.disabled,
		"四紫随机放入后可选择目标类型")
	panel._on_confirm()
	var purple_output := _only_item()
	check(GameState.inventory_used() == 1 and not purple_output.is_empty()
		and Equipment.item_kind(purple_output) == "weapon",
		"四紫界面产出指定武器")
	panel.set_open(false)
	bag.set_open(false)
	GameState.reset_to_defaults()
	var old := ItemFactory.make_equip_roll("c6_equip_weapon", 51, "legendary", rng)
	old.star = 12
	GameState.inventory[0] = old
	GameState.inventory[1] = ItemFactory.make_equip_dynamic("c6_equip_weapon", 61, "legendary", rng)
	GameState.gold = EquipmentFusion.full_star_cost()
	panel._on_requested(EquipmentFusion.STAR_TRANSFER)
	check(not panel._random.visible and not panel._slots[2].visible, "保星只显示两个材料格且无随机放入")
	panel._on_material_dropped(0, _payload(1))
	check(panel._selected[0].is_empty(), "新档 0 星装备不能放入旧档 12 星格")
	panel._on_material_dropped(0, _payload(0))
	panel._on_material_dropped(1, _payload(1))
	check(not panel._confirm.disabled and panel._summary.text.contains("128747"), "保星显示费用并允许确认")
	panel._on_confirm()
	check(GameState.inventory_used() == 2 and GameState.gold == EquipmentFusion.full_star_cost(),
		"保星第一次点击只提示词条重随机风险")
	panel._on_confirm()
	check(GameState.inventory_used() == 1 and GameState.inventory[0] is Dictionary and GameState.gold == 0
		and int(GameState.inventory[0].get("star", -1)) == 12, "保星再次确认才结算")
	# 跨档保星：51 档 12★ 升到 71 档，费用按档数翻倍，产物穿不上时明确提示。
	GameState.reset_to_defaults()
	var far_old := ItemFactory.make_equip_roll("c6_equip_weapon", 51, "legendary", rng)
	far_old.star = 12
	GameState.inventory[0] = far_old
	GameState.inventory[1] = ItemFactory.make_equip_dynamic("c6_equip_weapon", 71, "legendary", rng)
	GameState.gold = EquipmentFusion.full_star_cost() * 2
	panel._on_requested(EquipmentFusion.STAR_TRANSFER)
	panel._on_material_dropped(0, _payload(0))
	panel._on_material_dropped(1, _payload(1))
	check(not panel._confirm.disabled and panel._summary.text.contains("跨 2 档")
		and panel._summary.text.contains("257494"), "跨两档预览标明倍数与双倍费用")
	check(panel._summary.text.contains("暂时无法穿戴"), "产物高出玩家等级时提示暂时穿不上")
	panel._on_confirm()
	panel._on_confirm()
	var far_output := _only_item()
	check(GameState.inventory_used() == 1 and GameState.gold == 0
		and EquipmentFusion.tier_start(far_output) == 71 and int(far_output.get("star", 0)) == 12,
		"跨两档保星扣双倍金币并产出 71 档 12 星紫装")
	if failures.is_empty():
		print("[EquipmentFusionUiTest] 全部通过 ✅")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	get_tree().quit(0 if failures.is_empty() else 1)

## 构造与真实 ItemSlot 相同的背包拖拽载荷。
func _payload(index: int) -> Dictionary:
	var item: Dictionary = GameState.inventory[index]
	return {"from": ItemSlot.ROLE_BAG, "index": index, "item": item.duplicate(true),
		"token": Warehouse.item_token(item)}

## 找到唯一剩余装备，产物会写回第一件预选材料的原背包格。
func _only_item() -> Dictionary:
	for entry in GameState.inventory:
		if entry is Dictionary:
			return entry
	return {}

## 收集失败断言，末尾统一报告。
func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
