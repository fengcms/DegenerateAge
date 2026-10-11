extends Node
## 货郎商店面板视觉验收（开发期，M5 移除）。
## 塞入金币与装备 → 走近货郎按 E 打开商店 → 分别截「购买」「出售」两页，
## 并打印交易前后金币 / 背包变化，验证买扣钱入包、卖加钱出包（6.4）。
## 运行：/Applications/Godot.app/Contents/MacOS/Godot --path . res://tests/ShopShot.tscn

func _ready() -> void:
	var main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	for _i in range(20):
		await get_tree().process_frame

	GameState.reset_to_defaults()
	GameState.player.level = 5
	EventBus.player_leveled.emit(5)

	# 先穿一件弱武器（作为 6.4「高于已穿戴」的对照基准）
	GameState.add_item(_equip("weapon_starter", "shot_worn", "common", {"atk": 5}))
	GameState.equip_from_inventory(_index_of("shot_worn"))

	# 背包装备：1 件升级件（一键出售会保留）+ 4 件普通（可售）
	GameState.add_item(_equip("weapon_wolfking", "shot_strong", "rare", {"atk": 12},
		[{"stat": "atk", "value": 6}]))
	GameState.add_item(_equip("helmet_cloth", "shot_helm", "common", {"def": 2}))
	GameState.add_item(_equip("shoes_cloth", "shot_shoes", "uncommon", {"def": 1}))
	GameState.add_item(_equip("armor_starter", "shot_armor", "uncommon", {"def": 4, "hp": 15}))
	GameState.add_item(_equip("shield_basic", "shot_shield", "common", {"def": 5}))
	# 非装备（出售页应禁用，展示「只收购装备」）
	GameState.add_item({"kind": "potion", "itemId": "potion_hp_small", "count": 6})

	GameState.gold = 500
	EventBus.gold_changed.emit(GameState.gold)
	EventBus.inventory_changed.emit()

	# 走近货郎 → 按 E 打开商店（完整交互链路：6.3）
	var game = main.get_node("Game")
	var npc = game.get_node("Npcs").get_child(0)
	var player = game.get_node("Entities/Player")
	player.global_position = npc.global_position + Vector2(40.0, 0.0)
	await get_tree().process_frame
	print("[ShopShot] 靠近货郎：交互半径内命中=%s 货郎=%s" % [
		str(game.nearest_npc() != null), String(npc.npc_name)])

	# 世界视图截图（面板未开）：确认货郎实体 / 头顶名称 /「[E] 交谈」提示 / 脚下高亮圈
	for _i in range(10):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/degenerateage_shop_world.png")

	game._try_interact()

	var panel = main.get_node("UI/ShopPanel")
	for _i in range(12):
		await get_tree().process_frame
	print("[ShopShot] 商店面板可见=%s（互斥后背包面板可见=%s）" % [
		str(panel.visible), str(main.get_node("UI/InventoryPanel").visible)])

	# ① 购买页截图
	panel._tabs.current_tab = 0
	for _i in range(6):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/degenerateage_shop_buy.png")

	# 买一瓶复活卷（120 金币）：验证扣钱 + 入包
	var gold0: int = GameState.gold
	var bag0: int = GameState.inventory_used()
	var buy := GameState.shop_buy("peddler_camp", "misc_revive_scroll")
	print("[ShopShot] 购买 复活卷 ok=%s 金币 %d→%d 背包 %d→%d" % [
		str(buy.get("ok", false)), gold0, GameState.gold, bag0, GameState.inventory_used()])
	# 失败分支：金币不足
	GameState.gold = 5
	var poor := GameState.shop_buy("peddler_camp", "misc_revive_scroll")
	print("[ShopShot] 金币不足购买 ok=%s 原因=%s" % [str(poor.get("ok", false)), String(poor.get("reason", ""))])
	GameState.gold = 500
	EventBus.gold_changed.emit(GameState.gold)

	# ② 出售页截图（选中 3 件普通装备；刻意不选升级件 shot_strong，留给一键出售验证保留逻辑）
	panel._tabs.current_tab = 1
	panel._refresh_sell()
	for i in [1, 2, 3]:
		if i < panel._sell_buttons.size() and not panel._sell_buttons[i].disabled:
			panel._on_sell_slot_pressed(i)
	for _i in range(6):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/degenerateage_shop_sell.png")
	print("[ShopShot] 出售页：选中 %d 件 结算文案「%s」" % [
		panel._selected.size(), panel._sell_summary.text])

	# ③ 确认出售 → 验证加钱出包
	var gold1: int = GameState.gold
	panel._on_confirm_sell_pressed()
	for _i in range(4):
		await get_tree().process_frame
	print("[ShopShot] 确认出售：金币 %d→%d 背包占用 %d" % [gold1, GameState.gold, GameState.inventory_used()])

	# ④ 一键出售 → 应保留高于已穿戴的武器
	var gold2: int = GameState.gold
	var all := GameState.shop_sell_all()
	print("[ShopShot] 一键出售：卖出 %d 件 保留 %d 件 金币 %d→%d 更优武器仍在背包=%s" % [
		int(all.get("sold", 0)), int(all.get("skipped", 0)), gold2, GameState.gold,
		str(_index_of("shot_strong") >= 0)])

	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/degenerateage_shop_after.png")
	get_tree().quit()

func _equip(item_id: String, inst_id: String, quality: String, base: Dictionary,
		affixes: Array = []) -> Dictionary:
	return {
		"kind": "equip", "itemId": item_id, "instanceId": inst_id,
		"quality": quality, "level": 1,
		"baseAttrs": base, "affixes": affixes, "pctAttrs": [],
		"star": 0, "count": 1,
	}

func _index_of(instance_id: String) -> int:
	for i in range(GameState.inventory.size()):
		var it = GameState.inventory[i]
		if it is Dictionary and String(it.get("instanceId", "")) == instance_id:
			return i
	return -1
