extends Control
## A small medallion attached to the portrait rim.

func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5
	draw_circle(center + Vector2(0, 1), radius, Color("13120f"))
	draw_circle(center, radius - 2.0, Color("917139"))
	draw_circle(center, radius - 4.0, Color("d2b571"))
	draw_circle(center, radius - 5.5, Color("43331f"))
	draw_circle(center + Vector2(0, 1), radius - 7.0, Color("614726"))
	draw_arc(center, radius - 7.0, PI * 1.12, PI * 1.9, 24, Color("a98546"), 1.0, true)
	draw_arc(center, radius - 3.0, PI * 1.08, PI * 1.86, 24, Color("f1d993"), 1.0, true)
	for angle in [0.0, PI * 0.5, PI, PI * 1.5]:
		var point := center + Vector2(cos(angle), sin(angle)) * (radius - 3.0)
		draw_circle(point, 1.0, Color("f4dc9a"))
