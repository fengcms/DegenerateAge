extends Control
## 仓库：背包 / 仓库双栏，物品双击或拖放存取，金币扩容。

const PANEL_ID := "warehouse"
const COLUMNS := 8
const DOUBLE_CLICK_MS := 400
const SLOT_MIN := Vector2(46, 46)
## 双栏标题、计数、详情、兑换区和底部操作所占的逻辑高度；缩放时优先缩短滚动区。
## 109 新增兑换区（标题 + 按钮行 + 两处 separation）约占 64px，230 → 294。
const WAREHOUSE_VERTICAL_CHROME_BUDGET := 294.0

## 兑换按钮顺序与文案键（工程 109）。顺序 = 玩家自然动线：先换条、再合砖、再兑回。
const EXCHANGE_ROWS := [
	["gold_to_ingot", "ui.warehouse_panel.p017"],
	["ingot_to_brick", "ui.warehouse_panel.p018"],
	["ingot_to_gold", "ui.warehouse_panel.p019"],
	["brick_to_gold", "ui.warehouse_panel.p020"],
]

var _title: Label
var _bag_count: Label
var _store_count: Label
var _bag_organize: Button
var _store_organize: Button
var _gold: Label
var _detail: Label
var _expand: Button
var _bag_grid: GridContainer
var _store_grid: GridContainer
var _bag_scroll: ScrollContainer
var _store_scroll: ScrollContainer
var _bag_slots: Array[ItemSlot] = []
var _store_slots: Array[ItemSlot] = []
var _last_side := ""
var _last_index := -1
var _last_click_ms := 0
## 兑换按钮：pair_id → Button（工程 109）。
var _exchange_buttons: Dictionary = {}
## 批量数量弹框（工程 110）。最后 add_child，保证盖在面板之上。
var _amount_dialog: PanelAmountDialog
## 当前弹框在换哪一对。只有 `_on_exchange()` 会写它 —— 弹框本身不认识「兑换对」，
## 它只认识一个整数，业务身份由面板自己记住。
var _pending_pair := ""

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	get_viewport().size_changed.connect(_update_layout)
	EventBus.settings_changed.connect(_update_layout)
	_update_layout.call_deferred()
	visible = false
	EventBus.warehouse_panel_requested.connect(_on_requested)
	EventBus.panel_opened.connect(_on_panel_opened)
	EventBus.panels_close_requested.connect(func() -> void: set_open(false))
	EventBus.inventory_changed.connect(_refresh)
	EventBus.warehouse_changed.connect(_refresh)
	EventBus.gold_changed.connect(_on_gold_changed)

func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("interact") or event.is_action_pressed("pause")):
		set_open(false)
		get_viewport().set_input_as_handled()

func _on_requested(npc_name: String) -> void:
	_title.text = PanelChrome.title_text(Localization.tr_key("ui.warehouse_panel.p001") % npc_name)
	set_open(true)

func _on_panel_opened(panel_id: String) -> void:
	if panel_id != PANEL_ID and visible:
		set_open(false)

func _on_gold_changed(_amount: int) -> void:
	if visible:
		_refresh_summary()
		_refresh_exchange()

