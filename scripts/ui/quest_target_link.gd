class_name QuestTargetLink
extends Button
## 任务目标中的可点击怪物名称；底线与高亮色区别于普通说明文字。

func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	add_theme_color_override("font_color", Color("70d9eb"))
	add_theme_color_override("font_hover_color", Color("b6f6ff"))
	for state in ["normal", "hover", "pressed"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color.TRANSPARENT
		style.border_color = Color("70d9eb")
		style.border_width_bottom = 1 if state == "normal" else 2
		add_theme_stylebox_override(state, style)
