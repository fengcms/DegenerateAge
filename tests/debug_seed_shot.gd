extends Node
## 开发期测试便利验收（截图工具，M5 移除）。
## ① 世界视图：确认怪物数量已上调；② 背包面板：确认开局已发放测试武器。
## 运行：/Applications/Godot.app/Contents/MacOS/Godot --path . res://tests/DebugSeedShot.tscn

func _ready() -> void:
	var main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	for _i in range(8):
		await get_tree().process_frame

	# ① 世界视图：怪物数量 + 背包内容
	var spawner = main.get_node_or_null("Game/Spawner")
	var alive := 0
	var points := -1
	if spawner != null:
		alive = spawner.get_child_count()
		points = spawner.point_count()
	var bag: Array[String] = []
	for it in GameState.inventory:
		if it is Dictionary:
			bag.append(ItemUtil.display_name(it))
	print("[DebugSeedShot] 怪物实例=%d 怪物点=%d 背包=[%s]" % [
		alive, points, ", ".join(PackedStringArray(bag))])

	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	if img != null:
		img.save_png("/tmp/degenerateage_debug_world.png")

	# ② 背包面板：确认测试武器在列
	var panel = main.get_node("UI/InventoryPanel")
	panel.set_open(true)
	for _i in range(12):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img2: Image = get_viewport().get_texture().get_image()
	if img2 != null:
		img2.save_png("/tmp/degenerateage_debug_bag.png")
	print("[DebugSeedShot] 面板可见=%s" % str(panel.visible))

	# ③ 双击穿戴 → 展示攻击提升（T06）
	var idx := -1
	for i in range(GameState.inventory.size()):
		var it = GameState.inventory[i]
		if it is Dictionary and String(it.get("itemId", "")) == "debug_blade_overpower":
			idx = i
			break
	if idx >= 0:
		var before := GameState.total_attack()
		GameState.equip_from_inventory(idx)
		for _i in range(10):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img3: Image = get_viewport().get_texture().get_image()
		if img3 != null:
			img3.save_png("/tmp/degenerateage_debug_equipped.png")
		print("[DebugSeedShot] 穿戴测试武器：攻击 %d→%d 生命上限 %d（当前 HP %d）" % [
			before, GameState.total_attack(), GameState.max_hp(), int(GameState.player.hp)])

	get_tree().quit()
