class_name PanelChrome
extends PanelContainer
## 统一面板外框。按用户修订的 SVG 绘制可伸缩的切角、双层描边和标题横带。

const GOLD := Color("b99a5b")
const GOLD_LIGHT := Color("e3c17c")
const TEXT := Color("e8d8ae")
const MUTED := Color("a5adb0")
const SURFACE := Color("111a1f")
const SURFACE_LIGHT := Color("1b272c")
const HEADER_STRIP := preload("res://assets/ui/panel_chrome/header_strip.svg")
const ACTION_NORMAL := preload("res://assets/ui/panel_chrome/action_normal.svg")
const ACTION_PRIMARY := preload("res://assets/ui/panel_chrome/action_primary.svg")
const ACTION_HOVER := preload("res://assets/ui/panel_chrome/action_hover.svg")
const ACTION_PRIMARY_HOVER := preload("res://assets/ui/panel_chrome/action_primary_hover.svg")
const ACTION_PRESSED := preload("res://assets/ui/panel_chrome/action_pressed.svg")
const ACTION_DISABLED := preload("res://assets/ui/panel_chrome/action_disabled.svg")
const CLOSE_NORMAL := preload("res://assets/ui/panel_chrome/close_normal.svg")
const CLOSE_HOVER := preload("res://assets/ui/panel_chrome/close_hover.svg")
const CLOSE_PRESSED := preload("res://assets/ui/panel_chrome/close_pressed.svg")
const HELP_NORMAL := preload("res://assets/ui/panel_chrome/help_normal.svg")
const HELP_HOVER := preload("res://assets/ui/panel_chrome/help_hover.svg")
const HELP_PRESSED := preload("res://assets/ui/panel_chrome/help_pressed.svg")

## 初始化不占内容空间的透明容器，并在窗口改变尺寸时重绘外框。
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
	# 标题带沿用确认稿的三段明暗；只横向拉伸，不改变渐变方向。
	draw_texture_rect(HEADER_STRIP, Rect2(7, 8, w - 14, 49), false)
	# 标题分隔仅由外框绘制；内容面板只留同高度的空隙，不再叠加 HSeparator。
	draw_line(Vector2(25, 59), Vector2(w - 25, 59), Color("776d59"), 1.0, true)
	for left in [true, false]:
		var edge := 12.0 if left else w - 12.0
		var direction := 1.0 if left else -1.0
		var top_corner := PackedVector2Array([Vector2(edge, 37), Vector2(edge, 24),
			Vector2(edge + direction * 6, 18), Vector2(edge + direction * 28, 18)])
		var bottom_corner := PackedVector2Array([Vector2(edge, h - 37), Vector2(edge, h - 24),
			Vector2(edge + direction * 6, h - 18), Vector2(edge + direction * 28, h - 18)])
		draw_polyline(top_corner, GOLD, 1.0, true)
		draw_polyline(bottom_corner, GOLD, 1.0, true)
	draw_colored_polygon(PackedVector2Array([Vector2(w / 2.0, h - 4), Vector2(w / 2.0 + 4, h - 8),
		Vector2(w / 2.0, h - 12), Vector2(w / 2.0 - 4, h - 8)]), GOLD)

## 标题前的菱形和文字层级，与浮窗、设置、NPC 面板共用。
static func style_title(label: Label) -> void:
	label.text = title_text(label.text)
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", TEXT)
	label.add_theme_color_override("font_shadow_color", Color("080d0e"))
	label.add_theme_constant_override("shadow_offset_y", 1)

## 为面板标题加入共用的菱形前缀，保留运行时传入的名称。
static func title_text(value: String) -> String:
	return "◆  " + value

## 给右上角关闭动作应用正圆纹理，不依赖字号计算按钮轮廓。
static func style_close(button: Button) -> void:
	_style_round_button(button, 40, CLOSE_NORMAL, CLOSE_HOVER, CLOSE_PRESSED)