func set_open(open: bool) -> void:
	visible = open
	if not open and _amount_dialog != null:
		# 面板收起时弹框必须一起收：否则输入框焦点留在隐藏控件上，键盘会继续往里送字符。
		_amount_dialog.close()
	GameState.set_panel_open(PANEL_ID, open)
	if open:
		_update_layout()
		_detail.text = Localization.tr_key("ui.warehouse_panel.p002")
		_refresh()
		EventBus.panel_opened.emit(PANEL_ID)

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.42)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelChrome.new()
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)
	var head := HBoxContainer.new()
	root.add_child(head)
	PanelChrome.style_header_layout(margin, head)
	_title = Label.new()
	_title.text = Localization.tr_key("ui.warehouse_panel.p003")
	_title.add_theme_font_size_override("font_size", 18)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	PanelChrome.style_title(_title)
	var close := Button.new()
	close.text = "×"
	close.pressed.connect(func() -> void: set_open(false))
	head.add_child(close)
	PanelChrome.style_close(close)
	root.add_child(PanelChrome.make_title_gap())
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 14)
	root.add_child(columns)
	var bag_column := VBoxContainer.new()
	columns.add_child(bag_column)
	var bag_head := HBoxContainer.new()
	bag_column.add_child(bag_head)
	_bag_count = Label.new()
	_bag_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bag_head.add_child(_bag_count)
	PanelChrome.style_section(_bag_count)
	_bag_organize = Button.new()
	_bag_organize.text = Localization.tr_key("ui.warehouse_panel.p004")
	_bag_organize.tooltip_text = Localization.tr_key("ui.warehouse_panel.p005")
	_bag_organize.pressed.connect(_on_bag_organize)
	bag_head.add_child(_bag_organize)
	PanelChrome.style_action(_bag_organize)
	_bag_scroll = _make_scroll(bag_column)
	_bag_grid = _make_grid(_bag_scroll)
	var store_column := VBoxContainer.new()
	columns.add_child(store_column)
	var store_head := HBoxContainer.new()
	store_column.add_child(store_head)
	_store_count = Label.new()
	_store_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	store_head.add_child(_store_count)
	PanelChrome.style_section(_store_count)
	_store_organize = Button.new()
	_store_organize.text = Localization.tr_key("ui.warehouse_panel.p004")
	_store_organize.tooltip_text = Localization.tr_key("ui.warehouse_panel.p006")
	_store_organize.pressed.connect(_on_store_organize)
	store_head.add_child(_store_organize)
	PanelChrome.style_action(_store_organize)
	_store_scroll = _make_scroll(store_column)
	_store_grid = _make_grid(_store_scroll)
	_detail = Label.new()
	_detail.custom_minimum_size.y = 48
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_detail)
	_detail.add_theme_color_override("font_color", PanelChrome.MUTED)
	# 兑换区（工程 109）：标题一行 + 四个按钮一行。按钮文案带「可换 N 次」，
	# 禁用原因与提示共用一个 tooltip —— 不做第二套判断，避免「按钮灰了但说不出为什么」。
	var exchange_head := Label.new()
	exchange_head.text = Localization.tr_key("ui.warehouse_panel.p016")
	root.add_child(exchange_head)
	PanelChrome.style_section(exchange_head)
	var exchange_row := HBoxContainer.new()
	exchange_row.add_theme_constant_override("separation", 6)
	root.add_child(exchange_row)
	for spec in EXCHANGE_ROWS:
		var pair_id := String(spec[0])
		var button := Button.new()
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_on_exchange.bind(pair_id))
		exchange_row.add_child(button)
		PanelChrome.style_action(button)
		_exchange_buttons[pair_id] = button
	var footer := HBoxContainer.new()
	root.add_child(footer)
	_gold = Label.new()
	_gold.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_gold)
	_gold.add_theme_color_override("font_color", PanelChrome.GOLD_LIGHT)
	_expand = Button.new()
	_expand.pressed.connect(_on_expand)
	footer.add_child(_expand)
	PanelChrome.style_action(_expand)
	# 弹框放在最后 add_child：同层 Control 的绘制顺序按树序，后加即在最上。
	_amount_dialog = PanelAmountDialog.new()
	_amount_dialog.submitted.connect(_on_amount_submitted)
	add_child(_amount_dialog)

func _make_scroll(parent: VBoxContainer) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(406, 312)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	return scroll

func _make_grid(scroll: ScrollContainer) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	scroll.add_child(grid)
	return grid

func _update_layout() -> void:
	if _bag_scroll == null or _store_scroll == null:
		return
	var logical := get_viewport().get_visible_rect().size / SettingsRuntime.ui_scale_value()
	var available := maxf(280.0, logical.x - 46.0)
	var column_width := (available - 14.0) * 0.5
	var count := clampi(int(floor((column_width - 10.0 + 4.0) / 50.0)), 3, COLUMNS)
	var width := minf(406.0, float(count * 46 + (count - 1) * 4 + 10))
	var height := minf(312.0, maxf(100.0, logical.y - WAREHOUSE_VERTICAL_CHROME_BUDGET))
	_bag_grid.columns = count
	_store_grid.columns = count
	_bag_scroll.custom_minimum_size = Vector2(width, height)
	_store_scroll.custom_minimum_size = Vector2(width, height)

func _refresh() -> void:
	if not visible:
		return
	_refresh_grid(_bag_grid, _bag_slots, GameState.inventory, "bag")
	_refresh_grid(_store_grid, _store_slots, GameState.warehouse, "warehouse")
	_refresh_summary()
	_refresh_exchange()

