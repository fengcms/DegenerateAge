extends Node
## M4-9：可视区搜怪、无怪巡游、百分比恢复与打坐中断。

var _failures: Array[String] = []

func _ready() -> void:
	GameState.reset_to_defaults()
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	for _i in range(8):
		await get_tree().process_frame
	var game: Node = main.get_node("Game")
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
	chosen.global_position = player.global_position + Vector2(420, 0)
	await get_tree().process_frame
	_expect(game.visible_enemies().has(chosen), "测试怪物应在当前画面中")
	GameState.set_auto_battle(true)
	for _i in range(30):
		await get_tree().physics_frame
	_expect(pilot.current_target() == chosen, "自动战斗应选中画面中远处的怪物")
	_expect(player.global_position.distance_to(chosen.global_position) < 420, "应向远处可见怪物移动")

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
	found.global_position = player.global_position + Vector2(320, 0)
	await get_tree().process_frame
	for _i in range(30):
		await get_tree().physics_frame
	_expect(pilot.current_target() == found, "巡游途中发现可见怪物后应立即追击")
	found.queue_free()
	player.set_sitting(true)
	await get_tree().physics_frame
	_expect(pilot.current_state() == AutoBattle.State.RECOVER and player.auto_move == Vector2.ZERO,
		"打坐期间应暂停自动战斗并停止移动")
	player.set_sitting(false)

	GameState.set_auto_battle(false)
	player._combat_cooldown = 0.0
	player._hp_regen_rest = 0.0
	player._mp_regen_rest = 0.0
	GameState.player.hp = GameState.max_hp() / 2
	GameState.player.mp = GameState.max_mp() / 2
	var hp0 := int(GameState.player.hp)
	var mp0 := int(GameState.player.mp)
	player._tick_regen(2.0)
	_expect(int(GameState.player.hp) - hp0 == int(floorf(GameState.max_hp() * 0.02)), "脱战 HP 应按最大值每秒恢复 1%")
	_expect(int(GameState.player.mp) - mp0 == int(floorf(GameState.max_mp() * 0.04)), "脱战 MP 应按最大值每秒恢复 2%")
	player._mark_combat()
	hp0 = int(GameState.player.hp)
	mp0 = int(GameState.player.mp)
	player._tick_regen(5.0)
	_expect(int(GameState.player.hp) == hp0 and int(GameState.player.mp) == mp0, "战斗结束前 5 秒不应恢复")
	player._tick_regen(1.0)
	_expect(int(GameState.player.hp) > hp0, "脱战 5 秒后应恢复")

	player.set_sitting(true)
	_expect(player.is_sitting and player.auto_move == Vector2.ZERO, "打坐应停止移动")
	_expect(main.get_node("UI/Hud").get_node("AutoLabel").text.contains("打坐"), "HUD 应显示打坐状态")
	player._combat_cooldown = 0.0
	player._hp_regen_rest = 0.0
	player._mp_regen_rest = 0.0
	hp0 = int(GameState.player.hp)
	mp0 = int(GameState.player.mp)
	player._tick_regen(2.0)
	_expect(int(GameState.player.hp) - hp0 == int(floorf(GameState.max_hp() * 0.06)), "打坐 HP 应按最大值每秒恢复 3%")
	_expect(int(GameState.player.mp) - mp0 == int(floorf(GameState.max_mp() * 0.10)), "打坐 MP 应按最大值每秒恢复 5%")
	get_tree().paused = true
	hp0 = int(GameState.player.hp)
	mp0 = int(GameState.player.mp)
	player._tick_regen(2.0)
	_expect(int(GameState.player.hp) == hp0 and int(GameState.player.mp) == mp0, "暂停不能产生恢复")
	get_tree().paused = false
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

func _expect(ok: bool, reason: String) -> void:
	if not ok:
		_failures.append(reason)

func _finish() -> void:
	for reason in _failures:
		print("[M4-9] ❌ ", reason)
	if _failures.is_empty():
		print("[M4-9] 全部断言通过 ✅")
	get_tree().quit(0 if _failures.is_empty() else 1)
