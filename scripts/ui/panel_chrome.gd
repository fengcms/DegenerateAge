class_name PanelChrome
extends PanelContainer
## 统一面板外框。按用户修订的 SVG 绘制可伸缩的切角、双层描边和标题横带。

const GOLD := Color("b99a5b")
const GOLD_LIGHT := Color("e3c17c")
const TEXT := Color("e8d8ae")
const MUTED := Color("a5adb0")
const SURFACE := Color("111a1f")
const SURFACE_LIGHT := Color("1b272c")

func _init() -> void:
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 7
	empty.content_margin_right = 7
	empty.content_margin_top = 7
	empty.content_margin_bottom = 7
	add_theme_stylebox_override("panel", empty)
	resized.connect(queue_redraw)

## 框线留在最外沿，内容由调用方的 MarginContainer 保持安全距离。
func _draw() -> void:
	var w := size.x
	var h := size.y
	if w < 32.0 or h < 32.0:
		return
	var cut := 13.0
	var outline := PackedVector2Array([Vector2(cut, 0), Vector2(w - cut, 0), Vector2(w, cut),
		Vector2(w, h - cut), Vector2(w - cut, h), Vector2(cut, h), Vector2(0, h - cut), Vector2(0, cut)])
	draw_colored_polygon(outline, SURFACE)
	draw_polyline(PackedVector2Array(outline + PackedVector2Array([outline[0]])), GOLD, 2.0, true)
	var inner := PackedVector2Array([Vector2(17, 6), Vector2(w - 17, 6), Vector2(w - 6, 17),
		Vector2(w - 6, h - 17), Vector2(w - 17, h - 6), Vector2(17, h - 6),
		Vector2(6, h - 17), Vector2(6, 17), Vector2(17, 6)])
	draw_polyline(inner, Color("594f3d"), 1.0, true)
	# 标题区域只做低对比色带，正文维持深色，避免遮住现有内容。
	draw_rect(Rect2(7, 8, w - 14, 49), Color("172126"))
	draw_line(Vector2(25, 58), Vector2(w - 25, 58), Color("5c5646"), 1.0)
	draw_line(Vector2(25, 60), Vector2(w - 25, 60), Color("222c2e"), 1.0)
	for left in [true, false]:
		var edge := 12.0 if left else w - 12.0
		var direction := 1.0 if left else -1.0
		draw_line(Vector2(edge, 18), Vector2(edge + direction * 28, 18), GOLD, 1.0)
		draw_line(Vector2(edge, 18), Vector2(edge, 37), GOLD, 1.0)
		draw_line(Vector2(edge, h - 18), Vector2(edge + direction * 28, h - 18), GOLD, 1.0)
		draw_line(Vector2(edge, h - 18), Vector2(edge, h - 37), GOLD, 1.0)
	draw_colored_polygon(PackedVector2Array([Vector2(w / 2.0, h - 4), Vector2(w / 2.0 + 4, h - 8),
		Vector2(w / 2.0, h - 12), Vector2(w / 2.0 - 4, h - 8)]), GOLD)

## 标题前的菱形和文字层级，与浮窗、设置、NPC 面板共用。
static func style_title(label: Label) -> void:
	label.text = title_text(label.text)
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", TEXT)
	label.add_theme_color_override("font_shadow_color", Color("080d0e"))
	label.add_theme_constant_override("shadow_offset_y", 1)

static func title_text(value: String) -> String:
	return "◆  " + value

static func style_close(button: Button) -> void:
	button.text = "×"
	button.custom_minimum_size = Vector2(30, 30)
	button.add_theme_font_size_override("font_size", 22)
	button.add_theme_color_override("font_color", GOLD_LIGHT)
	button.add_theme_stylebox_override("normal", _button_style(Color("192328"), GOLD, 15))
	button.add_theme_stylebox_override("hover", _button_style(Color("344042"), GOLD_LIGHT, 15))
	button.add_theme_stylebox_override("pressed", _button_style(Color("403825"), GOLD_LIGHT, 15))

static func style_help(button: Button) -> void:
	button.text = "?"
	button.flat = false
	button.custom_minimum_size = Vector2(26, 26)
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_stylebox_override("normal", _button_style(Color("202a2c"), Color("5f655b"), 13))
	button.add_theme_stylebox_override("hover", _button_style(Color("344042"), GOLD, 13))

static func style_action(button: Button, primary: bool = false) -> void:
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_disabled_color", Color("788184"))
	button.add_theme_stylebox_override("normal", _button_style(Color("5c5038") if primary else SURFACE_LIGHT, GOLD))
	button.add_theme_stylebox_override("hover", _button_style(Color("796844") if primary else Color("2c3a3d"), GOLD_LIGHT))
	button.add_theme_stylebox_override("pressed", _button_style(Color("3c3528"), GOLD))
	button.add_theme_stylebox_override("disabled", _button_style(Color("182126"), Color("465052")))

static func style_tabs(tabs: TabContainer) -> void:
	tabs.add_theme_font_size_override("font_size", 16)
	tabs.add_theme_color_override("font_selected_color", TEXT)
	tabs.add_theme_color_override("font_unselected_color", MUTED)
	tabs.add_theme_stylebox_override("panel", _button_style(Color("10191e"), Color("405056")))
	tabs.add_theme_stylebox_override("tab_selected", _button_style(Color("303633"), GOLD))
	tabs.add_theme_stylebox_override("tab_unselected", _button_style(Color("1a252a"), Color("445054")))
	tabs.add_theme_stylebox_override("tab_disabled", _button_style(Color("162025"), Color("364044")))

static func style_separator(line: HSeparator) -> void:
	var style := StyleBoxLine.new()
	style.color = Color("4d4a3e")
	style.thickness = 1
	line.add_theme_stylebox_override("separator", style)

## 内容卡片与表单区域保持低对比，凸显标题和可操作控件。
static func style_card(panel: PanelContainer) -> void:
	var style := _button_style(Color("152126"), Color("3d4c50"))
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)

static func style_section(label: Label) -> void:
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", TEXT)

static func _button_style(bg: Color, border: Color, radius: int = 3) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style
