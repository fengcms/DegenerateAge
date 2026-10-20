extends Control
## 背包面板：物品、整理、扩容、低级装备筛选与批量出售。
## 依据：产品文档 9.2（四面板之背包面板 / 人物装备槽）、5.1（14 槽）、5.8（40 格）、
##       5.9（评分对比）、5.2（穿戴门槛）、10.1（实例属性不重随）。
##
## 交互（MVP 最小版）：
##   I 开关（`panel_inventory`）、Esc 关闭；
##   与人物面板并开时可双击或拖放穿戴；单开时装备双击无效；
##   悬停显示属性；装备类物品同时显示同槽已穿戴对比与评分高低（5.9）。
##   面板打开时仍可操作角色与快捷栏；鼠标命中面板控件时优先处理背包操作。
## 交易会话（M1-8 改造）：货郎开店时本面板**不关闭**，改为与货郎面板**并列**显示——
##   左半屏背包、右半屏货郎；背包格可把装备拖到出售托盘（6.4）。
## 通常打开时，可用药品/回城卷拖至 HUD 快捷栏；与人物面板并开时装备可拖出。
## 占位素材（R5）：格内以模板名前 2 字 + 品质色描边表现，不加载图标。
## 背包格随购买容量动态增减，超出首屏的格子可滚动查看。

const SLOT_MIN := Vector2(52, 52)
const BAG_COLUMNS := 8
const DOUBLE_CLICK_MS := 400

## 交易会话中本面板占据的屏幕横向区间（左侧），右侧留给货郎面板（见 shop_panel.gd）。
const TRADE_LEFT_RATIO := 0.60

const COL_PANEL := Color(0.06, 0.07, 0.09, 0.97)
const COL_BORDER := Color(0.30, 0.33, 0.38, 0.95)
const COL_TEXT_DIM := Color(0.52, 0.55, 0.60)

var _bag_buttons: Array[ItemSlot] = []
var _bag_title: Label
var _organize_button: Button
var _expand_button: Button
var _sell_low_button: Button
var _bag_grid: GridContainer
var _summary: Label
var _center: FloatingWindow
var _dim: ColorRect
var _last_click_index: int = -1
var _last_click_ms: int = 0
## 交易会话（货郎开店中）：与货郎面板并列显示，背包格开放拖出（M1-8 改造）。
var _trade_active: bool = false
var _fusion_active: bool = false
var _fusion_selected_ids := PackedStringArray()

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	visible = false
	EventBus.inventory_changed.connect(_refresh)
	EventBus.equipment_changed.connect(_refresh)
	EventBus.player_leveled.connect(func(_level: int) -> void: _refresh())
	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.panel_opened.connect(_on_panel_opened)
	EventBus.panels_close_requested.connect(func() -> void: set_open(false))
	EventBus.trade_mode_changed.connect(_on_trade_mode_changed)
	EventBus.fusion_mode_changed.connect(_on_fusion_mode_changed)
	EventBus.fusion_selection_changed.connect(_on_fusion_selection_changed)
	_refresh()

func _unhandled_input(event: InputEvent) -> void:
	if get_viewport().is_input_handled():
		return
	if event.is_action_pressed("panel_inventory"):
		# 交易会话中 I 键 = 结束整场交易（与货郎面板同步关闭），避免只关一半
		if _trade_active:
			EventBus.shop_close_requested.emit()
		elif _fusion_active:
			set_open(false)
		else:
			set_open(not visible)
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed("pause"):
		if _fusion_active:
			EventBus.equipment_fusion_close_requested.emit()
			get_viewport().set_input_as_handled()
			return
		if not _center.is_top_window():
			return
		if _trade_active:
			EventBus.shop_close_requested.emit()
		else:
			set_open(false)
		get_viewport().set_input_as_handled()

## 开关面板；同步全局可见面板集合，普通背包不阻断世界操控。
func set_open(open: bool) -> void:
	visible = open
	GameState.set_panel_open("inventory", open)
	var hud := get_node_or_null("../Hud")
	if hud != null:
		hud.set_hotbar_drop_mode(open)
	if open:
		EventBus.panel_opened.emit("inventory")
		_refresh()
		_center.show_window()
	else:
		if _fusion_active:
			EventBus.equipment_fusion_close_requested.emit()
		var character := get_node_or_null("../CharacterPanel")
		if character != null and character.visible:
			character._refresh()

