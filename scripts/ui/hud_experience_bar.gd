class_name HudExperienceBar
extends ProgressBar
## HUD 底部经验条：显示经验进度，并让已弹出的经验提示随经验事件实时更新。
## 只负责提示表现；经验结算与升级仍由 GameState 完成，HUD 负责写入最新数字。

var _live_tooltip_label: WeakRef

## 创建悬停提示并弱引用其中的文字；关闭提示后不会保留或访问旧节点。
func _make_custom_tooltip(_for_text: String) -> Object:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("111820")
	style.border_color = Color("74818a")
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.add_theme_font_size_override("font_size", maxi(9, roundi(16.0 * SettingsRuntime.text_scale_value())))
	label.add_theme_color_override("font_color", Color("e1e7ee"))
	panel.add_child(label)
	_live_tooltip_label = weakref(label)
	refresh_live_tooltip()
	return panel

## HUD 完成经验值与升级上限写入后，立即同步持续悬停的提示内容。
func refresh_live_tooltip() -> void:
	var label := _live_tooltip_label.get_ref() as Label if _live_tooltip_label != null else null
	if label != null:
		label.text = tooltip_text
