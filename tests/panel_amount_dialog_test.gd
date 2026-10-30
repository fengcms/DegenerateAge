extends Node
## 工程 110 批量兑换弹框：默认值 / 输入过滤 / 超限禁用 / 确认取值 / Esc 归属 / 焦点释放。
##
## 这六条全是「玩家真能感觉到、但逻辑层测试永远抓不到」的 UI 行为：
## - 输入过滤写错 ⇒ 玩家输「1e5」变成 15，直接错换数量
## - 焦点不释放 ⇒ 关掉弹框后角色永久不能动（`world_controls_blocked()` 恒真）
## - Esc 不吞掉 ⇒ 想取消兑换，结果连仓库面板一起关了
##
## 判据刻意用**绝对文案**（「1」/「123」/「15」）而不是读本地化配置再自比：
## 配置被改坏时这里必须红。

var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("[PanelAmountDialogTest] " + label)

func _ready() -> void:
	await _test_default_value()
	await _test_non_digit_filtered()
	await _test_over_max_disabled()
	await _test_confirm_emits()
	await _test_escape_only_closes_dialog()
	await _test_focus_on_open()
	if failures.is_empty():
		print("[PanelAmountDialogTest] 全部通过 ✅")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("[PanelAmountDialogTest] 失败 %d 项" % failures.size())
		get_tree().quit(1)

## 建一个已打开的弹框。预览提供者用假数据 —— 本测试只验弹框自己的行为，
## 不验汇率（那是 GoldExchangeTest 的事）。
func _make(max_times: int) -> PanelAmountDialog:
	var dialog := PanelAmountDialog.new()
	dialog.title = "金币 → 金条"
	dialog.rate_text = "1 次 = 金币 ×1000000 → 金条"
	dialog.max_times = max_times
	dialog.preview_provider = func(times: int) -> Dictionary:
		return {"cost": "金币 ×%d" % (1000000 * times), "got": "金条 ×%d" % times}
	add_child(dialog)
	dialog.popup()
	await get_tree().process_frame
	return dialog

## 模拟玩家在输入框里敲字：先落文本，再走 `text_changed`。
## 🔑 只写 `_edit.text = ...` 不够 —— `LineEdit.set_text()` **不触发** `text_changed`
## （那是真实输入路径才发的信号），只赋值会得到「过滤没生效」的假红。
func _type(dialog: PanelAmountDialog, value: String) -> void:
	dialog._edit.text = value
	dialog._edit.text_changed.emit(value)

# ---- 用例 1：默认值 1 且全选 ----

func _test_default_value() -> void:
	var dialog := await _make(10)
	check(dialog.visible, "popup() 之后弹框应可见")
	check(dialog._edit.text == "1", "输入框默认值应为 1，实际「%s」" % dialog._edit.text)
	check(dialog._edit.has_selection(), "默认值应已全选（玩家直接敲数字即可覆盖，不用先删）")
	dialog.queue_free()

# ---- 用例 2：非数字一律过滤 ----

func _test_non_digit_filtered() -> void:
	var dialog := await _make(100)
	_type(dialog, "1a2b3")
	check(dialog._edit.text == "123", "非数字应被过滤，实际「%s」" % dialog._edit.text)
	# 「1e5」若不剔字母会变成 15 —— 玩家以为输的是 100000，实际换了 15 次。
	_type(dialog, "1e5")
	check(dialog._edit.text == "15", "「1e5」应过滤成 15，实际「%s」" % dialog._edit.text)
	_type(dialog, "-7")
	check(dialog._edit.text == "7", "负号应被剔除，实际「%s」" % dialog._edit.text)
	dialog.queue_free()

# ---- 用例 3：超限 / 非法输入必须直接禁用确认 ----

func _test_over_max_disabled() -> void:
	var dialog := await _make(10)
	_type(dialog, "11")
	check(dialog._confirm.disabled, "超过上限时确认按钮必须禁用")
	check(dialog._cost_label.text.find("上限") >= 0,
		"超限时应把原因直接写在第一行（玩家不用点就知道），实际「%s」" % dialog._cost_label.text)
	_type(dialog, "10")
	check(not dialog._confirm.disabled, "正好等于上限时应可确认（边界不能差一）")
	check(dialog._cost_label.text.find("将消耗") >= 0,
		"合法输入时第一行应回到「将消耗」预览，实际「%s」" % dialog._cost_label.text)
	_type(dialog, "")
	check(dialog._confirm.disabled, "空输入必须禁用确认")
	dialog.queue_free()

# ---- 用例 4：确认只发出合法整数 ----

func _test_confirm_emits() -> void:
	var dialog := await _make(10)
	var got: Array[int] = []
	dialog.submitted.connect(func(times: int) -> void: got.append(times))
	_type(dialog, "7")
	dialog._on_confirm()
	check(got.size() == 1 and got[0] == 7, "确认应发出 7，实际 %s" % str(got))
	check(not dialog.visible, "确认后弹框应关闭")
	dialog.popup()
	await get_tree().process_frame
	# 超限值即便绕过按钮禁用（例如按钮状态还没刷新）也不许发出信号。
	_type(dialog, "99")
	dialog._on_confirm()
	check(got.size() == 1, "超限输入不得发出确认信号，实际收到 %s" % str(got))
	dialog.queue_free()

# ---- 用例 5：Esc 只关这一层，且事件必须被吃掉 ----

func _test_escape_only_closes_dialog() -> void:
	var dialog := await _make(10)
	var event := InputEventAction.new()
	event.action = "pause"
	event.pressed = true
	dialog._input(event)
	check(not dialog.visible, "Esc 应关闭弹框")
	# 被吃掉才不会再传给父面板的 `_unhandled_input` —— 否则一次 Esc 关两层。
	check(get_viewport().is_input_handled(), "Esc 必须 set_input_as_handled()，否则会连带关掉仓库面板")
	dialog.queue_free()

# ---- 用例 6：打开必须聚焦输入框 ----
#
# 只断「打开后有焦点」，不断「关闭后没有焦点」：后者由 Godot 的隐藏即释放保证，
# 与本工程代码无关（删掉任何一行都照样绿 ⇒ 那种断言是假绿，不是哨兵）。

func _test_focus_on_open() -> void:
	var dialog := await _make(10)
	check(dialog._edit.has_focus(), "打开时应聚焦输入框（否则玩家敲的数字进不去，全变成快捷栏操作）")
	dialog.close()
	dialog.queue_free()
