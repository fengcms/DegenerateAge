extends Node
## 双循环图数据、入口与奖励契约测试；在隔离项目中运行，结束时恢复运行态。

const MONSTER_SCENE := preload("res://scenes/entities/Monster.tscn")

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
	check(count == 96 and int(gold.get("normalCap", 0)) == 32, "金币图 96 席、同屏上限 32")
	var seats: Array = boss.get("bossSpawns", [])
	check(seats.size() == 100 and int(boss.get("bossCap", 0)) == 18, "百 Boss 图 100 席、同屏上限 18")
	for seat in seats:
		check(int(seat.get("respawnTime", 0)) == 600, "Boss 每席 600 秒重生")
	check(BossToken.keys_of("c7_boss_field").size() == 100, "100 席序号可追踪")
	var gold_drop: Dictionary = DataLoader.get_entry("dropTables", "DT_C7_Gold_Normal")
	var gold_range: Array = (gold_drop.get("entries", [])[0] as Dictionary).get("goldRange", [])
	check(gold_range.size() == 2 and int(gold_range[0]) == 440 and int(gold_range[1]) == 560, "金币范围 440–560")
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
	check(gold_spawner.point_count() == 96 and gold_spawner.alive_count() == 32, "金币图真实装配 96 点、最多 32 只")
	var normal: Monster = gold_spawner._points[0].get("entry", null)
	if normal != null:
		check(normal.level == 80 and normal.stat_norm.has("hp"), "金币怪实例等级 80 且有归一化数值")
		normal.drop_table_override = "__none__"
		var before := int(GameState.player.get("xp", 0))
		normal._settle_rewards()
		var expected := int(round(float(int(round(float(Balance.boss_xp(80)) / 10.0))) * 0.1))
		check(int(GameState.player.get("xp", 0)) - before == expected, "金币怪实得经验为同级 Boss 曲线 /10 再乘 0.1")
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
		check(boss.level == 100 and is_equal_approx(boss.xp_multiplier, 0.25)
			and is_equal_approx(boss.hp_multiplier, 2.0) and is_equal_approx(boss.atk_multiplier, 1.5),
			"Boss 实例等级 100、经验 ×0.25、生命 ×2、攻击 ×1.5")
	boss_spawner.queue_free()
	await get_tree().process_frame

## Task 5.2：三图倍率字段逐条落库；只看集合大小会被「某几条漏写」绕过，必须逐席断言。
func _test_multipliers() -> void:
	var boss: Dictionary = DataLoader.get_entry("maps", "c7_boss_field")
	var boss_seats: Array = boss.get("bossSpawns", [])
	check(boss_seats.size() == 100, "百首禁域 bossSpawns 应为 100 条，实际 %d" % boss_seats.size())
	for raw in boss_seats:
		var seat: Dictionary = raw
		var mid := String(seat.get("monsterId", ""))
		check(is_equal_approx(float(seat.get("hpMultiplier", 0.0)), 2.0), "百首禁域 %s 的 hpMultiplier 应为 2.0" % mid)
		check(is_equal_approx(float(seat.get("atkMultiplier", 0.0)), 1.5), "百首禁域 %s 的 atkMultiplier 应为 1.5" % mid)
		check(is_equal_approx(float(seat.get("xpMultiplier", 0.0)), 0.25), "百首禁域 %s 的 xpMultiplier 应为 0.25" % mid)

	var arena: Dictionary = DataLoader.get_entry("maps", "c7_arena")
	var arena_seats: Array = arena.get("bossSpawns", [])
	check(arena_seats.size() == 20, "无尽回廊 bossSpawns 应为 20 条，实际 %d" % arena_seats.size())
	for raw in arena_seats:
		var seat: Dictionary = raw
		var mid := String(seat.get("monsterId", ""))
		check(is_equal_approx(float(seat.get("hpMultiplier", 0.0)), 2.0), "无尽回廊 %s 的 hpMultiplier 应为 2.0" % mid)
		check(is_equal_approx(float(seat.get("xpMultiplier", 0.0)), 0.5), "无尽回廊 %s 的 xpMultiplier 应为 0.5" % mid)
		# 回廊**不叠攻击倍率**：要么未写该字段，要么显式 1.0。
		check(not seat.has("atkMultiplier") or is_equal_approx(float(seat.get("atkMultiplier", 1.0)), 1.0),
			"无尽回廊 %s 不应叠加攻击倍率（缺省或 1.0）" % mid)

	var gold: Dictionary = DataLoader.get_entry("maps", "c7_gold_field")
	for group in gold.get("spawnPoints", []):
		var g: Dictionary = group
		check(is_equal_approx(float(g.get("xpMultiplier", 0.0)), 0.1),
			"聚金地脉 %s 的 xpMultiplier 应为 0.1" % String(g.get("monsterId", "")))

