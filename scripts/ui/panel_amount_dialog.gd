class_name PanelAmountDialog
extends Control
## 批量数量输入层（工程 110）：呈现汇率、收集一个整数、确认或取消。
##
## 🔑 职责边界与 `PanelConfirmDialog` 完全一致：**不决定任何业务状态**。
## 它不知道汇率怎么算、不知道仓库里有几块、不知道金币有多少 —— 只知道两件事：
##   ① 这次最多能换多少次（`max_times`，调用方查好传进来）
##   ② 输入 N 次会长什么样（`preview_provider`，调用方实现）
## 一旦它自己去读 `GoldExchange` / `GameState`，预览就成了与真正提交并行的第二套推导，
## 「预览说消耗 1 亿、实际扣了 1.1 亿」这类错位没有任何断言能抓到。
##
## 🔴 成员变量刻意不叫 `_input`：`Control` 有虚函数 `_input(event)`，同名会让事件转发
## 被变量遮蔽。Godot 不报错，只是弹框再也收不到 Esc。

signal submitted(times: int)

## 标题，如「金币 → 金条」。
var title: String = "":
	set(value):
		title = value
		if _title_label != null:
			_title_label.text = PanelChrome.title_text(value)

## 汇率说明行，如「1 次 = 金币 ×1000000 → 金条」。由调用方从数据推导，本层不参与计算。
var rate_text: String = "":
	set(value):
		rate_text = value
		if _rate_label != null:
			_rate_label.text = value

## 本次最多可换次数。0 表示当前不可换（调用方的入口按钮本就应该置灰）。
var max_times: int = 0:
	set(value):
		max_times = value
		if _edit != null:
			_refresh_state()

## 输入 N 次时的预览文案，返回 `{"cost": String, "got": String}`。
## 返回非字典时预览留空 —— 宁可空着，也不显示一段编出来的数字。
var preview_provider: Callable = Callable()

var _title_label: Label
var _rate_label: Label
var _edit: LineEdit
var _max_button: Button
## 第一行：常态显示「将消耗 …」，非法输入时改显原因并转成警示色。
## 刻意**不另开一行**提示 Label：多一行会让弹框高度随输入变化，
## 玩家一输超限值，整个框和底部按钮就跟着跳一下。
var _cost_label: Label
var _got_label: Label
var _confirm: Button

## 建立覆盖父面板的遮罩与共用切角外框，初始保持隐藏。
func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# 遮罩必须吃鼠标：否则弹框打开时还能点穿到底下的仓库格子。
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	visible = false

## 打开弹框：输入框默认填 1 并全选，玩家直接敲数字即可覆盖。
func popup() -> void:
	visible = true
	_title_label.text = PanelChrome.title_text(title)
	_rate_label.text = rate_text
	_edit.text = "1"
	_refresh_state()
	# 延后一帧：节点刚 visible 时焦点与选区操作会被布局顶掉。
	_edit.grab_focus.call_deferred()
	_edit.select_all.call_deferred()

## 关闭弹框。
## 🔑 这里**不写** `release_focus()`：Godot 在控件隐藏时（`NOTIFICATION_VISIBILITY_CHANGED`）
## 已经自动释放焦点，实测「删掉 release_focus 后行为完全一致」（110 负向 N-2 的副产物结论）。
## 世界输入的兜底是 `GameState.world_controls_blocked()` 里的 `is_visible_in_tree()` 判据，
## 不是这一行。留一段「看起来在防什么、其实不防」的代码，比没有更糟 —— 后人不舍得删。
func close() -> void:
	visible = false

## Esc 只关这一层。`_input` 早于父面板的 `_unhandled_input`，这里吃掉 pause
## 才不会连带把仓库面板一起关掉（110 方案 §6 R4）。改动此处务必跑 Esc 用例。
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()

# ---- 构建 ----

func _build() -> void:
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0, 0, 0, 0.55)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var chrome := PanelChrome.new()
	center.add_child(chrome)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 18)
	chrome.add_child(margin)
	var content := VBoxContainer.new()
	# 比确认框（390）宽一些：汇率说明要容得下「金币 ×10000000 → 金砖」。
	content.custom_minimum_size.x = 420
	content.add_theme_constant_override("separation", 10)
	margin.add_child(content)
	var header := HBoxContainer.new()
	content.add_child(header)
	PanelChrome.style_header_layout(margin, header)
	_title_label = Label.new()
	_title_label.text = PanelChrome.title_text(title)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title_label)
	PanelChrome.style_title(_title_label)
	content.add_child(PanelChrome.make_title_gap())
	_rate_label = Label.new()
	_rate_label.text = rate_text
	_rate_label.add_theme_font_size_override("font_size", 13)
	_rate_label.add_theme_color_override("font_color", PanelChrome.MUTED)
	_rate_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_rate_label)
	content.add_child(_make_input_row())
	_cost_label = _make_preview_line(PanelChrome.MUTED)
	content.add_child(_cost_label)
	_got_label = _make_preview_line(PanelChrome.GOLD_LIGHT)
	content.add_child(_got_label)
	content.add_child(_make_actions())

