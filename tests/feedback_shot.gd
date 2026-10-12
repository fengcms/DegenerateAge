extends Node
## 第三批测试反馈修复（工程文档 14）的视觉验收工具（开发期，M4-10；M5 随其他工具清理）：
##  ① 背包数量角标：可堆叠物品 count>1 显示数字，装备 / 单个不顶「1」；
##  ② 仓库数量角标：仓库侧同样生效；
##  ③ Boss 墓碑跨图：击杀后「切图」（销毁 + 重建世界）→ 墓碑仍在（世界时钟驱动）。
##
## 运行（需开窗，非 headless）：
##   GODOT=/Applications/Godot.app/Contents/MacOS/Godot
##   "$GODOT" --path . res://tests/FeedbackShot.tscn

func _ready() -> void:
	await _shot_bag()
	await _shot_warehouse()
	await _shot_tombstone_cross_map()
	get_tree().quit()

func _capture(path: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("[FeedbackShot] ", path)

## ① 背包：药水 ×12 / 材料 ×9 / 回城卷 ×3（角标）；装备 ×1（无角标）。
func _shot_bag() -> void:
	GameState.reset_to_defaults()
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	for _i in range(20):
		await get_tree().process_frame
	GameState.add_item({"kind": "potion", "itemId": "potion_hp_small", "count": 12})
	GameState.add_item({"kind": "potion", "itemId": "potion_mp_small", "count": 7})
	GameState.add_item({"kind": "misc", "itemId": "spirit_shard", "count": 9})
	GameState.add_item({"kind": "misc", "itemId": "misc_town_scroll", "count": 3})
	GameState.add_item({
		"kind": "equip", "itemId": "weapon_wolfking", "instanceId": "fb_sword",
		"quality": "rare", "level": 1, "baseAttrs": {"atk": 12}, "affixes": [],
		"pctAttrs": [], "star": 0, "count": 1,
	})
	var panel: Control = main.get_node("UI/InventoryPanel")
	panel.set_open(true)
	for _i in range(12):
		await get_tree().process_frame
	await _capture("/tmp/degenerateage_fb_bag.png")
	panel.set_open(false)
	await get_tree().process_frame
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

## ② 仓库：把材料存入仓库 → 两侧格子均显示数量角标。
func _shot_warehouse() -> void:
	GameState.reset_to_defaults()
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	for _i in range(20):
		await get_tree().process_frame
	GameState.add_item({"kind": "misc", "itemId": "spirit_shard", "count": 9})
	GameState.add_item({"kind": "misc", "itemId": "misc_town_scroll", "count": 4})
	GameState.add_item({"kind": "potion", "itemId": "potion_hp_small", "count": 6})
	# 存入仓库（背包侧留一份、仓库侧一份 → 两侧都有角标）
	var idx := _index_of("misc_town_scroll")
	if idx >= 0:
		GameState.warehouse_store(idx, Warehouse.item_token(GameState.inventory[idx]))
	var panel: Control = main.get_node("UI/WarehousePanel")
	EventBus.warehouse_panel_requested.emit("仓库管理员")
	for _i in range(12):
		await get_tree().process_frame
	await _capture("/tmp/degenerateage_fb_warehouse.png")
	panel.set_open(false)
	await get_tree().process_frame
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

## ③ Boss 墓碑跨图：击杀 → 截图；销毁 + 重建世界（模拟切图）→ 墓碑仍在，截图。
func _shot_tombstone_cross_map() -> void:
	GameState.reset_to_defaults()
	GameState.current_map = "corruption_source"
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	_disable_input(main)
	await get_tree().process_frame
	var world: Node2D = main.get_node("Game")
	var player: PlayerCharacter = main.get_node("Game/Entities/Player")
	player.set_physics_process(false)
	player.get_node("AutoPilot").set_physics_process(false)
	world.get_node("Spawner").set_process(false)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	await get_tree().process_frame

	var boss_spec: Dictionary = MapService.current_boss().duplicate()
	boss_spec["ai"] = false
	var sp := MonsterSpawner.new()
	world.add_child(sp)
	sp.setup(world.get_node("Ground"), player)
	sp.spawn_from_map("corruption_source")
	sp.spawn_from_specs([boss_spec], "corruption_source")
	sp.set_process(false)
	await get_tree().process_frame

	var boss := _find_boss(sp)
	if boss != null:
		boss.set_physics_process(false)
		boss.global_position = player.global_position + Vector2(90, -48)   # 挪到镜头内
		boss.take_hit({"damage": 9999999})
	await get_tree().create_timer(0.5).timeout
	await _capture("/tmp/degenerateage_fb_tomb_before.png")

	# 模拟切图：销毁旧世界装配 → 重建（倒计时未到 → 墓碑必须仍在）
	sp.queue_free()
	await get_tree().process_frame
	var sp2 := MonsterSpawner.new()
	world.add_child(sp2)
	sp2.setup(world.get_node("Ground"), player)
	sp2.spawn_from_map("corruption_source")
	sp2.spawn_from_specs([boss_spec], "corruption_source")
	sp2.set_process(false)
	await get_tree().create_timer(0.3).timeout
	await _capture("/tmp/degenerateage_fb_tomb_after.png")

	main.queue_free()
	await get_tree().process_frame
	GameState.reset_to_defaults()

func _find_boss(sp: Node) -> Monster:
	for child in sp.get_children():
		if child is Monster and (child as Monster).monster_id == "boss_corrupted_beast" and not (child as Monster).is_dead:
			return child
	return null

## 背包含指定 itemId 的格子下标（无 → -1）。
func _index_of(item_id: String) -> int:
	for i in range(GameState.inventory.size()):
		var it = GameState.inventory[i]
		if it is Dictionary and String(it.get("itemId", "")) == item_id:
			return i
	return -1

func _disable_input(node: Node) -> void:
	node.set_process_input(false)
	node.set_process_unhandled_input(false)
	node.set_process_unhandled_key_input(false)
	for child in node.get_children():
		_disable_input(child)
