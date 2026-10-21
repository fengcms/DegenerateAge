class_name SkillDragButton
extends Button
## 技能和自动药品的拖拽源；仅打包快捷栏载荷，施放和药品结算仍由原入口负责。

var skill_id := ""
var drag_label := ""
var binding: Dictionary = {}
## 技能图标使用结构化详情；自动药品工具继续显示原生简短提示。
var tooltip_skill_id := ""

## 技能图标创建独立详情卡，自动药品保留简短原生说明。
func _make_custom_tooltip(_for_text: String) -> Object:
	return SkillDetailTooltip.for_skill(tooltip_skill_id) if not tooltip_skill_id.is_empty() else null

## 开始拖动时向快捷栏提供现有载荷结构，不改变图标放置和购买规则。
func _get_drag_data(_at_position: Vector2) -> Variant:
	if disabled or (skill_id.is_empty() and binding.is_empty()):
		return null
	var layer := get_tree().get_first_node_in_group("drag_ghost_layer")
	var label := drag_label if not drag_label.is_empty() else text
	if layer != null and get_viewport().gui_is_dragging():
		DragGhost.spawn_text(layer, label)
	elif get_viewport().gui_is_dragging():
		var preview := Label.new()
		preview.text = label
		set_drag_preview(preview)
	if not binding.is_empty():
		return {"kind": "hotbar_binding", "entry": binding.duplicate(true)}
	return {"kind": "hotbar_skill", "id": skill_id}
