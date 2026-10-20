extends Control
## 货郎商店面板（M1-8；M1-8 追加改造为「双面板 + 拖拽出售」）。
## 依据：产品文档 6.4 货郎 / 9.2 面板规范 / 6.2 售价公式 / 工程文档 05 改造方案。
##
## 两个页签：
##   购买 —— 读 shops.json 的 buyItems，逐项显示名称 / 简介 / 已拥有 / 价格 + 购买按钮；
##   出售 —— **出售托盘**：从左侧背包面板把**物品**（装备 / 药水 / 杂项 / 如意）**拖入**托盘暂存
##          （一格一件，堆叠品整叠一格）；托盘内点一下取回；
##          「挑选装备」按预设预选、逐件勾选后暂存，「一键移入材料」批量收药水 / 材料 / 如意；
##          「全部取回」清空托盘；「确认出售」才真正结算为金币。
## 收购口径（工程文档 39，2026-10-17 修订）：装备 / 药水 / 杂项 / 如意全部收购；
##          任务物品（`questItem`）与无价物品不收；非装备按 0.6 回收比例结算。
## 打开方式：靠近货郎按 E（game.gd 派发 EventBus.shop_open_requested）；E / Esc 关闭。
## 交易会话：本面板打开时**同时拉起背包面板**并与之并列（本面板居中于右半屏，
##          背包面板居中于左半屏），不互斥——见 EventBus.trade_mode_changed。
## 占位素材（R5）：格子以模板名前 2 字 + 品质色描边表现，不加载图标。
## 手拖或批量暂存的高价值装备在最终结算前仍需二次确认。

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
## 出售托盘：已从背包移出、尚未结算的物品实例（确认出售 / 取回 / 关闭退回见下）。
## 固定格位：键是 0..23 的格下标，值是物品实例；空格不占键。
var _tray: Dictionary = {}
## 托盘内物品是用哪个预设暂存的（空 = 读存档设置）。「暴力」一次性预设靠它一路传到结算，
## 结算前的风险确认据此跳过 —— 否则刚从暴力清单搬进来的装备会被再拦一次。
var _tray_preset: String = ""
var _sale_risk_confirmed := false

var _title: Label
var _gold_label: Label
var _tabs: TabContainer
var _buy_list: VBoxContainer
var _tray_slots: Array[ItemSlot] = []
var _tray_summary: Label
var _tray_warn: Label
var _confirm_btn: Button
var _stage_all_btn: Button
var _stage_potions_btn: Button
var _return_all_btn: Button
var _center: CenterContainer
var _box: PanelContainer
var _scroll: ScrollContainer
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
	resized.connect(func() -> void: _update_layout.call_deferred())
	EventBus.settings_changed.connect(func() -> void: _update_layout.call_deferred())

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

## 开关面板；同步全局可见面板集合，交易会话仅暂停自动战斗决策。
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
		_update_layout.call_deferred()
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

