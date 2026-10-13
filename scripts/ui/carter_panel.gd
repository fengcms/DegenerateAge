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
var _dim: ColorRect

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	visible = false
	EventBus.carter_panel_requested.connect(_on_requested)
	EventBus.panel_opened.connect(_on_panel_opened)
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
		_title.text = "%s　出行" % npc_name
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
	root.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	margin.add_child(root)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	root.add_child(head)
	_title = Label.new()
	_title.text = "车夫　出行"
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

	var greet := Label.new()
	greet.text = "「到过的地方，我都能直接送你去。头一趟先认认路。」"
	greet.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	greet.add_theme_font_size_override("font_size", 13)
	greet.add_theme_color_override("font_color", COL_TEXT_DIM)
	root.add_child(greet)

	root.add_child(HSeparator.new())

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	root.add_child(_list)

	_hint = Label.new()
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_font_size_override("font_size", 12)
	root.add_child(_hint)

func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL
	sb.border_color = COL_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	return sb

# ---- 刷新 ----

func _reset_hint() -> void:
	_hint.text = "点击「前往」扣费并切换地图。当前金币 %d。" % GameState.gold
	_hint.add_theme_color_override("font_color", COL_TEXT_DIM)

func _refresh() -> void:
	if _list == null:
		return
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var dests: Array = MapService.destinations()
	if dests.is_empty():
		var l := Label.new()
		l.text = "车夫暂无可用线路。"
		l.add_theme_color_override("font_color", COL_TEXT_DIM)
		_list.add_child(l)
		return
	for d in dests:
		_list.add_child(_make_row(d as Dictionary))

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
	sub.text = "推荐 Lv%d　·　%s" % [int(d.get("recommendedLevel", 1)), _fee_text(cost)]
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", COL_GOLD if cost > 0 else COL_TEXT_DIM)
	info.add_child(sub)

	row.add_child(_make_travel_button(map_id, unlocked, afford))
	return panel

func _make_travel_button(map_id: String, unlocked: bool, afford: bool) -> Button:
	var b := Button.new()
	b.text = "前往"
	b.custom_minimum_size = Vector2(84, 30)
	if not unlocked:
		b.disabled = true
		var reason := "尚未解锁"
		for destination in MapService.destinations():
			if String(destination.get("id", "")) == map_id:
				reason = String(destination.get("reason", reason))
				break
		b.tooltip_text = reason
	elif not afford:
		b.disabled = true
		b.tooltip_text = "金币不足（现有 %d）" % GameState.gold
	else:
		b.pressed.connect(_on_travel.bind(map_id))
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
	return "免费" if cost <= 0 else "%d 金" % cost

# ---- 交互 ----

func _on_travel(map_id: String) -> void:
	var res := MapService.travel_to(map_id)
	if bool(res.get("ok", false)):
		set_open(false)
		MapService.reload_world()   # 场景重载；抵达提示由 Game._ready 发出
		return
	var reason := String(res.get("reason", "无法前往"))
	_hint.text = reason
	_hint.add_theme_color_override("font_color", COL_WARN)
	EventBus.toast_requested.emit(reason, "danger")
	_refresh()
