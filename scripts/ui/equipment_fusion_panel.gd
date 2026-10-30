extends Control
## 铁匠四种合成 + 紫装献祭共用的工作台；背包物品只做预选引用，确认后才由 GameState 结算。
##
## 献祭（工程 87）复用这个面板骨架但不吃材料格：它扫整个背包、按档位分组汇总，
## 规则全在 `Sacrifice`，结算走 `GameState.sacrifice_purple`。

const PANEL_ID := "equipment_fusion"
const WIDTH := 430.0
const GAP := 12.0
const SLOT_SIZE := Vector2(78, 78)

var _mode := EquipmentFusion.GOLD_TO_PURPLE
var _box: PanelChrome
var _center: FloatingWindow
var _scroll: ScrollContainer
var _grid: FusionMaterialGrid
var _title: Label
var _hint: Label
var _summary: Label
## 工程 96：保星产物「暂时穿不上」的独立高亮行。**不拼进 `_summary`** ——
## 后者被四个模式共用，改它的颜色会波及其余三个。
var _out_level: Label
var _feedback: Label
var _confirm: Button
var _random: Button
var _target_row: Control
var _target: OptionButton
var _slots: Array[ItemSlot] = []
var _remove_buttons: Array[Button] = []
var _selected: Array[Dictionary] = []
var _risk_confirmed := false
## 献祭专用：12★ 是保星底件，默认不计入，需要显式勾选（勾了会在汇总里另起一行提示）。
var _star12: CheckBox
## 工程 112：如意压阵四格，**只在保星页显示**。四金 / 四紫定向本身 100% 必成，
## 四紫升紫是「件数换概率」的刻意设计（D2 拍板不吃如意），三处都没有可优化的掷点。
var _auto_runes: Button
var _rune_title: Label
var _rune_row: GridContainer
var _rune_pickers: Array[OptionButton] = []
var _rune_choices: Array[String] = ["", "", "", ""]
var _rune_hint: Label

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

## 铁匠菜单只能打开已登记的服务。
## 第三参 `portable`（工程 108）：合成与献祭**没有金币费用**（只消耗材料），
## 所以这里目前不参与任何计价 —— 收下并保存，是为了让「随身 / 回城」这条口径在
## 四个铁匠子面板里一致，将来若给合成加服务费，只有这一个入口需要接线。
var _portable := false

## 🔴 刻意**不给** `portable` 默认值：工程 108 把这个回调从单参改成双参时，漏改了
## 10 处「既有测试直接调用 `_on_requested(mode)`」的点，默认集当场红两项
## （`SCRIPT ERROR: Expected 2 argument(s)`）。加默认值确实能让它们静默变绿，
## 但那样「随身打开却按回城口径」在将来给合成加服务费时会**静默**发生 ——
## 上方注释写了「将来只有这一个入口需要接线」，所以它必须是强制的。
## 与 `equipment_fusion_panel_requested` 信号同为双参强制；漏传当场炸，才有牙。
func _on_requested(mode: String, portable: bool) -> void:
	if mode not in [EquipmentFusion.GOLD_TO_PURPLE, EquipmentFusion.PURPLE_TARGET,
			EquipmentFusion.PURPLE_UP_TIER, EquipmentFusion.STAR_TRANSFER,
			EquipmentFusion.SACRIFICE]:
		return
	_mode = mode
	_portable = portable
	set_open(true)

