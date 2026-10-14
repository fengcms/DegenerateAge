extends Control
## Thin engraved brass work around the portrait; the centre stays transparent.

func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5
	draw_arc(center, radius - 1.5, 0.0, TAU, 96, Color("171512"), 3.0, true)
	draw_arc(center, radius - 3.5, 0.0, TAU, 96, Color("a88b53"), 1.5, true)
	draw_arc(center, radius - 6.0, 0.0, TAU, 96, Color("423526"), 2.0, true)
	draw_arc(center, radius - 8.0, 0.0, TAU, 96, Color("d6bd81"), 1.0, true)
	for index in range(12):
		var angle := float(index) * TAU / 12.0
		var direction := Vector2(cos(angle), sin(angle))
		var outer := center + direction * (radius - 2.0)
		var inner := center + direction * (radius - (9.0 if index % 3 == 0 else 6.0))
		draw_line(inner, outer, Color("ddc693") if index % 3 == 0 else Color("7c6948"), 1.0, true)
	for angle in [0.0, PI * 0.5, PI, PI * 1.5]:
		var point := center + Vector2(cos(angle), sin(angle)) * (radius - 3.5)
		draw_circle(point, 2.1, Color("211b17"))
		draw_circle(point, 1.1, Color("e3c978"))
