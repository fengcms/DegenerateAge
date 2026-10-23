extends Node
## 工程 100：任务目标的「精英」刷点在冷却期必须在原地留倒计时（tombstone）。
##
## 为什么需要这层守门：`tombstone` 是**纯数据字段**，漏配不会编译报错、也不影响刷怪，
## 但它就是玩家唯一能看出「这怪在冷却，不是没刷」的线索。缺了它，任务箭头会照常
## 指向一格空地（`_on_monster_died` 保留死亡位置），玩家只能判断成「任务坏了」。
##
## 口径：只要求**被 kill 任务引用的精英**带墓碑；不要求其余精英也带（那是设计取舍）。

var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("[QuestTargetRespawnHintTest] " + message)

func _ready() -> void:
	GameState.reset_to_defaults()
	GameState.unlocks["chapter2"] = true

	# ---- ① 任务目标精英刷点：从任务数据推导，不写死 id 清单 ----
	var hits := 0
	var missing: Array[String] = []
	for quest in DataLoader.get_table("quests"):
		var tpl: Dictionary = quest as Dictionary
		var objective: Dictionary = tpl.get("objective", {})
		if String(objective.get("kind", "")) != "kill":
			continue
		var target_id := String(objective.get("targetId", ""))
		var monster: Variant = DataLoader.get_entry("monsters", target_id)
		if not (monster is Dictionary):
			continue
		if String((monster as Dictionary).get("kind", "")) != "elite":
			continue
		for raw_map in tpl.get("mapScope", []):
			var map_id := String(raw_map)
			for raw_spec in MapService.data_for(map_id).get("spawnPoints", []):
				var spec: Dictionary = raw_spec as Dictionary
				if String(spec.get("monsterId", "")) != target_id:
					continue
				hits += 1
				if not bool(spec.get("tombstone", false)):
					missing.append("%s/%s" % [map_id, target_id])
	check(hits >= 5, "任务目标精英刷点至少 5 处（非空跑前置），实际 %d" % hits)
	check(missing.is_empty(), "任务目标精英刷点必须带 tombstone：%s" % str(missing))

	# ---- ② Boss 侧不得被这次改动波及 ----
	var bosses := 0
	var boss_missing: Array[String] = []
	for entry in DataLoader.get_table("maps"):
		var md: Dictionary = entry as Dictionary
		var boss: Variant = md.get("bossSpawn", null)
		if not (boss is Dictionary):
			continue
		bosses += 1
		if not bool((boss as Dictionary).get("tombstone", false)):
			boss_missing.append(String(md.get("id", "")))
	check(bosses >= 17, "Boss 刷点至少 17 处（非空跑前置），实际 %d" % bosses)
	check(boss_missing.is_empty(), "Boss 刷点必须全部带 tombstone：%s" % str(boss_missing))

	# ---- ③ 文案：绝对期望串（不复用被测常量），且不得再写死 Boss ----
	check(Localization.tr_key("ui.boss_tombstone.p001", [1, 5]) == "刷新 01:05",
		"倒计时渲染为「刷新 01:05」")
	check(not Localization.tr_key("ui.boss_tombstone.p001", [59, 59]).contains("Boss"),
		"倒计时文案不写死 Boss（精英复用同一句）")

	# ---- ④ 行为层：真把该点标记为冷却中，装配后原地必须长出墓碑 ----
	var map_id := "c2_lower_works"
	var target := "c2_elite_broken_inspector"
	var spec_cell := Vector2i(-1, -1)
	for raw_spec in MapService.data_for(map_id).get("spawnPoints", []):
		var spec: Dictionary = raw_spec as Dictionary
		if String(spec.get("monsterId", "")) != target:
			continue
		var raw_cells: Variant = spec.get("cells", null)
		var one: Variant = raw_cells[0] if raw_cells is Array and (raw_cells as Array).size() > 0 else spec.get("cell", null)
		if one is Array and (one as Array).size() == 2:
			spec_cell = Vector2i(int((one as Array)[0]), int((one as Array)[1]))
	check(spec_cell.x >= 0, "能从数据里取到目标刷点格（非空跑前置）")

	var target_pos := Iso.grid_to_world(spec_cell)
	GameState.mark_spawn_dead(map_id, target, 0, 120.0, target_pos)
	check(GameState.spawn_remaining(map_id, target, 0) > 100.0, "标记后该点确实处在冷却中")

	GameState.current_map = map_id
	GameState.save_pos = target_pos
	GameState.has_save_pos = true
	var main := preload("res://scenes/Main.tscn").instantiate()
	add_child(main)
	for _i in range(6):
		await get_tree().process_frame

	var spawner := main.get_node_or_null("Game/Spawner")
	check(spawner != null, "装配出 Spawner")
	var stones := 0
	var nearest := -1.0
	if spawner != null:
		for child in spawner.get_children():
			if not (child is BossTombstone):
				continue
			stones += 1
			var dist: float = (child as Node2D).global_position.distance_to(target_pos)
			if nearest < 0.0 or dist < nearest:
				nearest = dist
	check(stones >= 1, "冷却中的任务目标精英原地必须有墓碑，实际 %d" % stones)
	check(nearest >= 0.0 and nearest < 64.0, "墓碑落在该刷点格上（偏差 %.1fpx）" % nearest)

	print("[QuestTargetRespawnHintTest] ", "全部通过 ✅" if failures.is_empty() else str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
