extends Node
## 仓库双栏格子回归：验证背包同款外观、图标、空槽和容量变更时的节点复用。

var _failures: Array[String] = []

## 只在隔离测试项目内修改 GameState，不触碰玩家存档。
func _ready() -> void:
	GameState.reset_to_defaults()
	var potion := {"kind": "potion", "itemId": "potion_hp_small", "count": 3}
	GameState.inventory[0] = potion.duplicate(true)
	GameState.warehouse[0] = potion.duplicate(true)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	GameState.warehouse[2] = ItemFactory.make_equip_roll("shoes_cloth", 1, "rare", rng)
	var panel := preload("res://scenes/ui/WarehousePanel.tscn").instantiate()
	add_child(panel)
	panel.set_open(true)
	var bag: ItemSlot = panel._bag_slots[0]
	var store: ItemSlot = panel._store_slots[0]
	var empty: ItemSlot = panel._store_slots[1]
	var quality_slot: ItemSlot = panel._store_slots[2]
	_check(bag.icon != null and store.icon == bag.icon and bag.text == "" and store.text == "",
		"两栏有图标的物品格使用同一图标且不叠加名称")
	_check(bag.role == ItemSlot.ROLE_BAG and store.role == ItemSlot.ROLE_WAREHOUSE
		and bag.draggable and store.draggable, "双栏角色和拖拽能力保留")
	_check(empty.text == "" and empty.item.is_empty() and not empty.draggable
		and empty.role == ItemSlot.ROLE_WAREHOUSE, "仓库空格不再显示旧占位点")
	var bag_style: StyleBoxFlat = bag.get_theme_stylebox("normal")
	var store_style: StyleBoxFlat = store.get_theme_stylebox("normal")
	var empty_style: StyleBoxFlat = empty.get_theme_stylebox("normal")
	_check(bag_style.bg_color == store_style.bg_color and store_style.bg_color == ItemSlot.GRID_FILLED
		and empty_style.bg_color == ItemSlot.GRID_EMPTY, "两栏共用背包式填充色和空槽色")
	var quality_style: StyleBoxFlat = quality_slot.get_theme_stylebox("normal")
	_check(quality_slot._quality_frame.visible and quality_style.border_color == Color.TRANSPARENT,
		"高品质装备使用动画品质框且不叠加静态边框")
	GameState.warehouse[0] = null
	panel._refresh()
	_check(panel._store_slots[0] == store and store.icon == null and store.text == ""
		and not store.draggable, "物品移走后复用格子并清除旧图标及拖拽态")
	GameState.warehouse.resize(50)
	panel._refresh()
	_check(panel._store_slots.size() == 50 and panel._store_slots[0] == store,
		"扩容只补建新格子，不重建已有格子")
	GameState.warehouse[0] = GoldExchange.stack_item(GoldExchange.BRICK, 3)
	panel._refresh()
	_check(panel._xp_buttons[GoldExchange.BRICK_XP].disabled, "低等级仓库按钮置灰")
	GameState.player.level = 100
	EventBus.player_leveled.emit(100)
	_check(not panel._xp_buttons[GoldExchange.BRICK_XP].disabled, "达到解锁等级时按钮更新")
	panel._xp_buttons[GoldExchange.BRICK_XP].pressed.emit()
	var dialog: PanelAmountDialog = panel._amount_dialog
	_check(dialog.visible and dialog._edit.text == "1" and dialog._got_label.text.contains("3486"),
		"数量框默认一块并预览到账经验")
	GameState.add_xp(1)
	EventBus.inventory_changed.emit()
	dialog._on_confirm()
	_check(not dialog.visible and GameState.warehouse[0].count == 2, "同级战斗经验和背包刷新后一次确认成功")
	dialog._on_confirm()
	_check(not dialog.visible and GameState.warehouse[0].count == 2 and GameState.player.xp == 3487,
		"重复确认不扣第二块")
	GameState.warehouse[1] = {"kind": "rune", "itemId": "rune_diamond", "count": 8}
	EventBus.warehouse_changed.emit()
	panel._xp_buttons[GoldExchange.DIAMOND_XP].pressed.emit()
	_check(dialog.visible and dialog._cost_label.text.contains("钻石如意") and dialog._cost_label.text.contains("4"),
		"如意入口预览一批四个")
	GameState.add_xp(2)
	dialog._on_confirm()
	_check(not dialog.visible and GameState.player.xp == 6975 and GameState.warehouse[1].count == 4 and GameState.diamond_xp_used == 1 and GameState.brick_xp_used == 1,
		"如意和金砖使用独立额度")
	var frame: QualityFrameOverlay = quality_slot._quality_frame
	var start := frame._started_usec
	frame.set_quality("rare")
	_check(frame.is_processing() and frame._started_usec == start, "相同品质不重启动画")
	panel.set_open(false)
	_check(not frame.is_processing(), "隐藏仓库停止品质框处理")
	panel.set_open(true)
	_check(frame.is_processing() and frame._started_usec == start, "重开继续原品质动画")
	panel.queue_free()
	if _failures.is_empty():
		print("[WarehouseSlotVisualTest] 全部通过 ✅")
	else:
		for failure in _failures:
			push_error("FAIL: " + failure)
	get_tree().quit(0 if _failures.is_empty() else 1)

## 累计独立断言，方便一次定位多个视觉退化。
func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures.append(label)
