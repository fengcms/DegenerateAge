extends Node
## 装备出售共用清单的交互回归：预设默认勾选、收藏更新与背包直卖。
## 用隔离面板实例验证 UI 到 GameState 的接线，不操作玩家正式存档。

var failures: Array[String] = []

## 打开背包清单后切换收藏并成交，确认预览不会直接改变背包。
func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 220
	GameState.reset_to_defaults()
	GameState.player.level = 15
	GameState.equipment.shoes = ItemFactory.make_equip_roll("c2_road_shoes", 11, "common", rng)
	var old_shoes := ItemFactory.make_equip_roll("shoes_cloth", 1, "common", rng)
	GameState.inventory[0] = old_shoes
	var panel := preload("res://scripts/ui/inventory_panel.gd").new()
	add_child(panel)
	panel.set_open(true)
	panel._on_sell_low_pressed()
	var preview: EquipmentSalePreview = _preview()
	check(preview != null and preview._rows.size() == 1 and bool(preview._selected.get(String(old_shoes.instanceId), false)),
		"默认谨慎打开清单并勾选旧装备")
	for factor in [1.0, 1.5, 2.0]:
		GameState.settings.uiScale = factor
		preview._resize()
		await get_tree().process_frame
		preview._resize()
		check(preview._box.position.x >= 0.0 and preview._box.position.y >= 0.0
			and preview._box.position.x + preview._box.size.x <= preview.size.x + 1.0
			and preview._box.position.y + preview._box.size.y <= preview.size.y + 1.0,
			"出售清单在 %.0f%% 界面倍率下保持窗口内：位置 %s、窗口 %s、视口 %s" %
				[factor * 100.0, preview._box.position, preview._box.size, preview.size])
	GameState.settings.uiScale = 1.0
	preview._resize()
	check(GameState.inventory[0] is Dictionary and GameState.gold == 0, "打开清单不立即出售")
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	panel._on_bag_slot_input(right_click, 0)
	check(bool(GameState.inventory[0].get("favorite", false)) and preview._stale,
		"背包右键收藏并使已打开的清单过期")
	preview._on_confirm()
	check(GameState.inventory[0] is Dictionary and not bool(preview._selected.get(String(old_shoes.instanceId), true)),
		"旧清单首次确认只刷新，收藏装备不再被勾选")
	panel._on_bag_slot_input(right_click, 0)
	check(not bool(GameState.inventory[0].get("favorite", true)), "右键可取消收藏")
	preview._on_confirm()
	check(GameState.inventory[0] is Dictionary, "取消收藏导致过期的清单仍需重新确认")
	var price := Shop.sell_price(old_shoes)
	preview._on_confirm()
	check(GameState.inventory[0] == null and GameState.gold == price, "新清单确认后只卖出选中的装备")
	var merchant := preload("res://scripts/ui/shop_panel.gd").new()
	add_child(merchant)
	var rare := ItemFactory.make_equip_roll("shoes_cloth", 1, "rare", rng)
	merchant._tray[0] = rare
	merchant._refresh_tray()
	var before_merchant := GameState.gold
	merchant._on_confirm_pressed()
	check(merchant._tray.size() == 1 and GameState.gold == before_merchant,
		"货郎托盘中的预设外装备首次确认只显示风险")
	merchant._on_confirm_pressed()
	check(merchant._tray.is_empty() and GameState.gold == before_merchant + Shop.sell_price(rare),
		"货郎再次确认后才结算高价值装备")
	if failures.is_empty():
		print("[SellGearPreviewTest] 全部通过 ✅")
	else:
		for failure in failures:
			push_error("FAIL: " + failure)
	get_tree().quit(0 if failures.is_empty() else 1)

## 返回当前测试节点下的清单实例，避免把其他面板当成确认对象。
func _preview() -> EquipmentSalePreview:
	for child in get_children():
		if child is EquipmentSalePreview:
			return child
	return null

## 记录所有界面断言失败后统一返回。
func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
