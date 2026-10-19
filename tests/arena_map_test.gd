extends Node
## M10-3 循环 Boss 图契约（工程 43 §7）：
## 拓扑 / 布局 / 规格 / 归一化基底 / 装配 / **等级现算** / 数值缩放 / 经验反推 / 存量不受影响。
##
## 核心底线：`norm` 通道与「等级每次生成现算」这两条一旦退化，游戏**能跑、能打、不报错**——
## 只是 100 级玩家会遇到 60 级 Boss（P-4/P-5），或 Lv10 模板 Boss 变成 3,000 血的纸老虎。
## 所以断言全部压在具体数值上，而不是「有没有生成」。

const MAP_ID := "c7_arena"
const HUB_ID := "c6_map00"
const DROP_TABLE := "DT_C7_Arena_Boss"
const LAYOUT_PATH := "res://data/layouts/c7_arena.json"
const MONSTER_SCENE := preload("res://scenes/entities/Monster.tscn")

## §6 实跑数值（norm = 24,300 / 420 / 141；真实值 = norm × S(level − 60)）。
const EXPECT_STATS := {
	60: {"hp": 24300, "atk": 420, "def": 141, "xp": 5833},
	100: {"hp": 182853, "atk": 3160, "def": 1061, "xp": 18160},
	1000: {"hp": 48804237, "atk": 843530, "def": 283185, "xp": 1016775},
}

var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("[ArenaMapTest] " + label)

func _ready() -> void:
	_test_topology()
	_test_layout()
	_test_specs()
	_test_norms()
	await _test_assembly()
	await _test_level_follows()
	await _test_scaled_stats()
	await _test_xp_curve()
	await _test_legacy_clamp()
	GameState.reset_to_defaults()
	if failures.is_empty():
		print("[ArenaMapTest] 全部通过 ✅")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("[ArenaMapTest] 失败 %d 项" % failures.size())
		get_tree().quit(1)

# ---- 1) 拓扑 ----

func _test_topology() -> void:
	var found: Variant = DataLoader.get_entry("maps", MAP_ID)
	check(found is Dictionary, "%s 必须登记在地图索引中" % MAP_ID)
	if not found is Dictionary:
		return
	var data: Dictionary = found
	check(String(data.get("kind", "")) == "spoke", "循环图 kind 应为 spoke")
	check(String(data.get("hubId", "")) == HUB_ID, "循环图 hubId 应为 %s" % HUB_ID)
	check(String(data.get("requiresUnlock", "")) == "campaign_complete",
		"入口钥匙应为 campaign_complete（C6Q12 产出）")
	check(not data.has("tierRange"), "循环图**不许**写 tierRange（等级由玩家等级现算）")
	var from_player: Variant = data.get("levelFromPlayer", null)
	check(from_player is Dictionary and bool((from_player as Dictionary).get("enabled", false)),
		"循环图必须配 levelFromPlayer.enabled")
	if from_player is Dictionary:
		check(int((from_player as Dictionary).get("minLevel", 0)) == 60, "levelFromPlayer.minLevel 应为 60")
	check(int(data.get("unclaimedLootCap", 0)) == 200, "D-13：循环图未领取上限应为 200")
	check(int(data.get("bossCap", 0)) == 10, "bossCap 应为 10")
	check(data.get("spawnPoints", []).is_empty(), "循环图不应有普通刷新区（否则会与 Boss 抢预算）")

	# 出口双向同格（`_validate_walk_exits` 的契约）：目标图 entrances[X] 必须等于**目标图自己**
	# 通往 X 的那个出口格，否则落地会卡在墙里。
	var exits: Array = data.get("exits", [])
	check(exits.size() == 1, "循环图应有 1 个出口，实际 %d" % exits.size())
	if exits.size() == 1:
		var exit_cell: Variant = (exits[0] as Dictionary).get("cell", null)
		var entrances: Variant = data.get("entrances", {})
		check(entrances is Dictionary and (entrances as Dictionary).get("from_%s" % HUB_ID) == exit_cell,
			"循环图的 entrances[from_%s] 必须等于自己的出口格" % HUB_ID)
	var hub: Variant = DataLoader.get_entry("maps", HUB_ID)
	check(hub is Dictionary, "%s 必须存在" % HUB_ID)
	if not hub is Dictionary:
		return
	var back: Variant = null
	for raw in (hub as Dictionary).get("exits", []):
		if raw is Dictionary and String((raw as Dictionary).get("toMap", "")) == MAP_ID:
			back = raw
	check(back != null, "%s 必须有通往 %s 的出口" % [HUB_ID, MAP_ID])
	if back is Dictionary:
		var back_cell: Variant = (back as Dictionary).get("cell", null)
		var hub_entrances: Variant = (hub as Dictionary).get("entrances", {})
		check(hub_entrances is Dictionary and (hub_entrances as Dictionary).get("from_%s" % MAP_ID) == back_cell,
			"反向同格契约：%s.entrances[from_%s] 必须等于 %s 的出口格" % [HUB_ID, MAP_ID, HUB_ID])
		# 出口自带锁是双保险：地图锁被改档绕过时出口仍拦得住。
		check(String((back as Dictionary).get("requiresUnlock", "")) == "campaign_complete",
			"通往循环图的出口应自带 requiresUnlock 双保险")

	# 车夫：目标图对本图反向报价 1200（`fee_to` 的第二条分支）。
	var fares: Variant = data.get("carterFares", {})
	check(fares is Dictionary and int((fares as Dictionary).get(HUB_ID, 0)) == 1200,
		"循环图对 %s 的车夫报价应为 1200" % HUB_ID)