## 切换服务清空预选；关闭时释放引用，但不动背包中的真实装备。
func set_open(open: bool) -> void:
	if not open and not visible:
		return
	visible = open
	GameState.set_panel_open(PANEL_ID, open)
	_reset_materials()
	if open:
		var title_key := "ui.fusion.gold_title"
		var hint_key := "ui.fusion.gold_hint"
		match _mode:
			EquipmentFusion.PURPLE_TARGET:
				title_key = "ui.fusion.purple_title"
				hint_key = "ui.fusion.purple_hint"
			EquipmentFusion.PURPLE_UP_TIER:
				title_key = "ui.fusion.purple_up_title"
				hint_key = "ui.fusion.purple_up_hint"
			EquipmentFusion.STAR_TRANSFER:
				title_key = "ui.fusion.star_title"
				hint_key = "ui.fusion.star_hint"
			EquipmentFusion.SACRIFICE:
				title_key = "ui.sacrifice.title"
				hint_key = "ui.sacrifice.hint"
		_title.text = Localization.tr_key(title_key)
		_hint.text = Localization.tr_key(hint_key)
		# 献祭不选材料：材料格、目标类型、随机放入一律隐藏，只留汇总 + 确认。
		var batch_mode := _mode == EquipmentFusion.SACRIFICE
		_target_row.visible = _mode == EquipmentFusion.PURPLE_TARGET
		_random.visible = _mode not in [EquipmentFusion.STAR_TRANSFER, EquipmentFusion.SACRIFICE]
		_grid.visible = not batch_mode
		_star12.visible = batch_mode
		_star12.button_pressed = false
		var rune_mode := _mode == EquipmentFusion.STAR_TRANSFER
		_auto_runes.visible = rune_mode
		_rune_title.visible = rune_mode
		_rune_row.visible = rune_mode
		_rune_hint.visible = rune_mode
		_confirm.text = Localization.tr_key("ui.fusion.transfer_action" if _mode == EquipmentFusion.STAR_TRANSFER else
			("ui.sacrifice.action" if batch_mode else "ui.fusion.forge_action"))
		_refresh_slots()
		EventBus.fusion_mode_changed.emit(true)
		_resize.call_deferred()
		EventBus.panel_opened.emit(PANEL_ID)
		_center.show_window()
	else:
		EventBus.fusion_mode_changed.emit(false)
		EventBus.fusion_selection_changed.emit(PackedStringArray())

## 背包是工作台的会话伙伴；其他互斥面板打开时退出。
func _on_panel_opened(panel_id: String) -> void:
	if visible and not GameState.panels_coexist(panel_id, PANEL_ID):
		set_open(false)

## 整理或耐久磨损/修理保留同一材料，耐久以外的实例内容变化仍撤下预选。
## 身上那件被换下 / 被消耗也走同一次检查（工程 65）—— 第一格可能来自穿戴槽。
func _on_inventory_changed() -> void:
	_revalidate_selection()

func _on_equipment_changed() -> void:
	_revalidate_selection()

## 按实例 ID 核对材料；只允许耐久变化，并更新完整快照供提交时严格终验。
func _revalidate_selection() -> void:
	if not visible:
		return
	var invalid := false
	for i in range(_selected.size()):
		if _selected[i].is_empty():
			continue
		var found := _find_item(String(_selected[i].get("instanceId", "")))
		if found.is_empty() or not _same_material_except_durability(found, _selected[i]):
			_selected[i] = {}
			invalid = true
		elif found != _selected[i]:
			_selected[i] = found.duplicate(true)
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

## 宽屏并列、窄屏上下排列；分区比例一律按**缩放后的逻辑视口**折算。
## 并列分支把工作台做成**可拖动浮窗**，默认落在背包右侧（工程 74 §7）；玩家拖走后以实际位置为准。
## 窄屏退化时左右 / 上下按分区钉住，此时不可拖（拖动会与分区伙伴错位），与货郎并列布局同口径。
## 注意：面板根控件在游戏内由 `SettingsRuntime.apply_ui_scale_to` 撑成逻辑视口，故下述比例
## 与绝对坐标在游戏内逐像素一致；独立测试里的根控件没有那份尺寸，但它们本就不参与断言。
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
		_center.set_pinned(false)
		var panel_width := _box.get_combined_minimum_size().x
		_center.set_origin(Vector2((left + bag_width + GAP) / maxf(1.0, logical.x - panel_width), 0.5), true)
		region = Vector2(width, logical.y)
	else:
		if bag != null and bag.visible:
			bag._center.set_docked(true, 0.0, 1.0, 0.0, 0.48)
		_center.set_pinned(true, Rect2(0.0, logical.y * 0.48, logical.x, logical.y * 0.52))
		region = Vector2(logical.x, logical.y * 0.52)
	_scroll.custom_minimum_size.y = clampf(region.y - 195.0, 32.0, 250.0)
	FloatingWindow.fit_content(region, _box, _scroll)

