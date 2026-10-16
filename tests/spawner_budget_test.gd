extends Node
## 刷新预算回归（E1）：预算按地图 kind 档位配置，普通／精英各自独立；
## 退役与外部释放都要回补，且每轮只做一次存活快照。

class CountingSpawner extends MonsterSpawner:
	var count_calls := 0
	func _active_counts() -> Dictionary:
		count_calls += 1
		return super._active_counts()

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
	assert(_normal(spawner) == 10, "Same batch must respect normal cap")
	spawner.count_calls = 0
	spawner._process(0.0)
	assert(spawner.count_calls == 1, "Saturated refresh counts only once")
	assert(_normal(spawner) == 10)
	# Death releases one slot, but the dead site remains on the global clock.
	var point: Dictionary = spawner._points[0]
	var monster := point.entry as Monster
	spawner._on_monster_died(point)
	monster.queue_free()
	spawner.count_calls = 0
	spawner._process(0.0)
	assert(spawner.count_calls == 1)
	assert(_normal(spawner) == 10, "Another ready site can fill a death slot")
	assert(point.entry == null and spawner._remaining(point) > 0, "Death cooldown must not be bypassed")
	# External freeing is accounted for at the next snapshot, without stale counters.
	var external := spawner._points[1].entry as Monster
	external.free()
	spawner._process(0.0)
	assert(_normal(spawner) == 10, "External deletion must not leak budget")
	player.position += Vector2(2000, 0)
	spawner._process(0.0)
	assert(_normal(spawner) == 0, "Far monsters retire")
	player.position -= Vector2(2000, 0)
	spawner._process(0.0)
	assert(_normal(spawner) == 10, "Return restores budget without overspawning")
	# Elite sites do not consume the ordinary-monster budget.
	spawner.spawn_from_specs([{"monsterId": "c2_spirit_larva", "count": 1,
		"cell": [9, 54], "kind": "elite", "ai": false}], "c2_pipe_slope")
	assert(spawner.alive_count() == 11 and _normal(spawner) == 10)
	# 第三章预算按图配置：枢纽 0/0/0，野外 10/2/1（maps.json 的 normalCap/eliteCap/bossCap）。
	var cells_c3: Array = []
	for i in range(30):
		cells_c3.append([9, 54])
	var hub := CountingSpawner.new()
	add_child(hub)
	hub.set_process(false)
	hub.setup(null, player)
	hub.spawn_from_specs([{"monsterId": "c3_normal01", "count": 10, "cells": cells_c3, "ai": false}], "c3_map00")
	assert(hub.alive_count() == 0, "安全枢纽不生成怪物")
	var field := CountingSpawner.new()
	add_child(field)
	field.set_process(false)
	field.setup(null, player)
	field.spawn_from_specs([{"monsterId": "c3_normal01", "count": 30, "cells": cells_c3, "ai": false}], "c3_map01")
	assert(_normal(field) == 10, "第三档普通怪按图配置封顶 10")
	field.spawn_from_specs([{"monsterId": "c3_elite01", "count": 5, "cells": cells_c3, "kind": "elite", "ai": false}], "c3_map01")
	assert(int(field._active_counts().get("elite", 0)) == 2, "精英按图配置封顶 2")
	field.spawn_from_specs([{"monsterId": "c3_boss01", "count": 3, "cells": cells_c3, "kind": "boss", "ai": false}], "c3_map01")
	assert(int(field._active_counts().get("boss", 0)) == 1, "首领按图配置封顶 1")
	print("[SpawnerBudgetTest] PASS")
	get_tree().quit()

## 当前存活普通怪数（旧版 `_active_normal_count()` 的等价查询）。
func _normal(spawner: MonsterSpawner) -> int:
	return int(spawner._active_counts().get("normal", 0))
