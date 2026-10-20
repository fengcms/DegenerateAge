extends Control
## 追猎令牌面板（M10-5；产品文档 13 §5.4）。
##
## 打开方式：双击背包里的「追猎令牌」（`PanelRouter.open("boss_token")` → 本面板）。
## 内容：走过的地图上所有已知 Boss —— 怪物名 / 等级 / 预计掉落等级 / 存活或冷却倒计时，
##       右侧一个动作按钮：当前图「追猎」（直接走过去），跨图「前往（车费）」。
##
## 三条性能约定（工程 46 §6 R-4 / R-5）：
## 1. `BossToken.rows()` **只在打开时调一次**；之后 `_process` 只改已有行的倒计时文字，
##    绝不重建列表、也不重新遍历 36 张地图。
## 2. 刷新节流 0.25s —— 27 行 × 每秒重算既无意义也占开销。
## 3. 行数固定，靠 `ScrollContainer` + `FloatingWindow.fit_content` 收敛，不动态增长。

const PANEL_WIDTH := 600
## 工程 80 紧凑化：原行高约 56px，营地视图 2788px（视口可用约 716px ⇒ 3.9 屏）。
const ROW_MARGIN_H := 8
const ROW_MARGIN_V := 4
const ROW_TITLE_SIZE := 14
const ROW_SUB_SIZE := 11
const STATUS_WIDTH := 96
const ACTION_BUTTON_SIZE := Vector2(96, 28)
## 该图的 Boss 行数超过这个数才按 `group` 折叠。c7_boss_field 100 席 / c7_arena 20 席会折，
## 存量单点 `bossSpawn`（没有 group 字段）保持平铺。
const FOLD_MIN_ROWS := 10
## 过滤三档（视图裁剪用，🔴 不回写规则层 `BossToken.rows()`）。
const FILTER_ALL := 0
const FILTER_ALIVE := 1
const FILTER_COOLDOWN := 2
const TICK_INTERVAL := 0.25
const COL_PANEL := Color(0.06, 0.07, 0.09, 0.97)
const COL_BORDER := Color(0.30, 0.33, 0.38, 0.95)
const COL_TEXT_DIM := Color(0.52, 0.55, 0.60)
const COL_TITLE := Color(0.62, 0.80, 0.94)
const COL_GOLD := Color(0.94, 0.78, 0.38)
const COL_WARN := Color(0.88, 0.42, 0.36)
const COL_ALIVE := Color(0.55, 0.82, 0.52)

var _title: Label
var _list: VBoxContainer
var _hint: Label
var _center: CenterContainer
var _box: PanelContainer
var _scroll: ScrollContainer
var _dim: ColorRect
## 行缓存：{row: Dictionary, status: Label}。倒计时只碰这里，不碰数据表。
var _rows: Array[Dictionary] = []
var _tick := 0.0
## 工程 80：**手风琴** —— 同时最多展开一组。旧实现用字典可多组同开，
## 全展开就是 +100 行（约 5600px），没有任何上限保护。改成单键后上限天然锁死。
var _expanded_group: String = ""
var _filter := FILTER_ALL
var _filter_bar: HBoxContainer
var _filter_buttons: Array[Button] = []
var _visible_row_count := 0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	visible = false
	EventBus.boss_token_panel_requested.connect(_on_requested)
	EventBus.panel_opened.connect(_on_panel_opened)
	EventBus.panels_close_requested.connect(func() -> void: set_open(false))
	EventBus.gold_changed.connect(_on_gold_changed)
	resized.connect(func() -> void: _update_layout.call_deferred())
	EventBus.settings_changed.connect(func() -> void: _update_layout.call_deferred())

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("pause"):
		set_open(false)
		get_viewport().set_input_as_handled()

## 倒计时是「面板打开照走」的（`world_time` 挂在 GameState 上）。Esc 暂停时随之冻结，
## 与墓碑口径一致 —— 不在这里自持时钟。
func _process(delta: float) -> void:
	if not visible or _rows.is_empty():
		return
	_tick += delta
	if _tick < TICK_INTERVAL:
		return
	_tick = 0.0
	for item in _rows:
		var row: Dictionary = item["row"]
		var status := item["status"] as Label
		if status == null or not is_instance_valid(status):
			continue
		var remaining := GameState.spawn_remaining(
			String(row.get("map_id", "")), String(row.get("monster_id", "")), int(row.get("ordinal", 0)))
		_set_status(status, remaining)

# ---- 开关 ----

