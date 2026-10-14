extends Node
## M4-9：可视区搜怪、无怪巡游、未受击定时恢复与打坐中断。

var _failures: Array[String] = []

func _ready() -> void:
	GameState.reset_to_defaults()
	# The camp centre is now a safe area; hostile targets there are deliberately invalid.
	GameState.current_map = "wild_trial"
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	for _i in range(8):
		await get_tree().process_frame
	var game: Node = main.get_node("Game")
	# 与 affix_shot / input_feedback_test / auto_control_acceptance 同一惯例：
	# 直接 queue_free 怪物不走 died 信号 ⇒ 刷新点「无死亡登记」，下一帧即在随机位置重生，
	# 随机新怪会与本测试的搜怪 / 巡游断言竞争（2026-10-13 实测偶发失败，失败项逐次不同）。
	# 关掉刷新进程，保证「只剩 chosen 一只怪」的局面确定。
	game.get_node("Spawner").set_process(false)
	var player := game.get_node("Entities/Player") as PlayerCharacter
	var pilot := player.get_node("AutoPilot") as AutoBattle
	var enemies := get_tree().get_nodes_in_group("enemies")
	_expect(not enemies.is_empty(), "测试地图应有怪物")
	if enemies.is_empty():
		_finish()
		return
	var chosen := enemies[0] as Node2D
	for i in range(1, enemies.size()):
		enemies[i].queue_free()
	var chosen_distance: float = await _place_visible_enemy(game, player, chosen)
	_expect(chosen_distance >= 160.0, "测试怪物应在当前画面较远处")
	GameState.set_auto_battle(true)
	for _i in range(30):
		await get_tree().physics_frame
	_expect(pilot.current_target() == chosen, "自动战斗应选中画面中远处的怪物")
	_expect(player.global_position.distance_to(chosen.global_position) < chosen_distance, "应向远处可见怪物移动")

	chosen.queue_free()
	await get_tree().process_frame
	for _i in range(35):
		await get_tree().physics_frame
	_expect(pilot.current_state() == AutoBattle.State.ROAM, "画面无怪后应进入巡游")
	var before := player.global_position
	for _i in range(50):
		await get_tree().physics_frame
	_expect(player.global_position.distance_to(before) > 20, "巡游应持续移动而非原地待机")
	var found: Monster = load("res://scenes/entities/Monster.tscn").instantiate()
	found.monster_id = "wolf_corrupted"
	found.ai_enabled = false
	game.get_node("Entities").add_child(found)
	var found_distance: float = await _place_visible_enemy(game, player, found)
	_expect(found_distance >= 160.0, "巡游后新怪应在当前画面中")
	for _i in range(30):
		await get_tree().physics_frame
	_expect(pilot.current_target() == found, "巡游途中发现可见怪物后应立即追击")
	player.set_physics_process(false)
	GameState.player.hp = GameState.max_hp() / 2
	GameState.player.mp = GameState.max_mp() / 2
	player._regen_elapsed = 2.9
	var hp_before_attack := int(GameState.player.hp)
	player.perform_attack(found)
	player._tick_regen(0.1)
	_expect(int(GameState.player.hp) > hp_before_attack,
		"主动攻击不应重置未受击恢复计时")
	found.queue_free()
	player.set_sitting(true)
	await get_tree().physics_frame
	_expect(pilot.current_state() == AutoBattle.State.RECOVER and player.auto_move == Vector2.ZERO,
		"打坐期间应暂停自动战斗并停止移动")
	player.set_sitting(false)

	GameState.set_auto_battle(false)
	player._regen_elapsed = 0.0
	GameState.player.hp = GameState.max_hp() / 2
	GameState.player.mp = GameState.max_mp() / 2
	var hp0 := int(GameState.player.hp)
	var mp0 := int(GameState.player.mp)
	player.auto_move = Vector2.RIGHT
	player.map_move_active = true
	player.manual_attack_active = true
	player._tick_regen(2.9)
	_expect(int(GameState.player.hp) == hp0 and int(GameState.player.mp) == mp0,
		"未受击时不足 3 秒不得提前恢复")
	player._tick_regen(0.1)
	_expect(int(GameState.player.hp) - hp0 == maxi(1, roundi(GameState.max_hp() * PlayerCharacter.IDLE_HP_RATE)),
		"走路与攻击中仍应每 3 秒恢复一次 HP")
	_expect(int(GameState.player.mp) - mp0 == maxi(1, roundi(GameState.max_mp() * PlayerCharacter.IDLE_MP_RATE)),
		"走路与寻怪中仍应每 3 秒恢复一次 MP")
	player.auto_move = Vector2.ZERO
	player.map_move_active = false
	player.manual_attack_active = false
	player._regen_elapsed = 2.5
	player._invuln = 0.0
	player.apply_damage(1)
	hp0 = int(GameState.player.hp)
	mp0 = int(GameState.player.mp)
	player._tick_regen(2.9)
	_expect(int(GameState.player.hp) == hp0 and int(GameState.player.mp) == mp0,
		"实际受击应重置 3 秒恢复计时")
	player._tick_regen(0.1)
	_expect(int(GameState.player.hp) > hp0 and int(GameState.player.mp) > mp0,
		"受击后满 3 秒恢复血蓝")

	player.set_sitting(true)
	_expect(player.is_sitting and player.auto_move == Vector2.ZERO, "打坐应停止移动")
	_expect(main.get_node("UI/Hud").get_node("AutoLabel").text.contains("打坐"), "HUD 应显示打坐状态")
	player._regen_elapsed = 0.0
	hp0 = int(GameState.player.hp)
	mp0 = int(GameState.player.mp)
	player._tick_regen(2.9)
	_expect(int(GameState.player.hp) == hp0 and int(GameState.player.mp) == mp0,
		"打坐不足 3 秒不得提前恢复")
	player._tick_regen(0.1)
	_expect(int(GameState.player.hp) - hp0 == maxi(1, roundi(GameState.max_hp() * PlayerCharacter.SIT_HP_RATE)),
		"打坐每 3 秒按最大值恢复 3% HP")
	_expect(int(GameState.player.mp) - mp0 == maxi(1, roundi(GameState.max_mp() * PlayerCharacter.SIT_MP_RATE)),
		"打坐每 3 秒按最大值恢复 5% MP")
	get_tree().paused = true
	hp0 = int(GameState.player.hp)
	mp0 = int(GameState.player.mp)
	player._tick_regen(3.0)
	_expect(int(GameState.player.hp) == hp0 and int(GameState.player.mp) == mp0, "暂停不能产生恢复")
	get_tree().paused = false
	player._map_background = true
	player._tick_regen(3.0)
	_expect(int(GameState.player.hp) > hp0 and int(GameState.player.mp) > mp0,
		"窗口失焦但未受击时恢复仍应继续")
	player._map_background = false
	player._invuln = 0.0
	player.apply_damage(1)
	_expect(not player.is_sitting, "实际受击应立即起身")
	player.set_sitting(true)
	player.request_map_move(player.global_position + Vector2(100, 0))
	_expect(not player.is_sitting, "手动地图移动应起身")
	var sit_key := InputEventKey.new()
	sit_key.physical_keycode = KEY_X
	sit_key.pressed = true
	game._unhandled_input(sit_key)
	_expect(player.is_sitting, "X 键应进入打坐")
	_finish()

func _place_visible_enemy(game: Node, player: PlayerCharacter, enemy: Node2D) -> float:
	var ground := game.get_node("Ground") as IsoGround
	for offset in [Vector2(220, 0), Vector2(-220, 0), Vector2(0, 220), Vector2(0, -220),
			Vector2(180, 120), Vector2(-180, -120)]:
		enemy.global_position = ground.clamp_to_map(player.global_position + offset)
		await get_tree().process_frame
		var distance := player.global_position.distance_to(enemy.global_position)
		if distance >= 160.0 and game.visible_enemies().has(enemy):
			return distance
	return -1.0

func _expect(ok: bool, reason: String) -> void:
	if not ok:
		_failures.append(reason)

func _finish() -> void:
	for reason in _failures:
		print("[M4-9] ❌ ", reason)
	if _failures.is_empty():
		print("[M4-9] 全部断言通过 ✅")
	get_tree().quit(0 if _failures.is_empty() else 1)
