extends Node
## 百首禁域真实地图的18席混合Boss回归及可选窗口采样：保留刷新身份、地形和技能，固定无敌玩家。
## 不模拟击杀效率或长期挂机；无头不证明GPU性能，窗口版确认实际绘制后记录帧间隔。
var failures: Array[String] = []
var rendered := 0

## 记录真实绘制回调，避免遮挡窗口导致采样没有渲染工作。
func _drawn() -> void:
	rendered += 1

## 装配正式地图/刷新器，将现有18席集中到玩家附近测试拥挤，结束后释放整个世界。
func _ready() -> void:
	seed(20261105)
	GameState.reset_to_defaults()
	SaveManager.active_slot = -1
	SaveManager.autosave_enabled = false
	GameState.current_map = "c7_boss_field"
	GameState.player.level = 100
	GameState.save_pos = Iso.grid_to_world(Vector2i(80, 60))
	GameState.has_save_pos = true
	var windowed := DisplayServer.get_name() != "headless"
	if windowed:
		get_window().size = Vector2i(1280, 800)
		RenderingServer.frame_post_draw.connect(_drawn)
	var world := load("res://scenes/Game.tscn").instantiate() as Node2D
	add_child(world)
	var player := world.get_node("Entities/Player") as PlayerCharacter
	player.set_physics_process(false)
	player.get_node("AutoPilot").set_physics_process(false)
	player._invuln = 100000.0
	var ground := world.get_node("Ground") as IsoGround
	var spawner := world.get_node("Spawner") as MonsterSpawner
	spawner.set_process(false)
	# 满预算压力夹具：关闭玩家距离门槛，仍沿用真实100席、18上限与实例数值。
	# 初次进图只激活附近席位，不能把不足18只的样本当作满预算验收。
	for point in spawner._points:
		var entry = point.get("entry")
		if is_instance_valid(entry):
			entry.queue_free()
		point.entry = null
	await get_tree().process_frame
	spawner.setup(ground, null)
	for point in spawner._points:
		spawner._spawn(point)
	var bosses: Array[Monster] = []
	var ids: Dictionary = {}
	for node in get_tree().get_nodes_in_group("enemies"):
		var boss := node as Monster
		if boss != null:
			bosses.append(boss)
			ids[boss.monster_id] = true
	_check(bosses.size() == 18 and spawner.point_count() == 100, "真实刷新100席、18只存活")
	_check(ids.size() == 10, "必须覆盖百首禁域全部10种模板")
	var home := player.global_position
	for i in range(bosses.size()):
		var boss := bosses[i]
		boss.global_position = ground.clamp_to_map(home + Vector2.from_angle(i * 2.399963) * (100.0 + (i % 5) * 28.0))
		boss.spawn_position = boss.global_position
		boss._enter(Monster.State.CHASE)
	var frame_ms: Array[float] = []
	var last := Time.get_ticks_usec()
	var tail_min := INF
	var warning_drift := 0.0
	var locks_checked := 0
	for frame in range(1200):
		var locked_positions: Dictionary = {}
		for boss in bosses:
			if boss._stomp_pending or not boss._chapter_boss_warn.is_empty() or (boss.boss_action != null and boss.boss_action.is_busy()):
				locked_positions[boss] = boss.position
		await get_tree().physics_frame
		for boss in locked_positions:
			warning_drift = maxf(warning_drift, boss.position.distance_to(locked_positions[boss]))
			locks_checked += 1
		if frame >= 900:
			for i in range(bosses.size()):
				for j in range(i + 1, bosses.size()):
					tail_min = minf(tail_min, Iso.ground_distance(bosses[i].position, bosses[j].position))
		if windowed:
			RenderingServer.force_draw(false)
		var now := Time.get_ticks_usec()
		if frame >= 300:
			frame_ms.append((now - last) / 1000.0)
		last = now
	frame_ms.sort()
	_check(tail_min >= 64.0, "末5秒最小地面间距须≥64，实际%.2f" % tail_min)
	_check(warning_drift < 0.01 and locks_checked > 100, "技能接管期间不得漂移，实际%.3f" % warning_drift)
	_check(spawner.alive_count() == 18, "站位调整不改变存活席位数")
	for point in spawner._points:
		_check(is_equal_approx(float(point.respawn_time), 600.0), "重生时间保持600秒")
	if windowed:
		_check(rendered >= 1200, "窗口采样每步必须实际绘制")
		get_viewport().get_texture().get_image().save_png("/tmp/da-boss-crowd-map.png")
	print("[PERF] boss_crowd_map ", JSON.stringify({"rendered":rendered,"samples":frame_ms.size(),"p50_ms":frame_ms[int(frame_ms.size()*0.5)],"p95_ms":frame_ms[int(frame_ms.size()*0.95)],"p99_ms":frame_ms[int(frame_ms.size()*0.99)],"min_gap":tail_min,"warning_drift":warning_drift,"lock_samples":locks_checked,"nodes":get_tree().get_node_count()}))
	# 在采样后验证真实死亡、一次性奖励和600秒席位恢复，不污染性能样本。
	var point: Dictionary = spawner._points[0]
	var defeated := point.entry as Monster
	var death_position := defeated.global_position
	defeated.take_hit({"damage":999999999,"miss":false})
	var rewards := GameState.unclaimed_loot.duplicate(true)
	var player_after := GameState.player.duplicate(true)
	defeated._die()
	_check(GameState.unclaimed_loot == rewards and GameState.player == player_after, "重复死亡不得重复奖励")
	var key := GameState.spawn_key("c7_boss_field", String(point.monster_id), int(point.ordinal))
	var saved: Dictionary = GameState.spawn_respawn.get(key, {})
	_check(not saved.is_empty(), "移动后的Boss仍按稳定席位登记死亡")
	var ready_at := float(saved.get("readyAt", 0.0))
	_check(is_equal_approx(ready_at - GameState.world_time, 600.0), "真实死亡登记600秒重生")
	_check((point.position as Vector2).distance_to(death_position) < 0.01, "保留移动后原位墓碑规则")
	_check(not spawner._spawn(point), "未到期不能提前刷新")
	GameState.world_time = ready_at + 0.1
	_check(spawner._spawn(point), "到期仍可刷新原席位")
	_check(spawner.alive_count() == 18 and point.entry != defeated, "重生后恢复18席且实例更新")
	world.queue_free()
	await get_tree().process_frame
	_check(get_tree().get_nodes_in_group("enemies").is_empty(), "切离地图后无残留Boss节点")
	if failures.is_empty():
		print("[BossCrowdMapTest] PASS")
	get_tree().quit(0 if failures.is_empty() else 1)

## 汇总失败，保持原有验证条件不因性能采样结果改变。
func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("[BossCrowdMapTest] " + message)
