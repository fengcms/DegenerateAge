extends Node
## 背包与装备面板视觉验收（开发期，M5 移除）。
## 塞入代表性装备 → 穿戴数件 → 打开面板截图，并打印属性变化验证穿戴生效（T06）。
## 运行：/Applications/Godot.app/Contents/MacOS/Godot --path . res://tests/EquipShot.tscn

func _ready() -> void:
	var main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	for _i in range(20):
		await get_tree().process_frame

	GameState.reset_to_defaults()
	GameState.player.level = 5            # 满足狼王之刃门槛（5.2）
	EventBus.player_leveled.emit(5)       # 同步 HUD 等级显示

	# 代表性装备：不同品质 / 类型 / 词条（5.7 / 5.10）
	var samples := [
		{"itemId": "weapon_wolfking", "quality": "rare", "base": {"atk": 12}, "affixes": [{"stat": "atk", "value": 6}]},
		{"itemId": "armor_starter", "quality": "uncommon", "base": {"def": 4, "hp": 15}, "affixes": []},
		{"itemId": "helmet_cloth", "quality": "common", "base": {"def": 2}, "affixes": []},
		{"itemId": "shield_basic", "quality": "common", "base": {"def": 5}, "affixes": []},
		{"itemId": "shoes_cloth", "quality": "epic", "base": {"def": 1, "mp": 5}, "affixes": [{"stat": "hp", "value": 18}], "pct": [{"stat": "mpPercent", "value": 0.06}]},
		{"itemId": "necklace_basic", "quality": "common", "base": {"hp": 10}, "affixes": []},
		{"itemId": "ring_basic", "quality": "common", "base": {"atk": 1, "mp": 5}, "affixes": []},
		{"itemId": "bracer_basic", "quality": "common", "base": {"def": 2}, "affixes": []},
	]
	for s in samples:
		GameState.add_item({
			"kind": "equip", "itemId": String(s.itemId), "instanceId": "shot_%s" % s.itemId,
			"quality": String(s.get("quality", "common")), "level": 1,
			"baseAttrs": s.get("base", {}), "affixes": s.get("affixes", []),
			"pctAttrs": s.get("pct", []), "star": 0, "count": 1,
		})
	GameState.add_item({"kind": "potion", "itemId": "potion_hp_small", "count": 12})

	var atk0 := GameState.total_attack()
	var def0 := GameState.total_defense()
	var hp0 := GameState.max_hp()

	# 穿戴三件（武器 / 护甲 / 头盔）
	for inst in ["shot_weapon_wolfking", "shot_armor_starter", "shot_helmet_cloth"]:
		GameState.equip_from_inventory(_index_of(inst))

	print("[EquipShot] 穿戴后：攻击 %d→%d 防御 %d→%d 生命上限 %d→%d 装备件数 %d 背包占用 %d" % [
		atk0, GameState.total_attack(), def0, GameState.total_defense(),
		hp0, GameState.max_hp(), Equipment.worn_count(GameState.equipment),
		GameState.inventory_used()])

	# 打开面板并截图
	var panel = main.get_node("UI/InventoryPanel")
	panel.set_open(true)
	for _i in range(12):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("/tmp/degenerateage_equip.png")

	# 悬停 tooltip：把鼠标移到「首个非空背包格」上（面板 UI 由代码构建，直接取按钮数组）
	var bag = panel._bag_buttons
	var hi := -1
	for i in range(bag.size()):
		if i < GameState.inventory.size() and GameState.inventory[i] != null:
			hi = i
			break
	if hi >= 0:
		var target: Button = bag[hi]
		var pos: Vector2 = target.get_global_rect().get_center()
		Input.warp_mouse(pos)
		var mv := InputEventMouseMotion.new()
		mv.position = pos
		mv.global_position = pos
		Input.parse_input_event(mv)
		for _i in range(6):
			await get_tree().process_frame
		await get_tree().create_timer(1.0).timeout   # 等 tooltip 弹出延迟（默认 0.5s）
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img2: Image = get_viewport().get_texture().get_image()
		if img2 != null:
			img2.save_png("/tmp/degenerateage_equip_tip.png")
		print("[EquipShot] tooltip 截图：悬停格「%s」 tooltip=%s" % [
			target.text, target.tooltip_text.substr(0, 40).replace("\n", " / ")])

	print("[EquipShot] 面板可见=%s" % str(panel.visible))
	get_tree().quit()

func _index_of(instance_id: String) -> int:
	for i in range(GameState.inventory.size()):
		var it = GameState.inventory[i]
		if it is Dictionary and String(it.get("instanceId", "")) == instance_id:
			return i
	return -1
