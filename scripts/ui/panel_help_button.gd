class_name PanelHelpButton
extends Button
## 四个常驻面板共用的问号帮助。提示是独立弹窗，字号需单独应用文字倍率。

const MAX_TEXT_WIDTH := 340.0

func _init() -> void:
	text = "❓"
	flat = true
	custom_minimum_size = Vector2(32, 28)

func _make_custom_tooltip(for_text: String) -> Object:
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
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
	var font_size := maxi(9, roundi(16.0 * SettingsRuntime.text_scale_value()))
	var width := minf(MAX_TEXT_WIDTH, maxf(120.0, get_viewport().get_visible_rect().size.x - 48.0))
	label.text = wrap_to_width(for_text, get_theme_font("font"), font_size, width)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.custom_minimum_size.x = width
	label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("e1e7ee"))
	panel.add_child(label)
	return panel

## 提前插入换行，避免引擎在独立 tooltip 弹窗中用错误的初始宽度计算高度。
static func wrap_to_width(value: String, font: Font, font_size: int, width: float) -> String:
	if font == null:
		return value
	var lines: Array[String] = []
	for paragraph in value.split("\n", true):
		var line := ""
		for i in range(paragraph.length()):
			var character := paragraph.substr(i, 1)
			if not line.is_empty() and font.get_string_size(line + character, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
				lines.append(line)
				line = ""
			line += character
		lines.append(line)
	return "\n".join(PackedStringArray(lines))
