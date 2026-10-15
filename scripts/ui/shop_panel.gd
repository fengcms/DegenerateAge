extends Control
## 货郎商店面板（M1-8；M1-8 追加改造为「双面板 + 拖拽出售」）。
## 依据：产品文档 6.4 货郎 / 9.2 面板规范 / 6.2 售价公式 / 工程文档 05 改造方案。
##
## 两个页签：
##   购买 —— 读 shops.json 的 buyItems，逐项显示名称 / 简介 / 已拥有 / 价格 + 购买按钮；
##   出售 —— **出售托盘**：从左侧背包面板把装备**拖入**托盘暂存（一格一件），
##          托盘内点一下取回；「一键移入」按背包里的等级与成色阈值筛选；
##          「全部取回」清空托盘；「确认出售」才真正结算为金币。
## 打开方式：靠近货郎按 E（game.gd 派发 EventBus.shop_open_requested）；E / Esc 关闭。
## 交易会话：本面板打开时**同时拉起背包面板**并与之并列（本面板居中于右半屏，
##          背包面板居中于左半屏），不互斥——见 EventBus.trade_mode_changed。
## 占位素材（R5）：格子以模板名前 2 字 + 品质色描边表现，不加载图标。
## 留待 M4：手拖优于已穿戴装备时的二次确认对话框（6.4）、仓库面板。

const SLOT_MIN := Vector2(46, 46)
const BUY_ROW_MIN := Vector2(430, 0)
## 出售托盘容量（格）：超过则拒绝继续投放并提示（不静默丢弃）。
const TRAY_COLUMNS := 6
const TRAY_ROWS := 4
const TRADE_GAP := 12.0

const COL_BORDER := Color(0.30, 0.33, 0.38, 0.95)
const COL_SLOT_BG := Color(0.13, 0.14, 0.17, 0.95)
const COL_SLOT_EMPTY := Color(0.10, 0.11, 0.13, 0.92)
const COL_SLOT_HOVER := Color(0.20, 0.22, 0.26, 0.98)
const COL_TEXT := Color(0.90, 0.92, 0.95)
const COL_TEXT_DIM := Color(0.52, 0.55, 0.60)
const COL_GOLD := Color(0.94, 0.78, 0.38)
const COL_WARN := Color(0.92, 0.68, 0.34)

var _shop_id: String = ""
## 交易会话是否进行中（由本面板发起，退出时同步关闭背包面板）。
var _trade_active: bool = false
## 出售托盘：已从背包移出、尚未结算的装备实例（确认出售 / 取回 / 关闭退回见下）。
## 固定格位：键是 0..23 的格下标，值是装备实例；空格不占键。
var _tray: Dictionary = {}

var _title: Label
var _gold_label: Label
var _tabs: TabContainer
var _buy_list: VBoxContainer
var _tray_slots: Array[ItemSlot] = []
var _tray_summary: Label
var _tray_warn: Label
var _confirm_btn: Button
var _stage_all_btn: Button
var _return_all_btn: Button
var _center: CenterContainer
var _box: PanelContainer
var _dim: ColorRect

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# 根节点不吃鼠标：交易会话中与背包面板并列，只有面板本体（PanelContainer）拦截，
	# 否则全屏根节点会把左侧背包面板的点击全部吞掉（见工程文档 05 §3.3）。
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	visible = false
	EventBus.shop_open_requested.connect(_on_shop_requested)
	EventBus.shop_close_requested.connect(_on_shop_close_requested)
	EventBus.panel_opened.connect(_on_panel_opened)
	EventBus.panels_close_requested.connect(func() -> void: set_open(false))
	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.inventory_changed.connect(_on_inventory_changed)
	EventBus.equipment_changed.connect(_on_inventory_changed)
	EventBus.player_leveled.connect(func(_level: int) -> void: _on_inventory_changed())
	resized.connect(func() -> void: _align_trade_windows.call_deferred())
	EventBus.settings_changed.connect(func() -> void: _align_trade_windows.call_deferred())

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

func _on_shop_close_requested() -> void:
	if visible:
		set_open(false)

