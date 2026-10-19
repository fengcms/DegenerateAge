class_name EquipmentSalePreview
extends Control
## 背包与货郎共用的装备出售清单：预设产生默认勾选，玩家本次可逐件修改。
## 本控件只展示和收集选择；实际扣物、入账及托盘暂存由 GameState/ShopPanel 校验。

const DIRECT := "direct"
const STAGE := "stage"
const PANEL_WIDTH := 680.0
const PANEL_HEIGHT := 570.0

var mode := DIRECT
var source_panel: WeakRef
var _rows: Array[Dictionary] = []
var _selected := {}
var _stale := false
var _risk_confirmed := false
var _dragging := false
var _drag_offset := Vector2.ZERO
var _box: PanelChrome
var _list: VBoxContainer
var _list_scroll: ScrollContainer
var _summary: Label
var _warning: Label
var _confirm: Button
var _preset: OptionButton

## 供背包或货郎调用；挂在同一 UI CanvasLayer，保持高缩放坐标口径一致。
static func open_for(source: Control, sale_mode: String) -> EquipmentSalePreview:
	var ui := source.get_parent()
	for sibling in ui.get_children():
		if sibling is EquipmentSalePreview:
			(sibling as EquipmentSalePreview).queue_free()
	var preview := EquipmentSalePreview.new()
	preview.mode = sale_mode
	preview.source_panel = weakref(source)
	ui.add_child(preview)
	return preview

## 构建无全屏遮罩的可移动窗口；键盘世界操作继续由游戏处理。
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 3000
	_resize()
	_build()
	_reload_entries()
	get_viewport().size_changed.connect(_resize)
	EventBus.settings_changed.connect(_on_state_changed)
	EventBus.inventory_changed.connect(_on_state_changed)
	EventBus.equipment_changed.connect(_on_state_changed)
	EventBus.player_leveled.connect(func(_level: int) -> void: _on_state_changed())
	if source_panel != null and source_panel.get_ref() is Control:
		(source_panel.get_ref() as Control).visibility_changed.connect(_on_source_visibility_changed)
	_resize.call_deferred()

## 关闭来源面板时同步撤销本次未提交的勾选。
func _on_source_visibility_changed() -> void:
	var source: Control = source_panel.get_ref() if source_panel != null else null
	if source == null or not source.visible:
		queue_free()

## 只拦截 Esc 与标题拖动；移动和战斗快捷键继续传给游戏。
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		queue_free()
	elif _dragging and event is InputEventMouseMotion:
		_box.position = (get_local_mouse_position() - _drag_offset).clamp(Vector2.ZERO,
			(size - _box.size).max(Vector2.ZERO))
	elif _dragging and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_dragging = false

## 从标题栏启动拖动，不使窗口外的世界点击失效。
func _on_header_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_drag_offset = get_local_mouse_position() - _box.position
		_dragging = true
		accept_event()

## 限制清单在当前逻辑视口内；UI CanvasLayer 已统一完成界面缩放。
func _resize() -> void:
	size = get_viewport_rect().size / SettingsRuntime.ui_scale_value()
	if _box == null:
		return
	var old_position := _box.position
	var desired := Vector2(minf(PANEL_WIDTH, size.x * 0.94), minf(PANEL_HEIGHT, size.y * 0.94))
	_list_scroll.custom_minimum_size = Vector2(0.0, maxf(80.0, desired.y - 305.0))
	_box.custom_minimum_size = desired
	_box.size = desired
	_box.position = old_position.clamp(Vector2.ZERO, (size - _box.size).max(Vector2.ZERO))

