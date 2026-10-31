extends Node
## 百首禁域窗口压力验收：100个真实Boss、2400个真实掉落，倍率1～16及人为160ms停顿。
## 使用隔离角色无敌和延长测试掉落寿命保持固定负载；不改变正式预算、奖励或物品配置。
var failures: Array[String] = []
var rendered_frames := 0

## 聚合失败，恢复引擎倍率并释放完整世界后才结束。
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

## 固定玩家位置只给100像素阶跃，排除寻路/击退，单独检验真实渲染压力下的镜头。
func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().quit(1)
		return
	DisplayServer.window_set_size(Vector2i(1280, 800))
	RenderingServer.render_loop_enabled = false
	RenderingServer.frame_post_draw.connect(_on_render)
	var original := Engine.time_scale
	Engine.time_scale = 1.0
	GameState.reset_to_defaults()
	GameState.current_map = "c7_boss_field"
	GameState.player.level = 100
	GameState.player.hpFlat = 10000000
	GameState.player.hp = GameState.max_hp()
	var baseline := get_tree().get_node_count()
	var world := preload("res://scenes/Game.tscn").instantiate()
	add_child(world)
	world.get_node("Spawner").set_process(false)
	var player := world.get_node("Entities/Player") as PlayerCharacter
	player.set_physics_process(false)
	player.get_node("AutoPilot").set_physics_process(false)
	player._invuln = 36000.0
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	await get_tree().process_frame
	var ground := world.get_node("Ground") as IsoGround
	var center := player.global_position
	var ids: Array = DataLoader.get_table("bossVisuals").bosses.keys()
	for i in range(100):
		var boss := preload("res://scenes/entities/Monster.tscn").instantiate() as Monster
		boss.monster_id = ids[i % ids.size()]
		boss.ai_enabled = true
		boss.position = ground.clamp_to_map(center + Vector2.from_angle(i * 2.4) * (90 + i % 8 * 45))
		boss.spawn_position = boss.position
		world.get_node("Entities").add_child(boss)
	for i in range(2400):
		var item := preload("res://scenes/entities/GroundItem.tscn").instantiate() as GroundItem
		item.item = {"kind":"coin", "itemId":"coin", "gold":1, "count":1}
		item.manual_only = true
		item._life = 36000.0
		item.position = ground.clamp_to_map(center + Vector2((i % 60 - 30) * 12, (i / 60 - 20) * 9))
		world.get_node("LootRoot").add_child(item)
		if i % 200 == 199:
			await get_tree().process_frame
	var camera := player.get_node("Camera2D") as StableFollowCamera
	var initial_nodes := get_tree().get_node_count()
	for scale in [1.0, 2.0, 4.0, 8.0, 16.0]:
		Engine.time_scale = scale
		player.global_position = center
		camera.snap_to_target()
		player.global_position = center + Vector2(100, 0)
		var previous := camera.global_position
		var jumps: Array[float] = []
		var frames: Array[float] = []
		var last := Time.get_ticks_usec()
		for frame in range(90):
			if frame == 30:
				OS.delay_msec(160) # 受控大帧，旧平滑会放大scaled delta；新跟随不得越过目标。
			await get_tree().process_frame
			RenderingServer.force_draw(false) # 即使测试窗口被遮挡也执行真实绘制，避免等待一个不会来的绘制信号。
			var now := Time.get_ticks_usec()
			frames.append((now - last) / 1000.0)
			last = now
			var position := camera.get_screen_center_position()
			jumps.append(position.distance_to(previous))
			check(position.is_finite() and position.x >= previous.x - 0.01 and position.x <= player.global_position.x + 0.01, "密集负载镜头有限且单调，不往返越过玩家")
			previous = position
		frames.sort()
		jumps.sort()
		check(get_tree().get_nodes_in_group("ground_items").size() == 2400, "压力样本没有静默减少掉落")
		print("[PERF] camera scale=", scale, " frame_ms=", [frames[45],frames[85],frames[89]], " max_camera_step_px=", jumps[-1], " final_error_px=", camera.global_position.distance_to(player.global_position), " nodes=", get_tree().get_node_count(), " baseline_nodes=", initial_nodes, " memory=", Performance.get_monitor(Performance.MEMORY_STATIC))
	check(rendered_frames >= 450, "每个压力样本都实际绘制")
	get_viewport().get_texture().get_image().save_png("/tmp/stable_camera_stress.png")
	RenderingServer.render_loop_enabled = true
	Engine.time_scale = original
	world.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	check(get_tree().get_node_count() <= baseline + 8, "退出压力世界相机和样本均释放")
	print("[CameraStressTest] ", "全部通过 ✅" if failures.is_empty() else str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)

## 统计实际完成绘制次数，避免被遮挡/最小化的窗口让验收空转。
func _on_render() -> void:
	rendered_frames += 1
