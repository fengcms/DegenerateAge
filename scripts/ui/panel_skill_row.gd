class_name PanelSkillRow
extends HBoxContainer
## 技能列表行保持 HBox 子节点结构，让原有拖拽源与快捷栏测试继续直接定位按钮。

func _init() -> void:
	custom_minimum_size.y = 58
	add_theme_constant_override("separation", 12)
	resized.connect(queue_redraw)

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, Color("17252a"))
	draw_rect(rect.grow(-1), Color("3d4d50"), false, 1.0)