## 构建预设、可滚动逐件清单与底部确认，不复用旧数字 SpinBox。
func _build() -> void:
	_box = PanelChrome.new()
	_box.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_box)
	var margin := MarginContainer.new()
	for side in ["left", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 15)
	_box.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	margin.add_child(column)
	var header := HBoxContainer.new()
	PanelChrome.style_header_layout(margin, header)
	column.add_child(header)
	header.gui_input.connect(_on_header_input)
	var title := Label.new()
	title.text = Localization.tr_key("ui.sale_preview.title_stage" if mode == STAGE else "ui.sale_preview.title_direct")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	PanelChrome.style_title(title)
	var close := Button.new()
	close.text = "×"
	close.pressed.connect(queue_free)
	header.add_child(close)
	PanelChrome.style_close(close)
	column.add_child(PanelChrome.make_title_gap())
	_preset = OptionButton.new()
	for preset_id in SellGearPolicy.PRESETS:
		_preset.add_item(Localization.tr_key("ui.sale_preview.preset_" + preset_id))
	column.add_child(_preset)
	PanelChrome.style_action(_preset)
	_preset.item_selected.connect(_on_preset_selected)
	_list_scroll = ScrollContainer.new()
	_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_list_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 5)
	_list_scroll.add_child(_list)
	_summary = Label.new()
	column.add_child(_summary)
	_warning = Label.new()
	_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_warning.add_theme_color_override("font_color", Color("ffbd88"))
	column.add_child(_warning)
	var actions := HBoxContainer.new()
	column.add_child(actions)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)
	var cancel := Button.new()
	cancel.text = Localization.tr_key("ui.common.cancel")
	cancel.pressed.connect(queue_free)
	actions.add_child(cancel)
	PanelChrome.style_action(cancel)
	_confirm = Button.new()
	_confirm.pressed.connect(_on_confirm)
	actions.add_child(_confirm)
	PanelChrome.style_action(_confirm, true)
	_resize()
	_box.position = (size - _box.size) * Vector2(0.5, 0.18)

## 背包/装备/等级变化只标记旧预览失效，玩家再次确认时才重建清单。
func _on_state_changed() -> void:
	_stale = true
	_risk_confirmed = false
	_refresh_footer()
	_resize.call_deferred()

## 切换预设后重置本次勾选，并持久化角色所选的预设。
func _on_preset_selected(index: int) -> void:
	if index < 0 or index >= SellGearPolicy.PRESETS.size():
		return
	for row in _rows:
		if bool(_selected.get(String(row.instance_id), false)) != bool(row.default_selected):
			EventBus.toast_requested.emit(Localization.tr_key("ui.sale_preview.preset_reset"), "info")
			break
	GameState.set_sell_gear_preset(String(SellGearPolicy.PRESETS[index]))
	_reload_entries()

## 依据当前背包重新生成清单；既有逐件勾选不跨预设或过期快照保留。
func _reload_entries() -> void:
	_stale = false
	_risk_confirmed = false
	_rows = GameState.preview_equipment_sale()
	_selected.clear()
	var preset_id := String(GameState.settings.get("sellGearPreset", SellGearPolicy.CAUTIOUS))
	_preset.select(maxi(0, SellGearPolicy.PRESETS.find(preset_id)))
	for row in _rows:
		_selected[String(row.instance_id)] = bool(row.default_selected)
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	if _rows.is_empty():
		var empty := Label.new()
		empty.text = Localization.tr_key("ui.sale_preview.empty")
		_list.add_child(empty)
	else:
		for row in _rows:
			_add_row(row)
	_refresh_footer()

## 单行保留装备的背包顺序，并显示价格、品质、星级及预设排除原因。
func _add_row(row: Dictionary) -> void:
	var wrapper := VBoxContainer.new()
	_list.add_child(wrapper)
	var header := HBoxContainer.new()
	wrapper.add_child(header)
	var box := CheckBox.new()
	box.button_pressed = bool(_selected.get(String(row.instance_id), false))
	box.disabled = not bool(row.manual_selectable)
	header.add_child(box)
	box.toggled.connect(_on_row_toggled.bind(String(row.instance_id)))
	var item: Dictionary = row.item_snapshot
	var icon := ItemSlot.new()
	icon.role = ItemSlot.ROLE_BAG
	icon.disabled = true
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.apply_grid_base(Vector2(38, 38))
	header.add_child(icon)
	icon.item = item
	var title := Label.new()
	title.text = "%s · Lv%d · %s · ★%d" % [ItemUtil.display_name(item), Equipment.level_req(item),
		Localization.tr_key("ui.inventory_panel.p%03d" % (8 + maxi(0, Shop.QUALITY_ORDER.find(Shop.item_quality(item))))),
		int(item.get("star", 0))]
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var price := Label.new()
	price.text = "%d 金币" % int(row.price)
	header.add_child(price)
	var reason := Label.new()
	reason.text = _reasons_text(row)
	if int(row.score_delta) > 0:
		reason.text += " · " + Localization.tr_key("ui.sale_preview.score_delta", [int(row.score_delta)])
	reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reason.add_theme_color_override("font_color", PanelChrome.MUTED)
	wrapper.add_child(reason)
	wrapper.add_child(HSeparator.new())

