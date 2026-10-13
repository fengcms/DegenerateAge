class_name TravelExit
extends Node2D
## 地图步行出口：只负责可见路牌与近距提示，实际切图由 Game 派发。

var exit_id: String = ""
var to_map: String = ""
var player_near: bool = false
var _label: Label

func _ready() -> void:
	_label = Label.new()
	_label.position = Vector2(-125.0, -62.0)
	_label.size = Vector2(250.0, 42.0)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Color("d9f0dc"))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("outline_size", 4)
	add_child(_label)
	_label.add_to_group("world_text")
	SettingsRuntime.apply_world_text_scale_to(_label)
	_update_label()
	queue_redraw()

func set_player_near(value: bool) -> void:
	if player_near == value:
		return
	player_near = value
	_update_label()
	queue_redraw()

func _update_label() -> void:
	if _label == null:
		return
	var name := MapService.display_name(to_map)
	if player_near:
		_label.text = "[E] 前往%s · 免费 · 推荐Lv%d" % [name, MapService.recommended_level(to_map)] if MapService.is_unlocked(to_map) else "道路封锁：%s尚未解锁" % name
	else:
		_label.text = "⇄ %s" % name

func _draw() -> void:
	var glow := Color("a5e7bb") if player_near else Color("668e79")
	draw_colored_polygon(PackedVector2Array([Vector2(-29, 9), Vector2(0, 20), Vector2(29, 9), Vector2(0, -2)]), Color(0.23, 0.48, 0.38, 0.48))
	draw_line(Vector2(0, -27), Vector2(0, 4), Color("b6a17e"), 4.0)
	draw_rect(Rect2(-27, -33, 54, 17), Color("304b3e"))
	draw_rect(Rect2(-27, -33, 54, 17), glow, false, 2.0)
	draw_line(Vector2(-18, -24), Vector2(18, -24), glow, 2.0)
	draw_line(Vector2(-18, -24), Vector2(-11, -29), glow, 2.0)
	draw_line(Vector2(-18, -24), Vector2(-11, -19), glow, 2.0)
	draw_line(Vector2(18, -24), Vector2(11, -29), glow, 2.0)
	draw_line(Vector2(18, -24), Vector2(11, -19), glow, 2.0)
