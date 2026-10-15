extends Node
## 货郎购买页布局回归：真实双窗宽度下，说明文字不能撑出横向滚动条或遮住购买按钮。

var _failures: Array[String] = []

## 打开营地货郎并等待容器完成布局，再逐行检查横向范围与金币刷新。
func _ready() -> void:
	GameState.reset_to_defaults()
	var inventory := preload("res://scenes/ui/InventoryPanel.tscn").instantiate()
	var shop := preload("res://scenes/ui/ShopPanel.tscn").instantiate()
	add_child(inventory)
	add_child(shop)
	shop._on_shop_requested("peddler_camp")
	await get_tree().process_frame
	await get_tree().process_frame
	var page: ScrollContainer = shop._tabs.get_child(0)
	var list: VBoxContainer = shop._buy_list
	_check(page.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED,
		"购买页只允许纵向滚动")
	_check(list.size.x <= page.size.x + 1.0,
		"商品列表宽度不超过可见区域（列表 %.1f，视口 %.1f）" % [list.size.x, page.size.x])
	for row in list.get_children():
		if not row is Control:
			continue
		_check(row.size.x <= page.size.x + 1.0,
			"商品行不应撑宽列表（%.1f > %.1f）" % [row.size.x, page.size.x])
		var buttons := row.find_children("*", "Button", true, false)
		_check(buttons.size() == 1 and buttons[0].get_global_rect().end.x <= page.get_global_rect().end.x + 1.0,
			"购买按钮完整落在购买页内")
	GameState.gold = 0
	shop._refresh_buy_prices()
	var prices := list.find_children("*", "Label", true, false).filter(func(label: Label) -> bool:
		return String(label.get_meta("role", "")) == "price")
	_check(prices.size() == list.get_child_count(), "金币变化后每行价格仍可被刷新")
	if not prices.is_empty():
		_check(prices[0].get_theme_color("font_color") == shop.COL_TEXT_DIM,
			"金币不足时嵌套标题行中的价格仍会变暗")
		GameState.gold = 999999
		shop._refresh_buy_prices()
		_check(prices[0].get_theme_color("font_color") == shop.COL_GOLD,
			"金币足够时嵌套标题行中的价格恢复金色")
	shop.set_open(false)
	if _failures.is_empty():
		print("[ShopBuyLayoutTest] 全部通过 ✅")
	else:
		for failure in _failures:
			push_error("FAIL: " + failure)
	get_tree().quit(0 if _failures.is_empty() else 1)

## 收集所有布局断言，便于一次定位不同商品的溢出。
func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures.append(label)
