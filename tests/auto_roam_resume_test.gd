extends Node
## 真实AutoBattle入口回归：战斗/拾取后接续游标，长追击重接、手动与旅行清理旧规划。
var failures: Array[String] = []

## 失败不能因异步提前退出而被当成通过。
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

## 冻结场景输入与物理，直接驱动同一个决策入口，保留真实玩家、怪物与掉落接口。
func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children():
		freeze(child)

## 给固定路线设置下一点，避免地图采样和随机刷新影响接续断言。
func route(pilot: AutoBattle, origin: Vector2) -> void:
	pilot._roam_points.assign([origin - Vector2(100, 0), origin + Vector2(200, 0), origin + Vector2(1100, 0), origin + Vector2(1400, 0)])
	pilot._roam_primary_count = 4
	pilot._roam_index = 1
	pilot._roam_resume_pending = false

## 验证真实选怪不会清游标，实际拾取决策同样记住进度；手动/切图显式失效。
func _ready() -> void:
	GameState.reset_to_defaults()
	GameState.current_map = "wild_trial"
	var main := preload("res://scenes/Main.tscn").instantiate()
	add_child(main)
	freeze(main)
	var world := main.get_node("Game")
	var player := world.get_node("Entities/Player") as PlayerCharacter
	var pilot := player.get_node("AutoPilot") as AutoBattle
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	await get_tree().process_frame
	var origin := player.global_position
	route(pilot, origin)
	var enemy := preload("res://scenes/entities/Monster.tscn").instantiate() as Monster
	enemy.monster_id = "training_dummy"
	enemy.ai_enabled = false
	world.add_child(enemy)
	enemy.global_position = origin + Vector2(80, 0)
	enemy.set_physics_process(false)
	pilot._tick(0.0)
	check(pilot.current_target() == enemy and pilot._roam_index == 1 and pilot._roam_resume_pending, "遇怪保留巡游下一点")
	player.global_position = origin + Vector2(90, 0)
	pilot._resume_roam()
	check(pilot._roam_index == 1 and not pilot._roam_resume_pending, "短追击不倒退到最近旧点")
	enemy.queue_free()
	await get_tree().process_frame
	pilot._target = null
	route(pilot, origin)
	pilot._interrupt_roam()
	player.global_position = origin + Vector2(1180, 0)
	pilot._resume_roam()
	check(pilot._roam_index == 2, "长追击选择合理前向点，不远距离回头")
	route(pilot, origin)
	player.global_position = origin
	var item := preload("res://scenes/entities/GroundItem.tscn").instantiate() as GroundItem
	item.item = {"kind":"potion", "itemId":"potion_hp_small", "count":1}
	world.add_child(item)
	item.global_position = origin + Vector2(170, 0)
	check(pilot._tick_loot() and pilot._roam_resume_pending and pilot._roam_index == 1, "顺路拾取也保留游标")
	item.queue_free()
	await get_tree().process_frame
	pilot.begin_manual_override()
	check(pilot._roam_index == -1 and not pilot._roam_resume_pending, "手动接管清除旧接续")
	pilot._build_roam_points()
	check(pilot._roam_builder != null, "存在分帧工作状态")
	pilot.reset_after_travel()
	check(pilot._roam_builder == null and pilot._roam_points.is_empty() and pilot._roam_index == -1, "旅行取消旧地图规划")
	print("[AutoRoamResumeTest] ", "全部通过 ✅" if failures.is_empty() else str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
