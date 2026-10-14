extends Node

class CountingSpawner extends MonsterSpawner:
	var count_calls := 0
	func _active_normal_count() -> int:
		count_calls += 1
		return super._active_normal_count()

func _ready() -> void:
	GameState.reset_to_defaults()
	GameState.current_map = "c2_pipe_slope"
	var player := Node2D.new()
	add_child(player)
	player.position = Iso.grid_to_world(Vector2i(9, 54))
	var spawner := CountingSpawner.new()
	add_child(spawner)
	spawner.set_process(false)
	spawner.setup(null, player)
	var cells: Array = []
	for i in range(30):
		cells.append([9, 54])
	spawner.spawn_from_specs([{"monsterId": "c2_spirit_larva", "count": 30,
		"cells": cells, "ai": false, "respawnTime": 30}], "c2_pipe_slope")
	assert(spawner.count_calls == 1, "Initialization counts once, not per site")
	assert(spawner._active_normal_count() == 10, "Same batch must respect normal cap")
	spawner.count_calls = 0
	spawner._process(0.0)
	assert(spawner.count_calls == 1, "Saturated refresh counts only once")
	assert(spawner._active_normal_count() == 10)
	# Death releases one slot, but the dead site remains on the global clock.
	var point: Dictionary = spawner._points[0]
	var monster := point.entry as Monster
	spawner._on_monster_died(point)
	monster.queue_free()
	spawner.count_calls = 0
	spawner._process(0.0)
	assert(spawner.count_calls == 1)
	assert(spawner._active_normal_count() == 10, "Another ready site can fill a death slot")
	assert(point.entry == null and spawner._remaining(point) > 0, "Death cooldown must not be bypassed")
	# External freeing is accounted for at the next snapshot, without stale counters.
	var external := spawner._points[1].entry as Monster
	external.free()
	spawner._process(0.0)
	assert(spawner._active_normal_count() == 10, "External deletion must not leak budget")
	player.position += Vector2(2000, 0)
	spawner._process(0.0)
	assert(spawner._active_normal_count() == 0, "Far monsters retire")
	player.position -= Vector2(2000, 0)
	spawner._process(0.0)
	assert(spawner._active_normal_count() == 10, "Return restores budget without overspawning")
	# Elite sites do not consume the ordinary-monster budget.
	spawner.spawn_from_specs([{"monsterId": "c2_spirit_larva", "count": 1,
		"cell": [9, 54], "kind": "elite", "ai": false}], "c2_pipe_slope")
	assert(spawner.alive_count() == 11 and spawner._active_normal_count() == 10)
	print("[SpawnerBudgetTest] PASS")
	get_tree().quit()
