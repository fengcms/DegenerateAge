extends Node
## 掉落可见性诊断工具（开发期，M5 移除）。
## 复现「近战击杀 → 掉落物是否可见」：输出落地保护期各阶段的地面掉落物数量。
## 回归断言在 tests/smoke_test.gd 的 _test_pickup_delay（本工具只做人工诊断输出）。
## 运行：/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/PickupRepro.tscn

func _ready() -> void:
	var main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	for _i in range(20):
		await get_tree().process_frame

	var game: Node = main.get_node("Game")
	var player: Node2D = game.get_node("Entities/Player")
	var loot_root: Node2D = game.get_node("LootRoot")

	var wolf = null
	for e in get_tree().get_nodes_in_group("enemies"):
		if bool(e.get("ai_enabled")):
			wolf = e
			break
	if wolf == null:
		print("[Repro] 未找到 AI 怪物，终止")
		get_tree().quit(1)
		return

	# 模拟真实战况：狼在玩家近战范围内（普攻 range 1.0 格 = 64px）
	(wolf as Node2D).global_position = player.global_position + Vector2(56.0, 0.0)
	await get_tree().physics_frame

	var gold_before: int = GameState.gold
	var bag_before: int = GameState.inventory_used()
	print("[Repro] 击杀前：金币=%d 背包=%d 地面掉落=%d" % [
		gold_before, bag_before, loot_root.get_child_count()])

	var hits := 0
	while not bool(wolf.get("is_dead")) and hits < 40:
		hits += 1
		player.perform_attack(wolf)
	print("[Repro] 普攻 %d 次后 狼.is_dead=%s" % [hits, str(wolf.get("is_dead"))])

	var n0: int = loot_root.get_child_count()
	var min_d := INF
	for c in loot_root.get_children():
		if c is Node2D:
			min_d = minf(min_d, (c as Node2D).global_position.distance_to(player.global_position))
	print("[Repro] 死亡当帧：地面掉落=%d 玩家→最近掉落物=%.1fpx（自动拾取半径=%.1fpx）" % [
		n0, min_d, 1.5 * 64.0])

	# 落地保护期过半时应仍在地面（>0 即玩家肉眼可见）
	var delay := GroundItem.PICKUP_DELAY
	await get_tree().create_timer(maxf(0.1, delay * 0.5)).timeout
	print("[Repro] 保护期过半（≈%.2fs）：地面掉落=%d ← 大于 0 即玩家看得到" % [
		delay * 0.5, loot_root.get_child_count()])

	await get_tree().create_timer(delay * 0.5 + 0.6).timeout
	print("[Repro] 保护期结束后：地面掉落=%d 金币=%d(+%d) 背包=%d(+%d)" % [
		loot_root.get_child_count(), GameState.gold, GameState.gold - gold_before,
		GameState.inventory_used(), GameState.inventory_used() - bag_before])

	get_tree().quit()
