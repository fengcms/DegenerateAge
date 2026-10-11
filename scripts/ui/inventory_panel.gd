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
## 占位素材（R5）：格内以模板名前 2 字 + 品质色描边表现，不加载图标。
## 拖拽丢弃 / 自动整理（5.8）、一键出售（6.4）留待 M4 / M1-8。

const SLOT_MIN := Vector2(46, 46)
const BAG_COLUMNS := 8
const EQUIP_COLUMNS := 2
const DOUBLE_CLICK_MS := 400

const COL_PANEL := Color(0.06, 0.07, 0.09, 0.97)
const COL_BORDER := Color(0.30, 0.33, 0.38, 0.95)
const COL_SLOT_BG := Color(0.13, 0.14, 0.17, 0.95)
const COL_SLOT_EMPTY := Color(0.10, 0.11, 0.13, 0.92)
const COL_SLOT_HOVER := Color(0.20, 0.22, 0.26, 0.98)
const COL_TEXT := Color(0.90, 0.92, 0.95)
const COL_TEXT_DIM := Color(0.52, 0.55, 0.60)

var _slot_buttons: Dictionary = {}          # slot_id -> Button
var _bag_buttons: Array[Button] = []
var _equip_title: Label
var _bag_title: Label
var _summary: Label
var _last_click_index: int = -1
var _last_click_ms: int = 0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	visible = false
	EventBus.inventory_changed.connect(_refresh)
	EventBus.equipment_changed.connect(_refresh)
	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.player_hp_changed.connect(_on_stat_changed)
	EventBus.player_mp_changed.connect(_on_stat_changed)
	EventBus.panel_opened.connect(_on_panel_opened)
	_refresh()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("panel_inventory"):
		set_open(not visible)
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed("pause"):
		set_open(false)
		get_viewport().set_input_as_handled()

## 开关面板；同步全局面板标志（角色操控在 player.gd 中据此屏蔽）。
func set_open(open: bool) -> void:
	visible = open
	GameState.set_panel_open("inventory", open)
	if open:
		EventBus.panel_opened.emit("inventory")
		_refresh()

## 其他面板（如货郎，M1-8）打开时自动关闭本面板，保证互斥。
func _on_panel_opened(panel_id: String) -> void:
	if panel_id != "inventory" and visible:
		set_open(false)

# ---- 构建 ----

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", _panel_style())
	center.add_child(box)

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
	title.text = "背包与装备"
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

	root.add_child(HSeparator.new())

	# 主体：左装备栏 / 右背包
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	root.add_child(body)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	body.add_child(left)
	_equip_title = Label.new()
	_equip_title.add_theme_font_size_override("font_size", 14)
	left.add_child(_equip_title)
	var equip_grid := GridContainer.new()
	equip_grid.columns = EQUIP_COLUMNS
	equip_grid.add_theme_constant_override("h_separation", 6)
	equip_grid.add_theme_constant_override("v_separation", 6)
	left.add_child(equip_grid)
	for d in Equipment.SLOT_DEFS:
		var sid := String(d.id)
		var b := _make_slot()
		b.tooltip_text = String(d.label)
		b.pressed.connect(_on_slot_pressed.bind(sid))
		equip_grid.add_child(b)
		_slot_buttons[sid] = b

	body.add_child(VSeparator.new())

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	body.add_child(right)
	_bag_title = Label.new()
	_bag_title.add_theme_font_size_override("font_size", 14)
	right.add_child(_bag_title)
	var bag_grid := GridContainer.new()
	bag_grid.columns = BAG_COLUMNS
	bag_grid.add_theme_constant_override("h_separation", 6)
	bag_grid.add_theme_constant_override("v_separation", 6)
	right.add_child(bag_grid)
	for i in range(GameState.inventory.size()):
		var b2 := _make_slot()
		b2.pressed.connect(_on_bag_pressed.bind(i))
		bag_grid.add_child(b2)
		_bag_buttons.append(b2)

	root.add_child(HSeparator.new())

	_summary = Label.new()
	_summary.add_theme_font_size_override("font_size", 14)
	root.add_child(_summary)

	var hint := Label.new()
	hint.text = "双击背包装备穿戴 · 点击装备槽卸下 · 悬停查看属性 · I / Esc 关闭"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", COL_TEXT_DIM)
	root.add_child(hint)