## Task 5.2：聚金地脉必须真的是「6 堆 × 16 席」，而不是把 96 席摊成一片。
## 方法：对每个格子枚举候选堆原点（cell − (a,b)，a/b ∈ {0,3,6,9}），
## 只有真正的 6 个原点各自恰好覆盖 16 格、合计 96 格；再校验 6 堆心两两世界像素距离。
func _test_gold_piles() -> void:
	var gold: Dictionary = DataLoader.get_entry("maps", "c7_gold_field")
	var cells := {}
	for group in gold.get("spawnPoints", []):
		var list: Variant = (group as Dictionary).get("cells", [])
		if not list is Array:
			continue
		for cell in list:
			if cell is Array and (cell as Array).size() == 2:
				cells[Vector2i(int((cell as Array)[0]), int((cell as Array)[1]))] = true
	check(cells.size() == 96, "聚金地脉应登记 96 个互不重复的刷新格，实际 %d" % cells.size())

	var coverage := {}
	for cell in cells.keys():
		for a in [0, 3, 6, 9]:
			for b in [0, 3, 6, 9]:
				var origin := (cell as Vector2i) - Vector2i(a, b)
				coverage[origin] = int(coverage.get(origin, 0)) + 1
	var origins: Array = []
	for origin in coverage.keys():
		if int(coverage[origin]) == 16:
			origins.append(origin)
	check(origins.size() == 6 and origins.size() * 16 == 96,
		"聚金地脉应恰好 6 堆各 16 席，实际 %d 堆（覆盖 %d）" % [origins.size(), origins.size() * 16])

	var centers: Array[Vector2] = []
	for origin in origins:
		var o: Vector2i = origin
		centers.append(Iso.grid_pt(float(o.x) + 4.5, float(o.y) + 4.5))
	var min_dist := INF
	for i in range(centers.size()):
		for j in range(i + 1, centers.size()):
			min_dist = minf(min_dist, centers[i].distance_to(centers[j]))
	check(centers.size() == 6 and min_dist >= 858.0,
		"聚金地脉 6 堆心两两世界像素距离应 ≥ 858px，实际 %.2f" % min_dist)

