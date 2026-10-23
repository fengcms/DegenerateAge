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
	var character := preload("res://scenes/ui/CharacterPanel.tscn").instantiate()
	add_child(dialogue)
	add_child(bag)
	add_child(panel)
	add_child(character)
	EventBus.blacksmith_panel_requested.emit("铁匠", "试试新服务")
	dialogue._show_menu()
	check(dialogue._fusion_buttons.size() == 5, "铁匠菜单提供五项消耗装备的服务（四种合成 + 紫装献祭）")
	check(dialogue._leave.get_parent() == dialogue._footer
		and not dialogue._service_scroll.is_ancestor_of(dialogue._leave),
		"离开按钮在底部固定行，不再混进服务网格")
	# 工程 77 之后服务网格是**三组**：强化（2）+ 合成（4，2×2）+ 维护与转化（2）。
	# 原断言「两组、各自成对」是工程 77 之前的形态，该测试此前不在默认集，一直没被发现；
	# 工程 87 把献祭并进维护组，正好把它从单按钮补成成对。
	check(dialogue._service_grids.size() == 3 and dialogue._service_grids.all(
		func(grid: GridContainer) -> bool: return grid.get_child_count() % 2 == 0),
		"三组服务网格各自成对，没有孤格")
	GameState.settings.uiScale = 1.0
	dialogue._resize()
	await get_tree().process_frame
	await get_tree().process_frame
	# 2026-10-21：合成组四项排成 2×2，「四紫升紫」与「保星升级」必须落在同一行。
	# 断的是实际矩形（同一 y、左右相邻、各自有宽），不是「父节点相同」——后者在
	# GridContainer 换成 1 列或 4 列时照样成立，属于假绿。
	var purple_up := _button_titled(dialogue._fusion_buttons, "ui.fusion.purple_up_title")
	var transfer := _button_titled(dialogue._fusion_buttons, "ui.fusion.star_title")
	check(purple_up != null and transfer != null
		and purple_up.get_parent() == transfer.get_parent()
		and absf(purple_up.global_position.y - transfer.global_position.y) <= 1.0
		and purple_up.global_position.x + purple_up.size.x <= transfer.global_position.x + 1.0
		and purple_up.size.x > 0.0 and transfer.size.x > 0.0,
		"四紫升紫与保星升级并排在同一行（左四紫、右保星，各自占半行）")
	# 服务区高度由 FloatingWindow.fit_content 按内容结算：100% 缩放下必须整段放得下，
	# 也就是**根本没有滚动条**；曾经写死 `clampf(logical.y - 250, 54, 380)` 时内容 407px
	# 溢出 27px，滚动条常驻（2026-10-21 修）。判据用 bar.visible + 内容高 vs 视窗高，
	# 只断「滚动量 ≤ 1.4 屏」会放过滚动条常驻这件事。
	var bar: VScrollBar = dialogue._service_scroll.get_v_scroll_bar()
	var content := dialogue._service_scroll.get_child(0) as Control
	check(not bar.visible and bar.max_value <= dialogue._service_scroll.size.y + 0.5,
		"100%% 缩放下服务区不出现滚动条（内容 %d / 视窗 %d）"
			% [int(bar.max_value), int(dialogue._service_scroll.size.y)])
	check(dialogue._service_scroll.size.y >= content.get_combined_minimum_size().y - 0.5,
		"服务区高度跟随内容自然高度，而不是被压到固定上限")
	check(dialogue._root.size.y <= dialogue._center.size.y + 1.0, "100% 缩放下铁匠面板不溢出视口")
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
	for i in range(4):
		GameState.inventory[i] = ItemFactory.make_equip_dynamic("c6_equip_ring", 61, "legendary", rng)
	panel._on_requested(EquipmentFusion.PURPLE_UP_TIER)
	check(panel.visible and panel._random.visible and not panel._target_row.visible
		and panel._title.text == Localization.tr_key("ui.fusion.purple_up_title"),
		"四紫升紫沿用四格与随机按钮，不显示指定部位")
	GameState.inventory[0].star = 12
	panel._on_material_dropped(0, _payload(0))
	check(panel._selected[0].is_empty(), "12 星紫装不能拖进升档格")
	GameState.inventory[0].star = 0
	EventBus.inventory_changed.emit()
	panel._on_random_fill()
	check(panel._material_snapshots().size() == 4 and not panel._confirm.disabled
		and panel._summary.text.contains("61—70") and panel._summary.text.contains("71—80")
		and panel._summary.text.contains("随机部位"), "四紫随机放入只预选四件并显示升档预览")
	panel._on_confirm()
	var up_output := _only_item()
	check(GameState.inventory_used() == 1 and EquipmentFusion.tier_start(up_output) == 71
		and int(up_output.get("star", -1)) == 0, "四紫升紫界面结算为下一档 0 星紫装")
	panel.set_open(false)
	bag.set_open(false)
	GameState.reset_to_defaults()
	for i in range(4):
		GameState.inventory[i] = ItemFactory.make_equip_dynamic("c6_equip_ring", 61, "legendary", rng)
	GameState.inventory[0].star = 11
	panel._on_requested(EquipmentFusion.PURPLE_UP_TIER)
	for i in range(4):
		panel._on_material_dropped(i, _payload(i))
	check(not panel._confirm.disabled, "手动可放入 11 星紫装")
	panel._on_confirm()
	check(GameState.inventory_used() == 4 and panel._feedback.text.contains("星级会消失"),
		"升档首次确认只提示材料星级损失")
	panel._on_confirm()
	check(GameState.inventory_used() == 1 and EquipmentFusion.tier_start(_only_item()) == 71,
		"再次确认才消耗带星紫装")
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
	# 显式钉住等级：默认等级一旦变化，「产物穿不上」这个前提会静默失效，断言就变成空转。
	GameState.player["level"] = 1
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
	check(panel._out_level.text.contains("Lv71") and panel._out_level.text.contains("还差 70 级")
		and not panel._summary.text.contains("暂时无法穿戴"),
		"产物高出玩家等级时提示搬到独立高亮行（不再混在四模式共用的 _summary 里）")
	panel._on_confirm()
	panel._on_confirm()
	var far_output := _only_item()
	check(GameState.inventory_used() == 1 and GameState.gold == 0
		and EquipmentFusion.tier_start(far_output) == 71 and int(far_output.get("star", 0)) == 12,
		"跨两档保星扣双倍金币并产出 71 档 12 星紫装")
	# ---- 工程 65：并开人物面板 + 从身上把旧件拖进第一格 ----
	GameState.reset_to_defaults()
	var worn_old := ItemFactory.make_equip_roll("c6_equip_weapon", 51, "legendary", rng)
	worn_old.star = 12
	GameState.equipment["weapon"] = worn_old
	GameState.inventory[0] = ItemFactory.make_equip_dynamic("c6_equip_weapon", 61, "legendary", rng)
	GameState.gold = EquipmentFusion.full_star_cost()
	panel._on_requested(EquipmentFusion.STAR_TRANSFER)
	check(panel._slots[0].accept_equip_source and not panel._slots[1].accept_equip_source,
		"只有保星第一格接收穿戴载荷")
	var worn_payload := {"from": ItemSlot.ROLE_EQUIP, "slot_id": "weapon",
		"item": worn_old.duplicate(true), "token": Warehouse.item_token(worn_old)}
	check(panel._grid._can_drop_data(panel._slots[0].position + panel._slots[0].size * 0.5, worn_payload)
		and not panel._grid._can_drop_data(panel._slots[1].position + panel._slots[1].size * 0.5, worn_payload),
		"格网只对第一格放行穿戴载荷")
	character.set_open(true)
	check(panel.visible and character.visible, "按 C 打开人物面板不再关闭保星面板")
	panel._on_material_dropped(1, worn_payload)
	check(panel._selected[1].is_empty() and panel._feedback.text.contains("只能从背包拖入"),
		"第二格拒收身上那件并说明原因")
	panel._on_material_dropped(0, worn_payload)
	check(String(panel._selected[0].get("instanceId", "")) == String(worn_old.instanceId),
		"第一格接收身上那件")
	GameState.equipment["weapon"] = null
	EventBus.equipment_changed.emit()
	check(panel._selected[0].is_empty(), "身上那件被换下后预选自动失效")
	var swapped := ItemFactory.make_equip_roll("c6_equip_weapon", 51, "legendary", rng)
	swapped.star = 12
	GameState.equipment["weapon"] = swapped
	EventBus.equipment_changed.emit()
	panel._on_material_dropped(0, worn_payload)
	check(panel._selected[0].is_empty() and panel._feedback.text.contains("材料已变化"),
		"拖动期间换了身，旧载荷不能再被选入")
	GameState.equipment["weapon"] = worn_old
	EventBus.equipment_changed.emit()
	panel._on_material_dropped(0, worn_payload)
	panel._on_material_dropped(1, _payload(0))
	check(not panel._confirm.disabled, "身上 + 背包两件凑齐后可确认保星")
	panel._on_confirm()
	check(panel._feedback.text.contains("穿在身上"), "首次确认明确提示该部位将空出")
	panel._on_confirm()
	check(GameState.equipment.get("weapon") == null and GameState.gold == 0
		and GameState.inventory_used() == 1 and panel.visible and character.visible,
		"结算后穿戴槽清空、金币扣一次、产物进背包，两面板都还开着")
	# ---- 工程 75：两件即可开赌，成功率与失败全损必须写在界面上 ----
	panel.set_open(false)
	bag.set_open(false)
	character.set_open(false)
	GameState.reset_to_defaults()
	for i in range(2):
		GameState.inventory[i] = ItemFactory.make_equip_dynamic("c6_equip_ring", 61, "legendary", rng)
	panel._on_requested(EquipmentFusion.PURPLE_UP_TIER)
	panel._on_material_dropped(0, _payload(0))
	panel._on_material_dropped(1, _payload(1))
	check(panel._material_snapshots().size() == 2 and not panel._confirm.disabled,
		"四紫升紫放入两件即可确认，不再强制四件")
	check(panel._summary.text.contains("成功率 50%")
		and panel._summary.text.contains("失败将消耗投入的全部材料"),
		"两件时预览写明 50% 成功率与失败全损")
	var before_two := GameState.inventory.duplicate(true)
	panel._on_confirm()
	check(GameState.inventory == before_two and panel._feedback.text.contains("成功率 50%")
		and panel._feedback.text.contains("全部消耗"),
		"两件首次点击只警告成功率与失败全损，不消耗材料")
	# 随机放入改取最低档：先把 71 档四件塞满，再点随机，必须整组换掉并清空多余格。
	GameState.reset_to_defaults()
	for i in range(2):
		GameState.inventory[i] = ItemFactory.make_equip_dynamic("c6_equip_ring", 61, "legendary", rng)
	for i in range(2, 6):
		GameState.inventory[i] = ItemFactory.make_equip_dynamic("c6_equip_ring", 71, "legendary", rng)
	panel._on_requested(EquipmentFusion.PURPLE_UP_TIER)
	for i in range(4):
		panel._on_material_dropped(i, _payload(i + 2))
	check(panel._material_snapshots().size() == 4, "手动放满四件 71 档可确认")
	panel._on_random_fill()
	check(panel._material_snapshots().size() == 2
		and EquipmentFusion.tier_start(panel._selected[0]) == 61
		and panel._selected[2].is_empty() and panel._selected[3].is_empty(),
		"随机放入改取最低档两件，并清空多出来的两格")
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

## 按本地化文案找按钮：不依赖 _fusion_buttons 的排列顺序，重排菜单时断言不会跟着失效。
func _button_titled(buttons: Array[Button], key: String) -> Button:
	var text := Localization.tr_key(key)
	for button in buttons:
		if button.text == text:
			return button
	return null

## 收集失败断言，末尾统一报告。
func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
