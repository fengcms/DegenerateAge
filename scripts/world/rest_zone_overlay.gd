class_name RestZoneOverlay
extends Node2D
## 城镇矩形安全区的地面提示；与 MapService 的逻辑格边界一致。

const FILL := Color(0.60, 0.76, 0.68, 0.09)
const EDGE := Color(0.68, 0.84, 0.75, 0.47)

func _draw() -> void:
	var area := MapService.safe_area_cells(GameState.current_map)
	if not area.has_area():
		return
	var lo := area.position
	var hi := area.end
	var points := PackedVector2Array([
		Iso.grid_pt(lo.x - 0.5, lo.y - 0.5),
		Iso.grid_pt(hi.x + 0.5, lo.y - 0.5),
		Iso.grid_pt(hi.x + 0.5, hi.y + 0.5),
		Iso.grid_pt(lo.x - 0.5, hi.y + 0.5),
	])
	draw_colored_polygon(points, FILL)
	points.append(points[0])
	draw_polyline(points, EDGE, 1.5, true)
