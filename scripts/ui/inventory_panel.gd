extends Control
## 背包与装备面板（M1-7）。
## 依据：产品文档 9.2（四面板之背包面板 / 人物装备槽）、5.1（14 槽）、5.8（40 格）、
##       5.9（评分对比）、5.2（穿戴门槛）、10.1（实例属性不重随）。
##
## 交互（MVP 最小版）：
##   I 开关（`panel_inventory`）、Esc 关闭；
##   双击背包中的装备 → 穿戴（自动选槽）；点击装备槽 → 卸下（需背包空位）；
##   悬停显示属性；装备类物品同时显示同槽已穿戴对比与评分高低（5.9）。
##   面板打开时屏蔽角色操控（不暂停世界模拟，见 player.gd）。
## 交易会话（M1-8 改造）：货郎开店时本面板**不关闭**，改为与货郎面板**并列**显示——
##   左半屏背包、右半屏货郎；背包格可把装备拖到出售托盘（6.4）。
## 通常打开时，可用药品/回城卷也可拖至 HUD 快捷栏；装备仍只在交易时开放拖出。
## 占位素材（R5）：格内以模板名前 2 字 + 品质色描边表现，不加载图标。
## 拖拽丢弃 / 自动整理（5.8）留待 M4。

const SLOT_MIN := Vector2(46, 46)
const BAG_COLUMNS := 8
const DOUBLE_CLICK_MS := 400

## 交易会话中本面板占据的屏幕横向区间（左侧），右侧留给货郎面板（见 shop_panel.gd）。
const TRADE_LEFT_RATIO := 0.60

const COL_PANEL := Color(0.06, 0.07, 0.09, 0.97)
const COL_BORDER := Color(0.30, 0.33, 0.38, 0.95)
const COL_SLOT_BG := Color(0.13, 0.14, 0.17, 0.95)
const COL_SLOT_EMPTY := Color(0.10, 0.11, 0.13, 0.92)
const COL_SLOT_HOVER := Color(0.20, 0.22, 0.26, 0.98)
const COL_TEXT := Color(0.90, 0.92, 0.95)
const COL_TEXT_DIM := Color(0.52, 0.55, 0.60)

var _bag_buttons: Array[ItemSlot] = []
var _bag_title: Label
var _organize_button: Button
var _expand_button: Button
var _bag_grid: GridContainer
var _summary: Label
var _center: FloatingWindow
var _dim: ColorRect
var _last_click_index: int = -1
var _last_click_ms: int = 0
## 交易会话（货郎开店中）：与货郎面板并列显示，背包格开放拖出（M1-8 改造）。
var _trade_active: bool = false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	visible = false
	EventBus.inventory_changed.connect(_refresh)
	EventBus.equipment_changed.connect(_refresh)
	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.panel_opened.connect(_on_panel_opened)
	EventBus.trade_mode_changed.connect(_on_trade_mode_changed)
	_refresh()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("panel_inventory"):
		# 交易会话中 I 键 = 结束整场交易（与货郎面板同步关闭），避免只关一半
		if _trade_active:
			EventBus.shop_close_requested.emit()
		else:
			set_open(not visible)
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed("pause"):
		if not _center.is_top_window():
			return
		if _trade_active:
			EventBus.shop_close_requested.emit()
		else:
			set_open(false)
		get_viewport().set_input_as_handled()

## 开关面板；同步全局面板标志（角色操控在 player.gd 中据此屏蔽）。
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
		var character := get_node_or_null("../CharacterPanel")
		if character != null and character.visible:
			character._refresh()

## 其他面板打开时自动关闭本面板，保证互斥——**例外**：交易会话中的货郎面板（见 05 方案）。
func _on_panel_opened(panel_id: String) -> void:
	if panel_id == "inventory":
		return
	if panel_id in ["shop", "character", "skill", "mount"]:
		if panel_id == "character" and visible:
			_refresh()
		return
	if visible:
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
		_apply_trade_layout(false)
		if visible:
			_refresh()

