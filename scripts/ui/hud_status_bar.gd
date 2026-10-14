class_name HudStatusBar
extends Control
## Compact, pixel-crisp HUD resource bar. The fill is drawn row by row so its
## highlight and dark lower edge track the real HP/MP value without a bitmap.

@export_enum("HP", "MP") var bar_kind := 0:
	set(next_kind):
		bar_kind = next_kind
		queue_redraw()

var max_value := 100.0:
	set(next_max):
		max_value = maxf(1.0, next_max)
		queue_redraw()

var value := 100.0:
	set(next_value):
		value = next_value
		queue_redraw()

func _draw() -> void:
	var w := floorf(size.x)
	var h := floorf(size.y)
	if w < 12.0 or h < 7.0:
		return
	# Both bars use the same half-pixel-per-row slope. Their scene widths account
	# for the vertical gap, so the two right edges form one continuous line.
	var top_right := w - 1.0
	var bottom_right := top_right - (h - 1.0) * 0.5
	var track := PackedVector2Array([Vector2(0, 0), Vector2(top_right, 0), Vector2(bottom_right, h - 1.0), Vector2(0, h - 1.0)])
	draw_colored_polygon(track, Color("11151a"))
	var ratio := clampf(value / max_value, 0.0, 1.0)
	if ratio > 0.0:
		var light := Color("f47b74") if bar_kind == 0 else Color("8bd6f6")
		var mid := Color("cf4a4a") if bar_kind == 0 else Color("4aa3e0")
		var dark := Color("762b34") if bar_kind == 0 else Color("1e527f")
		for row in range(2, int(h) - 2):
			var t := float(row - 2) / maxf(1.0, h - 5.0)
			var color := light.lerp(mid, t / 0.42) if t < 0.42 else mid.lerp(dark, (t - 0.42) / 0.58)
			var row_limit := top_right - float(row) * 0.5 - 2.0
			var right := 2.0 + (row_limit - 2.0) * ratio
			if right > 2.0:
				draw_line(Vector2(2, row + 0.5), Vector2(right, row + 0.5), color, 1.0)
		var shine_right := 3.0 + (top_right - 6.0) * ratio
		if shine_right > 4.0:
			draw_line(Vector2(3, 2.5), Vector2(shine_right, 2.5), light.lightened(0.22), 1.0)
	draw_polyline(PackedVector2Array([Vector2(0, h - 1), Vector2(0, 0), Vector2(top_right, 0), Vector2(bottom_right, h - 1), Vector2(0, h - 1)]), Color("716d65"), 1.0)
