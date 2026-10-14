class_name DragGhost
extends Control
## 拖拽幽灵：跟随鼠标显示「正在拖动的物品」（M1-8 追加修复：拖拽预览层级）。
##
## 为什么不用引擎的 set_drag_preview（根因）：
##   Godot 的拖拽预览挂载点由引擎自定 —— 实测 4.7 会把预览插到**发起拖拽的面板内部**
##   （`UI/InventoryPanel/@PanelContainer@xxx`）。它与其余面板同处一个 canvas、z_index
##   同为 0，绘制顺序遂由树的先后决定；货郎面板排在背包面板之后 ⇒ 预览被整块盖住，
##   玩家看不到自己拖动的元素。而 `z_index` 只在同一 canvas 内比较，无法跨 canvas 纠正。
##   ⇒ 改为自绘幽灵，显式挂到 UI 层内层级最高的专用图层（组 drag_ghost_layer）。
##
## 生命周期：由 ItemSlot 在 `_get_drag_data` 时创建；自身在 `_process` 中跟随鼠标，
## 拖拽结束后自我回收（未见拖拽态的宽限期内亦自毁，避免无头测试残留控件）。

## 图层内的相对层级（同 canvas 内最大 4096，见 RenderingServer.CANVAS_ITEM_Z_MAX）。
const Z := 4096
## 文字型拖拽提示仍避开光标；物品格则使用抓取点保持相对位置。
const FOLLOW_OFFSET := Vector2(14, 10)
## 启动宽限期（s）：拖拽判定与 `_get_drag_data` 返回之间有一个极短窗口，
## 期间 `gui_is_dragging()` 可能尚未置位，宽限期内不因「不在拖拽」而回收。
const GRACE := 0.25

## 创建幽灵并挂到指定图层（返回 null 表示无可用图层）。
static func spawn(layer: Node, item: Dictionary) -> DragGhost:
	if layer == null:
		return null
	var g := DragGhost.new()
	g.name = "DragGhost"
	g._build(item)
	layer.add_child(g)
	g._follow()
	return g

## 复制来源格子的实际外观，避免拖起后变成横向文字标签。
static func spawn_slot(layer: Node, source: ItemSlot, grab_point: Vector2) -> DragGhost:
	if layer == null:
		return null
	var g := DragGhost.new()
	g.name = "DragGhost"
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.z_index = Z
	g.custom_minimum_size = source.size
	g.size = source.size
	g._follow_offset = -Vector2(clampf(grab_point.x, 0.0, source.size.x),
		clampf(grab_point.y, 0.0, source.size.y))
	g.add_child(slot_copy(source))
	layer.add_child(g)
	g._follow()
	return g

static func slot_copy(source: ItemSlot) -> ItemSlot:
	var copy := ItemSlot.new()
	copy.item = source.item
	copy.text = source.text
	copy.icon = source.icon
	copy.expand_icon = source.expand_icon
	copy.icon_alignment = source.icon_alignment
	copy.texture_filter = source.texture_filter
	copy.custom_minimum_size = source.size
	copy.size = source.size
	copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	copy.focus_mode = Control.FOCUS_NONE
	for name in ["normal", "hover", "pressed", "focus", "disabled"]:
		copy.add_theme_stylebox_override(name, source.get_theme_stylebox(name).duplicate())
	for name in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		copy.add_theme_color_override(name, source.get_theme_color(name))
	copy.add_theme_font_size_override("font_size", source.get_theme_font_size("font_size"))
	copy.add_theme_constant_override("icon_max_width", source.get_theme_constant("icon_max_width"))
	return copy

static func spawn_text(layer: Node, label: String) -> DragGhost:
	if layer == null:
		return null
	var g := DragGhost.new()
	g.name = "DragGhost"
	g._build_label(label, Color("8bc6d9"))
	layer.add_child(g)
	g._follow()
	return g

var _life: float = 0.0
var _seen_drag: bool = false
var _follow_offset := FOLLOW_OFFSET

func _build(item: Dictionary) -> void:
	_build_label(ItemUtil.display_name(item), ItemUtil.quality_color(String(item.get("quality", "common"))))

func _build_label(label: String, border: Color) -> void:
	# 不拦鼠标：投放判定由引擎在拖拽态下完成，幽灵绝不能吃事件。
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = Z
	var box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.11, 0.14, 0.94)
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 8.0
	sb.content_margin_right = 8.0
	sb.content_margin_top = 4.0
	sb.content_margin_bottom = 4.0
	box.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = label
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(0.95, 0.93, 0.86))
	box.add_child(l)
	add_child(box)
	modulate = Color(1, 1, 1, 0.92)

func _ready() -> void:
	size = get_combined_minimum_size()   # 非容器父节点下按内容取尺寸

func _process(delta: float) -> void:
	if get_viewport().gui_is_dragging():
		_seen_drag = true
	elif _seen_drag:
		queue_free()      # 拖拽已结束
		return
	else:
		_life += delta
		if _life > GRACE:
			queue_free()  # 从未真正进入拖拽（无头调用 / 判定失败）
			return
	_follow()

## 跟随鼠标：本节点位于 UI 层（无 canvas 变换），全局坐标即屏幕坐标。
func _follow() -> void:
	global_position = get_global_mouse_position() + _follow_offset
