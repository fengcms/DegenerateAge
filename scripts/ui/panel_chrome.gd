class_name PanelChrome
extends PanelContainer
## 统一面板外框。按用户修订的 SVG 绘制可伸缩的切角、双层描边和标题横带。

const GOLD := Color("b99a5b")
const GOLD_LIGHT := Color("e3c17c")
const TEXT := Color("e8d8ae")
const MUTED := Color("a5adb0")
const SURFACE := Color("111a1f")
const SURFACE_LIGHT := Color("1b272c")
const FRAME_CONTENT_INSET := 7
const HEADER_BAND_BOTTOM := 57
const HEADER_DIVIDER_Y := 59
const HEADER_ROW_HEIGHT := 40
const HEADER_MARGIN_TOP := HEADER_BAND_BOTTOM - HEADER_ROW_HEIGHT - FRAME_CONTENT_INSET
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
	empty.content_margin_left = FRAME_CONTENT_INSET
	empty.content_margin_right = FRAME_CONTENT_INSET
	empty.content_margin_top = FRAME_CONTENT_INSET
	empty.content_margin_bottom = FRAME_CONTENT_INSET
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
	# 标题渐变贴合内层切角，不让矩形纹理填入角落的留白或覆盖折线。
	var header_top := Color("30383b")
	var header_middle := Color("1b252a")
	var header_bottom := Color("131a1e")
	var header_turn := header_top.lerp(header_middle, 8.0 / 25.0)
	draw_polygon(PackedVector2Array([Vector2(15, 8), Vector2(w - 15, 8),
		Vector2(w - 7, 16), Vector2(7, 16)]),
		PackedColorArray([header_top, header_top, header_turn, header_turn]))
	draw_polygon(PackedVector2Array([Vector2(7, 16), Vector2(w - 7, 16),
		Vector2(w - 7, 33), Vector2(7, 33)]),
		PackedColorArray([header_turn, header_turn, header_middle, header_middle]))
	draw_polygon(PackedVector2Array([Vector2(7, 33), Vector2(w - 7, 33),
		Vector2(w - 7, HEADER_BAND_BOTTOM), Vector2(7, HEADER_BAND_BOTTOM)]),
		PackedColorArray([header_middle, header_middle, header_bottom, header_bottom]))
	draw_polyline(inner, Color("594f3d"), 1.0, true)
	# 标题分隔仅由外框绘制；内容面板只留同高度的空隙，不再叠加 HSeparator。
	draw_line(Vector2(25, HEADER_DIVIDER_Y), Vector2(w - 25, HEADER_DIVIDER_Y), Color("776d59"), 1.0, true)
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

## 让所有共用外框面板的标题行固定在渐变带内，避免圆钮压住分隔线。
## 调用方仍可独立设置内容区左右及底部边距。
static func style_header_layout(margin: MarginContainer, header: HBoxContainer) -> void:
	margin.add_theme_constant_override("margin_top", HEADER_MARGIN_TOP)
	header.custom_minimum_size.y = HEADER_ROW_HEIGHT

## 给右上角关闭动作应用正圆纹理，不依赖字号计算按钮轮廓。
static func style_close(button: Button) -> void:
	_style_round_button(button, 40, CLOSE_NORMAL, CLOSE_HOVER, CLOSE_PRESSED)

## 帮助按钮与关闭按钮使用固定宽高的圆形贴图，避免文字倍率和标题行拉伸椭圆化。
static func style_help(button: Button) -> void:
	_style_round_button(button, HEADER_ROW_HEIGHT, HELP_NORMAL, HELP_HOVER, HELP_PRESSED)

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

## 将加载进度条的轨道与进度填充纳入面板配色；动画仍由 ProgressBar 管理。
static func style_progress(bar: ProgressBar) -> void:
	var track := _button_style(SURFACE, Color("5e644f"))
	track.content_margin_top = 0
	track.content_margin_bottom = 0
	var fill := _button_style(GOLD, GOLD_LIGHT)
	fill.content_margin_top = 0
	fill.content_margin_bottom = 0
	bar.add_theme_stylebox_override("background", track)
	bar.add_theme_stylebox_override("fill", fill)

## 存档命名等单行输入框沿用深色面板与细金边，保留原生文字编辑行为。
static func style_line_edit(edit: LineEdit) -> void:
	edit.add_theme_stylebox_override("normal", _button_style(SURFACE_LIGHT, Color("706750")))
	edit.add_theme_stylebox_override("focus", _focus_style(3))
	edit.add_theme_stylebox_override("read_only", _button_style(SURFACE, Color("405056")))
	edit.add_theme_color_override("font_color", TEXT)
	edit.add_theme_color_override("font_placeholder_color", MUTED)

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
