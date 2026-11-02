extends Node
## 实际窗口掉落压力基准：2400件同模板紫装同屏、满200格，冻结Boss/玩家以隔离掉落成本。
## 帧时间无硬件相关通过阈值；不是100 Boss持续战斗或真实存档的FPS承诺。

## 用真实经过时间采样帧间隔；倍率不影响采样窗口长度。
func observe(seconds: float, collect: bool) -> Array[float]:
	var samples: Array[float] = []
	var until := Time.get_ticks_usec() + int(seconds*1000000)
	var last := Time.get_ticks_usec()
	while Time.get_ticks_usec() < until:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		if collect:
			samples.append((now-last)/1000.0)
		last = now
	return samples

## 固定种子、布局和候选密度，每个倍率预热2秒、采样3秒，记录原始样本数量。
func _ready() -> void:
	assert(DisplayServer.get_name() != "headless", "必须实际窗口运行")
	get_window().size = Vector2i(1280,800)
	get_window().content_scale_size = Vector2i.ZERO
	GameState.reset_to_defaults("mage")
	GameState.current_map = "c7_boss_field"
	GameState.inventory = Inventory.create(200)
	for i in range(200):
		GameState.inventory[i] = ItemFactory.make_any("potion_hp_small",999)
	GameState.set_auto_pickup(true)
	var world: Node2D = load("res://scenes/Game.tscn").instantiate()
	add_child(world)
	world.get_node("Spawner").set_process(false)
	var player := world.get_node("Entities/Player") as PlayerCharacter
	player.set_physics_process(false)
	player.get_node("AutoPilot").set_physics_process(false)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.set_physics_process(false)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4513
	for i in range(2400):
		var gi := load("res://scenes/entities/GroundItem.tscn").instantiate() as GroundItem
		gi.item = ItemFactory.make_equip_exact("c6_equip_weapon",500,"legendary",rng)
		gi.batch_size = 30
		gi.hold_time = 0.0
		gi.position = player.position + Vector2((i%60)*8-240,floori(i/60.0)*8-160)
		world.get_node("LootRoot").add_child(gi)
	for speed in [1.0,8.0]:
		Engine.time_scale = speed
		await observe(2.0,false)
		var samples := await observe(3.0,true)
		samples.sort()
		assert(get_tree().get_nodes_in_group("ground_items").size() == 2400, "不能用删除掉落换性能")
		print("[PERF] loot_backlog ",JSON.stringify({"scale":speed,"frames":samples.size(),"p50_ms":samples[int(samples.size()*0.5)],"p95_ms":samples[int(samples.size()*0.95)],"max_ms":samples[-1],"items":2400}))
	Engine.time_scale = 1.0
	print("[LootBacklogBenchmark] PASS")
	get_tree().quit()