## 其他面板打开时自动关闭本面板，保证互斥——**例外**：交易会话中的货郎面板（见 05 方案）。
## 并开集合统一由 `GameState.panels_coexist`（F-P3-1）判定，本面板不再自带名单。
func _on_panel_opened(panel_id: String) -> void:
	if panel_id == "character" and visible:
		_refresh()
	if visible and not (GameState.panels_coexist(panel_id, "inventory") or panel_id == "shop"):
		set_open(false)

# ---- 交易会话（M1-8 改造）----

## 进入 / 退出交易会话：切换布局、遮罩与背包格的拖出能力。
func _on_trade_mode_changed(active: bool) -> void:
	_trade_active = active
	if active:
		_apply_trade_layout(true)
		if not visible:
			set_open(true)
	else:
		_apply_trade_layout(_fusion_active)
		if visible:
			_refresh()

## 合成会话只改变布局与并开状态，材料始终留在背包。
func _on_fusion_mode_changed(active: bool) -> void:
	_fusion_active = active
	if active:
		_apply_trade_layout(true)
		if not visible:
			set_open(true)
	else:
		_apply_trade_layout(_trade_active)
		if visible:
			_refresh()

## 仅材料选择变化时刷新背包已选角标，不改变装备实例。
func _on_fusion_selection_changed(ids: PackedStringArray) -> void:
	_fusion_selected_ids = ids
	for button in _bag_buttons:
		button.fusion_selected = _fusion_active and _fusion_selected_ids.has(String(button.item.get("instanceId", "")))

## 交易布局：左半屏居中 + 去遮罩（两层黑遮罩叠加会把对面面板压暗）；
## 普通布局：全屏居中 + 恢复遮罩。
func _apply_trade_layout(trade: bool) -> void:
	if _center == null:
		return
	_center.set_docked(trade, 0.0, TRADE_LEFT_RATIO)
	if _dim != null:
		_dim.visible = false
	for b in _bag_buttons:
		b.draggable = not b.item.is_empty()

# ---- 构建 ----

func _build() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.35)
	_dim.visible = false
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)

	_center = FloatingWindow.new()
	_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_center)

	var box := PanelChrome.new()
	_center.add_child(box)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 12)
	box.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	# 标题行
	var head := HBoxContainer.new()
	root.add_child(head)
	PanelChrome.style_header_layout(margin, head)
	var title := Label.new()
	title.text = Localization.tr_key("ui.inventory_panel.p001")
	title.add_theme_font_size_override("font_size", 18)
	head.add_child(title)
	PanelChrome.style_title(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var help := PanelHelpButton.new()
	help.tooltip_text = Localization.tr_key("ui.inventory_panel.p013")
	head.add_child(help)
	PanelChrome.style_help(help)
	var close := Button.new()
	close.text = "×"
	close.custom_minimum_size = Vector2(32, 28)
	close.pressed.connect(func() -> void: set_open(false))
	head.add_child(close)
	PanelChrome.style_close(close)
	_center.setup(self, box, head, Vector2(0.02, 0.18))

	root.add_child(PanelChrome.make_title_gap())

	# F-P2-3：标题行外侧框内不动，标题以下的内容整体可滚动。容器未超出可见区时，
	# 这里的最小尺寸恰等于内容自然尺寸，布局与不加滚动时逐像素一致。
	var content_scroll := ScrollContainer.new()
	content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	content_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(content_scroll)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_scroll.add_child(content)
	_center.set_content_scroll(content_scroll)

	# 背包只管理物品；穿戴槽与战斗属性统一放到人物面板。
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	content.add_child(right)
	var bag_head := HBoxContainer.new()
	right.add_child(bag_head)
	_bag_title = Label.new()
	_bag_title.add_theme_font_size_override("font_size", 14)
	_bag_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bag_head.add_child(_bag_title)
	_summary = Label.new()
	_summary.add_theme_font_size_override("font_size", 14)
	_summary.add_theme_color_override("font_color", PanelChrome.GOLD_LIGHT)
	bag_head.add_child(_summary)
	var bag_divider := HSeparator.new()
	PanelChrome.style_separator(bag_divider)
	right.add_child(bag_divider)
	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 6)
	right.add_child(action_row)
	_organize_button = Button.new()
	_organize_button.text = Localization.tr_key("ui.inventory_panel.p002")
	_organize_button.tooltip_text = Localization.tr_key("ui.inventory_panel.p003")
	_organize_button.pressed.connect(_on_organize_pressed)
	action_row.add_child(_organize_button)
	PanelChrome.style_action(_organize_button)
	_expand_button = Button.new()
	_expand_button.pressed.connect(_on_expand_pressed)
	action_row.add_child(_expand_button)
	PanelChrome.style_action(_expand_button)
	_sell_low_button = Button.new()
	_sell_low_button.text = Localization.tr_key("ui.inventory_panel.p004")
	_sell_low_button.pressed.connect(_on_sell_low_pressed)
	action_row.add_child(_sell_low_button)
	PanelChrome.style_action(_sell_low_button)
	var bag_scroll := ScrollContainer.new()
	bag_scroll.custom_minimum_size = Vector2(460, 360)
	bag_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(bag_scroll)
	_bag_grid = GridContainer.new()
	_bag_grid.columns = BAG_COLUMNS
	_bag_grid.add_theme_constant_override("h_separation", 6)
	_bag_grid.add_theme_constant_override("v_separation", 6)
	bag_scroll.add_child(_bag_grid)
	_ensure_bag_slots()

	var divider := HSeparator.new()
	PanelChrome.style_separator(divider)
	content.add_child(divider)

	var hint := Label.new()
	hint.text = "左键查看 · 与人物面板并开时可拖放装备"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", PanelChrome.MUTED)
	content.add_child(hint)