# ---- 2) 布局 ----

func _test_layout() -> void:
	var parsed := _layout()
	check(not parsed.is_empty(), "布局 %s 必须可解析" % LAYOUT_PATH)
	if parsed.is_empty():
		return
	var map_data: Dictionary = DataLoader.get_entry("maps", MAP_ID)
	var size_data: Dictionary = map_data.get("size", {})
	var grid: Array = parsed.get("grid_size", [])
	check(grid.size() == 2 and int(grid[0]) == int(size_data.get("w", 0)) and int(grid[1]) == int(size_data.get("h", 0)),
		"布局 grid_size 必须与 map.json 的 size 一致（%s vs %s）" % [str(grid), str(size_data)])
	var rows: Array = parsed.get("walkable_rows", [])
	check(rows.size() == int(grid[1]), "walkable_rows 行数应等于地图高度")
	if rows.is_empty():
		return

	# 10 个 Boss 格 + 出口 + 车夫落点全部可走。
	var cells: Array = []
	for spec in map_data.get("bossSpawns", []):
		cells.append((spec as Dictionary).get("cell", null))
	for raw in map_data.get("exits", []):
		cells.append((raw as Dictionary).get("cell", null))
	cells.append(map_data.get("carterArrival", null))
	for cell in cells:
		check(_is_walkable(rows, cell), "固定格 %s 必须可走" % str(cell))

	# 从入口 BFS 必须覆盖全部可走格（有孤岛 ⇒ 玩家走不到、但刷新点照样登记）。
	var start := Vector2i(8, 45)
	check(_is_walkable(rows, [start.x, start.y]), "入口格 (8,45) 必须可走")
	var total := _walkable_total(rows)
	var reached := _reachable_count(rows, start)
	check(reached == total, "可走格必须全连通：从入口只到 %d / %d" % [reached, total])

# ---- 3) 规格 ----