func _on_requested(title: String) -> void:
	if not title.is_empty():
		_title.text = PanelChrome.title_text(title)
	set_open(true)

## 其他面板打开时自动关闭（与车夫 / 背包 / 货郎互斥）。
func _on_panel_opened(panel_id: String) -> void:
	if panel_id == "boss_token":
		return
	if visible:
		set_open(false)

func _on_gold_changed(_amount: int) -> void:
	if visible:
		_reset_hint()
		_rebuild()

func set_open(open: bool) -> void:
	visible = open
	GameState.set_panel_open("boss_token", open)
	if open:
		_tick = 0.0
		_filter = FILTER_ALL
		_expanded_group = _default_expanded()
		_refresh_filter_buttons()
		_reset_hint()
		_rebuild()
		EventBus.panel_opened.emit("boss_token")

## 站在一张需要折叠的图上时，默认展开它的 A 组（沿用旧行为）。
func _default_expanded() -> String:
	if GameState.current_map != "c7_boss_field":
		return ""
	return GameState.current_map + "|A"

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
	_title.text = PanelRouter.title("boss_token")
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

	content.add_child(_make_filter_bar())

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	content.add_child(_list)

	_hint = Label.new()
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_font_size_override("font_size", 12)
	content.add_child(_hint)

	_update_layout()

func _update_layout() -> void:
	if _center == null or _box == null or _scroll == null:
		return
	FloatingWindow.fit_content(_center.size, _box, _scroll)

# ---- 刷新 ----

func _reset_hint() -> void:
	_hint.text = Localization.tr_key("ui.boss_token_panel.p009") % GameState.gold
	_hint.add_theme_color_override("font_color", COL_TEXT_DIM)

## 唯一重建入口：只在打开 / 金币变化 / 过滤与折叠切换时调。`BossToken.rows()` 内部已排序。
func _rebuild() -> void:
	if _list == null:
		return
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_rows.clear()
	_visible_row_count = 0
	var rows := BossToken.rows()
	if rows.is_empty():
		_list.add_child(_empty_label(Localization.tr_key("ui.boss_token_panel.p001")))
		_update_layout.call_deferred()
		return
	# 过滤是**视图裁剪**，规则层 `BossToken.rows()` 一行不动（BossTokenTest 的锚点是 137 行）。
	var shown := _apply_filter(rows)
	if shown.is_empty():
		_list.add_child(_empty_label(Localization.tr_key("ui.boss_token_panel.p014")))
		_update_layout.call_deferred()
		return
	var groups := _fold_groups(shown)
	if not groups.is_empty():
		_list.add_child(_make_group_bar(groups))
	var fold_keys := {}
	for g in groups:
		fold_keys[String((g as Dictionary).get("key", ""))] = true
	var separated := false
	for row in shown:
		# 当前图置顶后拉一条分隔线；之后的行按推荐等级升序。
		if not separated and not bool(row.get("is_current_map", false)):
			separated = true
			var divider := HSeparator.new()
			PanelChrome.style_separator(divider)
			_list.add_child(divider)
		var key := String(row.get("map_id", "")) + "|" + String(row.get("group", ""))
		if bool(fold_keys.get(key, false)) and key != _expanded_group:
			continue
		_list.add_child(_make_row(row))
		_visible_row_count += 1
	_update_layout.call_deferred()

func _empty_label(text: String) -> Control:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", COL_TEXT_DIM)
	return l

## 过滤只在这里发生：`rows` 是规则层原样的副本，裁剪结果不写回任何地方。
func _apply_filter(rows: Array) -> Array[Dictionary]:
	if _filter == FILTER_ALL:
		return rows
	var out: Array[Dictionary] = []
	for row in rows:
		if bool((row as Dictionary).get("alive", false)) == (_filter == FILTER_ALIVE):
			out.append(row as Dictionary)
	return out

## 需要折叠的组（有序，按出现顺序）：该图 Boss 行数 > `FOLD_MIN_ROWS` 且行带 `group`。
## 存量单点 `bossSpawn` 没有 group 字段 ⇒ 永远平铺。
func _fold_groups(rows: Array) -> Array[Dictionary]:
	var per_map: Dictionary = {}
	for row in rows:
		var mid := String((row as Dictionary).get("map_id", ""))
		per_map[mid] = int(per_map.get(mid, 0)) + 1
	var counts: Dictionary = {}
	for row in rows:
		var d: Dictionary = row as Dictionary
		var key := String(d.get("map_id", "")) + "|" + String(d.get("group", ""))
		counts[key] = int(counts.get(key, 0)) + 1
	var out: Array[Dictionary] = []
	var seen := {}
	for row in rows:
		var d: Dictionary = row as Dictionary
		var map_id := String(d.get("map_id", ""))
		var group := String(d.get("group", ""))
		if group.is_empty() or int(per_map.get(map_id, 0)) <= FOLD_MIN_ROWS:
			continue
		var key := map_id + "|" + group
		if seen.has(key):
			continue
		seen[key] = true
		out.append({"key": key, "map_id": map_id,
			"map_name": String(d.get("map_name", map_id)), "group": group,
			"count": int(counts.get(key, 0))})
	return out

