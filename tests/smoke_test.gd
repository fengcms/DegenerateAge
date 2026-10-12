extends Node
## 无头冒烟测试（M1）。断言关键不变量，失败则以非 0 退出码结束。
##
## 运行（两步：先导入扫描，再跑测试）：
##   GODOT=/Applications/Godot.app/Contents/MacOS/Godot
##   "$GODOT" --headless --path . --import
##   "$GODOT" --headless --path . res://tests/SmokeTest.tscn
##
## 说明：--import 用于注册 class_name 全局类（Iso / IsoGround / PlayerCharacter /
## Combat / Monster / MonsterSpawner / DamageNumber / Fx / ItemUtil / Loot /
## Inventory / GroundItem / Equipment / Shop / ItemSlot / DragGhost / AutoBattle）；
## 换机或新增 class_name 后需先跑一次。

var _failures: Array[String] = []

func _ready() -> void:
	_test_data_validation()
	await _test_elite_affixes()
	_test_iso_math()
	_test_stats()
	_test_combat()
	await _test_single_resolution()
	await _test_monster_chase()
	await _test_monster_attacks_player()
	await _test_death_settles_once()
	await _test_spawner()
	await _test_level_gap()
	_test_loot()
	_test_balance_calibration()
	_test_inventory()
	_test_inventory_sort()
	_test_warehouse_sort()
	_test_mount_core()
	await _test_pickup()
	await _test_claim_fly()
	_test_equipment()
	_test_upgrade()
	_test_rune_upgrade()
	_test_rune_loot()
	await _test_blacksmith()
	await _test_warehouse()
	_test_shop()
	await _test_trade_panel()
	_test_debug_seed()
	await _test_drag_layer()
	await _test_auto_battle()
	await _test_save()
	# ---- M2 任务系统（R9）----
	_test_quest_chain()
	_test_quest_save()
	_test_level_up_carry()
	_test_quest_side()
	await _test_consumable()
	_test_map_travel()
	await _test_world()
	await _test_map_reload()
	await _test_auto_hud_reload()
	_test_fog()
	await _test_fog_ui()
	_finish()

func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failures.append(msg)

func _test_data_validation() -> void:
	var report: Array[String] = DataLoader.validate_all()
	_expect(report.is_empty(), "数据校验未通过：%s" % [report])