## 开关面板；同步全局面板标志（角色操控在 player.gd 中据此屏蔽）。
## 开启 = 进入交易会话（拉起背包面板并列）；关闭 = 退出会话 + **托盘内未确认装备退回背包**。
func set_open(open: bool) -> void:
	visible = open
	GameState.set_panel_open("shop", open)
	if open:
		_trade_active = true
		_apply_trade_layout(true)
		EventBus.trade_mode_changed.emit(true)   # 先拉起背包面板
		EventBus.panel_opened.emit("shop")
		_refresh()
		_align_trade_windows.call_deferred()
	else:
		_return_tray()
		_trade_active = false
		EventBus.trade_mode_changed.emit(false)  # 背包回到独立窗口，保持打开
		_apply_trade_layout(false)

## 其他面板打开时自动关闭：货郎自身与「交易会话中的背包」是唯一例外（会话伙伴，见 05 §3.2）。
func _on_panel_opened(panel_id: String) -> void:
	if visible and not (panel_id == "shop" or (_trade_active and panel_id == "inventory")):
		set_open(false)

## 交易布局：右半屏居中 + 隐藏遮罩（两层黑遮罩叠加会把左侧背包面板压暗）。
func _apply_trade_layout(trade: bool) -> void:
	if _center == null:
		return
	_center.anchor_left = 0.0
	_center.anchor_right = 1.0
	_center.offset_left = 0.0
	_center.offset_right = 0.0
	if _dim != null:
		_dim.visible = not trade

## 用两块面板实际最小宽度排布；宽屏不会因「各自半屏居中」拉出大空隙。
func _align_trade_windows() -> void:
	if not _trade_active or not visible or size.x <= 0.0 or _box == null:
		return
	var inventory: Variant = get_node_or_null("../InventoryPanel")
	if inventory == null or inventory._center == null:
		return
	var bag_width: float = inventory._center.panel_box.get_combined_minimum_size().x
	var shop_width: float = _box.get_combined_minimum_size().x
	var left := maxf(0.0, (size.x - bag_width - shop_width - TRADE_GAP) * 0.5)
	var bag_left := minf(left, maxf(0.0, size.x - bag_width))
	# 窄窗口无法并排时允许两窗重叠，优先保证各窗口留在可见区域。
	var shop_left := minf(bag_left + bag_width + TRADE_GAP, maxf(0.0, size.x - shop_width))
	inventory._center.set_docked(true, bag_left / size.x, (bag_left + bag_width) / size.x)
	_center.anchor_left = shop_left / size.x
	_center.anchor_right = (shop_left + shop_width) / size.x
	_center.offset_left = 0.0
	_center.offset_right = 0.0

func _on_gold_changed(_amount: int) -> void:
	_refresh_gold()
	if visible:
		_refresh_buy_prices()

func _on_inventory_changed() -> void:
	if visible:
		_refresh()

# ---- 构建 ----

func _build() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.35)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)

	_center = CenterContainer.new()
	_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_center)

	var box := PanelChrome.new()
	_box = box
	_center.add_child(box)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 12)
	box.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	# 标题行：货郎名 + 金币 + 关闭
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	root.add_child(head)
	PanelChrome.style_header_layout(margin, head)
	_title = Label.new()
	_title.text = Localization.tr_key("ui.shop_panel.p001")
	_title.add_theme_font_size_override("font_size", 18)
	head.add_child(_title)
	PanelChrome.style_title(_title)
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
	PanelChrome.style_close(close)

	root.add_child(PanelChrome.make_title_gap())

	_tabs = TabContainer.new()
	_tabs.custom_minimum_size = Vector2(BUY_ROW_MIN.x, 400)
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_theme_font_size_override("font_size", 15)
	root.add_child(_tabs)
	PanelChrome.style_tabs(_tabs)

	_tabs.add_child(_build_buy_page())
	_tabs.add_child(_build_sell_page())
	_tabs.set_tab_title(0, Localization.tr_key("ui.shop_panel.p002"))
	_tabs.set_tab_title(1, Localization.tr_key("ui.shop_panel.p003"))

	var hint := Label.new()
	hint.text = Localization.tr_key("ui.shop_panel.p004")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", COL_TEXT_DIM)
	root.add_child(hint)