## 组按钮**横排**（工程 80）：旧实现每个组按钮独占一整行，c7 两图共 15 个 ≈ 525px。
## 改成按图分段（小标题 + HFlowContainer），15 个按钮压到 3~4 行。
func _make_group_bar(groups: Array) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var by_map: Dictionary = {}
	var order: Array[String] = []
	for g in groups:
		var d: Dictionary = g as Dictionary
		var map_id := String(d.get("map_id", ""))
		if not by_map.has(map_id):
			by_map[map_id] = []
			order.append(map_id)
		(by_map[map_id] as Array).append(d)
	for map_id in order:
		var items: Array = by_map[map_id]
		var caption := Label.new()
		caption.text = String((items[0] as Dictionary).get("map_name", map_id))
		caption.add_theme_font_size_override("font_size", 11)
		caption.add_theme_color_override("font_color", COL_TEXT_DIM)
		box.add_child(caption)
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 4)
		flow.add_theme_constant_override("v_separation", 4)
		for g in items:
			var d: Dictionary = g as Dictionary
			var key := String(d.get("key", ""))
			var b := Button.new()
			b.text = "%s 组 · %d" % [String(d.get("group", "")), int(d.get("count", 0))]
			b.custom_minimum_size = Vector2(64, 24)
			b.add_theme_font_size_override("font_size", 11)
			b.add_theme_color_override("font_color", COL_TITLE if key == _expanded_group else COL_TEXT_DIM)
			b.pressed.connect(_toggle_group.bind(key))
			flow.add_child(b)
		box.add_child(flow)
	return box

## **手风琴**：展开新组即收起旧组，同时最多一组展开。
## 旧实现用字典可多组同开，全展开就是 +100 行（约 5600px），没有上限保护。
func _toggle_group(key: String) -> void:
	_expanded_group = "" if _expanded_group == key else key
	_rebuild()

func _make_filter_bar() -> Control:
	_filter_bar = HBoxContainer.new()
	_filter_bar.add_theme_constant_override("separation", 6)
	var keys := ["ui.boss_token_panel.p011", "ui.boss_token_panel.p012", "ui.boss_token_panel.p013"]
	for i in range(keys.size()):
		var b := Button.new()
		b.text = Localization.tr_key(keys[i])
		b.custom_minimum_size = Vector2(72, 26)
		b.add_theme_font_size_override("font_size", 12)
		b.pressed.connect(_on_filter.bind(i))
		_filter_bar.add_child(b)
		_filter_buttons.append(b)
	_refresh_filter_buttons()
	return _filter_bar

func _on_filter(mode: int) -> void:
	if _filter == mode:
		return
	_filter = mode
	_refresh_filter_buttons()
	_rebuild()

func _refresh_filter_buttons() -> void:
	for i in range(_filter_buttons.size()):
		_filter_buttons[i].add_theme_color_override(
			"font_color", COL_TITLE if i == _filter else COL_TEXT_DIM)

## 只读访问器：`BossToken.rows()` 是规则层口径（恒 137），这里只反映**当前建出来的行**。
func visible_row_count() -> int:
	return _visible_row_count

func filter_mode() -> int:
	return _filter

func set_filter(mode: int) -> void:
	_on_filter(mode)

func expanded_group() -> String:
	return _expanded_group

func toggle_group(key: String) -> void:
	_toggle_group(key)

