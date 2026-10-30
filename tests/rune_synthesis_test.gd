extends Node
var failures: Array[String] = []
var warehouse_signals := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)

func store(iron: int, jade: int, gold: int, diamond: int) -> Array:
	var out: Array = []
	out.resize(40)
	for pair in [["rune_iron", iron], ["rune_jade", jade], ["rune_gold", gold], ["rune_diamond", diamond]]:
		if pair[1] > 0:
			check(Inventory.add(out, ItemFactory.make_any(pair[0], pair[1])), "测试材料入库")
	return out

func _ready() -> void:
	check(DataLoader.validate_all().is_empty(), "正式配置校验")
	for row in [[0, 0, 0, false], [3, 0, 0, false], [4, 0, 0, true], [5, 0, 0, true], [0, 3, 0, false], [0, 4, 0, true], [0, 0, 39, false], [0, 0, 40, true], [0, 0, 41, true]]:
		var source := store(row[0], row[1], row[2], 0)
		var snapshot := source.duplicate(true)
		var result := RuneSynthesis.plan(source)
		check(result.ok == row[3], "材料阈值 " + str(row))
		check(source == snapshot, "计划不修改原容器")
	var with_other: Array = [ItemFactory.make_any("rune_iron", 5), {"kind": "potion", "itemId": "potion_hp_small", "count": 3}, null]
	var other_snapshot: Dictionary = with_other[1].duplicate(true)
	var preserves := RuneSynthesis.plan(with_other)
	check(preserves.ok and preserves.store[0].count == 1 and preserves.store[1] == other_snapshot, "保留余数格和非如意物品位置")
	var chain := RuneSynthesis.plan(store(640, 0, 0, 0))
	check(chain.ok and RuneCharge.inventory_counts(chain.store).get("rune_diamond") == 1 and Inventory.used_slots(chain.store) == 1, "640 铁贯通至一钻石")
	var mixed := RuneSynthesis.plan(store(19, 3, 39, 2))
	check(mixed.ok and RuneCharge.inventory_counts(mixed.store) == {"rune_iron": 3, "rune_jade": 3, "rune_diamond": 3}, "混合余数与已有钻石")
	var full: Array = [ItemFactory.make_any("rune_iron", 5)]
	check(not RuneSynthesis.plan(full).ok and full[0].count == 5, "满仓余数占格整笔失败")
	full = [ItemFactory.make_any("rune_iron", 4)]
	check(RuneSynthesis.plan(full).ok, "满仓释放格位成功")
	full = [ItemFactory.make_any("rune_iron", 5), ItemFactory.make_any("rune_jade", 1)]
	check(RuneSynthesis.plan(full).ok, "满仓合堆成功")
	check(ItemUtil.stack_max(ItemFactory.make_any("rune_diamond")) == 999 and ItemUtil.stack_max(ItemFactory.make_any("rune_gold")) == 99, "仅钻石提升到999")
	var packed: Array = [null, null]
	check(Inventory.add(packed, ItemFactory.make_any("rune_diamond", 1000)) and packed[0].count == 999 and packed[1].count == 1, "钻石跨堆叠999边界")
	var overflow := RuneSynthesis.plan([ItemFactory.make_any("rune_gold", 80), ItemFactory.make_any("rune_diamond", 998)])
	check(overflow.ok and overflow.store[0].count == 1 and overflow.store[1].count == 999, "产物超过999拆堆")
	var bad := Warehouse.config().duplicate(true)
	bad.runeSynthesis[0].sourceCount = 0
	check(not RuneSynthesis.validate_config(bad).is_empty(), "拒绝零比例")
	bad = Warehouse.config().duplicate(true)
	bad.runeSynthesis[0].targetId = "rune_iron"
	check(not RuneSynthesis.validate_config(bad).is_empty(), "拒绝自环配方")
	GameState.reset_to_defaults()
	GameState.warehouse = store(19, 3, 39, 2)
	GameState.inventory[0] = ItemFactory.make_any("rune_iron", 99)
	var bag_before := GameState.inventory.duplicate(true)
	var panel := preload("res://scenes/ui/WarehousePanel.tscn").instantiate()
	var ui := CanvasLayer.new()
	add_child(ui)
	ui.add_child(panel)
	panel.set_open(true)
	check(not panel._synthesize.disabled, "仓库合成按钮可用")
	EventBus.warehouse_changed.connect(func() -> void: warehouse_signals += 1)
	panel._synthesize.pressed.emit()
	check(warehouse_signals == 1 and RuneCharge.inventory_counts(GameState.warehouse).get("rune_diamond") == 3, "真实按钮提交且仅广播一次")
	check(GameState.inventory == bag_before, "背包不参与")
	check(panel._synthesize.disabled and panel._detail.text.contains("2→3"), "合成后置灰并显示最终数量")
	var settled := GameState.warehouse.duplicate(true)
	check(not GameState.synthesize_warehouse_runes().ok and warehouse_signals == 1 and GameState.warehouse == settled, "重复提交不发奖不广播")
	GameState.warehouse = store(4, 0, 0, 0)
	EventBus.warehouse_changed.emit()
	check(not panel._synthesize.disabled, "库存变更更新按钮")
	GameState.warehouse = store(0, 0, 0, 999)
	GameState.inventory[0] = ItemFactory.make_any("rune_diamond", 999)
	var saved := SaveManager._collect()
	saved.slotId = 1
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(saved))
	check(SaveManager._is_valid_save(decoded), "999钻石存档校验")
	GameState.warehouse = store(0, 0, 0, 0)
	SaveManager.apply_to_game_state(decoded)
	check(RuneCharge.inventory_counts(GameState.warehouse).get("rune_diamond") == 999 and GameState.inventory[0].count == 999, "999钻石JSON往返不丢失")
	var old := decoded.duplicate(true)
	old.warehouse[0].count = 99
	check(SaveManager._is_valid_save(old), "旧99堆叠存档继续接受")
	var oversized := decoded.duplicate(true)
	oversized.warehouse[0].count = 1000
	check(not SaveManager._is_valid_save(oversized), "超过999仍拒绝")
	# 额外输出堆放不下时，已模拟扣除的原材料也必须保持不变。
	var blocked: Array = [ItemFactory.make_any("rune_iron", 5), ItemFactory.make_any("rune_jade", 4), ItemFactory.make_any("rune_gold", 40), ItemFactory.make_any("rune_diamond", 999)]
	var blocked_before := blocked.duplicate(true)
	check(not RuneSynthesis.plan(blocked).ok and blocked == blocked_before, "多阶段产物无法放入时整笔回滚")
	if DisplayServer.get_name() != "headless":
		await _check_layout(panel)
	panel.queue_free()
	GameState.reset_to_defaults()
	if failures.is_empty():
		print("[RuneSynthesisTest] 全部通过 ✅")
	get_tree().quit(0 if failures.is_empty() else 1)

## 真实渲染时检查默认、窄窗口及放大文字下的按钮可见性，并导出复核截图。
func _check_layout(panel: Control) -> void:
	GameState.warehouse = store(19, 3, 39, 2)
	for spec in [[Vector2i(1280, 800), 1.0, 1.0], [Vector2i(960, 720), 1.3, 1.0], [Vector2i(1280, 800), 1.5, 1.5]]:
		DisplayServer.window_set_size(spec[0])
		GameState.settings.textScale = spec[1]
		GameState.settings.uiScale = spec[2]
		SettingsRuntime.apply_ui_scale_to(panel.get_parent())
		SettingsRuntime.apply_text_scale_to(panel)
		panel.set_open(true)
		for _i in range(12):
			await get_tree().process_frame
		var rect := Rect2(panel._synthesize.get_global_transform_with_canvas().origin, panel._synthesize.size * float(spec[2]))
		check(get_viewport().get_visible_rect().encloses(rect), "合成按钮在视口内 " + str(spec))
		check(not panel._synthesize.get_global_rect().intersects(panel._store_organize.get_global_rect()), "两操作按钮不重叠")
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/warehouse_synthesis_%d_%d.png" % [spec[0].x, int(float(spec[2]) * 100)])
