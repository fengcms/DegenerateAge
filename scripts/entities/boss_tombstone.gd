class_name BossTombstone
extends Node2D
## Boss 死亡后的世界标记：绘制斜向像素墓碑与实时倒计时。
## 由刷新点持有并随地图释放；位置由刷新点赋值，本类不负责刷新逻辑或碰撞。

## 等宽字体（M4-10）：自绘倒计时不经主题，显式引用与 default_theme 相同的字体资源。
const MONO_FONT := preload("res://assets/themes/mono_font.tres")
## 64×64 像素墓碑，脚底锚点位于纹理坐标 (32, 62)。
const TOMBSTONE_TEXTURE := preload("res://assets/sprites/environment/boss_tombstone.png")

var remaining := 0.0
var _shown_seconds := -1

## 注册为世界文字以响应显示倍率变化，并保持像素画最近邻采样。
func _ready() -> void:
	add_to_group("world_text")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

## 接收刷新点剩余秒数；仅当屏幕显示的整数秒变化时重绘。
func set_remaining(seconds: float) -> void:
	remaining = maxf(0, seconds)
	var display := ceili(remaining)
	if display != _shown_seconds:
		_shown_seconds = display
		queue_redraw()

## 将碑脚贴到节点原点，倒计时在碑顶上方居中绘制。
func _draw() -> void:
	draw_texture(TOMBSTONE_TEXTURE, Vector2(-32, -62))
	var seconds := maxi(0, _shown_seconds)
	var text := "Boss 刷新 %02d:%02d" % [seconds / 60, seconds % 60]
	# 字号抵消地图倍率，再按玩家设定的最终文字倍率显示。
	var font_size := 15.0 * SettingsRuntime.world_text_scale_value()
	draw_string(MONO_FONT, Vector2(-100, -63), text, HORIZONTAL_ALIGNMENT_CENTER, 200, font_size, Color("f2cc71"))
