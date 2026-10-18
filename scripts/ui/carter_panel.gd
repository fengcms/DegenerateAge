extends Control
## 车夫面板（M3-2；产品文档 06 §6.6 / 07 §7.8，工程文档 13 §3 M3-2）。
##
## 打开方式：靠近车夫按 E → `game.gd::_try_interact` 派发 `EventBus.carter_panel_requested`；E / Esc 关闭。
##
## 内容：NPC 名 + 一行自我介绍 + 线路列表（目的地 · 推荐等级 · 费用 · 前往按钮）。
##   未解锁 / 金币不足 → 「前往」禁用并给出原因（不静默）。
## 前往成功 → `MapService.travel_to` 写入 `current_map` + `save_pos` 并重载场景，本面板随场景销毁。
##
## 形态与 QuestPanel 同构（拍板 D3-A）；6.3 的通用「对话 + 功能菜单」框架留 M4/M5-5。
##
## M10-7 起**一个节点两种模式**（`_portable`）：
##   当地车夫（NPC 交互 / 任务面板）= `destinations()` 平铺 + `travel_to`，渲染与原实现逐字一致；
##   随身车夫（`PanelRouter`）= `anywhere_destinations()` 七分组 + `travel_anywhere`。
## 判据只有本文件的两处（`_refresh` / `_on_travel`），其余渲染函数两种模式共用。

const PANEL_WIDTH := 560
const COL_PANEL := Color(0.06, 0.07, 0.09, 0.97)
const COL_BORDER := Color(0.30, 0.33, 0.38, 0.95)
const COL_TEXT_DIM := Color(0.52, 0.55, 0.60)
const COL_TITLE := Color(0.62, 0.80, 0.94)
const COL_GOLD := Color(0.94, 0.78, 0.38)
const COL_WARN := Color(0.88, 0.42, 0.36)

var _title: Label
var _list: VBoxContainer
var _hint: Label
var _center: CenterContainer
var _box: PanelContainer
var _scroll: ScrollContainer
var _dim: ColorRect
## M10-7：同一节点两种模式。`false` = 当地车夫（`destinations()` + `travel_to`），
## `true` = 随身车夫（`anywhere_destinations()` 七分组 + `travel_anywhere`）。
var _portable := false
## 当前渲染的分组键（当地模式恒为空）与行数 —— 只读访问器供测试，不含业务分支。
var _section_keys: Array[String] = []
var _row_count := 0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	visible = false
	EventBus.carter_panel_requested.connect(_on_requested)
	EventBus.panel_opened.connect(_on_panel_opened)
	EventBus.panels_close_requested.connect(func() -> void: set_open(false))
	EventBus.gold_changed.connect(_on_gold_changed)
	# F-P2-3：窗口 / 倍率 / 线路列表变化都可能改变内容自然高度，重新收敛尺寸。
	resized.connect(func() -> void: _update_layout.call_deferred())
	EventBus.settings_changed.connect(func() -> void: _update_layout.call_deferred())

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("pause"):
		set_open(false)
		get_viewport().set_input_as_handled()

# ---- 开关 ----

## `portable` 由信号第二参给出（M10-7）。同理 `PanelRouter` 传 `true`、NPC 交互传 `false`，
## 两个来源语义不同但共用一个节点 —— 只传标题会让随身车夫列成当地列表（工程 48 C-1）。
func _on_requested(npc_name: String, portable: bool = false) -> void:
	_portable = portable
	if not npc_name.is_empty():
		_title.text = PanelChrome.title_text(Localization.tr_key("ui.carter_panel.p001") % npc_name)
	set_open(true)

## 其他面板打开时自动关闭（与背包 / 货郎 / 任务面板互斥）。
func _on_panel_opened(panel_id: String) -> void:
	if panel_id == "carter":
		return
	if visible:
		set_open(false)

func _on_gold_changed(_amount: int) -> void:
	if visible:
		_refresh()

