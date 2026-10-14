extends Node

func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children():
		freeze(child)

func _ready() -> void:
	GameState.reset_to_defaults()
	GameState.current_map = "c2_lower_works"
	var explored := {}
	var blocks := Fog.block_grid(GameState.current_map)
	for id in range(blocks.x * blocks.y):
		explored[str(id)] = true
	GameState.explored_maps[GameState.current_map] = explored
	var main := preload("res://scenes/Main.tscn").instantiate()
	add_child(main)
	freeze(main)
	var canvas := MapCanvas.new()
	canvas.size = Vector2(240, 180)
	add_child(canvas)
	canvas.set_process(false)
	await get_tree().process_frame
	await get_tree().process_frame
	var ground := main.get_node("Game/Ground") as IsoGround
	assert(ground._blocked_mesh.get_surface_count() == 1)
	assert(ground._blocked_mesh.surface_get_array_len(0) == ground.cave.blocked_cells().size() * 4)
	assert(canvas._terrain_mesh.get_surface_count() == 1, "Explored cells share a single draw surface")
	var arrays := canvas._terrain_mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	assert(vertices.size() == 28740 * 4 and indices.size() == 28740 * 6)
	var seen := {}
	for offset in range(0, vertices.size(), 4):
		var center := Vector2.ZERO
		for i in range(4):
			center += Vector2(vertices[offset + i].x, vertices[offset + i].y) * 0.25
		var cell := Vector2i(canvas.canvas_to_grid(center).round())
		assert(ground.cave.is_walkable(cell), "Batched mesh must not reveal walls")
		assert(not seen.has(cell), "Each walkable cell appears exactly once")
		seen[cell] = true
	assert(seen.size() == 28740)
	GameState.explored_maps[GameState.current_map] = {}
	EventBus.fog_changed.emit(GameState.current_map)
	await get_tree().process_frame
	await get_tree().process_frame
	assert(canvas._terrain_mesh == null, "Reset exploration removes old geometry")
	print("[FlatTerrainMeshTest] PASS")
	get_tree().quit()