## 构建购买列表的纵向滚动容器；商品说明须在容器宽度内换行，不启用横向滚动。
func _build_buy_page() -> Control:
	var page := ScrollContainer.new()
	page.name = "Buy"
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
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
	tip.text = Localization.tr_key("ui.shop_panel.p005")
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.add_theme_font_size_override("font_size", 12)
	tip.add_theme_color_override("font_color", COL_TEXT_DIM)
	page.add_child(tip)

	_tray_grid_holder(page)

	page.add_child(HSeparator.new())

	_tray_summary = Label.new()
	_tray_summary.add_theme_font_size_override("font_size", 14)
	page.add_child(_tray_summary)

	_tray_warn = Label.new()
	_tray_warn.add_theme_font_size_override("font_size", 12)
	_tray_warn.add_theme_color_override("font_color", COL_WARN)
	page.add_child(_tray_warn)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	page.add_child(bar)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(sp)
	_return_all_btn = Button.new()
	_return_all_btn.text = Localization.tr_key("ui.shop_panel.p006")
	_return_all_btn.custom_minimum_size = Vector2(96, 32)
	_return_all_btn.pressed.connect(_on_return_all_pressed)
	bar.add_child(_return_all_btn)
	PanelChrome.style_action(_return_all_btn)
	_stage_all_btn = Button.new()
	_stage_all_btn.text = Localization.tr_key("ui.shop_panel.p007")
	_stage_all_btn.tooltip_text = Localization.tr_key("ui.shop_panel.p008")
	_stage_all_btn.custom_minimum_size = Vector2(96, 32)
	_stage_all_btn.pressed.connect(_on_stage_all_pressed)
	bar.add_child(_stage_all_btn)
	PanelChrome.style_action(_stage_all_btn)
	_confirm_btn = Button.new()
	_confirm_btn.text = Localization.tr_key("ui.shop_panel.p009")
	_confirm_btn.custom_minimum_size = Vector2(96, 32)
	_confirm_btn.pressed.connect(_on_confirm_pressed)
	bar.add_child(_confirm_btn)
	PanelChrome.style_action(_confirm_btn, true)

	return page