## F-P2-3：先把面板收敛到逻辑视口内（超出的商品页交给滚动条），再按收敛后的
## 实际宽度并列排布。两者顺序不可交换——`_align_trade_windows` 依赖收敛后的宽度。
func _update_layout() -> void:
	if _box == null or _scroll == null:
		return
	FloatingWindow.fit_content(size, _box, _scroll)
	_align_trade_windows()

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
	# 与背包并排的「窗口」语义：点谁谁到前面来（工程 74）。
	FloatingWindow.enable_click_to_front(self, box)

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

	# F-P2-3：标题行留在外框渐变带内，页签与提示整体可滚动。
	# 工程 60：内容只允许纵向滚动。横向滚动在本面板里是**纯破坏性**的 ——
	# 托盘靠两侧弹性空白居中，一旦内容比视口宽，网格就会整体右移、右侧列被裁到视口外
	# （出售页暂存多件装备时的「界面变形」就是这么来的）。内容宽度必须由换行保证，不靠滚动兜底。
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_scroll)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(content)
	_box.minimum_size_changed.connect(func() -> void: _update_layout.call_deferred())

	_tabs = TabContainer.new()
	_tabs.custom_minimum_size = Vector2(BUY_ROW_MIN.x, 400)
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_theme_font_size_override("font_size", 15)
	content.add_child(_tabs)
	PanelChrome.style_tabs(_tabs)

	_tabs.add_child(_build_buy_page())
	_tabs.add_child(_build_sell_page())
	_tabs.set_tab_title(0, Localization.tr_key("ui.shop_panel.p002"))
	_tabs.set_tab_title(1, Localization.tr_key("ui.shop_panel.p003"))
	# 工程 60：`TabContainer` 的最小尺寸只统计**当前可见页**，切页会改变整块内容的最小宽高；
	# 不接这支信号，切到出售页后外层既不会重算滚动区、也不会重排并列窗口。
	_tabs.tab_changed.connect(func(_tab: int) -> void: _update_layout.call_deferred())

	var hint := Label.new()
	hint.text = Localization.tr_key("ui.shop_panel.p004")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", COL_TEXT_DIM)
	content.add_child(hint)

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

	# 工程 60：这两行是**唯一会随件数线性变长**的文本（件数 + 金币位数 + 装备名单）。
	# 不换行时 Label 的最小宽度等于整行宽度，会把出售页撑到视口之外 —— 必须换行并撑满。
	_tray_summary = Label.new()
	_tray_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tray_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tray_summary.add_theme_font_size_override("font_size", 14)
	page.add_child(_tray_summary)

	_tray_warn = Label.new()
	_tray_warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tray_warn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tray_warn.add_theme_font_size_override("font_size", 12)
	_tray_warn.add_theme_color_override("font_color", COL_WARN)
	page.add_child(_tray_warn)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	page.add_child(bar)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(sp)
	# 工程 39 D-5-A：四个按钮同宽 92（92×4 + 8×3 = 392 ≤ BUY_ROW_MIN.x 430 − 左右边距），
	# 面板最小宽度不撑破（RK-9）；字号 13 保证「一键移入材料」六字不截断。
	_return_all_btn = Button.new()
	_return_all_btn.text = Localization.tr_key("ui.shop_panel.p006")
	_return_all_btn.custom_minimum_size = Vector2(92, 32)
	_return_all_btn.add_theme_font_size_override("font_size", 13)
	_return_all_btn.pressed.connect(_on_return_all_pressed)
	bar.add_child(_return_all_btn)
	PanelChrome.style_action(_return_all_btn)
	_stage_all_btn = Button.new()
	_stage_all_btn.text = Localization.tr_key("ui.shop_panel.p007")
	_stage_all_btn.tooltip_text = Localization.tr_key("ui.shop_panel.p008")
	_stage_all_btn.custom_minimum_size = Vector2(92, 32)
	_stage_all_btn.add_theme_font_size_override("font_size", 13)
	_stage_all_btn.pressed.connect(_on_stage_all_pressed)
	bar.add_child(_stage_all_btn)
	PanelChrome.style_action(_stage_all_btn)
	_stage_potions_btn = Button.new()
	_stage_potions_btn.text = Localization.tr_key("ui.shop_panel.stage_potions")
	_stage_potions_btn.tooltip_text = Localization.tr_key("ui.shop_panel.stage_potions_tip")
	_stage_potions_btn.custom_minimum_size = Vector2(92, 32)
	_stage_potions_btn.add_theme_font_size_override("font_size", 13)
	_stage_potions_btn.pressed.connect(_on_stage_potions_pressed)
	bar.add_child(_stage_potions_btn)
	PanelChrome.style_action(_stage_potions_btn)
	_confirm_btn = Button.new()
	_confirm_btn.text = Localization.tr_key("ui.shop_panel.p009")
	_confirm_btn.custom_minimum_size = Vector2(92, 32)
	_confirm_btn.add_theme_font_size_override("font_size", 13)
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
	_title.text = PanelChrome.title_text(Localization.tr_key("ui.shop_panel.p010") % _shop_title_name())
	_refresh_gold()
	_rebuild_buy()
	_refresh_tray()

func _refresh_gold() -> void:
	if _gold_label != null:
		_gold_label.text = Localization.tr_key("ui.shop_panel.p011") % GameState.gold

## 标题里的店名。随身商队是合成店铺（`shop_id` 不在 `shops.json` 里），
## 名称走本地化 key；普通货郎继续读数据里的 `name`。`Shop` 因此保持零本地化依赖。
func _shop_title_name() -> String:
	if Shop.is_portable(_shop_id):
		return Localization.tr_key("ui.panel.portable_shop")
	return Shop.display_name(_shop_id)

