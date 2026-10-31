extends Node
var failures: Array[String] = []
var rng := RandomNumberGenerator.new()
func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)
func setup(count: int) -> void:
	GameState.reset_to_defaults()
	if count > 40:
		GameState.inventory_expansions = Warehouse.max_expansions()
		GameState.inventory.resize(400)
	for i in range(count):
		GameState.inventory[i] = ItemFactory.make_equip_dynamic("c6_equip_weapon", 61 + (i % 2) * 10, "epic", rng)
func _ready() -> void:
	rng.seed = 3125
	setup(8)
	var ui := CanvasLayer.new()
	add_child(ui)
	var panel := preload("res://scenes/ui/EquipmentFusionPanel.tscn").instantiate()
	ui.add_child(panel)
	panel._on_requested(EquipmentFusion.GOLD_TO_PURPLE, true)
	check(panel._batch.visible, "四金页显示批量按钮")
	panel._on_material_dropped(0, {"from": ItemSlot.ROLE_BAG, "index": 0, "item": GameState.inventory[0].duplicate(true), "token": Warehouse.item_token(GameState.inventory[0])})
	var manual: Dictionary = panel._selected[0].duplicate(true)
	panel._batch.pressed.emit()
	var dialog: GoldBatchDialog = panel._batch_dialog
	check(dialog.visible and not dialog._include.button_pressed and not dialog._confirm.disabled, "打开默认排除带星且可确认")
	var before := GameState.inventory.duplicate(true)
	var esc := InputEventKey.new()
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	Input.parse_input_event(esc)
	await get_tree().process_frame
	check(not dialog.visible and panel.visible and panel._selected[0] == manual and GameState.inventory == before, "Esc只关批量层且保留手动预选")
	panel._batch.pressed.emit()
	GameState.inventory[0].favorite = true
	EventBus.inventory_changed.emit()
	check(dialog._confirm.disabled and dialog._status.text.contains("发生变化"), "收藏变化使确认失效")
	dialog._reload.pressed.emit()
	check(not dialog._status.text.contains("发生变化"), "重新读取恢复当前计划")
	dialog.close()
	panel._on_requested(EquipmentFusion.STAR_TRANSFER, true)
	check(not panel._batch.visible, "其他模式不显示批量入口")
	setup(396)
	panel._on_requested(EquipmentFusion.GOLD_TO_PURPLE, true)
	panel._batch.pressed.emit()
	dialog._confirm.pressed.emit()
	check(dialog._busy and GameState.inventory_used() == 396, "分帧准备期间没有消耗")
	GameState.pickup_loot(ItemFactory.make_any("potion_hp_small", 1))
	var frames := 0
	while dialog.visible and frames < 100:
		await get_tree().process_frame
		frames += 1
	check(not dialog.visible and GameState.inventory_used() == 100, "批量99次成功并保留准备时拾取")
	check(GameState.inventory.any(func(item: Variant) -> bool: return item is Dictionary and item.get("kind") == "potion"), "新增药水完整保留")
	setup(100)
	panel._on_requested(EquipmentFusion.GOLD_TO_PURPLE, true)
	panel._batch.pressed.emit()
	before = GameState.inventory.duplicate(true)
	dialog._confirm.pressed.emit()
	dialog.close()
	await get_tree().process_frame
	check(GameState.inventory == before, "准备期间取消不消耗不发奖")
	setup(8)
	GameState.inventory[0].star = 12
	panel._on_requested(EquipmentFusion.GOLD_TO_PURPLE, true)
	panel._batch.pressed.emit()
	check(dialog._summary.text.contains("保护带星 1"), "预览说明带星保护")
	dialog._include.button_pressed = true
	check(dialog._summary.text.contains("消耗带星金装 1"), "明确包含带星时提示损失")
	if DisplayServer.get_name() != "headless":
		for spec in [[Vector2i(1280, 800), 1.0], [Vector2i(960, 720), 1.0], [Vector2i(1280, 800), 1.5]]:
			DisplayServer.window_set_size(spec[0])
			GameState.settings.uiScale = spec[1]
			GameState.settings.textScale = spec[1]
			SettingsRuntime.apply_ui_scale_to(ui)
			SettingsRuntime.apply_text_scale_to(ui)
			dialog._resize()
			for _i in range(16):
				await get_tree().process_frame
			var box: Control = dialog._window.panel_box
			var rect := Rect2(box.get_global_transform_with_canvas().origin, box.size * float(spec[1]))
			check(get_viewport().get_visible_rect().grow(1).encloses(rect), "批量浮层不越界 " + str(spec))
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("/tmp/gold_batch_ui_%d_%d.png" % [spec[0].x, int(float(spec[1]) * 100)])
	dialog.close()
	panel.queue_free()
	GameState.reset_to_defaults()
	if failures.is_empty():
		print("[GoldBatchUiTest] 全部通过 ✅")
	get_tree().quit(0 if failures.is_empty() else 1)
