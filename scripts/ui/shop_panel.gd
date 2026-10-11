extends Control
## 货郎商店面板（M1-8，依据产品文档 6.4 货郎 / 9.2 面板规范 / 6.2 售价公式）。
##
## 两个页签：
##   购买 —— 读 shops.json 的 buyItems，逐项显示名称 / 简介 / 已拥有 / 价格 + 购买按钮；
##   出售 —— 类背包格子面板，点击装备加入出售清单并累计结算金币，可「确认出售」或
##          「一键出售」（6.4：属性高于已穿戴的装备不会被一键出售）。
## 打开方式：靠近货郎按 E（game.gd 派发 EventBus.shop_open_requested）；E / Esc 关闭。
## 与背包面板互斥（EventBus.panel_opened 广播，后开者关闭先开者）。
## 占位素材（R5）：格子以模板名前 2 字 + 品质色描边表现，不加载图标。
## 留待 M4：拖拽出售、卖出高于自身穿戴时的二次确认对话框（6.4）、仓库面板。

const SLOT_MIN := Vector2(46, 46)
const BAG_COLUMNS := 8

const COL_PANEL := Color(0.06, 0.07, 0.09, 0.97)
const COL_BORDER := Color(0.30, 0.33, 0.38, 0.95)
const COL_SLOT_BG := Color(0.13, 0.14, 0.17, 0.95)
const COL_SLOT_EMPTY := Color(0.10, 0.11, 0.13, 0.92)
const COL_SLOT_HOVER := Color(0.20, 0.22, 0.26, 0.98)
const COL_SELECTED := Color(0.95, 0.82, 0.40)
const COL_TEXT := Color(0.90, 0.92, 0.95)
const COL_TEXT_DIM := Color(0.52, 0.55, 0.60)
const COL_GOLD := Color(0.94, 0.78, 0.38)

var _shop_id: String = ""
var _selected: Array[int] = []

var _title: Label
var _gold_label: Label
var _tabs: TabContainer
var _buy_list: VBoxContainer
var _sell_grid: GridContainer
var _sell_buttons: Array[Button] = []
var _sell_summary: Label
var _sell_confirm: Button
var _sell_all: Button

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	visible = false
	EventBus.shop_open_requested.connect(_on_shop_requested)
	EventBus.panel_opened.connect(_on_panel_opened)
	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.inventory_changed.connect(_on_inventory_changed)
	EventBus.equipment_changed.connect(_on_inventory_changed)

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("pause"):
		set_open(false)
		get_viewport().set_input_as_handled()

# ---- 开关 ----

func _on_shop_requested(shop_id: String) -> void:
	_shop_id = shop_id
	set_open(true)

## 开关面板；同步全局面板标志（角色操控在 player.gd 中据此屏蔽）。
func set_open(open: bool) -> void:
	visible = open
	GameState.set_panel_open("shop", open)
	if open:
		_selected.clear()
		EventBus.panel_opened.emit("shop")
		_refresh()

## 其他面板打开时自动关闭本面板（与背包面板互斥）。
func _on_panel_opened(panel_id: String) -> void:
	if panel_id != "shop" and visible:
		set_open(false)

func _on_gold_changed(_amount: int) -> void:
	_refresh_gold()
	# 金币变化影响按钮可用性（金币不足提示）
	if visible:
		_refresh_sell()

func _on_inventory_changed() -> void:
	if visible:
		_refresh()