func _rebuild_buy() -> void:
	for c in _buy_list.get_children():
		_buy_list.remove_child(c)
		c.queue_free()
	var items := Shop.buy_items(_shop_id)
	# 随身商队按模板价上浮 20%（D-14）：不写这一行，玩家只会看到「比营地贵」而无从判断。
	if Shop.is_portable(_shop_id):
		var hint := Label.new()
		hint.text = Localization.tr_key("ui.shop_panel.p031")
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.add_theme_font_size_override("font_size", 12)
		hint.add_theme_color_override("font_color", COL_TEXT_DIM)
		_buy_list.add_child(hint)
		_buy_list.add_child(_make_repair_row())
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
## 随身商店修理行（工程 77）：1.5× 便利费，铁匠 1.0× 仍是回城最优解。
func _make_repair_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var desc := Label.new()
	desc.text = Localization.tr_key("ui.shop_panel.repair_desc")
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc.add_theme_font_size_override("font_size", 13)
	row.add_child(desc)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(120, 32)
	btn.add_theme_font_size_override("font_size", 13)
	var maximum := Durability.max_durability()
	var total := 0
	var damaged := 0
	for slot_id in GameState.equipment.keys():
		var it = GameState.equipment[slot_id]
		if not it is Dictionary:
			continue
		var missing := maximum - Durability.current(it)
		if missing <= 0:
			continue
		damaged += 1
		var full := Durability.repair_full_price(it)
		if full >= 0:
			total += maxi(1, int(ceil(float(full) * float(missing) / float(maximum))))
	total = maxi(1, int(round(float(total) * 1.5))) if damaged > 0 else 0
	if damaged == 0:
		btn.text = Localization.tr_key("ui.blacksmith_panel.repair_full")
		btn.disabled = true
	else:
		btn.text = Localization.tr_key("ui.shop_panel.repair_cost", [total])
		btn.pressed.connect(func() -> void:
			var result := GameState.repair_equipment(1.5)
			if bool(result.get("ok", false)):
				EventBus.toast_requested.emit(Localization.tr_key("ui.durability.repair_done",
					[int(result.get("repaired", 0)), int(result.get("cost", 0))]), "pickup")
			else:
				EventBus.toast_requested.emit(String(result.get("reason", "修理失败")), "danger")
			_rebuild_buy())
	row.add_child(btn)
	return row

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
	_sale_risk_confirmed = false
	GameState.set_trade_staged_count(_tray.size())   # E-P3-4：供 SaveManager 挂起自动存档
	if _tray_slots.is_empty():
		return
	for i in range(_tray_slots.size()):
		var b: ItemSlot = _tray_slots[i]
		if _tray.has(i):
			var it: Dictionary = _tray[i]
			var tint := _item_tint(it)
			b.item = it
			b.text = _short_name(it)
			b.add_theme_color_override("font_color", tint)
			_apply_slot_style(b, tint, true)
			b.tooltip_text = _tray_tooltip(it)
		else:
			b.item = {}
			b.text = ""
			_apply_slot_style(b, COL_BORDER, false)
			b.tooltip_text = Localization.tr_key("ui.shop_panel.p015")

	var total := 0
	var upgraded := 0
	var runes := 0
	for it2 in _tray.values():
		total += Shop.sell_price(it2)
		if GameState.is_upgrade_over_worn(it2):
			upgraded += 1
		if String((it2 as Dictionary).get("kind", "")) == "rune":
			runes += 1
	_tray_summary.text = Localization.tr_key("ui.shop_panel.p016") % [_tray.size(), _tray_slots.size(), total]
	# 告警行：升级件（6.4 二次确认）与升星材料（工程 39 D-6）互不覆盖，各占一行。
	var warns: Array[String] = []
	if upgraded > 0:
		warns.append(Localization.tr_key("ui.shop_panel.p017") % upgraded)
	if runes > 0:
		warns.append(Localization.tr_key("ui.shop_panel.warn_rune") % runes)
	_tray_warn.text = "\n".join(PackedStringArray(warns))
	_confirm_btn.disabled = _tray.is_empty()
	_stage_all_btn.disabled = GameState.inventory_used() == 0
	_stage_potions_btn.disabled = not _has_stageable_potion()
	_return_all_btn.disabled = _tray.is_empty()

