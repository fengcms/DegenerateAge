extends Node
## 自动战斗 / 自动拾取诊断与验收（开发期，M5 移除）。
##
## 无头运行（断言，不截图）：
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/AutoBattleProbe.tscn
## 开窗运行（同时截图到 /tmp/degenerateage_auto_*.png）：
##   /Applications/Godot.app/Contents/MacOS/Godot --path . res://tests/AutoBattleProbe.tscn
##
## 覆盖 3.14 的三条硬性异常规则（T08 不可达改选 / T10 背包满 / 4.6 手动接管）
## 与完整闭环：开 F → 锚点搜怪 → 接近 → 攻击 → 击杀 → 无怪时顺路拾取（G）。

var _failures: Array[String] = []
var _killed: int = 0

func _ready() -> void:
	GameState.reset_to_defaults()
	# 用 Main.tscn（含 UI 层 / HUD），便于同时验收 HUD 的自动状态指示
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	for _i in range(10):
		await get_tree().process_frame

	var game: Node = main.get_node("Game")
	var player: PlayerCharacter = game.get_node("Entities/Player")
	var pilot: AutoBattle = player.get_node("AutoPilot")
	_expect(pilot != null, "Player 下应挂有 AutoPilot")
	if pilot == null:
		_finish()
		return

	# ① 接近 + 攻击：低攻击保证怪不死，便于观察状态机
	GameState.player.attack = 5
	GameState.set_auto_battle(true)
	print("[Auto] 开 F：battle=%s pickup=%s" % [
		str(GameState.auto_battle_on), str(GameState.auto_pickup_on)])

	var seen_path := false
	var seen_attack := false
	for _i in range(150):                     # ≈2.5s
		await get_tree().physics_frame
		if pilot.current_state() == AutoBattle.State.PATH_TO_TARGET:
			seen_path = true
		if pilot.current_state() == AutoBattle.State.ATTACK_TARGET:
			seen_attack = true
	_expect(seen_path, "开 F 后应出现「接近目标」状态")
	_expect(seen_attack, "接近后应进入「攻击目标」状态")
	var tgt := pilot.current_target()
	print("[Auto] 阶段① 状态=%s 目标=%s 玩家位置=%s" % [
		AutoBattle.state_name(pilot.current_state()),
		("null" if tgt == null else String(tgt.get("display_name"))),
		str(player.global_position.round())])

	# ② 击杀：拉高攻击 → 必杀；断言经验 / 金币 / 背包有变化
	# 注意：max_hp 由攻击派生（4.3），直接改攻击会让「当前 HP / 上限」占比骤降，
	# 从而触发 3.14 的「危险血量」保护（正确行为）→ 必须同步补满 HP，
	# 等价于正常成长路径（升级按比例结转 / 穿装保持绝对值）。
	var xp0 := int(GameState.player.xp)
	GameState.player.attack = 999
	GameState.player.hp = GameState.max_hp()
	EventBus.monster_died.connect(_on_monster_died)
	for _i in range(180):                     # ≈3s
		await get_tree().physics_frame
	print("[Auto] 阶段② 击杀=%d 经验 %d→%d 金币=%d 背包=%d HP=%d/%d 状态=%s" % [
		_killed, xp0, int(GameState.player.xp), GameState.gold, GameState.inventory_used(),
		int(GameState.player.hp), GameState.max_hp(), AutoBattle.state_name(pilot.current_state())])
	_expect(_killed > 0, "自动战斗应至少击杀 1 只怪（3.14）")
	_expect(int(GameState.player.xp) != xp0 or GameState.gold > 0
		or GameState.inventory_used() > 0, "击杀后应有经验 / 金币 / 物品入账")
	_expect(not player.is_dead, "玩家不应在自动战斗中断死亡（HP=%d）" % int(GameState.player.hp))

	# ③ 危险血量保护（3.14）：HP ≤ 阈值 → 停寻怪（M1 无药水使用 → RECOVER）
	GameState.player.hp = maxi(1, int(round(float(GameState.max_hp()) * 0.2)))
	for _i in range(4):
		await get_tree().physics_frame
	print("[Auto] 阶段③ 低血（%d/%d）状态=%s" % [
		int(GameState.player.hp), GameState.max_hp(), AutoBattle.state_name(pilot.current_state())])
	_expect(pilot.current_state() == AutoBattle.State.RECOVER,
		"HP 低于阈值时应暂停自动战斗，实际 %s" % AutoBattle.state_name(pilot.current_state()))
	GameState.player.hp = GameState.max_hp()

	# ④ G：无怪时顺路拾取 5 格外的掉落物（超出 1.5 格自动拾取半径，必须靠自动走位）
	GameState.set_auto_battle(false)
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	# 清掉阶段②的残留掉落物，让路径干净（否则会先去捡附近的，时序不稳）
	for g in get_tree().get_nodes_in_group("ground_items"):
		g.queue_free()
	await get_tree().process_frame
	var loot_root: Node = game.get_node("LootRoot")
	var far: GroundItem = load("res://scenes/entities/GroundItem.tscn").instantiate()
	far.auto_claim = false   # 未认领地面物（工程文档 10）：验「顺路拾取」兜底路径
	far.hold_time = 0.0
	# 用不可堆叠的装备（药水会叠进已有堆，`inventory_used()` 不增，不便断言）
	far.item = {
		"kind": "equip", "itemId": "helmet_cloth", "instanceId": "probe_far",
		"quality": "common", "level": 1, "baseAttrs": {"def": 2},
		"affixes": [], "pctAttrs": [], "star": 0, "count": 1,
	}
	loot_root.add_child(far)
	far.global_position = player.global_position + Vector2(5.0 * Iso.TILE_W, 0.0)
	await get_tree().process_frame
	var bag0 := GameState.inventory_used()
	var d0 := player.global_position.distance_to(far.global_position)
	GameState.set_auto_pickup(true)
	GameState.set_auto_battle(true)
	var seen_loot_path := false
	for _i in range(210):                     # ≈3.5s
		await get_tree().physics_frame
		if pilot.current_state() == AutoBattle.State.PATH_TO_LOOT:
			seen_loot_path = true
	var bag1 := GameState.inventory_used()
	print("[Auto] 阶段④ 起距=%.0fpx 走向掉落=%s 背包 %d→%d 掉落物仍在=%s 状态=%s" % [
		d0, str(seen_loot_path), bag0, bag1, str(is_instance_valid(far)),
		AutoBattle.state_name(pilot.current_state())])
	_expect(seen_loot_path, "G 开启时无怪应走向掉落物（3.14 / 9.9）")
	_expect(bag1 > bag0, "顺路拾取后背包应 +1")

	# ⑤ 手动接管：模拟按住方向键 → 状态转「手动接管」（4.6）
	Input.action_press("move_left")
	for _i in range(6):
		await get_tree().physics_frame
	var st_manual := pilot.current_state()
	print("[Auto] 阶段⑤ 手动输入后状态=%s" % AutoBattle.state_name(st_manual))
	_expect(st_manual == AutoBattle.State.MANUAL_OVERRIDE,
		"检测到手动输入应进入「手动接管」，实际 %s" % AutoBattle.state_name(st_manual))
	Input.action_release("move_left")

	# ⑥ 关掉自动 → 状态应回到「关闭」（4.6：关闭后不得自动恢复）
	GameState.set_auto_battle(false)
	for _i in range(3):
		await get_tree().physics_frame
	print("[Auto] 阶段⑥ 关 F 后状态=%s" % AutoBattle.state_name(pilot.current_state()))
	_expect(pilot.current_state() == AutoBattle.State.OFF,
		"关闭自动战斗后状态应为「关闭」")

	# ⑦ 截图（开窗运行时）
	if DisplayServer.get_name() != "headless":
		GameState.set_auto_battle(true)
		GameState.set_auto_pickup(true)
		var mon: Monster = load("res://scenes/entities/Monster.tscn").instantiate()
		mon.monster_id = "wolf_corrupted"
		mon.ai_enabled = true
		game.get_node("Spawner").add_child(mon)
		mon.global_position = player.global_position + Vector2(150.0, -60.0)
		for _i in range(90):
			await get_tree().physics_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/degenerateage_auto_hud.png")
		print("[Auto] 截图：/tmp/degenerateage_auto_hud.png（HUD 应显示自动状态）")

	_finish()

func _on_monster_died(_id: String) -> void:
	_killed += 1

func _finish() -> void:
	if _failures.is_empty():
		print("[Auto] 全部断言通过 ✅")
	else:
		for f in _failures:
			print("[Auto] ❌ %s" % f)
		print("[Auto] 失败 %d 项" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)

func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failures.append(msg)