## 构建两列材料格和可滚动目标类型，按钮始终留在滚动区之外。
func _build() -> void:
	_center = FloatingWindow.new()
	_center.set_anchors_preset(Control.PRESET_FULL_RECT)
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
	# 与其余浮窗同构：标题行拖动、点击置前、越界夹紧（工程 74 §7）。
	_center.setup(self, _box, header, Vector2(0.5, 0.5))
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
	# 工程 112：如意压阵。摆在材料格之后、汇总之前 —— 玩家看完两件材料就知道产物词条
	# 要重随机，这里正好是"要不要加钱买个好一点的随机"的决策点。
	_rune_title = Label.new()
	_rune_title.text = Localization.tr_key("ui.fusion.rune_title")
	PanelChrome.style_section(_rune_title)
	form.add_child(_rune_title)
	_auto_runes = Button.new()
	_auto_runes.text = Localization.tr_key("ui.fusion.auto_runes")
	_auto_runes.tooltip_text = Localization.tr_key("ui.fusion.auto_runes_tip")
	_auto_runes.custom_minimum_size.y = 38
	PanelChrome.style_action(_auto_runes)
	_auto_runes.pressed.connect(_on_auto_runes)
	form.add_child(_auto_runes)
	# 🔴 2×2 栅格，不是一行四格：四个下拉最小宽度合起来 588px，会把面板整体撑宽，
	# 而面板定位算式仍按原宽度算（与重铸面板同一个坑）。两列时最小宽度只有 290px。
	_rune_row = GridContainer.new()
	_rune_row.columns = 2
	_rune_row.add_theme_constant_override("h_separation", 8)
	_rune_row.add_theme_constant_override("v_separation", 6)
	form.add_child(_rune_row)
	for i in range(RuneCharge.SLOTS):
		var picker := OptionButton.new()
		picker.custom_minimum_size.y = 32
		picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		picker.item_selected.connect(_on_rune_selected.bind(i))
		_rune_row.add_child(picker)
		PanelChrome.style_option_button(picker)
		_rune_pickers.append(picker)
	_rune_hint = Label.new()
	_rune_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rune_hint.add_theme_font_size_override("font_size", 12)
	_rune_hint.add_theme_color_override("font_color", PanelChrome.MUTED)
	form.add_child(_rune_hint)
	_summary = Label.new()
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_summary)
	# 橙色而非红色：产物穿不上是跨档保星的**正常设计**（D3 产物永远进背包），
	# 不是错误状态。用 danger 红会让玩家以为操作失败了。
	_out_level = Label.new()
	_out_level.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_out_level.add_theme_color_override("font_color", Color("ffbd88"))
	root.add_child(_out_level)
	# 献祭专用开关：12★ 是保星底件，默认不计入（只在献祭模式显示）。
	_star12 = CheckBox.new()
	_star12.text = Localization.tr_key("ui.sacrifice.star12")
	_star12.tooltip_text = Localization.tr_key("ui.sacrifice.star12_tip")
	_star12.visible = false
	_star12.toggled.connect(func(_pressed: bool) -> void:
		_risk_confirmed = false
		_refresh_preview())
	root.add_child(_star12)
	root.move_child(_star12, _summary.get_index())
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

## 战斗会持续磨损穿戴装备；耐久不影响材料资格，不能把它视为换了材料。
## 仅排除耐久，身份、星级、词条、收藏等其余字段继续完整比较。
func _same_material_except_durability(current: Dictionary, snapshot: Variant) -> bool:
	if not snapshot is Dictionary:
		return false
	if current == snapshot:
		return true
	if current.get("kind") != "equip" or snapshot.get("kind") != "equip":
		return false
	var left := current.duplicate(true)
	var right: Dictionary = snapshot.duplicate(true)
	left.erase("durability")
	right.erase("durability")
	return left == right

