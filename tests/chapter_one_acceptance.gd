extends Node
## M3 整章出口：从营地真实车夫面板出行，经两次中转抵达 Boss，首杀入档。
## 测试驱动节点留在 root；将 Main 设为 current_scene，以便验证真实 reload_current_scene。

var _failures: Array[String] = []

func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)
		print("[ChapterOne] 失败：", message)

func _press_e() -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_E
		event.physical_keycode = KEY_E
		event.pressed = pressed
		get_viewport().push_input(event, true)

func _travel(to_map: String, expected_fee: int) -> bool:
	var old_main := get_tree().current_scene
	if old_main == null or not old_main.has_node("Game"):
		_check(false, "出行前缺少当前世界")
		return false
	var world: Node2D = old_main.get_node("Game")
	var player: PlayerCharacter = world.get_node("Entities/Player")
	var carter: Npc = null
	for child in world.get_node("Npcs").get_children():
		if child is Npc and child.role == "carter":
			carter = child
			break
	if carter == null:
		_check(false, "%s 缺少车夫" % GameState.current_map)
		return false
	player.global_position = carter.global_position + Vector2(40, 0)
	await get_tree().process_frame
	_check(world.nearest_npc() == carter, "%s 玩家应进入车夫交互范围" % GameState.current_map)
	_press_e()
	var panel: Control = old_main.get_node("UI/CarterPanel")
	_check(panel.visible and GameState.panel_open, "%s 按 E 应打开车夫面板" % GameState.current_map)
	var button: Button = null
	var rows: Array[Node] = panel._list.get_children()
	var destinations: Array = MapService.destinations()
	for i in range(mini(rows.size(), destinations.size())):
		var candidates: Array[Node] = rows[i].find_children("*", "Button", true, false)
		var destination: Dictionary = destinations[i]
		if String(destination.get("id", "")) == to_map and not candidates.is_empty():
			button = candidates[0]
			break
	if button == null:
		_check(false, "%s 车夫面板缺少 %s 线路" % [GameState.current_map, to_map])
		return false
	_check(not button.disabled and MapService.fee_to(to_map) == expected_fee,
		"%s→%s 线路应可用且费用为 %d" % [GameState.current_map, to_map, expected_fee])
	var old_weak: WeakRef = weakref(old_main)
	var gold_before := GameState.gold
	button.pressed.emit()
	for _i in range(30):
		await get_tree().process_frame
		if get_tree().current_scene != old_main:
			break
	var new_main := get_tree().current_scene
	_check(new_main != old_main and old_weak.get_ref() == null, "%s 应销毁旧世界并重载新世界" % to_map)
	_check(GameState.current_map == to_map and GameState.gold == gold_before - expected_fee,
		"车夫出行应到达 %s 并准确扣费" % to_map)
	if new_main == null or new_main == old_main:
		return false
	var new_world: Node2D = new_main.get_node("Game")
	_check(String(new_world.get_node("Ground").map_id) == to_map, "%s 地面应加载新地图" % to_map)
	_check(new_world.get_node("Spawner").point_count() > 0, "%s 应装配怪物点" % to_map)
	if to_map in ["ash_land", "corruption_source"]:
		var normal_count := 0
		var elite_count := 0
		var boss_count := 0
		for point in new_world.get_node("Spawner")._points:
			var template: Dictionary = DataLoader.get_entry("monsters", String(point.monster_id))
			match String(template.get("kind", "")):
				"normal": normal_count += 1
				"elite": elite_count += 1
				"boss": boss_count += 1
		var expected_normal := 6 if to_map == "ash_land" else 8
		var expected_elite := 2 if to_map == "ash_land" else 4
		_check(normal_count == expected_normal and elite_count == expected_elite and boss_count == (0 if to_map == "ash_land" else 1),
			"%s 应为 %d 普通 + %d 精英 + %d Boss，实际 %d/%d/%d" % [to_map, expected_normal, expected_elite,
				0 if to_map == "ash_land" else 1, normal_count, elite_count, boss_count])
	_check(not GameState.has_save_pos, "%s 到达落点应消费一次" % to_map)
	_check(not new_main.get_node("UI/CarterPanel").visible, "%s 重载后车夫面板应关闭" % to_map)
	return true