func set_open(open: bool) -> void:
	visible = open
	GameState.set_panel_open("carter", open)
	if open:
		_reset_hint()
		_refresh()
		EventBus.panel_opened.emit("carter")

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

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 12)
	box.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	root.add_child(head)
	PanelChrome.style_header_layout(margin, head)
	_title = Label.new()
	_title.text = Localization.tr_key("ui.carter_panel.p002")
	_title.add_theme_font_size_override("font_size", 18)
	head.add_child(_title)
	PanelChrome.style_title(_title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var close := Button.new()
	close.text = "×"
	close.custom_minimum_size = Vector2(32, 28)
	close.pressed.connect(func() -> void: set_open(false))
	head.add_child(close)
	PanelChrome.style_close(close)

	# F-P2-3：标题行留在外框渐变带内，自我介绍与线路列表整体可滚动。
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_scroll)
	var content := VBoxContainer.new()
	content.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	content.add_theme_constant_override("separation", 8)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(content)
	_box.minimum_size_changed.connect(func() -> void: _update_layout.call_deferred())

	var greet := Label.new()
	greet.text = Localization.tr_key("ui.carter_panel.p003")
	greet.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	greet.add_theme_font_size_override("font_size", 13)
	greet.add_theme_color_override("font_color", COL_TEXT_DIM)
	content.add_child(greet)

	var divider := HSeparator.new()
	PanelChrome.style_separator(divider)
	content.add_child(divider)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	content.add_child(_list)

	_hint = Label.new()
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_font_size_override("font_size", 12)
	content.add_child(_hint)

	_update_layout()

## F-P2-3：把面板收敛到逻辑视口内；未超出时布局不变，超出部分由内容滚动条承载。
func _update_layout() -> void:
	if _center == null or _box == null or _scroll == null:
		return
	FloatingWindow.fit_content(_center.size, _box, _scroll)

func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL
	sb.border_color = COL_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	return sb

# ---- 刷新 ----

func _reset_hint() -> void:
	# 随身价（20 × 等级、下限 50）与当地 `carterFares` 是**两套价**：
	# 同一目的地会出现两个数字，必须解释来源，否则玩家会当成 bug（工程 48 R-4）。
	if _portable:
		_hint.text = Localization.tr_key("ui.carter_panel.p011")
	else:
		_hint.text = Localization.tr_key("ui.carter_panel.p004") % GameState.gold
	_hint.add_theme_color_override("font_color", COL_TEXT_DIM)

func _refresh() -> void:
	if _list == null:
		return
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_section_keys.clear()
	_row_count = 0
	var dests: Array = MapService.anywhere_destinations() if _portable else MapService.destinations()
	if dests.is_empty():
		var l := Label.new()
		l.text = Localization.tr_key("ui.carter_panel.p005")
		l.add_theme_color_override("font_color", COL_TEXT_DIM)
		_list.add_child(l)
		return
	if not _portable:
		for d in dests:
			_list.add_child(_make_row(d as Dictionary))
			_row_count += 1
		return
	# 随身模式：按 LEVEL_GROUPS 的**固定顺序**分组渲染；空组整段跳过（不显示空标题）。
	var by_group: Dictionary = {}
	for d in dests:
		var key := String((d as Dictionary).get("group", ""))
		if not by_group.has(key):
			by_group[key] = []
		(by_group[key] as Array).append(d)
	for raw_key in MapService.LEVEL_GROUPS:
		var key := String(raw_key)
		if not by_group.has(key):
			continue
		_section_keys.append(key)
		_list.add_child(_make_section(key))
		for d in by_group[key]:
			_list.add_child(_make_row(d as Dictionary))
			_row_count += 1

## 分组标题：循环图组用专名（等级对 60+ 无意义，c7_arena 与 51-60 组同为 60）。
func _make_section(key: String) -> Control:
	var l := Label.new()
	l.text = Localization.tr_key("ui.carter_panel.p013") if key == "60+" \
		else Localization.tr_key("ui.carter_panel.p012") % key
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", COL_TITLE)
	return l

