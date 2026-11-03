extends Node
## 装备UI回归：真实界面倍率、服务切换和滚动裁剪，防止材料节点存在但看不见。

## 以实际CanvasLayer应用倍率，验证冷启动、缩放和清空重开后的材料可访问性。
func _ready() -> void:
	get_window().size = Vector2i(1280,800)
	GameState.reset_to_defaults()
	var ui := CanvasLayer.new()
	add_child(ui)
	var bag = load("res://scenes/ui/InventoryPanel.tscn").instantiate()
	ui.add_child(bag)
	var panel = load("res://scenes/ui/EquipmentFusionPanel.tscn").instantiate()
	ui.add_child(panel)
	for scale_value in [1.0,1.25,2.0,1.0]:
		GameState.settings.uiScale = scale_value
		SettingsRuntime.apply_ui_scale_to(ui)
		for mode in [EquipmentFusion.SACRIFICE,EquipmentFusion.STAR_TRANSFER,EquipmentFusion.GOLD_TO_PURPLE,EquipmentFusion.STAR_TRANSFER]:
			panel._on_requested(mode,false)
			panel._scroll.scroll_vertical = 0
			for i in range(25):
				await get_tree().process_frame
			var logical: Vector2 = Vector2(get_window().size)/scale_value
			assert(panel._box.size.y <= panel._center.size.y+1.0, "面板不能超出分区")
			assert(panel._center.position.y+panel._center.size.y <= logical.y+1.0, "面板不能漂出视口")
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
	# 库存变化与第二次点击发生在同一帧，不能沿用旧批次确认。
	GameState.player.level = 600
	var rng := RandomNumberGenerator.new()
	rng.seed = 4513
	GameState.inventory[0] = ItemFactory.make_equip_exact("c6_equip_weapon", 500, "legendary", rng)
	panel._on_requested(EquipmentFusion.SACRIFICE, true)
	panel._on_confirm()
	assert(panel._risk_confirmed)
	assert(GameState.add_item(ItemFactory.make_equip_exact("c6_equip_weapon", 500, "legendary", rng)))
	assert(not panel._risk_confirmed, "库存信号立即撤销旧确认")
	panel._on_confirm()
	assert(panel._risk_confirmed and GameState.inventory_used() == 2, "重新确认时仍保留两件装备")
	panel._on_confirm()
	assert(GameState.inventory_used() == 0, "确认最新批次后才消耗装备")
	await get_tree().process_frame
	await get_tree().process_frame
	assert(bag._bag_buttons[0].item.is_empty() and bag._bag_buttons[1].item.is_empty())
	print("[EquipmentLayoutRegressionTest] PASS")
	get_tree().quit()