## 帮助按钮与关闭按钮使用固定宽高的圆形贴图，避免文字倍率和标题行拉伸椭圆化。
static func style_help(button: Button) -> void:
	_style_round_button(button, 36, HELP_NORMAL, HELP_HOVER, HELP_PRESSED)

## 操作按钮的渐变、高光和端部使用确认稿的局部 SVG，文案仍由 Button 实时绘制。
static func style_action(button: Button, primary: bool = false) -> void:
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_disabled_color", Color("788184"))
	button.add_theme_stylebox_override("normal", _action_style(ACTION_PRIMARY if primary else ACTION_NORMAL))
	button.add_theme_stylebox_override("hover", _action_style(ACTION_PRIMARY_HOVER if primary else ACTION_HOVER))
	button.add_theme_stylebox_override("pressed", _action_style(ACTION_PRESSED))
	button.add_theme_stylebox_override("hover_pressed", _action_style(ACTION_PRESSED))
	button.add_theme_stylebox_override("disabled", _action_style(ACTION_DISABLED))
	button.add_theme_stylebox_override("focus", _focus_style(3))

## 保留原标题行分隔控件占用的高度，但不重复绘线，避免内容整体上移。
static func make_title_gap() -> Control:
	var gap := Control.new()
	gap.custom_minimum_size.y = 1
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return gap

## 标题圆钮的符号已包含于纹理中；固定正方形并在较高标题行里垂直居中。
static func _style_round_button(button: Button, diameter: float, normal: Texture2D, hover: Texture2D, pressed: Texture2D) -> void:
	button.text = ""
	button.flat = false
	button.custom_minimum_size = Vector2(diameter, diameter)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.add_theme_stylebox_override("normal", _round_style(normal))
	button.add_theme_stylebox_override("hover", _round_style(hover))
	button.add_theme_stylebox_override("pressed", _round_style(pressed))
	button.add_theme_stylebox_override("hover_pressed", _round_style(pressed))
	button.add_theme_stylebox_override("disabled", _round_style(normal))
	button.add_theme_stylebox_override("focus", _focus_style(int(diameter / 2.0)))

## 圆钮使用整张正方形贴图；禁用文本内距，防止字体产生额外最小高度。
static func _round_style(texture: Texture2D) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = texture
	style.content_margin_left = 0
	style.content_margin_right = 0
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	return style

## 九宫格只拉伸操作按钮中段，保留端部圆角、金边和上沿高光。
static func _action_style(texture: Texture2D) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = texture
	style.texture_margin_left = 5
	style.texture_margin_right = 5
	style.texture_margin_top = 4
	style.texture_margin_bottom = 4
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style

## 焦点只加一圈细描边，不覆盖 SVG 的渐变和高光。
static func _focus_style(radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.border_color = GOLD_LIGHT
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	return style

## 给现有选项卡统一字体与状态色，不改变页签内容和切换逻辑。
static func style_tabs(tabs: TabContainer) -> void:
	tabs.add_theme_font_size_override("font_size", 16)
	tabs.add_theme_color_override("font_selected_color", TEXT)
	tabs.add_theme_color_override("font_unselected_color", MUTED)
	tabs.add_theme_stylebox_override("panel", _button_style(Color("10191e"), Color("405056")))
	tabs.add_theme_stylebox_override("tab_selected", _button_style(Color("303633"), GOLD))
	tabs.add_theme_stylebox_override("tab_unselected", _button_style(Color("1a252a"), Color("445054")))
	tabs.add_theme_stylebox_override("tab_disabled", _button_style(Color("162025"), Color("364044")))

## 内容区自身的分组线继续使用本样式；标题线由外框独占。
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

## 应用内容区小标题的共用字号与文字色。
static func style_section(label: Label) -> void:
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", TEXT)

## 为页签和内容卡片提供平面底框；操作按钮改用纹理，不再调用本函数。
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
