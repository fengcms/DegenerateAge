class_name PanelConfirmDialog
extends Control
## 共用的游戏内确认层，供存档覆盖和设置改键冲突使用。
## 只负责呈现与确认/取消信号，不决定业务状态或写盘。

signal confirmed

var title: String = "":
	set(value):
		title = value
		if _title_label != null:
			_title_label.text = PanelChrome.title_text(value)
var dialog_text: String = "":
	set(value):
		dialog_text = value
		if _body_label != null:
			_body_label.text = value

var _title_label: Label
var _body_label: Label
var _confirm_button: Button

## 建立覆盖父面板的遮罩与共用切角外框，初始保持隐藏。
func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	visible = false

## 沿用原生确认框的调用语义：显示在父面板中央并聚焦确认按钮。
func popup_centered() -> void:
	visible = true
	_confirm_button.grab_focus.call_deferred()

## Esc 只取消当前确认，不继续关闭承载它的存档或设置面板。
func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		visible = false
		get_viewport().set_input_as_handled()

## 构建标题、说明和双操作按钮；尺寸随文案自然扩展。
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
	content.custom_minimum_size.x = 390
	content.add_theme_constant_override("separation", 12)
	margin.add_child(content)
	var header := HBoxContainer.new()
	content.add_child(header)
	PanelChrome.style_header_layout(margin, header)
	_title_label = Label.new()
	_title_label.text = title
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title_label)
	PanelChrome.style_title(_title_label)
	content.add_child(PanelChrome.make_title_gap())
	_body_label = Label.new()
	_body_label.text = dialog_text
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.add_theme_color_override("font_color", PanelChrome.TEXT)
	content.add_child(_body_label)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 10)
	content.add_child(actions)
	var cancel := Button.new()
	cancel.text = Localization.tr_key("ui.common.cancel")
	cancel.pressed.connect(_cancel)
	actions.add_child(cancel)
	PanelChrome.style_action(cancel)
	_confirm_button = Button.new()
	_confirm_button.text = Localization.tr_key("ui.common.confirm")
	_confirm_button.pressed.connect(_confirm)
	actions.add_child(_confirm_button)
	PanelChrome.style_action(_confirm_button, true)

## 关闭弹层且不触发业务确认。
func _cancel() -> void:
	visible = false

## 先关闭弹层，再通知业务方执行已确认的操作。
func _confirm() -> void:
	visible = false
	confirmed.emit()
