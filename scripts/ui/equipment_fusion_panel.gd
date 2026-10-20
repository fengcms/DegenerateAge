extends Control
## 铁匠三种合成共用的材料工作台；背包物品只做预选引用，确认后才由 GameState 结算。

const PANEL_ID := "equipment_fusion"
const WIDTH := 430.0
const GAP := 12.0
const SLOT_SIZE := Vector2(78, 78)

var _mode := EquipmentFusion.GOLD_TO_PURPLE
var _box: PanelChrome
var _center: CenterContainer
var _scroll: ScrollContainer
var _grid: FusionMaterialGrid
var _title: Label
var _hint: Label
var _summary: Label
var _feedback: Label
var _confirm: Button
var _random: Button
var _target_row: Control
var _target: OptionButton
var _slots: Array[ItemSlot] = []
var _remove_buttons: Array[Button] = []
var _selected: Array[Dictionary] = []
var _risk_confirmed := false

## 接入工作台会话和背包更新，不进行逐帧背包扫描。
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
	# 换装 / 卸下也走同一次失效检查（工程 65）：第一格可能来自穿戴槽。
	EventBus.equipment_changed.connect(_on_equipment_changed)
	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.settings_changed.connect(_resize)
	get_viewport().size_changed.connect(_resize)
	_resize.call_deferred()

## Esc/E 只关闭合成工作台；背包保持可见，输入事件不再传给背包。
func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("interact") or event.is_action_pressed("pause")):
		set_open(false)
		get_viewport().set_input_as_handled()

## 铁匠菜单只能打开三种已登记的服务。
func _on_requested(mode: String) -> void:
	if mode not in [EquipmentFusion.GOLD_TO_PURPLE, EquipmentFusion.PURPLE_TARGET,
			EquipmentFusion.STAR_TRANSFER]:
		return
	_mode = mode
	set_open(true)

## 切换服务清空预选；关闭时释放引用，但不动背包中的真实装备。
func set_open(open: bool) -> void:
	if not open and not visible:
		return
	visible = open
	GameState.set_panel_open(PANEL_ID, open)
	_reset_materials()
	if open:
		_title.text = Localization.tr_key("ui.fusion.gold_title" if _mode == EquipmentFusion.GOLD_TO_PURPLE else
			"ui.fusion.purple_title" if _mode == EquipmentFusion.PURPLE_TARGET else "ui.fusion.star_title")
		_hint.text = Localization.tr_key("ui.fusion.gold_hint" if _mode == EquipmentFusion.GOLD_TO_PURPLE else
			"ui.fusion.purple_hint" if _mode == EquipmentFusion.PURPLE_TARGET else "ui.fusion.star_hint")
		_target_row.visible = _mode == EquipmentFusion.PURPLE_TARGET
		_random.visible = _mode != EquipmentFusion.STAR_TRANSFER
		_confirm.text = Localization.tr_key("ui.fusion.transfer_action" if _mode == EquipmentFusion.STAR_TRANSFER else
			"ui.fusion.forge_action")
		_refresh_slots()
		EventBus.fusion_mode_changed.emit(true)
		_resize.call_deferred()
		EventBus.panel_opened.emit(PANEL_ID)
	else:
		EventBus.fusion_mode_changed.emit(false)
		EventBus.fusion_selection_changed.emit(PackedStringArray())

## 背包是工作台的会话伙伴；其他互斥面板打开时退出。
func _on_panel_opened(panel_id: String) -> void:
	if visible and not GameState.panels_coexist(panel_id, PANEL_ID):
		set_open(false)

## 背包整理可改变下标但不改变实例；物品本身变化则撤下对应预选。
## 身上那件被换下 / 被消耗也走同一次检查（工程 65）—— 第一格可能来自穿戴槽。
func _on_inventory_changed() -> void:
	_revalidate_selection()

func _on_equipment_changed() -> void:
	_revalidate_selection()

