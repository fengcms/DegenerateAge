class_name HudStatusIcon
extends Control
## Small HUD status glyphs. Off, active and paused have different silhouettes
## and colors; their exact meaning remains available through tooltips.

@export_enum("battle", "pickup", "focus") var icon_kind := "battle":
	set(next_kind):
		icon_kind = next_kind
		queue_redraw()

var active := false:
	set(next_active):
		active = next_active
		queue_redraw()

var paused := false:
	set(next_paused):
		paused = next_paused
		queue_redraw()

func _draw() -> void:
	var edge := Color("aa9064") if active else Color("55585b")
	var glyph := Color("e9c780") if icon_kind == "battle" else Color("83d2dc") if icon_kind == "pickup" else Color("e2bd77")
	if not active:
		glyph = Color("747a7e")
	if paused:
		glyph = Color("b9a77e")
	draw_rect(Rect2(1, 1, size.x - 2, size.y - 2), Color(0.04, 0.06, 0.08, 0.68))
	draw_rect(Rect2(1, 1, size.x - 2, size.y - 2), edge, false, 1.0)
	match icon_kind:
		"battle":
			draw_line(Vector2(6, 6), Vector2(18, 18), glyph, 2.0)
			draw_line(Vector2(18, 6), Vector2(6, 18), glyph, 2.0)
			draw_line(Vector2(5, 11), Vector2(11, 5), glyph, 1.0)
			draw_line(Vector2(13, 5), Vector2(19, 11), glyph, 1.0)
		"pickup":
			draw_colored_polygon(PackedVector2Array([Vector2(12, 4), Vector2(18, 9), Vector2(12, 14), Vector2(6, 9)]), glyph)
			draw_line(Vector2(12, 14), Vector2(12, 19), glyph, 2.0)
			draw_line(Vector2(8, 16), Vector2(12, 20), glyph, 1.0)
			draw_line(Vector2(16, 16), Vector2(12, 20), glyph, 1.0)
		"focus":
			draw_colored_polygon(PackedVector2Array([Vector2(13, 3), Vector2(7, 13), Vector2(12, 13), Vector2(10, 21), Vector2(18, 10), Vector2(13, 10)]), glyph)
	if paused:
		draw_rect(Rect2(size.x - 7, 3, 2, 5), Color("e6ddc6"))
		draw_rect(Rect2(size.x - 4, 3, 2, 5), Color("e6ddc6"))
