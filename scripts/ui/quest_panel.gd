extends Control
## 任务面板（M2-2；产品文档 08 §8.5 / 09 §9.2 面板规范，工程文档 11 §4.4）。
##
## 打开方式：靠近任务官（长老）按 E → `game.gd::_try_interact` 派发
## `EventBus.quest_panel_requested`；E / Esc 关闭。
##
## 内容：NPC 名 + 一行自我介绍 + 任务列表（名称 · 描述 · 目标进度 + 状态按钮）。
## 状态按钮（08 §8.5 三态，本实现细化为 5 种渲染态）：
##   available  → 「接受任务」（可点）
##   active     → 「完成」（禁用，显示进度）
##   completed  → 「已完成」（可点 → 发放奖励，金色高亮）
##   rewarded   → 「✓ 已领奖」（禁用）
##   locked     → 「未解锁」（禁用）
## 支线（abandonable）在 active 时额外给「放弃」按钮（08 §8.2 / §8.4）。
##
## 占位素材（R5）：无图标，纯文字行 + 状态按钮。
## 留待 M5-5：9.8 逐句对话推进（点击继续）。

const PANEL_WIDTH := 620
const COL_PANEL := Color(0.06, 0.07, 0.09, 0.97)
const COL_BORDER := Color(0.30, 0.33, 0.38, 0.95)
const COL_TEXT := Color(0.90, 0.92, 0.95)
const COL_TEXT_DIM := Color(0.52, 0.55, 0.60)
const COL_MAIN := Color(0.94, 0.78, 0.38)
const COL_SIDE := Color(0.60, 0.78, 0.92)
const COL_DONE := Color(0.56, 0.82, 0.49)

var _title: Label
var _list: VBoxContainer
var _center: CenterContainer
var _dim: ColorRect
var _root: VBoxContainer
var _scroll: ScrollContainer

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	get_viewport().size_changed.connect(_update_layout)
	EventBus.settings_changed.connect(_update_layout)
	_update_layout.call_deferred()
	visible = false
	EventBus.quest_panel_requested.connect(_on_requested)
	EventBus.panel_opened.connect(_on_panel_opened)
	EventBus.quest_accepted.connect(_on_quest_changed)
	EventBus.quest_completed.connect(_on_quest_changed)
	EventBus.quest_rewarded.connect(_on_quest_changed)
	EventBus.quest_progressed.connect(_on_progressed)
	EventBus.gold_changed.connect(_on_gold_changed)

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("pause"):
		set_open(false)
		get_viewport().set_input_as_handled()

# ---- 开关 ----

func _on_requested(npc_name: String) -> void:
	if not npc_name.is_empty():
		_title.text = "%s　任务" % npc_name
	set_open(true)

## 其他面板打开时自动关闭（与背包 / 货郎面板互斥，I / E 键）。
func _on_panel_opened(panel_id: String) -> void:
	if panel_id == "quest":
		return
	if visible:
		set_open(false)

func set_open(open: bool) -> void:
	visible = open
	GameState.set_panel_open("quest", open)
	if open:
		_update_layout()
		_refresh()
		EventBus.panel_opened.emit("quest")

# ---- 事件回调 ----

func _on_quest_changed(_quest_id: String) -> void:
	if visible:
		_refresh()

func _on_progressed(_quest_id: String, _cur: int, _need: int) -> void:
	if visible:
		_refresh()

func _on_gold_changed(_amount: int) -> void:
	if visible:
		_refresh()

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
	_root = root
	root.add_theme_constant_override("separation", 8)
	root.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	margin.add_child(root)

	# 标题行：NPC 名 + 关闭
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	root.add_child(head)
	_title = Label.new()
	_title.text = "长老　任务"
	_title.add_theme_font_size_override("font_size", 18)
	head.add_child(_title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var close := Button.new()
	close.text = "×"
	close.custom_minimum_size = Vector2(32, 28)
	close.pressed.connect(func() -> void: set_open(false))
	head.add_child(close)

	# NPC 自我介绍（08 §8.5「自我介绍 + 任务列表」）
	var greet := Label.new()
	greet.text = "「守护者，末法之世要靠你了。这些事，先做起来。」"
	greet.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	greet.add_theme_font_size_override("font_size", 13)
	greet.add_theme_color_override("font_color", COL_TEXT_DIM)
	root.add_child(greet)

	root.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	_scroll = scroll
	scroll.custom_minimum_size = Vector2(PANEL_WIDTH, 460)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)

	var hint := Label.new()
	hint.text = "「完成」= 目标未达成（禁用）　·　「已完成」= 点击领取金币与经验奖励　·　E / Esc 关闭"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", COL_TEXT_DIM)
	root.add_child(hint)