## 托盘格描边 / 文字色：装备按品质，其余按品类（药水红 / 如意青 / 材料土黄）。
func _item_tint(item: Dictionary) -> Color:
	var kind := String(item.get("kind", ""))
	if kind == "equip":
		return ItemUtil.quality_color(Shop.item_quality(item))
	return ItemUtil.kind_color(kind)

# ---- 交互 ----

func _on_buy_pressed(item_id: String) -> void:
	GameState.shop_buy(_shop_id, item_id)   # 失败原因由 GameState 广播 toast
	_refresh()

## 托盘收到背包格的拖入（ItemSlot.item_dropped）。载荷携带背包下标与物品实例；
## 这里**以载荷下标 + 逐字段核对**取出，避免拖拽期间其他变动导致的下标位移误移（工程文档 05 🔴R1）。
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
	var idx := _resolve_source_index(payload)
	if idx < 0:
		EventBus.toast_requested.emit(Localization.tr_key("ui.shop_panel.p020"), "danger")
		_refresh()
		return
	var taken := GameState.remove_item_at(idx)
	if taken.is_empty():
		_refresh()
		return
	_tray[tray_index] = taken
	# 手动拖入的装备不来自任何预设清单；混入后整批按存档预设重新判风险。
	_tray_preset = ""
	_refresh_tray()

## 反查拖入源在背包中的实时下标（-1 = 已不在背包）。
## 工程 39 G9：药水 / 材料**没有 instanceId**（实例只有 kind / itemId / count），
## 旧实现只按 instanceId 反查 ⇒ 放行后一律判「已不在背包」，整类物品拖不进托盘。
## 故优先用载荷自带的背包下标并逐字段核对；核对失败再回退 instanceId（装备 / 仓库来源）。
func _resolve_source_index(payload: Dictionary) -> int:
	var item: Dictionary = payload.get("item", {})
	var idx := int(payload.get("index", -1))
	if idx >= 0 and idx < GameState.inventory.size():
		var cur = GameState.inventory[idx]
		if cur is Dictionary and _same_item(cur, item):
			return idx
	return _index_of_instance(String(item.get("instanceId", "")))

## 载荷与背包实时项是否为同一件（种类 / 模板 / 数量 / 实例 id 全等）。
static func _same_item(a: Dictionary, b: Dictionary) -> bool:
	return String(a.get("kind", "")) == String(b.get("kind", "")) \
		and String(a.get("itemId", "")) == String(b.get("itemId", "")) \
		and int(a.get("count", 1)) == int(b.get("count", 1)) \
		and String(a.get("instanceId", "")) == String(b.get("instanceId", ""))

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

## 装备批量暂存先展示共用清单，避免旧数字阈值绕过逐件核对。
func _on_stage_all_pressed() -> void:
	EquipmentSalePreview.open_for(self, EquipmentSalePreview.STAGE)

## 清单最终确认后再同步移走背包装备，现有托盘物品和格位均不变。
## `preset_override` 来自出售预览窗：暴力是一次性预设，不写存档，只能随这次调用传进来。
func _stage_selected_equipment(rows: Array[Dictionary], allow_risky: bool,
		preset_override: String = "") -> Dictionary:
	if not visible or not _trade_active or not Shop.sell_enabled(_shop_id):
		return {"ok": false, "reason": "货郎交易已结束，请重新打开"}
	var free_slots := _tray_slots.size() - _tray.size()
	var result := GameState.take_equipment_for_sale(rows, free_slots, allow_risky, preset_override)
	if not bool(result.get("ok", false)):
		return result
	_tray_preset = preset_override
	for item in result.items:
		var free_slot := _first_free_tray_slot()
		_tray[free_slot] = item
	_refresh_tray()
	return result

## 一键移入药品（工程 61）：只搬**药水**，任务物品不收。
## 原「一键移入材料」会把杂项（卷轴、传送符）与如意一起搬走 —— 卷轴随时可能要用，
## 如意是升星材料，误卖的代价远高于药水，故一并退出自动勾选。
func _on_stage_potions_pressed() -> void:
	var moved := 0
	var full := false
	var i := GameState.inventory.size() - 1
	while i >= 0:
		var it = GameState.inventory[i]
		if not (it is Dictionary) or not _is_stageable_potion(it):
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
	EventBus.toast_requested.emit(msg if moved > 0 else Localization.tr_key("ui.shop_panel.no_potions"),
		"pickup" if moved > 0 else "danger")
	_refresh_tray()