## 出售托盘：TRAY_COLUMNS × TRAY_ROWS 个可接收投放的格子（ItemSlot.ROLE_TRAY）。
## 用两侧弹性空白把网格居中（比 size_flags 收缩更可控，不会随面板变宽而左贴）。
func _tray_grid_holder(page: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	page.add_child(row)
	var pad_l := Control.new()
	pad_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(pad_l)

	var grid := ShopTrayGrid.new()
	grid.columns = TRAY_COLUMNS
	grid.mouse_filter = Control.MOUSE_FILTER_STOP
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	grid.item_dropped.connect(_on_tray_drop)
	row.add_child(grid)

	var pad_r := Control.new()
	pad_r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(pad_r)
	for i in range(TRAY_COLUMNS * TRAY_ROWS):
		var b := ItemSlot.new()
		b.role = ItemSlot.ROLE_TRAY
		b.index = i
		b.custom_minimum_size = SLOT_MIN
		b.clip_text = true
		b.add_theme_font_size_override("font_size", 13)
		b.add_theme_color_override("font_color", COL_TEXT)
		b.add_theme_color_override("font_hover_color", Color.WHITE)
		_apply_slot_style(b, COL_BORDER, false)
		b.item_dropped.connect(_on_tray_drop)
		b.pressed.connect(_on_tray_slot_pressed.bind(i))
		grid.add_child(b)
		_tray_slots.append(b)

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
	_title.text = PanelChrome.title_text(Localization.tr_key("ui.shop_panel.p010") % Shop.display_name(_shop_id))
	_refresh_gold()
	_rebuild_buy()
	_refresh_tray()

func _refresh_gold() -> void:
	if _gold_label != null:
		_gold_label.text = Localization.tr_key("ui.shop_panel.p011") % GameState.gold

func _rebuild_buy() -> void:
	for c in _buy_list.get_children():
		_buy_list.remove_child(c)
		c.queue_free()
	var items := Shop.buy_items(_shop_id)
	if items.is_empty():
		var l := Label.new()
		l.text = Localization.tr_key("ui.shop_panel.p012")
		l.add_theme_color_override("font_color", COL_TEXT_DIM)
		_buy_list.add_child(l)
		return
	for it in items:
		if it is Dictionary:
			_buy_list.add_child(_make_buy_row(it))

## 金币变化时遍历商品行内的价格标签并更新颜色，不重建整页。
func _refresh_buy_prices() -> void:
	if _buy_list == null:
		return
	for row in _buy_list.get_children():
		for c in row.find_children("*", "Label", true, false):
			if c is Label and String(c.get_meta("role", "")) == "price":
				var price := int(c.get_meta("price", 0))
				c.add_theme_color_override("font_color", COL_GOLD if GameState.gold >= price else COL_TEXT_DIM)

## 商品名称、价格和按钮同排；较长说明单独占下一行，避免把购买按钮挤出滚动视口。
func _make_buy_row(e: Dictionary) -> Control:
	var item_id := String(e.get("itemId", ""))
	var price := int(e.get("price", 0))
	var proto := Shop.make_item(item_id)

	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	var headline := HBoxContainer.new()
	headline.add_theme_constant_override("separation", 10)
	row.add_child(headline)

	var nm := Label.new()
	nm.text = item_id if proto.is_empty() else ItemUtil.display_name(proto)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.add_theme_font_size_override("font_size", 15)
	headline.add_child(nm)

	var desc := Label.new()
	desc.text = Localization.tr_key("ui.shop_panel.p013") % [Shop.describe(item_id), _owned_count(item_id)]
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", COL_TEXT_DIM)
	row.add_child(desc)

	var pr := Label.new()
	pr.text = Localization.tr_key("ui.shop_panel.p014") % price
	pr.custom_minimum_size = Vector2(90, 0)
	pr.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pr.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pr.add_theme_font_size_override("font_size", 15)
	pr.add_theme_color_override("font_color", COL_GOLD if GameState.gold >= price else COL_TEXT_DIM)
	pr.set_meta("role", "price")
	pr.set_meta("price", price)
	headline.add_child(pr)

	var buy := Button.new()
	buy.text = Localization.tr_key("ui.shop_panel.p002")
	buy.custom_minimum_size = Vector2(72, 30)
	buy.pressed.connect(_on_buy_pressed.bind(item_id))
	headline.add_child(buy)
	PanelChrome.style_action(buy, true)

	return row

func _refresh_tray() -> void:
	if _tray_slots.is_empty():
		return
	for i in range(_tray_slots.size()):
		var b: ItemSlot = _tray_slots[i]
		if _tray.has(i):
			var it: Dictionary = _tray[i]
			b.item = it
			b.text = _short_name(it)
			b.add_theme_color_override("font_color", ItemUtil.quality_color(Shop.item_quality(it)))
			_apply_slot_style(b, ItemUtil.quality_color(Shop.item_quality(it)), true)
			b.tooltip_text = _tray_tooltip(it)
		else:
			b.item = {}
			b.text = ""
			_apply_slot_style(b, COL_BORDER, false)
			b.tooltip_text = Localization.tr_key("ui.shop_panel.p015")

	var total := 0
	var upgraded := 0
	for it2 in _tray.values():
		total += Shop.sell_price(it2)
		if GameState.is_upgrade_over_worn(it2):
			upgraded += 1
	_tray_summary.text = Localization.tr_key("ui.shop_panel.p016") % [_tray.size(), _tray_slots.size(), total]
	_tray_warn.text = (Localization.tr_key("ui.shop_panel.p017") % upgraded) if upgraded > 0 else ""
	_confirm_btn.disabled = _tray.is_empty()
	_stage_all_btn.disabled = GameState.inventory_used() == 0
	_return_all_btn.disabled = _tray.is_empty()

# ---- 交互 ----

func _on_buy_pressed(item_id: String) -> void:
	GameState.shop_buy(_shop_id, item_id)   # 失败原因由 GameState 广播 toast
	_refresh()

## 托盘收到背包格的拖入（ItemSlot.item_dropped）。载荷携带背包下标与物品实例；
## 这里**以实例反查实时下标**取出，避免拖拽期间其他变动导致的下标位移误移（工程文档 05 🔴R1）。
func _on_tray_drop(tray_index: int, payload: Dictionary) -> void:
	var item: Dictionary = payload.get("item", {})
	if item.is_empty():
		return
	if tray_index < 0 or tray_index >= _tray_slots.size():
		return
	if not Shop.can_sell(item):
		EventBus.toast_requested.emit(Localization.tr_key("ui.shop_panel.p018"), "danger")
		return
	if _tray.size() >= _tray_slots.size():
		EventBus.toast_requested.emit(Localization.tr_key("ui.shop_panel.p019") % _tray_slots.size(), "danger")
		return
	if _tray.has(tray_index):
		EventBus.toast_requested.emit(Localization.tr_key("ui.shop.tray_occupied"), "danger")
		return
	var idx := _index_of_instance(String(item.get("instanceId", "")))
	if idx < 0:
		EventBus.toast_requested.emit(Localization.tr_key("ui.shop_panel.p020"), "danger")
		_refresh()
		return
	var taken := GameState.remove_item_at(idx)
	if taken.is_empty():
		_refresh()
		return
	_tray[tray_index] = taken
	_refresh_tray()

## 点托盘格：把该件取回背包（背包满则拒绝，不静默丢失）。
func _on_tray_slot_pressed(tray_index: int) -> void:
	if not _tray.has(tray_index):
		return
	var one: Array = [_tray[tray_index]]
	var back := GameState.shop_unstage(one)
	if back == 0:
		EventBus.toast_requested.emit(Localization.tr_key("ui.shop_panel.p021"), "danger")
		return
	_tray.erase(tray_index)
	_refresh_tray()

## 一键移入（6.4）：按背包筛选阈值批量移入托盘空格，穿戴评分不参与筛选。
func _on_stage_all_pressed() -> void:
	var moved := 0
	var full := false
	var i := GameState.inventory.size() - 1
	while i >= 0:
		var it = GameState.inventory[i]
		if not (it is Dictionary) or not GameState.is_low_gear(it):
			i -= 1
			continue
		var free_slot := _first_free_tray_slot()
		if free_slot < 0:
			full = true
			break
		var taken := GameState.remove_item_at(i)
		if not taken.is_empty():
			_tray[free_slot] = taken
			moved += 1
		i -= 1
	var msg := Localization.tr_key("ui.shop.staged_count") % moved
	if full:
		msg += Localization.tr_key("ui.shop.tray_full_suffix")
	EventBus.toast_requested.emit(msg if moved > 0 else Localization.tr_key("ui.shop_panel.p023"), "pickup" if moved > 0 else "danger")
	_refresh_tray()

## 全部取回：清空托盘退回背包。
func _on_return_all_pressed() -> void:
	var back := _return_tray()
	if back > 0:
		EventBus.toast_requested.emit(Localization.tr_key("ui.shop_panel.p024") % back, "info")
	_refresh_tray()

func _on_confirm_pressed() -> void:
	if _tray.is_empty():
		EventBus.toast_requested.emit(Localization.tr_key("ui.shop_panel.p025"), "danger")
		return
	var res := GameState.shop_sell_staged(_tray.values())
	var n := int(res.get("count", 0))
	var gold := int(res.get("gold", 0))
	_tray.clear()
	if n > 0:
		EventBus.toast_requested.emit(Localization.tr_key("ui.shop_panel.p026") % [n, gold], "pickup")
	_refresh_tray()

## 把托盘内装备退回背包（关闭面板 / 全部取回）。返回退回件数；背包满的件保留在托盘。
func _return_tray() -> int:
	if _tray.is_empty():
		return 0
	var back := 0
	for slot_id in _tray.keys():
		var one: Array = [_tray[slot_id]]
		if GameState.shop_unstage(one) == 1:
			_tray.erase(slot_id)
			back += 1
	if not _tray.is_empty():
		EventBus.toast_requested.emit(Localization.tr_key("ui.shop_panel.p027") % _tray.size(), "danger")
	return back

func _first_free_tray_slot() -> int:
	for i in range(_tray_slots.size()):
		if not _tray.has(i):
			return i
	return -1

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

## 按实例 id 反查背包实时下标（-1 = 不在背包）。
func _index_of_instance(instance_id: String) -> int:
	if instance_id.is_empty():
		return -1
	for i in range(GameState.inventory.size()):
		var it = GameState.inventory[i]
		if it is Dictionary and String(it.get("instanceId", "")) == instance_id:
			return i
	return -1

func _tray_tooltip(item: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append(ItemUtil.display_name(item))
	lines.append_array(ItemUtil.attr_lines(item))
	lines.append("")
	lines.append(Localization.tr_key("ui.shop_panel.p028") % Shop.sell_price(item))
	if GameState.is_upgrade_over_worn(item):
		lines.append(Localization.tr_key("ui.shop_panel.p029"))
	lines.append(Localization.tr_key("ui.shop_panel.p030"))
	return "\n".join(PackedStringArray(lines))
