extends Node
## Encounter budgets and fixed cells: the 392 sites must not all instantiate at once.

var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("[ChapterTwoEncountersTest] " + message)

func _ready() -> void:
	GameState.reset_to_defaults()
	var expected := {
		"c2_pipe_slope": [84, 2, 0], "c2_old_well": [90, 3, 1],
		"c2_lower_works": [128, 3, 0], "c2_ember_furnace": [54, 1, 1],
		"c2_well_core": [36, 2, 1],
	}
	for map_id in expected:
		var data := MapService.data_for(map_id)
		var layout := CaveLayout.new(String(data.layoutPath))
		var normal := 0
		var elite := 0
		for spec in data.spawnPoints:
			if String(spec.get("kind", "normal")) == "elite":
				elite += int(spec.count)
			else:
				normal += int(spec.count)
			var cells: Variant = spec.get("cells", [spec.get("cell", [])])
			check(cells.size() == int(spec.count), "%s 固定刷新格数量" % map_id)
			for raw in cells:
				check(layout.is_walkable(Vector2i(int(raw[0]), int(raw[1]))), "%s 怪物不在障碍中" % map_id)
		check([normal, elite, 0 if data.bossSpawn == null else 1] == expected[map_id], "%s 刷新预算" % map_id)
	GameState.current_map = "c2_pipe_slope"
	GameState.save_pos = Iso.grid_to_world(Vector2i(9, 54))
	GameState.has_save_pos = true
	var main := preload("res://scenes/Main.tscn").instantiate()
	add_child(main)
	var spawner := main.get_node("Game/Spawner") as MonsterSpawner
	check(spawner.point_count() == 86, "断管坡全部刷新位登记")
	check(int(spawner._active_counts().get("normal", 0)) <= MonsterSpawner.LEGACY_NORMAL_CAP, "近处只激活有限怪群")
	print("[ChapterTwoEncountersTest] ", "全部通过 ✅" if failures.is_empty() else str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