func _make_row(row: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _row_style())

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", ROW_MARGIN_H)
	margin.add_theme_constant_override("margin_right", ROW_MARGIN_H)
	margin.add_theme_constant_override("margin_top", ROW_MARGIN_V)
	margin.add_theme_constant_override("margin_bottom", ROW_MARGIN_V)
	panel.add_child(margin)

	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	margin.add_child(line)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	line.add_child(info)

	var title := Label.new()
	var map_label := String(row.get("map_name", row.get("map_id", "")))
	if bool(row.get("is_current_map", false)):
		map_label += " · " + Localization.tr_key("ui.boss_token_panel.p007")
	title.text = "%s · %s" % [map_label, String(row.get("monster_name", ""))]
	title.add_theme_font_size_override("font_size", ROW_TITLE_SIZE)
	title.add_theme_color_override("font_color", COL_TITLE)
	info.add_child(title)

	var sub := Label.new()
	sub.text = Localization.tr_key("ui.boss_token_panel.p004") % [
		int(row.get("level", 1)), int(row.get("drop_level", 1))]
	sub.add_theme_font_size_override("font_size", ROW_SUB_SIZE)
	sub.add_theme_color_override("font_color", COL_GOLD)
	info.add_child(sub)

	var status := Label.new()
	status.custom_minimum_size = Vector2(STATUS_WIDTH, 0)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status.add_theme_font_size_override("font_size", 12)
	line.add_child(status)
	_set_status(status, float(row.get("remaining", 0.0)))
	_rows.append({"row": row, "status": status})

	line.add_child(_make_action(row))
	return panel

func _set_status(label: Label, remaining: float) -> void:
	if remaining <= 0.0:
		label.text = Localization.tr_key("ui.boss_token_panel.p002")
		label.add_theme_color_override("font_color", COL_ALIVE)
		return
	label.text = Localization.tr_key("ui.boss_token_panel.p003") % _mmss(remaining)
	label.add_theme_color_override("font_color", COL_TEXT_DIM)

func _mmss(seconds: float) -> String:
	var total := maxi(0, ceili(seconds))
	return "%02d:%02d" % [total / 60, total % 60]

func _make_action(row: Dictionary) -> Button:
	var is_current := bool(row.get("is_current_map", false))
	var cost := 0 if is_current else MapService.fee_anywhere(String(row.get("map_id", "")))
	var b := Button.new()
	b.custom_minimum_size = ACTION_BUTTON_SIZE
	if is_current:
		b.text = Localization.tr_key("ui.boss_token_panel.p005")
		PanelChrome.style_action(b, true)
		b.pressed.connect(_on_action.bind(row))
		return b
	b.text = Localization.tr_key("ui.boss_token_panel.p006")
	if not MapService.entry_gate_reason(String(row.get("map_id", "")), "carter").is_empty():
		b.disabled = true
		b.tooltip_text = "请从无尽回廊入口步行进入"
		PanelChrome.style_action(b, false)
		return b
	if not bool(row.get("unlocked", true)) or cost < 0:
		b.disabled = true
		b.tooltip_text = Localization.tr_key("msg.map_service.p016") % String(row.get("map_name", ""))
		PanelChrome.style_action(b, false)
		return b
	b.tooltip_text = Localization.tr_key("ui.boss_token_panel.p006") + " · " + str(cost)
	if GameState.gold < cost:
		b.disabled = true
		b.tooltip_text = Localization.tr_key("ui.boss_token_panel.p008") % cost
		PanelChrome.style_action(b, false)
		return b
	PanelChrome.style_action(b, true)
	b.pressed.connect(_on_action.bind(row))
	return b

func _row_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(4)
	sb.set_border_width_all(1)
	sb.bg_color = Color(0.13, 0.14, 0.17, 0.95)
	sb.border_color = COL_BORDER
	return sb

# ---- 交互 ----

## 同图：直接走过去（世界节点自己会 toast，这里不重复提示）。
## 跨图：先扣费切图，**成功之后**才 arm 落地意图 —— 反过来会在失败时留下幽灵指令。
func _on_action(row: Dictionary) -> void:
	var map_id := String(row.get("map_id", ""))
	var target: Variant = row.get("world_pos", Vector2.ZERO)
	if not target is Vector2:
		return
	if bool(row.get("is_current_map", false)):
		var world := get_tree().get_first_node_in_group("map_world")
		if world == null or not world.has_method("request_map_move"):
			return
		set_open(false)
		# `call` 而非直接调用：world 的静态类型是 Node，`request_map_move` 只在 Game 上，
		# 直接写会在 warnings_as_errors 下变成编译期报错。
		world.call("request_map_move", target)
		return
	var res := MapService.travel_anywhere(map_id)
	if not bool(res.get("ok", false)):
		var reason := String(res.get("reason", Localization.tr_key("ui.carter.travel_failed")))
		_hint.text = reason
		_hint.add_theme_color_override("font_color", COL_WARN)
		EventBus.toast_requested.emit(reason, "danger")
		_rebuild()
		return
	MapService.arm_landing_move(target)
	set_open(false)
	MapService.reload_world()
