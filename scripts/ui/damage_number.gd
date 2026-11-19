extends Node2D
class_name DamageNumber
## 伤害飘字（产品文档 9.5）：普通白色 / 暴击黄色加大 / Miss 灰色。
## 上浮 + 淡出后自毁。挂载于世界坐标（随相机移动）。

var _amount: int = 0
var _is_crit: bool = false
var _is_miss: bool = false

## 在入树前接收已结算数值及其表现类型，不参与伤害计算。
func setup(amount: int, is_crit: bool, is_miss: bool = false) -> void:
	_amount = amount
	_is_crit = is_crit
	_is_miss = is_miss

## 入树时设置样式和当前世界文字倍率，播放一次上浮与淡出后释放。
func _ready() -> void:
	var label: Label = $Label
	# M5-9e（创意 09 §7）：飘字是世界文字 —— 像素尺寸不随地图倍率变（生成即自应用，
	# 改档位由 world_text 组统一重扫）。本节点只动画 position / modulate，不碰 scale，无冲突。
	label.add_to_group("world_text")
	SettingsRuntime.apply_world_text_scale_to(label)
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

	label.resized.connect(_center_label)
	_center_label()
	position += Vector2(randf_range(-10.0, 10.0), 0.0)

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "position", position + Vector2(0, -42), 0.75) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(label, "modulate:a", 0.0, 0.6).set_delay(0.2)
	tw.chain().tween_callback(queue_free)


## 文本撑开最小尺寸后重新对齐中心，在不同字号和地图倍率下仍绕命中锚点缩放。
func _center_label() -> void:
	var label: Label = $Label
	var half_size := label.size * 0.5
	label.pivot_offset = half_size
	label.position = Vector2(0.0, -20.0) - half_size