## 按实例 ID（先背包、后穿戴）核对每个预选是否仍原样存在；任一失效即整体提示。
func _revalidate_selection() -> void:
	if not visible:
		return
	var invalid := false
	for i in range(_selected.size()):
		if _selected[i].is_empty():
			continue
		var found := _find_item(String(_selected[i].get("instanceId", "")))
		if found.is_empty() or found != _selected[i]:
			_selected[i] = {}
			invalid = true
	_risk_confirmed = false
	_refresh_slots()
	_refresh_preview()
	if invalid:
		_feedback.text = Localization.tr_key("ui.fusion.stale")

## 金币变化重算可支付状态，并取消旧的风险确认。
func _on_gold_changed(_amount: int) -> void:
	if visible:
		_risk_confirmed = false
		_refresh_preview()

## 宽屏并列、窄屏上下排列；所有尺寸以缩放后的逻辑视口为准。
func _resize() -> void:
	if _box == null:
		return
	var logical := get_viewport_rect().size / SettingsRuntime.ui_scale_value()
	if logical.x <= 0.0 or logical.y <= 0.0:
		return
	var bag: Variant = get_node_or_null("../InventoryPanel")
	var width := minf(WIDTH, logical.x * 0.9)
	_box.custom_minimum_size.x = width
	var region := Vector2(width, logical.y)
	var bag_width := 540.0
	if bag != null and bag._center != null:
		bag_width = bag._center.panel_box.get_combined_minimum_size().x
	if logical.x >= bag_width + width + GAP + 24.0:
		var left := (logical.x - bag_width - width - GAP) * 0.5
		if bag != null and bag.visible:
			bag._center.set_docked(true, left / logical.x, (left + bag_width) / logical.x)
		_center.position = Vector2(left + bag_width + GAP, 0.0)
		region = Vector2(width, logical.y)
	else:
		if bag != null and bag.visible:
			bag._center.set_docked(true, 0.0, 1.0, 0.0, 0.48)
		_center.position = Vector2(0.0, logical.y * 0.48)
		region = Vector2(logical.x, logical.y * 0.52)
	_scroll.custom_minimum_size.y = clampf(region.y - 195.0, 32.0, 250.0)
	FloatingWindow.fit_content(region, _box, _scroll)
	_center.size = region

## 构建两列材料格和可滚动目标类型，按钮始终留在滚动区之外。
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
	_grid = FusionMaterialGrid.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_grid.item_dropped.connect(_on_material_dropped)
	form.add_child(_grid)
	for i in range(4):
		var slot := ItemSlot.new()
		slot.role = ItemSlot.ROLE_TRAY
		slot.index = i
		slot.apply_grid_base(SLOT_SIZE)
		slot.item_dropped.connect(_on_material_dropped)
		slot.pressed.connect(_clear_material.bind(i))
		_grid.add_child(slot)
		_slots.append(slot)
		_selected.append({})
		var remove := Button.new()
		remove.text = "×"
		remove.tooltip_text = Localization.tr_key("ui.fusion.remove")
		remove.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		remove.offset_left = -23
		remove.offset_right = -2
		remove.offset_top = 2
		remove.offset_bottom = 23
		remove.pressed.connect(_clear_material.bind(i))
		slot.add_child(remove)
		_remove_buttons.append(remove)
	_target_row = VBoxContainer.new()
	form.add_child(_target_row)
	var target_label := Label.new()
	target_label.text = Localization.tr_key("ui.fusion.target")
	_target_row.add_child(target_label)
	_target = OptionButton.new()
	_target.add_item(Localization.tr_key("ui.fusion.choose"))
	for kind in Equipment.slot_kinds():
		_target.add_item(Equipment.slot_label(Equipment.slots_for_kind(kind)[0]))
	_target.item_selected.connect(func(_i: int) -> void:
		_risk_confirmed = false
		_refresh_preview())
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
	actions.add_theme_constant_override("separation", 8)
	root.add_child(actions)
	_confirm = Button.new()
	_confirm.pressed.connect(_on_confirm)
	actions.add_child(_confirm)
	PanelChrome.style_action(_confirm, true)
	_random = Button.new()
	_random.text = Localization.tr_key("ui.fusion.random_fill")
	_random.tooltip_text = Localization.tr_key("ui.fusion.random_tip")
	_random.pressed.connect(_on_random_fill)
	actions.add_child(_random)
	PanelChrome.style_action(_random)
	_refresh_slots()

