extends Node
## A visible cave monster across a detour must remain selected while the player follows the route.

var failures: Array[String] = []

func _ready() -> void:
	GameState.reset_to_defaults()
	GameState.current_map = "corruption_source"
	GameState.save_pos = Iso.grid_to_world(Vector2i(8, 25))
	GameState.has_save_pos = true
	var main := preload("res://scenes/Main.tscn").instantiate()
	add_child(main)
	var world := main.get_node("Game")
	world.get_node("Spawner").set_process(false)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	await get_tree().process_frame
	var player := world.get_node("Entities/Player") as PlayerCharacter
	var pilot := player.get_node("AutoPilot") as AutoBattle
	var monster: Monster = preload("res://scenes/entities/Monster.tscn").instantiate()
	monster.monster_id = "wolf_corrupted"
	monster.ai_enabled = false
	world.get_node("Entities").add_child(monster)
	monster.global_position = Iso.grid_to_world(Vector2i(22, 31))
	await get_tree().process_frame
	_check(world.visible_enemies().has(monster), "绕障目标处于可视范围")
	var start := player.global_position
	GameState.set_auto_battle(true)
	for _i in range(180):
		await get_tree().physics_frame
	_check(player.global_position.distance_to(start) > 80.0, "自动战斗沿洞穴路径推进")
	_check(pilot.current_target() == monster and pilot.blacklist_size() == 0,
		"绕路期间不误判目标卡住")
	print("[CaveAutoBattleTest] ", "全部通过 ✅" if failures.is_empty() else str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("[CaveAutoBattleTest] " + message)
