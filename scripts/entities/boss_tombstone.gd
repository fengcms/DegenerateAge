class_name BossTombstone
extends Node2D
## 由刷新点持有；随世界释放，不另建独立计时器或刷新点。
## 位置由刷新点赋值（跨图重建时取死亡位置），本类不自行定位。

## 等宽字体（M4-10）：自绘倒计时不经主题，显式引用与 default_theme 相同的字体资源。
const MONO_FONT := preload("res://assets/themes/mono_font.tres")

var remaining := 0.0
var _shown_seconds := -1

func _ready() -> void:
	# M5-9e（创意 09 §7）：倒计时是世界文字 —— 入组供改地图倍率时重绘（_draw 按当时倍率取字号）。
	add_to_group("world_text")

func set_remaining(seconds: float) -> void:
	remaining = maxf(0, seconds)
	var display := ceili(remaining)
	if display != _shown_seconds:
		_shown_seconds = display
		queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(-14, -26, 28, 30), Color("6e747d"))
	draw_line(Vector2(-8, -16), Vector2(8, -16), Color("c4c7cc"), 2)
	draw_line(Vector2(0, -22), Vector2(0, -6), Color("c4c7cc"), 2)
	var seconds := maxi(0, _shown_seconds)
	var text := "Boss 刷新 %02d:%02d" % [seconds / 60, seconds % 60]
	# 字号抵消地图倍率，再按玩家设定的最终文字倍率显示。
	var font_size := 15.0 * SettingsRuntime.world_text_scale_value()
	draw_string(MONO_FONT, Vector2(-100, -38), text, HORIZONTAL_ALIGNMENT_CENTER, 200, font_size, Color("f2cc71"))