func _update_layout() -> void:
	if _root == null or _scroll == null:
		return
	var logical := get_viewport().get_visible_rect().size / SettingsRuntime.ui_scale_value()
	_root.custom_minimum_size.x = minf(PANEL_WIDTH, maxf(280.0, logical.x - 48.0))
	_scroll.custom_minimum_size = Vector2(0, minf(460.0, maxf(100.0, logical.y - 132.0)))

func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL
	sb.border_color = COL_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	return sb

# ---- 刷新 ----

func _refresh() -> void:
	if _list == null:
		return
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var entries: Array[Dictionary] = Quest.list_states()
	if entries.is_empty():
		var l := Label.new()
		l.text = "暂无任务。"
		l.add_theme_color_override("font_color", COL_TEXT_DIM)
		_list.add_child(l)
		return
	for e in entries:
		_list.add_child(_make_row(e))

func _make_row(e: Dictionary) -> Control:
	var qid := String(e.get("id", ""))
	var state := String(e.get("state", ""))
	var is_side := String(e.get("type", "")) == "side"

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _row_style(state))

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
	title.text = "%s%s" % ["〔支线〕" if is_side else "", String(e.get("name", qid))]
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", _title_color(state, is_side))
	info.add_child(title)

	var sub := Label.new()
	var obj_text := String(e.get("objectiveText", ""))
	sub.text = obj_text if not obj_text.is_empty() else String(e.get("desc", ""))
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", COL_TEXT_DIM if state != Quest.STATE_REWARDED else Color(0.45, 0.60, 0.45))
	info.add_child(sub)

	# 完整描述放 tooltip（列表保持单行紧凑；08 §8.5 列表只要求「名称 / 目标 / 进度」）
	var desc := String(e.get("desc", ""))
	if not desc.is_empty():
		panel.tooltip_text = desc

	# 支线放弃按钮（仅进行中；08 §8.2 / §8.4）
	if is_side and state == Quest.STATE_ACTIVE:
		var ab := Button.new()
		ab.text = "放弃"
		ab.tooltip_text = "放弃后计数清零，可立即重接（08 §8.4）"
		ab.custom_minimum_size = Vector2(64, 30)
		ab.pressed.connect(_on_abandon.bind(qid))
		row.add_child(ab)

	row.add_child(_make_action_button(qid, state))
	return panel

## 状态按钮（08 §8.5 三态 + locked / rewarded 的禁用渲染）。
func _make_action_button(qid: String, state: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(92, 30)
	match state:
		Quest.STATE_AVAILABLE:
			b.text = "接受任务"
			b.pressed.connect(_on_accept.bind(qid))
		Quest.STATE_ACTIVE:
			b.text = "完成"
			b.disabled = true
			b.tooltip_text = "目标达成后可领取奖励"
		Quest.STATE_COMPLETED:
			b.text = "已完成"
			b.tooltip_text = "点击领取金币与经验奖励"
			b.add_theme_color_override("font_color", COL_DONE)
			b.pressed.connect(_on_deliver.bind(qid))
		Quest.STATE_REWARDED:
			b.text = "✓ 已领奖"
			b.disabled = true
		Quest.STATE_LOCKED:
			b.text = "未解锁"
			b.disabled = true
			b.tooltip_text = "前置任务未完成"
		_:
			b.text = "—"
			b.disabled = true
	return b

func _row_style(state: String) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(4)
	sb.set_border_width_all(1)
	match state:
		Quest.STATE_COMPLETED:
			sb.bg_color = Color(0.16, 0.20, 0.14, 0.95)
			sb.border_color = Color(COL_DONE.r, COL_DONE.g, COL_DONE.b, 0.7)
		Quest.STATE_REWARDED:
			sb.bg_color = Color(0.10, 0.11, 0.13, 0.92)
			sb.border_color = Color(0.25, 0.28, 0.32, 0.8)
		Quest.STATE_LOCKED:
			sb.bg_color = Color(0.09, 0.10, 0.12, 0.9)
			sb.border_color = Color(0.22, 0.24, 0.28, 0.8)
		_:
			sb.bg_color = Color(0.13, 0.14, 0.17, 0.95)
			sb.border_color = COL_BORDER
	return sb

func _title_color(state: String, is_side: bool) -> Color:
	if state == Quest.STATE_LOCKED:
		return COL_TEXT_DIM
	if state == Quest.STATE_REWARDED:
		return COL_DONE
	return COL_SIDE if is_side else COL_MAIN

# ---- 交互 ----

func _on_accept(qid: String) -> void:
	Quest.accept(qid)          # 失败原因由 Quest 广播 toast（不静默）
	_refresh()

func _on_deliver(qid: String) -> void:
	Quest.deliver(qid)         # 结算金币 / 经验 / 物品 / 解锁
	_refresh()

func _on_abandon(qid: String) -> void:
	Quest.abandon(qid)
	_refresh()