func _finish() -> void:
	var live_main := get_tree().current_scene
	get_tree().current_scene = self
	if live_main != self and is_instance_valid(live_main):
		live_main.queue_free()
	GameState.reset_to_defaults()
	print("[ChapterOne] ", "全部通过 ✅" if _failures.is_empty() else str(_failures))
	get_tree().quit(0 if _failures.is_empty() else 1)

func _ready() -> void:
	GameState.reset_to_defaults()
	GameState.menu_mode = "world"
	GameState.gold = 400  # 覆盖多次乘车与跨图直达费用。
	# 此场景验收车夫与 Boss；首次步行到访及存档门控由 SmokeTest 覆盖。
	GameState.mark_visited("ash_land")
	GameState.mark_visited("corruption_source")
	GameState.quest_states = {"Q005": {"state": "active", "progress": 0}}
	await get_tree().process_frame  # 避开根节点构造阶段的 add_child 锁。
	var main := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	await get_tree().process_frame
	_check(GameState.current_map == "camp", "第一章应从幸存者营地开始")
	if not await _travel("wild_trial", 0):
		_finish()
		return
	if not await _travel("ash_land", 50):
		_finish()
		return
	if not await _travel("camp", 70):
		_finish()
		return
	if not await _travel("corruption_source", 150):
		_finish()
		return
	if get_tree().current_scene != null and GameState.current_map == "corruption_source":
		var world: Node2D = get_tree().current_scene.get_node("Game")
		var player: PlayerCharacter = world.get_node("Entities/Player")
		var spawner: MonsterSpawner = world.get_node("Spawner")
		spawner.set_process(false)
		var boss: Monster = null
		for point in spawner._points:
			if String(point.monster_id) == "boss_corrupted_beast":
				boss = point.entry
				break
		_check(boss != null and boss.level == 10, "腐化源头应生成 L10 Boss")
		if boss != null:
			boss.set_physics_process(false)
			player.get_node("AutoPilot").set_physics_process(false)
			# 随机刷新点可能落在出行休整区边缘；首杀验收固定在战斗区域。
			boss.global_position = Iso.grid_to_world(Vector2i(25, 20))
			player.global_position = boss.global_position + Vector2(-48, 0)
			GameState.player.attack = 99999  # 压缩验收耗时，仍走玩家真实普攻入口。
			GameState.player.hp = GameState.max_hp()
			var clear_count := [0]
			EventBus.boss_first_clear.connect(func(_id: String) -> void: clear_count[0] += 1)
			_check(player.try_auto_attack(boss), "玩家应在近身后以真实普攻击杀 Boss")
			_check(boss.is_dead and clear_count[0] == 1, "Boss 首杀应恰好结算一次")
			_check(bool(GameState.first_clear.get("boss_corrupted_beast", false))
				and bool(GameState.unlocks.get("chapter2", false)), "首杀应写入标记并解锁第二章")
			_check(Quest.state_of("Q005") == Quest.STATE_COMPLETED, "首杀应推进已接取的 Q005")
			_check(spawner._points.back().marker is BossTombstone, "Boss 死亡应创建刷新墓碑")
			SaveManager.set_active_slot(3)
			_check(SaveManager.save_slot(3, true), "首杀进度应可写入存档")
			var saved := SaveManager.read_slot(3)
			_check(bool(saved.get("ok", false)), "首杀存档应可读取")
			if bool(saved.get("ok", false)):
				GameState.first_clear.clear()
				GameState.unlocks.clear()
				SaveManager.apply_to_game_state(saved.data)
				_check(bool(GameState.first_clear.get("boss_corrupted_beast", false))
					and bool(GameState.unlocks.get("chapter2", false)), "读档后首杀与解锁应保留")
			SaveManager.delete_slot(3)
	_finish()
