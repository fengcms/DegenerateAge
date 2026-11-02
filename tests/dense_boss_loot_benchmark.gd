extends Node
## 高倍速实际窗口基准：100真实Boss、2400混合持久掉落；固定玩家隔离推进与绘制成本。
## 无硬件帧率通过阈值，不模拟持续击杀、完整HUD或真实存档I/O，不得当作全部游戏FPS。
var rendered := 0

## 统计实际提交的绘制，避免窗口未绘制时产生假改善。
func _on_render() -> void:
	rendered += 1

## 按现实秒预热/采样，记录物理补步、尾部帧时间、引擎快照；不改变游戏时间。
func observe(seconds: float, collect: bool) -> Dictionary:
	var samples: Array[float] = []
	var until := Time.get_ticks_usec()+int(seconds*1000000)
	var last := Time.get_ticks_usec()
	var physics_start := Engine.get_physics_frames()
	var render_start := rendered
	while Time.get_ticks_usec() < until:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		if collect:
			samples.append((now-last)/1000.0)
		last = now
	if not collect:
		return {}
	assert(rendered > render_start, "必须发生实际绘制")
	samples.sort()
	var idle := get_node_or_null("Game/LootRoot/GroundLootIdle")
	return {"parked":int(idle.get("_sleepers").size()) if idle != null else 0,"frames":samples.size(),"physics_steps":Engine.get_physics_frames()-physics_start,
		"p50_ms":samples[int(samples.size()*0.5)],"p95_ms":samples[int(samples.size()*0.95)],
		"p99_ms":samples[int(samples.size()*0.99)],"max_ms":samples[-1],
		"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"memory_mb":Performance.get_monitor(Performance.MEMORY_STATIC)/1048576.0,
		"nodes":get_tree().get_node_count(),"items":get_tree().get_nodes_in_group("ground_items").size(),
		"enemies":get_tree().get_nodes_in_group("enemies").size(),"cache":GroundLootVisualCache._textures.size()}

## 固定种子、地图与几何，各倍率预热1秒采样3秒；保留100敌人和2400奖励记录。
func _ready() -> void:
	assert(DisplayServer.get_name() != "headless", "必须实际窗口运行")
	get_window().size = Vector2i(1280,800)
	get_window().content_scale_size = Vector2i.ZERO
	seed(4513)
	GameState.reset_to_defaults()
	GameState.current_map = "c7_boss_field"
	GameState.player.level = 600
	GameState.player.hpFlat = 10000000
	GameState.player.hp = GameState.max_hp()
	GameState.inventory = Inventory.create(200)
	for i in range(200):
		GameState.inventory[i] = ItemFactory.make_any("potion_hp_small",999)
	GameState.set_auto_pickup(true)
	var ui := CanvasLayer.new()
	add_child(ui)
	ui.add_child(load("res://scenes/ui/BossHealthBar.tscn").instantiate())
	var world: Node2D = load("res://scenes/Game.tscn").instantiate()
	add_child(world)
	world.get_node("Spawner").set_process(false)
	var player := world.get_node("Entities/Player") as PlayerCharacter
	player.set_physics_process(false)
	player.get_node("AutoPilot").set_physics_process(false)
	player._invuln = 360000.0
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	await get_tree().process_frame
	var ground := world.get_node("Ground") as IsoGround
	var center := player.global_position
	var ids: Array = DataLoader.get_table("bossVisuals").bosses.keys()
	for i in range(100):
		var boss := load("res://scenes/entities/Monster.tscn").instantiate() as Monster
		boss.monster_id = ids[i%ids.size()]
		boss.ai_enabled = true
		boss.position = ground.clamp_to_map(center+Vector2.from_angle(i*2.4)*(90+i%8*45))
		boss.spawn_position = boss.position
		world.get_node("Entities").add_child(boss)
	var equip_ids: Array[String] = []
	for entry in DataLoader.get_table("equipments"):
		if String(entry.id).begins_with("c6_equip_"):
			equip_ids.append(String(entry.id))
	equip_ids.sort()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4513
	for i in range(2400):
		var item := load("res://scenes/entities/GroundItem.tscn").instantiate() as GroundItem
		item.item = ItemFactory.make_equip_exact(equip_ids[i%equip_ids.size()],500,["rare","epic","legendary"][i%3],rng)
		item.batch_size = 30
		item.persistent = true
		item.hold_time = 0.0
		item.position = center+Vector2((i%60)*8-240,floori(i/60.0)*8-160)
		world.get_node("LootRoot").add_child(item)
	RenderingServer.frame_post_draw.connect(_on_render)
	await observe(8.0,false)
	for speed in [4.0,8.0,16.0]:
		Engine.time_scale = speed
		await observe(1.0,false)
		var result := await observe(3.0,true)
		assert(result.items == 2400 and result.enemies == 100 and GameState.unclaimed_count(GameState.current_map) == 2400)
		result.scale = speed
		print("[PERF] dense_boss_loot ",JSON.stringify(result))
	Engine.time_scale = 1.0
	print("[DenseBossLootBenchmark] PASS")
	get_tree().quit()