func _make_input_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var caption := Label.new()
	caption.text = Localization.tr_key("ui.warehouse_panel.p024")
	caption.custom_minimum_size.x = 72
	row.add_child(caption)
	_edit = LineEdit.new()
	_edit.custom_minimum_size = Vector2(148, 32)
	# 7 位足够（上限 9.99 亿金币 ÷ 100 万 ≈ 999 次），同时挡掉粘贴超长数字。
	_edit.max_length = 7
	_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	PanelChrome.style_line_edit(_edit)
	_edit.text_changed.connect(_on_text_changed)
	_edit.text_submitted.connect(_on_text_submitted)
	row.add_child(_edit)
	_max_button = Button.new()
	_max_button.pressed.connect(_on_max_pressed)
	row.add_child(_max_button)
	PanelChrome.style_action(_max_button)
	return row

func _make_preview_line(color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.y = 18
	return label

func _make_actions() -> HBoxContainer:
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 10)
	var cancel := Button.new()
	cancel.text = Localization.tr_key("ui.common.cancel")
	cancel.pressed.connect(close)
	actions.add_child(cancel)
	PanelChrome.style_action(cancel)
	_confirm = Button.new()
	_confirm.text = Localization.tr_key("ui.common.confirm")
	_confirm.pressed.connect(_on_confirm)
	actions.add_child(_confirm)
	PanelChrome.style_action(_confirm, true)
	return actions

# ---- 输入与刷新 ----

## 只留数字。`is_valid_int()` 只判整体，粘贴「1e5」「12块」这类要在这里剔干净。
func _on_text_changed(new_text: String) -> void:
	var filtered := ""
	for ch in new_text:
		if ch >= "0" and ch <= "9":
			filtered += ch
	if filtered != new_text:
		# 二次进入时 filtered == text，不会反复触发（不会死循环）。
		_edit.text = filtered
		_edit.caret_column = filtered.length()
	_refresh_state()

func _on_text_submitted(_text: String) -> void:
	_on_confirm()

func _on_max_pressed() -> void:
	_edit.text = str(maxi(1, max_times))
	_edit.caret_column = _edit.text.length()
	_refresh_state()

func _on_confirm() -> void:
	# 🔑 不拿 `_confirm.disabled` 当判据：那只是渲染结果，任何一次漏刷新
	# 都会让非法值被提交（输入过滤与禁用态是两层，这里必须自己再判一次）。
	var times := _parse_amount()
	if times < 1 or times > max_times:
		return
	# 先关再发信号：调用方会在信号里落账并刷新面板，弹框不必留在屏幕上。
	close()
	submitted.emit(times)

## 当前输入值；非法一律返回 0（调用方据此判「不可确认」）。
func _parse_amount() -> int:
	var text := _edit.text.strip_edges()
	# 🔴 不能直接 `to_int()`：超长数字串转 int 的溢出行为不可依赖。
	if text.is_empty() or not text.is_valid_int():
		return 0
	return maxi(0, text.to_int())

## 单一刷新入口：输入、上限变化、打开弹框都走这里，
## 避免「按钮能点但其实超限」与「明明够却灰着」两种错位同时存在。
##
## 🔑 两行预览**始终占位**（用空字符串而不是 `visible = false`）：否则弹框高度会随
## 输入合法性变化，玩家一输超限值整个框就跳一下，底部按钮的位置也跟着跑。
func _refresh_state() -> void:
	var times := _parse_amount()
	_max_button.text = Localization.tr_key("ui.warehouse_panel.p025") % max_times
	_max_button.disabled = max_times <= 0
	var reason := ""
	if times < 1:
		reason = Localization.tr_key("ui.warehouse_panel.p028") % max_times
	elif times > max_times:
		reason = Localization.tr_key("ui.warehouse_panel.p029") % max_times
	var cost := ""
	var got := ""
	if reason.is_empty() and preview_provider.is_valid():
		var preview: Variant = preview_provider.call(times)
		if preview is Dictionary:
			cost = Localization.tr_key("ui.warehouse_panel.p026") \
				% String((preview as Dictionary).get("cost", ""))
			got = Localization.tr_key("ui.warehouse_panel.p027") \
				% String((preview as Dictionary).get("got", ""))
	if reason.is_empty():
		_cost_label.text = cost
		_got_label.text = got
		_cost_label.add_theme_color_override("font_color", PanelChrome.MUTED)
	else:
		# 第一行兼任错误提示：同一行换内容而不是另开一行，弹框高度因此恒定。
		_cost_label.text = reason
		_got_label.text = ""
		_cost_label.add_theme_color_override("font_color", PanelChrome.DANGER)
	_confirm.disabled = not reason.is_empty()
