extends Node2D
class_name DamageNumber
## 伤害飘字（产品文档 9.5）：普通白色 / 暴击黄色加大 / Miss 灰色。
## 上浮 + 淡出后自毁。挂载于世界坐标（随相机移动）。

var _amount: int = 0
var _is_crit: bool = false
var _is_miss: bool = false

## 须在 add_child 之前调用。
func setup(amount: int, is_crit: bool, is_miss: bool = false) -> void:
	_amount = amount
	_is_crit = is_crit
	_is_miss = is_miss

func _ready() -> void:
	var label: Label = $Label
	if _is_miss:
		label.text = "Miss"
		label.add_theme_color_override("font_color", Color("b9c0c8"))
		label.add_theme_font_size_override("font_size", 16)
	elif _is_crit:
		label.text = str(_amount)
		label.add_theme_color_override("font_color", Color("ffd24a"))
		label.add_theme_font_size_override("font_size", 26)
	else:
		label.text = str(_amount)
		label.add_theme_color_override("font_color", Color("f5f5f5"))
		label.add_theme_font_size_override("font_size", 18)

	position += Vector2(randf_range(-10.0, 10.0), 0.0)

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "position", position + Vector2(0, -42), 0.75) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(label, "modulate:a", 0.0, 0.6).set_delay(0.2)
	tw.chain().tween_callback(queue_free)
