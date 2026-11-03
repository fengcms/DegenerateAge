extends Node
## 装备UI回归：真实界面倍率、服务切换和滚动裁剪，防止材料节点存在但看不见。

## 以实际CanvasLayer应用倍率，验证冷启动、缩放和清空重开后的材料可访问性。
func _ready() -> void:
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	get_window().size = Vector2i(1280,800)
	GameState.reset_to_defaults()
	var ui := CanvasLayer.new()
	add_child(ui)
	var bag = load("res://scenes/ui/InventoryPanel.tscn").instantiate()
	ui.add_child(bag)
	var panel = load("res://scenes/ui/EquipmentFusionPanel.tscn").instantiate()
	ui.add_child(panel)
	var character = load("res://scenes/ui/CharacterPanel.tscn").instantiate()
	ui.add_child(character)
	for spec in [[Vector2i(2304, 900), 1.0], [Vector2i(1280, 800), 1.0],
			[Vector2i(1280, 800), 1.25], [Vector2i(1280, 800), 2.0]]:
		get_window().size = spec[0]
		await get_tree().process_frame
		var scale_value: float = spec[1]
		GameState.settings.uiScale = scale_value
		SettingsRuntime.apply_ui_scale_to(ui)
		for mode in [EquipmentFusion.SACRIFICE,EquipmentFusion.STAR_TRANSFER,EquipmentFusion.GOLD_TO_PURPLE,EquipmentFusion.STAR_TRANSFER]:
			panel._on_requested(mode,false)
			panel._scroll.scroll_vertical = 0
			for i in range(25):
				await get_tree().process_frame
			var logical: Vector2 = get_viewport().get_visible_rect().size / SettingsRuntime.ui_scale_value()
			assert(panel._box.size.y <= panel._center.size.y+1.0, "面板不能超出分区")
			assert(panel._center.position.y+panel._center.size.y <= logical.y+1.0, "面板不能漂出视口")
			if mode == EquipmentFusion.STAR_TRANSFER:
				assert(character.visible and bag.visible and panel.visible, "保星升级一次打开三窗")
				var bounds := Rect2(Vector2.ZERO, logical).grow(1.0)
				var work_rect: Rect2 = panel._box.get_global_rect()
				var bag_rect: Rect2 = bag._center.panel_box.get_global_rect()
				var character_rect: Rect2 = character._center.panel_box.get_global_rect()
				assert(bounds.encloses(work_rect) and bounds.encloses(bag_rect) and bounds.encloses(character_rect), "三窗均须留在视口内")
				if logical.x >= 2000.0:
					assert(bag_rect.end.x <= work_rect.position.x and work_rect.end.x <= character_rect.position.x,
						"宽屏三窗横排")
				else:
					assert(work_rect.end.y <= bag_rect.position.y + 1.0, "窄屏来源区位于工作台下方")
				assert(not work_rect.intersects(character_rect) and not work_rect.intersects(bag_rect)
					and not character_rect.intersects(bag_rect), "三个操作区互不遮挡")
			if mode == EquipmentFusion.SACRIFICE:
				assert(not panel._grid.visible)
				continue
			assert(panel._scroll.size.y >= 78.0, "材料视窗不能压成0或小于一格")
			assert(panel._grid.position.y <= 1.0, "打开即显示材料行，不被长说明顶出首屏")
			# 滚动到材料行，用裁剪区域的交集验证可见性，而非只断言visible=true。
			panel._scroll.scroll_vertical = int(panel._grid.position.y)
			for i in range(3):
				await get_tree().process_frame
			for index in range(2 if mode == EquipmentFusion.STAR_TRANSFER else 4):
				var slot: ItemSlot = panel._slots[index]
				if index >= 2:
					continue # 四格模式第二行按滚动访问，保星两格必须同屏。
				assert(slot.is_visible_in_tree() and slot.size == Vector2(78,78))
				var overlap := slot.get_global_rect().intersection(panel._scroll.get_global_rect())
				assert(overlap.size.y >= 77.0 and overlap.size.x >= 77.0, "材料必须实际落在可见裁剪区")
		panel.set_open(false)
		assert(character.visible and bag.visible and not character._center._docked, "关闭工作台恢复人物浮窗")
	# 同帧拾取、背包整理和击杀磨损均不替换第一次确认的装备。
	GameState.player.level = 600
	var rng := RandomNumberGenerator.new()
	rng.seed = 4513
	var locked := ItemFactory.make_equip_exact("c6_equip_weapon", 500, "legendary", rng)
	var newcomer := ItemFactory.make_equip_exact("c6_equip_weapon", 490, "legendary", rng)
	GameState.inventory[0] = locked
	GameState.equipment.weapon = ItemFactory.make_equip_exact("c6_equip_weapon", 500, "legendary", rng)
	panel._on_requested(EquipmentFusion.SACRIFICE, true)
	panel._on_confirm()
	assert(panel._risk_confirmed)
	var expected_xp := Sacrifice.xp_of(locked)
	assert(GameState.pickup_loot(newcomer).ok)
	GameState.organize_inventory()
	GameState.wear_equipment("normal")
	GameState.add_xp(1)
	assert(panel._risk_confirmed, "拾取与磨损保留已锁定确认")
	panel._on_confirm()
	assert(GameState.inventory_used() == 1 and not GameState.find_owned_item(newcomer.instanceId).is_empty()
		and GameState.find_owned_item(locked.instanceId).is_empty() and GameState.player.xp == expected_xp + 1,
		"第二次点击只扣旧批，新拾取的低档装备仍在")
	await get_tree().process_frame
	await get_tree().process_frame
	panel._on_confirm()
	assert(panel._risk_confirmed)
	GameState.set_equipment_favorite(newcomer.instanceId, true)
	panel._on_confirm()
	assert(GameState.inventory_used() == 1 and GameState.player.xp == expected_xp + 1
		and not panel._risk_confirmed, "锁定装备被收藏后整批拒绝")
	print("[EquipmentLayoutRegressionTest] PASS")
	get_tree().quit()
