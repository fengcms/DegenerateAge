class_name ItemSlot
extends Button
## 通用物品格子（M1-8 拖拽改造）。
##
## 两种角色（`role`）：
##   ROLE_BAG  —— 背包格：`draggable = true` 时可拖出，载荷携带背包下标与物品实例；
##   ROLE_TRAY —— 出售托盘格：可接收来自背包格的投放，松手即回传信号。
##
## 拖拽载荷结构：{ "from": int(ROLE_BAG), "index": int, "item": Dictionary }
## 界面本体仍为占位绘制（R5）：格内文字为模板名前 2 字 + 品质色描边。
##
## 为什么单独抽一个控件：Godot 4 的拖放是 Control 的虚方法（_get_drag_data /
## _can_drop_data / _drop_data），必须在脚本里覆写；界面为代码构建，无法给 Button 实例
## 单独挂虚方法，故统一由此类承载拖出与接收两端。

enum { ROLE_BAG, ROLE_TRAY }

## 托盘收到投放时回传（tray_index 为本格下标，payload 见文件头）。
signal item_dropped(tray_index: int, payload: Dictionary)

var role: int = ROLE_BAG
var index: int = -1              # 背包下标（ROLE_BAG）/ 托盘下标（ROLE_TRAY）
var item: Dictionary = {}        # 当前格内物品实例（由面板在刷新时写入）
var draggable: bool = false      # 是否允许拖出（仅交易会话中的背包格打开）

# ---- 拖出（ROLE_BAG）----

func _get_drag_data(_at_position: Vector2) -> Variant:
	if role != ROLE_BAG or not draggable or item.is_empty():
		return null
	# 预览只在真实拖拽中创建：引擎要求 set_drag_preview 时正处于拖拽态，
	# 无头测试直接调用本函数取载荷时不能设置预览（否则报错并泄漏控件）。
	if get_viewport().gui_is_dragging():
		set_drag_preview(_make_drag_preview())
	return {"from": ROLE_BAG, "index": index, "item": item}

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
	if role != ROLE_TRAY or not (data is Dictionary):
		return false
	return int((data as Dictionary).get("from", -1)) == ROLE_BAG

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	item_dropped.emit(index, data as Dictionary)