## 用实际实例 ID 定位玩家拥有的那件（先背包、后身上穿戴，口径见 `GameState.find_owned_item`），
## 不依赖可被整理改变的格子下标。
func _find_item(id: String) -> Dictionary:
	return GameState.find_owned_item(id).get("item", {})

## 验证拖拽载荷仍指向原背包装备，防止拖动期间整理或变更后误选。
func _source_item(payload: Dictionary) -> Dictionary:
	if int(payload.get("from", -1)) != ItemSlot.ROLE_BAG:
		return {}
	var index := int(payload.get("index", -1))
	if index < 0 or index >= GameState.inventory.size() or not GameState.inventory[index] is Dictionary:
		return {}
	var current: Dictionary = GameState.inventory[index]
	if current != payload.get("item", {}) or not Warehouse.token_matches(current, String(payload.get("token", ""))):
		return {}
	return current

## 验证载荷仍指向身上那件装备（工程 65）；拖动期间换装或卸下即失效。
func _source_equipped(payload: Dictionary) -> Dictionary:
	var slot_id := String(payload.get("slot_id", ""))
	if slot_id.is_empty():
		return {}
	var worn: Variant = GameState.equipment.get(slot_id)
	if not worn is Dictionary:
		return {}
	var current: Dictionary = worn
	if current != payload.get("item", {}) or not Warehouse.token_matches(current, String(payload.get("token", ""))):
		return {}
	return current

## 单格检查品质、星级、收藏和已选档位；完整四件仍由 EquipmentFusion 终验。
func _material_error(item: Dictionary, row: int) -> String:
	if row < 0 or row >= (2 if _mode == EquipmentFusion.STAR_TRANSFER else 4):
		return Localization.tr_key("ui.fusion.invalid_slot")
	if String(item.get("kind", "")) != "equip" or EquipmentFusion.tier_start(item) == 0 \
			or Equipment.item_kind(item).is_empty() or bool(item.get("favorite", false)):
		return Localization.tr_key("ui.fusion.invalid_material")
	var id := String(item.get("instanceId", ""))
	if id.is_empty():
		return Localization.tr_key("ui.fusion.invalid_material")
	for i in range(_selected.size()):
		if i != row and String(_selected[i].get("instanceId", "")) == id:
			return Localization.tr_key("ui.fusion.duplicate")
	var quality := String(item.get("quality", ""))
	var star := int(item.get("star", -1))
	if _mode == EquipmentFusion.GOLD_TO_PURPLE:
		return "" if quality == "epic" and star >= 0 and star <= Upgrade.max_star() else \
			Localization.tr_key("ui.fusion.gold_only")
	if _mode == EquipmentFusion.PURPLE_TARGET:
		if quality != "legendary" or star < 0 or star >= Upgrade.max_star():
			return Localization.tr_key("ui.fusion.purple_only")
		for i in range(4):
			if i != row and not _selected[i].is_empty() \
					and EquipmentFusion.tier_start(_selected[i]) != EquipmentFusion.tier_start(item):
				return Localization.tr_key("ui.fusion.same_tier")
		return ""
	if quality != "legendary" or star != (12 if row == 0 else 0):
		return Localization.tr_key("ui.fusion.old_role" if row == 0 else "ui.fusion.new_role")
	var other := _selected[1 - row]
	if not other.is_empty():
		var old := item if row == 0 else other
		var fresh := item if row == 1 else other
		var plan := EquipmentFusion.plan_transfer(old, fresh)
		if not bool(plan.get("ok", false)):
			return String(plan.get("reason", ""))
	return ""