func _test_blacksmith() -> void:
	GameState.reset_to_defaults()
	var item := _equip_instance("weapon_starter", "smith_weapon", {"atk": 10})
	GameState.inventory[0] = item
	GameState.add_gold(500)
	var main := preload("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var world: Node = main.get_node("Game")
	var player: Node2D = world.get_node("Entities/Player")
	var smith: Npc = null
	for child in world.get_node("Npcs").get_children():
		if child is Npc and child.role == "blacksmith":
			smith = child
			break
	_expect(smith != null, "营地应生成铁匠 NPC")
	if smith != null:
		_expect(world.npc_at_screen(smith.get_global_transform_with_canvas().origin) == smith,
			"点击铁匠的人物区域应准确命中")
		_expect(not smith.is_player_in_range(), "铁匠应与出生点有可辨识距离")
		world._request_npc_interaction(smith)
		_expect(player.map_move_active, "远距离点击铁匠应开始自动靠近")
		player.global_position = smith.global_position + Vector2(32.0, 0.0)
		world._process(0.0)
		var dialogue: Control = main.get_node("UI/BlacksmithPanel")
		var upgrade: Control = main.get_node("UI/UpgradePanel")
		_expect(dialogue.visible and GameState.panel_open,
			"到达铁匠身边应打开对话并阻止世界操作")
		dialogue._show_menu()
		dialogue._open_upgrade()
		_expect(not dialogue.visible and upgrade.visible and GameState.panel_open,
			"铁匠菜单应切换到升星十字面板")
		upgrade._on_upgrade()
		_expect(item.star == 1 and GameState.gold == 0,
			"玩家通过铁匠对话应完成金币扣费和装备升星")
		upgrade.set_open(false)
		_expect(not GameState.panel_open, "关闭升星面板应恢复世界操作")
		player.global_position = smith.global_position + Vector2(32.0, 0.0)
		_expect(world._try_interact() and dialogue.visible,
			"靠近铁匠按 E 应能再次打开对话")
		dialogue.set_open(false)
		player.global_position = smith.global_position + Vector2(300.0, 0.0)
		world._request_npc_interaction(smith)
		player.map_move_active = false
		world._process(0.0)
		player.global_position = smith.global_position + Vector2(32.0, 0.0)
		world._process(0.0)
		_expect(not dialogue.visible, "手动打断走向 NPC 后不应延迟弹出对话")
	main.queue_free()
	await get_tree().process_frame
	GameState.reset_to_defaults()

func _test_inventory_sort() -> void:
	GameState.reset_to_defaults()
	var rare := _equip_instance("weapon_starter", "sort_rare", {"atk": 5})
	rare.quality = "rare"
	var common := _equip_instance("weapon_starter", "sort_common", {"atk": 6})
	GameState.inventory[3] = common
	GameState.inventory[7] = {"kind": "potion", "itemId": "potion_hp_small", "count": 98}
	GameState.inventory[9] = rare
	GameState.inventory[11] = {"kind": "potion", "itemId": "potion_hp_small", "count": 3}
	GameState.inventory[13] = {"kind": "potion", "itemId": "potion_hp_small", "count": 5, "batch": "special"}
	var panel := preload("res://scenes/ui/InventoryPanel.tscn").instantiate()
	add_child(panel)
	panel.set_open(true)
	panel.get("_organize_button").pressed.emit()
	_expect(GameState.inventory[0].instanceId == "sort_rare" and GameState.inventory[1].instanceId == "sort_common",
		"背包整理应先排装备，同模板高品质在前且保留实例")
	_expect(GameState.inventory[2].count == 99 and GameState.inventory[3].count == 2
		and GameState.inventory[4].count == 5 and GameState.inventory[4].batch == "special",
		"相同药品应安全合堆，不同元数据的堆叠不得混合")
	_expect(GameState.inventory[5] == null and GameState.inventory.size() == 40,
		"整理后空格应移到末尾且背包容量不变")
	_expect(not GameState.organize_inventory(), "重复整理应保持稳定顺序")
	panel.set_open(false)
	panel.queue_free()
	GameState.reset_to_defaults()

func _test_warehouse_sort() -> void:
	GameState.reset_to_defaults()
	var equipment := _equip_instance("weapon_starter", "stored_sorted", {"atk": 8})
	GameState.warehouse[6] = equipment
	GameState.warehouse[12] = {"kind": "potion", "itemId": "potion_hp_small", "count": 98}
	GameState.warehouse[15] = {"kind": "potion", "itemId": "potion_hp_small", "count": 3}
	GameState.inventory[5] = {"kind": "potion", "itemId": "potion_hp_small", "count": 2}
	var panel := preload("res://scenes/ui/WarehousePanel.tscn").instantiate()
	add_child(panel)
	panel.set_open(true)
	panel.get("_store_organize").pressed.emit()
	_expect(GameState.warehouse[0].instanceId == "stored_sorted"
		and GameState.warehouse[1].count == 99 and GameState.warehouse[2].count == 2
		and GameState.warehouse[3] == null, "仓库整理应保留装备实例、合并药品并把空位移后")
	_expect(GameState.inventory[5].count == 2 and GameState.inventory[0] == null,
		"仓库整理不得改变背包")
	panel.get("_bag_organize").pressed.emit()
	_expect(GameState.inventory[0].count == 2 and GameState.warehouse[1].count == 99,
		"仓库窗口的背包整理按钮应只整理背包")
	_expect(not GameState.organize_warehouse(), "重复整理仓库应保持稳定顺序")
	panel.set_open(false)
	panel.queue_free()
	GameState.reset_to_defaults()

func _test_mount_core() -> void:
	GameState.reset_to_defaults()
	var found := false
	for seed_value in range(100):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		for drop in Loot.roll("DT_Boss_L1", rng, "boss_corrupted_beast"):
			if String(drop.get("kind", "")) == "mount":
				found = String(drop.get("itemId", "")) == "mount_corrupted_wing"
				break
		if found:
			break
	_expect(found, "腐化巨兽掉落表应可产出配置坐骑")
	var wrong_source := RandomNumberGenerator.new()
	wrong_source.seed = 1
	for drop in Loot.roll("DT_Boss_L1", wrong_source, "wolf_corrupted"):
		_expect(String(drop.get("kind", "")) != "mount", "非指定 Boss 不得产出该坐骑")
	var ground := preload("res://scenes/entities/GroundItem.tscn").instantiate()
	ground.item = {"kind": "mount", "itemId": "mount_corrupted_wing", "count": 1}
	add_child(ground)
	_expect(GameState.owned_mounts == ["mount_corrupted_wing"] and GameState.inventory_used() == 0,
		"坐骑拾取后应进入独立收藏，不占背包")
	for seed_value in range(30):
		var duplicate_rng := RandomNumberGenerator.new()
		duplicate_rng.seed = seed_value
		for drop in Loot.roll("DT_Boss_L1", duplicate_rng, "boss_corrupted_beast"):
			_expect(String(drop.get("kind", "")) != "mount", "已收藏坐骑不得重复掉落")
	var panel := preload("res://scenes/ui/MountPanel.tscn").instantiate()
	add_child(panel)
	EventBus.mount_panel_requested.emit()
	var action: Button = panel.get("_action")
	_expect(panel.visible and action.disabled and panel.get("_image").texture != null,
		"坐骑快捷入口应打开预览，未达等级时骑乘按钮禁用")
	_expect(not GameState.ride_mount("mount_corrupted_wing").ok and GameState.mount_speed_multiplier() == 1.0,
		"20 级前不得骑乘")
	GameState.player.level = 20
	EventBus.player_leveled.emit(20)
	action.pressed.emit()
	_expect(GameState.active_mount == "mount_corrupted_wing" and is_equal_approx(GameState.mount_speed_multiplier(), 1.3),
		"20 级后骑乘应提供配置速度加成")
	var saved := SaveManager._collect()
	_expect(SaveManager._is_valid_save(saved), "坐骑收藏与骑乘状态应可入档")
	var invalid := saved.duplicate(true)
	invalid.activeMount = "unknown_mount"
	_expect(not SaveManager._is_valid_save(invalid), "存档不得接受未知骑乘坐骑")
	invalid = saved.duplicate(true)
	invalid.ownedMounts = ["unknown_mount"]
	_expect(not SaveManager._is_valid_save(invalid), "存档不得接受未知收藏坐骑")
	var old := saved.duplicate(true)
	old.schemaVersion = 3
	old.erase("ownedMounts")
	old.erase("activeMount")
	_expect(SaveManager._is_valid_save(old), "schema 3 旧档应可迁移空坐骑收藏")
	SaveManager.apply_to_game_state(saved)
	_expect(GameState.owned_mounts == ["mount_corrupted_wing"] and GameState.active_mount == "mount_corrupted_wing",
		"坐骑收藏与骑乘状态读档后应还原")
	action.pressed.emit()
	_expect(GameState.mount_speed_multiplier() == 1.0, "下骑应恢复基础速度")
	panel.set_open(false)
	panel.queue_free()
	ground.queue_free()
	GameState.reset_to_defaults()

func _test_warehouse() -> void:
	GameState.reset_to_defaults()
	_expect(GameState.warehouse.size() == 40 and Warehouse.next_cost(0) == 1000,
		"仓库初始应为 40 格、首次扩容 1000 金币")
	var item := _equip_instance("weapon_starter", "store_once", {"atk": 7})
	GameState.inventory[0] = item
	var stored := GameState.warehouse_store(0, "store_once")
	_expect(stored.ok and GameState.inventory[0] == null and GameState.warehouse[0] == item,
		"存入仓库应保持装备实例且清空背包格")
	GameState.inventory[1] = {"kind": "potion", "itemId": "potion_hp_small", "count": 1}
	var potion_token := Warehouse.item_token(GameState.inventory[1])
	_expect(GameState.warehouse_store(1, potion_token).ok and GameState.warehouse[1].kind == "potion",
		"仓库应支持药品")
	GameState.inventory[1] = {"kind": "rune", "itemId": "rune_iron", "count": 2}
	_expect(GameState.warehouse_store(1, Warehouse.item_token(GameState.inventory[1])).ok,
		"仓库应支持如意")
	GameState.inventory[1] = {"kind": "misc", "itemId": "misc_town_scroll", "count": 1}
	_expect(GameState.warehouse_store(1, Warehouse.item_token(GameState.inventory[1])).ok,
		"仓库应支持杂项")
	GameState.inventory[0] = _equip_instance("weapon_starter", "stale_now", {"atk": 2})
	_expect(not GameState.warehouse_store(0, "store_once").ok and GameState.warehouse[0] == item,
		"拖拽载荷过期时不得误存另一件装备")
	for i in range(GameState.inventory.size()):
		if GameState.inventory[i] == null:
			GameState.inventory[i] = _equip_instance("weapon_starter", "full_%d" % i, {"atk": 1})
	_expect(not GameState.warehouse_take(0, "store_once").ok and GameState.warehouse[0] == item,
		"背包满时取出应失败且仓库装备不丢失")
	GameState.inventory[2] = null
	var taken := GameState.warehouse_take(0, "store_once", 2)
	_expect(taken.ok and GameState.warehouse[0] == null and GameState.inventory[2] == item,
		"取出仓库应放入指定空格并保留实例属性")
	GameState.inventory[1] = {"kind": "potion", "itemId": "potion_hp_small", "count": 98}
	_expect(GameState.warehouse_take(1, Warehouse.item_token(GameState.warehouse[1])).ok
		and GameState.inventory[1].count == 99 and GameState.warehouse[1] == null,
		"背包无空格但有足够同类堆叠空间时，应能整堆取出药品")
	var stale_stack_token := Warehouse.item_token(GameState.warehouse[2])
	GameState.warehouse[2].count = 3
	_expect(not GameState.warehouse_take(2, stale_stack_token).ok,
		"可堆叠物品数量变化后旧拖拽载荷不得误取")
	_expect(not GameState.warehouse_expand().ok and GameState.warehouse.size() == 40,
		"金币不足不得扩容")
	GameState.add_gold(1000)
	var expanded := GameState.warehouse_expand()
	_expect(expanded.ok and expanded.cost == 1000 and GameState.warehouse.size() == 50 and GameState.gold == 0,
		"首次扩容应扣 1000 金币并加 10 格")
	_expect(Warehouse.next_cost(1) == 1600 and Warehouse.capacity(Warehouse.max_expansions()) == 200
		and Warehouse.next_cost(Warehouse.max_expansions()) == -1,
		"后续扩容费应按几何公式递增且 200 格封顶")
	var invalid_save := SaveManager._collect()
	invalid_save.warehouse.resize(49)
	_expect(not SaveManager._is_valid_save(invalid_save), "存档应拒绝仓库格数与扩容次数不一致")
	invalid_save = SaveManager._collect()
	invalid_save.warehouse[0] = {"kind": "potion", "itemId": "potion_hp_small", "count": 1}
	_expect(SaveManager._is_valid_save(invalid_save), "存档应接受仓库中的药品")
	invalid_save.warehouse[0] = {"kind": "bogus", "itemId": "none", "count": 1}
	_expect(not SaveManager._is_valid_save(invalid_save), "存档仍应拒绝非法品类")
	GameState.reset_to_defaults()
	var ui_item := _equip_instance("weapon_starter", "ui_store", {"atk": 8})
	GameState.inventory[0] = ui_item
	var main := preload("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var world: Node = main.get_node("Game")
	var player: Node2D = world.get_node("Entities/Player")
	var keeper: Npc = null
	for child in world.get_node("Npcs").get_children():
		if child is Npc and child.role == "warehouse":
			keeper = child
			break
	_expect(keeper != null, "营地应生成仓库管理员")
	if keeper != null:
		player.global_position = keeper.global_position + Vector2(32.0, 0.0)
		_expect(world._try_interact(), "靠近仓库管理员按 E 应派发交互")
		var panel: Control = main.get_node("UI/WarehousePanel")
		_expect(panel.visible and GameState.panel_open, "仓库面板应可打开并阻止世界操控")
		panel._on_slot_pressed("bag", 0)
		panel._on_slot_pressed("bag", 0)
		_expect(GameState.warehouse[0] == ui_item and GameState.inventory[0] == null,
			"双击背包装备应存入仓库")
		var bag_target: ItemSlot = panel.get("_bag_grid").get_child(10)
		var payload := {"from": ItemSlot.ROLE_WAREHOUSE, "index": 0, "item": ui_item}
		_expect(bag_target._can_drop_data(Vector2.ZERO, payload), "背包空格应接受仓库装备拖放")
		panel._on_drop(10, payload, "bag")
		_expect(GameState.warehouse[0] == null and GameState.inventory[10] == ui_item,
			"拖放仓库装备到背包指定空格应取出")
		panel.set_open(false)
		_expect(not GameState.panel_open, "关闭仓库应恢复世界操控")
	main.queue_free()
	await get_tree().process_frame
	GameState.reset_to_defaults()

func _test_rune_loot() -> void:
	var found := {}
	for seed_value in range(500):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		for item in Loot.roll("DT_Boss_L1", rng, "boss_corrupted_beast"):
			if String(item.get("kind", "")) == "rune":
				found[String(item.get("itemId", ""))] = true
	_expect(found.size() == 4, "四种如意都应能从 Boss 掉落表产出")
	var other_rng := RandomNumberGenerator.new()
	other_rng.seed = 42
	for item in Loot.roll("DT_Boss_L1", other_rng, "wolf_corrupted"):
		_expect(String(item.get("kind", "")) != "rune", "非 Boss 不得产出 Boss 专属如意")

func _test_rune_upgrade() -> void:
	GameState.reset_to_defaults()
	var weapon := _equip_instance("weapon_starter", "rune_upgrade", {"atk": 10})
	weapon.star = 8
	GameState.inventory[0] = weapon
	GameState.inventory[1] = {"kind": "rune", "itemId": "rune_diamond", "count": 2}
	GameState.inventory[2] = {"kind": "rune", "itemId": "rune_diamond", "count": 2}
	GameState.add_gold(Upgrade.cost(8))
	var plan := Upgrade.rune_plan(GameState.inventory, ["rune_diamond", "rune_diamond", "rune_diamond", "rune_diamond"])
	_expect(plan.ok and is_equal_approx(Upgrade.final_rate(8, plan.bonus), 100.0),
		"四枚钻石如意应把 8→9 的 20% 提高到封顶 100%")
	var panel := preload("res://scenes/ui/UpgradePanel.tscn").instantiate()
	add_child(panel)
	panel.set_open(true)
	for picker in panel.get("_rune_pickers"):
		picker.select(4)
		picker.item_selected.emit(4)
	_expect(panel.get("_price").text.contains("100%") and not panel.get("_upgrade_button").disabled,
		"升星面板应预览含四枚如意的最终成功率")
	panel.get("_upgrade_button").pressed.emit()
	_expect(weapon.star == 9 and GameState.gold == 0 and GameState.inventory[1] == null and GameState.inventory[2] == null,
		"升星成功应扣除四枚如意与金币，保留装备实例")
	panel.set_open(false)
	panel.queue_free()
	weapon.star = 11
	GameState.inventory[1] = {"kind": "rune", "itemId": "rune_iron", "count": 1}
	GameState.gold = Upgrade.cost(11)
	var before_gold := GameState.gold
	_expect(not GameState.upgrade_equipment("bag", 0, "stale_rune_upgrade", null, ["rune_iron"]).ok
		and GameState.gold == before_gold and GameState.inventory[1].count == 1,
		"装备实例失效时不得扣如意或金币")
	GameState.gold = before_gold - 1
	_expect(not GameState.upgrade_equipment("bag", 0, "rune_upgrade", null, ["rune_iron"]).ok
		and GameState.inventory[1].count == 1, "金币不足时不得扣如意")
	GameState.gold = before_gold
	_expect(not GameState.upgrade_equipment("bag", 0, "rune_upgrade", null, ["rune_iron", "rune_iron"]).ok
		and GameState.gold == before_gold and GameState.inventory[1].count == 1,
		"如意数量不足时不得扣金币或物品")
	var failed_rng := RandomNumberGenerator.new()
	failed_rng.seed = 42
	var failed := GameState.upgrade_equipment("bag", 0, "rune_upgrade", failed_rng, ["rune_iron"])
	_expect(failed.ok and not failed.success and weapon.star == 11 and GameState.gold == 0
		and GameState.inventory[1] == null and failed.runesUsed == 1,
		"升星失败应消耗金币与如意，但保留星级")
	GameState.reset_to_defaults()

func _test_upgrade() -> void:
	GameState.reset_to_defaults()
	var weapon := _equip_instance("weapon_starter", "upgrade_test", {"atk": 10}, [{"stat": "atk", "value": 3}])
	GameState.equipment["weapon"] = weapon
	GameState.add_gold(100000)
	var before_attack := GameState.total_attack()
	var result := GameState.upgrade_equipment("worn", "weapon", "upgrade_test")
	_expect(result.ok and result.success and result.cost == 500 and weapon.star == 1,
		"0→1 升星应必成且扣 500 金币")
	_expect(GameState.gold == 99500 and GameState.total_attack() == before_attack + 1,
		"升星后金币及已穿戴固定属性应即时生效")
	_expect(weapon.affixes[0].value == 3 and float(weapon.baseAttrs.atk) == 10.0,
		"升星不能修改原始基础值或词条")
	_expect(Equipment.score(weapon) > Equipment.score(_equip_instance("weapon_starter", "plain", {"atk": 10}, [{"stat": "atk", "value": 3}])),
		"升星后的装备评分应提高")
	var stale_gold := GameState.gold
	var stale := GameState.upgrade_equipment("worn", "weapon", "old_instance")
	_expect(not stale.ok and GameState.gold == stale_gold, "实例已移动时不应扣费")
	weapon.star = 11
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var failure_cost := Upgrade.cost(11)
	var failed := GameState.upgrade_equipment("worn", "weapon", "upgrade_test", rng)
	_expect(failed.ok and not failed.success and failed.cost == failure_cost,
		"11→12 失败应返回明确结算")
	_expect(weapon.star == 11 and GameState.gold == stale_gold - failure_cost,
		"失败应扣金币但星级不下降")
	weapon.star = 12
	var cap_gold := GameState.gold
	_expect(not GameState.upgrade_equipment("worn", "weapon", "upgrade_test").ok and GameState.gold == cap_gold,
		"满星不可继续扣费")
	var bag_item := _equip_instance("weapon_starter", "bag_upgrade", {"atk": 5})
	GameState.inventory[0] = bag_item
	GameState.gold = 0
	_expect(not GameState.upgrade_equipment("bag", 0, "bag_upgrade").ok and bag_item.star == 0,
		"背包装备金币不足时不应改变星级")
	GameState.add_gold(500)
	_expect(GameState.upgrade_equipment("bag", 0, "bag_upgrade").success and bag_item.star == 1,
		"背包装备应可升星，且保持原实例")
	var panel := preload("res://scenes/ui/UpgradePanel.tscn").instantiate()
	add_child(panel)
	panel.set_open(true)
	_expect(panel.visible and GameState.panel_open, "升星面板应可打开并屏蔽世界操控")
	panel.set_open(false)
	panel.queue_free()
	GameState.reset_to_defaults()

func _test_iso_math() -> void:
	# 往返转换
	var cell := Vector2i(7, 3)
	var back := Iso.world_to_grid(Iso.grid_to_world(cell))
	_expect(is_equal_approx(back.x, float(cell.x)) and is_equal_approx(back.y, float(cell.y)),
		"等距坐标往返失败：%s -> %s" % [cell, back])
	# 公式抽查（文档 7.1：tileW=64, tileH=32）
	_expect(is_equal_approx(Iso.grid_to_world(Vector2i(1, 0)).x, 32.0), "col+1 应使 screenX +32")
	_expect(is_equal_approx(Iso.grid_to_world(Vector2i(0, 1)).x, -32.0), "row+1 应使 screenX −32")
	_expect(is_equal_approx(Iso.grid_to_world(Vector2i(1, 1)).y, -32.0), "col+row 增大应使 screenY 更小")

# ---- M1-3：属性派生与数值广播 ----
func _test_stats() -> void:
	GameState.reset_to_defaults()
	# 4.3 / 4.4：L1（攻12/防5）→ HP 102、MP 35
	_expect(GameState.max_hp() == 102, "L1 最大生命应为 102，实际 %d" % GameState.max_hp())
	_expect(GameState.max_mp() == 35, "L1 最大法力应为 35，实际 %d" % GameState.max_mp())
	_expect(int(GameState.player.hp) == GameState.max_hp(), "初始当前 HP 应等于上限")
	_expect(GameState.inventory.size() == 40, "背包应为 40 格，实际 %d" % GameState.inventory.size())

	# 数值变更应经 EventBus 广播（HUD 实时刷新链路）
	var hp_sig := [0, 0]
	EventBus.player_hp_changed.connect(func(c, m): hp_sig[0] = c; hp_sig[1] = m)
	GameState.damage_player(15)
	_expect(hp_sig[0] == 87 and hp_sig[1] == 102, "扣血应广播 87/102，实际 %s" % [hp_sig])

	var gold_sig := [0]
	EventBus.gold_changed.connect(func(v): gold_sig[0] = v)
	GameState.add_gold(50)
	_expect(gold_sig[0] == 50, "金币变更应广播，实际 %d" % gold_sig[0])
	GameState.reset_to_defaults()

# ---- M1-4：伤害公式（3.2 / 3.5 / 3.8）----
func _test_combat() -> void:
	# 基础伤害：atk12 / def2 / 系数1.0 → floor(12 − 2×0.5) = 11
	var r := Combat.resolve(12.0, 2.0, 1.0, 0.0, 1.5, 0.0)
	_expect(not r.miss and int(r.damage) == 11 and not r.critical,
		"普攻基础伤害应为 11/非暴击，实际 %s" % [r])
	# 暴击：倍数 floor(11 × 1.5) = 16。注意 3.8 暴击率上限 75%，
	# 故用固定种子跑 100 次，确定性校验「暴击=16 / 非暴击=11」两条路径。
	var crng := RandomNumberGenerator.new()
	crng.seed = 999
	var n_crit := 0
	var n_norm := 0
	for _i in range(100):
		var rc := Combat.resolve(12.0, 2.0, 1.0, 0.75, 1.5, 0.0, crng)
		if rc.critical:
			n_crit += 1
			_expect(int(rc.damage) == 16, "暴击伤害应为 16，实际 %d" % int(rc.damage))
		else:
			n_norm += 1
			_expect(int(rc.damage) == 11, "非暴击伤害应为 11，实际 %d" % int(rc.damage))
	_expect(n_crit > 0 and n_norm > 0, "100 次抽样应同时出现暴击与非暴击（暴击 %d / 普通 %d）" % [n_crit, n_norm])
	# 概率 Miss（3.5）：dodge50 → 50%；封顶 75%
	_expect(is_equal_approx(Combat.miss_chance(50.0), 0.5), "闪避 50 → Miss 应为 50%")
	_expect(is_equal_approx(Combat.miss_chance(1000.0), 0.75), "Miss 应封顶 75%")
	# 伤害下限 ≥1（3.2 约束）
	var rmin := Combat.resolve(1.0, 999.0, 1.0, 0.0, 1.5, 0.0)
	_expect(int(rmin.damage) == 1, "伤害下限应为 1，实际 %d" % int(rmin.damage))
	# 技能系数（3.3）：裂地斩 1.4 → floor(12 × 1.4 − 1) = 15
	var rs := Combat.resolve(12.0, 2.0, 1.4, 0.0, 1.5, 0.0)
	_expect(int(rs.damage) == 15, "裂地斩(1.4) 伤害应为 15，实际 %d" % int(rs.damage))

# ---- T04：单次命中只结算一次 ----
func _test_single_resolution() -> void:
	var monster = load("res://scenes/entities/Monster.tscn").instantiate()
	monster.monster_id = "training_dummy"   # hpBase 50 / defense 0
	add_child(monster)
	await get_tree().process_frame

	var hp0: int = int(monster.get("hp"))
	_expect(hp0 == 50, "木桩初始 HP 应为 50，实际 %d" % hp0)

	var res := Combat.resolve(12.0, monster.get_defense(), 1.0, 0.0, 1.5, 0.0)
	monster.take_hit(res, null)
	_expect(int(monster.get("hp")) == hp0 - int(res.damage),
		"单次命中应只扣一次血：%d -> %d（伤害 %d）" % [hp0, int(monster.get("hp")), int(res.damage)])

	monster.queue_free()
	await get_tree().process_frame

# ---- M1-5：怪物 AI 追击（7.9）----
func _test_monster_chase() -> void:
	GameState.reset_to_defaults()
	var player = load("res://scenes/entities/Player.tscn").instantiate()
	add_child(player)
	player.global_position = Vector2.ZERO

	var wolf = load("res://scenes/entities/Monster.tscn").instantiate()
	wolf.monster_id = "wolf_corrupted"
	wolf.spawn_level = 2
	wolf.ai_enabled = true
	wolf.position = Vector2(160.0, 0.0)     # 在仇恨半径内、攻击范围外
	wolf.spawn_position = Vector2(160.0, 0.0)
	add_child(wolf)
	await get_tree().physics_frame

	var d0: float = wolf.global_position.distance_to(player.global_position)
	for _i in range(20):
		await get_tree().physics_frame
	var d1: float = wolf.global_position.distance_to(player.global_position)
	_expect(d1 < d0, "怪物应朝玩家追击：距离 %0.1f -> %0.1f" % [d0, d1])
	_expect(wolf.state == wolf.State.CHASE or wolf.state == wolf.State.ATTACK,
		"怪物应处于追击/攻击态，实际 %d" % wolf.state)

	player.queue_free()
	wolf.queue_free()
	await get_tree().physics_frame

# ---- M1-5：怪物攻击玩家（3.1 敌我对等）----
func _test_monster_attacks_player() -> void:
	GameState.reset_to_defaults()
	var player = load("res://scenes/entities/Player.tscn").instantiate()
	add_child(player)
	player.global_position = Vector2.ZERO

	var wolf = load("res://scenes/entities/Monster.tscn").instantiate()
	wolf.monster_id = "wolf_corrupted"
	wolf.spawn_level = 2
	wolf.ai_enabled = true
	wolf.position = Vector2(40.0, 0.0)      # 在普攻范围内（1 格 = 64px）
	wolf.spawn_position = Vector2(40.0, 0.0)
	add_child(wolf)

	var hp0: int = int(GameState.player.hp)
	for _i in range(15):
		await get_tree().physics_frame
	_expect(int(GameState.player.hp) < hp0,
		"怪物应攻击玩家并扣血：%d -> %d" % [hp0, int(GameState.player.hp)])
	_expect(GameState.player.hp == hp0 - 5,
		"野狼(攻8) 打玩家(防5) 应为 5 点伤害，实际 %d" % [hp0 - int(GameState.player.hp)])

	# 玩家无敌帧内不应被连续命中（3.4）
	var hp_a: int = int(GameState.player.hp)
	player.apply_damage(5)   # 立即再打一次应被无敌帧挡下
	_expect(int(GameState.player.hp) == hp_a, "无敌帧内不应再次扣血")

	player.queue_free()
	wolf.queue_free()
	await get_tree().physics_frame

# ---- M1-5/M1-6：死亡结算仅一次 + 掉落生成 ----
func _test_death_settles_once() -> void:
	GameState.reset_to_defaults()
	var loot_root := Node2D.new()
	loot_root.add_to_group("loot_root")
	add_child(loot_root)

	var wolf = load("res://scenes/entities/Monster.tscn").instantiate()
	wolf.monster_id = "wolf_corrupted"
	wolf.spawn_level = 2
	add_child(wolf)
	await get_tree().process_frame

	var xp0: int = int(GameState.player.xp)
	var lethal := Combat.resolve(9999.0, wolf.get_defense(), 1.0, 1.0, 1.0, 0.0)
	wolf.take_hit(lethal, null)
	_expect(bool(wolf.is_dead), "致命伤害后怪物应死亡")
	_expect(int(GameState.player.xp) - xp0 == 26,
		"L1 击杀 L2 野狼应结算经验 26，实际 %d" % [int(GameState.player.xp) - xp0])
	await get_tree().process_frame
	var drop_n := loot_root.get_child_count()
	_expect(drop_n >= 1, "击杀后应生成至少 1 件地面掉落（coin 概率 1.0），实际 %d" % drop_n)

	# 二次致命不应重复结算 / 重复掉落
	var xp1: int = int(GameState.player.xp)
	wolf.take_hit(lethal, null)
	await get_tree().process_frame
	_expect(int(GameState.player.xp) == xp1, "死亡结算应仅一次（经验）")
	_expect(loot_root.get_child_count() == drop_n, "死亡后不应重复掉落")

	wolf.queue_free()
	loot_root.queue_free()
	await get_tree().process_frame

# ---- M1-5：怪物点生成与刷新（7.9）----
func _test_spawner() -> void:
	var sp := MonsterSpawner.new()
	add_child(sp)
	sp.setup(null, null)
	sp.spawn_from_specs([
		{"monsterId": "wolf_corrupted", "level": 2, "count": 3, "respawnTime": 1.0, "ai": true},
	])
	await get_tree().process_frame
	_expect(sp.point_count() == 3, "应登记 3 个怪物点，实际 %d" % sp.point_count())
	_expect(sp.alive_count() == 3, "应生成 3 个存活怪物，实际 %d" % sp.alive_count())

	# 击杀一只后应按 respawnTime 重生
	var first: Node = sp.get_child(0)
	first.take_hit(Combat.resolve(9999.0, 0.0, 1.0, 1.0, 1.0, 0.0), null)
	await get_tree().process_frame
	_expect(sp.alive_count() == 2, "击杀后存活数应为 2，实际 %d" % sp.alive_count())

	# 注意：无头模式不锁帧，单帧 delta 极小，故按真实时间等待而非帧数
	await get_tree().create_timer(1.4).timeout
	_expect(sp.alive_count() == 3, "刷新时间到达后应回到 3 只，实际 %d" % sp.alive_count())

	sp.queue_free()
	await get_tree().process_frame

# ---- M3-6：地图等级范围与击杀经验等级差 ----
func _test_level_gap() -> void:
	_expect(is_equal_approx(LevelGap.experience_multiplier(5, 5), 1.0), "同级经验应为 1 倍")
	_expect(is_equal_approx(LevelGap.experience_multiplier(1, 10), 1.36), "越级经验应为 1.36 倍")
	_expect(is_equal_approx(LevelGap.experience_multiplier(1, 30), 1.5), "越级经验应封顶 1.5 倍")
	_expect(is_equal_approx(LevelGap.experience_multiplier(30, 1), 0.2), "回低图经验应保底 0.2 倍")

	var sp := MonsterSpawner.new()
	add_child(sp)
	sp.setup(null, null)
	sp.spawn_from_specs([{"monsterId":"shellback_bug", "level":9, "ai":false}], "corruption_source")
	_expect((sp.get_child(0) as Monster).level == 10, "Boss 图 L9 怪物应限制为 L10")
	_expect((sp.get_child(0) as Monster).max_hp > int(DataLoader.get_entry("monsters", "shellback_bug").hpBase),
		"高等级刷新怪物生命应高于模板等级")
	sp.spawn_from_specs([{"monsterId":"wolf_corrupted", "level":99, "ai":false}], "wild_trial")
	_expect((sp.get_child(1) as Monster).level == 5, "试炼野外 L99 配置应限制为 L5")
	sp.spawn_from_specs([{"monsterId":"shellback_bug", "ai":false}], "corruption_source")
	_expect((sp.get_child(2) as Monster).level == 10, "未指定等级应按模板等级再限制到地图范围")
	sp.queue_free()
	await get_tree().process_frame

	var original_maps: Array = DataLoader.tables["maps"]
	var invalid_maps := original_maps.duplicate(true)
	invalid_maps[0].spawnPoints[0].level = 2
	DataLoader.tables["maps"] = invalid_maps
	var report: Array[String] = DataLoader.validate_all()
	_expect(" ".join(PackedStringArray(report)).contains("超出 tierRange"), "配置校验应拒绝超出区域范围的刷新等级")
	DataLoader.tables["maps"] = original_maps

	GameState.reset_to_defaults()
	GameState.player.level = 10
	var wolf: Monster = load("res://scenes/entities/Monster.tscn").instantiate()
	wolf.monster_id = "wolf_corrupted"
	wolf.spawn_level = 2
	add_child(wolf)
	wolf.take_hit({"damage": 9999})
	_expect(int(GameState.player.xp) == 17, "L10 击杀 L2 野狼应获得 17 经验，实际 %d" % int(GameState.player.xp))
	wolf.take_hit({"damage": 9999})
	_expect(int(GameState.player.xp) == 17, "重复击杀不应重复结算等级差经验")
	GameState.add_xp(25)
	_expect(int(GameState.player.xp) == 42, "任务等直接奖励经验应保持原值")
	wolf.queue_free()
	await get_tree().process_frame
	GameState.reset_to_defaults()

# ---- M1-6 / T07：掉落合法（品类 / 引用 / 品质权重 / 等级范围）----
func _test_loot() -> void:
	# 固定种子 → 可复现
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var drops := Loot.roll("DT_Wild_L1", rng)
	_expect(drops.size() >= 1, "DT_Wild_L1 应至少产出 1 件（coin 概率 1.0）")
	var has_coin := false
	for it in drops:
		var kind := String(it.get("kind", ""))
		_expect(kind in ["coin", "potion", "equip", "rune", "misc"], "掉落品类非法：%s" % kind)
		if kind == "coin":
			has_coin = true
			var g := int(it.get("gold", 0))
			_expect(g >= 4 and g <= 8, "野生金币应在 [4,8]，实际 %d" % g)
		elif kind == "potion":
			_expect(DataLoader.get_entry("potions", String(it.get("itemId", ""))) != null,
				"掉落的药水未在 potions.json 定义")
		elif kind == "equip":
			_expect(ItemUtil.is_valid_quality(String(it.get("quality", ""))),
				"装备品质非法：%s" % String(it.get("quality", "")))
			var lv := int(it.get("level", 0))
			_expect(lv >= 1 and lv <= 5, "野生装备等级应在 [1,5]，实际 %d" % lv)
			_expect(DataLoader.get_entry("equipments", String(it.get("itemId", ""))) != null,
				"掉落的装备模板未定义：%s" % String(it.get("itemId", "")))
			_expect(not String(it.get("instanceId", "")).is_empty(), "装备实例需带 instanceId")
	_expect(has_coin, "DT_Wild_L1 coin 概率 1.0，应必出金币")

	# Boss 表品质权重仅 rare/epic/legendary（10.2 权重约束）
	for s in range(40):
		var br := RandomNumberGenerator.new()
		br.seed = s
		for it2 in Loot.roll("DT_Boss_L1", br):
			if String(it2.get("kind", "")) == "equip":
				var q := String(it2.get("quality", ""))
				_expect(q in ["rare", "epic", "legendary"],
					"Boss 装备品质应限于 rare/epic/legendary，实际 %s" % q)

	# M2（R1）：misc 品类 —— 裂壳虫专属表必掉灵能碎片（Q003 收集物来源，Q3 选专属表）
	var s_rng := RandomNumberGenerator.new()
	s_rng.seed = 777
	var drops2 := Loot.roll("DT_Shellback_L1", s_rng)
	var has_shard := false
	for it3 in drops2:
		var k3 := String(it3.get("kind", ""))
		_expect(k3 in ["coin", "potion", "misc"], "裂壳虫表品类非法：%s" % k3)
		if k3 == "misc":
			_expect(String(it3.get("itemId", "")) == "spirit_shard",
				"裂壳虫 misc 应为灵能碎片，实际 %s" % String(it3.get("itemId", "")))
			_expect(DataLoader.get_entry("miscItems", "spirit_shard") != null, "灵能碎片模板应存在")
			_expect(int(it3.get("count", 0)) >= 1, "灵能碎片应至少 1 个")
			has_shard = true
	_expect(has_shard, "裂壳虫表 misc 概率 1.0，应必出灵能碎片（Q003 不靠脸）")

	# 无效掉落表 → 空（不崩溃）
	_expect(Loot.roll("DT_NOT_EXIST").is_empty(), "无效掉落表应返回空数组")

# ---- M1 收尾 / 数值校准（07 方案 §7）：防回归断言 ----
## 校准值一旦被误改回旧值，此用例立即失败。
func _test_balance_calibration() -> void:
	# C1 裂壳虫：hpBase / defense 已校准（原 300 / 20 → 30s 过肉）
	var bug = DataLoader.get_entry("monsters", "shellback_bug")
	if bug == null:
		_expect(false, "缺少裂壳虫模板 shellback_bug")
	else:
		_expect(int(bug.get("hpBase", 0)) == 140,
			"C1 裂壳虫 hpBase 应为 140（校准），实际 %d" % int(bug.get("hpBase", 0)))
		_expect(int(bug.get("defense", 0)) == 12,
			"C1 裂壳虫 defense 应为 12（校准），实际 %d" % int(bug.get("defense", 0)))

	# C2 闪避为「点数」口径：野狼/游魂 6（≈10.7%）、狼王 8（≈13.8%）
	var dodge_cases := {"wolf_corrupted": 6, "ash_wraith": 6, "elite_wolf_king": 8}
	for mid in dodge_cases.keys():
		var mon = DataLoader.get_entry("monsters", mid)
		if mon == null:
			_expect(false, "缺少怪物模板 %s" % mid)
			continue
		var dv := int(mon.get("dodge", -1))
		_expect(dv == int(dodge_cases[mid]),
			"C2 %s dodge 应为 %d（点数口径），实际 %d" % [mid, int(dodge_cases[mid]), dv])
		# 点数口径复核：dodge=6 → Miss≈10.7%、dodge=8 → Miss≈13.8%
		var miss := Combat.miss_chance(float(dv))
		_expect(miss > 0.05 and miss < 0.20,
			"C2 %s dodge=%d 的 Miss 应落在 (5%%,20%%)，实际 %.2f%%" % [mid, dv, miss * 100.0])

	# C3 精英专属掉落表：存在 + 已绑定 + 金币/装备口径正确
	var elite = DataLoader.get_entry("monsters", "elite_wolf_king")
	if elite != null:
		_expect(String(elite.get("dropTableId", "")) == "DT_Elite_L1",
			"C3 精英应绑 DT_Elite_L1，实际 %s" % String(elite.get("dropTableId", "")))
	var dt = DataLoader.get_entry("dropTables", "DT_Elite_L1")
	if dt == null:
		_expect(false, "C3 缺少 DT_Elite_L1 掉落表")
	else:
		var coin_ok := false
		var equip_ok := false
		for e in dt.get("entries", []):
			var kind := String(e.get("kind", ""))
			if kind == "coin":
				var gr = e.get("goldRange", [])
				coin_ok = gr is Array and gr.size() >= 2 and int(gr[0]) == 48 and int(gr[1]) == 72
			elif kind == "equip":
				_expect(is_equal_approx(float(e.get("chance", 0.0)), 1.0),
					"C3 精英装备应必掉（chance 1.0）")
				var qw = e.get("qualityWeight", {})
				equip_ok = qw is Dictionary and int(qw.get("uncommon", 0)) == 50 \
					and int(qw.get("rare", 0)) == 40 and int(qw.get("epic", 0)) == 10
		_expect(coin_ok, "C3 DT_Elite_L1 金币范围应为 [48,72]")
		_expect(equip_ok, "C3 DT_Elite_L1 品质权重应为 优50/稀40/史10")

	# 精英掉落实测：金币落 [48,72] 且必出装备（多轮验证）
	var seen_equip := false
	for s in range(30):
		var r := RandomNumberGenerator.new()
		r.seed = 900 + s
		for it in Loot.roll("DT_Elite_L1", r):
			var k := String(it.get("kind", ""))
			if k == "coin":
				var g := int(it.get("gold", 0))
				_expect(g >= 48 and g <= 72, "C3 精英金币应在 [48,72]，实际 %d" % g)
			elif k == "equip":
				seen_equip = true
				var q := String(it.get("quality", ""))
				_expect(q in ["uncommon", "rare", "epic"], "C3 精英装备品质越界：%s" % q)
	_expect(seen_equip, "C3 精英应必出装备（30 轮抽取全未见 equip，异常）")

# ---- M1-6 / T10：背包存储与满包判定（5.8）----
func _test_inventory() -> void:
	var inv := Inventory.create(40)
	_expect(inv.size() == 40, "背包应为 40 格，实际 %d" % inv.size())
	_expect(Inventory.used_slots(inv) == 0, "新背包应为空")

	# 药水可堆叠
	var potion := {"kind": "potion", "itemId": "potion_hp_small", "count": 1}
	_expect(Inventory.add(inv, potion), "药水应可入包")
	_expect(Inventory.add(inv, potion), "药水应可续堆")
	_expect(Inventory.used_slots(inv) == 1, "两瓶药水应占 1 格，实际 %d" % Inventory.used_slots(inv))
	_expect(int(inv[0].get("count", 0)) == 2, "药水应堆叠为 2，实际 %d" % int(inv[0].get("count", 0)))

	# 装备不可堆叠 → 各占一格
	var eq := {"kind": "equip", "itemId": "weapon_starter", "quality": "common", "level": 1, "instanceId": "i1", "count": 1}
	_expect(Inventory.add(inv, eq), "装备应可入包")
	_expect(Inventory.add(inv, eq.duplicate(true)), "第二件装备应入新格")
	_expect(Inventory.used_slots(inv) == 3, "应为 3 格，实际 %d" % Inventory.used_slots(inv))

	# 满包：40 件装备 → is_full
	var full := Inventory.create(40)
	for i in range(40):
		Inventory.add(full, {"kind": "equip", "itemId": "weapon_starter", "quality": "common", "level": 1, "instanceId": "f%d" % i, "count": 1})
	_expect(Inventory.is_full(full), "40 件装备后背包应满")
	_expect(not Inventory.add(full, {"kind": "equip", "itemId": "weapon_starter", "count": 1}), "满包不应再入装备")
	_expect(not Inventory.has_space_for(full, {"kind": "equip", "itemId": "weapon_starter", "count": 1}), "满包对装备应无空间")
	_expect(not Inventory.has_space_for(full, {"kind": "potion", "itemId": "potion_hp_small", "count": 1}), "满包（无药水堆）不应容纳新药水")

# ---- M1-6：靠近自动拾取 / T10 满包留地（9.9）----
func _test_pickup() -> void:
	GameState.reset_to_defaults()
	GameState.settings["dropFlyAnim"] = false   # 本用例验「入包」语义：关掉飞行表现以便即时判定
	var loot_root := Node2D.new()
	loot_root.add_to_group("loot_root")
	add_child(loot_root)

	var player = load("res://scenes/entities/Player.tscn").instantiate()
	add_child(player)
	player.global_position = Vector2.ZERO
	await get_tree().physics_frame

	# 金币：靠近 → 直接入账（不占背包）
	var gi: GroundItem = load("res://scenes/entities/GroundItem.tscn").instantiate()
	gi.hold_time = 0.0   # 本用例验即时拾取语义，关闭停驻 / 保护期
	gi.item = {"kind": "coin", "itemId": "coin", "gold": 7, "count": 1}
	loot_root.add_child(gi)
	gi.global_position = Vector2(20.0, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_expect(GameState.gold == 7, "拾取金币应入账 7，实际 %d" % GameState.gold)
	_expect(not is_instance_valid(gi), "拾取后金币掉落物应被移除")

	# 药水：靠近 → 入背包
	var gi2: GroundItem = load("res://scenes/entities/GroundItem.tscn").instantiate()
	gi2.hold_time = 0.0
	gi2.item = {"kind": "potion", "itemId": "potion_hp_small", "count": 1}
	loot_root.add_child(gi2)
	gi2.global_position = Vector2(20.0, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_expect(GameState.inventory_used() == 1, "拾取药水应占 1 格，实际 %d" % GameState.inventory_used())

	# T10：背包满 → 物品留地
	GameState.inventory = Inventory.create(40)
	for i in range(40):
		Inventory.add(GameState.inventory, {"kind": "equip", "itemId": "weapon_starter", "quality": "common", "level": 1, "instanceId": "z%d" % i, "count": 1})
	var gi3: GroundItem = load("res://scenes/entities/GroundItem.tscn").instantiate()
	gi3.hold_time = 0.0
	gi3.item = {"kind": "equip", "itemId": "weapon_starter", "quality": "common", "level": 1, "instanceId": "ll", "count": 1}
	loot_root.add_child(gi3)
	gi3.global_position = Vector2(20.0, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_expect(is_instance_valid(gi3), "背包满时地面物品应留地（T10）")
	_expect(GameState.inventory_used() == 40, "背包满时应保持 40 件")

	player.queue_free()
	loot_root.queue_free()
	await get_tree().process_frame

## M1-6 改（工程文档 10 方案 C）：**生成即认领 + 飞行表现**。
## 契约：① 掉落产生即入包（**与玩家距离无关** → 挂机 0 丢件，解掉 M1-6 的丢件根因）；
##       ② 认领后脱离 `ground_items` 组（顺路拾取 / 观测工具自动看不见它）；
##       ③ 节点在 HOLD/FLY 期间保留（「看得见」），动画结束回收（不泄漏）；
##       ④ `auto_claim=false`（玩家丢弃物）保留旧地面语义（停驻期 + 靠近拾取）。
func _test_claim_fly() -> void:
	GameState.reset_to_defaults()
	GameState.settings["dropFlyAnim"] = true
	var loot_root := Node2D.new()
	loot_root.add_to_group("loot_root")
	add_child(loot_root)
	var player = load("res://scenes/entities/Player.tscn").instantiate()
	add_child(player)
	player.global_position = Vector2.ZERO
	await get_tree().physics_frame

	# 玩家故意站到很远：若「认领」依赖靠近，本用例就不会入账
	player.global_position = Vector2(900.0, 900.0)

	var gi: GroundItem = load("res://scenes/entities/GroundItem.tscn").instantiate()
	gi.item = {"kind": "coin", "itemId": "coin", "gold": 9, "count": 1}
	loot_root.add_child(gi)
	gi.global_position = Vector2(20.0, 0.0)

	# ① 生成即入包（与玩家位置无关 → 挂机不丢件）
	_expect(GameState.gold == 9,
		"掉落应在生成当帧入包（与玩家距离无关），实际金币 %d" % GameState.gold)
	# ② 认领后脱离 ground_items 组 + 标记为已认领
	_expect(not gi.is_in_group("ground_items"),
		"认领后应脱离 ground_items 组（顺路拾取 / 观测工具不再看到它）")
	_expect(gi.is_claimed(), "生成即认领的掉落物应标记为已认领")
	# ③ 动画期间保留可见，随后回收
	_expect(is_instance_valid(gi), "认领物应在停驻 / 飞行期间保留（供玩家看见）")
	await get_tree().create_timer(GroundItem.HOLD_TIME + GroundItem.FLY_TIME + 0.8).timeout
	_expect(not is_instance_valid(gi), "飞行动画结束后应回收掉落物节点（不泄漏）")

	# ④ 未认领（玩家丢弃物）：保留地面语义 —— 停驻期内不入包，靠近后入包
	var gi2: GroundItem = load("res://scenes/entities/GroundItem.tscn").instantiate()
	gi2.auto_claim = false
	gi2.item = {"kind": "coin", "itemId": "coin", "gold": 5, "count": 1}
	loot_root.add_child(gi2)
	gi2.global_position = Vector2(20.0, 0.0)
	var gold_before: int = GameState.gold
	for _i in range(3):
		await get_tree().physics_frame
	_expect(gi2.is_in_group("ground_items"), "未认领物应仍留在 ground_items 组（顺路拾取兜底）")
	_expect(GameState.gold == gold_before, "未认领物在停驻期内不应入包，实际 %d" % GameState.gold)
	player.global_position = Vector2.ZERO   # 走回拾取半径内
	await get_tree().create_timer(GroundItem.HOLD_TIME + 0.3).timeout
	_expect(GameState.gold == gold_before + 5, "未认领物在停驻期结束后应被靠近拾取")
	_expect(not is_instance_valid(gi2), "拾取后未认领物应被移除")

	player.queue_free()
	loot_root.queue_free()
	await get_tree().process_frame

## M1-7：装备栏 14 槽（5.1）、穿戴后属性立即生效（T06）、实例属性不重随（10.1）。
func _test_equipment() -> void:
	GameState.reset_to_defaults()

	# 14 槽定义：数量 / id 唯一 / 单双槽（5.1）
	_expect(Equipment.SLOT_DEFS.size() == 14, "装备槽应为 14 个，实际 %d" % Equipment.SLOT_DEFS.size())
	var seen := {}
	for d in Equipment.SLOT_DEFS:
		seen[String(d.id)] = true
	_expect(seen.size() == 14, "槽位 id 应唯一，实际 %d" % seen.size())
	_expect(Equipment.slots_for_kind("ring").size() == 2, "戒指应为双槽")
	_expect(Equipment.slots_for_kind("weapon").size() == 1, "武器应为单槽")
	_expect(Equipment.create().size() == 14, "Equipment.create 应生成 14 槽")
	# 武器与盾牌可同时装备（5.1）；类型取自模板（5.7）
	_expect(Equipment.item_kind({"itemId": "weapon_starter"}) == "weapon", "守护者短刃应为武器")
	_expect(Equipment.item_kind({"itemId": "shield_basic"}) == "shield", "木盾应为盾牌")

	# 穿戴：属性立即生效（T06），且不改基础值（5.1）
	var base_atk: int = int(GameState.player.attack)
	var hp_before := GameState.max_hp()
	var idx := _put_item(_equip_instance("weapon_starter", "e1", {"atk": 5}))
	var res := GameState.equip_from_inventory(idx)
	_expect(bool(res.get("ok", false)), "穿戴守护者短刃应成功：%s" % res.get("reason", ""))
	_expect(int(GameState.player.attack) == base_atk, "装备不应改基础攻击（5.1）")
	_expect(GameState.total_attack() == base_atk + 5,
		"总攻击应为基础+5，实际 %d" % GameState.total_attack())
	_expect(GameState.max_hp() > hp_before, "穿戴加攻装备后最大生命应提升（4.3 派生）")
	_expect(GameState.equipment.get("weapon") != null, "武器槽应已占用")
	_expect(GameState.inventory_used() == 0, "穿戴后该装备应离开背包（已穿戴不占背包 5.8）")

	# 实例属性不重随（10.1）：记录实例 → 卸下 → 再穿，逐字段一致
	var worn: Dictionary = GameState.equipment["weapon"]
	var atk_worn := GameState.total_attack()
	var un := GameState.unequip_slot("weapon")
	_expect(bool(un.get("ok", false)), "卸下应成功")
	_expect(GameState.total_attack() == base_atk, "卸下后总攻击应还原，实际 %d" % GameState.total_attack())
	_expect(GameState.inventory_used() == 1, "卸下后装备应回到背包")
	var again := GameState.equip_from_inventory(_index_of_instance("e1"))
	_expect(bool(again.get("ok", false)), "再次穿戴应成功")
	_expect(str(GameState.equipment["weapon"]) == str(worn), "穿脱后实例属性不应重随（10.1）")
	_expect(GameState.total_attack() == atk_worn, "再次穿戴后总攻击应一致")

	# 同槽替换：旧装备回背包，新装备生效
	GameState.player.level = 5
	var idx2 := _put_item(_equip_instance("weapon_wolfking", "e2", {"atk": 12}, [{"stat": "atk", "value": 6}]))
	var rep := GameState.equip_from_inventory(idx2)
	_expect(bool(rep.get("ok", false)), "替换武器应成功：%s" % rep.get("reason", ""))
	_expect(String(GameState.equipment["weapon"].get("instanceId", "")) == "e2", "武器槽应换成新武器")
	var rep_old: Dictionary = rep.get("replaced", {})
	_expect(not rep_old.is_empty(), "应返回被替换的旧装备")
	_expect(GameState.total_attack() == base_atk + 12 + 6,
		"攻击应为基础+12+6，实际 %d" % GameState.total_attack())
	_expect(GameState.inventory_used() == 1, "被替换的旧武器应回到背包")

	# 等级门槛（5.2 / 4.5）：不足不可穿戴，且不改变状态
	GameState.reset_to_defaults()
	var idx3 := _put_item(_equip_instance("weapon_wolfking", "e3", {"atk": 12}))
	var low := GameState.equip_from_inventory(idx3)
	_expect(not bool(low.get("ok", false)), "Lv1 不应能穿戴 Lv4 装备")
	_expect(GameState.equipment["weapon"] == null, "穿戴失败不应占用槽位")
	_expect(GameState.inventory_used() == 1, "穿戴失败不应改变背包")
	_expect(Equipment.level_req(_equip_instance("weapon_wolfking", "e3", {})) == 4,
		"狼王之刃门槛应为 4（5.2）")

	# 卸下需背包空位（5.1）
	GameState.player.level = 5
	GameState.equip_from_inventory(idx3)
	_expect(GameState.equipment["weapon"] != null, "Lv5 应能穿戴 Lv4 武器")
	for i in range(GameState.inventory.size()):
		if GameState.inventory[i] == null:
			GameState.inventory[i] = {"kind": "potion", "itemId": "potion_hp_small", "count": 99}
	var full_un := GameState.unequip_slot("weapon")
	_expect(not bool(full_un.get("ok", false)), "背包满时卸下应失败（5.1）")
	_expect(GameState.equipment["weapon"] != null, "卸下失败不应清空槽位")

	# 双槽类：两枚戒指可同时装备（5.1）
	GameState.reset_to_defaults()
	for k in range(2):
		var ri := _put_item(_equip_instance("ring_basic", "r%d" % k, {"atk": 1, "mp": 5}))
		GameState.equip_from_inventory(ri)
	_expect(Equipment.worn_count(GameState.equipment) == 2, "两枚戒指应各占一槽")
	_expect(GameState.equipment["ring_1"] != null and GameState.equipment["ring_2"] != null,
		"双槽应分别占用")
	# 装备 mp 进入 MPFlat（4.3）
	_expect(GameState.max_mp() == 35 + 10, "两枚戒指应使最大法力 +10，实际 %d" % GameState.max_mp())

	# 评分（5.9）：高攻装备评分更高
	_expect(Equipment.score({"baseAttrs": {"atk": 12}, "affixes": [{"stat": "atk", "value": 6}]})
		> Equipment.score({"baseAttrs": {"atk": 5}}), "高攻装备评分应更高")

	GameState.reset_to_defaults()

## M1-8：货郎买卖（6.4 / 6.2）——买扣金币入包；卖加金币出包；
## 金币不足 / 背包满 / 非装备出售 均有明确拦截（不静默）。
func _test_shop() -> void:
	var shop_id := "peddler_camp"
	GameState.reset_to_defaults()

	# 配置读取（数据驱动，10.2）
	_expect(Shop.display_name(shop_id) == "货郎（营地）",
		"货郎名应取自 shops.json，实际 %s" % Shop.display_name(shop_id))
	_expect(Shop.buy_items(shop_id).size() >= 1, "营地货郎应有出售商品")
	_expect(Shop.buy_price(shop_id, "potion_hp_small") == 20, "小红药售价应为 20")
	_expect(Shop.buy_price(shop_id, "potion_hp_large") == -1, "营地货郎不应出售大红药（返回 -1）")

	# 买 · 金币不足 → 明确失败，不扣钱不入包
	GameState.gold = 0
	var poor := GameState.shop_buy(shop_id, "potion_hp_small")
	_expect(not bool(poor.get("ok", false)), "金币不足应购买失败")
	_expect(GameState.gold == 0, "购买失败不应扣金币")
	_expect(GameState.inventory_used() == 0, "购买失败不应入包")

	# 买 · 成功 → 扣金币 + 入包（同一药水堆叠为 1 格 2 瓶）
	GameState.gold = 100
	var ok1 := GameState.shop_buy(shop_id, "potion_hp_small")
	_expect(bool(ok1.get("ok", false)), "金币充足应购买成功：%s" % ok1.get("reason", ""))
	_expect(GameState.gold == 80, "购买应扣 20 金币，实际 %d" % GameState.gold)
	_expect(GameState.inventory_used() == 1, "药水应入包占 1 格，实际 %d" % GameState.inventory_used())
	var ok2 := GameState.shop_buy(shop_id, "potion_hp_small")
	_expect(bool(ok2.get("ok", false)), "第二瓶应可续买")
	_expect(int(GameState.inventory[0].get("count", 0)) == 2,
		"两瓶药水应堆叠为 2，实际 %d" % int(GameState.inventory[0].get("count", 0)))

	# 买 · 杂项品类解析正确（回城卷 → misc）
	GameState.gold = 200
	var scroll := GameState.shop_buy(shop_id, "misc_town_scroll")
	_expect(bool(scroll.get("ok", false)), "回城卷应可购买")
	_expect(String(GameState.inventory[1].get("kind", "")) == "misc", "回城卷品类应为 misc")

	# 买 · 背包满 → 明确失败且不扣钱
	GameState.reset_to_defaults()
	GameState.gold = 999
	for i in range(GameState.inventory.size()):
		GameState.inventory[i] = _equip_instance("weapon_starter", "f%d" % i, {"atk": 1})
	var full := GameState.shop_buy(shop_id, "potion_hp_small")
	_expect(not bool(full.get("ok", false)), "背包满应购买失败")
	_expect(GameState.gold == 999, "背包满失败不应扣金币，实际 %d" % GameState.gold)

	# 售价公式（6.2）：round(baseValue × qualityMult × (1 + star×0.08))
	var common_w := _equip_instance("weapon_starter", "s1", {"atk": 5})
	_expect(Shop.sell_price(common_w) == 50,
		"普通武器（基础价 50 × 1.0）售价应为 50，实际 %d" % Shop.sell_price(common_w))
	var rare_w := _equip_instance("weapon_wolfking", "s2", {"atk": 12})
	rare_w["quality"] = "rare"
	_expect(Shop.sell_price(rare_w) == 720,
		"稀有武器（240 × 3）售价应为 720，实际 %d" % Shop.sell_price(rare_w))
	var rare_star := rare_w.duplicate(true)
	rare_star["star"] = 1
	_expect(Shop.sell_price(rare_star) == 778,
		"稀有 +1 星（240 × 3 × 1.08）应为 778，实际 %d" % Shop.sell_price(rare_star))
	_expect(Shop.can_sell(rare_w), "装备可出售")
	_expect(not Shop.can_sell({"kind": "potion", "itemId": "potion_hp_small"}),
		"药水不可出售给货郎（6.4）")

	# 卖 · 非装备拦截
	GameState.reset_to_defaults()
	GameState.inventory[0] = {"kind": "potion", "itemId": "potion_hp_small", "count": 1}
	var bad_sell := GameState.shop_sell(0)
	_expect(not bool(bad_sell.get("ok", false)), "药水不应可出售给货郎")
	_expect(GameState.inventory[0] != null, "出售失败不应移除物品")

	# 卖 · 装备 → 加金币出包
	GameState.reset_to_defaults()
	GameState.inventory[0] = _equip_instance("weapon_starter", "v1", {"atk": 5})
	var sell := GameState.shop_sell(0)
	_expect(bool(sell.get("ok", false)), "装备应可出售")
	_expect(GameState.gold == 50, "出售普通武器应得 50 金币，实际 %d" % GameState.gold)
	_expect(GameState.inventory[0] == null, "出售后该格应清空")
	_expect(not GameState.is_upgrade_over_worn(_equip_instance("weapon_starter", "v2", {"atk": 5})),
		"无同类型已穿戴装备时不应判为升级件")

	# 暂存 → 退回（关闭面板 / 取回）：不结算、不丢失
	GameState.reset_to_defaults()
	GameState.player.level = 5
	GameState.inventory[0] = _equip_instance("weapon_wolfking", "w_strong", {"atk": 12},
		[{"stat": "atk", "value": 6}])
	GameState.equip_from_inventory(0)      # 穿上强武器（武器槽占用）
	GameState.inventory[0] = _equip_instance("weapon_starter", "w_weak", {"atk": 5})
	GameState.inventory[1] = _equip_instance("helmet_cloth", "h1", {"def": 2})
	GameState.inventory[2] = _equip_instance("weapon_starter", "w_better", {"atk": 30})
	_expect(GameState.is_upgrade_over_worn(GameState.inventory[2]),
		"攻击 30 的武器应高于已穿戴（18）而判为升级件")

	var staged_ret: Array = [GameState.remove_item_at(0)]
	var gold_ret: int = GameState.gold
	var back_n := GameState.shop_unstage(staged_ret)
	_expect(back_n == 1, "退回 1 件应成功，实际 %d" % back_n)
	_expect(staged_ret.is_empty(), "退回后暂存列表应清空")
	_expect(GameState.gold == gold_ret, "退回不予结算（不应加金币）")
	_expect(_index_of_instance("w_weak") >= 0, "退回的装备应回到背包")

	# 暂存 → 确认出售（6.4）：批量结算为金币
	var staged: Array = []
	for i in range(GameState.inventory.size() - 1, -1, -1):
		if GameState.inventory[i] is Dictionary:
			staged.append(GameState.remove_item_at(i))
	var expect_gold := 0
	for it in staged:
		expect_gold += Shop.sell_price(it)
	var gold_before: int = GameState.gold
	var settled := GameState.shop_sell_staged(staged)
	_expect(int(settled.get("count", 0)) == staged.size(),
		"确认出售应结算全部暂存件，实际 %d" % int(settled.get("count", 0)))
	_expect(GameState.gold - gold_before == expect_gold,
		"确认出售应入账 %d 金币，实际 %d" % [expect_gold, GameState.gold - gold_before])
	_expect(GameState.inventory_used() == 0, "结算后背包应为空")
	_expect(GameState.shop_sell_staged([]).get("count", -1) == 0, "空暂存结算应为 0 件")

	GameState.reset_to_defaults()

## 交易界面（双面板 + 拖拽出售，M1-8 改造）：面板级不变量与 6.4 托盘流程。
## 独立实例化两个面板（不加载世界），验证拖入 / 取回 / 确认结算 / 一键移入保留升级件 / 关闭退回。
func _test_trade_panel() -> void:
	GameState.reset_to_defaults()
	GameState.player.level = 5

	var inv: Control = load("res://scenes/ui/InventoryPanel.tscn").instantiate()
	var shop: Control = load("res://scenes/ui/ShopPanel.tscn").instantiate()
	add_child(inv)
	add_child(shop)                       # 与 Main.tscn 同序：货郎面板在上层
	await get_tree().process_frame

	# 开战前：两面板都关闭
	_expect(not shop.visible and not inv.visible, "未交易时两面板应都关闭")

	# 走近货郎按 E → 进入交易会话：货郎面板 + 背包面板**并列打开**（工程文档 05 🔴R2）
	EventBus.shop_open_requested.emit("peddler_camp")
	await get_tree().process_frame
	_expect(shop.visible, "开战后货郎面板应可见")
	_expect(inv.visible, "开战后背包面板应同时可见（不再互斥）")
	_expect(shop.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"货郎面板根节点应为 IGNORE，否则会吞掉左侧背包的鼠标事件")
	_expect(not inv._dim.visible and not shop._dim.visible, "交易会话中双方遮罩都应隐藏")

	# 背包准备：2 件普通装备（可售）+ 1 件优于已穿戴的武器（一键移入应跳过）
	GameState.inventory[0] = _equip_instance("weapon_wolfking", "p_worn", {"atk": 12},
		[{"stat": "atk", "value": 6}])
	GameState.equip_from_inventory(0)     # 穿上强武器
	GameState.inventory[0] = _equip_instance("weapon_starter", "p_weak", {"atk": 5})
	GameState.inventory[1] = _equip_instance("helmet_cloth", "p_helm", {"def": 2})
	GameState.inventory[2] = _equip_instance("weapon_starter", "p_better", {"atk": 30})
	EventBus.inventory_changed.emit()
	await get_tree().process_frame

	var bag_slot: ItemSlot = inv._bag_buttons[0]
	var payload: Variant = bag_slot._get_drag_data(Vector2.ZERO)
	_expect(payload is Dictionary, "背包格应可拖出（_get_drag_data 返回载荷）")
	_expect(int((payload as Dictionary).get("index", -1)) == 0, "载荷应携带背包下标")
	var payload_item: Dictionary = (payload as Dictionary).get("item", {})
	_expect(String(payload_item.get("instanceId", "")) == "p_weak", "载荷应携带该格物品实例")

	var tray_slot: ItemSlot = shop._tray_slots[0]
	_expect(tray_slot._can_drop_data(Vector2.ZERO, payload), "托盘格应接受背包格的投放")
	_expect(not tray_slot._can_drop_data(Vector2.ZERO, {"from": 999}), "托盘格不应接受非法来源")

	# 拖入 → 装备从背包移入托盘暂存（未结算）
	shop._on_tray_drop(0, payload)
	await get_tree().process_frame
	_expect(shop._tray.size() == 1, "拖入后托盘应暂存 1 件，实际 %d" % shop._tray.size())
	_expect(_index_of_instance("p_weak") < 0, "拖入后该装备应离开背包")
	_expect(GameState.gold == 0, "暂存阶段不应结算金币")
	_expect(tray_slot.item.get("instanceId", "") == "p_weak", "托盘格应显示该装备")

	# 点托盘格 → 取回背包
	shop._on_tray_slot_pressed(0)
	await get_tree().process_frame
	_expect(shop._tray.is_empty(), "取回后托盘应清空")
	_expect(_index_of_instance("p_weak") >= 0, "取回的装备应回到背包")

	# 一键移入：移入可售装备、跳过优于已穿戴的武器
	shop._on_stage_all_pressed()
	await get_tree().process_frame
	_expect(shop._tray.size() == 2, "一键移入应移入 2 件可售装备，实际 %d" % shop._tray.size())
	_expect(_index_of_instance("p_better") >= 0, "优于已穿戴的武器不应被一键移入（6.4）")
	_expect(_index_of_instance("p_weak") < 0 and _index_of_instance("p_helm") < 0,
		"可售装备应已移入托盘")

	# 确认出售 → 结算为金币
	var gold_before: int = GameState.gold
	shop._on_confirm_pressed()
	await get_tree().process_frame
	_expect(shop._tray.is_empty(), "确认出售后托盘应清空")
	_expect(GameState.gold > gold_before, "确认出售应加金币，实际 %d→%d" % [gold_before, GameState.gold])

	# 关闭货郎面板 → 背包面板随之关闭（交易会话整体退出）
	shop.set_open(false)
	await get_tree().process_frame
	_expect(not shop.visible and not inv.visible, "关闭货郎面板应同时关闭背包面板")
	_expect(not GameState.panel_open, "退出交易后角色操控应解除屏蔽")

	# 关闭时托盘内未确认装备应退回背包（不静默丢失，🔴R3）
	EventBus.shop_open_requested.emit("peddler_camp")
	await get_tree().process_frame
	GameState.inventory[0] = _equip_instance("weapon_starter", "p_lost", {"atk": 5})
	EventBus.inventory_changed.emit()
	await get_tree().process_frame
	shop._on_tray_drop(0, inv._bag_buttons[0]._get_drag_data(Vector2.ZERO))
	_expect(shop._tray.size() == 1, "再次拖入应暂存 1 件")
	shop.set_open(false)
	await get_tree().process_frame
	_expect(shop._tray.is_empty(), "关闭后面板托盘应清空")
	_expect(_index_of_instance("p_lost") >= 0, "关闭面板时未确认的装备应退回背包")

	inv.queue_free()
	shop.queue_free()
	await get_tree().process_frame
	GameState.reset_to_defaults()

# ---- M1-8 追加修复：拖拽预览层级（DragGhost 的落点图层）----
## 根因：引擎的 set_drag_preview 把预览插到发起拖拽的面板内部（实测 4.7），与其余面板
## 同 canvas、同 z_index → 被排在后面的面板整块盖住；z_index 只在同 canvas 内比较。
## 故改为自绘 DragGhost，挂到 UI 层内最高层（组 drag_ghost_layer）。本测守住这条契约。
func _test_drag_layer() -> void:
	GameState.reset_to_defaults()
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame

	var layer := get_tree().get_first_node_in_group("drag_ghost_layer")
	_expect(layer != null, "缺少拖拽预览图层（组 drag_ghost_layer）")
	var shop: Control = main.get_node("UI/ShopPanel")
	var inv: Control = main.get_node("UI/InventoryPanel")

	# HUD 提示条必须浮在面板之上：Hud 与面板同 canvas、z_index 皆为 0 时，
	# 绘制顺序由树的先后决定（Hud 排在 UI 层最前 → 被后绘制的面板整块盖住），
	# 于是交易中的「货郎只收购装备」「背包已满」等提示玩家根本看不到。
	var toast: Control = main.get_node("UI/Hud/ToastBox")
	_expect(toast != null, "未找到 HUD 提示条容器（Hud/ToastBox）")
	if toast != null:
		_expect(toast.z_index > shop.z_index and toast.z_index > inv.z_index,
			"HUD 提示条 z_index（%d）应高于面板（货郎 %d / 背包 %d）"
			% [toast.z_index, shop.z_index, inv.z_index])

	if layer != null:
		_expect(int(layer.z_index) > int(shop.z_index) and int(layer.z_index) > int(inv.z_index),
			"拖拽图层 z_index（%d）应高于面板（货郎 %d / 背包 %d）"
			% [layer.z_index, shop.z_index, inv.z_index])
		if toast != null:
			_expect(int(toast.z_index) < int(layer.z_index),
				"HUD 提示条 z_index（%d）应低于拖拽幽灵图层（%d）—— 幽灵须始终最上"
				% [toast.z_index, layer.z_index])
		_expect(layer.mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"拖拽图层不得拦截鼠标（否则面板点击失效）")
		_expect(layer.get_parent() == main.get_node("UI"),
			"拖拽图层必须与面板同属 UI 层（z_index 只在同 canvas 内有效）")

	# 非拖拽态取载荷：返回载荷但**不创建幽灵**，也不得报错（无头安全）
	GameState.add_item(_equip_instance("helmet_cloth", "dl_probe", {"def": 2}))
	var inv2: Control = load("res://scenes/ui/InventoryPanel.tscn").instantiate()
	add_child(inv2)
	await get_tree().process_frame
	inv2._bag_buttons[0].draggable = true
	var payload: Variant = inv2._bag_buttons[0]._get_drag_data(Vector2.ZERO)
	_expect(payload is Dictionary, "背包格应可拖出（_get_drag_data 返回载荷）")
	if layer != null:
		_expect(layer.get_node_or_null("DragGhost") == null,
			"非拖拽态下不应创建拖拽幽灵（避免控件泄漏）")

	inv2.queue_free()
	main.queue_free()
	await get_tree().process_frame
	GameState.reset_to_defaults()

## M1-9：自动战斗 / 自动拾取（3.14 硬性异常规则；T08 不可达改选 / T10 背包满 / T11 MP 与冷却；4.6 手动接管）。
func _test_auto_battle() -> void:
	GameState.reset_to_defaults()

	# ---- T11：MP / 冷却 / 等级不足 → 不施放该技能（choose_skill 纯函数）----
	var skills: Array = DataLoader.get_table("skills")
	var earth := _skill_by_id(skills, "earth_cleave")     # Lv5 / 15MP / 范围(cone)
	var armor := _skill_by_id(skills, "armor_break")      # Lv25 / 40MP / 单体
	_expect(not earth.is_empty() and not armor.is_empty(),
		"skills.json 应含 earth_cleave / armor_break")
	# 3.14：优先可用范围技（命中 ≥2）
	_expect(String(AutoBattle.choose_skill([earth], 5, 35, {}, 3).get("id", "")) == "earth_cleave",
		"命中≥2 时应优先范围技")
	# 单体场景不选范围技（返回空 = 回退普攻）
	_expect(AutoBattle.choose_skill([earth], 5, 35, {}, 1).is_empty(),
		"单体场景不应选范围技（应回退普攻）")
	# MP 不足 → 不施放（T11）
	_expect(AutoBattle.choose_skill([earth], 5, 14, {}, 3).is_empty(),
		"MP 不足不应施放技能（T11）")
	# 冷却中 → 不施放（T11）
	_expect(AutoBattle.choose_skill([armor], 25, 40, {"armor_break": 3.0}, 1).is_empty(),
		"冷却中不应施放技能（T11）")
	# 等级不足 → 不施放
	_expect(AutoBattle.choose_skill([earth], 1, 999, {}, 3).is_empty(),
		"技能未解锁不应施放")
	# 条件齐备 → 可施放单体
	_expect(String(AutoBattle.choose_skill([armor], 25, 40, {}, 1).get("id", "")) == "armor_break",
		"条件齐备应可施放单体技能")

	# ---- 状态机：实例化世界，开 F → 锚点搜怪 → 接近 / 攻击 ----
	var game: Node = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	var player: PlayerCharacter = game.get_node("Entities/Player")
	var pilot: AutoBattle = player.get_node_or_null("AutoPilot")
	_expect(pilot != null, "Player 下应挂有 AutoPilot 自动战斗决策机")
	if pilot == null:
		game.queue_free()
		await get_tree().process_frame
		GameState.reset_to_defaults()
		return

	# 锚点半径内放一只不动的怪，保证必有目标（避免依赖随机怪物点）
	var mon: Monster = load("res://scenes/entities/Monster.tscn").instantiate()
	mon.monster_id = "training_dummy"
	mon.ai_enabled = false
	game.get_node("Spawner").add_child(mon)
	mon.global_position = player.global_position + Vector2(220.0, 0.0)
	await get_tree().process_frame

	GameState.set_auto_battle(true)
	_expect(GameState.auto_battle_on, "开启自动战斗后 auto_battle_on 应为 true")
	# 压低攻击保证目标不死，便于观察状态机；max_hp 由攻击派生（4.3）→ 同步补满
	GameState.player.attack = 1
	GameState.player.hp = GameState.max_hp()
	var seen_combat := false
	for _i in range(120):                     # ≈2s
		await get_tree().physics_frame
		var st := pilot.current_state()
		if st == AutoBattle.State.PATH_TO_TARGET or st == AutoBattle.State.ATTACK_TARGET:
			seen_combat = true
	_expect(pilot.current_target() != null, "自动战斗应锁定锚点半径内的目标")
	_expect(seen_combat, "开 F 后应进入「接近目标」或「攻击目标」状态")

	# 4.6 手动接管：模拟按住方向键 → 立即转「手动接管」
	Input.action_press("move_left")
	for _i in range(4):
		await get_tree().physics_frame
	_expect(pilot.current_state() == AutoBattle.State.MANUAL_OVERRIDE,
		"检测到手动输入应进入「手动接管」，实际 %s"
		% AutoBattle.state_name(pilot.current_state()))
	Input.action_release("move_left")

	# 3.14 ⑥ 死亡 → 自动转 off（4.7）
	player.is_dead = true
	for _i in range(4):
		await get_tree().physics_frame
	_expect(not GameState.auto_battle_on, "玩家死亡后自动战斗应自动关闭（3.14）")
	player.is_dead = false
	GameState.set_auto_battle(false)

	# ---- T10：背包满 → 不走向需要入包的掉落物（金币不受背包限制）----
	for i in range(GameState.inventory.size()):
		GameState.inventory[i] = _equip_instance("helmet_cloth", "full_%d" % i, {"def": 1})
	var loot_root: Node = game.get_node("LootRoot")
	var it_potion: GroundItem = load("res://scenes/entities/GroundItem.tscn").instantiate()
	it_potion.item = {"kind": "potion", "itemId": "potion_hp_small", "count": 1}
	loot_root.add_child(it_potion)
	await get_tree().process_frame
	_expect(not pilot._can_pick(it_potion),
		"背包满时应判定该掉落物不可拾取（T10：不得无限拾取满背包）")
	var it_coin: GroundItem = load("res://scenes/entities/GroundItem.tscn").instantiate()
	it_coin.item = {"kind": "coin", "itemId": "coin", "gold": 5, "count": 1}
	loot_root.add_child(it_coin)
	await get_tree().process_frame
	_expect(pilot._can_pick(it_coin), "金币不受背包容量限制，应仍可拾取")

	game.queue_free()
	await get_tree().process_frame
	GameState.reset_to_defaults()

## M1-10：存档落地（10.3 记录清单 / 原子写入 / 备份 / T16 损坏恢复）。
## 契约：① 存→退→进后 等级 / 经验 / 金币 / 地图 / 背包实例 / 已穿戴实例 / 坐标 / 任务状态 全部一致；
##       ② 主档损坏 → 自动回退备份并自愈；③ 主档 + 备份都坏 → 明确失败（不静默）；
##       ④ 删除清干净；⑤ 旧档缺字段按默认值补齐；⑥ 运行态自动战斗开关不落档（10.3）。
## 说明：用 3 号槽做实验，测试前快照、测试后原样写回，不碰玩家 1 / 2 号槽。
func _test_save() -> void:
	const SLOT := 3
	var prev_active: int = SaveManager.active_slot
	var snap := _snapshot_saves(SLOT)
	SaveManager.delete_slot(SLOT)

	# ---- ① 空槽语义：读取失败但给出明确说明（不静默）----
	_expect(not SaveManager.has_slot(SLOT), "删除后该槽应视为空")
	var empty_read := SaveManager.read_slot(SLOT)
	_expect(not bool(empty_read.get("ok", false)), "空槽读取应失败")
	_expect(not String(empty_read.get("message", "")).is_empty(), "空槽读取应给出明确说明")

	# ---- 构造一份有内容的进度（等级 / 经验 / 背包实例 / 已穿戴实例 / 坐标 / 任务状态）----
	GameState.reset_to_defaults()
	GameState.player.level = 7
	GameState.player.xp = 33
	GameState.player.attack = 24
	GameState.player.defense = 11
	GameState.player.hp = 90
	GameState.player.mp = 12
	GameState.gold = 1234
	GameState.current_map = "camp"
	GameState.quest_states = {"Q002": {"state": "active", "progress": 2}, "Q003": {"state": "rewarded", "progress": 3}}
	GameState.first_clear = {"boss_corrupt_beast": true}
	GameState.unlocks = {"chapter2": true}
	Fog.reveal("camp", Vector2i(0, 0))
	Fog.reveal("wild_trial", Vector2i(59, 59))
	var expected_explored := Fog.encode()
	GameState.settings["searchRadius"] = 15
	GameState.inventory[0] = _equip_instance("weapon_starter", "sv_1", {"atk": 5})
	GameState.inventory[1] = {"kind": "potion", "itemId": "potion_hp_small", "count": 3}
	GameState.warehouse_expansions = 1
	GameState.warehouse = Warehouse.create(1)
	GameState.warehouse[0] = _equip_instance("weapon_starter", "sv_store", {"atk": 9}, [{"stat": "def", "value": 2}])
	GameState.warehouse[1] = {"kind": "potion", "itemId": "potion_mp_small", "count": 7}
	GameState.equipment["weapon"] = _equip_instance("weapon_wolfking", "sv_worn", {"atk": 12},
		[{"stat": "atk", "value": 6}])
	GameState.save_pos = Vector2(123.5, -456.25)
	GameState.has_save_pos = true
	GameState.set_auto_battle(true)          # 运行态开关：不应被存档带过重启（10.3）

	var expected_worn: Dictionary = (GameState.equipment["weapon"] as Dictionary).duplicate(true)
	var expected_bag0: Dictionary = (GameState.inventory[0] as Dictionary).duplicate(true)
	var expected_store: Dictionary = (GameState.warehouse[0] as Dictionary).duplicate(true)
	var expected_store_potion: Dictionary = (GameState.warehouse[1] as Dictionary).duplicate(true)
	var expected_quests: Dictionary = GameState.quest_states.duplicate(true)
	var expected_atk := GameState.total_attack()

	SaveManager.set_active_slot(SLOT)
	_expect(SaveManager.save_slot(SLOT, true), "保存应成功")
	_expect(SaveManager.has_slot(SLOT), "保存后应存在存档文件")
	SaveManager.save_slot(SLOT, true)        # 再存一次 → 产生一份最近有效备份（10.3）

	# ---- 摘要（9.4 存档卡：角色名 / 等级 / 地图 / 存档时间）----
	var sum := SaveManager.slot_summary(SLOT)
	_expect(bool(sum.get("ok", false)), "存档摘要应可用：%s" % String(sum.get("message", "")))
	_expect(int(sum.get("level", 0)) == 7, "摘要等级应为 7，实际 %d" % int(sum.get("level", 0)))
	_expect(int(sum.get("gold", 0)) == 1234, "摘要金币应为 1234，实际 %d" % int(sum.get("gold", 0)))
	_expect(int(sum.get("worn", 0)) == 1, "摘要应记录 1 件已穿戴，实际 %d" % int(sum.get("worn", 0)))
	_expect(int(sum.get("inventoryUsed", 0)) == 2,
		"摘要应记录 2 格背包占用，实际 %d" % int(sum.get("inventoryUsed", 0)))
	_expect(String(sum.get("mapName", "")) == "幸存者营地",
		"摘要地图名应取自 maps.json，实际 %s" % String(sum.get("mapName", "")))
	_expect(not String(sum.get("savedAt", "")).is_empty(), "摘要应含存档时间")
	_expect(String(sum.get("savedAt", "")).find("T") < 0, "存档时间应已格式化为可读形式")

	# ---- ② 退出（重置）→ 重进（读档）后逐字段一致 ----
	GameState.reset_to_defaults()
	_expect(GameState.gold == 0 and int(GameState.player.level) == 1, "重置后应回到初始状态")

	var res := SaveManager.read_slot(SLOT)
	_expect(bool(res.get("ok", false)), "读档应成功")
	_expect(String(res.get("source", "")) == "main", "正常读档来源应为主档")
	SaveManager.apply_to_game_state(res.get("data", {}))

	_expect(int(GameState.player.level) == 7, "读档后等级应为 7，实际 %d" % int(GameState.player.level))
	_expect(int(GameState.player.xp) == 33, "读档后经验应为 33，实际 %d" % int(GameState.player.xp))
	_expect(int(GameState.player.attack) == 24, "读档后基础攻击应为 24")
	_expect(int(GameState.player.defense) == 11, "读档后基础防御应为 11")
	_expect(int(GameState.player.hp) == 90, "读档后当前 HP 应为 90，实际 %d" % int(GameState.player.hp))
	_expect(int(GameState.player.mp) == 12, "读档后当前 MP 应为 12，实际 %d" % int(GameState.player.mp))
	_expect(GameState.gold == 1234, "读档后金币应为 1234，实际 %d" % GameState.gold)
	_expect(GameState.current_map == "camp", "读档后地图应一致")
	_expect(_deep_equal(GameState.quest_states, expected_quests),
		"读档后任务状态应逐键一致（含嵌套 state/progress）：\n  存档时：%s\n  读档后：%s"
		% [str(expected_quests), str(GameState.quest_states)])
	_expect(bool(GameState.first_clear.get("boss_corrupt_beast", false)), "读档后首杀标记应一致")
	_expect(bool(GameState.unlocks.get("chapter2", false)), "读档后解锁标记应一致（M2 新增字段）")
	_expect(int(GameState.settings.get("searchRadius", 0)) == 15, "读档后设置项应一致")

	# 背包：实例（含 int 化的数值字段）逐字段一致 + 堆叠数正确
	var idx := _index_of_instance("sv_1")
	_expect(idx >= 0, "读档后背包装备应还原")
	if idx >= 0:
		_expect(_deep_equal(GameState.inventory[idx], expected_bag0),
			"读档后背包实例应逐字段一致（10.1 不重随）：\n  存档时：%s\n  读档后：%s"
			% [str(expected_bag0), str(GameState.inventory[idx])])
	_expect(String(GameState.inventory[1].get("itemId", "")) == "potion_hp_small",
		"读档后药水应还原")
	_expect(int(GameState.inventory[1].get("count", 0)) == 3,
		"读档后药水堆叠应为 3（JSON 数字需回落为 int），实际 %d"
		% int(GameState.inventory[1].get("count", 0)))
	_expect(GameState.warehouse_expansions == 1 and GameState.warehouse.size() == 50
		and _deep_equal(GameState.warehouse[0], expected_store)
		and _deep_equal(GameState.warehouse[1], expected_store_potion),
		"读档后仓库扩容、装备及药品数量应保持不变")

	# 已穿戴实例：逐字段一致，且加成立即生效（T06）
	_expect(_deep_equal(GameState.equipment["weapon"], expected_worn),
		"读档后已穿戴实例应逐字段一致（10.1）：\n  存档时：%s\n  读档后：%s"
		% [str(expected_worn), str(GameState.equipment["weapon"])])
	_expect(GameState.total_attack() == expected_atk,
		"读档后总攻击应为 %d，实际 %d" % [expected_atk, GameState.total_attack()])

	# 坐标（10.3 当前地图与坐标）
	_expect(GameState.has_save_pos, "读档后应带出生坐标")
	_expect(GameState.save_pos.is_equal_approx(Vector2(123.5, -456.25)),
		"读档后坐标应一致，实际 %s" % str(GameState.save_pos))

	_expect(_deep_equal(Fog.encode(), expected_explored), "读档后各图探索区块应完整一致")

	# ---- ③ 运行态开关不落档（10.3：重启后自动战斗默认关闭）----
	_expect(not GameState.auto_battle_on, "读档后自动战斗应默认关闭（运行态开关不持久化）")

	# ---- ④ 存 → 退 → 进（续档链路，10.3 继续）----
	GameState.reset_to_defaults()
	_expect(SaveManager.resume_last(), "重启后应能继续上次存档（last_slot）")
	_expect(int(GameState.player.level) == 7 and GameState.gold == 1234, "续档后进度应一致")

	# ---- ⑤ T16：主档损坏 → 回退备份并自愈 ----
	var path := SaveManager.slot_path(SLOT)
	_write_raw(path, "{ 这不是合法 JSON")
	var from_bak := SaveManager.read_slot(SLOT)
	_expect(bool(from_bak.get("ok", false)), "主档损坏时应能回退备份（T16）：%s"
		% String(from_bak.get("message", "")))
	_expect(String(from_bak.get("source", "")) == "backup", "恢复来源应为备份，实际 %s"
		% String(from_bak.get("source", "")))
	_expect(int((from_bak.get("data", {}) as Dictionary).get("gold", 0)) == 1234,
		"从备份恢复的金币应与最近有效存档一致")
	_expect(FileAccess.file_exists(path + ".corrupt"), "损坏的主档应另存为 .corrupt 保留现场")
	var healed := SaveManager.read_slot(SLOT)
	_expect(String(healed.get("source", "")) == "main", "恢复后应回到主档路径（已自愈）")

	# 结构非法（合法 JSON 但不是存档）同样判为损坏
	_write_raw(path, JSON.stringify({"schemaVersion": 1}))
	_write_raw(SaveManager.backup_path(SLOT), JSON.stringify({"schemaVersion": 1}))
	var dead := SaveManager.read_slot(SLOT)
	_expect(not bool(dead.get("ok", false)), "主档与备份都不是合法存档时应明确失败")
	_expect(not String(dead.get("message", "")).is_empty(), "损坏时应给出明确说明（不静默）")

	# ---- ⑥ 旧档导入：缺字段按默认值补齐 ----
	SaveManager.delete_slot(SLOT)            # 先清掉上一轮的 .bak / .corrupt 等旁文件
	_write_raw(path, JSON.stringify({"schemaVersion": 0, "player": {"level": 3}, "gold": 5}))
	var old_res := SaveManager.read_slot(SLOT)
	_expect(bool(old_res.get("ok", false)), "缺字段的旧档应可读取（旧档导入）")
	SaveManager.apply_to_game_state(old_res.get("data", {}))
	_expect(GameState.explored_maps.is_empty(), "旧档缺探索字段必须清空，不能沿用上一槽")
	_expect(int(GameState.player.level) == 3, "旧档已有字段应保留（等级 3）")
	_expect(int(GameState.player.attack) == int(GameState.default_player()["attack"]),
		"旧档缺失字段应补默认值（攻击 %d）" % int(GameState.default_player()["attack"]))
	_expect(GameState.inventory.size() == GameState.INVENTORY_SIZE, "旧档无背包字段时应补空背包")
	_expect(GameState.equipment.size() == Equipment.SLOT_DEFS.size(), "旧档无装备字段时应补空槽")
	_expect(GameState.warehouse.size() == 40 and GameState.warehouse_expansions == 0,
		"旧档无仓库字段时应补 40 个空格")
	_expect(not GameState.has_save_pos, "旧档无坐标字段时应回退地图中心出生")

	# ---- ⑦ 删除：清干净（主档 / 备份 / 临时 / 损坏现场）----
	SaveManager.delete_slot(SLOT)
	_expect(not FileAccess.file_exists(path), "删除后主档应移除")
	_expect(not FileAccess.file_exists(path + ".bak"), "删除后备份应移除")
	_expect(not FileAccess.file_exists(path + ".corrupt"), "删除后损坏现场应移除")
	_expect(not SaveManager.has_slot(SLOT), "删除后 has_slot 应为 false")

	# 还原现场（不污染玩家真实存档）
	_restore_saves(SLOT, snap)
	SaveManager.active_slot = prev_active
	GameState.reset_to_defaults()

	# ---- ⑧ 读档坐标 → 世界出生点（10.3「当前地图与坐标」）----
	GameState.save_pos = Vector2(400.0, -400.0)
	GameState.has_save_pos = true
	var game: Node = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	var player: Node2D = game.get_node("Entities/Player")
	var ground: IsoGround = game.get_node("Ground")
	var expected := ground.clamp_to_map(Vector2(400.0, -400.0))
	_expect(player.global_position.is_equal_approx(expected),
		"读档后玩家应出生在存档坐标而非地图中心：pos=%s expected=%s"
		% [str(player.global_position), str(expected)])
	_expect(not player.global_position.is_equal_approx(ground.get_map_center_world()),
		"读档出生点不应等于地图中心（说明坐标未被消费）")
	_expect(not GameState.has_save_pos, "出生坐标应在读档出生后被消费一次清空")

	# 坏档 / 越界坐标容错：应被夹回地图范围内（不把玩家扔到墙外）
	var far := ground.clamp_to_map(Vector2(999999.0, -999999.0))
	var gfar := Iso.world_to_grid(far)
	_expect(gfar.x >= 0.0 and gfar.x <= float(ground.grid_size.x)
		and gfar.y >= 0.0 and gfar.y <= float(ground.grid_size.y),
		"越界坐标应被夹回地图范围，实际网格坐标 %s" % str(gfar))

	game.queue_free()
	await get_tree().process_frame
	GameState.reset_to_defaults()

# ---- 存档测试辅助：快照 / 还原 3 号槽与 last_slot（避免污染玩家真实存档）----

func _snapshot_saves(slot: int) -> Dictionary:
	var out := {"__last__": ""}
	if FileAccess.file_exists(SaveManager.LAST_SLOT_FILE):
		var lf := FileAccess.open(SaveManager.LAST_SLOT_FILE, FileAccess.READ)
		if lf != null:
			out["__last__"] = lf.get_as_text()
			lf.close()
	for suffix in ["", ".bak", ".tmp", ".corrupt"]:
		var p: String = SaveManager.slot_path(slot) + suffix
		if FileAccess.file_exists(p):
			var f := FileAccess.open(p, FileAccess.READ)
			if f != null:
				out[suffix] = f.get_as_text()
				f.close()
	return out

func _restore_saves(slot: int, snap: Dictionary) -> void:
	SaveManager.delete_slot(slot)
	for key in snap.keys():
		var txt := String(snap[key])
		var path: String = SaveManager.LAST_SLOT_FILE if String(key) == "__last__" \
			else SaveManager.slot_path(slot) + String(key)
		if txt.is_empty():
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)
		else:
			_write_raw(path, txt)

func _write_raw(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("[SmokeTest] 无法写入测试文件：%s" % path)
		return
	f.store_string(text)
	f.close()

# ---- M2.5 消耗品使用与自动喝药（工程文档 12 R7）----

## 放入一瓶药水，返回其格位。
func _put_potion(item_id: String, count: int = 1) -> int:
	return _put_item({"kind": "potion", "itemId": item_id, "count": count})

## 某格堆叠数（格为空 / 越界返回 -1）。
func _stack_at(index: int) -> int:
	if index < 0 or index >= GameState.inventory.size():
		return -1
	var it = GameState.inventory[index]
	if not (it is Dictionary):
		return -1
	return int((it as Dictionary).get("count", 1))

func _test_consumable() -> void:
	GameState.reset_to_defaults()

	# ① 数据齐备（5.11：红蓝 × 小中大，含恢复量与独立冷却）
	for pid in ["potion_hp_small", "potion_hp_mid", "potion_hp_large",
			"potion_mp_small", "potion_mp_mid", "potion_mp_large"]:
		var tpl0 = DataLoader.get_entry("potions", pid)
		_expect(tpl0 is Dictionary, "缺少药水模板 %s" % pid)
		if tpl0 is Dictionary:
			_expect(int(tpl0.get("restoreAmount", 0)) > 0, "%s 应配置 restoreAmount" % pid)
			_expect(float(tpl0.get("cooldown", 0.0)) > 0.0, "%s 应配置 cooldown" % pid)

	# ② 使用入口：药水回血 + 扣堆叠（M2.5 之前这一步会报「无法装备」）
	GameState.player.hp = 1
	var ri := _put_potion("potion_hp_small", 2)
	_expect(ri >= 0, "应能放入红药")
	var hp0 := int(GameState.player.hp)
	var r1 := GameState.use_item(ri)
	_expect(bool(r1.get("ok", false)), "使用红药应成功：%s" % r1.get("reason", ""))
	_expect(int(GameState.player.hp) == hp0 + 80,
		"小红药应回 80 生命，实际 %d" % int(GameState.player.hp))
	_expect(_stack_at(ri) == 1, "使用后堆叠应由 2 减到 1，实际 %d" % _stack_at(ri))

	# ③ 冷却阻塞（5.11：每类独立冷却）
	_expect(Consumable.cd_of("potion_hp_small") > 0.0, "使用后应进入冷却")
	var r2 := GameState.use_item(ri)
	_expect(not bool(r2.get("ok", false)), "冷却中不应再次使用")
	_expect(String(r2.get("reason", "")).contains("冷却"),
		"冷却拒绝原因应含「冷却」，实际：%s" % r2.get("reason", ""))
	_expect(_stack_at(ri) == 1, "冷却被拒不应扣药")

	# ④ 跨种类互不阻塞：红药冷却中，蓝药仍可独立使用
	GameState.player.mp = 1
	var bi := _put_potion("potion_mp_small", 1)
	var r3 := GameState.use_item(bi)
	_expect(bool(r3.get("ok", false)),
		"红药冷却中时蓝药应仍可独立使用：%s" % r3.get("reason", ""))
	_expect(Consumable.cd_of("potion_mp_small") > 0.0, "蓝药应各自进冷却")
	_expect(Consumable.cd_of("potion_hp_small") > 0.0, "红药冷却不应被蓝药影响")

	# ⑤ 超量恢复按缺口截断（5.11：不超过上限）
	Consumable.reset()
	GameState.player.hp = GameState.max_hp() - 10
	var ti := _put_potion("potion_hp_large", 1)
	var r4 := GameState.use_item(ti)
	_expect(bool(r4.get("ok", false)), "大红药应可用")
	_expect(int(GameState.player.hp) == GameState.max_hp(),
		"超量恢复应截断到上限，实际 %d/%d" % [int(GameState.player.hp), GameState.max_hp()])
	_expect(int(r4.get("restored", 0)) == 10,
		"restored 应等于缺口 10，实际 %d" % int(r4.get("restored", 0)))

	# ⑥ 满值不浪费：不扣药、不进冷却（R-e）
	Consumable.reset()
	GameState.player.hp = GameState.max_hp()
	var fi := _put_potion("potion_hp_small", 1)
	var r5 := GameState.use_item(fi)
	_expect(not bool(r5.get("ok", false)), "满血不应允许喝药")
	_expect(Consumable.cd_of("potion_hp_small") == 0.0, "满血被拒不应进入冷却（R-e）")
	_expect(_stack_at(fi) == 1, "满血被拒不应扣药")

	# ⑦ 耗尽移除格
	Consumable.reset()
	GameState.player.hp = 1
	var li := _put_potion("potion_hp_small", 1)
	var used0 := GameState.inventory_used()
	var r6 := GameState.use_item(li)
	_expect(bool(r6.get("ok", false)), "最后一瓶应可用")
	_expect(GameState.inventory[li] == null, "耗尽后该格应清空")
	_expect(GameState.inventory_used() == used0 - 1, "耗尽后占用应 -1")

	# ⑧ R-b 回归：use_item 必须按 kind 分流 —— 双击装备仍应穿戴
	Consumable.reset()
	var ei := _put_item(_equip_instance("weapon_starter", "cm_equip", {"atk": 3}))
	var r7 := GameState.use_item(ei)
	_expect(bool(r7.get("ok", false)), "双击装备应仍可穿戴（R-b）：%s" % r7.get("reason", ""))
	_expect(GameState.equipment.get("weapon") != null, "装备应已进入武器槽")

	# ⑨ 非可用品类明确拒绝且不吞物品（不静默）
	var qi := _put_item({"kind": "quest", "itemId": "spirit_shard", "count": 1})
	var r8 := GameState.use_item(qi)
	_expect(not bool(r8.get("ok", false)), "任务物品不应可「使用」")
	_expect(qi >= 0 and GameState.inventory[qi] != null, "被拒的物品不应消失")

	# ⑩ Q1 选瓶策略（纯函数）：够用的最小档优先；均不足则取最大档
	var cands := [{"index": 0, "amount": 80}, {"index": 1, "amount": 220}, {"index": 2, "amount": 500}]
	_expect(Consumable.choose_candidate(60, cands) == 0, "缺口 60 应选 80 的小药（Q1）")
	_expect(Consumable.choose_candidate(100, cands) == 1, "缺口 100 应跳过 80 选 220（Q1）")
	_expect(Consumable.choose_candidate(900, cands) == 2, "缺口超过所有档时应取最大档")
	_expect(Consumable.choose_candidate(60, []) == -1, "无候选应返回 -1")

	# ⑪ pick_index：缺口大 → 中药；缺口小 → 小药；冷却中的小药被跳过
	GameState.reset_to_defaults()
	GameState.player.hp = 1
	var si := _put_potion("potion_hp_small", 1)
	var mi := _put_potion("potion_hp_mid", 1)
	_expect(Consumable.pick_index(Consumable.KIND_RED) == mi,
		"缺口大于小药恢复量时应选中药（实际 %d / 中药 %d / 小药 %d）"
			% [Consumable.pick_index(Consumable.KIND_RED), mi, si])
	GameState.player.hp = GameState.max_hp() - 60
	_expect(Consumable.pick_index(Consumable.KIND_RED) == si, "缺口 60 应选小药（够用最小档）")
	Consumable._cd["potion_hp_small"] = 5.0
	_expect(Consumable.pick_index(Consumable.KIND_RED) == mi, "冷却中的小药应被跳过")
	Consumable.reset()

	# ⑫ 背包 tooltip 文案（R3）：药水显示恢复量 / 冷却 / 使用方式；任务物说明不可使用
	var panel = load("res://scenes/ui/InventoryPanel.tscn").instantiate()
	add_child(panel)
	await get_tree().process_frame
	var tip := String(panel._bag_tooltip({"kind": "potion", "itemId": "potion_hp_small", "count": 1}))
	_expect(tip.contains("恢复 80"), "药水 tooltip 应显示恢复量：%s" % tip)
	_expect(tip.contains("冷却"), "药水 tooltip 应显示冷却：%s" % tip)
	_expect(tip.contains("双击使用"), "药水 tooltip 应提示「双击使用」：%s" % tip)
	var tip2 := String(panel._bag_tooltip({"kind": "quest", "itemId": "spirit_shard", "count": 1}))
	_expect(tip2.contains("不可使用"), "任务物品 tooltip 应说明不可使用：%s" % tip2)
	panel.queue_free()

	GameState.reset_to_defaults()

## 存储结构深比较：键集相同 + 逐键相等。
## 注意 JSON 往返会**改变字典的键顺序**（解析后按键排序），故不能用 str() 比较。
func _deep_equal(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		return false
	match typeof(a):
		TYPE_DICTIONARY:
			var da: Dictionary = a
			var db: Dictionary = b
			if da.size() != db.size():
				return false
			for k in da.keys():
				if not db.has(k) or not _deep_equal(da[k], db[k]):
					return false
			return true
		TYPE_ARRAY:
			var aa: Array = a
			var ab: Array = b
			if aa.size() != ab.size():
				return false
			for i in range(aa.size()):
				if not _deep_equal(aa[i], ab[i]):
					return false
			return true
		_:
			return a == b

## 按 id 取 skills.json 中的一条技能定义（不存在返回空字典）。
func _skill_by_id(skills: Array, skill_id: String) -> Dictionary:
	for s in skills:
		if s is Dictionary and String(s.get("id", "")) == skill_id:
			return s
	return {}

## 构造一件装备实例（10.1：实例自带属性，永不重随）。
func _equip_instance(item_id: String, inst_id: String, base_attrs: Dictionary,
		affixes: Array = []) -> Dictionary:
	return {
		"kind": "equip", "itemId": item_id, "instanceId": inst_id,
		"quality": "common", "level": 1,
		"baseAttrs": base_attrs, "affixes": affixes, "pctAttrs": [],
		"star": 0, "count": 1,
	}

## 放入背包首个空位，返回索引（-1 = 无空位）。
func _put_item(item: Dictionary) -> int:
	for i in range(GameState.inventory.size()):
		if GameState.inventory[i] == null:
			GameState.inventory[i] = item
			return i
	return -1

## 背包中指定实例 id 的格位（-1 = 不存在）。
func _index_of_instance(instance_id: String) -> int:
	for i in range(GameState.inventory.size()):
		var it = GameState.inventory[i]
		if it is Dictionary and String(it.get("instanceId", "")) == instance_id:
			return i
	return -1

## 背包内是否含指定模板 id 的物品（M2 任务奖励断言用）。
func _has_item_id(item_id: String) -> bool:
	for it in GameState.inventory:
		if it is Dictionary and String(it.get("itemId", "")) == item_id:
			return true
	return false

# ---- 开发期测试便利：测试武器必须与掉落池隔离（防污染回归）----
func _test_debug_seed() -> void:
	var id := "debug_blade_overpower"
	var tpl = DataLoader.get_entry("equipments", id)
	_expect(tpl is Dictionary, "缺少开发期测试武器模板 %s" % id)
	if tpl is Dictionary:
		_expect(bool(tpl.get("debug", false)), "测试武器模板应带 debug 标记（否则会进掉落池）")
		_expect(String(tpl.get("slot", "")) == "weapon", "测试武器应为 weapon 槽")
		_expect(int((tpl.get("baseAttrs", {}) as Dictionary).get("atk", 0)) >= 100,
			"测试武器攻击应显著高于普通装备")

	# 抽取 500 次野生掉落：测试武器一次都不应出现（Loot 跳过 debug 模板）
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261011
	var hits := 0
	for _i in range(500):
		for it in Loot.roll("DT_Wild_L1", rng):
			if it is Dictionary and String(it.get("itemId", "")) == id:
				hits += 1
	_expect(hits == 0, "测试武器不应出现在掉落中（命中 %d 次）" % hits)

# ============================================================================
# M2 任务系统（R9；产品文档 08 / 工程文档 11）
# ============================================================================

# ---- M2-1 / M2-3 / M2-5：主线链 Q001–Q005 全流程（接取 → 推进 → 完成 → 交付 → 前置解锁）----
func _test_quest_chain() -> void:
	GameState.reset_to_defaults()
	# M3-1 恢复清单（工程文档 13 §6 R5）：Q002–Q004 的 mapScope 已还原为 ["wild_trial"]，
	# 故推进前必须把当前地图切到该图，否则 Quest._in_scope 校验会拒绝计数。
	GameState.current_map = "wild_trial"

	# ① 状态推导：Q001 可接（prev 空）；Q002 前置未完成 → locked；二者均不落档
	_expect(Quest.state_of("Q001") == Quest.STATE_AVAILABLE, "Q001 初始应可接取")
	_expect(Quest.state_of("Q002") == Quest.STATE_LOCKED, "Q002 前置未完成应锁定")
	_expect(GameState.quest_states.is_empty(), "locked / available 不应落档（由 prev 链推导）")

	# ② 接取 Q001（talk 类，接取即达标 → completed，D4-A）
	var r1 := Quest.accept("Q001")
	_expect(bool(r1.get("ok", false)), "接取 Q001 应成功：%s" % r1.get("reason", ""))
	_expect(Quest.state_of("Q001") == Quest.STATE_COMPLETED,
		"talk 类目标接取即达标，实际 %s" % Quest.state_of("Q001"))

	# ③ 交付 Q001：50 金币 + weapon_starter 入包；Q002 随之解锁
	var d1 := Quest.deliver("Q001")
	_expect(bool(d1.get("ok", false)), "交付 Q001 应成功：%s" % d1.get("reason", ""))
	_expect(Quest.state_of("Q001") == Quest.STATE_REWARDED, "Q001 交付后应置 rewarded")
	_expect(GameState.gold == 50, "Q001 奖励应为 50 金币，实际 %d" % GameState.gold)
	_expect(_has_item_id("weapon_starter"), "背包应含 Q001 奖励武器 weapon_starter")
	_expect(Quest.state_of("Q002") == Quest.STATE_AVAILABLE, "Q001 交付后 Q002 应解锁")

	# ④ Q002：击杀 5 只腐化野狼（monster_died 推进，逐次计数）
	_expect(bool(Quest.accept("Q002").get("ok", false)), "Q002 应可接取")
	_expect(Quest.state_of("Q002") == Quest.STATE_ACTIVE, "Q002 接取后应 active")
	for _i in range(4):
		Quest.on_event("monster_died", "wolf_corrupted")
	_expect(int(Quest.progress_of("Q002").get("cur", 0)) == 4,
		"Q002 应计数 4，实际 %d" % int(Quest.progress_of("Q002").get("cur", 0)))
	Quest.on_event("monster_died", "wolf_corrupted")            # 第 5 只 → 达标
	_expect(Quest.state_of("Q002") == Quest.STATE_COMPLETED, "打满 5 只后应 completed")
	Quest.on_event("monster_died", "wolf_corrupted")            # 08 §8.1：达标后不再计数
	_expect(int(Quest.progress_of("Q002").get("cur", 0)) == 5, "达标后不应继续计数")
	Quest.deliver("Q002")
	_expect(GameState.gold == 150, "Q002 交付后金币应为 150，实际 %d" % GameState.gold)

	# ⑤ Q003：收集 3 个灵能碎片（item_picked 推进）
	_expect(bool(Quest.accept("Q003").get("ok", false)), "Q003 应可接取")
	# 目标不匹配的事件不应计数
	Quest.on_event("item_picked", "misc_firework")
	_expect(int(Quest.progress_of("Q003").get("cur", 0)) == 0, "非目标物品不应计数")
	for _i in range(3):
		Quest.on_event("item_picked", "spirit_shard")
	_expect(Quest.state_of("Q003") == Quest.STATE_COMPLETED, "收集 3 个碎片后应 completed")
	GameState.inventory = Inventory.create(40)                  # 腾空背包，确保奖励护甲可入包
	var d3 := Quest.deliver("Q003")
	_expect(bool(d3.get("ok", false)), "交付 Q003 应成功：%s" % d3.get("reason", ""))
	_expect(_has_item_id("armor_starter"), "背包应含 Q003 奖励护甲 armor_starter")

	# ⑥ Q004：击杀裂爪狼王 1 只
	_expect(Quest.state_of("Q004") == Quest.STATE_AVAILABLE, "Q003 交付后 Q004 应解锁")
	_expect(bool(Quest.accept("Q004").get("ok", false)), "Q004 应可接取")
	Quest.on_event("monster_died", "elite_wolf_king")
	_expect(Quest.state_of("Q004") == Quest.STATE_COMPLETED, "击杀狼王后应 completed")
	GameState.inventory = Inventory.create(40)
	Quest.deliver("Q004")
	_expect(_has_item_id("weapon_wolfking"), "背包应含 Q004 奖励 狼王之刃")

	# ⑦ Q005：击杀腐化巨兽 → 写 unlocks.chapter2（该任务 mapScope = corruption_source）
	GameState.current_map = "corruption_source"
	_expect(Quest.state_of("Q005") == Quest.STATE_AVAILABLE, "Q004 交付后 Q005 应解锁")
	_expect(bool(Quest.accept("Q005").get("ok", false)), "Q005 应可接取")
	Quest.on_event("monster_died", "boss_corrupted_beast")
	_expect(Quest.state_of("Q005") == Quest.STATE_COMPLETED, "击杀巨兽后应 completed")
	Quest.deliver("Q005")
	_expect(Quest.state_of("Q005") == Quest.STATE_REWARDED, "Q005 应置 rewarded")
	_expect(bool(GameState.unlocks.get("chapter2", false)), "Q005 应写入 unlocks.chapter2")

	# ⑧ 重复交付应被拒绝（08 §8.1：奖励不重复领）
	_expect(not bool(Quest.deliver("Q005").get("ok", false)), "已交付的任务不应重复领奖")

	GameState.reset_to_defaults()

# ---- M2-6 / R8：任务状态存档往返 + 老结构（String）防御性迁移 ----
func _test_quest_save() -> void:
	const SLOT := 3
	var prev_active: int = SaveManager.active_slot
	var snap := _snapshot_saves(SLOT)
	SaveManager.delete_slot(SLOT)

	GameState.reset_to_defaults()
	# M3-1：Q002 的 mapScope 已还原为 ["wild_trial"]，推进前必须切到该图（同 _test_quest_chain）
	GameState.current_map = "wild_trial"
	# 造一份混合局面：rewarded / active(带进度) + 解锁标记
	Quest.accept("Q001")
	Quest.deliver("Q001")
	Quest.accept("Q002")
	Quest.on_event("monster_died", "wolf_corrupted")
	Quest.on_event("monster_died", "wolf_corrupted")
	GameState.unlocks = {"chapter2": true}
	var expected: Dictionary = GameState.quest_states.duplicate(true)
	_expect(not expected.is_empty(), "应有任务状态可存")

	SaveManager.set_active_slot(SLOT)
	_expect(SaveManager.save_slot(SLOT, true), "任务存档应写入成功")

	# 存 → 退 → 进
	GameState.reset_to_defaults()
	_expect(GameState.quest_states.is_empty(), "重置后任务状态应清空")
	var res := SaveManager.read_slot(SLOT)
	_expect(bool(res.get("ok", false)), "任务存档应可读取")
	SaveManager.apply_to_game_state(res.get("data", {}))
	_expect(_deep_equal(GameState.quest_states, expected),
		"任务状态存读应逐字段一致（嵌套 state/progress）：\n  存档时：%s\n  读档后：%s"
		% [str(expected), str(GameState.quest_states)])
	_expect(Quest.state_of("Q002") == Quest.STATE_ACTIVE, "读档后 Q002 应仍为 active")
	_expect(int(Quest.progress_of("Q002").get("cur", 0)) == 2,
		"读档后 Q002 进度应保留 2，实际 %d" % int(Quest.progress_of("Q002").get("cur", 0)))
	_expect(bool(GameState.unlocks.get("chapter2", false)), "读档后 unlocks 应保留")

	# 老结构迁移：String 值 → {state, progress}；非法状态丢弃（R8 防御）
	var migrated := Quest.normalize_states({"Q001": "rewarded", "Q004": "active", "Q009": "bogus"})
	_expect(String((migrated.get("Q001", {}) as Dictionary).get("state", "")) == "rewarded",
		"老档 String 值应迁移为 {state, progress}")
	_expect(int((migrated.get("Q001", {}) as Dictionary).get("progress", -1)) == 0,
		"迁移后 progress 应为 0")
	_expect(not migrated.has("Q009"), "非法状态应被丢弃（不静默写坏）")

	# 还原现场（不污染玩家真实存档）
	SaveManager.delete_slot(SLOT)
	_restore_saves(SLOT, snap)
	SaveManager.active_slot = prev_active
	GameState.reset_to_defaults()

# ---- M2-5 / T05：升级保留 HP / MP 百分比（产品文档 4.3）----
func _test_level_up_carry() -> void:
	GameState.reset_to_defaults()
	var hp0 := GameState.max_hp()
	var mp0 := GameState.max_mp()
	# 当前值设为上限的 50%
	GameState.player.hp = int(round(float(hp0) * 0.5))
	GameState.player.mp = int(round(float(mp0) * 0.5))
	var ratio_hp := float(GameState.player.hp) / float(hp0)
	var ratio_mp := float(GameState.player.mp) / float(mp0)

	GameState.add_xp(GameState.xp_to_next(1))       # 恰好升 1 级
	_expect(int(GameState.player.level) == 2,
		"应升到 2 级，实际 %d" % int(GameState.player.level))
	_expect(GameState.max_hp() > hp0, "升级后最大生命应提高")
	var new_ratio_hp := float(GameState.player.hp) / float(GameState.max_hp())
	var new_ratio_mp := float(GameState.player.mp) / float(GameState.max_mp())
	_expect(absf(new_ratio_hp - ratio_hp) <= 0.02,
		"升级后 HP 百分比应保留（4.3）：升级前 %.3f，升级后 %.3f" % [ratio_hp, new_ratio_hp])
	_expect(absf(new_ratio_mp - ratio_mp) <= 0.02,
		"升级后 MP 百分比应保留（4.3）：升级前 %.3f，升级后 %.3f" % [ratio_mp, new_ratio_mp])
	GameState.reset_to_defaults()

# ---- M2-6 / 08 §8.2 §8.4：支线放弃 / 重接（计数清零）+ 同时接取上限 5 ----
func _test_quest_side() -> void:
	GameState.reset_to_defaults()

	# ① 支线可接取；主线不可放弃
	_expect(bool(Quest.accept("S001").get("ok", false)), "支线 S001 应可接取")
	_expect(Quest.state_of("S001") == Quest.STATE_ACTIVE, "S001 接取后应 active")
	_expect(not bool(Quest.abandon("Q001").get("ok", false)), "主线任务不可放弃（08 §8.2）")

	# ② 计数后放弃 → 计数清零
	Quest.on_event("monster_died", "shellback_bug")
	_expect(int(Quest.progress_of("S001").get("cur", 0)) == 1, "S001 应先计数 1")
	_expect(bool(Quest.abandon("S001").get("ok", false)), "支线应可放弃")
	_expect(Quest.state_of("S001") == Quest.STATE_ABANDONED, "放弃后应为 abandoned")
	_expect(int(Quest.progress_of("S001").get("cur", 0)) == 0, "放弃后计数应清零（08 §8.4）")

	# ③ 立即重接 → active，计数从 0 重新开始
	_expect(bool(Quest.accept("S001").get("ok", false)), "放弃后应可立即重接")
	_expect(Quest.state_of("S001") == Quest.STATE_ACTIVE, "重接后应回到 active")
	_expect(int(Quest.progress_of("S001").get("cur", 0)) == 0, "重接后计数应从 0 开始")

	# ④ 同时接取上限 5（08 §8.4）：临时注入 6 条可接任务
	GameState.reset_to_defaults()
	var quests_ref: Array = DataLoader.get_table("quests")
	for i in range(6):
		quests_ref.append({
			"id": "T_TMP%d" % i, "name": "临时任务 %d" % i, "type": "side", "giver": "elder",
			"objective": {"kind": "kill", "targetId": "training_dummy", "count": 1},
			"reward": {"gold": 1, "xp": 0}, "mapScope": ["camp"], "prev": "", "abandonable": true,
		})
	var ok_n := 0
	for i in range(6):
		if bool(Quest.accept("T_TMP%d" % i).get("ok", false)):
			ok_n += 1
	_expect(ok_n == 5, "同时接取上限应为 5，实际成功 %d 个" % ok_n)
	_expect(Quest.active_count() == 5, "active 数应封顶 5，实际 %d" % Quest.active_count())

	# 清理临时任务（避免污染后续用例）
	var kept: Array = []
	for q in quests_ref:
		if q is Dictionary and not String((q as Dictionary).get("id", "")).begins_with("T_TMP"):
			kept.append(q)
	quests_ref.clear()
	for q in kept:
		quests_ref.append(q)
	GameState.reset_to_defaults()

# ---- M1 世界装配：出生点 / 边界 / 怪物点 / NPC / 掉落容器（M1-5 / M1-6 / M1-8）----
func _test_world() -> void:
	GameState.reset_to_defaults()   # 保证发放测试武器时背包有空间
	var game: Node = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame   # 等 deferred 发放测试武器落地

	var ground: Node = game.get_node_or_null("Ground")
	var player: Node = game.get_node_or_null("Entities/Player")
	_expect(ground != null, "未找到 Ground 节点")
	_expect(player != null, "未找到 Player 节点")
	if ground == null or player == null:
		return

	var center: Vector2 = ground.get_map_center_world()
	_expect(player.global_position.is_equal_approx(center),
		"玩家未出生在地图中心：pos=%s center=%s" % [player.global_position, center])

	var bounds: Rect2 = ground.get_world_bounds()
	_expect(bounds.size.x > 0.0 and bounds.size.y > 0.0, "地图包围盒非法：%s" % [bounds])

	var boundary: Node = ground.get_node_or_null("Boundary")
	_expect(boundary != null, "未生成边界碰撞体")
	if boundary != null:
		_expect(boundary.get_child_count() == 4, "边界墙应为 4 段，实际 %d" % boundary.get_child_count())

	# M3-1：怪物点由 maps.json 的 spawnPoints 驱动（营地 = 3 只教学木桩，ai:false）
	var spawner: Node = game.get_node_or_null("Spawner")
	_expect(spawner != null, "未找到 Spawner 节点")
	if spawner != null:
		_expect(spawner.point_count() >= 3,
			"营地图怪物点应至少 3 个（教学木桩），实际 %d" % spawner.point_count())
		_expect(spawner.get_child_count() == spawner.point_count(),
			"每个怪物点都应生成实例：点=%d 实例=%d" % [spawner.point_count(), spawner.get_child_count()])

	# 开发期测试便利：开局应已把测试武器放进背包
	var debug_found := false
	for it in GameState.inventory:
		if it is Dictionary and String(it.get("itemId", "")) == "debug_blade_overpower":
			debug_found = true
	_expect(debug_found, "开发期测试武器未发放到背包")

	# M1-6：世界掉落容器
	var loot_root: Node = game.get_node_or_null("LootRoot")
	_expect(loot_root != null and loot_root.is_in_group("loot_root"), "缺少 LootRoot 掉落容器节点")

	# M3-1 / M3-2：营地图 NPC 由 maps.json 的 npcs 驱动（货郎 + 长老 + 车夫）与交互半径
	var npcs: Node = game.get_node_or_null("Npcs")
	_expect(npcs != null, "未找到 Npcs 节点")
	if npcs != null:
		var expected_npcs := MapService.current_npcs().size()
		_expect(npcs.get_child_count() == expected_npcs,
			"NPC 数应与 maps.json 的 npcs 一致（%d），实际 %d" % [expected_npcs, npcs.get_child_count()])
		var peddler: Npc = null
		var elder: Npc = null
		var carter: Npc = null
		for c in npcs.get_children():
			var n := c as Npc
			if n == null:
				continue
			if n.role == "quest":
				elder = n
			elif n.role == "carter":
				carter = n
			elif not n.shop_id.is_empty():
				peddler = n
		_expect(peddler != null, "应存在货郎 NPC（role=shop）")
		_expect(elder != null, "应存在任务官 NPC（role=quest，M2-2）")
		_expect(carter != null, "应存在车夫 NPC（role=carter，M3-2）")
		if elder != null:
			_expect(elder.npc_name == "长老", "任务官应名为长老，实际 %s" % elder.npc_name)
			_expect(elder.shop_id.is_empty(), "任务官不应绑定商店")
		if peddler != null:
			_expect(peddler.shop_id == "peddler_camp", "货郎应绑定 peddler_camp 商店")
			_expect(not peddler.npc_name.is_empty(), "货郎应有显示名")
			_expect(not peddler.is_player_in_range(), "出生点不应已在货郎交互范围内（避免开局误开面板）")
			(player as Node2D).global_position = peddler.global_position + Vector2(40.0, 0.0)
			await get_tree().process_frame
			_expect(game.nearest_npc() == peddler, "走进交互半径后应能定位到货郎（6.3）")

	# HUD 伤害飘字层分组
	var dn: Node = game.get_node_or_null("DamageNumbers")
	_expect(dn != null and dn.is_in_group("damage_numbers"), "DamageNumbers 节点缺少分组标记")
	game.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

## M3-1 / M3-2：地图数据、车夫拓扑与出行校验链（工程文档 13 §3 / §6 R5）。
func _test_map_travel() -> void:
	GameState.reset_to_defaults()

	# ① 地图数据与车夫拓扑（07 §7.8：营地 ⇄ 试炼野外；营地**不**直达灰烬之地）
	_expect(MapService.exists("camp") and MapService.exists("wild_trial"), "camp / wild_trial 地图应存在")
	_expect(MapService.display_name("camp") == "幸存者营地", "camp 显示名应为「幸存者营地」")
	_expect(MapService.is_linked("wild_trial"), "营地应可直达试炼野外")
	_expect(not MapService.is_linked("ash_land"), "营地不应直达灰烬之地（需中转，07 §7.8）")
	_expect(MapService.is_unlocked("wild_trial"), "无 requiresUnlock 的地图应恒为已解锁")
	_expect(MapService.fee_to("wild_trial") == 0, "营地→试炼野外应为免费（0）")

	# ② 目的地列表
	var dests: Array = MapService.destinations()
	_expect(dests.size() == 1, "营地车夫应有 1 条线路，实际 %d" % dests.size())
	if dests.size() > 0:
		var d0 := dests[0] as Dictionary
		_expect(String(d0.get("id", "")) == "wild_trial", "营地线路应为 wild_trial")
		_expect(int(d0.get("cost", -1)) == 0, "该线路费用应为 0")
		_expect(bool(d0.get("unlocked", false)), "该线路应已解锁")

	# ③ 拒绝分支：未知图 / 当前图 / 不连通 / 金币不足
	_expect(not bool(MapService.travel_to("no_such_map").get("ok", false)), "未知地图应拒绝")
	_expect(not bool(MapService.travel_to("camp").get("ok", false)), "已在当前图应拒绝")
	_expect(not bool(MapService.travel_to("ash_land").get("ok", false)), "不连通目的地应拒绝（需中转）")
	_expect(GameState.current_map == "camp", "被拒时不应改变当前地图")

	GameState.current_map = "wild_trial"
	_expect(MapService.fee_to("ash_land") == 50, "试炼野外→灰烬之地应为 50 金")
	GameState.gold = 10
	_expect(not bool(MapService.travel_to("ash_land").get("ok", false)), "金币不足应拒绝")
	_expect(GameState.gold == 10, "被拒时不应扣费，实际 %d" % GameState.gold)
	_expect(GameState.current_map == "wild_trial", "被拒时不应切图")

	# ④ 成功出行：扣费 + 写 current_map + 写落点（travel_to 本身不触发场景重载）
	GameState.gold = 100
	var res := MapService.travel_to("ash_land")
	_expect(bool(res.get("ok", false)), "金币足够时应放行：%s" % res.get("reason", ""))
	_expect(GameState.current_map == "ash_land", "成功后 current_map 应为 ash_land")
	_expect(GameState.gold == 50, "成功后应扣 50 金，实际 %d" % GameState.gold)
	_expect(GameState.has_save_pos, "成功后应写入落点供重载消费")
	_expect(MapService.display_name(GameState.current_map) == "灰烬之地", "落点地图名应为灰烬之地")

	# ⑤ Boss 点数据（M3-5 用；此处只验证数据可达与墓碑标记）
	_expect(MapService.current_boss().is_empty(), "灰烬之地不应有 Boss 点")
	GameState.current_map = "corruption_source"
	_expect(not MapService.current_boss().is_empty(), "腐化源头应配 Boss 点")
	_expect(bool(MapService.current_boss().get("tombstone", false)), "Boss 点应启用墓碑")

	GameState.reset_to_defaults()

## M3-1 / 验收场景 T15：切图重建 —— 新图按自身数据装配、落点正确、旧实体不残留。
## 做法：直接实例化 `Game.tscn` 模拟「重载后的世界」，对比营地与野外两套装配
## （真实重载行为 = 销毁旧 Game + `Game._ready` 按 `GameState.current_map` 重建，见 MapService 头注）。
func _test_map_reload() -> void:
	GameState.reset_to_defaults()

	# ① 营地世界：3 只教学木桩 + 3 个 NPC（货郎 / 长老 / 车夫）
	var camp_game: Node = load("res://scenes/Game.tscn").instantiate()
	add_child(camp_game)
	await get_tree().process_frame
	var camp_spawner: Node = camp_game.get_node_or_null("Spawner")
	var camp_npcs: Node = camp_game.get_node_or_null("Npcs")
	_expect(camp_spawner != null and camp_npcs != null, "营地世界装配缺失（Spawner / Npcs）")
	var camp_monsters := int(camp_spawner.point_count()) if camp_spawner != null else -1
	var camp_npc_n := int(camp_npcs.get_child_count()) if camp_npcs != null else -1
	_expect(camp_monsters == _expected_point_count("camp"),
		"营地怪物点数应为 %d，实际 %d" % [_expected_point_count("camp"), camp_monsters])
	Fog.reveal("camp", Vector2i.ZERO)
	var camp_explored: Array = Fog.encode().get("camp", []).duplicate()
	camp_game.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	# ② 切到试炼野外（模拟 MapService 的状态变更）后实例化新世界
	GameState.current_map = "wild_trial"
	# 注意：Game._ready 会**消费一次即清空** save_pos，故落点先存到局部变量再断言
	var target := MapService.entry_point("wild_trial")
	GameState.save_pos = target
	GameState.has_save_pos = true
	var wild_game: Node = load("res://scenes/Game.tscn").instantiate()
	add_child(wild_game)
	await get_tree().process_frame

	var ground: Node = wild_game.get_node_or_null("Ground")
	_expect(ground != null, "野外世界缺少 Ground")
	if ground != null:
		_expect(String(ground.map_id) == "wild_trial",
			"地面应加载到当前地图，实际 %s" % String(ground.map_id))
		_expect(ground.grid_size == Vector2i(60, 60),
			"试炼野外尺寸应为 60×60，实际 %s" % str(ground.grid_size))

	var spawner: Node = wild_game.get_node_or_null("Spawner")
	var npcs: Node = wild_game.get_node_or_null("Npcs")
	_expect(spawner != null and npcs != null, "野外世界装配缺失（Spawner / Npcs）")
	if spawner != null:
		_expect(int(spawner.point_count()) == _expected_point_count("wild_trial"),
			"野外怪物点数应为 %d，实际 %d" % [_expected_point_count("wild_trial"), spawner.point_count()])
		_expect(int(spawner.point_count()) != camp_monsters,
			"切图后怪物点数应与营地不同（营地 %d）" % camp_monsters)
	if npcs != null:
		_expect(int(npcs.get_child_count()) == _expected_npc_count("wild_trial"),
			"野外 NPC 数应为 %d，实际 %d" % [_expected_npc_count("wild_trial"), npcs.get_child_count()])
		_expect(int(npcs.get_child_count()) != camp_npc_n,
			"切图后 NPC 应重建（营地 %d）" % camp_npc_n)

	var player: Node = wild_game.get_node_or_null("Entities/Player")
	_expect(player != null, "野外世界缺少 Player")
	if player != null:
		_expect((player as Node2D).global_position.is_equal_approx(target),
			"玩家应落在切图落点：pos=%s 落点=%s" % [(player as Node2D).global_position, target])
	_expect(not GameState.has_save_pos, "落点应被消费一次即清空")
	_expect(_deep_equal(Fog.encode().get("camp", []), camp_explored), "进入野外不应改变营地探索")

	wild_game.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	GameState.gold = 100
	_expect(bool(MapService.travel_to("camp").ok), "回营地切图校验失败")
	var returned: Node = load("res://scenes/Game.tscn").instantiate()
	add_child(returned)
	await get_tree().process_frame
	_expect(_deep_equal(Fog.encode().get("camp", []), camp_explored), "返回营地后历史探索丢失")
	returned.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	GameState.reset_to_defaults()

## maps.json 的怪物点总数（count 展开 + Boss 点 1）。
func _expected_point_count(map_id: String) -> int:
	var m = DataLoader.get_entry("maps", map_id)
	if not (m is Dictionary):
		return -1
	var n := 0
	var pts = (m as Dictionary).get("spawnPoints", [])
	if pts is Array:
		for p in pts:
			if p is Dictionary:
				n += int((p as Dictionary).get("count", 1))
	var boss = (m as Dictionary).get("bossSpawn", null)
	if boss is Dictionary:
		n += 1
	return n

## maps.json 的 NPC 点数。
func _expected_npc_count(map_id: String) -> int:
	var m = DataLoader.get_entry("maps", map_id)
	if not (m is Dictionary):
		return -1
	var arr = (m as Dictionary).get("npcs", [])
	return arr.size() if arr is Array else 0

func _finish() -> void:
	if _failures.is_empty():
		print("[SmokeTest] 全部通过 ✅")
		get_tree().quit(0)
	else:
		for f in _failures:
			printerr("[SmokeTest] 失败：", f)
		get_tree().quit(1)

# ---- M3-3：探索、迁移与真实 UI 输入链 ----
func _test_fog() -> void:
	GameState.reset_to_defaults()
	_expect(not Fog.is_explored("camp", Vector2i(0, 0)), "新档不得已探索整图")
	_expect(Fog.reveal("camp", Vector2i(0, 0)), "首次揭示必须产生变化")
	_expect(Fog.is_explored("camp", Vector2i(8, 0)) and not Fog.is_explored("camp", Vector2i(12, 0)), "揭示半径/区块边缘不正确")
	var initial := Fog.encode().duplicate(true)
	_expect(not Fog.reveal("camp", Vector2i(0, 0)) and _deep_equal(initial, Fog.encode()), "重复揭示不应增长集合")
	_expect(not Fog.reveal("unknown", Vector2i.ZERO) and not Fog.reveal("camp", Vector2i(-1, 0)), "未知地图/越界不应揭示")
	Fog.reveal("corruption_source", Vector2i(49, 49))
	_expect(Fog.is_explored("corruption_source", Vector2i(49, 49)) and Fog.block_grid("corruption_source") == Vector2i(13, 13), "50格地图的不足四格边块丢失")
	var snapshot := Fog.encode()
	GameState.explored_maps = Fog.normalize(JSON.parse_string(JSON.stringify(snapshot)))
	_expect(_deep_equal(snapshot, Fog.encode()), "探索的JSON往返不一致")
	GameState.explored_maps = Fog.normalize({"wild_trial": [0.0, 0, 224, 225, -1, 1.5, "2", INF, NAN], "unknown": [0], "camp": 42})
	_expect(GameState.explored_maps.size() == 1 and GameState.explored_maps.wild_trial.size() == 2, "坏探索记录、重复或未知地图未清理")
	var legacy := SaveManager._collect()
	legacy.schemaVersion = 1
	legacy.erase("exploredMaps")
	legacy.player.level = 3
	legacy.gold = 17
	var old := SaveManager._migrate(legacy)
	SaveManager.apply_to_game_state(old)
	_expect(int(old.schemaVersion) == SaveManager.CURRENT_SCHEMA and GameState.explored_maps.is_empty() and GameState.gold == 17, "v1迁移探索状态泄漏或覆盖已有字段")
	var v2 := SaveManager._collect()
	v2.schemaVersion = 2
	v2.erase("warehouse")
	v2.erase("warehouseExpansions")
	_expect(SaveManager._is_valid_save(v2), "v2 旧档应可迁移新增仓库字段")
	SaveManager.apply_to_game_state(v2)
	_expect(GameState.warehouse.size() == 40 and GameState.warehouse_expansions == 0,
		"v2 迁移应获得空仓库且不覆盖其他进度")
	GameState.reset_to_defaults()

func _test_fog_ui() -> void:
	GameState.reset_to_defaults()
	GameState.current_map = "wild_trial"
	GameState.quest_states = {"Q002": {"state": "active", "progress": 0}}
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var panel: Control = main.get_node("UI/MapBigPanel")
	var canvas: MapCanvas = panel.get("_map")
	var player: PlayerCharacter = main.get_node("Game/Entities/Player")
	var world: Node = main.get_node("Game")
	var markers := MapMarkers.for_world(world)
	var targets := markers.filter(func(marker: Dictionary) -> bool: return marker.kind == "quest")
	_expect(targets.size() == 6 and targets.all(func(marker: Dictionary) -> bool: return marker.revealed), "接取狼任务未揭示六个实际刷新点")
	_expect(MapMarkers.drops_item("shellback_bug", "spirit_shard") and not MapMarkers.drops_item("training_dummy", "spirit_shard"), "收集标记没有按真实掉落表过滤")
	for monster: Node in get_tree().get_nodes_in_group("enemies"):
		monster.set_physics_process(false)
	panel.set_open(true)
	_expect(panel.visible and GameState.panel_open, "大地图未登记关闭式面板")
	var cell := Vector2(40, 34)
	var point := Iso.grid_pt(cell.x, cell.y)
	var canvas_point := canvas.world_to_canvas(point)
	_expect(canvas.canvas_to_grid(canvas_point).is_equal_approx(cell), "大小地图投影反算不一致")
	GameState.set_auto_battle(true)
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	mouse.position = canvas_point
	canvas._gui_input(mouse)
	_expect(not panel.visible and not GameState.panel_open and player.map_move_active, "大地图点击未关闭面板并发起真实移动")
	var before := player.global_position
	await get_tree().create_timer(0.5).timeout
	_expect(player.global_position.distance_to(before) > 10 and player.global_position.distance_to(point) < before.distance_to(point), "地图点击后角色未接近目的地")
	var pilot: AutoBattle = player.get_node("AutoPilot")
	_expect(pilot.get("_state") == AutoBattle.State.MANUAL_OVERRIDE, "地图行走被自动战斗抢占")
	panel.set_open(true)
	var held := player.global_position
	var manual_t := float(pilot.get("_manual_t"))
	await get_tree().create_timer(0.2).timeout
	_expect(player.global_position.is_equal_approx(held) and is_equal_approx(float(pilot.get("_manual_t")), manual_t), "打开地图后路线/接管计时未冻结")
	EventBus.panel_opened.emit("inventory")
	_expect(not panel.visible, "地图未与其他面板互斥")
	GameState.set_panel_open("inventory", false)
	player._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	await get_tree().create_timer(0.15).timeout
	_expect(player.global_position.is_equal_approx(held), "后台地图路线仍推进")
	player._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	GameState.set_auto_battle(false)
	Input.action_press("move_right")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("move_right")
	_expect(not player.map_move_active, "WASD未取消地图目的地")
	var signal_count := EventBus.fog_changed.get_connections().size()
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(EventBus.fog_changed.get_connections().size() == signal_count - 2, "销毁大小地图后探索信号残留")
	GameState.reset_to_defaults()

func _test_elite_affixes() -> void:
	GameState.reset_to_defaults()
	var scene := load("res://scenes/entities/Monster.tscn") as PackedScene
	var tpl: Dictionary = DataLoader.get_entry("monsters", "elite_wolf_king")
	var original := tpl.duplicate(true)
	var container := Node2D.new()
	add_child(container)
	var player := (load("res://scenes/entities/Player.tscn") as PackedScene).instantiate() as PlayerCharacter
	container.add_child(player)
	player.set_physics_process(false)
	for id in ["rage", "hard", "fast", "frost", "vampire", "summon"]:
		tpl.affixPool = [id]
		tpl.affixCount = [1, 1]
		var monster := scene.instantiate() as Monster
		monster.monster_id = "elite_wolf_king"
		container.add_child(monster)
		monster.set_physics_process(false)
		_expect(monster.active_affixes.size() == 1 and monster.display_name != original.name, "精英词缀及名称：" + id)
		match id:
			"rage":
				_expect(is_equal_approx(monster.attack_power, 18.2) and is_equal_approx(monster.attack_interval, 1.1 / 1.2), "狂暴攻击与攻速")
			"hard":
				_expect(is_equal_approx(monster.get_defense(), 12.0), "坚硬防御")
			"fast":
				_expect(is_equal_approx(monster.move_speed_px, 3.4 * 64 * 1.3), "迅捷移速")
			"frost":
				monster._apply_hit_effects(player, 10)
				player.apply_slow(0.2, 2.0)
				_expect(is_equal_approx(player.movement_multiplier(), 0.8), "寒霜不叠乘")
				player.auto_move = Vector2.RIGHT
				player._physics_process(0.1)
				_expect(is_equal_approx(player.velocity.x, 204.8), "寒霜影响实际自动移动速度")
				player._physics_process(2.1)
				_expect(is_equal_approx(player.movement_multiplier(), 1.0) and is_equal_approx(player.velocity.x, 256.0), "寒霜到期恢复")
				player.auto_move = Vector2.ZERO
			"vampire":
				monster.hp = 400
				monster._apply_hit_effects(player, 10)
				monster._apply_hit_effects(player, 10)
				_expect(monster.hp == 401, "吸血小数累计")
				monster._apply_hit_effects(player, 0)
				_expect(monster.hp == 401, "未实际扣血不能吸血")
				monster._apply_hit_effects(player, 10000)
				_expect(monster.hp == monster.max_hp, "吸血不超过上限")
				player._invuln = 1.0
				monster.hp = 400
				monster._do_attack(player)
				_expect(monster.hp == 400, "真实无敌帧阻断吸血")
			"summon":
				var before := container.get_child_count()
				monster._die()
				monster._die()
				await get_tree().process_frame
				_expect(container.get_child_count() == before + 2, "死亡只召唤两只一次")
				for child in container.get_children():
					if child is Monster and child != monster:
						_expect(child.monster_id == "wolf_corrupted" and child.active_affixes.is_empty(), "召唤普通怪禁止递归词缀")
						child.queue_free()
		monster.queue_free()
		await get_tree().process_frame
	tpl.clear()
	tpl.merge(original, true)
	var seen := {}
	for i in range(40):
		var monster := scene.instantiate() as Monster
		monster.monster_id = "elite_wolf_king"
		monster._rng.seed = i + 1
		monster._load_template()
		_expect(monster.active_affixes.size() >= 1 and monster.active_affixes.size() <= 2, "随机词缀数量")
		var unique := {}
		for effect in monster.active_affixes:
			unique[effect.id] = true
			seen[effect.id] = true
		_expect(unique.size() == monster.active_affixes.size(), "词缀不能重复")
		monster.free()
	_expect(seen.size() == 6 and tpl == original, "随机池覆盖六种且不改模板")
	var normal := scene.instantiate() as Monster
	normal._load_template()
	_expect(normal.active_affixes.is_empty() and normal.get_attack() == 8, "普通怪不受词缀影响")
	normal.free()
	tpl.affixPool = ["missing"]
	_expect(not DataLoader.validate_all().is_empty(), "未知词缀启动校验")
	tpl.affixPool = ["fast", "fast"]
	_expect(not DataLoader.validate_all().is_empty(), "重复词缀启动校验")
	tpl.clear()
	tpl.merge(original, true)
	var summon: Dictionary = DataLoader.get_entry("affixes", "summon")
	summon.summonId = "elite_wolf_king"
	_expect(not DataLoader.validate_all().is_empty(), "递归召唤配置被拒绝")
	summon.summonId = "wolf_corrupted"
	player.apply_slow(0.2, 2)
	player._begin_death()
	_expect(player.movement_multiplier() == 1.0, "死亡清理减速")
	container.queue_free()
	await get_tree().process_frame
	GameState.reset_to_defaults()

func _test_auto_hud_reload() -> void:
	GameState.reset_to_defaults()
	GameState.set_auto_battle(true)
	for map_id in ["camp", "wild_trial"]:
		GameState.current_map = map_id
		var main: Node = load("res://scenes/Main.tscn").instantiate()
		add_child(main)
		var player: PlayerCharacter = main.get_node("Game/Entities/Player")
		var pilot: AutoBattle = player.get_node("AutoPilot")
		pilot.set_physics_process(false)
		var hud: Control = main.get_node("UI/Hud")
		_expect(not String(hud.get_node("%AutoLabel").text).contains("关（F"), "切图后 HUD 应读取自动开关")
		pilot.begin_manual_override()
		pilot._physics_process(0.1)
		_expect(pilot.current_phase().contains("3 秒"), "恢复倒计时 3")
		pilot._physics_process(1.0)
		_expect(pilot.current_phase().contains("2 秒"), "恢复倒计时 2")
		pilot._physics_process(1.0)
		_expect(pilot.current_phase().contains("1 秒"), "恢复倒计时 1")
		GameState.set_panel_open("test", true)
		pilot._physics_process(1.0)
		_expect(is_equal_approx(pilot._manual_t, 0.9), "面板打开冻结恢复计时")
		GameState.set_panel_open("test", false)
		pilot._physics_process(1.0)
		_expect(pilot.current_state() != AutoBattle.State.MANUAL_OVERRIDE, "倒计时结束恢复决策")
		main.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	GameState.reset_to_defaults()