## 背包格：使用 ItemSlot（可用物品拖到快捷栏；交易时装备可拖到出售托盘）。
## 人物面板的装备槽由 EquipmentSlot 负责，这里只创建背包等物品格。
func _make_item_slot(role: int, index: int) -> ItemSlot:
	var b := ItemSlot.new()
	b.role = role
	b.index = index
	_apply_slot_base(b)
	return b

## 格子通用外观（尺寸 / 字号 / 文字色 / 空槽描边）。
func _apply_slot_base(b: Button) -> void:
	(b as ItemSlot).apply_grid_base(SLOT_MIN)

func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL
	sb.border_color = COL_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	return sb

## filled = true 时以品质色描边（5.7），空槽用暗边。
func _apply_slot_style(b: Button, border: Color, filled: bool) -> void:
	(b as ItemSlot).apply_grid_style(border, filled)

# ---- 刷新 ----

func _on_organize_pressed() -> void:
	_last_click_index = -1
	_last_click_ms = 0
	GameState.organize_inventory()

func _refresh() -> void:
	_ensure_bag_slots()
	for i in range(_bag_buttons.size()):
		var b2: ItemSlot = _bag_buttons[i]
		var it2 = GameState.inventory[i] if i < GameState.inventory.size() else null
		if it2 is Dictionary:
			var col2 := _item_color(it2)
			b2.item = it2          # 供拖拽载荷携带（ItemSlot._get_drag_data）
			b2.fusion_selected = _fusion_active and _fusion_selected_ids.has(String(it2.get("instanceId", "")))
			b2.draggable = true
			b2.text = _short_name(it2)
			b2.add_theme_color_override("font_color", col2)
			_apply_slot_style(b2, col2, true)
			b2.tooltip_text = _bag_tooltip(it2)
			var preview := Equipment.replacement_preview(GameState.equipment, it2) if String(it2.get("kind", "")) == "equip" else {}
			b2.upgrade_badge_state = ItemSlot.UpgradeBadge.NONE
			if bool(preview.get("score_increase", false)):
				b2.upgrade_badge_state = ItemSlot.UpgradeBadge.READY if Equipment.meets_level(it2, int(GameState.player.level)) \
					else ItemSlot.UpgradeBadge.LEVEL_LOCKED
		else:
			b2.item = {}
			b2.fusion_selected = false
			b2.draggable = false
			b2.text = ""
			_apply_slot_style(b2, COL_BORDER, false)
			b2.tooltip_text = ""
			b2.upgrade_badge_state = ItemSlot.UpgradeBadge.NONE
		SampleArt.decorate(b2, SampleArt.icon_for(it2))
	_bag_title.text = Localization.tr_key("ui.inventory_panel.p014") % [GameState.inventory_used(), GameState.inventory.size()]
	var cost := Warehouse.next_cost(GameState.inventory_expansions)
	_expand_button.disabled = cost < 0
	_expand_button.text = Localization.tr_key("ui.inventory_panel.p015") if cost < 0 else Localization.tr_key("ui.inventory_panel.p016") % [
		Warehouse.capacity(GameState.inventory_expansions + 1) - GameState.inventory.size(), cost]
	_sell_low_button.disabled = int(GameState.player.get("level", 1)) < 15
	_sell_low_button.tooltip_text = Localization.tr_key("ui.inventory_panel.p017") if _sell_low_button.disabled else Localization.tr_key("ui.inventory_panel.p018")
	_refresh_summary()