## Task 5.2：怪物 → 玩家伤害下限（不破防时按最大生命比例，10–60）。
## 既有公式：破防走 floor(攻×系数 − 防×0.5)，只有不破防才用调用方下限替换 1 点兜底。
func _test_damage_floor() -> void:
	GameState.reset_to_defaults()
	# ① 纯公式：不破防（攻 1 < 防 100000×0.5）→ 缺省下限 1；显式下限 37 → 37。
	check(int(Combat.resolve(1.0, 100000.0, 1.0, 0.0, 1.0, 0.0).get("damage", -1)) == 1,
		"不破防且未传下限时退化为 1 点")
	check(int(Combat.resolve(1.0, 100000.0, 1.0, 0.0, 1.0, 0.0, null, 37).get("damage", -1)) == 37,
		"不破防时下限 37 应原样生效")
	# ② 破防（攻 8 − 防 5×0.5 = 5.5 → 5）：下限不参与，数值逐值不变。
	check(int(Combat.resolve(8.0, 5.0, 1.0, 0.0, 1.0, 0.0).get("damage", -1)) == 5,
		"破防伤害 5 不受下限影响")

	# ③ 怪物侧：真实 Monster 实例的 _min_hit_on_player() 落在 [10, 60]，且等于公式值。
	var monster := MONSTER_SCENE.instantiate() as Monster
	monster.monster_id = "c6_boss03"
	monster.ai_enabled = false
	add_child(monster)
	await get_tree().process_frame
	var floor_hit := monster._min_hit_on_player()
	var expect := clampi(int(round(float(GameState.max_hp()) * 0.0025)), 10, 60)
	check(floor_hit == expect, "_min_hit_on_player() 应等于最大生命比例公式，实际 %d（期望 %d）" % [floor_hit, expect])
	check(floor_hit >= 10 and floor_hit <= 60, "怪物 → 玩家伤害下限应落在 [10, 60]，实际 %d" % floor_hit)
	# ④ 不破防结算：防御取极大值 → 公式 ≤0 → 结果由下限接管，仍 ≥10 且 ≤60。
	var dealt := int(Combat.resolve(1.0, 100000.0, 1.0, 0.0, 1.0, 0.0, null, floor_hit).get("damage", 0))
	check(dealt >= 10 and dealt <= 60, "不破防时怪物 → 玩家伤害应 ≥10 且 ≤60，实际 %d" % dealt)
	monster.queue_free()
	await get_tree().process_frame

## Task 5.2：倍率管道 —— 无倍率规格应与「同怪同级的裸实例」逐值相等（存量零影响）；
## 有倍率规格精确等于基础值 × 倍率（证明倍率在 norm/scale 结算之后才生效）。
func _test_multiplier_pipeline() -> void:
	GameState.reset_to_defaults()
	var mid := "c6_boss03"
	var lv := 100
	var sp := MonsterSpawner.new()
	add_child(sp)
	sp.setup(null, null)
	sp.spawn_from_specs([
		{"monsterId": mid, "level": lv, "ai": false, "scaleStats": true},
		{"monsterId": mid, "level": lv, "ai": false, "scaleStats": true,
			"hpMultiplier": 3.0, "atkMultiplier": 2.0},
	], "")
	await get_tree().process_frame
	var plain: Monster = sp._points[0].get("entry", null)
	var boosted: Monster = sp._points[1].get("entry", null)
	check(plain != null and boosted != null, "倍率管道两席都应生成实体")
	if plain != null and boosted != null:
		var bare := MONSTER_SCENE.instantiate() as Monster
		bare.monster_id = mid
		bare.spawn_level = lv
		bare.stat_norm = Endgame.norm(mid)
		bare.scale_stats = true
		bare.ai_enabled = false
		add_child(bare)
		await get_tree().process_frame
		check(plain.max_hp == bare.max_hp and int(round(plain.attack_power)) == int(round(bare.attack_power)),
			"无倍率规格应与裸实例逐值相等（max_hp %d/%d，atk %.1f/%.1f）" % [
				plain.max_hp, bare.max_hp, plain.attack_power, bare.attack_power])
		check(boosted.max_hp == bare.max_hp * 3,
			"hpMultiplier 3.0 应精确 ×3（%d vs %d）" % [boosted.max_hp, bare.max_hp * 3])
		check(is_equal_approx(boosted.attack_power, bare.attack_power * 2.0),
			"atkMultiplier 2.0 应精确 ×2（%.2f vs %.2f）" % [boosted.attack_power, bare.attack_power * 2.0])
		bare.queue_free()
	sp.queue_free()
	await get_tree().process_frame

## 隔离测试入口，所有失败均以非零退出码传给运行器。
func _ready() -> void:
	GameState.reset_to_defaults()
	_test_entry()
	_test_maps()
	_test_multipliers()
	_test_gold_piles()
	_test_reward_preservation()
	await _test_damage_floor()
	await _test_multiplier_pipeline()
	await _test_spawn_instances()
	GameState.reset_to_defaults()
	if failures.is_empty():
		print("[EndgameCycleMapTest] 全部通过 ✅")
		get_tree().quit(0)
	else:
		print("[EndgameCycleMapTest] 失败 %d 项" % failures.size())
		get_tree().quit(1)
