extends Node
## 货郎交易界面视觉验收（开发期，M5 移除）。
## 覆盖 M1-8 改造后的交互：靠近货郎按 E → **背包面板与货郎面板并列**打开 →
## 从背包把装备**拖入**货郎的出售托盘 → 确认出售结算。
## 依次截：世界视图、双面板并列（购买页）、拖入 3 件后的出售托盘、确认结算后。
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

	# 背包装备：1 件升级件（一键移入会保留）+ 4 件普通（可售）
	GameState.add_item(_equip("weapon_wolfking", "shot_strong", "rare", {"atk": 12},
		[{"stat": "atk", "value": 6}]))
	GameState.add_item(_equip("helmet_cloth", "shot_helm", "common", {"def": 2}))
	GameState.add_item(_equip("shoes_cloth", "shot_shoes", "uncommon", {"def": 1}))
	GameState.add_item(_equip("armor_starter", "shot_armor", "uncommon", {"def": 4, "hp": 15}))
	GameState.add_item(_equip("shield_basic", "shot_shield", "common", {"def": 5}))
	# 非装备（托盘应拒收，展示「只收购装备」）
	GameState.add_item({"kind": "potion", "itemId": "potion_hp_small", "count": 6})

	GameState.gold = 500
	EventBus.gold_changed.emit(GameState.gold)
	EventBus.inventory_changed.emit()

	# 走近货郎 → 按 E 打开交易（完整交互链路：6.3）
	var game = main.get_node("Game")
	var npc = game.get_node("Npcs").get_child(0)
	var player = game.get_node("Entities/Player")
	player.global_position = npc.global_position + Vector2(40.0, 0.0)
	await get_tree().process_frame
	print("[ShopShot] 靠近货郎：交互半径内命中=%s 货郎=%s" % [
		str(game.nearest_npc() != null), String(npc.npc_name)])

	# ① 世界视图截图（面板未开）：确认货郎实体 / 头顶名称 /「[E] 交谈」提示 / 脚下高亮圈
	for _i in range(10):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/degenerateage_shop_world.png")

	game._try_interact()

	var panel = main.get_node("UI/ShopPanel")
	var inv = main.get_node("UI/InventoryPanel")
	for _i in range(12):
		await get_tree().process_frame
	print("[ShopShot] 交易会话：货郎面板可见=%s 背包面板可见=%s（并列，不再互斥）" % [
		str(panel.visible), str(inv.visible)])
	print("[ShopShot] 布局：背包面板居中于左 %d px、货郎面板居中于右 %d px" % [
		int(inv._center.size.x), int(panel._center.size.x)])

	# ② 双面板并列截图（购买页）
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

	# ③ 拖拽出售：从左侧背包把 3 件普通装备拖入右侧托盘（真实走 ItemSlot 拖拽载荷）
	panel._tabs.current_tab = 1
	for _i in range(4):
		await get_tree().process_frame
	var grid: GridContainer = panel._tray_slots[0].get_parent()
	print("[ShopShot] 出售托盘几何：网格 %d×%d 宽 %.0f px，居中于货郎面板（面板宽 %.0f px）" % [
		grid.columns, grid.get_child_count() / grid.columns, grid.size.x, panel._center.get_child(0).size.x])
	for inst in ["shot_helm", "shot_shoes", "shot_shield"]:
		var ok := await _drop_into_tray(inv, panel, inst)
		print("[ShopShot] 拖入 %s → %s（托盘 %d 件）" % [inst, "成功" if ok else "失败", panel._tray.size()])

	# 非装备拖入应被拒收
	var potion_idx := _index_of_kind("potion")
	if potion_idx >= 0:
		var before_tray: int = panel._tray.size()
		panel._on_tray_drop(0, inv._bag_buttons[potion_idx]._get_drag_data(Vector2.ZERO))
		print("[ShopShot] 拖入药水 → 托盘 %d→%d 件（应不变，货郎只收购装备）" % [
			before_tray, panel._tray.size()])

	for _i in range(6):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/degenerateage_shop_sell.png")
	print("[ShopShot] 出售托盘：%s" % panel._tray_summary.text)

	# ④ 确认出售 → 验证加钱出包
	var gold1: int = GameState.gold
	panel._on_confirm_pressed()
	for _i in range(4):
		await get_tree().process_frame
	print("[ShopShot] 确认出售：金币 %d→%d 背包占用 %d" % [gold1, GameState.gold, GameState.inventory_used()])

	# ⑤ 一键移入 → 应保留高于已穿戴的武器（6.4）
	var gold2: int = GameState.gold
	panel._on_stage_all_pressed()
	await get_tree().process_frame
	print("[ShopShot] 一键移入：托盘 %d 件 保留更优武器（仍在背包）=%s" % [
		panel._tray.size(), str(_index_of("shot_strong") >= 0)])

	# ⑥ 关闭面板 → 托盘内未确认装备退回背包
	var tray_before: int = panel._tray.size()
	var bag_before: int = GameState.inventory_used()
	panel.set_open(false)
	await get_tree().process_frame
	print("[ShopShot] 关闭交易：托盘 %d→0 件 背包 %d→%d 格（未确认装备已退回）" % [
		tray_before, bag_before, GameState.inventory_used()])
	print("[ShopShot] 关闭后两面板可见性：货郎=%s 背包=%s" % [
		str(panel.visible), str(inv.visible)])

	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/degenerateage_shop_after.png")
	get_tree().quit()

## 把背包中指定实例 id 的装备拖入托盘（走 ItemSlot 的真实拖拽载荷）。
func _drop_into_tray(inv: Control, panel: Control, instance_id: String) -> bool:
	var idx := _index_of(instance_id)
	if idx < 0:
		return false
	var payload: Variant = inv._bag_buttons[idx]._get_drag_data(Vector2.ZERO)
	if not (payload is Dictionary):
		return false
	panel._on_tray_drop(0, payload)
	await get_tree().process_frame
	return true

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

## 背包中第一个指定品类的格位（-1 = 无）。
func _index_of_kind(kind: String) -> int:
	for i in range(GameState.inventory.size()):
		var it = GameState.inventory[i]
		if it is Dictionary and String(it.get("kind", "")) == kind:
			return i
	return -1
