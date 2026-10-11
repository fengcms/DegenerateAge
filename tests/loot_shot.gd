extends Node
## 掉落与拾取视觉验收工具（开发期）：
## 摆放代表性地面掉落物（金币 / 药水 / 普通·稀有·史诗装备）+ 击杀野狼产生真实掉落，
## 截图到 /tmp，再验证靠近自动拾取，打印金币与背包变化。
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

	# 代表性掉落物（半径 150 > 1.5 格，避免被立刻拾取，便于截图）
	var samples := [
		{"kind": "coin", "itemId": "coin", "gold": 6, "count": 1},
		{"kind": "potion", "itemId": "potion_hp_small", "count": 1},
		{"kind": "equip", "itemId": "helmet_cloth", "quality": "common", "level": 2, "instanceId": "s1", "count": 1},
		{"kind": "equip", "itemId": "weapon_wolfking", "quality": "rare", "level": 4, "instanceId": "s2", "count": 1},
		{"kind": "equip", "itemId": "armor_starter", "quality": "epic", "level": 3, "instanceId": "s3", "count": 1},
	]
	var gi_scene = load("res://scenes/entities/GroundItem.tscn")
	for i in range(samples.size()):
		var ang := -PI * 0.9 + float(i) * (PI * 0.6 / float(maxi(1, samples.size() - 1)))
		var gi = gi_scene.instantiate()
		gi.item = samples[i]
		loot_root.add_child(gi)
		gi.global_position = center + Vector2(cos(ang), sin(ang)) * 150.0

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
	print("[LootShot] ground_items=%d" % loot_root.get_child_count())

	# 走近拾取验证：把玩家移到掉落物中心附近
	var before_gold: int = GameState.gold
	var before_bag: int = GameState.inventory_used()
	player.global_position = center + Vector2(150.0, 0.0)   # 靠近第一件
	for _i in range(10):
		await get_tree().process_frame
	player.global_position = center + Vector2(230.0, -170.0)  # 走到野狼掉落处
	for _i in range(10):
		await get_tree().process_frame
	print("[LootShot] pickup 前 金币=%d 背包=%d / 后 金币=%d 背包=%d 剩余地面=%d" % [
		before_gold, before_bag, GameState.gold, GameState.inventory_used(), loot_root.get_child_count()])
	get_tree().quit()
