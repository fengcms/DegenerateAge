extends Node
## Deterministic CPU benchmark; use the isolated runner to protect real saves.
## Timings are diagnostics, not hardware-dependent pass/fail thresholds.

func _ready() -> void:
	GameState.reset_to_defaults()
	GameState.current_map = "c2_lower_works"
	GameState.save_pos = MapService.entry_point(GameState.current_map)
	GameState.has_save_pos = true
	var start := Time.get_ticks_usec()
	var main := preload("res://scenes/Main.tscn").instantiate()
	add_child(main)
	print("[PERF] lower_works scene setup: %.3f ms" % ((Time.get_ticks_usec() - start) / 1000.0))
	var world := main.get_node("Game")
	var player := world.get_node("Entities/Player") as PlayerCharacter
	var pilot := player.get_node("AutoPilot") as AutoBattle
	start = Time.get_ticks_usec()
	pilot._build_roam_points()
	print("[PERF] roam build: %.3f ms, %d points" % [
		(Time.get_ticks_usec() - start) / 1000.0, pilot._roam_points.size()])
	assert(not pilot._roam_points.is_empty(), "Largest map needs reachable roam points")
	var canvas := MapCanvas.new()
	canvas.minimap = true
	canvas.size = Vector2(180, 180)
	add_child(canvas)
	var point := player.global_position
	start = Time.get_ticks_usec()
	for i in range(10000):
		canvas.world_to_canvas(point + Vector2(i % 100, 0))
	print("[PERF] map projection 10000 calls: %.3f ms" % ((Time.get_ticks_usec() - start) / 1000.0))
	var roundtrip := canvas.canvas_to_grid(canvas.world_to_canvas(point))
	assert(roundtrip.distance_to(Iso.world_to_grid(point)) < 0.001, "Projection round trip")
	var spawner := world.get_node("Spawner") as MonsterSpawner
	start = Time.get_ticks_usec()
	for i in range(200):
		spawner._process(0.0)
	print("[PERF] spawner 200 ticks: %.3f ms, %d sites" % [
		(Time.get_ticks_usec() - start) / 1000.0, spawner.point_count()])
	assert(spawner._active_normal_count() <= MonsterSpawner.CHAPTER_TWO_NORMAL_BUDGET)
	print("[MapPerformanceTest] PASS")
	get_tree().quit()
