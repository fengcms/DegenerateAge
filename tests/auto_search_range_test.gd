extends Node
## 在真实世界和相机中验证屏外自动选怪，保持Tab范围、迷雾、Boss与黑名单规则。
var failures: Array[String] = []

## 聚合检查，任何失败均以非零退出，不依赖固定运行帧数。
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

## 固定怪物行为，避免随机刷新干扰范围断言。
func spawn(world: Node, position: Vector2, id: String = "training_dummy") -> Monster:
	var enemy := preload("res://scenes/entities/Monster.tscn").instantiate() as Monster
	enemy.monster_id = id
	enemy.ai_enabled = false
	world.add_child(enemy)
	enemy.global_position = position
	enemy.set_physics_process(false)
	return enemy

## 冻结真实世界，仅直接调用搜索入口，测试数据由隔离运行器承载。
func _ready() -> void:
	GameState.reset_to_defaults()
	GameState.current_map = "wild_trial"
	var main := preload("res://scenes/Main.tscn").instantiate()
	add_child(main)
	var world := main.get_node("Game")
	world.set_process(false)
	world.get_node("Spawner").set_process(false)
	var player := world.get_node("Entities/Player") as PlayerCharacter
	var pilot := player.get_node("AutoPilot") as AutoBattle
	player.set_physics_process(false)
	pilot.set_physics_process(false)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	await get_tree().process_frame
	player.global_position = Iso.grid_to_world(Vector2i(70, 45))
	var camera := player.get_node("Camera2D") as Camera2D
	camera.position_smoothing_enabled = false
	camera.zoom = Vector2(2, 2)
	camera.reset_smoothing()
	camera.force_update_scroll()
	var enemy := spawn(world, player.global_position + Vector2(600, 0))
	check(not world.visible_enemies().has(enemy), "600像素样本确实在屏外")
	GameState.explored_maps.clear()
	check(pilot._find_target() == null, "不追逐未探索屏外怪")
	Fog.reveal(GameState.current_map, Vector2i(Iso.world_to_grid(enemy.global_position).round()))
	check(pilot._find_target() == enemy, "已探索屏外怪可自动发现")
	check(not world.visible_enemies().has(enemy), "Tab可视列表未扩展")
	pilot._blacklist[enemy.get_instance_id()] = 3.0
	check(pilot._find_target() == null, "屏外黑名单仍生效")
	pilot._blacklist.clear()
	enemy.position = player.global_position + Vector2(761, 0)
	Fog.reveal(GameState.current_map, Vector2i(Iso.world_to_grid(enemy.global_position).round()))
	check(pilot._find_target() == null, "屏外范围不超过760像素")
	camera.zoom = Vector2(0.5, 0.5)
	camera.force_update_scroll()
	check(world.visible_enemies().has(enemy) and pilot._find_target() == enemy, "原可视远目标不被760裁掉")
	camera.zoom = Vector2(2, 2)
	camera.force_update_scroll()
	enemy.queue_free()
	await get_tree().process_frame
	var boss := spawn(world, player.global_position + Vector2(600, 0), "boss_corrupted_beast")
	GameState.settings.allowBoss = false
	check(pilot._find_target() == null, "屏外Boss受开关约束")
	GameState.settings.allowBoss = true
	check(pilot._find_target() == boss, "允许Boss后能发现")
	boss.hide()
	check(pilot._find_target() == null, "隐藏节点不参与搜索")
	boss.queue_free()
	await get_tree().process_frame
	print("[AutoSearchRangeTest] ", "全部通过 ✅" if failures.is_empty() else str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
