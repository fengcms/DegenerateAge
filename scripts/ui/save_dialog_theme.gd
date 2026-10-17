class_name SaveDialogTheme
extends RefCounted
## 存档导出 / 导入文件选择器的统一面板外观。
##
## FileDialog 属 Window 类，吃不到 UI CanvasLayer 的界面倍率（由
## SettingsRuntime.apply_ui_scale_to_window 单独补内容缩放）；外观则统一交给本 Theme：
## 外框复用 PanelChrome 的切角、双层描边、标题带与角标素材，内部控件沿用同一套
## 深色底、金边与文字层级，避免弹层与游戏内面板观感割裂。

## 外框九宫格纹理：四角切角、标题带与角标都落在纹理边距内，不参与拉伸。
const FRAME := preload("res://assets/ui/panel_chrome/dialog_frame.svg")
const FRAME_MARGIN_SIDE := 44
const FRAME_MARGIN_TOP := 61
const FRAME_MARGIN_BOTTOM := 44
## 外框内容内距：上方让出标题带高度，其余留出框线与角标的安全距离。
const CONTENT_INSET_SIDE := 12
const CONTENT_INSET_TOP := 64
const CONTENT_INSET_BOTTOM := 14
## 引擎自绘标题在标题带内的垂直居中高度与字号。
const TITLE_HEIGHT := 54
const TITLE_FONT_SIZE := 20
const BODY_FONT_SIZE := 15
const SMALL_FONT_SIZE := 13

static func build() -> Theme:
	var theme := Theme.new()
	_style_window(theme)
	_style_dialog_body(theme)
	_style_buttons(theme)
	_style_item_list(theme)
	_style_inputs(theme)
	_style_scrollbars(theme)
	_style_popup(theme)
	theme.set_color("font_color", "Label", PanelChrome.TEXT)
	theme.set_font_size("font_size", "Label", BODY_FONT_SIZE)
	return theme

## 外框与标题：引擎按 Window/embedded_border 绘制，FileDialog 的内部控件恒贴在窗口矩形上，
## 故用**外扩边距**把标题带推到窗口矩形之外，内部控件便自然落在标题带下方。
static func _style_window(theme: Theme) -> void:
	var frame := StyleBoxTexture.new()
	frame.texture = FRAME
	frame.texture_margin_left = FRAME_MARGIN_SIDE
	frame.texture_margin_top = FRAME_MARGIN_TOP
	frame.texture_margin_right = FRAME_MARGIN_SIDE
	frame.texture_margin_bottom = FRAME_MARGIN_BOTTOM
	frame.content_margin_left = 0
	frame.content_margin_top = 0
	frame.content_margin_right = 0
	frame.content_margin_bottom = 0
	frame.expand_margin_left = CONTENT_INSET_SIDE
	frame.expand_margin_top = CONTENT_INSET_TOP
	frame.expand_margin_right = CONTENT_INSET_SIDE
	frame.expand_margin_bottom = CONTENT_INSET_BOTTOM
	theme.set_stylebox("embedded_border", "Window", frame)
	theme.set_stylebox("embedded_unfocused_border", "Window", frame)
	theme.set_constant("title_height", "Window", TITLE_HEIGHT)
	theme.set_constant("title_outline_size", "Window", 0)
	theme.set_constant("close_h_offset", "Window", 34)
	theme.set_constant("close_v_offset", "Window", 28)
	theme.set_color("title_color", "Window", PanelChrome.TEXT)
	theme.set_color("title_outline_modulate", "Window", Color(0, 0, 0, 0))
	theme.set_font_size("title_font_size", "Window", TITLE_FONT_SIZE)
	theme.set_icon("close", "Window", PanelChrome.CLOSE_NORMAL)
	theme.set_icon("close_pressed", "Window", PanelChrome.CLOSE_PRESSED)

## 对话框底板透明：外框已由 embedded_border 提供，避免再叠一层矩形底。
static func _style_dialog_body(theme: Theme) -> void:
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0, 0, 0, 0)
	panel.content_margin_left = 0
	panel.content_margin_top = 0
	panel.content_margin_right = 0
	panel.content_margin_bottom = 0
	theme.set_stylebox("panel", "AcceptDialog", panel)

## 操作按钮与工具栏图标钮统一换成 PanelChrome 的九宫格纹理。
static func _style_buttons(theme: Theme) -> void:
	theme.set_font_size("font_size", "Button", BODY_FONT_SIZE)
	theme.set_color("font_color", "Button", PanelChrome.TEXT)
	theme.set_color("font_hover_color", "Button", PanelChrome.TEXT)
	theme.set_color("font_pressed_color", "Button", PanelChrome.GOLD_LIGHT)
	theme.set_color("font_disabled_color", "Button", Color("788184"))
	theme.set_stylebox("normal", "Button", PanelChrome.action_stylebox(PanelChrome.ACTION_NORMAL))
	theme.set_stylebox("hover", "Button", PanelChrome.action_stylebox(PanelChrome.ACTION_HOVER))
	theme.set_stylebox("pressed", "Button", PanelChrome.action_stylebox(PanelChrome.ACTION_PRESSED))
	theme.set_stylebox("hover_pressed", "Button", PanelChrome.action_stylebox(PanelChrome.ACTION_PRESSED))
	theme.set_stylebox("disabled", "Button", PanelChrome.action_stylebox(PanelChrome.ACTION_DISABLED))
	theme.set_stylebox("focus", "Button", _focus_style(3))

