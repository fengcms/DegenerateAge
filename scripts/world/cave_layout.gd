class_name CaveLayout
extends RefCounted
## One authoritative orthographic grid for cave rendering, collision and routing.

const PATH := "res://data/cave_layout.json"

var size := Vector2i(50, 50)
var points: Dictionary = {}
var _blocked: Dictionary = {}
var _astar := AStarGrid2D.new()

func _init(layout_path: String = PATH) -> void:
	var file := FileAccess.open(layout_path, FileAccess.READ)
	assert(file != null, "Missing map layout: %s" % layout_path)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary, "Invalid map layout: %s" % layout_path)
	var data: Dictionary = parsed
	var dims: Array = data.get("grid_size", [50, 50])
	size = Vector2i(int(dims[0]), int(dims[1]))
	points = data.get("points", {})
	var rows: Array = data.get("walkable_rows", [])
	assert(rows.size() == size.y, "Cave mask must be compiled with build_cave_layout.py")
	for y in range(size.y):
		var row := String(rows[y])
		assert(row.length() == size.x)
		for x in range(size.x):
			var cell := Vector2i(x, y)
			if row[x] != "1":
				_blocked[cell] = true
	_astar.region = Rect2i(Vector2i.ZERO, size)
	_astar.cell_size = Vector2.ONE
	# Diagonal steps are allowed only when both adjacent sides are open.
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.update()
	for cell in _blocked:
		_astar.set_point_solid(cell)

func is_walkable(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y and not _blocked.has(cell)

func blocked_cells() -> Array:
	return _blocked.keys()

func boundary_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for raw in _blocked:
		var cell: Vector2i = raw
		if is_walkable(cell + Vector2i(1, 0)) or is_walkable(cell + Vector2i(-1, 0)) or is_walkable(cell + Vector2i(0, 1)) or is_walkable(cell + Vector2i(0, -1)):
			result.append(cell)
	return result

func nearest_walkable(cell: Vector2i) -> Vector2i:
	var clamped := cell.clamp(Vector2i.ZERO, size - Vector2i.ONE)
	if is_walkable(clamped):
		return clamped
	for radius in range(1, maxi(size.x, size.y) + 1):
		for y in range(maxi(0, clamped.y - radius), mini(size.y - 1, clamped.y + radius) + 1):
			for x in range(maxi(0, clamped.x - radius), mini(size.x - 1, clamped.x + radius) + 1):
				var candidate := Vector2i(x, y)
				if is_walkable(candidate):
					return candidate
	return clamped

func path(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	return _astar.get_id_path(nearest_walkable(from_cell), nearest_walkable(to_cell))

## Keep the player's collision radius away from cave walls when joining path nodes.
func segment_walkable(start: Vector2, finish: Vector2, clearance: float = 14.0) -> bool:
	var delta := finish - start
	var length := delta.length()
	var tangent := delta / length if length > 0.001 else Vector2.RIGHT
	var normal := Vector2(-tangent.y, tangent.x)
	var samples := maxi(1, ceili(length / 6.0))
	for i in range(samples + 1):
		var point := start.lerp(finish, float(i) / float(samples))
		for offset in [Vector2.ZERO, normal * clearance, -normal * clearance]:
			var cell := Vector2i(Iso.world_to_grid(point + offset).round())
			if not is_walkable(cell):
				return false
	return true

## Bounded string-pulling avoids repeated 90-degree turns without crossing a wall.
func smooth_path(origin: Vector2, cells: Array[Vector2i]) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var anchor := origin
	var index := 0
	while index < cells.size():
		var best := index
		for candidate in range(mini(cells.size() - 1, index + 12), index - 1, -1):
			if segment_walkable(anchor, Iso.grid_to_world(cells[candidate])):
				best = candidate
				break
		var waypoint := Iso.grid_to_world(cells[best])
		result.append(waypoint)
		anchor = waypoint
		index = best + 1
	return result
