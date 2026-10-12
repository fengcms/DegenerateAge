extends Node
## M3 T08/T09：真实世界状态机、冻结位移模拟不可达、Viewport 点击接管。

var _failures: Array[String] = []

func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)
		print("[AutoControl] 失败：", message)

func _click(point: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = pressed
		get_viewport().push_input(event, true)

func _spawn_dummy(world: Node, point: Vector2) -> Monster:
	var monster := (load("res://scenes/entities/Monster.tscn") as PackedScene).instantiate() as Monster
	monster.monster_id = "training_dummy"
	monster.ai_enabled = false
	world.add_child(monster)
	monster.global_position = point
	monster.max_hp = 1000
	monster.hp = 1000
	monster.set_physics_process(false)
	return monster

func _ready() -> void:
	GameState.reset_to_defaults()
	var main := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(main)
	await get_tree().process_frame
	var world: Node2D = main.get_node("Game")
	var player: PlayerCharacter = world.get_node("Entities/Player")
	var pilot: AutoBattle = player.get_node("AutoPilot")
	world.get_node("Spawner").set_process(false)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	await get_tree().process_frame
	var start := player.global_position
	var near := _spawn_dummy(world, start + Vector2(170, 0))
	var alternate := _spawn_dummy(world, start + Vector2(300, 0))
	GameState.player.attack = 1
	GameState.player.hp = GameState.max_hp()

	# T08：冻结玩家位移模拟路径受阻，真实物理帧驱动三次不推进判据。
	player.set_physics_process(false)
	GameState.set_auto_battle(true)
	var selected_near := false
	for _i in range(150):
		await get_tree().physics_frame
		selected_near = selected_near or pilot.current_target() == near
		if pilot.blacklist_size() > 0:
			break
	_check(selected_near, "T08 自动战斗应先选最近目标")
	_check(pilot.blacklist_size() == 1 and pilot._is_blacklisted(near), "T08 连续不推进应将不可达目标拉黑")
	_check(pilot.current_state() == AutoBattle.State.BLOCKED and player.auto_move == Vector2.ZERO,
		"T08 拉黑后应立即停止旧移动指令")
	player.set_physics_process(true)
	var selected_alternate := false
	for _i in range(120):
		await get_tree().physics_frame
		if pilot.current_target() == alternate:
			selected_alternate = true
			break
	_check(selected_alternate, "T08 受阻停顿后应改选未拉黑目标")
	_check(pilot._is_blacklisted(near), "T08 改选期间旧目标仍应在短期黑名单")
	var distance_before := player.global_position.distance_to(alternate.global_position)
	for _i in range(20):
		await get_tree().physics_frame
	_check(player.global_position.distance_to(alternate.global_position) < distance_before,
		"T08 改选后应实际接近新目标")

	# T09：地图真实点击接管，移动结束后 3 秒恢复自动决策。
	GameState.set_auto_battle(false)
	await get_tree().physics_frame
	player.global_position = start
	await get_tree().process_frame
	GameState.set_auto_battle(true)
	for _i in range(10):
		await get_tree().physics_frame
	_check(pilot.current_target() == near, "T09 接管前自动战斗应已选目标")
	var destination := player.global_position + Vector2(0, 110)
	_click(world.get_canvas_transform() * destination)
	_check(player.map_move_active and pilot.current_state() == AutoBattle.State.MANUAL_OVERRIDE,
		"T09 地图点击应立即接管自动战斗")
	_check(pilot.current_target() == null and player.auto_move == Vector2.ZERO,
		"T09 手动接管应清除旧自动目标和移动指令")
	var arrived := false
	for _i in range(120):
		await get_tree().physics_frame
		if not player.map_move_active:
			arrived = true
			break
		_check(pilot.current_state() == AutoBattle.State.MANUAL_OVERRIDE,
			"T09 点击行走期间自动战斗不得抢回控制")
	_check(arrived and player.global_position.distance_to(destination) <= AutoBattle.LOOT_ARRIVE_EPS + 2.0,
		"T09 应走到点击位置附近")
	var timer_moved := false
	for _i in range(85):
		await get_tree().physics_frame
		if pilot.current_phase().contains("2 秒"):
			timer_moved = true
			break
	_check(timer_moved, "T09 停止操作后倒计时应从 3 秒递减")
	var resumed := false
	for _i in range(210):
		await get_tree().physics_frame
		if pilot.current_state() != AutoBattle.State.MANUAL_OVERRIDE and pilot.current_target() != null:
			resumed = true
			break
	_check(resumed and GameState.auto_battle_on, "T09 3 秒后应恢复自动搜怪")

	# 攻击目标的鼠标点击同样属于手动命令。
	_click(near.get_global_transform_with_canvas().origin + Vector2(0, -8))
	_check(player.manual_attack_active and player.locked_target == near,
		"T09 点击怪物应下达手动追击命令")
	_check(pilot.current_state() == AutoBattle.State.MANUAL_OVERRIDE and pilot.current_target() == null,
		"T09 点击怪物应立即取消自动决策")

	GameState.set_auto_battle(false)
	main.queue_free()
	await get_tree().process_frame
	GameState.reset_to_defaults()
	print("[AutoControl] ", "全部通过 ✅" if _failures.is_empty() else str(_failures))
	get_tree().quit(0 if _failures.is_empty() else 1)