func _make_slot() -> Button:
	var b := Button.new()
	b.custom_minimum_size = SLOT_MIN
	b.clip_text = true
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_color_override("font_color", COL_TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", COL_TEXT)
	b.add_theme_color_override("font_focus_color", COL_TEXT)
	_apply_slot_style(b, COL_BORDER, false)
	return b

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

func _refresh() -> void:
	var worn := 0
	for d in Equipment.SLOT_DEFS:
		var sid := String(d.id)
		var b: Button = _slot_buttons[sid]
		var it = GameState.equipment.get(sid)
		if it is Dictionary:
			worn += 1
			var col := ItemUtil.quality_color(String(it.get("quality", "common")))
			b.text = _short_name(it)
			b.add_theme_color_override("font_color", col)
			_apply_slot_style(b, col, true)
			b.tooltip_text = _equip_tooltip(it, String(d.label))
		else:
			b.text = String(d.label)
			b.add_theme_color_override("font_color", COL_TEXT_DIM)
			_apply_slot_style(b, COL_BORDER, false)
			b.tooltip_text = "%s（空槽）" % String(d.label)
	_equip_title.text = "装备  %d / %d" % [worn, Equipment.SLOT_DEFS.size()]

	for i in range(_bag_buttons.size()):
		var b2: Button = _bag_buttons[i]
		var it2 = GameState.inventory[i] if i < GameState.inventory.size() else null
		if it2 is Dictionary:
			var col2 := _item_color(it2)
			b2.text = _short_name(it2)
			b2.add_theme_color_override("font_color", col2)
			_apply_slot_style(b2, col2, true)
			b2.tooltip_text = _bag_tooltip(it2)
		else:
			b2.text = ""
			_apply_slot_style(b2, COL_BORDER, false)
			b2.tooltip_text = ""
	_bag_title.text = "背包  %d / %d" % [GameState.inventory_used(), GameState.inventory.size()]
	_refresh_summary()

func _refresh_summary() -> void:
	if _summary == null:
		return
	var b := GameState.equip_bonus()
	var atk_b := int(round(float(b.get("atk", 0.0))))
	var def_b := int(round(float(b.get("def", 0.0))))
	_summary.text = "攻击 %d（装备 +%d）　防御 %d（装备 +%d）　生命 %d / %d　法力 %d / %d　金币 %d" % [
		GameState.total_attack(), atk_b,
		GameState.total_defense(), def_b,
		int(GameState.player.hp), GameState.max_hp(),
		int(GameState.player.mp), GameState.max_mp(),
		GameState.gold,
	]

func _on_gold_changed(_amount: int) -> void:
	_refresh_summary()

func _on_stat_changed(_current: int, _maximum: int) -> void:
	_refresh_summary()

# ---- 文本 ----

func _short_name(item: Dictionary) -> String:
	var nm: String = ItemUtil.template_name(item)
	return nm.substr(0, 2) if nm.length() > 2 else nm

func _item_color(item: Dictionary) -> Color:
	if String(item.get("kind", "")) == "equip":
		return ItemUtil.quality_color(String(item.get("quality", "common")))
	return ItemUtil.kind_color(String(item.get("kind", "misc")))

func _equip_tooltip(item: Dictionary, slot_label: String) -> String:
	var lines: Array[String] = []
	lines.append(ItemUtil.display_name(item))
	lines.append("%s · 需求等级 %d" % [slot_label, Equipment.level_req(item)])
	lines.append_array(ItemUtil.attr_lines(item))
	lines.append("")
	lines.append("点击卸下")
	return "\n".join(PackedStringArray(lines))

func _bag_tooltip(item: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append(ItemUtil.display_name(item))
	if String(item.get("kind", "")) != "equip":
		lines.append("（M1-7 仅装备可穿戴；药水使用 / 丢弃见后续子步骤）")
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
	lines.append("双击穿戴" if ok else "等级不足，无法穿戴")
	return "\n".join(PackedStringArray(lines))

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

func _on_slot_pressed(slot_id: String) -> void:
	if GameState.equipment.get(slot_id) == null:
		return
	GameState.unequip_slot(slot_id)

## 双击（400ms 内两次点击同一格）→ 穿戴。
func _on_bag_pressed(index: int) -> void:
	var now := Time.get_ticks_msec()
	if index == _last_click_index and now - _last_click_ms <= DOUBLE_CLICK_MS:
		_last_click_index = -1
		_last_click_ms = 0
		GameState.equip_from_inventory(index)
	else:
		_last_click_index = index
		_last_click_ms = now