func _test_specs() -> void:
	var map_data: Dictionary = DataLoader.get_entry("maps", MAP_ID)
	var specs: Array = map_data.get("bossSpawns", [])
	check(specs.size() == 10, "循环图应有 10 条 bossSpawns，实际 %d" % specs.size())
	var groups := {}
	for raw in specs:
		if not raw is Dictionary:
			check(false, "bossSpawns 条目必须是字典")
			continue
		var spec: Dictionary = raw
		var mid := String(spec.get("monsterId", ""))
		var tpl: Variant = DataLoader.get_entry("monsters", mid)
		check(tpl is Dictionary, "bossSpawns 引用未定义怪物 %s" % mid)
		if tpl is Dictionary:
			check(String((tpl as Dictionary).get("kind", "")) == "boss", "%s 的模板 kind 必须是 boss" % mid)
		check(String(spec.get("kind", "")) == "boss", "%s 的规格 kind 必须是 boss" % mid)
		check(is_equal_approx(float(spec.get("respawnTime", 0)), 600.0), "%s 的复活时间应为 600s" % mid)
		check(bool(spec.get("tombstone", false)), "%s 必须落墓碑（跨图可见倒计时）" % mid)
		check(bool(spec.get("scaleStats", false)), "%s 必须开 scaleStats" % mid)
		check(bool(spec.get("xpFromCurve", false)), "%s 必须开 xpFromCurve" % mid)
		check(String(spec.get("dropTableId", "")) == DROP_TABLE, "%s 的 dropTableId 必须指向 %s" % [mid, DROP_TABLE])
		var group := String(spec.get("group", ""))
		check(not group.is_empty(), "%s 缺少 group 标注" % mid)
		groups[group] = int(groups.get(group, 0)) + 1
	check(groups.size() == 5, "五区各两只，实际区数 %d" % groups.size())
	for group in groups.keys():
		check(int(groups[group]) == 2, "区 %s 应恰好 2 只 Boss，实际 %d" % [String(group), int(groups[group])])

# ---- 4) 归一化基底 ----

func _test_norms() -> void:
	var rows: Array = Endgame.arena_bosses()
	check(rows.size() == 10, "endgame.json 应登记 10 条 arenaBosses，实际 %d" % rows.size())
	var map_data: Dictionary = DataLoader.get_entry("maps", MAP_ID)
	for raw in map_data.get("bossSpawns", []):
		var mid := String((raw as Dictionary).get("monsterId", ""))
		var norm := Endgame.norm(mid)
		check(not norm.is_empty(), "%s 必须在 endgame.json 有 norm 基底" % mid)
		for key in ["hp", "atk", "def"]:
			var value: Variant = norm.get(key, null)
			check(value is int or value is float, "%s 的 norm.%s 必须是数字" % [mid, key])
			if value is int or value is float:
				check(float(value) >= 1.0, "%s 的 norm.%s 必须 ≥ 1，实际 %s" % [mid, key, str(value)])
	# 差距必须被压进窄带：模板 hpBase 从 3,000 到 24,300 是 8.1 倍，norm 之后必须 ≤ 1.1 倍。
	var lo := 1 << 30
	var hi := 0
	for raw in rows:
		var hp := int((Endgame.norm(String((raw as Dictionary).get("monsterId", "")))).get("hp", 0))
		lo = mini(lo, hp)
		hi = maxi(hi, hp)
	check(lo > 0 and float(hi) / float(lo) <= 1.1,
		"norm.hp 必须压进窄带（≤1.1 倍），实际 %d—%d（%.2f 倍）" % [lo, hi, float(hi) / float(lo)])

# ---- 5) 装配 ----

func _test_assembly() -> void:
	GameState.reset_to_defaults()
	GameState.player.level = 60
	var sp := MonsterSpawner.new()
	add_child(sp)
	sp.setup(null, null)
	sp.spawn_from_specs(_specs(), MAP_ID)
	await get_tree().process_frame
	check(sp.point_count() == 10, "装配后应登记 10 个 Boss 点，实际 %d" % sp.point_count())
	# 验收口径（§3.2）：10 个**点**必须全部登记；实体按 760px 就近生成，
	# 这里没有玩家 ⇒ 距离预算不生效，10 只全出。
	check(sp.alive_count() >= 1, "装配后应至少有 1 只 Boss 实体，实际 %d" % sp.alive_count())
	sp.queue_free()
	await get_tree().process_frame

# ---- 6) 等级现算（P-5）----