## 只读访问器（同 `BossHealthBar.bar_count()` 规格）：测试用它确认模式串到了 UI。
func section_keys() -> Array[String]:
	return _section_keys.duplicate()

func row_count() -> int:
	return _row_count

## 提示行文本（失败原因落在这里）。测试用它确认**选对了哪条出行 API**：
## 金币不足时 `travel_anywhere` 报「金币不足」、`travel_to` 报「车夫无法直达」，两者不通用。
func hint_text() -> String:
	return _hint.text if _hint != null else ""

func _make_row(d: Dictionary) -> Control:
	var map_id := String(d.get("id", ""))
	var unlocked := bool(d.get("unlocked", true))
	var cost := int(d.get("cost", 0))
	var afford := GameState.gold >= cost

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _row_style(unlocked, afford))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	panel.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	margin.add_child(row)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	row.add_child(info)

	var title := Label.new()
	title.text = String(d.get("name", map_id))
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", COL_TITLE if unlocked else COL_TEXT_DIM)
	info.add_child(title)

	var sub := Label.new()
	sub.text = Localization.tr_key("ui.carter_panel.p006") % [int(d.get("recommendedLevel", 1)), _fee_text(cost)]
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", COL_GOLD if cost > 0 else COL_TEXT_DIM)
	info.add_child(sub)

	row.add_child(_make_travel_button(d, unlocked, afford))
	return panel

## 目的地行由调用方传入：原本这里会**再调一次** `destinations()` 反查原因，
## 随身模式下列表来自 `anywhere_destinations()`，反查会拿到错的一组（工程 48 C-1）。
func _make_travel_button(d: Dictionary, unlocked: bool, afford: bool) -> Button:
	var map_id := String(d.get("id", ""))
	var b := Button.new()
	b.text = Localization.tr_key("ui.carter_panel.p007")
	b.custom_minimum_size = Vector2(84, 30)
	if not unlocked:
		b.disabled = true
		b.tooltip_text = String(d.get("reason", Localization.tr_key("ui.carter.locked")))
	elif not afford:
		b.disabled = true
		b.tooltip_text = Localization.tr_key("ui.carter_panel.p008") % GameState.gold
	else:
		b.pressed.connect(_on_travel.bind(map_id))
	PanelChrome.style_action(b, unlocked and afford)
	return b

func _row_style(unlocked: bool, afford: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(4)
	sb.set_border_width_all(1)
	if not unlocked:
		sb.bg_color = Color(0.09, 0.10, 0.12, 0.9)
		sb.border_color = Color(0.22, 0.24, 0.28, 0.8)
	elif not afford:
		sb.bg_color = Color(0.14, 0.11, 0.11, 0.95)
		sb.border_color = Color(COL_WARN.r, COL_WARN.g, COL_WARN.b, 0.45)
	else:
		sb.bg_color = Color(0.13, 0.14, 0.17, 0.95)
		sb.border_color = COL_BORDER
	return sb

func _fee_text(cost: int) -> String:
	return Localization.tr_key("ui.carter_panel.p009") if cost <= 0 else Localization.tr_key("ui.carter_panel.p010") % cost

# ---- 交互 ----

func _on_travel(map_id: String) -> void:
	# 随身车夫不要求拓扑相邻（M10-5 的 `travel_anywhere`；两者共用 `_travel_checks`）。
	var res := MapService.travel_anywhere(map_id) if _portable else MapService.travel_to(map_id)
	if bool(res.get("ok", false)):
		set_open(false)
		MapService.reload_world()   # 场景重载；抵达提示由 Game._ready 发出
		return
	var reason := String(res.get("reason", Localization.tr_key("ui.carter.travel_failed")))
	_hint.text = reason
	_hint.add_theme_color_override("font_color", COL_WARN)
	EventBus.toast_requested.emit(reason, "danger")
	_refresh()
