extends Node
## 掉落「认领 + 飞行」诊断工具（开发期，M5 移除）。
## 复现「近战击杀 → 掉落是否可见、是否丢件」（工程文档 10 方案 C）：
##   ① 死亡当帧：收益**立即入账**（与玩家是否逗留无关）；掉落物脱离 ground_items 组；
##   ② 死亡当帧 ~1.2s：节点仍在 LootRoot 下（HOLD 停驻 + FLY 飞行 → 玩家「看得见」）；
##   ③ 动画结束：节点回收，地面无残留、不泄漏。
## 回归断言在 tests/smoke_test.gd 的 _test_claim_fly（本工具只做人工诊断输出）。
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
	print("[Repro] 击杀前：金币=%d 背包=%d ｜ 组内地面物=%d LootRoot 子节点=%d" % [
		gold_before, bag_before,
		get_tree().get_nodes_in_group("ground_items").size(), loot_root.get_child_count()])

	var hits := 0
	while not bool(wolf.get("is_dead")) and hits < 80:
		hits += 1
		player.perform_attack(wolf)
	await get_tree().physics_frame
	print("[Repro] 普攻 %d 次 → 狼.is_dead=%s" % [hits, str(wolf.get("is_dead"))])

	# ① 收益立即入账（不依赖玩家靠近） ② 认领即离组 ③ 飞行中节点仍可见
	print("[Repro] 死亡当帧：金币=%d(+%d) 背包=%d(+%d) ｜ 组内地面物=%d（认领即离组，应为 0）" % [
		GameState.gold, GameState.gold - gold_before,
		GameState.inventory_used(), GameState.inventory_used() - bag_before,
		get_tree().get_nodes_in_group("ground_items").size()])
	print("[Repro] 死亡当帧：LootRoot 子节点=%d（>0 = 停驻 / 飞行中，玩家肉眼可见）" % [
		loot_root.get_child_count()])

	var ttl := GroundItem.HOLD_TIME + GroundItem.FLY_TIME + 0.6
	await get_tree().create_timer(ttl).timeout
	print("[Repro] 动画结束（≈%.2fs）：LootRoot 子节点=%d（应为 0，无残留、不泄漏）｜ 金币=%d 背包=%d" % [
		ttl, loot_root.get_child_count(), GameState.gold, GameState.inventory_used()])

	get_tree().quit()
