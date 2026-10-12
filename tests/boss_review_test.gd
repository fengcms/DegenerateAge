extends Node
var failures: Array[String] = []
var clears := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		print("[BossReview] 失败：", message)

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/degenerateage_boss_" + label + ".png")

func _ready() -> void:
	GameState.reset_to_defaults()
	GameState.current_map = "corruption_source"
	GameState.quest_states = {"Q005":{"state":"active", "progress":0}}
	EventBus.boss_first_clear.connect(func(_id: String) -> void: clears += 1)
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	_disable_input(main)
	await get_tree().process_frame
	var world: Node2D = main.get_node("Game")
	var player: PlayerCharacter = main.get_node("Game/Entities/Player")
	player.set_physics_process(false)
	player.get_node("AutoPilot").set_physics_process(false)
	world.get_node("Spawner").set_process(false)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	await get_tree().process_frame
	var spawner := MonsterSpawner.new()
	world.add_child(spawner)
	spawner.setup(world.get_node("Ground"), player)
	spawner.spawn_from_specs([{"monsterId":"boss_corrupted_beast", "level":10, "respawnTime":300, "tombstone":true, "ai":false}])
	spawner.set_process(false)
	var boss: Monster = spawner._points[0].entry
	boss.global_position = player.global_position + Vector2(60, 0)
	boss.set_physics_process(false)
	player.select_target(boss)
	var hp := int(GameState.player.hp)
	boss.hp = 1800
	boss._update_boss(0)
	check(boss.boss_phase == 0 and not boss._stomp_pending, "60%边界保持第一阶段")
	boss.hp = 1799
	boss.ai_enabled = true
	boss._physics_process(0)
	check(boss.boss_phase == 1 and boss._stomp_pending and GameState.player.hp == hp, "低于60%先预警不扣血")
	await capture("warning")
	boss._update_boss(0.79)
	check(GameState.player.hp == hp and boss._stomp_pending, "0.8秒前不造成伤害")
	boss._update_boss(0.02)
	check(GameState.player.hp < hp and not boss._stomp_pending, "预警结束圈内结算")
	# 离开固定预警圈可躲避；自动战斗开关不改变预警时长。
	player._invuln = 0
	hp = int(GameState.player.hp)
	GameState.set_auto_battle(true)
	boss._stomp_cooldown = 0
	boss._update_boss(0)
	check(boss._stomp_pending and is_equal_approx(boss._stomp_remaining, 0.8), "自动模式仍有完整预警")
	player.global_position += Vector2(-200, 0)
	boss._update_boss(0.81)
	check(GameState.player.hp == hp, "离开预警范围不受伤")
	GameState.set_auto_battle(false)
	boss.hp = 900
	boss._update_boss(0)
	check(not boss._boss_enraged, "30%边界尚未狂暴")
	boss.hp = 899
	boss._update_boss(0)
	await get_tree().process_frame
	check(boss.boss_phase == 2 and boss._boss_enraged and is_equal_approx(boss.attack_interval, 1.4 / 1.3), "狂暴攻速生效")
	check(spawner.get_child_count() == 3, "狂暴召唤两只")
	boss._update_boss(0)
	await get_tree().process_frame
	check(spawner.get_child_count() == 3, "狂暴不重复召唤")
	for child in spawner.get_children():
		if child is Monster:
			child.set_physics_process(false)
	await capture("enraged")
	boss.take_hit({"damage": 99999, "miss": false})
	boss._die()
	check(clears == 1 and GameState.first_clear.get("boss_corrupted_beast", false) and GameState.unlocks.get("chapter2", false), "首次死亡仅结算一次首通解锁")
	check(Quest.state_of("Q005") == Quest.STATE_COMPLETED, "击杀推进Q005")
	var marker: BossTombstone = spawner._points[0].marker
	check(is_instance_valid(marker) and marker.remaining == 300, "死亡创建300秒墓碑")
	await get_tree().create_timer(0.4).timeout
	await capture("tombstone")
	spawner._process(299)
	check(spawner.alive_count() == 0 and marker.remaining == 1, "倒计时未结束不刷新")
	spawner._process(1)
	var second: Monster = spawner._points[0].entry
	check(is_instance_valid(second) and second != boss and spawner._points[0].marker == null, "到期刷新并移除墓碑")
	second.set_physics_process(false)
	second._die()
	check(clears == 1, "二次击杀不重复首通")
	check(SaveManager.save_slot(3, true), "首杀写档")
	var stored := SaveManager.read_slot(3)
	GameState.first_clear.clear()
	GameState.unlocks.clear()
	SaveManager.apply_to_game_state(stored.data)
	check(GameState.first_clear.get("boss_corrupted_beast", false) and GameState.unlocks.get("chapter2", false), "首杀和解锁重载保留")
	SaveManager.delete_slot(3)
	var ref: WeakRef = weakref(spawner)
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	check(ref.get_ref() == null, "世界释放清理刷新点与墓碑")
	GameState.reset_to_defaults()
	print("[BossReview] ", "全部通过 ✅" if failures.is_empty() else str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)

func _disable_input(node: Node) -> void:
	node.set_process_input(false)
	node.set_process_unhandled_input(false)
	node.set_process_unhandled_key_input(false)
	for child in node.get_children():
		_disable_input(child)
