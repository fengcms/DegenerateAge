class_name RestZoneOverlay
extends Node2D
## 城镇矩形安全区的地面提示；营地正式原画用环境本身表达城镇，不叠加调试线。
## 只负责旧地图的视觉边界，安全区判定仍由 MapService 独立处理。

const FILL := Color(0.60, 0.76, 0.68, 0.09)
const EDGE := Color(0.68, 0.84, 0.75, 0.47)

## 对需要显式边界的城镇绘制安全区；正式营地跳过，避免直线割裂原画。
func _draw() -> void:
	if GameState.current_map == "camp":
		return
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
