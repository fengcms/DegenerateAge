class_name RestZoneOverlay
extends Node2D
## 出行休整区的地面提示；判定仍以 MapService 的逻辑网格半径为准。

const SEGMENTS := 48
const FILL := Color(0.60, 0.76, 0.68, 0.09)
const EDGE := Color(0.68, 0.84, 0.75, 0.47)

func _draw() -> void:
	for zone in MapService.rest_zones(GameState.current_map):
		var center: Vector2 = zone.cell
		var points := PackedVector2Array()
		for i in range(SEGMENTS):
			var angle := TAU * float(i) / float(SEGMENTS)
			var cell := center + Vector2(cos(angle), sin(angle)) * MapService.REST_RADIUS_CELLS
			points.append(Iso.grid_pt(cell.x, cell.y))
		draw_colored_polygon(points, FILL)
		points.append(points[0])
		draw_polyline(points, EDGE, 1.5, true)
