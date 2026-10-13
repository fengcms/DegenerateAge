extends Node
## Route contract for the cave: detour around walls and never fall back to wall-running.

func _ready() -> void:
	var ground := IsoGround.new()
	ground.cave = CaveLayout.new()
	var origin := Iso.grid_to_world(Vector2i(8, 25))
	var destination := Iso.grid_to_world(Vector2i(40, 26))
	var route := ground.route(origin, destination)
	assert(route.size() > 32, "Cave route must detour through passages")
	var nav := CaveNavigator.new()
	var direction := nav.direction(ground, origin, destination)
	assert(direction != Vector2.ZERO and nav.has_route(), "Reachable destination needs a route")
	# Isolate the entrance cell. There must be no direct-line fallback across the wall.
	var entrance := Vector2i(8, 25)
	for neighbor in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		ground.cave._astar.set_point_solid(entrance + neighbor)
	nav.clear()
	assert(nav.direction(ground, origin, destination) == Vector2.ZERO, "Unreachable route must stop")
	assert(not nav.has_route(), "Unreachable route must stay empty")
	print("[CaveNavigationTest] 全部通过 ✅")
	ground.free()
	get_tree().quit()