## 接收背包或身上穿戴拖入（后者仅限打开了 `accept_equip_source` 的格）；
## 拒绝时说明原因，成功只保存快照并刷新预览。
func _on_material_dropped(row: int, payload: Dictionary) -> void:
	if not visible:
		return
	var from_equip := int(payload.get("from", -1)) == ItemSlot.ROLE_EQUIP
	if from_equip and (row < 0 or row >= _slots.size() or not _slots[row].accept_equip_source):
		_feedback.text = Localization.tr_key("ui.fusion.bag_only")
		return
	var item := _source_equipped(payload) if from_equip else _source_item(payload)
	if item.is_empty():
		_feedback.text = Localization.tr_key("ui.fusion.stale")
		return
	var error := _material_error(item, row)
	if not error.is_empty():
		_feedback.text = error
		return
	_selected[row] = item.duplicate(true)
	_risk_confirmed = false
	_feedback.text = ""
	_refresh_slots()
	_refresh_preview()

## 清空某一材料格，原物品一直留在背包。
func _clear_material(row: int) -> void:
	if row < 0 or row >= _selected.size() or _selected[row].is_empty():
		return
	_selected[row] = {}
	_risk_confirmed = false
	_feedback.text = ""
	_refresh_slots()
	_refresh_preview()

## 随机预选替换现有四格；无同档四件 0 星时不改变原选择。
func _on_random_fill() -> void:
	if _mode == EquipmentFusion.STAR_TRANSFER:
		return
	var picked := EquipmentFusion.random_materials(GameState.inventory, _mode)
	if picked.size() != 4:
		_feedback.text = Localization.tr_key("ui.fusion.random_empty")
		return
	for i in range(4):
		_selected[i] = picked[i]
	_risk_confirmed = false
	_feedback.text = ""
	_refresh_slots()
	_refresh_preview()

## 仅重置预选引用与风险状态，绝不扣除背包物品。
func _reset_materials() -> void:
	for i in range(_selected.size()):
		_selected[i] = {}
	_risk_confirmed = false
	if _feedback != null:
		_feedback.text = ""
	if _slots.size() == 4:
		_refresh_slots()
		_refresh_preview()

## 使用背包同款格子外观；向背包发出被选实例 ID 用于描边标记。
func _refresh_slots() -> void:
	var ids := PackedStringArray()
	for i in range(_slots.size()):
		var slot := _slots[i]
		slot.visible = i < (2 if _mode == EquipmentFusion.STAR_TRANSFER else 4)
		# 只有保星第一格（旧 12★）接收身上穿戴：第二格要的是 0★ 新料，
		# 从身上拖等于「先脱下来再当肥料」，收益不对等（工程 65 D1）。
		slot.accept_equip_source = _mode == EquipmentFusion.STAR_TRANSFER and i == 0
		var item := _selected[i]
		slot.item = item
		slot.text = ItemUtil.display_name(item).substr(0, 2) if not item.is_empty() else \
			(Localization.tr_key("ui.fusion.old_slot" if i == 0 else "ui.fusion.new_slot") if _mode == EquipmentFusion.STAR_TRANSFER else
			Localization.tr_key("ui.fusion.empty_slot", [i + 1]))
		slot.apply_grid_style(ItemUtil.quality_color(String(item.get("quality", "common"))) if not item.is_empty() else
			ItemSlot.GRID_BORDER, not item.is_empty())
		slot.tooltip_text = "%s\n%s" % [ItemUtil.display_name(item), "\n".join(PackedStringArray(ItemUtil.attr_lines(item)))] \
			if not item.is_empty() else ""
		_remove_buttons[i].visible = not item.is_empty() and slot.visible
		SampleArt.decorate(slot, SampleArt.icon_for(item))
		if not item.is_empty():
			ids.append(String(item.get("instanceId", "")))
	EventBus.fusion_selection_changed.emit(ids)