## 交易布局：左半屏居中 + 去遮罩（两层黑遮罩叠加会把对面面板压暗）；
## 普通布局：全屏居中 + 恢复遮罩。
func _apply_trade_layout(trade: bool) -> void:
	if _center == null:
		return
	_center.set_docked(trade, 0.0, TRADE_LEFT_RATIO)
	if _dim != null:
		_dim.visible = false
	for b in _bag_buttons:
		b.draggable = trade or not HotbarConfig.entry_for_item(b.item).is_empty()

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

	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", _panel_style())
	_center.add_child(box)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	box.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	# 标题行
	var head := HBoxContainer.new()
	root.add_child(head)
	var title := Label.new()
	title.text = "背包"
	title.add_theme_font_size_override("font_size", 18)
	head.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var close := Button.new()
	close.text = "×"
	close.custom_minimum_size = Vector2(32, 28)
	close.pressed.connect(func() -> void: set_open(false))
	head.add_child(close)
	_center.setup(self, box, head, Vector2(0.20, 0.30))

	root.add_child(HSeparator.new())

	# 背包只管理物品；穿戴槽与战斗属性统一放到人物面板。
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	root.add_child(right)
	var bag_head := HBoxContainer.new()
	right.add_child(bag_head)
	_bag_title = Label.new()
	_bag_title.add_theme_font_size_override("font_size", 14)
	_bag_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bag_head.add_child(_bag_title)
	_organize_button = Button.new()
	_organize_button.text = "整理"
	_organize_button.tooltip_text = "按品类整理背包并合并相同物品"
	_organize_button.pressed.connect(_on_organize_pressed)
	bag_head.add_child(_organize_button)
	_expand_button = Button.new()
	_expand_button.pressed.connect(_on_expand_pressed)
	bag_head.add_child(_expand_button)

	var bag_scroll := ScrollContainer.new()
	bag_scroll.custom_minimum_size = Vector2(410, 360)
	bag_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(bag_scroll)
	_bag_grid = GridContainer.new()
	_bag_grid.columns = BAG_COLUMNS
	_bag_grid.add_theme_constant_override("h_separation", 6)
	_bag_grid.add_theme_constant_override("v_separation", 6)
	bag_scroll.add_child(_bag_grid)
	_ensure_bag_slots()

	root.add_child(HSeparator.new())

	_summary = Label.new()
	_summary.add_theme_font_size_override("font_size", 14)
	root.add_child(_summary)

	var hint := Label.new()
	hint.text = "与人物面板并开可穿戴装备 · 双击使用药品 / 回城卷 · 装备可拖到货郎托盘 · I / Esc 关闭"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", COL_TEXT_DIM)
	root.add_child(hint)

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
	b.custom_minimum_size = SLOT_MIN
	b.clip_text = true
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_color_override("font_color", COL_TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", COL_TEXT)
	b.add_theme_color_override("font_focus_color", COL_TEXT)
	_apply_slot_style(b, COL_BORDER, false)

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

## filled = true 时以品质色描边（5.7），空槽用暗边。
func _apply_slot_style(b: Button, border: Color, filled: bool) -> void:
	var bg := COL_SLOT_BG if filled else COL_SLOT_EMPTY
	b.add_theme_stylebox_override("normal", _slot_style(bg, border))
	b.add_theme_stylebox_override("hover", _slot_style(COL_SLOT_HOVER, border))
	b.add_theme_stylebox_override("pressed", _slot_style(bg, border))
	b.add_theme_stylebox_override("focus", _slot_style(Color(0, 0, 0, 0), Color(0, 0, 0, 0)))
	b.add_theme_stylebox_override("disabled", _slot_style(bg, border))

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
			b2.draggable = _trade_active or not HotbarConfig.entry_for_item(it2).is_empty() \
				or (String(it2.get("kind", "")) == "equip" and _character_visible())
			b2.text = _short_name(it2)
			b2.add_theme_color_override("font_color", col2)
			_apply_slot_style(b2, col2, true)
			b2.tooltip_text = _bag_tooltip(it2)
		else:
			b2.item = {}
			b2.draggable = false
			b2.text = ""
			_apply_slot_style(b2, COL_BORDER, false)
			b2.tooltip_text = ""
		SampleArt.decorate(b2, SampleArt.icon_for(it2))
	_bag_title.text = "背包  %d / %d" % [GameState.inventory_used(), GameState.inventory.size()]
	var cost := Warehouse.next_cost(GameState.inventory_expansions)
	_expand_button.disabled = cost < 0
	_expand_button.text = "已达上限" if cost < 0 else "扩容 +%d（%d 金币）" % [
		Warehouse.capacity(GameState.inventory_expansions + 1) - GameState.inventory.size(), cost]
	_refresh_summary()

func _ensure_bag_slots() -> void:
	while _bag_buttons.size() < GameState.inventory.size():
		var index := _bag_buttons.size()
		var button := _make_item_slot(ItemSlot.ROLE_BAG, index)
		button.pressed.connect(_on_bag_pressed.bind(index))
		button.item_dropped.connect(_on_bag_item_dropped.bind(index))
		_bag_grid.add_child(button)
		_bag_buttons.append(button)
	while _bag_buttons.size() > GameState.inventory.size():
		var button: ItemSlot = _bag_buttons.pop_back()
		_bag_grid.remove_child(button)
		button.queue_free()

func _on_expand_pressed() -> void:
	GameState.inventory_expand()
	_refresh_summary()

func _refresh_summary() -> void:
	if _summary == null:
		return
	_summary.text = "金币  %d" % GameState.gold

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
		lines.append("需求等级 %d" % req)
	else:
		lines.append("需求等级 %d（当前 Lv%d，不足）" % [req, level])
	lines.append_array(ItemUtil.attr_lines(item))
	lines.append("")

	var worn := _worn_same_kind(item)
	var s_new := Equipment.score(item)
	if worn.is_empty():
		lines.append("同槽为空 · 评分 %.1f" % s_new)
	else:
		var s_old := Equipment.score(worn)
		var mark := "↑ 更高" if s_new > s_old else ("↓ 更低" if s_new < s_old else "＝ 持平")
		lines.append("已穿戴：%s" % ItemUtil.display_name(worn))
		lines.append("评分 %.1f vs %.1f　%s" % [s_new, s_old, mark])
	lines.append("")
	lines.append(("双击穿戴 / 拖到人物槽" if _character_visible() else "打开人物面板后可穿戴") if ok else "等级不足，无法穿戴")
	return "\n".join(PackedStringArray(lines))

## 非装备物品的 tooltip（M2.5）：药水显示恢复量 / 冷却 / 使用方式；
## 任务物与杂项明确说明不可使用（不静默）。
func _non_equip_tooltip(item: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var kind := String(item.get("kind", ""))
	if kind == "potion":
		var item_id := String(item.get("itemId", ""))
		var tpl = DataLoader.get_entry("potions", item_id)
		if tpl is Dictionary:
			var t: Dictionary = tpl
			var color := String(t.get("kind", Consumable.KIND_RED))
			out.append("恢复 %d %s" % [
				int(t.get("restoreAmount", 0)), Consumable.stat_label(color)])
			out.append("冷却 %ds（各药水独立计时，互不影响）" % int(t.get("cooldown", 0)))
			var key := "1" if color == Consumable.KIND_RED else "2"
			var left := Consumable.cd_of(item_id)
			if left > 0.0:
				out.append("")
				out.append("冷却中：还需 %.1fs" % left)
				return out
			out.append("")
			out.append("双击使用（或按 %s）" % key)
			return out
		out.append("（药水数据缺失）")
		return out
	if kind == "quest":
		out.append("任务物品，不可使用")
		return out
	if kind == "misc" and item.get("itemId") == HotbarConfig.TOWN_SCROLL:
		out.append("双击或拖到快捷栏使用；从野外返回幸存者营地")
		return out
	out.append("杂项物品，暂未开放使用（M4）")
	return out

## 同类型槽中第一件已穿戴装备（用于 5.9 对比）。
func _worn_same_kind(item: Dictionary) -> Dictionary:
	var kind := Equipment.item_kind(item)
	if kind.is_empty():
		return {}
	for sid in Equipment.slots_for_kind(kind):
		var it = GameState.equipment.get(sid)
		if it is Dictionary:
			return it
	return {}

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
	if not visible or not _character_visible() or int(payload.get("from", -1)) != ItemSlot.ROLE_EQUIP:
		return
	var sid := String(payload.get("slot_id", ""))
	var current: Variant = GameState.equipment.get(sid)
	if not current is Dictionary or not Warehouse.token_matches(current, String(payload.get("token", ""))):
		EventBus.toast_requested.emit("装备位置已变化，请重新拖动", "danger")
		return
	GameState.unequip_slot_to_inventory(sid, index)
