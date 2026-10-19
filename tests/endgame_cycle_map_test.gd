extends Node
## 双循环图数据、入口与奖励契约测试；在隔离项目中运行，结束时恢复运行态。

var failures: Array[String] = []

## 记录失败条件，以便一次运行报告全部地图契约问题。
func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("[EndgameCycleMapTest] " + label)

## 验证等级与 14 槽紫装边界，不依赖真实玩家存档。
func _test_entry() -> void:
	GameState.current_map = "c7_arena"
	GameState.unlocks["campaign_complete"] = true
	GameState.player["level"] = 79
	check(not MapService.entry_gate_reason("c7_gold_field").is_empty(), "79 级无法进入金币图")
	GameState.player["level"] = 80
	check(MapService.entry_gate_reason("c7_gold_field").is_empty(), "80 级可从回廊进入金币图")
	check(not MapService.entry_gate_reason("c7_gold_field", "carter").is_empty(), "快捷旅行无法进入金币图")
	GameState.mark_visited("c7_gold_field")
	GameState.gold = 999999
	check(not bool(MapService.travel_anywhere("c7_gold_field").get("ok", false)), "到访后随身车夫仍无法绕入金币图")
	check(not bool(MapService.travel_to("c7_gold_field").get("ok", false)), "当地车夫也无法绕入金币图")
	GameState.player["level"] = 99
	check(MapService.entry_gate_reason("c7_boss_field").contains("100"), "99 级不可进入百 Boss 图")
	GameState.player["level"] = 100
	check(MapService.entry_gate_reason("c7_boss_field").contains("全身"), "缺少紫装不能进入百 Boss 图")
	for slot in Equipment.SLOT_DEFS:
		GameState.equipment[String(slot.id)] = {"quality": "legendary"}
	check(MapService.entry_gate_reason("c7_boss_field").is_empty(), "14 槽紫装可入图")
	GameState.mark_visited("c7_boss_field")
	check(not bool(MapService.travel_anywhere("c7_boss_field").get("ok", false)), "全紫装到访后也不能用随身车夫绕入")
	GameState.equipment["ring_2"] = {"quality": "epic"}
	check(MapService.entry_gate_reason("c7_boss_field").contains("戒指"), "双戒指任一非紫装应阻挡")
	check(not MapService.entry_gate_reason("c7_boss_field", "walk", "c6_map00").is_empty(), "不可从其他地图绕入")

## 固定刷新点数量、坐标、重生、掉落与连通布局必须和产品规则一致。
func _test_maps() -> void:
	var gold: Dictionary = DataLoader.get_entry("maps", "c7_gold_field")
	var boss: Dictionary = DataLoader.get_entry("maps", "c7_boss_field")
	var count := 0
	for group in gold.get("spawnPoints", []):
		count += int(group.get("count", 0))
		check(int(group.get("respawnTime", 0)) == 15, "金币怪 15 秒重生")
		check(Endgame.has_norm(String(group.get("monsterId", ""))), "金币怪需有归一化数值")
	check(count == 96 and int(gold.get("normalCap", 0)) == 28, "金币图 96 席、同屏上限 28")
	var seats: Array = boss.get("bossSpawns", [])
	check(seats.size() == 100 and int(boss.get("bossCap", 0)) == 18, "百 Boss 图 100 席、同屏上限 18")
	for seat in seats:
		check(int(seat.get("respawnTime", 0)) == 600, "Boss 每席 600 秒重生")
	check(BossToken.keys_of("c7_boss_field").size() == 100, "100 席序号可追踪")
	var gold_drop: Dictionary = DataLoader.get_entry("dropTables", "DT_C7_Gold_Normal")
	var gold_range: Array = (gold_drop.get("entries", [])[0] as Dictionary).get("goldRange", [])
	check(gold_range.size() == 2 and int(gold_range[0]) == 176 and int(gold_range[1]) == 224, "金币范围 176–224")
	var boss_drop: Dictionary = DataLoader.get_entry("dropTables", "DT_C7_Boss_Field")
	var equip_rows := 0
	for row in boss_drop.get("entries", []):
		if String(row.get("kind", "")) == "equip":
			equip_rows += 1
	check(equip_rows == 6, "Boss 装备三组各独立尝试两次")
	var arena_drop: Dictionary = DataLoader.get_entry("dropTables", "DT_C7_Arena_Boss")
	for source in arena_drop.get("entries", []):
		var matches := 0
		for target in boss_drop.get("entries", []):
			if target == source:
				matches += 1
		check(matches == (2 if String(source.get("kind", "")) == "equip" else 1), "装备翻倍且非装备组不变：%s" % str(source.get("kind", "")))
	check(DataLoader.validate_all().is_empty(), "地图和掉落引用通过全量校验")

