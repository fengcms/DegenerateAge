class_name CaveNavigator
extends RefCounted
## Cached four-neighbour route for moving targets inside the cave.

var _target_cell := Vector2i(-1, -1)
var _waypoints: Array[Vector2] = []
var _index := 0

func has_route() -> bool:
	return not _waypoints.is_empty()

func direction(ground: IsoGround, origin: Vector2, target: Vector2) -> Vector2:
	if ground == null or ground.cave == null:
		return origin.direction_to(target)
	var cell := Vector2i(Iso.world_to_grid(target).round())
	if cell != _target_cell or _waypoints.is_empty() or (_index < _waypoints.size() and origin.distance_to(_waypoints[_index]) > 96.0):
		_target_cell = cell
		_waypoints = ground.route(origin, ground.clamp_to_map(target))
		_index = 0
	if _waypoints.is_empty():
		return Vector2.ZERO
	while _index < _waypoints.size() and origin.distance_to(_waypoints[_index]) < 9.0:
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
