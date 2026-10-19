extends Control
## 铁匠三种装备合成的共用界面；只选材料和展示计划，结算交给 GameState。
## 材料快照在选择时固定，背包变化后必须刷新，防止自动拾取或整理造成误耗。

const PANEL_ID := "equipment_fusion"
const WIDTH := 540.0

var _mode := EquipmentFusion.GOLD_TO_PURPLE
var _box: PanelChrome
var _center: CenterContainer
var _scroll: ScrollContainer
var _title: Label
var _hint: Label
var _summary: Label
var _feedback: Label
var _confirm: Button
var _target_row: Control
var _target: OptionButton
var _pickers: Array[OptionButton] = []
var _choice_ids: Array[Array] = []
var _selected: Array[Dictionary] = []
var _stale := false
var _risk_confirmed := false

## 初始化事件订阅和窗口；游戏世界输入由既有面板规则继续处理。
func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	visible = false
	EventBus.equipment_fusion_panel_requested.connect(_on_requested)
	EventBus.equipment_fusion_close_requested.connect(func() -> void: set_open(false))
	EventBus.panel_opened.connect(_on_panel_opened)
	EventBus.panels_close_requested.connect(func() -> void: set_open(false))
	EventBus.inventory_changed.connect(_on_inventory_changed)
	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.settings_changed.connect(_resize)
	get_viewport().size_changed.connect(_resize)
	_resize.call_deferred()

## E/Esc 关闭窗口，不改变材料或金币。
func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("interact") or event.is_action_pressed("pause")):
		set_open(false)
		get_viewport().set_input_as_handled()

## 接收铁匠菜单选择；仅识别三种稳定服务 ID。
func _on_requested(mode: String) -> void:
	if mode not in [EquipmentFusion.GOLD_TO_PURPLE, EquipmentFusion.PURPLE_TARGET,
			EquipmentFusion.STAR_TRANSFER]:
		return
	_mode = mode
	set_open(true)

## 开关窗口并同步面板状态；每次打开都从真实背包重建选项。
func set_open(open: bool) -> void:
	if not open and not visible:
		return
	visible = open
	GameState.set_panel_open(PANEL_ID, open)
	if open:
		EventBus.fusion_mode_changed.emit(true)
		_title.text = Localization.tr_key("ui.fusion.gold_title" if _mode == EquipmentFusion.GOLD_TO_PURPLE else
			"ui.fusion.purple_title" if _mode == EquipmentFusion.PURPLE_TARGET else "ui.fusion.star_title")
		_hint.text = Localization.tr_key("ui.fusion.gold_hint" if _mode == EquipmentFusion.GOLD_TO_PURPLE else
			"ui.fusion.purple_hint" if _mode == EquipmentFusion.PURPLE_TARGET else "ui.fusion.star_hint")
		_target_row.visible = _mode == EquipmentFusion.PURPLE_TARGET
		for i in range(_pickers.size()):
			_pickers[i].get_parent().visible = i < (2 if _mode == EquipmentFusion.STAR_TRANSFER else 4)
		_refresh_choices()
		_resize.call_deferred()
		EventBus.panel_opened.emit(PANEL_ID)
	else:
		EventBus.fusion_mode_changed.emit(false)

## 打开其他互斥 NPC 服务时关闭本窗口。
func _on_panel_opened(panel_id: String) -> void:
	if visible and not GameState.panels_coexist(panel_id, PANEL_ID):
		set_open(false)

## 运行时背包变化使旧快照失效，须由玩家刷新后重新选择。
func _on_inventory_changed() -> void:
	if visible:
		_stale = true
		_risk_confirmed = false
		_feedback.text = Localization.tr_key("ui.fusion.stale")
		_confirm.disabled = true

## 金币变化只重算可支付状态，不重选装备。
func _on_gold_changed(_amount: int) -> void:
	if visible and not _stale:
		_refresh_preview()

## 使窗口在界面轴 100%～200% 下保持于逻辑视口内。
func _resize() -> void:
	if _box == null:
		return
	var logical := get_viewport_rect().size / SettingsRuntime.ui_scale_value()
	var width := minf(WIDTH, logical.x * 0.86)
	_box.custom_minimum_size.x = width
	_scroll.custom_minimum_size = Vector2(0.0, clampf(logical.y * 0.54, 105.0, 360.0))
	_center.size = logical

