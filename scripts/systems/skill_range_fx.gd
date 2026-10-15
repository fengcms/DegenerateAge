extends Node2D
## 主动技能的短暂程序范围提示；与伤害结算解耦，不改变实际命中范围。

var shape := "circle"
var radius := Iso.TILE_W   # 默认 1 格（7.1：tileW=64，单一来源 Iso.TILE_W）
var facing := Vector2.RIGHT
var age := 0.0

func _process(delta: float) -> void:
	age += delta
	if age >= 0.3:
		queue_free()
	else:
		queue_redraw()

func _draw() -> void:
	var alpha := 1.0 - age / 0.3
	var ink := Color(0.46, 0.91, 0.88, 0.6 * alpha)
	if shape == "cone":
		var points := PackedVector2Array([Vector2.ZERO])
		for i in range(17):
			points.append(facing.rotated(lerpf(-PI / 4.0, PI / 4.0, float(i) / 16.0)) * radius)
		draw_colored_polygon(points, Color(0.46, 0.91, 0.88, 0.14 * alpha))
		draw_arc(Vector2.ZERO, radius, facing.angle() - PI / 4.0,
			facing.angle() + PI / 4.0, 16, ink, 2.0)
	else:
		draw_circle(Vector2.ZERO, radius, Color(0.46, 0.91, 0.88, 0.10 * alpha))
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, ink, 2.0)
