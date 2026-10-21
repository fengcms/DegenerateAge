class_name PanelSkillRow
extends HBoxContainer
## 技能列表行保持 HBox 子节点结构，让原有拖拽源与快捷栏测试继续直接定位按钮。

var skill_id := ""

## 名称和空白区由行卡提供悬停详情；自动药品工具行不绑定技能。
func _make_custom_tooltip(_for_text: String) -> Object:
	return SkillDetailTooltip.for_skill(skill_id) if not skill_id.is_empty() else null

## 初始化可扫描行高和间距，并在尺寸变化时重绘背景。
func _init() -> void:
	custom_minimum_size.y = 58
	add_theme_constant_override("separation", 12)
	resized.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)


## 只画行卡底与边框，不生成额外全屏遮罩。
func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, Color("17252a"))
	draw_rect(rect.grow(-1), Color("c9a75d") if has_focus() else Color("3d4d50"), false, 1.0)