func _test_level_follows() -> void:
	GameState.reset_to_defaults()
	GameState.player.level = 60
	var sp := MonsterSpawner.new()
	add_child(sp)
	sp.setup(null, null)
	sp.spawn_from_specs(_specs(), MAP_ID)
	await get_tree().process_frame
	var point: Dictionary = sp._points[0]
	var first: Monster = point.get("entry", null)
	check(first != null, "首个 Boss 点应生成实例")
	if first == null:
		sp.queue_free()
		return
	check(first.level == 60, "L60 玩家：实例等级应为 60，实际 %d" % first.level)

	# 让**同一个点**重新生成（等价于 600s 复活 / 走远回收后走近补建）。
	first.queue_free()
	point["entry"] = null
	GameState.player.level = 100
	sp._spawn(point, null)
	var second: Monster = point.get("entry", null)
	check(second != null, "等级变化后该点应能重新生成")
	if second != null:
		check(second.level == 100,
			"L100 玩家重生成后实例等级应为 100，实际 %d（P-5：等级不许固化成进图那天的值）" % second.level)
		check(second.max_hp == int(EXPECT_STATS[100]["hp"]),
			"L100 重生成后 max_hp 应为 %d，实际 %d" % [int(EXPECT_STATS[100]["hp"]), second.max_hp])
	sp.queue_free()
	await get_tree().process_frame

# ---- 7) 数值缩放 ----

func _test_scaled_stats() -> void:
	for level in [60, 100, 1000]:
		var m := _make_boss("c6_boss03", level)
		await get_tree().process_frame
		var expect: Dictionary = EXPECT_STATS[level]
		check(m.level == level, "%d 级实例的 level 应为 %d，实际 %d" % [level, level, m.level])
		check(m.max_hp == int(expect["hp"]), "%d 级 Boss max_hp 应为 %d，实际 %d" % [level, int(expect["hp"]), m.max_hp])
		check(int(round(m.get_attack())) == int(expect["atk"]),
			"%d 级 Boss 攻击应为 %d，实际 %d" % [level, int(expect["atk"]), int(round(m.get_attack()))])
		check(int(round(m.get_defense())) == int(expect["def"]),
			"%d 级 Boss 防御应为 %d，实际 %d" % [level, int(expect["def"]), int(round(m.get_defense()))])
		m.queue_free()

	# 反证：Lv10 模板的 3,000 血基底**不能**直接进循环图（产品 13 §4.2 的 8.1 倍硬伤）。
	var weak := _make_boss("boss_corrupted_beast", 60)
	await get_tree().process_frame
	check(weak.max_hp == 24300,
		"Lv10 模板 boss_corrupted_beast 在 L60 循环图应为 24,300 血，实际 %d（norm 通道失效）" % weak.max_hp)
	weak.queue_free()
	await get_tree().process_frame

# ---- 8) 经验反推 ----

func _test_xp_curve() -> void:
	GameState.reset_to_defaults()
	for level in [60, 100, 1000]:
		var expect := int(EXPECT_STATS[level]["xp"])
		check(Balance.boss_xp(level) == expect, "L%d 的单只 Boss 经验应为 %d，实际 %d" % [level, expect, Balance.boss_xp(level)])

	# 真链路：`xp_from_curve` 打开时 `_settle_rewards` 必须按曲线发经验，而不是模板值。
	# 掉落用不存在的表名短路，本用例只观察经验（避免生成地面物污染状态）。
	GameState.player.level = 60
	GameState.player.xp = 0
	var m := _make_boss("c6_boss03", 60)
	m.drop_table_override = "__none__"
	await get_tree().process_frame
	var before := int(GameState.player.xp)
	m._settle_rewards()
	var gained := int(GameState.player.xp) - before
	check(gained == int(EXPECT_STATS[60]["xp"]),
		"xpFromCurve 应发 %d 经验，实际 %d（回落到模板值说明通道没接上）" % [int(EXPECT_STATS[60]["xp"]), gained])

	# 关掉开关必须回落到模板 xpReward（存量轨迹不变）。
	GameState.player.xp = 0
	var legacy := _make_boss("c6_boss03", 60)
	legacy.xp_from_curve = false
	legacy.drop_table_override = "__none__"
	await get_tree().process_frame
	legacy._settle_rewards()
	var template_xp := int((DataLoader.get_entry("monsters", "c6_boss03") as Dictionary).get("xpReward", 0))
	check(int(GameState.player.xp) == template_xp,
		"xpFromCurve 关闭时应回落到模板 xpReward %d，实际 %d" % [template_xp, int(GameState.player.xp)])
	m.queue_free()
	legacy.queue_free()
	await get_tree().process_frame

