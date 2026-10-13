class_name CaveLayout
extends RefCounted
## One authoritative orthographic grid for cave rendering, collision and routing.

const PATH := "res://data/cave_layout.json"

var size := Vector2i(50, 50)
var points: Dictionary = {}
var _blocked: Dictionary = {}
var _astar := AStarGrid2D.new()

func _init() -> void:
	var file := FileAccess.open(PATH, FileAccess.READ)
	assert(file != null, "Missing cave layout")
	var data: Dictionary = JSON.parse_string(file.get_as_text())
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
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
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