## 验证拖拽载荷仍指向原背包装备，防止拖动期间整理或变更后误选。
func _source_item(payload: Dictionary) -> Dictionary:
	if int(payload.get("from", -1)) != ItemSlot.ROLE_BAG:
		return {}
	var index := int(payload.get("index", -1))
	if index < 0 or index >= GameState.inventory.size() or not GameState.inventory[index] is Dictionary:
		return {}
	var current: Dictionary = GameState.inventory[index]
	if not _same_material_except_durability(current, payload.get("item", {})) or not Warehouse.token_matches(current, String(payload.get("token", ""))):
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
	if not _same_material_except_durability(current, payload.get("item", {})) or not Warehouse.token_matches(current, String(payload.get("token", ""))):
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
	if _mode in [EquipmentFusion.PURPLE_TARGET, EquipmentFusion.PURPLE_UP_TIER]:
		if quality != "legendary" or star < 0 or star >= Upgrade.max_star():
			return Localization.tr_key("ui.fusion.purple_only" if _mode == EquipmentFusion.PURPLE_TARGET else
				"ui.fusion.purple_up_only")
		for i in range(_selected.size()):
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

## 随机预选替换全部材料格；只从最低合格档取，该档不足四件时空出余格（成功率随件数下降）。
func _on_random_fill() -> void:
	if _mode == EquipmentFusion.STAR_TRANSFER:
		return
	var picked := EquipmentFusion.random_materials(GameState.inventory, _mode)
	if picked.size() < EquipmentFusion.material_range(_mode).x:
		_feedback.text = Localization.tr_key("ui.fusion.random_empty")
		return
	for i in range(_selected.size()):
		_selected[i] = picked[i] if i < picked.size() else {}
	_risk_confirmed = false
	_feedback.text = ""
	_refresh_slots()
	_refresh_preview()

## 仅重置预选引用与风险状态，绝不扣除背包物品。
func _reset_materials() -> void:
	for i in range(_selected.size()):
		_selected[i] = {}
	# 工程 112：如意同理 —— 面板里存的只是「想投哪四枚」，真正扣除在结算成功时。
	for i in range(_rune_choices.size()):
		_rune_choices[i] = ""
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

## 返回已放入的材料快照（**允许空槽**，四紫升紫 2 件即可）；件数不在
## `EquipmentFusion.material_range()` 区间内时返回空数组，确认按钮随即禁用。
func _material_snapshots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for i in range(2 if _mode == EquipmentFusion.STAR_TRANSFER else _slots.size()):
		if _selected[i].is_empty():
			continue
		result.append(_selected[i])
	var limits := EquipmentFusion.material_range(_mode)
	if result.size() < limits.x or result.size() > limits.y:
		return []
	return result

## 预览只读规则层；金币与目标类型改变时同步更新按钮状态。
func _refresh_preview() -> void:
	if _confirm == null:
		return
	# 任何模式重算前先清空：否则切服务或撤下材料后，上一轮的「穿不上」会留在屏幕上。
	if _out_level != null:
		_out_level.text = ""
	if _mode == EquipmentFusion.SACRIFICE:
		_refresh_sacrifice()
		return
	# 工程 112：无论材料是否齐备都刷如意格 —— 先把"我有什么"摆出来，玩家才知道该不该去背包装。
	if _mode == EquipmentFusion.STAR_TRANSFER:
		_refresh_runes()
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
	var label := Localization.tr_key("ui.fusion.random_kind") if _mode in [
		EquipmentFusion.GOLD_TO_PURPLE, EquipmentFusion.PURPLE_UP_TIER] else \
		Equipment.slot_label(Equipment.slots_for_kind(String(plan.target_kind))[0])
	_summary.text = Localization.tr_key("ui.fusion.preview", ["%d—%d" % [int(plan.tier), int(plan.tier) + 9],
		label, " ★12" if _mode == EquipmentFusion.STAR_TRANSFER else " ★0"])
	if _mode == EquipmentFusion.PURPLE_UP_TIER:
		_summary.text = Localization.tr_key("ui.fusion.purple_up_preview", [
			int(plan.tier) - ItemFactory.TIER_SPAN,
			int(plan.tier) - ItemFactory.TIER_SPAN + 9,
			int(plan.tier), int(plan.tier) + 9])
		var rate := float(plan.get("rate", 1.0))
		_summary.text += "\n" + Localization.tr_key("ui.fusion.rate", [int(round(rate * 100.0))])
		if rate < 1.0:
			_summary.text += "\n" + Localization.tr_key("ui.fusion.rate_risk")
		if int(GameState.player.get("level", 1)) < int(plan.tier) + 9:
			_summary.text += "\n" + Localization.tr_key("ui.fusion.purple_up_level",
				[int(GameState.player.get("level", 1))])
	if _mode == EquipmentFusion.STAR_TRANSFER:
		var gap := int(plan.get("gap", 1))
		if gap > 1:
			_summary.text += "\n" + Localization.tr_key("ui.fusion.gap", [gap, gap])
		_summary.text += "\n" + Localization.tr_key("ui.fusion.cost", [int(plan.cost), GameState.gold])
		_refresh_out_level(plan)
	_confirm.disabled = GameState.gold < int(plan.get("cost", 0))