## 返回完整预选快照；材料不足时禁用合成。
func _material_snapshots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for i in range(2 if _mode == EquipmentFusion.STAR_TRANSFER else 4):
		if _selected[i].is_empty():
			return []
		result.append(_selected[i])
	return result

## 预览只读规则层；金币与目标类型改变时同步更新按钮状态。
func _refresh_preview() -> void:
	if _confirm == null:
		return
	_confirm.text = Localization.tr_key("ui.fusion.confirm_again") if _risk_confirmed else \
		Localization.tr_key("ui.fusion.transfer_action" if _mode == EquipmentFusion.STAR_TRANSFER else "ui.fusion.forge_action")
	_confirm.disabled = true
	var items := _material_snapshots()
	if items.is_empty():
		_summary.text = Localization.tr_key("ui.fusion.pick")
		return
	var kind := Equipment.slot_kinds()[_target.selected - 1] if _mode == EquipmentFusion.PURPLE_TARGET and _target.selected > 0 else ""
	var plan := EquipmentFusion.plan_transfer(items[0], items[1]) if _mode == EquipmentFusion.STAR_TRANSFER else \
		EquipmentFusion.plan_four(items, _mode, kind)
	if not bool(plan.get("ok", false)):
		_summary.text = String(plan.get("reason", ""))
		return
	var label := Localization.tr_key("ui.fusion.random_kind") if _mode == EquipmentFusion.GOLD_TO_PURPLE else \
		Equipment.slot_label(Equipment.slots_for_kind(String(plan.target_kind))[0])
	_summary.text = Localization.tr_key("ui.fusion.preview", ["%d—%d" % [int(plan.tier), int(plan.tier) + 9],
		label, " ★12" if _mode == EquipmentFusion.STAR_TRANSFER else " ★0"])
	if _mode == EquipmentFusion.STAR_TRANSFER:
		var gap := int(plan.get("gap", 1))
		if gap > 1:
			_summary.text += "\n" + Localization.tr_key("ui.fusion.gap", [gap, gap])
		_summary.text += "\n" + Localization.tr_key("ui.fusion.cost", [int(plan.cost), GameState.gold])
		var required := int(plan.get("required", 0))
		if required > int(GameState.player.get("level", 1)):
			_summary.text += "\n" + Localization.tr_key("ui.fusion.out_level",
				[required, int(GameState.player.get("level", 1))])
	_confirm.disabled = GameState.gold < int(plan.get("cost", 0))

## 带星材料与保星交易二次确认，最终仍由 GameState 快照重核。
func _on_confirm() -> void:
	if _confirm.disabled:
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
	# 材料可能正穿在身上（工程 65）：必须显式告知，否则玩家会以为战力凭空掉了。
	var worn_names: Array[String] = []
	for item in items:
		if String(GameState.find_owned_item(String(item.get("instanceId", ""))).get("loc", "")) == "worn":
			worn_names.append(ItemUtil.display_name(item))
	if risk and not _risk_confirmed:
		_risk_confirmed = true
		_feedback.text = Localization.tr_key("ui.fusion.star_warning") if _mode == EquipmentFusion.STAR_TRANSFER else \
			Localization.tr_key("ui.fusion.star_loss", [", ".join(PackedStringArray(stars))])
		if not worn_names.is_empty():
			_feedback.text += "\n" + Localization.tr_key("ui.fusion.worn_warning",
				[", ".join(PackedStringArray(worn_names))])
		_refresh_preview()
		return
	var kind := Equipment.slot_kinds()[_target.selected - 1] if _mode == EquipmentFusion.PURPLE_TARGET else ""
	var result := GameState.forge_equipment(_mode, items, kind)
	if bool(result.get("ok", false)):
		EventBus.toast_requested.emit(Localization.tr_key("ui.fusion.done", [ItemUtil.display_name(result.item)]), "pickup")
		_reset_materials()
	else:
		_feedback.text = String(result.get("reason", "合成失败"))
		_risk_confirmed = false
		_refresh_preview()