## 构建可滚动材料选择和确认区域；窗口外不遮挡世界点击。
func _build() -> void:
	_center = CenterContainer.new()
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_center)
	_box = PanelChrome.new()
	_center.add_child(_box)
	var margin := MarginContainer.new()
	for side in ["left", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	_box.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)
	var header := HBoxContainer.new()
	root.add_child(header)
	PanelChrome.style_header_layout(margin, header)
	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	PanelChrome.style_title(_title)
	var close := Button.new()
	close.text = "×"
	close.pressed.connect(func() -> void: set_open(false))
	header.add_child(close)
	PanelChrome.style_close(close)
	_hint = Label.new()
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_hint)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(_scroll)
	var form := VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_theme_constant_override("separation", 8)
	_scroll.add_child(form)
	for i in range(4):
		var row := VBoxContainer.new()
		form.add_child(row)
		var label := Label.new()
		label.text = Localization.tr_key("ui.fusion.material", [i + 1])
		row.add_child(label)
		var picker := OptionButton.new()
		picker.item_selected.connect(_on_item_selected.bind(i))
		row.add_child(picker)
		PanelChrome.style_action(picker)
		_pickers.append(picker)
		_choice_ids.append([])
	_target_row = VBoxContainer.new()
	form.add_child(_target_row)
	var target_label := Label.new()
	target_label.text = Localization.tr_key("ui.fusion.target")
	_target_row.add_child(target_label)
	_target = OptionButton.new()
	_target.add_item(Localization.tr_key("ui.fusion.choose"))
	for kind in Equipment.slot_kinds():
		_target.add_item(Equipment.slot_label(Equipment.slots_for_kind(kind)[0]))
	_target.item_selected.connect(func(_i: int) -> void: _refresh_preview())
	_target_row.add_child(_target)
	PanelChrome.style_action(_target)
	_summary = Label.new()
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_summary)
	_feedback = Label.new()
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feedback.add_theme_color_override("font_color", Color("ffbd88"))
	root.add_child(_feedback)
	var actions := HBoxContainer.new()
	root.add_child(actions)
	var refresh := Button.new()
	refresh.text = Localization.tr_key("ui.fusion.refresh")
	refresh.pressed.connect(_refresh_choices)
	actions.add_child(refresh)
	PanelChrome.style_action(refresh)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)
	_confirm = Button.new()
	_confirm.text = Localization.tr_key("ui.fusion.confirm")
	_confirm.pressed.connect(_on_confirm)
	actions.add_child(_confirm)
	PanelChrome.style_action(_confirm, true)

## 按模式过滤背包装备；刷新会清空旧选择与风险确认状态。
func _refresh_choices() -> void:
	_stale = false
	_risk_confirmed = false
	_selected.clear()
	_feedback.text = ""
	for i in range(_pickers.size()):
		var picker := _pickers[i]
		picker.clear()
		picker.add_item(Localization.tr_key("ui.fusion.choose"))
		_choice_ids[i] = [""]
		if i >= (2 if _mode == EquipmentFusion.STAR_TRANSFER else 4):
			continue
		for index in range(GameState.inventory.size()):
			var entry = GameState.inventory[index]
			if not entry is Dictionary or String(entry.get("kind", "")) != "equip" \
					or bool(entry.get("favorite", false)):
				continue
			var quality := String(entry.get("quality", ""))
			var star := int(entry.get("star", -1))
			if _mode == EquipmentFusion.GOLD_TO_PURPLE and quality != "epic":
				continue
			if _mode == EquipmentFusion.PURPLE_TARGET and (quality != "legendary" or star == Upgrade.max_star()):
				continue
			if _mode == EquipmentFusion.STAR_TRANSFER and (quality != "legendary" or star != (12 if i == 0 else 0)):
				continue
			picker.add_item("%d · %s" % [index + 1, ItemUtil.display_name(entry)])
			_choice_ids[i].append(String(entry.get("instanceId", "")))
		picker.select(0)
	_refresh_preview()