## 工程 96 P1：产物穿不上时把提示搬到独立高亮行。
## 判据来自规则层 `EquipmentFusion.transfer_locked_level`，UI 不自己写 `<`。
func _refresh_out_level(plan: Dictionary) -> void:
	if _out_level == null:
		return
	var level := int(GameState.player.get("level", 1))
	var need := EquipmentFusion.transfer_locked_level(int(plan.get("outputLevel", 0)), level)
	if need <= 0:
		return
	_out_level.text = Localization.tr_key("ui.fusion.out_level", [need, level, need - level])

## 工程 112：按背包实际枚数重填四格下拉（与重铸面板、升星面板同一范式）。
## 缺货档位置灰不删 —— 玩家要能看到「金如意已经用完了」，删掉会变成「这档不存在」。
func _refresh_runes() -> void:
	if _rune_pickers.is_empty():
		return
	var counts := RuneCharge.inventory_counts(GameState.inventory)
	_auto_runes.disabled = counts.is_empty()
	var remaining := counts.duplicate()
	for slot in range(_rune_choices.size()):
		var rune_id := _rune_choices[slot]
		if rune_id.is_empty():
			continue
		if int(remaining.get(rune_id, 0)) <= 0 or not DataLoader.get_entry("runes", rune_id) is Dictionary:
			_rune_choices[slot] = ""
			continue
		remaining[rune_id] = int(remaining[rune_id]) - 1
	var templates = DataLoader.get_table("runes")
	for slot in range(_rune_pickers.size()):
		var picker := _rune_pickers[slot]
		picker.clear()
		picker.add_item(Localization.tr_key("ui.fusion.rune_none"))
		picker.set_item_metadata(0, "")
		var selected_index := 0
		if templates is Array:
			for template in templates:
				if not template is Dictionary:
					continue
				var rune_id := String(template.get("id", ""))
				if rune_id.is_empty():
					continue
				var available := int(counts.get(rune_id, 0))
				var index := picker.item_count
				picker.add_item("%s ×%d" % [String(template.get("name", rune_id)), available])
				picker.set_item_metadata(index, rune_id)
				picker.set_item_disabled(index, available <= 0)
				if _rune_choices[slot] == rune_id:
					selected_index = index
		picker.select(selected_index)
	_refresh_rune_hint()

func _refresh_rune_hint() -> void:
	if _rune_hint == null:
		return
	if _rune_choices.count("") == _rune_choices.size():
		_rune_hint.text = Localization.tr_key("ui.fusion.rune_missing")
		return
	_rune_hint.text = Localization.tr_key("ui.fusion.rune_hint", [RuneCharge.tries(_rune_choices)])

func _on_rune_selected(choice_index: int, slot: int) -> void:
	if slot < 0 or slot >= _rune_pickers.size():
		return
	var picker := _rune_pickers[slot]
	_rune_choices[slot] = String(picker.get_item_metadata(choice_index)) if choice_index > 0 else ""
	_refresh_rune_hint()
	# 改了如意就等于改了"这一单要不要确认"，二次确认必须重来（与换材料同口径）。
	_risk_confirmed = false
	_refresh_preview()

