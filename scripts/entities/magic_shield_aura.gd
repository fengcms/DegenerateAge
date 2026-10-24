class_name MagicShieldAura
extends Node2D
## 玩家魔法盾的竖向护罩画层；前后两实例夹住角色贴图，共用同一轮廓。
## 只画世界空间的身体外观，不承担地面范围、碰撞或伤害判定；隐藏后不提交绘制命令。

const SEGMENTS := 48
const SHIELD_FILL := Color(0.23, 0.79, 0.94, 0.10)
const SHIELD_GLOW := Color(0.36, 0.90, 1.0, 0.14)
const SHIELD_EDGE := Color(0.60, 0.95, 1.0, 0.72)

@export var front_pass := false
var _mounted := false

## 骑乘外观比站立外观宽高各多一档；只在骑乘状态变化时重建轮廓。
func set_mounted(value: bool) -> void:
	if _mounted == value:
		return
	_mounted = value
	queue_redraw()

## 供场景回归检查护罩上沿与脚底锚点，单位为玩家节点的本地像素。
func outline_bounds() -> Rect2:
	var center := Vector2(0.0, -43.0 if _mounted else -37.0)
	var radius := Vector2(64.0, 78.0) if _mounted else Vector2(43.0, 56.0)
	return Rect2(center - radius, radius * 2.0)

## 后层铺极淡色罩，前层仅描轮廓；不盖住角色面部和动作帧。
func _draw() -> void:
	var bounds := outline_bounds()
	var center := bounds.get_center()
	var radius := bounds.size * 0.5
	var points := PackedVector2Array()
	for index in range(SEGMENTS + 1):
		var angle := TAU * float(index) / float(SEGMENTS)
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	if front_pass:
		draw_polyline(points, SHIELD_GLOW, 6.0, true)
		draw_polyline(points, SHIELD_EDGE, 1.8, true)
	else:
		points.resize(SEGMENTS)
		draw_colored_polygon(points, SHIELD_FILL)
