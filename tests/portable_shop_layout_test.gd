extends Node
## 工程 60：随身商店「出售」页布局回归。
##
## 锁的是**一条会随数据变长而爆的链**，不是某个像素：
##   `ui.sale_preview.risk` 把 N 件装备全名拼成一行 → Label 未换行 ⇒ 最小宽 = 整行宽（实测 4 件 853px）
##   → `TabContainer`（只算当前页）→ `ScrollContainer` 内容宽 869px，而视口只有 430px
##   → 托盘两侧弹性空白在 869px 里居中，网格右移 273px、右侧两列落到视口外。
##
## 所以断言分三层，缺一层就可能「看起来修好了」：
##   ① 内容宽 ≤ 视口宽（换行真的生效）
##   ② 横向滚动条不存在（兜底开关真的关了）
##   ③ 托盘仍居中（这是玩家截图里看到的「变形」本身，也是唯一能咬住 ① 之外的补救方案）
##
## ⚠ 只断 ① 会漏掉「关掉横向滚动但没换行」的改法 —— 那种改法内容宽 869 而视口 430，
##    断言 ① 红、但真实表现是「文字被裁」，同样不可接受。故 ③ 必须同时在。

const EQUIP_IDS := ["c6_equip_bracer", "c6_equip_helmet", "c6_equip_armor", "c6_equip_shoes",
	"c6_equip_knee", "c6_equip_shield", "c6_equip_bracelet", "c6_equip_ring",
	"c6_equip_necklace", "c6_equip_weapon"]

var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("[ShopLayoutTest] " + label)

func _ready() -> void:
	await _test_sell_page(1280.0, 4, "1280 宽 / 4 件（截图场景）")
	await _test_sell_page(1280.0, 12, "1280 宽 / 12 件")
	await _test_sell_page(800.0, 4, "800 宽 / 4 件")
	_test_risk_text_folding()
	GameState.reset_to_defaults()
	if failures.is_empty():
		print("[ShopLayoutTest] 全部通过 ✅")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("[ShopLayoutTest] 失败 %d 项" % failures.size())
		get_tree().quit(1)

## 打开面板 → 塞装备 → 切出售页 → 点确认（生成风险行），再量四处几何。
func _test_sell_page(width: float, count: int, tag: String) -> void:
	GameState.reset_to_defaults()
	var panel := await _open_panel(width)
	if panel == null:
		check(false, "%s：面板未能打开" % tag)
		return

	var tray: Dictionary = panel.get("_tray")
	for i in range(count):
		var item := ItemFactory.make_equip_dynamic(String(EQUIP_IDS[i % EQUIP_IDS.size()]), 106, "legendary")
		item["star"] = 12
		tray[i] = item
	panel.call("_refresh_tray")
	await get_tree().process_frame

	var tabs: TabContainer = panel.get("_tabs")
	tabs.current_tab = 1
	for i in range(4):
		await get_tree().process_frame

	# 风险行只有在「有装备不在预设默认勾选内」时才出现；传奇 + 12 星在谨慎预设下必然触顶。
	panel.call("_on_confirm_pressed")
	for i in range(4):
		await get_tree().process_frame

	var scroll: ScrollContainer = panel.get("_scroll")
	var content: Control = scroll.get_child(0) as Control
	var warn: Label = panel.get("_tray_warn")
	var summary: Label = panel.get("_tray_summary")
	var grid := _find_grid(panel)
	check(grid != null, "%s：应能定位到托盘网格" % tag)
	if grid == null:
		_destroy(panel)
		return

	check(not scroll.get_h_scroll_bar().visible, "%s：出售页不得出现横向滚动条" % tag)
	# 必须断言**最小尺寸**而不是 `size`：`size` 会被父容器钳到视口宽，
	# 于是「文字 853px 溢出一屏」的坏实现照样能让 size 断言通过 —— 那是假绿。
	var content_min := content.get_combined_minimum_size()
	check(content_min.x <= scroll.size.x + 0.5,
		"%s：内容最小宽 %.1f 不得大于滚动视口 %.1f（长名单必须换行）" % [tag, content_min.x, scroll.size.x])
	check(warn.size.x <= content.size.x + 0.5,
		"%s：告警行宽 %.1f 超出内容区 %.1f（文字会被裁）" % [tag, warn.size.x, content.size.x])
	check(summary.size.x <= content.size.x + 0.5,
		"%s：汇总行宽 %.1f 超出内容区 %.1f" % [tag, summary.size.x, content.size.x])
	# 居中：左右留白相等（允许滚动条与内边距带来的偏差）
	var left_pad := grid.position.x
	var right_pad := content.size.x - grid.position.x - grid.size.x
	check(absf(left_pad - right_pad) <= 16.0,
		"%s：托盘应居中，左留白 %.1f / 右留白 %.1f（右移即截图里的变形）" % [tag, left_pad, right_pad])
	check(warn.get_line_count() >= 2,
		"%s：风险文本应折成多行，实际 %d 行" % [tag, warn.get_line_count()])
	check(warn.text.contains("珍贵装备"), "%s：风险文本内容不应丢失" % tag)
	_destroy(panel)

## 折叠口径是纯函数，单独测：12 件只列前 5 件 + 「等 12 件」，且不得泄漏第 6 件之后的名字。
func _test_risk_text_folding() -> void:
	var short: Array[String] = ["甲", "乙", "丙"]
	check(EquipmentSalePreview.risk_names_text(short) == "甲, 乙, 丙",
		"3 件时应原样列出，实际「%s」" % EquipmentSalePreview.risk_names_text(short))

	var many: Array[String] = []
	for i in range(12):
		many.append("装备%d号" % i)
	var text := EquipmentSalePreview.risk_names_text(many)
	check(text.contains("等 12 件"), "超过 %d 件应折成「等 12 件」，实际「%s」" % [EquipmentSalePreview.RISK_LIST_LIMIT, text])
	check(text.contains("装备4号") and not text.contains("装备5号"),
		"折叠应恰好保留前 %d 件，实际「%s」" % [EquipmentSalePreview.RISK_LIST_LIMIT, text])
	check(text.length() < 120, "12 件的名单应被收短（<120 字），实际 %d 字" % text.length())

# ---- 工具 ----

func _open_panel(width: float) -> Control:
	var host := Control.new()
	host.size = Vector2(width, 720)
	add_child(host)
	var packed := load("res://scenes/ui/ShopPanel.tscn") as PackedScene
	var panel := packed.instantiate() as Control
	host.add_child(panel)
	await get_tree().process_frame
	panel.call("_on_shop_requested", "portable_shop")
	for i in range(3):
		await get_tree().process_frame
	return panel

func _destroy(panel: Control) -> void:
	var host := panel.get_parent()
	panel.queue_free()
	if host != null:
		host.queue_free()
	await get_tree().process_frame

func _find_grid(panel: Control) -> ShopTrayGrid:
	var tabs: TabContainer = panel.get("_tabs")
	if tabs == null or tabs.get_child_count() < 2:
		return null
	for c in tabs.get_child(1).get_children():
		if c is HBoxContainer:
			for g in c.get_children():
				if g is ShopTrayGrid:
					return g
	return null