## 带星材料、少于四件的赌局与保星交易都要二次确认，最终仍由 GameState 快照重核。
func _on_confirm() -> void:
	if _confirm.disabled:
		return
	if _mode == EquipmentFusion.SACRIFICE:
		_on_confirm_sacrifice()
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
	# 2—3 件是赌局：失败全损，必须显式说清成功率与「材料全没」，不能只靠预览里那行小字。
	var rate := 1.0 if _mode == EquipmentFusion.STAR_TRANSFER \
		else float(EquipmentFusion.success_rate(items.size()))
	if rate < 1.0:
		risk = true
	# 材料可能正穿在身上（工程 65）：必须显式告知，否则玩家会以为战力凭空掉了。
	var worn_names: Array[String] = []
	for item in items:
		if String(GameState.find_owned_item(String(item.get("instanceId", ""))).get("loc", "")) == "worn":
			worn_names.append(ItemUtil.display_name(item))
	# 工程 96 P2：产物穿不上必须在**决策点**再说一次 —— 预览行在第一次点击之前就显示了，
	# 但玩家那时的视线在按钮上，而且确认后预览会随材料一起清空。
	var level := int(GameState.player.get("level", 1))
	var locked_level := 0
	if _mode == EquipmentFusion.STAR_TRANSFER and items.size() >= 2:
		var plan := EquipmentFusion.plan_transfer(items[0], items[1])
		if bool(plan.get("ok", false)):
			locked_level = EquipmentFusion.transfer_locked_level(int(plan.get("outputLevel", 0)), level)
	if risk and not _risk_confirmed:
		_risk_confirmed = true
		var lines: Array[String] = []
		if _mode == EquipmentFusion.STAR_TRANSFER:
			lines.append(Localization.tr_key("ui.fusion.star_warning"))
		else:
			if rate < 1.0:
				lines.append(Localization.tr_key("ui.fusion.rate_loss",
					[int(round(rate * 100.0)), items.size()]))
			if not stars.is_empty():
				lines.append(Localization.tr_key("ui.fusion.star_loss", [", ".join(PackedStringArray(stars))]))
		# P4：身上件被吃 + 产物穿不上 = 该部位**净空一件**，是本流程唯一会掉战力的组合，
		# 比单独的「暂时穿不上」严重一档，单独用强化文案。
		if not worn_names.is_empty():
			var names := ", ".join(PackedStringArray(worn_names))
			lines.append(Localization.tr_key("ui.fusion.worn_locked_warning", [names, locked_level])
				if locked_level > 0 else Localization.tr_key("ui.fusion.worn_warning", [names]))
		elif locked_level > 0:
			lines.append(Localization.tr_key("ui.fusion.out_level_confirm",
				[locked_level, level, locked_level - level]))
		_feedback.text = "\n".join(PackedStringArray(lines))
		_refresh_preview()
		return
	var kind := Equipment.slot_kinds()[_target.selected - 1] if _mode == EquipmentFusion.PURPLE_TARGET else ""
	var result := GameState.forge_equipment(_mode, items, kind, null, _rune_choices.duplicate())
	if bool(result.get("ok", false)):
		# P3：用**产物实际等级**而不是上面的预估值 —— 万一口径哪天漂了，toast 也必须说真话。
		# 🔴 只加短后缀：`hud.gd` 的 toast 是单行 Label、无 autowrap，长文案会横向溢出屏幕。
		var gained: Dictionary = result.item
		var need := Equipment.level_req(gained)
		var text := Localization.tr_key("ui.fusion.done", [ItemUtil.display_name(gained)])
		if need > level:
			text = Localization.tr_key("ui.fusion.done_locked", [ItemUtil.display_name(gained), need])
		# 工程 112 D4：走了取优就必须说出来，否则四枚钻石如意的消耗在界面上不可见。
		var tries := int(result.get("tries", 1))
		if tries > 1:
			text += Localization.tr_key("ui.fusion.rune_best", [tries])
		EventBus.toast_requested.emit(text, "pickup")
		_reset_materials()
	elif bool(result.get("lost", false)):
		# 掷骰失败：材料已经被吃掉。只写小字会被当成「装备静默消失」，必须走 toast。
		EventBus.toast_requested.emit(String(result.get("reason", "")), "danger")
		_reset_materials()
	else:
		_feedback.text = String(result.get("reason", "合成失败"))
		_risk_confirmed = false
		_refresh_preview()