func _ensure_bag_slots() -> void:
	while _bag_buttons.size() < GameState.inventory.size():
		var index := _bag_buttons.size()
		var button := _make_item_slot(ItemSlot.ROLE_BAG, index)
		button.pressed.connect(_on_bag_pressed.bind(index))
		button.item_dropped.connect(_on_bag_item_dropped.bind(index))
		button.gui_input.connect(_on_bag_slot_input.bind(index))
		_bag_grid.add_child(button)
		_bag_buttons.append(button)
	while _bag_buttons.size() > GameState.inventory.size():
		var button: ItemSlot = _bag_buttons.pop_back()
		_bag_grid.remove_child(button)
		button.queue_free()

func _on_expand_pressed() -> void:
	GameState.inventory_expand()

func _on_sell_low_pressed() -> void:
	EquipmentSalePreview.open_for(self, EquipmentSalePreview.DIRECT)

## 背包装备右键切换收藏，不影响原有左键双击和拖放入口。
func _on_bag_slot_input(event: InputEvent, index: int) -> void:
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_RIGHT or not event.pressed:
		return
	if index >= 0 and index < GameState.inventory.size() and GameState.inventory[index] is Dictionary:
		var item: Dictionary = GameState.inventory[index]
		if String(item.get("kind", "")) == "equip":
			GameState.set_equipment_favorite(String(item.get("instanceId", "")), not bool(item.get("favorite", false)))
			get_viewport().set_input_as_handled()

func _refresh_summary() -> void:
	if _summary == null:
		return
	_summary.text = Localization.tr_key("ui.inventory_panel.p019") % GameState.gold

func _on_gold_changed(_amount: int) -> void:
	_refresh_summary()

# ---- 文本 ----

func _short_name(item: Dictionary) -> String:
	var nm: String = ItemUtil.template_name(item)
	return nm.substr(0, 2) if nm.length() > 2 else nm

func _item_color(item: Dictionary) -> Color:
	if String(item.get("kind", "")) == "equip":
		return ItemUtil.quality_color(String(item.get("quality", "common")))
	return ItemUtil.kind_color(String(item.get("kind", "misc")))

