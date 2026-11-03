extends Node2D
## 短生命周期斩击表现：由攻击入口创建并自动释放，不参与伤害判定或目标选择。
## Procedural short cyan slash, triggered by the existing attack event only.
var direction := 0.0
var age := 0.0

func _process(delta: float) -> void:
	age += delta
	if age >= 0.16:
		queue_free()
	else:
		queue_redraw()

func _draw() -> void:
	var alpha := 1.0 - age / 0.16
	draw_arc(Vector2.ZERO, 21.0, direction - 0.8, direction + 0.8, 7, Color(0.47, 0.85, 0.82, alpha), 3.0)
	draw_arc(Vector2.ZERO, 17.0, direction - 0.5, direction + 0.6, 5, Color(0.90, 1.0, 0.95, alpha), 1.0)