## 文件 / 目录列表沿用面板卡片底与金边选中态。
static func _style_item_list(theme: Theme) -> void:
	theme.set_stylebox("panel", "ItemList", _plate(PanelChrome.SURFACE_LIGHT, Color("3d4c50")))
	theme.set_color("font_color", "ItemList", PanelChrome.TEXT)
	theme.set_color("font_selected_color", "ItemList", PanelChrome.TEXT)
	theme.set_color("font_hovered_color", "ItemList", PanelChrome.GOLD_LIGHT)
	theme.set_font_size("font_size", "ItemList", SMALL_FONT_SIZE)
	var selected := _plate(Color("303633"), PanelChrome.GOLD)
	theme.set_stylebox("selected", "ItemList", selected)
	theme.set_stylebox("selected_focus", "ItemList", selected)
	theme.set_stylebox("hovered", "ItemList", _plate(PanelChrome.SURFACE_LIGHT, PanelChrome.GOLD_LIGHT))
	theme.set_stylebox("focus", "ItemList", _focus_style(3))

## 文件名输入框与过滤器下拉沿用 PanelChrome 的输入框与下拉配色。
static func _style_inputs(theme: Theme) -> void:
	theme.set_stylebox("normal", "LineEdit", _plate(PanelChrome.SURFACE_LIGHT, Color("706750")))
	theme.set_stylebox("focus", "LineEdit", _focus_style(3))
	theme.set_stylebox("read_only", "LineEdit", _plate(PanelChrome.SURFACE, Color("405056")))
	theme.set_color("font_color", "LineEdit", PanelChrome.TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", PanelChrome.MUTED)
	theme.set_color("caret_color", "LineEdit", PanelChrome.GOLD_LIGHT)
	theme.set_color("selection_color", "LineEdit", Color("3d4c50"))
	theme.set_font_size("font_size", "LineEdit", BODY_FONT_SIZE)
	theme.set_stylebox("normal", "OptionButton", PanelChrome.action_stylebox(PanelChrome.ACTION_NORMAL))
	theme.set_stylebox("hover", "OptionButton", PanelChrome.action_stylebox(PanelChrome.ACTION_HOVER))
	theme.set_stylebox("pressed", "OptionButton", PanelChrome.action_stylebox(PanelChrome.ACTION_PRESSED))
	theme.set_stylebox("disabled", "OptionButton", PanelChrome.action_stylebox(PanelChrome.ACTION_DISABLED))
	theme.set_stylebox("focus", "OptionButton", _focus_style(3))
	theme.set_color("font_color", "OptionButton", PanelChrome.TEXT)
	theme.set_color("font_hover_color", "OptionButton", PanelChrome.GOLD_LIGHT)
	theme.set_font_size("font_size", "OptionButton", BODY_FONT_SIZE)

## 滚动条换成细金条的深色轨道，避免原生浅灰在深色面板上过亮。
static func _style_scrollbars(theme: Theme) -> void:
	for type in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", type, _plate(PanelChrome.SURFACE, Color("405056")))
		theme.set_stylebox("grabber", type, _plate(Color("5c5a49"), PanelChrome.GOLD))
		theme.set_stylebox("grabber_highlight", type, _plate(PanelChrome.GOLD, PanelChrome.GOLD_LIGHT))
		theme.set_stylebox("grabber_pressed", type, _plate(PanelChrome.GOLD_LIGHT, PanelChrome.GOLD_LIGHT))

## 右键菜单（新建文件夹等）与收藏夹下拉沿用面板配色。
static func _style_popup(theme: Theme) -> void:
	theme.set_stylebox("panel", "PopupMenu", _plate(PanelChrome.SURFACE, PanelChrome.GOLD))
	theme.set_stylebox("hover", "PopupMenu", _plate(PanelChrome.SURFACE_LIGHT, PanelChrome.GOLD_LIGHT))
	theme.set_color("font_color", "PopupMenu", PanelChrome.TEXT)
	theme.set_color("font_hover_color", "PopupMenu", PanelChrome.GOLD_LIGHT)
	theme.set_color("font_disabled_color", "PopupMenu", PanelChrome.MUTED)
	theme.set_color("font_separator_color", "PopupMenu", PanelChrome.MUTED)
	theme.set_font_size("font_size", "PopupMenu", BODY_FONT_SIZE)

## 深色底 + 细金边的平面底框（与 PanelChrome 内部底框同口径）。
static func _plate(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style

## 焦点只加一圈细描边，不覆盖底框纹理。
static func _focus_style(radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.border_color = PanelChrome.GOLD_LIGHT
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	return style