func _bag_tooltip(item: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append(ItemUtil.display_name(item))
	if String(item.get("kind", "")) != "equip":
		lines.append_array(_non_equip_tooltip(item))
		return "\n".join(PackedStringArray(lines))

	var level := int(GameState.player.level)
	var req := Equipment.level_req(item)
	var ok := Equipment.meets_level(item, level)
	if ok:
		lines.append(Localization.tr_key("ui.inventory_panel.p020") % req)
	else:
		lines.append(Localization.tr_key("ui.inventory_panel.p021") % [req, level])
	# 工程 77：耐久行 + 破损红字；属性行照常列出（展示与生效分离，玩家能看见修好后拿回什么）。
	if item.has("durability"):
		lines.append(Localization.tr_key("ui.durability.line",
			[Durability.current(item), Durability.max_durability()]))
	if Durability.is_broken(item):
		lines.append(Localization.tr_key("ui.durability.broken"))
	lines.append_array(ItemUtil.attr_lines(item))
	lines.append("")
	lines.append((Localization.tr_key("ui.inventory_panel.p025") if _character_visible() else Localization.tr_key("ui.inventory_panel.p026")) if ok else Localization.tr_key("ui.inventory_panel.p027"))
	return "\n".join(PackedStringArray(lines))

## 非装备物品的 tooltip（M2.5）：药水显示恢复量 / 冷却 / 使用方式；
## 如意说明其为升星材料；任务物明确说明不可使用；杂项按其 useType 给出对应说明。
func _non_equip_tooltip(item: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var kind := String(item.get("kind", ""))
	if kind == "potion":
		var item_id := String(item.get("itemId", ""))
		var tpl = DataLoader.get_entry("potions", item_id)
		if tpl is Dictionary:
			var t: Dictionary = tpl
			var color := String(t.get("kind", Consumable.KIND_RED))
			# M10-10：显示**实际**恢复量而不是模板固定值 —— 玩家看到的数必须和喝下去的一致
			out.append(Localization.tr_key("ui.inventory_panel.p028") % [
				Consumable.preview_restore(item_id), Consumable.stat_label(color)])
			var pct := float(t.get("restorePercent", 0.0))
			if pct > 0.0:
				out.append(Localization.tr_key("ui.inventory_panel.p041") % int(round(pct * 100.0)))
			out.append(Localization.tr_key("ui.inventory_panel.p029") % int(t.get("cooldown", 0)))
			var key := "1" if color == Consumable.KIND_RED else "2"
			var left := Consumable.cd_of(item_id)
			if left > 0.0:
				out.append("")
				out.append(Localization.tr_key("ui.inventory_panel.p030") % left)
				return out
			out.append("")
			out.append(Localization.tr_key("ui.inventory_panel.p031") % key)
			return out
		out.append(Localization.tr_key("ui.inventory_panel.p032"))
		return out
	if kind == "quest":
		out.append(Localization.tr_key("ui.inventory_panel.p033"))
		return out
	if kind == "rune":
		var rune_tpl: Variant = DataLoader.get_entry("runes", String(item.get("itemId", "")))
		var bonus := 0.0
		if rune_tpl is Dictionary:
			bonus = float((rune_tpl as Dictionary).get("successBonus", 0.0))
		out.append(Localization.tr_key("ui.inventory_panel.p038") % int(round(bonus * 100.0)))
		return out
	# 杂项按数据表 useType 分流，而非按具体 id 硬编码；
	# 这样新增/调整过用途的物品不会落到兜底文案上显示成「未实现」。
	var use_type := ""
	var misc_tpl = DataLoader.get_entry("miscItems", String(item.get("itemId", "")))
	if misc_tpl is Dictionary:
		use_type = String((misc_tpl as Dictionary).get("useType", ""))
	match use_type:
		"townPortal":
			out.append(Localization.tr_key("ui.inventory_panel.p034"))
		"randomTeleport":
			out.append(Localization.tr_key("ui.inventory_panel.p035"))
		"revive":
			out.append(Localization.tr_key("ui.inventory_panel.p039"))
		"quest":
			out.append(Localization.tr_key("ui.inventory_panel.p033"))
		"panel":
			# M10-4（P-6）：面板类道具必须说明「双击会用」，否则文案和实际行为对不上。
			out.append(Localization.tr_key("ui.inventory_panel.p040") % PanelRouter.title(
				String((misc_tpl as Dictionary).get("panelId", ""))))
		_:
			out.append(Localization.tr_key("ui.inventory_panel.p036"))
	return out

# ---- 交互 ----

## 双击（400ms 内两次点击同一格）→ 使用 / 穿戴。
## M2.5：改走 `GameState.use_item`，由它按品类分流（药水 → 使用；装备 → 穿戴），
## 保证「双击装备仍穿戴」行为完全不变（工程文档 12 §5 R-b）。
func _on_bag_pressed(index: int) -> void:
	var now := Time.get_ticks_msec()
	if index == _last_click_index and now - _last_click_ms <= DOUBLE_CLICK_MS:
		_last_click_index = -1
		_last_click_ms = 0
		var item: Variant = GameState.inventory[index] if index >= 0 and index < GameState.inventory.size() else null
		if item is Dictionary and String(item.get("kind", "")) == "equip":
			if _character_visible():
				GameState.equip_from_inventory(index)
		else:
			GameState.use_item(index)
	else:
		_last_click_index = index
		_last_click_ms = now

func _character_visible() -> bool:
	var character := get_node_or_null("../CharacterPanel")
	return character != null and character.visible

func _on_bag_item_dropped(_target_index: int, payload: Dictionary, index: int) -> void:
	if visible and int(payload.get("from", -1)) == ItemSlot.ROLE_BAG:
		_last_click_index = -1
		_last_click_ms = 0
		GameState.move_inventory_item(int(payload.get("index", -1)), index, String(payload.get("token", "")))
		return
	if not visible or not _character_visible() or int(payload.get("from", -1)) != ItemSlot.ROLE_EQUIP:
		return
	var sid := String(payload.get("slot_id", ""))
	var current: Variant = GameState.equipment.get(sid)
	if not current is Dictionary or not Warehouse.token_matches(current, String(payload.get("token", ""))):
		EventBus.toast_requested.emit(Localization.tr_key("ui.inventory_panel.p037"), "danger")
		return
	GameState.unequip_slot_to_inventory(sid, index)