## 献祭预览：扫整个背包（不读材料格），按档位分组汇总；12★ 单列且默认不计入。
## 只读 `Sacrifice.plan`，不产生任何副作用。
func _refresh_sacrifice() -> void:
	var level := int(GameState.player.get("level", 1))
	_confirm.text = Localization.tr_key("ui.sacrifice.confirm_again" if _risk_confirmed
		else "ui.sacrifice.action")
	_confirm.disabled = true
	if level < Sacrifice.OPEN_LEVEL:
		_summary.text = Localization.tr_key("ui.sacrifice.low_level", [Sacrifice.OPEN_LEVEL])
		return
	var plan := Sacrifice.plan(GameState.inventory, _star12.button_pressed)
	var count := int(plan.get("count", 0))
	if count <= 0:
		_summary.text = Localization.tr_key("ui.sacrifice.empty")
		return
	var lines: Array[String] = []
	var raw_groups: Array = plan.get("groups", [])
	for raw in raw_groups:
		var group: Dictionary = raw
		var tier := int(group.get("tier", 0))
		lines.append(Localization.tr_key("ui.sacrifice.group",
			[tier, tier + 9, int(group.get("count", 0)), int(group.get("xp", 0))]))
	var gain := int(plan.get("xp", 0))
	var next := maxi(1, GameState.xp_to_next(level))
	var percent := int(round(float(gain) * 100.0 / float(next)))
	lines.append(Localization.tr_key("ui.sacrifice.summary", [count, gain, percent]))
	if int(plan.get("star12_count", 0)) > 0 and not _star12.button_pressed:
		lines.append(Localization.tr_key("ui.sacrifice.star12_hint",
			[int(plan.get("star12_count", 0)), int(plan.get("star12_xp", 0))]))
	if int(plan.get("remaining", 0)) > 0:
		lines.append(Localization.tr_key("ui.sacrifice.batch",
			[Sacrifice.MAX_BATCH, int(plan.get("remaining", 0))]))
	_summary.text = "\n".join(PackedStringArray(lines))
	_confirm.disabled = false

## 献祭结算：确认时**重新扫背包**（面板可能开很久），按实例 ID 交回 GameState 二次复核。
## 紫装献祭不可逆，所以第一次点击只做风险确认，第二次才真正消耗。
func _on_confirm_sacrifice() -> void:
	if int(GameState.player.get("level", 1)) < Sacrifice.OPEN_LEVEL:
		_feedback.text = Localization.tr_key("ui.sacrifice.low_level", [Sacrifice.OPEN_LEVEL])
		return
	var plan := Sacrifice.plan(GameState.inventory, _star12.button_pressed)
	var ids := PackedStringArray(plan.get("ids", PackedStringArray()))
	if ids.is_empty():
		_feedback.text = Localization.tr_key("ui.sacrifice.empty")
		_refresh_preview()
		return
	if not _risk_confirmed:
		_risk_confirmed = true
		_feedback.text = Localization.tr_key("ui.sacrifice.warning",
			[int(plan.get("count", 0)), int(plan.get("xp", 0))])
		_refresh_preview()
		return
	var result := GameState.sacrifice_purple(ids)
	_risk_confirmed = false
	if bool(result.get("ok", false)):
		EventBus.toast_requested.emit(Localization.tr_key("ui.sacrifice.done",
			[int(result.get("count", 0)), int(result.get("xp", 0))]), "pickup")
		_feedback.text = ""
	else:
		_feedback.text = String(result.get("reason", ""))
	_refresh_preview()

## 自动预选与手动换如意共用预览及二次确认失效流程。
func _on_auto_runes() -> void:
	if _mode != EquipmentFusion.STAR_TRANSFER or _auto_runes.disabled:
		return
	_rune_choices = RuneCharge.best_available(GameState.inventory)
	_risk_confirmed = false
	_feedback.text = ""
	_refresh_preview()
