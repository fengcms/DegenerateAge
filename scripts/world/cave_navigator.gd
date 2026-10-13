class_name CaveNavigator
extends RefCounted
## Cached collision-safe route for moving targets inside the cave.

var _target_cell := Vector2i(-1, -1)
var _waypoints: Array[Vector2] = []
var _index := 0
var _segment_start := Vector2.ZERO
var _route_origin_cell := Vector2i(-1, -1)

func has_route() -> bool:
	return not _waypoints.is_empty()

func direction(ground: IsoGround, origin: Vector2, target: Vector2) -> Vector2:
	if ground == null or ground.cave == null:
		return origin.direction_to(target)
	var cell := Vector2i(Iso.world_to_grid(target).round())
	var origin_cell := Vector2i(Iso.world_to_grid(origin).round())
	var deviated := _index < _waypoints.size() and origin.distance_to(
		Geometry2D.get_closest_point_to_segment(origin, _segment_start, _waypoints[_index])) > 48.0
	if cell != _target_cell or (_waypoints.is_empty() and origin_cell != _route_origin_cell) or deviated:
		_target_cell = cell
		_route_origin_cell = origin_cell
		_waypoints = ground.route(origin, ground.clamp_to_map(target))
		_index = 0
		_segment_start = origin
	if _waypoints.is_empty():
		return Vector2.ZERO
	while _index < _waypoints.size() and origin.distance_to(_waypoints[_index]) < 9.0:
		_segment_start = _waypoints[_index]
		_index += 1
	if _index < _waypoints.size():
		return origin.direction_to(_waypoints[_index])
	# Only the final walkable cell permits a short direct correction toward an off-centre item.
	# A missing route must never fall back to a line through cave walls.
	if Vector2i(Iso.world_to_grid(origin).round()) == cell and ground.cave.is_walkable(cell):
		return origin.direction_to(target)
	return Vector2.ZERO

func clear() -> void:
	_target_cell = Vector2i(-1, -1)
	_waypoints.clear()
	_index = 0
	_segment_start = Vector2.ZERO
	_route_origin_cell = Vector2i(-1, -1)
