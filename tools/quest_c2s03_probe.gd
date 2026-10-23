extends Node
## 只读探针：C2S03「师父的旧钳子」目标怪 c2_elite_broken_inspector 是否真的会刷出来。
## 不写存档、不改数据；只打印事实。

const TARGET := "c2_elite_broken_inspector"
const MAP_ID := "c2_lower_works"

func _ready() -> void:
	GameState.reset_to_defaults()
	GameState.unlocks["chapter2"] = true

	print("==== ① 任务定义 ====")
	var tpl := Quest.template("C2S03")
	print("id=", tpl.get("id", ""), " name=", tpl.get("name", ""), " prev=", tpl.get("prev", ""))
	print("scope=", tpl.get("mapScope", []), " objective=", tpl.get("objective", {}))

	print("==== ② 地图里的刷点 ====")
	var md := MapService.data_for(MAP_ID)
	var found := []
	for spec in md.get("spawnPoints", []):
		if String(spec.get("monsterId", "")) == TARGET:
			found.append(spec)
	print("命中刷点 ", found.size(), " 条 -> ", JSON.stringify(found))
	print("地图名=", md.get("name", ""), " tierRange=", md.get("tierRange", []),
			" requiresUnlock=", md.get("requiresUnlock", ""))

	print("==== ③ 怪物模板 ====")
	var t: Variant = DataLoader.get_entry("monsters", TARGET)
	print("模板存在=", t is Dictionary, " level=", (t as Dictionary).get("level", -1) if t is Dictionary else -1,
			" kind=", (t as Dictionary).get("kind", "") if t is Dictionary else "")

	print("==== ④ 实跑：把玩家放到目标点附近再装配 ====")
	var cell := Vector2i(45, 87)
	GameState.current_map = MAP_ID
	GameState.save_pos = Iso.grid_to_world(cell)
	GameState.has_save_pos = true
	var main := preload("res://scenes/Main.tscn").instantiate()
	add_child(main)
	for _i in range(8):
		await get_tree().process_frame
	for _i in range(20):
		await get_tree().physics_frame

	var spawner := main.get_node_or_null("Game/Spawner")
	print("Spawner=", spawner, " point_count=", spawner.point_count() if spawner else -1)
	var by_id := {}
	if spawner:
		for child in spawner.get_children():
			var mid := String(child.get("monster_id") if child.get("monster_id") != null else "")
			if mid.is_empty():
				continue
			by_id[mid] = int(by_id.get(mid, 0)) + 1
	print("实例化怪种=", JSON.stringify(by_id))
	print("目标怪实例化数=", int(by_id.get(TARGET, 0)))

	print("==== ⑤ 目标点附近是否有别的怪 ====")
	var target_pos := Iso.grid_to_world(cell)
	var near := []
	if spawner:
		for child in spawner.get_children():
			var p := child as Node2D
			if p == null:
				continue
			var d := p.global_position.distance_to(target_pos)
			if d <= 320.0:
				near.append([str(p.get("monster_id")), int(d)])
	near.sort_custom(func(a, b): return int(a[1]) < int(b[1]))
	print("目标点 320px 内=", JSON.stringify(near))

	print("==== ⑥ 任务导航 ====")
	GameState.current_map = MAP_ID
	var nav := MapService.start_quest_navigation(TARGET, ["c2_lower_works"])
	print("导航结果=", JSON.stringify(nav))
	print("PROBE_DONE")
	get_tree().quit(0)