# ---- 构建 ----

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", _panel_style())
	center.add_child(box)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	box.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	# 标题行：货郎名 + 金币 + 关闭
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	root.add_child(head)
	_title = Label.new()
	_title.text = "货郎"
	_title.add_theme_font_size_override("font_size", 18)
	head.add_child(_title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	_gold_label = Label.new()
	_gold_label.add_theme_font_size_override("font_size", 16)
	_gold_label.add_theme_color_override("font_color", COL_GOLD)
	head.add_child(_gold_label)
	var close := Button.new()
	close.text = "×"
	close.custom_minimum_size = Vector2(32, 28)
	close.pressed.connect(func() -> void: set_open(false))
	head.add_child(close)

	root.add_child(HSeparator.new())

	_tabs = TabContainer.new()
	_tabs.custom_minimum_size = Vector2(760, 400)
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_theme_font_size_override("font_size", 15)
	root.add_child(_tabs)

	_tabs.add_child(_build_buy_page())
	_tabs.add_child(_build_sell_page())
	_tabs.set_tab_title(0, "购买")
	_tabs.set_tab_title(1, "出售")

	var hint := Label.new()
	hint.text = "靠近货郎按 E 开合　·　双击与拖拽出售、高价值装备卖出二次确认见 M4"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", COL_TEXT_DIM)
	root.add_child(hint)

func _build_buy_page() -> Control:
	var page := ScrollContainer.new()
	page.name = "Buy"
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_buy_list = VBoxContainer.new()
	_buy_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_buy_list.add_theme_constant_override("separation", 10)
	page.add_child(_buy_list)
	return page

func _build_sell_page() -> Control:
	var page := VBoxContainer.new()
	page.name = "Sell"
	page.add_theme_constant_override("separation", 8)

	var tip := Label.new()
	tip.text = "点击背包装备加入出售清单（货郎只收购装备；高于已穿戴的不会被一键出售）"
	tip.add_theme_font_size_override("font_size", 12)
	tip.add_theme_color_override("font_color", COL_TEXT_DIM)
	page.add_child(tip)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(scroll)

	_sell_grid = GridContainer.new()
	_sell_grid.columns = BAG_COLUMNS
	_sell_grid.add_theme_constant_override("h_separation", 6)
	_sell_grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(_sell_grid)
	for i in range(GameState.inventory.size()):
		var b := _make_slot()
		b.pressed.connect(_on_sell_slot_pressed.bind(i))
		_sell_grid.add_child(b)
		_sell_buttons.append(b)

	page.add_child(HSeparator.new())

	_sell_summary = Label.new()
	_sell_summary.add_theme_font_size_override("font_size", 14)
	page.add_child(_sell_summary)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	page.add_child(bar)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(sp)
	_sell_all = Button.new()
	_sell_all.text = "一键出售"
	_sell_all.custom_minimum_size = Vector2(110, 32)
	_sell_all.pressed.connect(_on_sell_all_pressed)
	bar.add_child(_sell_all)
	_sell_confirm = Button.new()
	_sell_confirm.text = "确认出售"
	_sell_confirm.custom_minimum_size = Vector2(110, 32)
	_sell_confirm.pressed.connect(_on_confirm_sell_pressed)
	bar.add_child(_sell_confirm)

	return page

func _make_slot() -> Button:
	var b := Button.new()
	b.custom_minimum_size = SLOT_MIN
	b.clip_text = true
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_color_override("font_color", COL_TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_color", COL_TEXT)
	b.add_theme_color_override("font_disabled_color", COL_TEXT_DIM)
	_apply_slot_style(b, COL_BORDER, false)
	return b

func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL
	sb.border_color = COL_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	return sb

func _slot_style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	return sb

func _apply_slot_style(b: Button, border: Color, filled: bool) -> void:
	var bg := COL_SLOT_BG if filled else COL_SLOT_EMPTY
	b.add_theme_stylebox_override("normal", _slot_style(bg, border))
	b.add_theme_stylebox_override("hover", _slot_style(COL_SLOT_HOVER, border))
	b.add_theme_stylebox_override("pressed", _slot_style(bg, border))
	b.add_theme_stylebox_override("focus", _slot_style(Color(0, 0, 0, 0), Color(0, 0, 0, 0)))
	b.add_theme_stylebox_override("disabled", _slot_style(COL_SLOT_EMPTY, Color(COL_BORDER.r, COL_BORDER.g, COL_BORDER.b, 0.5)))

# ---- 刷新 ----

func _refresh() -> void:
	if not visible:
		return
	_title.text = "%s　买卖" % Shop.display_name(_shop_id)
	_refresh_gold()
	_rebuild_buy()
	_refresh_sell()

func _refresh_gold() -> void:
	if _gold_label != null:
		_gold_label.text = "金币  %d" % GameState.gold

func _rebuild_buy() -> void:
	for c in _buy_list.get_children():
		_buy_list.remove_child(c)
		c.queue_free()
	var items := Shop.buy_items(_shop_id)
	if items.is_empty():
		var l := Label.new()
		l.text = "该货郎暂无商品。"
		l.add_theme_color_override("font_color", COL_TEXT_DIM)
		_buy_list.add_child(l)
		return
	for it in items:
		if it is Dictionary:
			_buy_list.add_child(_make_buy_row(it))

func _make_buy_row(e: Dictionary) -> Control:
	var item_id := String(e.get("itemId", ""))
	var price := int(e.get("price", 0))
	var proto := Shop.make_item(item_id)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	row.add_child(info)

	var nm := Label.new()
	nm.text = item_id if proto.is_empty() else ItemUtil.display_name(proto)
	nm.add_theme_font_size_override("font_size", 15)
	info.add_child(nm)

	var desc := Label.new()
	desc.text = "%s　·　已拥有 %d" % [Shop.describe(item_id), _owned_count(item_id)]
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", COL_TEXT_DIM)
	info.add_child(desc)

	var pr := Label.new()
	pr.text = "%d 金币" % price
	pr.custom_minimum_size = Vector2(90, 0)
	pr.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pr.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pr.add_theme_font_size_override("font_size", 15)
	pr.add_theme_color_override("font_color", COL_GOLD if GameState.gold >= price else COL_TEXT_DIM)
	row.add_child(pr)

	var buy := Button.new()
	buy.text = "购买"
	buy.custom_minimum_size = Vector2(72, 30)
	buy.pressed.connect(_on_buy_pressed.bind(item_id))
	row.add_child(buy)

	return row

func _refresh_sell() -> void:
	if _sell_buttons.is_empty():
		return
	for i in range(_sell_buttons.size()):
		var b: Button = _sell_buttons[i]
		var it = GameState.inventory[i] if i < GameState.inventory.size() else null
		var sellable := it is Dictionary and Shop.can_sell(it)
		if it is Dictionary:
			b.text = _short_name(it)
			b.add_theme_color_override("font_color", ItemUtil.quality_color(Shop.item_quality(it)))
			b.tooltip_text = _sell_tooltip(it)
		else:
			b.text = ""
			b.tooltip_text = ""
		b.disabled = not sellable
		var sel := _selected.has(i)
		_apply_slot_style(b, COL_SELECTED if sel else COL_BORDER, it is Dictionary)

	var total := 0
	var n := 0
	for i in _selected:
		var it2 = GameState.inventory[i] if i < GameState.inventory.size() else null
		if it2 is Dictionary:
			total += Shop.sell_price(it2)
			n += 1
	_sell_summary.text = "选中 %d 件　·　结算 %d 金币" % [n, total]
	_sell_confirm.disabled = n == 0
	_sell_all.disabled = GameState.inventory_used() == 0

# ---- 交互 ----

func _on_buy_pressed(item_id: String) -> void:
	GameState.shop_buy(_shop_id, item_id)   # 失败原因由 GameState 广播 toast
	_refresh()

func _on_sell_slot_pressed(index: int) -> void:
	if _selected.has(index):
		_selected.erase(index)
	else:
		_selected.append(index)
	_refresh_sell()

func _on_confirm_sell_pressed() -> void:
	if _selected.is_empty():
		EventBus.toast_requested.emit("请先选择要出售的装备", "danger")
		return
	var idxs := _selected.duplicate()
	var total := 0
	var n := 0
	for i in idxs:
		var res := GameState.shop_sell(int(i), true)   # 静默逐件，末尾汇总一条
		if bool(res.get("ok", false)):
			total += int(res.get("price", 0))
			n += 1
	_selected.clear()
	if n > 0:
		EventBus.toast_requested.emit("出售 %d 件（+%d 金币）" % [n, total], "pickup")
	_refresh()

func _on_sell_all_pressed() -> void:
	GameState.shop_sell_all()
	_selected.clear()
	_refresh()

# ---- 文本 ----

func _short_name(item: Dictionary) -> String:
	var nm: String = ItemUtil.template_name(item)
	return nm.substr(0, 2) if nm.length() > 2 else nm

## 背包内同模板物品总数（含堆叠数量）。
func _owned_count(item_id: String) -> int:
	var n := 0
	for it in GameState.inventory:
		if it is Dictionary and String(it.get("itemId", "")) == item_id:
			n += int(it.get("count", 1))
	return n

func _sell_tooltip(item: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append(ItemUtil.display_name(item))
	lines.append_array(ItemUtil.attr_lines(item))
	lines.append("")
	lines.append("售价 %d 金币" % Shop.sell_price(item))
	if GameState.is_upgrade_over_worn(item):
		lines.append("⚠ 优于已穿戴（一键出售会保留）")
	lines.append("点击加入 / 移出出售清单")
	return "\n".join(PackedStringArray(lines))
