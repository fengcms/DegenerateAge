extends Node
## 使用真实 Main 和 Viewport 输入路由验证试玩反馈；独立 tests 存档闸门。
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		print("[InputFeedback] 失败：", message)

func key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.keycode = code
		event.pressed = pressed
		get_viewport().push_input(event, true)

func click(point: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = pressed
		get_viewport().push_input(event, true)

func _ready() -> void:
	GameState.reset_to_defaults()
	# 交互回归需要可攻击的近距离怪；营地出生点位于免战区内。
	GameState.current_map = "wild_trial"
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var world: Node2D = main.get_node("Game")
	var player: PlayerCharacter = main.get_node("Game/Entities/Player")
	var pilot: AutoBattle = player.get_node("AutoPilot")
	var hud: Control = main.get_node("UI/Hud")
	world.get_node("Spawner").set_process(false)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	await get_tree().process_frame
	var enemies: Array[Monster] = []
	for offset in [Vector2(130, 0), Vector2(260, 0), Vector2(2000, 0)]:
		var enemy := (load("res://scenes/entities/Monster.tscn") as PackedScene).instantiate() as Monster
		enemy.monster_id = "training_dummy"
		world.add_child(enemy)
		enemy.global_position = player.global_position + offset
		enemy.max_hp = 1000
		enemy.hp = 1000
		enemy.set_physics_process(false)
		enemies.append(enemy)
	await get_tree().create_timer(0.1).timeout
	check(not hud.get_node("TargetPanel").visible, "无目标时整体隐藏")
	key(KEY_TAB)
	check(player.locked_target == enemies[0] and enemies[0].selected, "Tab 首选最近可见目标")
	check(hud.get_node("TargetPanel").visible, "选中显示目标区")
	key(KEY_TAB)
	check(player.locked_target == enemies[1] and not enemies[0].selected, "Tab 切换并清除旧高亮")
	key(KEY_TAB)
	check(player.locked_target == enemies[0], "Tab 循环不选屏外怪")
	check(not player.try_auto_attack(enemies[1]), "超距离不能直接扣血")
	# 无锁定目标时按「可见范围」选最近者（屏外 2000px 不参选）；显式锁定优先，
	# 但锁定目标进黑名单后回退最近可见。
	# （M4-9 起搜怪以 visible_enemies 为准，旧锚点 _anchor 已移除 ——
	#  2026-10-13 M5-7 回归时重写本节，原锚点范围断言随 API 废止。）
	player.select_target(enemies[0], false)
	check(pilot._find_target() == enemies[0], "无锁定应选最近可见目标")
	player.select_target(enemies[1])
	check(pilot._find_target() == enemies[1], "用户锁定目标优先")
	pilot._blacklist[enemies[1].get_instance_id()] = 8.0
	check(pilot._find_target() == enemies[0], "锁定目标被拉黑后回退最近可见目标")
	pilot._blacklist.clear()
	player.select_target(null)
	# 空地移动使用世界投影，与相机位置无关。
	var start := player.global_position
	var point := start + Vector2(0, 130)
	click(world.get_canvas_transform() * point)
	await get_tree().create_timer(0.3).timeout
	check(player.global_position.distance_to(point) < start.distance_to(point), "主地图左击实际行走")
	Input.action_press("move_left")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("move_left")
	check(not player.map_move_active, "WASD 取消点击行走")
	# 点击指定的远目标，不应攻击更近的其他怪。
	click(enemies[1].get_global_transform_with_canvas().origin + Vector2(0, -8))
	check(player.manual_attack_active and player.locked_target == enemies[1], "点击怪物锁定并下达攻击")
	await get_tree().create_timer(2.2).timeout
	check(enemies[1].hp < 1000 and enemies[0].hp == 1000, "接近后持续普攻仅命中指定目标")
	check(player.global_position.distance_to(enemies[1].global_position) <= player.melee_range_px(), "攻击时实际抵达范围")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/degenerateage_input_selected.png")
	# 打开面板后，地图区域鼠标不能驱动人物。
	key(KEY_M)
	var stopped := player.global_position
	var hp_before := enemies[1].hp
	await get_tree().create_timer(0.3).timeout
	check(player.global_position.is_equal_approx(stopped) and enemies[1].hp == hp_before, "面板阻断追击及攻击")
	key(KEY_ESCAPE)
	Input.action_press("move_left")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("move_left")
	check(not player.manual_attack_active, "WASD 取消连续攻击")
	click(Vector2(100, 50))
	check(not player.map_move_active and not player.manual_attack_active, "点击 HUD 不穿透到世界")
	# Space 对 Tab 锁定目标同样可以超距接近。
	player.global_position = start
	player.select_target(enemies[1])
	Input.action_press("attack")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("attack")
	check(player.manual_attack_active, "Space 接近锁定目标")
	player.manual_attack_active = false
	# 目标直接释放也必须清除引用和 HUD。
	enemies[1].queue_free()
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame
	check(not is_instance_valid(player.locked_target) and not hud.get_node("TargetPanel").visible, "目标释放清理选中和 HUD")
	# 持续按键超过 3 秒不会恢复，松开后倒计时。
	GameState.set_auto_battle(true)
	pilot.set_physics_process(false)
	player.set_physics_process(false)
	Input.action_press("move_left")
	for i in range(5):
		pilot._physics_process(1.0)
	check(pilot._manual_t == 3.0 and pilot.current_state() == AutoBattle.State.MANUAL_OVERRIDE, "持续手动操作刷新三秒")
	Input.action_release("move_left")
	pilot._physics_process(1.0)
	check(pilot.current_phase().contains("2 秒") and String(hud.get_node("%AutoLabel").text).contains("2 秒"), "HUD 显示真实倒计时")
	pilot.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	pilot._physics_process(1.0)
	check(pilot._manual_t == 1.0, "窗口失焦后自动战斗的接管倒计时仍推进")
	pilot._manual_t = 0.0
	pilot._target = enemies[0]
	pilot._physics_process(0.35)
	check(pilot.current_state() in [AutoBattle.State.PATH_TO_TARGET, AutoBattle.State.ATTACK_TARGET],
		"窗口失焦后自动战斗仍追怪或攻击")
	pilot.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	GameState.set_auto_battle(false)
	for enemy in enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	await get_tree().process_frame
	key(KEY_TAB)
	check(player.locked_target == null and not hud.get_node("TargetPanel").visible, "空场景 Tab 无目标")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/degenerateage_input_empty.png")
	main.queue_free()
	await get_tree().process_frame
	GameState.reset_to_defaults()
	print("[InputFeedback] ", "全部通过 ✅" if failures.is_empty() else str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