## 容量变化时才增减格子；物品变化只刷新已有节点，保留拖放与滚动状态。
func _refresh_grid(grid: GridContainer, slots: Array[ItemSlot], items: Array, side: String) -> void:
	while slots.size() < items.size():
		var index := slots.size()
		var button := ItemSlot.new()
		button.role = ItemSlot.ROLE_BAG if side == "bag" else ItemSlot.ROLE_WAREHOUSE
		button.index = index
		button.apply_grid_base(SLOT_MIN)
		button.pressed.connect(_on_slot_pressed.bind(side, index))
		button.item_dropped.connect(_on_drop.bind(side))
		grid.add_child(button)
		slots.append(button)
	while slots.size() > items.size():
		var removed: ItemSlot = slots.pop_back()
		grid.remove_child(removed)
		removed.queue_free()
	for index in range(slots.size()):
		var button: ItemSlot = slots[index]
		var item: Variant = items[index]
		if item is Dictionary:
			button.item = item
			button.draggable = true
			button.text = ItemUtil.template_name(item).left(2)
			var color := ItemUtil.quality_color(String(item.get("quality", "common"))) if String(item.get("kind", "")) == "equip" \
				else ItemUtil.kind_color(String(item.get("kind", "misc")))
			button.add_theme_color_override("font_color", color)
			button.apply_grid_style(color, true)
			button.tooltip_text = "%s\n%s" % [ItemUtil.display_name(item), "\n".join(ItemUtil.attr_lines(item))]
		else:
			button.item = {}
			button.draggable = false
			button.text = ""
			button.add_theme_color_override("font_color", ItemSlot.GRID_TEXT)
			button.apply_grid_style(ItemSlot.GRID_BORDER, false)
			button.tooltip_text = ""
		SampleArt.decorate(button, SampleArt.icon_for(item))

func _refresh_summary() -> void:
	_bag_count.text = Localization.tr_key("ui.warehouse_panel.p007") % [GameState.inventory_used(), GameState.inventory.size()]
	_store_count.text = Localization.tr_key("ui.warehouse_panel.p008") % [Inventory.used_slots(GameState.warehouse), GameState.warehouse.size()]
	_gold.text = Localization.tr_key("ui.warehouse_panel.p009") % GameState.gold
	var cost := Warehouse.next_cost(GameState.warehouse_expansions)
	_expand.disabled = cost < 0
	_expand.text = Localization.tr_key("ui.warehouse_panel.p010") if cost < 0 else Localization.tr_key("ui.warehouse_panel.p011") % [
		Warehouse.capacity(GameState.warehouse_expansions + 1) - GameState.warehouse.size(), cost]

## 兑换按钮的文案与禁用态（工程 109）。可换次数来自 `GoldExchange.max_times()`，
## 禁用原因来自 `GoldExchange.check()` —— 与真正提交走同一套判定，不会出现
## 「按钮能点但点了失败」或「明明够却不能点」两种错位。
func _refresh_exchange() -> void:
	for spec in EXCHANGE_ROWS:
		var pair_id := String(spec[0])
		var button: Variant = _exchange_buttons.get(pair_id)
		if not button is Button:
			continue
		var times := GoldExchange.max_times(pair_id)
		var label := Localization.tr_key(String(spec[1]))
		button.text = Localization.tr_key("ui.warehouse_panel.p021") % [label, times]
		button.disabled = times <= 0
		var gate := GoldExchange.check(pair_id, 1)
		var hint := Localization.tr_key("ui.warehouse_panel.p022")
		if not bool(gate.get("ok", false)):
			hint = "%s\n%s" % [hint, String(gate.get("reason", ""))]
		button.tooltip_text = hint

