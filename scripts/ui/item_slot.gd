class_name ItemSlot
extends Button
## 通用物品格子（M1-8 拖拽改造）。
##
## 两种角色（`role`）：
##   ROLE_BAG  —— 背包格：`draggable = true` 时可拖出，载荷携带背包下标与物品实例；
##   ROLE_TRAY —— 出售托盘格：可接收来自背包格的投放；
##   ROLE_WAREHOUSE —— 仓库格：与背包格双向拖放。
##
## 拖拽载荷结构：{ "from": ROLE_BAG 或 ROLE_WAREHOUSE, "index": int, "item": Dictionary }
## 拖动时的跟随视觉由 DragGhost 承载（挂 UI 层最高层；**不用**引擎的拖拽预览，
## 原因见 `_spawn_drag_visual`）。界面本体仍为占位绘制（R5）：格内文字为模板名前 2 字 + 品质色描边。
##
## 为什么单独抽一个控件：Godot 4 的拖放是 Control 的虚方法（_get_drag_data /
## _can_drop_data / _drop_data），必须在脚本里覆写；界面为代码构建，无法给 Button 实例
## 单独挂虚方法，故统一由此类承载拖出与接收两端。

enum { ROLE_BAG, ROLE_TRAY, ROLE_WAREHOUSE, ROLE_EQUIP }

## 目标格收到投放时回传（target_index 为本格下标，payload 见文件头）。
signal item_dropped(tray_index: int, payload: Dictionary)

var role: int = ROLE_BAG
var index: int = -1              # 背包下标（ROLE_BAG）/ 托盘下标（ROLE_TRAY）
var draggable: bool = false      # 是否允许拖出（背包可用物品 / 交易装备 / 仓库存取）

## 当前格内物品实例（由面板在刷新时写入）。**赋值即刷新右下角数量角标**（M4-10）。
var item: Dictionary = {}:
	set(value):
		item = value
		_refresh_count()
		_apply_sample_icon.call_deferred()
		queue_redraw()

## 数量角标（右下角）：仅 `count > 1` 显示 —— 装备 / 单个道具不顶「1」（Q4-A）。
var _count: Label

func _ready() -> void:
	_count = Label.new()
	_count.set_anchors_preset(Control.PRESET_FULL_RECT)
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_count.add_theme_font_size_override("font_size", 11)
	_count.add_theme_constant_override("outline_size", 2)
	_count.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_count.add_theme_color_override("font_color", Color(0.96, 0.94, 0.85))
	_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_count)
	_refresh_count()

## 依据 `item.count` 刷新角标文本。`_ready` 前被赋值时安全跳过（`_count` 为 null）。
func _refresh_count() -> void:
	if _count == null:
		return
	var n := 0
	if not item.is_empty():
		n = int(item.get("count", 1))
	_count.text = str(n) if n > 1 else ""

# ---- 拖出（ROLE_BAG）----

func _get_drag_data(_at_position: Vector2) -> Variant:
	if not [ROLE_BAG, ROLE_WAREHOUSE].has(role) or not draggable or item.is_empty():
		return null
	_spawn_drag_visual()
	return {"from": role, "index": index, "item": item, "token": Warehouse.item_token(item)}

## 拖动时跟随鼠标的视觉反馈（拖拽幽灵）。
## **不用引擎的 set_drag_preview**：预览挂载点由引擎自定（实测 4.7 插到本面板内部），
## 与其它面板同 canvas、同 z_index，绘制顺序由树的先后决定 —— 预览会被排在后面的
## 面板（如货郎面板）整块盖住，玩家看不到拖动的元素；`z_index` 只在同 canvas 内比较，
## 无法跨 canvas 纠正。故改为自绘 DragGhost，显式挂到 UI 层内最高层（组 drag_ghost_layer）。
## 兜底：场景中无该图层时（如独立测试场景）仍走引擎预览，并尽量抬高其 z_index。
## 引擎契约：`_get_drag_data` 内的拖拽态必为真（官方即推荐在此调用 set_drag_preview，
## 其内部同样断言 gui_is_dragging）；无头测试直接取载荷时为假 —— 此时不做任何视觉创建。
func _spawn_drag_visual() -> void:
	if not get_viewport().gui_is_dragging():
		return
	var layer := get_tree().get_first_node_in_group("drag_ghost_layer")
	if layer != null:
		DragGhost.spawn(layer, item)
		return
	var preview := _make_drag_preview()
	preview.z_index = DragGhost.Z
	set_drag_preview(preview)

## 拖拽跟随鼠标的小预览：物品名 + 品质色描边（占位素材，不加载图标）。
func _make_drag_preview() -> Control:
	var box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.11, 0.14, 0.94)
	sb.border_color = ItemUtil.quality_color(String(item.get("quality", "common")))
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 8.0
	sb.content_margin_right = 8.0
	sb.content_margin_top = 4.0
	sb.content_margin_bottom = 4.0
	box.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = ItemUtil.display_name(item)
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(0.95, 0.93, 0.86))
	box.add_child(l)
	box.modulate = Color(1, 1, 1, 0.92)
	return box

# ---- 接收（ROLE_TRAY）----

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary):
		return false
	var source := int((data as Dictionary).get("from", -1))
	return (role == ROLE_TRAY and source == ROLE_BAG) \
		or (role == ROLE_WAREHOUSE and source == ROLE_BAG) \
		or (role == ROLE_BAG and source == ROLE_WAREHOUSE) \
		or (role == ROLE_BAG and source == ROLE_EQUIP)

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	item_dropped.emit(index, data as Dictionary)

func _apply_sample_icon() -> void:
	SampleArt.decorate(self, SampleArt.icon_for(item))
