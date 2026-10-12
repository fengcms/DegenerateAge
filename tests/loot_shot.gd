extends Node
## 掉落与拾取视觉验收工具（开发期）：
## ① 摆放代表性**未认领**地面掉落物（`auto_claim=false`，金币 / 药水 / 三档装备）→ 静置供截图；
## ② 击杀野狼产生真实掉落（**生成即认领 + 飞行动画**，工程文档 10 方案 C）→ 捕捉飞行观感；
## ③ 走近未认领物验证靠近自动拾取，打印金币与背包变化。
## 运行：GODOT=/Applications/Godot.app/Contents/MacOS/Godot
##       "$GODOT" --path . res://tests/LootShot.tscn

func _ready() -> void:
	var main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	for _i in range(20):
		await get_tree().process_frame

	var game: Node = main.get_node("Game")
	var player = game.get_node("Entities/Player")
	var loot_root = game.get_node("LootRoot")
	var center: Vector2 = player.global_position

	# 代表性**未认领**地面掉落物（auto_claim=false → 静置不飞，供地面物外观验收）
	var samples := [
		{"kind": "coin", "itemId": "coin", "gold": 6, "count": 1},
		{"kind": "potion", "itemId": "potion_hp_small", "count": 1},
		{"kind": "equip", "itemId": "helmet_cloth", "quality": "common", "level": 2, "instanceId": "s1", "count": 1},
		{"kind": "equip", "itemId": "weapon_wolfking", "quality": "rare", "level": 4, "instanceId": "s2", "count": 1},
		{"kind": "equip", "itemId": "armor_starter", "quality": "epic", "level": 3, "instanceId": "s3", "count": 1},
	]
	var gi_scene = load("res://scenes/entities/GroundItem.tscn")
	var sample_positions: Array[Vector2] = []
	for i in range(samples.size()):
		var ang := -PI * 0.9 + float(i) * (PI * 0.6 / float(maxi(1, samples.size() - 1)))
		var gi = gi_scene.instantiate()
		gi.auto_claim = false               # 留地展示（须在入树前设置，_ready 才读得到）
		gi.item = samples[i]
		loot_root.add_child(gi)
		var pos := center + Vector2(cos(ang), sin(ang)) * 150.0
		gi.global_position = pos
		sample_positions.append(pos)

	# 击杀一只野狼 → 真实掉落表产出（coin 概率 1.0）
	var wolf = null
	for e in get_tree().get_nodes_in_group("enemies"):
		if bool(e.get("ai_enabled")):
			wolf = e
			break
	if is_instance_valid(wolf):
		(wolf as Node2D).global_position = center + Vector2(230.0, -170.0)
		wolf.take_hit(Combat.resolve(99999.0, 0.0, 1.0, 0.0, 1.0, 0.0), null)

	for _i in range(30):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("/tmp/degenerateage_loot.png")
	print("[LootShot] LootRoot 子节点=%d（地面静置样本 + 认领飞行中）｜ 组内未认领=%d" % [
		loot_root.get_child_count(), get_tree().get_nodes_in_group("ground_items").size()])

	# 走近拾取验证：把玩家直接站到未认领样本上（须等待超过停驻 / 保护期）
	var before_gold: int = GameState.gold
	var before_bag: int = GameState.inventory_used()
	player.global_position = sample_positions[0]
	await get_tree().create_timer(GroundItem.HOLD_TIME + 0.4).timeout
	player.global_position = sample_positions[1]
	await get_tree().create_timer(GroundItem.HOLD_TIME + 0.4).timeout
	print("[LootShot] pickup 前 金币=%d 背包=%d / 后 金币=%d 背包=%d 剩余地面=%d" % [
		before_gold, before_bag, GameState.gold, GameState.inventory_used(), loot_root.get_child_count()])
	get_tree().quit()
