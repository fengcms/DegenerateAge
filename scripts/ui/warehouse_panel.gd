extends Control
## 仓库：背包 / 仓库双栏，物品双击或拖放存取，金币扩容。

const PANEL_ID := "warehouse"
const COLUMNS := 8
const DOUBLE_CLICK_MS := 400
const SLOT_MIN := Vector2(46, 46)
const COL_PANEL := Color(0.06, 0.07, 0.09, 0.97)
const COL_BORDER := Color(0.30, 0.33, 0.38)

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
var _last_side := ""
var _last_index := -1
var _last_click_ms := 0

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
	EventBus.inventory_changed.connect(_refresh)
	EventBus.warehouse_changed.connect(_refresh)
	EventBus.gold_changed.connect(_on_gold_changed)

func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("interact") or event.is_action_pressed("pause")):
		set_open(false)
		get_viewport().set_input_as_handled()

func _on_requested(npc_name: String) -> void:
	_title.text = "%s　·　仓库" % npc_name
	set_open(true)

func _on_panel_opened(panel_id: String) -> void:
	if panel_id != PANEL_ID and visible:
		set_open(false)

func _on_gold_changed(_amount: int) -> void:
	if visible:
		_refresh_summary()

func set_open(open: bool) -> void:
	visible = open
	GameState.set_panel_open(PANEL_ID, open)
	if open:
		_update_layout()
		_detail.text = "双击物品存取，也可拖到另一侧的空格。"
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
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = COL_PANEL
	style.border_color = COL_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)
	var head := HBoxContainer.new()
	root.add_child(head)
	_title = Label.new()
	_title.text = "仓库"
	_title.add_theme_font_size_override("font_size", 18)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var close := Button.new()
	close.text = "×"
	close.pressed.connect(func() -> void: set_open(false))
	head.add_child(close)
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
	_bag_organize = Button.new()
	_bag_organize.text = "整理"
	_bag_organize.tooltip_text = "整理背包"
	_bag_organize.pressed.connect(_on_bag_organize)
	bag_head.add_child(_bag_organize)
	_bag_scroll = _make_scroll(bag_column)
	_bag_grid = _make_grid(_bag_scroll)
	var store_column := VBoxContainer.new()
	columns.add_child(store_column)
	var store_head := HBoxContainer.new()
	store_column.add_child(store_head)
	_store_count = Label.new()
	_store_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	store_head.add_child(_store_count)
	_store_organize = Button.new()
	_store_organize.text = "整理"
	_store_organize.tooltip_text = "整理仓库"
	_store_organize.pressed.connect(_on_store_organize)
	store_head.add_child(_store_organize)
	_store_scroll = _make_scroll(store_column)
	_store_grid = _make_grid(_store_scroll)
	_detail = Label.new()
	_detail.custom_minimum_size.y = 48
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_detail)
	var footer := HBoxContainer.new()
	root.add_child(footer)
	_gold = Label.new()
	_gold.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_gold)
	_expand = Button.new()
	_expand.pressed.connect(_on_expand)
	footer.add_child(_expand)

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
	var height := minf(312.0, maxf(100.0, logical.y - 190.0))
	_bag_grid.columns = count
	_store_grid.columns = count
	_bag_scroll.custom_minimum_size = Vector2(width, height)
	_store_scroll.custom_minimum_size = Vector2(width, height)

func _refresh() -> void:
	if not visible:
		return
	_rebuild_grid(_bag_grid, GameState.inventory, "bag")
	_rebuild_grid(_store_grid, GameState.warehouse, "warehouse")
	_refresh_summary()

func _rebuild_grid(grid: GridContainer, items: Array, side: String) -> void:
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	for index in range(items.size()):
		var button := ItemSlot.new()
		button.role = ItemSlot.ROLE_BAG if side == "bag" else ItemSlot.ROLE_WAREHOUSE
		button.index = index
		button.custom_minimum_size = SLOT_MIN
		var item = items[index]
		if item is Dictionary:
			button.item = item
			button.draggable = true
			button.text = ItemUtil.template_name(item).left(2)
			button.tooltip_text = "%s\n%s" % [ItemUtil.display_name(item), "\n".join(ItemUtil.attr_lines(item))]
		else:
			button.text = "·"
		button.pressed.connect(_on_slot_pressed.bind(side, index))
		button.item_dropped.connect(_on_drop.bind(side))
		grid.add_child(button)

func _refresh_summary() -> void:
	_bag_count.text = "背包　%d / %d" % [GameState.inventory_used(), GameState.inventory.size()]
	_store_count.text = "仓库　%d / %d" % [Inventory.used_slots(GameState.warehouse), GameState.warehouse.size()]
	_gold.text = "金币：%d" % GameState.gold
	var cost := Warehouse.next_cost(GameState.warehouse_expansions)
	_expand.disabled = cost < 0
	_expand.text = "已达上限" if cost < 0 else "扩容 +%d 格（%d 金币）" % [
		Warehouse.capacity(GameState.warehouse_expansions + 1) - GameState.warehouse.size(), cost]

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
			_detail.text = String(result.get("reason", "存取完成")) if not result.get("ok", false) else "存取完成"
		return
	_last_side = side
	_last_index = index
	_last_click_ms = now
	if item is Dictionary:
		_detail.text = "%s　%s" % [ItemUtil.display_name(item), "，".join(ItemUtil.attr_lines(item))]
	else:
		_detail.text = "空格"

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
		_detail.text = "存取完成" if result.get("ok", false) else String(result.get("reason", "无法存取"))

func _on_expand() -> void:
	var result := GameState.warehouse_expand()
	_detail.text = "扩容完成，当前 %d 格" % result.get("capacity", 0) if result.get("ok", false) \
		else String(result.get("reason", "扩容失败"))