## 保存选中装备的深拷贝快照；本次选择不能因后续整理指向别的实例。
func _on_item_selected(choice: int, row: int) -> void:
	while _selected.size() <= row:
		_selected.append({})
	var id := String(_choice_ids[row][choice]) if choice >= 0 and choice < _choice_ids[row].size() else ""
	_selected[row] = {}
	for item in GameState.inventory:
		if item is Dictionary and String(item.get("instanceId", "")) == id and not id.is_empty():
			_selected[row] = item.duplicate(true)
			break
	_risk_confirmed = false
	_refresh_preview()

## 返回已选择的完整材料；有空格时返回空数组，供预览禁用确认。
func _material_snapshots() -> Array[Dictionary]:
	var count := 2 if _mode == EquipmentFusion.STAR_TRANSFER else 4
	var result: Array[Dictionary] = []
	for i in range(count):
		if i >= _selected.size() or _selected[i].is_empty():
			return []
		result.append(_selected[i])
	return result

## 只读规则预览，显示输出档、费用和拒绝原因。
func _refresh_preview() -> void:
	_confirm.text = Localization.tr_key("ui.fusion.confirm_again" if _risk_confirmed else "ui.fusion.confirm")
	_confirm.disabled = true
	if _stale:
		return
	var items := _material_snapshots()
	if items.is_empty():
		_summary.text = Localization.tr_key("ui.fusion.pick")
		return
	var kind := ""
	if _mode == EquipmentFusion.PURPLE_TARGET and _target.selected > 0:
		kind = Equipment.slot_kinds()[_target.selected - 1]
	var plan := EquipmentFusion.plan_transfer(items[0], items[1]) if _mode == EquipmentFusion.STAR_TRANSFER \
		else EquipmentFusion.plan_four(items, _mode, kind)
	if not bool(plan.get("ok", false)):
		_summary.text = String(plan.get("reason", ""))
		return
	var label := Localization.tr_key("ui.fusion.random_kind") if _mode == EquipmentFusion.GOLD_TO_PURPLE else \
		Equipment.slot_label(Equipment.slots_for_kind(String(plan.target_kind))[0])
	_summary.text = Localization.tr_key("ui.fusion.preview", ["%d—%d" % [int(plan.tier), int(plan.tier) + 9],
		label, " ★12" if _mode == EquipmentFusion.STAR_TRANSFER else " ★0"])
	if _mode == EquipmentFusion.STAR_TRANSFER:
		_summary.text += "\n" + Localization.tr_key("ui.fusion.cost", [int(plan.cost), GameState.gold])
	_confirm.disabled = GameState.gold < int(plan.get("cost", 0))

## 已升星材料和保星交易需二次确认；真正扣材由 GameState 重核快照。
func _on_confirm() -> void:
	if _stale:
		_feedback.text = Localization.tr_key("ui.fusion.stale")
		return
	var items := _material_snapshots()
	if items.is_empty():
		return
	var risk := _mode == EquipmentFusion.STAR_TRANSFER
	var stars: Array[String] = []
	for item in items:
		if int(item.get("star", 0)) > 0:
			stars.append(ItemUtil.display_name(item))
			risk = true
	if risk and not _risk_confirmed:
		_risk_confirmed = true
		_feedback.text = Localization.tr_key("ui.fusion.star_warning") if _mode == EquipmentFusion.STAR_TRANSFER else \
			Localization.tr_key("ui.fusion.star_loss", [", ".join(PackedStringArray(stars))])
		_refresh_preview()
		return
	var kind := Equipment.slot_kinds()[_target.selected - 1] if _mode == EquipmentFusion.PURPLE_TARGET else ""
	var result := GameState.forge_equipment(_mode, items, kind)
	if bool(result.get("ok", false)):
		EventBus.toast_requested.emit(Localization.tr_key("ui.fusion.done", [ItemUtil.display_name(result.item)]), "pickup")
		_refresh_choices()
	else:
		_feedback.text = String(result.get("reason", "合成失败"))
		_risk_confirmed = false
		_refresh_preview()