## 将策略原因转为玩家可读短语；颜色之外始终保留文字说明。
func _reasons_text(row: Dictionary) -> String:
	if bool(row.default_selected):
		return Localization.tr_key("ui.sale_preview.default_reason")
	var labels: Array[String] = []
	for reason in row.reasons:
		labels.append(Localization.tr_key("ui.sale_preview.reason_" + String(reason)))
	return " · ".join(PackedStringArray(labels))

## 本次勾选只改预览，不改背包；高价值手选会重置二次确认。
func _on_row_toggled(pressed: bool, instance_id: String) -> void:
	_selected[instance_id] = pressed
	_risk_confirmed = false
	_refresh_footer()

## 汇总玩家当前勾选，避免直接使用预设候选数代替本次实际选择。
func _selected_rows() -> Array[Dictionary]:
	var chosen: Array[Dictionary] = []
	for row in _rows:
		if bool(_selected.get(String(row.instance_id), false)):
			chosen.append(row)
	return chosen

## 显示预计金币、托盘剩余容量、过期警告及风险确认状态。
func _refresh_footer() -> void:
	var chosen := _selected_rows()
	var total := 0
	var risky: Array[String] = []
	for row in chosen:
		total += int(row.price)
		if not bool(row.default_selected):
			risky.append(ItemUtil.display_name(row.item_snapshot))
	_summary.text = Localization.tr_key("ui.sale_preview.summary", [chosen.size(), total])
	var free_slots := 9999
	var source: Control = source_panel.get_ref() if source_panel != null else null
	if mode == STAGE and source != null:
		free_slots = (source.get("_tray_slots") as Array).size() - (source.get("_tray") as Dictionary).size()
	if _stale:
		_warning.text = Localization.tr_key("ui.sale_preview.stale")
	elif mode == STAGE and chosen.size() > free_slots:
		_warning.text = Localization.tr_key("ui.sale_preview.capacity", [free_slots, chosen.size() - free_slots])
	elif _risk_confirmed:
		_warning.text = Localization.tr_key("ui.sale_preview.risk", [", ".join(PackedStringArray(risky))])
	else:
		_warning.text = ""
	_confirm.disabled = chosen.is_empty() or (mode == STAGE and chosen.size() > free_slots)
	_confirm.text = Localization.tr_key("ui.sale_preview.confirm_risk") if _risk_confirmed else \
		Localization.tr_key("ui.sale_preview.confirm_stage" if mode == STAGE else "ui.sale_preview.confirm_direct")

## 首次确认预设外装备只展示风险；再次确认才交给事务层，失败则刷新重新核对。
func _on_confirm() -> void:
	if _stale:
		_reload_entries()
		_warning.text = Localization.tr_key("ui.sale_preview.stale")
		return
	var chosen := _selected_rows()
	if chosen.is_empty():
		return
	var risky := false
	for row in chosen:
		if not bool(row.default_selected):
			risky = true
			break
	if risky and not _risk_confirmed:
		_risk_confirmed = true
		_refresh_footer()
		return
	var result := {}
	if mode == STAGE:
		var source: Control = source_panel.get_ref() if source_panel != null else null
		if source == null or not source.visible:
			queue_free()
			return
		result = source.call("_stage_selected_equipment", chosen, risky)
	else:
		result = GameState.sell_selected_equipment(chosen, risky)
	if bool(result.get("ok", false)):
		EventBus.toast_requested.emit(Localization.tr_key("ui.sale_preview.done_stage" if mode == STAGE else "ui.sale_preview.done_direct",
			[int(result.get("count", 0)), int(result.get("gold", 0))]), "pickup")
		# 工程 56 口径 A：直卖时金币满额不再拒绝，入账差额在汇总提示之后补一句。
		if bool(result.get("capped", false)):
			EventBus.toast_requested.emit(Localization.tr_key("msg.game_state.p054"), "danger")
		queue_free()
	else:
		_reload_entries()
		_warning.text = String(result.get("reason", Localization.tr_key("ui.sale_preview.stale")))
