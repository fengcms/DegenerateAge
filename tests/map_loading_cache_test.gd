extends Node

func _ready() -> void:
	GameState.reset_to_defaults()
	for map_id in ["camp", "wild_trial", "ash_land", "corruption_source", "c2_well_town",
			"c2_pipe_slope", "c2_old_well", "c2_lower_works", "c2_ember_furnace", "c2_well_core"]:
		var data := MapService.data_for(map_id)
		var path := String(data.layoutPath)
		var layout := CaveLayout.new(path)
		var center := MapService.grid_size(map_id) / 2
		assert(MapService.entry_point(map_id) == Iso.grid_to_world(layout.nearest_walkable(center)))
		for cell in [Vector2i(-10, -10), layout.size + Vector2i.ONE, Vector2i.ZERO, center]:
			assert(CaveLayout.nearest_cell_in_layout(path, cell) == layout.nearest_walkable(cell), "Mask-only spawn must retain nearest-cell ordering")
	var file := FileAccess.open("user://entry-cache-layout.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"grid_size": [3, 3], "walkable_rows": ["111", "111", "111"]}))
	file.close()
	var maps: Array = DataLoader.get_table("maps")
	var fixture := {"id": "_entry_cache_test", "size": {"w": 3, "h": 3}, "layoutPath": "user://entry-cache-layout.json"}
	maps.append(fixture)
	assert(MapService.entry_point("_entry_cache_test") == Iso.grid_to_world(Vector2i(1, 1)))
	fixture.size = {"w": 2, "h": 2}
	MapService.entry_point("_entry_cache_test")
	assert(MapService._entry_cache["_entry_cache_test"].size == Vector2i(2, 2), "Dimension changes invalidate entry cache")
	file = FileAccess.open("user://entry-cache-layout.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"grid_size": [3, 3], "walkable_rows": ["111", "101", "111"]}))
	file.close()
	EventBus.data_loaded.emit()
	assert(MapService._entry_cache.is_empty(), "Reloading tables clears default entries")
	assert(MapService.entry_point("_entry_cache_test") == Iso.grid_to_world(Vector2i.ZERO))
	maps.erase(fixture)
	GameState.current_map = "c2_lower_works"
	var ground := IsoGround.new()
	add_child(ground)
	assert(ground.cave._components_revision == ground.cave.navigation_revision, "Connectivity is ready before gameplay")
	var walls := ground.get_node("CaveWalls")
	assert(walls.get_child_count() == 522, "Collision geometry count is unchanged")
	var shape := (walls.get_child(0) as CollisionShape2D).shape
	for child: CollisionShape2D in walls.get_children():
		assert(is_same(child.shape, shape), "All static diamonds share one shape resource")
	var start := Time.get_ticks_usec()
	for i in range(1000):
		MapService.entry_point(GameState.current_map)
	print("[PERF] default entry 1000 cached calls: %.3f ms" % ((Time.get_ticks_usec() - start) / 1000.0))
	print("[MapLoadingCacheTest] PASS")
	get_tree().quit()
