class_name TravelExit
extends Node2D
## 地图步行出口：显示三态像素路标和目的地提示，实际切图由 Game 派发。
## 门禁状态来自 MapService；节点不改变地图位置、碰撞或步行范围。

const MARKER_IDLE := preload("res://assets/sprites/environment/travel_waymarker_idle.png")
const MARKER_NEAR := preload("res://assets/sprites/environment/travel_waymarker_near.png")
const MARKER_LOCKED := preload("res://assets/sprites/environment/travel_waymarker_locked.png")

var exit_id: String = ""
var to_map: String = ""
var player_near: bool = false
var is_open: bool = true
var blocked_reason: String = ""
var _label: Label

## 创建随地图释放的世界文字，并订阅会改变出口门禁的事件。
func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_label = Label.new()
	_label.position = Vector2(-125.0, -108.0)
	_label.size = Vector2(250.0, 48.0)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.max_lines_visible = 2
	_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Color("d9f0dc"))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("outline_size", 4)
	add_child(_label)
	_label.add_to_group("world_text")
	SettingsRuntime.apply_world_text_scale_to(_label)
	EventBus.quest_state_changed.connect(refresh_availability)
	EventBus.equipment_changed.connect(refresh_availability)
	EventBus.player_leveled.connect(_on_player_leveled)
	EventBus.data_loaded.connect(refresh_availability)
	refresh_availability()

## 玩家进入或离开 1.5 格交互范围时，切换路标箭芯和动态提示。
func set_player_near(value: bool) -> void:
	if player_near == value:
		return
	player_near = value
	_update_label()
	queue_redraw()

## 门禁或角色条件变化后重新计算显示状态；无变化时避免重建绘制命令。
func refresh_availability() -> void:
	var reason := MapService.walk_exit_block_reason(MapService.walk_exit(exit_id))
	var open_now := reason.is_empty()
	var changed := open_now != is_open
	is_open = open_now
	blocked_reason = reason
	_update_label()
	if changed:
		queue_redraw()

## 升级信号带等级参数；外观只需重新读取当前入场条件。
func _on_player_leveled(_new_level: int) -> void:
	refresh_availability()

## 将屏幕坐标转为路标局部坐标；保持原有点击热区与导航入口。
func contains_screen_point(point: Vector2) -> bool:
	var local := get_global_transform_with_canvas().affine_inverse() * point
	return Rect2(-38.0, -62.0, 76.0, 84.0).has_point(local)

## 动态文字保留目的地与推荐等级；封锁时展示与切图相同的门禁原因。
func _update_label() -> void:
	if _label == null:
		return
	var name := MapService.display_name(to_map)
	if player_near:
		if is_open:
			_label.text = Localization.tr_key("ui.travel_exit.p001",
				[name, MapService.recommended_level(to_map)])
		else:
			_label.text = blocked_reason
	elif not is_open:
		_label.text = "%s%s" % [name, Localization.tr_key("ui.map.locked_suffix")]
	else:
		_label.text = "⇄ %s" % name

## 64×64 纹理以 (32,61) 为脚底锚点，仅在靠近或门禁状态改变时重绘。
func _draw() -> void:
	var marker_texture: Texture2D = MARKER_LOCKED if not is_open else MARKER_NEAR if player_near else MARKER_IDLE
	draw_texture(marker_texture, Vector2(-32, -61))