## 可批量移入的「药品」：只有药水，且当前可售（排除任务物品与无价物品）。
func _is_stageable_potion(item: Dictionary) -> bool:
	return String(item.get("kind", "")) == "potion" and Shop.can_sell(item)

func _has_stageable_potion() -> bool:
	for it in GameState.inventory:
		if it is Dictionary and _is_stageable_potion(it):
			return true
	return false

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
	if not _sale_risk_confirmed:
		var risky_names := _risky_sale_names()
		if not risky_names.is_empty():
			_sale_risk_confirmed = true
			_append_warn_line(Localization.tr_key("ui.sale_preview.risk",
				[EquipmentSalePreview.risk_names_text(risky_names)]))
			return
	var res := GameState.shop_sell_staged(_tray.values())
	if not bool(res.get("ok", false)):
		EventBus.toast_requested.emit(String(res.get("reason", "出售失败，请重新核对")), "danger")
		return
	var n := int(res.get("count", 0))
	var gold := int(res.get("gold", 0))
	_tray.clear()
	_tray_preset = ""
	if n > 0:
		EventBus.toast_requested.emit(Localization.tr_key("ui.shop_panel.p026") % [n, gold], "pickup")
		# 工程 56 口径 A：金币满额照卖不拒，差额在这里补一句（先报件数与入账，再报缺口）。
		if bool(res.get("capped", false)):
			EventBus.toast_requested.emit(Localization.tr_key("msg.game_state.p054"), "danger")
	_refresh_tray()

## 向告警区追加一行。工程 60：原先直接 `+= "\n" + line`，告警区为空时会留下一个开头空行。
func _append_warn_line(line: String) -> void:
	if _tray_warn.text.is_empty():
		_tray_warn.text = line
	else:
		_tray_warn.text += "\n" + line

## 货郎最终结算前重新检查托盘中预设不会自动选中的装备；手动拖入也适用。
## 暴力预设下整批本来就是玩家一次性清包的结果，不再逐件拦（与「不提示不确认」一致）。
func _risky_sale_names() -> Array[String]:
	var names: Array[String] = []
	if _tray_preset == SellGearPolicy.BRUTAL:
		return names
	var preset := String(GameState.settings.get("sellGearPreset", SellGearPolicy.CAUTIOUS))
	for item in _tray.values():
		if not item is Dictionary or String(item.get("kind", "")) != "equip":
			continue
		var row := SellGearPolicy.entry(item, -1, int(GameState.player.get("level", 1)),
			GameState.equipment, preset)
		if not bool(row.get("default_selected", false)):
			names.append(ItemUtil.display_name(item))
	return names

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
	# E-P3-4：关闭面板走的是「退回但不刷新 UI」这条路，必须在此同步暂存件数，
	# 否则托盘已空而计数滞留 > 0，自动存档会被永久挂起。
	GameState.set_trade_staged_count(_tray.size())
	if _tray.is_empty():
		_tray_preset = ""
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
	var count := maxi(1, int(item.get("count", 1)))
	if String(item.get("kind", "")) != "equip" and count > 1:
		lines.append(Localization.tr_key("ui.shop_panel.unit_price") % [_unit_price(item), count])
	lines.append(Localization.tr_key("ui.shop_panel.p028") % Shop.sell_price(item))
	if String(item.get("kind", "")) == "rune":
		lines.append(Localization.tr_key("ui.shop_panel.rune_note"))
	if GameState.is_upgrade_over_worn(item):
		lines.append(Localization.tr_key("ui.shop_panel.p029"))
	lines.append(Localization.tr_key("ui.shop_panel.p030"))
	return "\n".join(PackedStringArray(lines))

## 单件售价：直接按「一件」重算。不可用整叠总价 ÷ 数量 —— 单价先行取整，反推会有误差。
func _unit_price(item: Dictionary) -> int:
	var one := item.duplicate(true)
	one["count"] = 1
	return Shop.sell_price(one)