# ---- 9) 存量三十五张图零影响 ----

func _test_legacy_clamp() -> void:
	var sp := MonsterSpawner.new()
	add_child(sp)
	sp.setup(null, null)
	sp.spawn_from_specs([{"monsterId": "wolf_corrupted", "level": 99, "ai": false}], "wild_trial")
	check(int(sp._points[0].get("level", 0)) == 5, "试炼野外 L99 应夹到 L5，实际 %d" % int(sp._points[0].get("level", 0)))
	sp.spawn_from_specs([{"monsterId": "shellback_bug", "level": 9, "ai": false}], "corruption_source")
	check(int(sp._points[1].get("level", 0)) == 10,
		"腐化之源 L9 应夹到 L10，实际 %d" % int(sp._points[1].get("level", 0)))
	check(sp._level_min == 0, "存量图不应进入「等级跟随玩家」分支（_level_min 应为 0，实际 %d）" % sp._level_min)
	# 存量怪物的数值口径不变：没有 norm ⇒ 走 `_derive_max_hp`（模板 hpBase × 等级修正），
	# 而不是被 S(d) 放大成几十万血。
	var wolf := _make_boss("wolf_corrupted", 5)
	await get_tree().process_frame
	var hp_base := int((DataLoader.get_entry("monsters", "wolf_corrupted") as Dictionary).get("hpBase", 0))
	check(wolf.max_hp > 0 and wolf.max_hp < hp_base * 4,
		"存量怪物 max_hp 应走模板口径（远小于 S 放大），实际 %d（hpBase %d）" % [wolf.max_hp, hp_base])
	wolf.queue_free()
	sp.queue_free()
	await get_tree().process_frame

# ---- 辅助 ----

func _specs() -> Array:
	var map_data: Dictionary = DataLoader.get_entry("maps", MAP_ID)
	return map_data.get("bossSpawns", []).duplicate(true)

## 造一只装了 norm 通道的 Boss（不经过 spawner，专测数值口径）。
## 注意**不能**置 `suppress_rewards`：用例 8 要真的跑一遍 `_settle_rewards` 才能锁住经验通道。
func _make_boss(monster_id: String, level: int) -> Monster:
	var m := MONSTER_SCENE.instantiate() as Monster
	m.monster_id = monster_id
	m.spawn_level = level
	m.stat_norm = Endgame.norm(monster_id)
	m.scale_stats = true
	m.xp_from_curve = true
	m.ai_enabled = false
	add_child(m)
	return m

func _layout() -> Dictionary:
	if not FileAccess.file_exists(LAYOUT_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
	return parsed if parsed is Dictionary else {}

func _is_walkable(rows: Array, cell: Variant) -> bool:
	if not cell is Array or (cell as Array).size() != 2:
		return false
	var x := int((cell as Array)[0])
	var y := int((cell as Array)[1])
	if y < 0 or y >= rows.size():
		return false
	var row := String(rows[y])
	if x < 0 or x >= row.length():
		return false
	return row[x] == "1"

func _walkable_total(rows: Array) -> int:
	var n := 0
	for row in rows:
		n += String(row).count("1")
	return n

## 四邻接洪泛：从 start 可达的可走格数。
func _reachable_count(rows: Array, start: Vector2i) -> int:
	var height := rows.size()
	var width := String(rows[0]).length()
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for delta in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = cell + delta
			if next.x < 0 or next.y < 0 or next.x >= width or next.y >= height:
				continue
			if String(rows[next.y])[next.x] != "1" or seen.has(next):
				continue
			seen[next] = true
			queue.append(next)
	return seen.size()
