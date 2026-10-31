extends Node
## 正式Game场景自动战斗长时回归；默认三图各600游戏秒，总30分钟，允许固定步长加速执行。
## 隔离测试注入高生存属性，保留真实AI、寻路、拾取与掉落；不能作为正常角色平衡或GPU帧率证据。
var kills := 0
var pickups := 0
var seconds_per_map := 600
var render_frames: Array[float] = []
var last_render_usec := 0
var render_warmup := 60

## 计数实际怪物死亡事件，不替代或直接调用奖励结算。
func _on_kill(_id: String) -> void:
	kills += 1

## 计数实际拾取事件，不手动清空掉落或背包。
func _on_pickup(_id: String) -> void:
	pickups += 1

## 每图真实推进物理帧；定期记录活动节点、内存、路线状态，退图检查节点释放。
func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seconds-per-map="):
			seconds_per_map = maxi(1, arg.trim_prefix("--seconds-per-map=").to_int())
	if DisplayServer.get_name() != "headless":
		RenderingServer.frame_post_draw.connect(_on_render)
	EventBus.monster_died.connect(_on_kill)
	EventBus.item_picked.connect(_on_pickup)
	var started := Time.get_ticks_usec()
	var baseline_nodes := get_tree().get_node_count()
	for map_id in ["corruption_source", "c2_ember_furnace", "c7_arena"]:
		GameState.reset_to_defaults()
		GameState.current_map = map_id
		GameState.player.level = 100
		GameState.player.attack = 50000 if map_id == "c7_arena" else 500
		GameState.player.defense = 50000 if map_id == "c7_arena" else 500
		GameState.player.hpFlat = 1000000
		GameState.player.hp = GameState.max_hp()
		GameState.player.mp = GameState.max_mp()
		GameState.settings.allowBoss = true
		render_frames.clear()
		last_render_usec = 0
		render_warmup = 60
		var world := preload("res://scenes/Game.tscn").instantiate()
		add_child(world)
		var player := world.get_node("Entities/Player") as PlayerCharacter
		var pilot := player.get_node("AutoPilot") as AutoBattle
		var map_kills := kills
		var map_pickups := pickups
		GameState.set_auto_battle(true)
		var walked := 0.0
		var previous := player.global_position
		var roam_frames := 0
		for tick in range(seconds_per_map * 60):
			await get_tree().physics_frame
			walked += player.global_position.distance_to(previous)
			previous = player.global_position
			if pilot.current_state() == AutoBattle.State.ROAM:
				roam_frames += 1
			assert(not player.is_dead and GameState.auto_battle_on, "长跑应持续决策，不因死亡或停战静默变成空载")
			if (tick + 1) % 3600 == 0:
				print("[PERF] ", JSON.stringify({"map":map_id, "game_seconds":(tick + 1) / 60, "kills":kills - map_kills, "pickups":pickups - map_pickups, "walked_px":roundi(walked), "roam_frames":roam_frames, "nodes":get_tree().get_node_count(), "memory":Performance.get_monitor(Performance.MEMORY_STATIC)}))
		assert(walked > 100.0 and kills > map_kills, "每张图应实际移动和战斗")
		if not render_frames.is_empty():
			render_frames.sort()
			print("[PERF] render ", map_id, " frame_ms_p50_p95_p99_max=", [render_frames[int(render_frames.size() * 0.5)], render_frames[int(render_frames.size() * 0.95)], render_frames[int(render_frames.size() * 0.99)], render_frames[-1]], " draw_calls=", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), " video_memory=", Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))
			get_viewport().get_texture().get_image().save_png("/tmp/auto_roam_" + map_id + ".png")
		GameState.set_auto_battle(false)
		world.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
		assert(get_tree().get_node_count() <= baseline_nodes + 8, "退出地图应释放活动实体和分帧规划")
		print("[PERF] map_cleanup ", map_id, " nodes=", get_tree().get_node_count())
	print("[PERF] wall_seconds=", (Time.get_ticks_usec() - started) / 1000000.0, " game_seconds=", seconds_per_map * 3, " kills=", kills, " pickups=", pickups)
	print("[AutoRoamSoakTest] 全部通过 ✅")
	get_tree().quit()

## 仅真实窗口采集完成绘制的墙钟间隔；每张地图跳过最初60帧加载预热。
func _on_render() -> void:
	var tick := Time.get_ticks_usec()
	if last_render_usec > 0:
		if render_warmup > 0:
			render_warmup -= 1
		else:
			render_frames.append((tick - last_render_usec) / 1000.0)
	last_render_usec = tick
