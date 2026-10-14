class_name CaveLayout
extends RefCounted
## One authoritative orthographic grid for cave rendering, collision and routing.

const PATH := "res://data/cave_layout.json"

var size := Vector2i(50, 50)
var points: Dictionary = {}
var _blocked: Dictionary = {}
var _access_gate_cells: Dictionary = {}
var _astar := AStarGrid2D.new()
## Changes to the navigation mask invalidate route and connected-region caches.
var navigation_revision := 0
var _component_ids := PackedInt32Array()
var _components_revision := -1

static func _read_layout(layout_path: String) -> Dictionary:
	var file := FileAccess.open(layout_path, FileAccess.READ)
	assert(file != null, "Missing map layout: %s" % layout_path)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary, "Invalid map layout: %s" % layout_path)
	return parsed

## Default spawns only need the compiled mask, not blocked dictionaries or AStar.
## Keep the same clamping and radius/row/column search order as nearest_walkable.
static func nearest_cell_in_layout(layout_path: String, cell: Vector2i) -> Vector2i:
	var data := _read_layout(layout_path)
	var dims: Array = data.get("grid_size", [50, 50])
	var extent := Vector2i(int(dims[0]), int(dims[1]))
	var rows: Array = data.get("walkable_rows", [])
	assert(rows.size() == extent.y)
	var clamped := cell.clamp(Vector2i.ZERO, extent - Vector2i.ONE)
	if String(rows[clamped.y])[clamped.x] == "1":
		return clamped
	for radius in range(1, maxi(extent.x, extent.y) + 1):
		for y in range(maxi(0, clamped.y - radius), mini(extent.y - 1, clamped.y + radius) + 1):
			var row := String(rows[y])
			for x in range(maxi(0, clamped.x - radius), mini(extent.x - 1, clamped.x + radius) + 1):
				if row[x] == "1":
					return Vector2i(x, y)
	return clamped

func _init(layout_path: String = PATH) -> void:
	var data := _read_layout(layout_path)
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
	return cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y \
		and not _blocked.has(cell) and not _access_gate_cells.has(cell)

func blocked_cells() -> Array:
	return _blocked.keys() + _access_gate_cells.keys()

## 井心主机场地在 C2Q10 交付前关闭；使用同一网格约束寻路与物理碰撞。
func set_access_gate_open(open: bool) -> void:
	if not points.has("gate"):
		return
	var gate: Array = points["gate"]
	var x := int(gate[0])
	if open == _access_gate_cells.is_empty():
		return
	navigation_revision += 1
	_access_gate_cells.clear()
	for y in range(size.y):
		var cell := Vector2i(x, y)
		if not _blocked.has(cell):
			if not open:
				_access_gate_cells[cell] = true
			_astar.set_point_solid(cell, not open)

func is_behind_access_gate(cell: Vector2i) -> bool:
	return not _access_gate_cells.is_empty() and cell.x > int((points["gate"] as Array)[0])

func boundary_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for raw in blocked_cells():
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

## Four-neighbour connectivity is equivalent to the current no-corner-cutting
## AStar rule: every legal diagonal has a walkable cardinal detour.
func _ensure_components() -> void:
	if _components_revision == navigation_revision:
		return
	_component_ids.resize(size.x * size.y)
	_component_ids.fill(0)
	# -1 = solid, 0 = unvisited. Query the authoritative AStar mask once.
	for y in range(size.y):
		for x in range(size.x):
			if _astar.is_point_solid(Vector2i(x, y)):
				_component_ids[y * size.x + x] = -1
	var queue := PackedInt32Array()
	queue.resize(size.x * size.y)
	var component := 0
	for seed in range(_component_ids.size()):
		if _component_ids[seed] != 0:
			continue
		component += 1
		var head := 0
		var tail := 1
		queue[0] = seed
		_component_ids[seed] = component
		while head < tail:
			var id := queue[head]
			head += 1
			var x := id % size.x
			for neighbor in [id - size.x, id + size.x, id - 1 if x > 0 else -1, id + 1 if x < size.x - 1 else -1]:
				if neighbor >= 0 and neighbor < _component_ids.size() and _component_ids[neighbor] == 0:
					_component_ids[neighbor] = component
					queue[tail] = neighbor
					tail += 1
	_components_revision = navigation_revision

func prepare_connectivity() -> void:
	_ensure_components()

func component_at(cell: Vector2i) -> int:
	_ensure_components()
	var resolved := nearest_walkable(cell)
	return _component_ids[resolved.y * size.x + resolved.x]

func reachable(from_cell: Vector2i, to_cell: Vector2i) -> bool:
	var component := component_at(from_cell)
	return component > 0 and component == component_at(to_cell)

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
