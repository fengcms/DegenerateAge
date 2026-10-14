extends Node

func frames() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children():
		freeze(child)

func _ready() -> void:
	GameState.reset_to_defaults()
	GameState.current_map = "c2_lower_works"
	var main := preload("res://scenes/Main.tscn").instantiate()
	add_child(main)
	freeze(main)
	var player := main.get_node("Game/Entities/Player") as PlayerCharacter
	var canvas := MapCanvas.new()
	canvas.size = Vector2(240, 180)
	canvas.minimap = true
	add_child(canvas)
	canvas.set_process(false)
	await frames()
	assert(canvas.background_draw_count > 0, "Static canvas must draw initially")
	var count := canvas.background_draw_count
	player.position += Vector2(1, 0)
	canvas.refresh()
	await frames()
	assert(canvas.background_draw_count == count, "Player movement must only redraw overlay")
	EventBus.fog_changed.emit(GameState.current_map)
	await frames()
	assert(canvas.background_draw_count > count, "Exploration must redraw terrain")
	count = canvas.background_draw_count
	canvas.size = Vector2(360, 240)
	await frames()
	assert(canvas.background_draw_count > count, "Resize must rebuild terrain projection")
	for mode in [false, true]:
		canvas.minimap = mode
		canvas.refresh()
		for cell in [Vector2(0, 0), Vector2(120, 67), Vector2(239, 134)]:
			assert(canvas.canvas_to_grid(canvas.world_to_canvas(Iso.grid_pt(cell.x, cell.y))).distance_to(cell) < 0.001)
	await frames()
	count = canvas.background_draw_count
	GameState.explored_maps[GameState.current_map] = {"0": true}
	canvas.refresh()
	await frames()
	assert(canvas.background_draw_count > count, "Replacing exploration on load must invalidate terrain")
	count = canvas.background_draw_count
	canvas.hide()
	GameState.explored_maps[GameState.current_map] = {"1": true}
	EventBus.fog_changed.emit(GameState.current_map)
	await frames()
	canvas.show()
	canvas.refresh()
	await frames()
	assert(canvas.background_draw_count > count, "Hidden map must draw latest exploration when reopened")
	count = canvas.background_draw_count
	canvas.refresh()
	await frames()
	assert(canvas.background_draw_count == count, "Unchanged map must retain cached draw commands")
	print("[MapCanvasCacheTest] PASS")
	get_tree().quit()