## 点兑换按钮 → 开批量数量弹框。
## 🔑 刻意**取消**了「单击换 1 次、Shift 换到上限」：Shift 是玩家常按的修饰键，
## 想换 1 块却手滑按着 Shift ⇒ 1 亿金币瞬间清零，且这一步不可逆。
## 便捷性不该建立在「按住某个键就等于清空储值」上（110 方案 §1）。
func _on_exchange(pair_id: String) -> void:
	_reset_click()
	var maximum := GoldExchange.max_times(pair_id)
	if maximum <= 0:
		return
	var label_key := _exchange_label_key(pair_id)
	_amount_dialog.title = Localization.tr_key(label_key) if not label_key.is_empty() else pair_id
	_amount_dialog.rate_text = GoldExchange.rate_text(pair_id)
	# 上限在打开时取一次快照，只用于「可换 N 次」提示与输入校验；
	# 真正的可行性以 `GameState.exchange()` 落账前的重新校验为准（见 _do_exchange）。
	_amount_dialog.max_times = maximum
	_amount_dialog.preview_provider = func(times: int) -> Dictionary:
		return {
			"cost": GoldExchange.cost_text(pair_id, times),
			"got": GoldExchange.got_text(pair_id, times),
		}
	_pending_pair = pair_id
	_amount_dialog.popup()

## 弹框确认后落账。弹框打开期间金币/仓库可能已经变了（仓库面板不屏蔽世界，
## 挂机战斗照旧在跑），所以这里**以 `GameState.exchange()` 的返回为准**，
## 绝不拿打开弹框时算的 max 去夹取玩家输入 —— 那等于用过期快照改写玩家的意图。
func _on_amount_submitted(times: int) -> void:
	_do_exchange(_pending_pair, times)

func _do_exchange(pair_id: String, times: int) -> void:
	if pair_id.is_empty() or times < 1:
		return
	var result := GameState.exchange(pair_id, times)
	_detail.text = Localization.tr_key("msg.exchange.p006") % String(result.get("got", "")) \
		if bool(result.get("ok", false)) else String(result.get("reason", ""))
	_refresh()

func _exchange_label_key(pair_id: String) -> String:
	for spec in EXCHANGE_ROWS:
		if String(spec[0]) == pair_id:
			return String(spec[1])
	return ""

func _on_bag_organize() -> void:
	_reset_click()
	GameState.organize_inventory()
func _on_store_organize() -> void:
	_reset_click()
	GameState.organize_warehouse()

func _reset_click() -> void:
	_last_side = ""
	_last_index = -1
	_last_click_ms = 0

func _on_slot_pressed(side: String, index: int) -> void:
	var items: Array = GameState.inventory if side == "bag" else GameState.warehouse
	var item = items[index]
	var now := Time.get_ticks_msec()
	if _last_side == side and _last_index == index and now - _last_click_ms <= DOUBLE_CLICK_MS:
		_last_side = ""
		_last_index = -1
		if item is Dictionary:
			var id := Warehouse.item_token(item)
			var result := GameState.warehouse_store(index, id) if side == "bag" else GameState.warehouse_take(index, id)
			_detail.text = String(result.get("reason", Localization.tr_key("ui.warehouse_panel.p012"))) if not result.get("ok", false) else Localization.tr_key("ui.warehouse_panel.p012")
		return
	_last_side = side
	_last_index = index
	_last_click_ms = now
	if item is Dictionary:
		_detail.text = "%s　%s" % [ItemUtil.display_name(item), "，".join(ItemUtil.attr_lines(item))]
	else:
		_detail.text = Localization.tr_key("ui.warehouse_panel.p013")

func _on_drop(target_index: int, payload: Dictionary, target_side: String) -> void:
	var source_index := int(payload.get("index", -1))
	var item: Variant = payload.get("item", {})
	if not item is Dictionary:
		return
	var id := String(payload.get("token", Warehouse.item_token(item)))
	var result: Dictionary = {}
	if target_side == "warehouse" and int(payload.get("from", -1)) == ItemSlot.ROLE_BAG:
		result = GameState.warehouse_store(source_index, id, target_index)
	elif target_side == "bag" and int(payload.get("from", -1)) == ItemSlot.ROLE_WAREHOUSE:
		result = GameState.warehouse_take(source_index, id, target_index)
	if not result.is_empty():
		_detail.text = Localization.tr_key("ui.warehouse_panel.p012") if result.get("ok", false) else String(result.get("reason", Localization.tr_key("ui.warehouse_panel.p014")))

func _on_expand() -> void:
	var result := GameState.warehouse_expand()
	_detail.text = Localization.tr_key("ui.warehouse_panel.p015") % result.get("capacity", 0) if result.get("ok", false) \
		else String(result.get("reason", Localization.tr_key("ui.warehouse.expand_failed")))