## 高产图越过自动停战阈值时仍保留已登记奖励，不执行旧的 FIFO 淘汰。
func _test_reward_preservation() -> void:
	var rows: Array = []
	for i in range(2401):
		rows.append({"uid": "u_1_%d" % i, "item": {"kind": "equip"}})
	GameState.unclaimed_loot["c7_boss_field"] = rows
	GameState._evict_unclaimed_overflow()
	check(GameState.unclaimed_count("c7_boss_field") == 2401, "百 Boss 图超软上限不删除奖励")
	GameState.unclaimed_loot.erase("c7_boss_field")

## 真实装配刷新点，确认激活上限、等级跟随和新经验系数均进入怪物实例。
func _test_spawn_instances() -> void:
	GameState.reset_to_defaults()
	GameState.current_map = "c7_gold_field"
	GameState.player["level"] = 80
	var gold_spawner := MonsterSpawner.new()
	add_child(gold_spawner)
	gold_spawner.setup(null, null)
	gold_spawner.spawn_from_map("c7_gold_field")
	await get_tree().process_frame
	check(gold_spawner.point_count() == 96 and gold_spawner.alive_count() == 28, "金币图真实装配 96 点、最多 28 只")
	var normal: Monster = gold_spawner._points[0].get("entry", null)
	if normal != null:
		check(normal.level == 80 and normal.stat_norm.has("hp"), "金币怪实例等级 80 且有归一化数值")
		normal.drop_table_override = "__none__"
		var before := int(GameState.player.get("xp", 0))
		normal._settle_rewards()
		var expected := int(round(float(int(round(float(Balance.boss_xp(80)) / 10.0))) * 0.5))
		check(int(GameState.player.get("xp", 0)) - before == expected, "金币怪实得经验为同级 Boss 曲线 /10 再减半")
	gold_spawner.queue_free()
	await get_tree().process_frame
	GameState.current_map = "c7_boss_field"
	GameState.player["level"] = 100
	var boss_spawner := MonsterSpawner.new()
	add_child(boss_spawner)
	boss_spawner.setup(null, null)
	var boss_map: Dictionary = DataLoader.get_entry("maps", "c7_boss_field")
	boss_spawner.spawn_from_specs(boss_map.get("bossSpawns", []), "c7_boss_field")
	await get_tree().process_frame
	check(boss_spawner.point_count() == 100 and boss_spawner.alive_count() == 18, "百 Boss 图真实装配 100 点、最多 18 只")
	var boss: Monster = boss_spawner._points[0].get("entry", null)
	if boss != null:
		check(boss.level == 100 and is_equal_approx(boss.xp_multiplier, 0.5), "Boss 实例等级 100 且经验减半")
	boss_spawner.queue_free()
	await get_tree().process_frame

## 隔离测试入口，所有失败均以非零退出码传给运行器。
func _ready() -> void:
	GameState.reset_to_defaults()
	_test_entry()
	_test_maps()
	_test_reward_preservation()
	await _test_spawn_instances()
	GameState.reset_to_defaults()
	if failures.is_empty():
		print("[EndgameCycleMapTest] 全部通过 ✅")
		get_tree().quit(0)
	else:
		print("[EndgameCycleMapTest] 失败 %d 项" % failures.size())
		get_tree().quit(1)
