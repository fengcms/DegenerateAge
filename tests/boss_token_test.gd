extends Node
## M10-5 追猎令牌与任意图出行（工程 46 §5）：
## 行集完整性 / visited 过滤 / 倒计时同源 / ordinal 真进 key / 等级跟随 / 存量不跟随 /
## 与 Spawner 的真实序号逐条一致 / `_map_has_monster` 认 bossSpawns /
## `fee_anywhere` 边界 / `travel_anywhere` 全链 / 落地意图一次性 / 回滚清理。
##
## 底线：这份测试里最有钱的一条是**用例 7**。令牌与 Boss 墓碑共用
## `spawn_key(map, monster_id, ordinal)`，序号一旦对不上，面板会显示「存活」而实际在冷却
## —— 那种错误不会报错、只会让玩家白跑一趟。所以这里真的跑一遍 Spawner 装配再逐个比对。

const ARENA := "c7_arena"
const LEGACY_MAP := "c6_map05"
const LEGACY_BOSS := "c6_boss03"
const ARENA_BOSS := "c6_boss03"
const TOTAL_BOSS_ROWS := 137  # 17 单点 + c7_arena 20 + 百首禁域 100
const LEGACY_UNLOCK := "c6_access_05"

var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("[BossTokenTest] " + label)

func _ready() -> void:
	_test_rows_complete()
	_test_visited_filter()
	_test_countdown_source()
	_test_ordinal_in_key()
	_test_level_follows_player()
	_test_legacy_level_fixed()
	await _test_keys_match_spawner()
	_test_map_has_monster()
	_test_fee_anywhere()
	_test_travel_anywhere()
	_test_landing_move_once()
	_test_rollback_clears_landing()
	GameState.reset_to_defaults()
	if failures.is_empty():
		print("[BossTokenTest] 全部通过 ✅")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("[BossTokenTest] 失败 %d 项" % failures.size())
		get_tree().quit(1)

# ---- 1) 行集完整性 ----

func _test_rows_complete() -> void:
	_visit_all_boss_maps()
	var rows := BossToken.rows()
	check(rows.size() == TOTAL_BOSS_ROWS,
		"走过全部 boss 图后应有 %d 行（17 单点 + c7_arena 20），实际 %d" % [TOTAL_BOSS_ROWS, rows.size()])
	var arena := _rows_of(rows, ARENA)
	check(arena.size() == 20, "c7_arena 应贡献 20 行（bossSpawns 形态），实际 %d" % arena.size())
	var legacy := _rows_of(rows, LEGACY_MAP)
	check(legacy.size() == 1, "%s 应贡献 1 行（bossSpawn 形态），实际 %d" % [LEGACY_MAP, legacy.size()])
	# 当前图置顶：camp 没有 boss，所以这里先只断言「当前图的行全部在最前面」。
	if not rows.is_empty():
		var first_other := -1
		for i in range(rows.size()):
			if not bool(rows[i].get("is_current_map", false)):
				first_other = i
				break
		var current_tail := -1
		for i in range(rows.size()):
			if bool(rows[i].get("is_current_map", false)):
				current_tail = i
		check(first_other == -1 or current_tail < first_other, "当前图的行必须排在全部非当前图之前")

# ---- 2) visited 过滤 ----

func _test_visited_filter() -> void:
	GameState.reset_to_defaults()
	var rows := BossToken.rows()
	check(rows.is_empty(), "新档（只到过 camp）令牌应为 0 行，实际 %d（visited 过滤失效）" % rows.size())

# ---- 3) 倒计时与墓碑同源 ----

func _test_countdown_source() -> void:
	_visit_all_boss_maps()
	GameState.mark_spawn_dead(LEGACY_MAP, LEGACY_BOSS, 0, 600.0, Vector2.ZERO)
	var row := _find(BossToken.rows(), LEGACY_MAP, LEGACY_BOSS, 0)
	check(not row.is_empty(), "%s/%s 的行必须存在" % [LEGACY_MAP, LEGACY_BOSS])
	if row.is_empty():
		return
	var remaining := float(row.get("remaining", 0.0))
	check(remaining > 500.0 and remaining <= 600.0,
		"刚击杀的 Boss 剩余应接近 600s，实际 %.1f（未读 spawn_remaining？）" % remaining)
	check(not bool(row.get("alive", true)), "冷却中的 Boss 不应标记为存活")
	GameState.clear_spawn_state(LEGACY_MAP, LEGACY_BOSS, 0)

# ---- 4) ordinal 真的进 key ----
##
## 全库 Boss 与普通点零重叠 ⇒ 真实数据的序号恒 0，光看真实行咬不住这条。
## 所以拆三段：① 序号分配规则（合成数据，能造出非 0 序号）；② 行的 ordinal 必须真的拿去查
## 刷新状态（传 3 就得看 ordinal=3）；③ 真实数据下 rows 与 keys_of 必须同源。
func _test_ordinal_in_key() -> void:
	# ① Spawner 是「先按 spawnPoints 累加同种计数，再给 Boss 取号」——
	# 少了累加这一步，Boss 序号会从 0 起，与墓碑 key 错位。
	var synthetic := {
		"spawnPoints": [
			{"monsterId": "wolf_corrupted", "count": 2},
			{"monsterId": ARENA_BOSS, "count": 3},
		],
		"bossSpawns": [{"monsterId": ARENA_BOSS}, {"monsterId": ARENA_BOSS}],
	}
	var ords: Array = BossToken._boss_ordinals(synthetic)
	check(ords.size() == 2, "合成数据应分配 2 个 Boss 序号，实际 %d" % ords.size())
	if ords.size() == 2:
		check(int((ords[0] as Array)[1]) == 3 and int((ords[1] as Array)[1]) == 4,
			"Boss 序号必须接着普通点计数往后排（应为 3、4），实际 %d、%d"
				% [int((ords[0] as Array)[1]), int((ords[1] as Array)[1])])

	# ② 行必须用传入的 ordinal 去查刷新状态（写死 0 就会把别的号的冷却算到自己头上）。
	GameState.reset_to_defaults()
	GameState.mark_spawn_dead("camp", ARENA_BOSS, 3, 600.0, Vector2.ZERO)
	var map_data := {"id": "camp", "name": "营地", "recommendedLevel": 1}
	var spec := {"monsterId": ARENA_BOSS}
	var late := BossToken._row(map_data, spec, ARENA_BOSS, 3, 60, false, 0)
	check(not bool(late.get("alive", true)), "ordinal=3 的行必须读到 ordinal=3 的冷却状态")
	var early := BossToken._row(map_data, spec, ARENA_BOSS, 0, 60, false, 1)
	check(bool(early.get("alive", true)), "ordinal=0 的行不得被 ordinal=3 的状态污染（序号没进 key）")
	GameState.clear_spawn_state("camp", ARENA_BOSS, 3)

	# ③ 真实数据：rows() 的 (monster_id, ordinal) 必须与 keys_of 同源。
	_visit_all_boss_maps()
	var rows := BossToken.rows()
	var keys := BossToken.keys_of(ARENA)
	var arena := _rows_of(rows, ARENA)
	check(arena.size() == keys.size(), "c7_arena 行数与 keys_of 应一致（%d vs %d）" % [arena.size(), keys.size()])
	for i in range(mini(arena.size(), keys.size())):
		check(String(arena[i].get("monster_id", "")) == String((keys[i] as Dictionary).get("monster_id", ""))
			and int(arena[i].get("ordinal", -1)) == int((keys[i] as Dictionary).get("ordinal", -1)),
			"第 %d 行的 (monster_id, ordinal) 必须与 keys_of 同源" % i)


# ---- 5) 等级跟随玩家 ----

func _test_level_follows_player() -> void:
	_visit_all_boss_maps()
	for level in [100, 60]:
		GameState.player.level = level
		var rows := _rows_of(BossToken.rows(), ARENA)
		check(rows.size() == 20, "c7_arena 应有 20 行，实际 %d" % rows.size())
		for row in rows:
			check(int(row.get("level", 0)) == level,
				"L%d 玩家：c7_arena 的 %s 等级应为 %d，实际 %d" % [level, String(row.get("monster_name", "")), level, int(row.get("level", 0))])
			check(int(row.get("drop_level", 0)) == level,
				"掉落等级应与怪物等级一致（L%d），实际 %d" % [level, int(row.get("drop_level", 0))])

# ---- 6) 存量图不被误跟随 ----

func _test_legacy_level_fixed() -> void:
	_visit_all_boss_maps()
	GameState.player.level = 100
	var row := _find(BossToken.rows(), LEGACY_MAP, LEGACY_BOSS, 0)
	check(not row.is_empty(), "%s/%s 的行必须存在" % [LEGACY_MAP, LEGACY_BOSS])
	if row.is_empty():
		return
	check(int(row.get("level", 0)) == 60,
		"存量图 %s 的 Boss 等级应固定 60（玩家 100 级也不许跟随），实际 %d" % [LEGACY_MAP, int(row.get("level", 0))])

# ---- 7) 令牌 key 与 Spawner 真实装配逐条一致（最有钱的一条）----

func _test_keys_match_spawner() -> void:
	GameState.reset_to_defaults()
	GameState.player.level = 60
	var sp := MonsterSpawner.new()
	add_child(sp)
	sp.setup(null, null)
	sp.spawn_from_map(ARENA)
	var specs: Array = (DataLoader.get_entry("maps", ARENA) as Dictionary).get("bossSpawns", []).duplicate(true)
	sp.spawn_from_specs(specs, ARENA)
	await get_tree().process_frame
	var actual: Array = []
	for point in sp._points:
		actual.append("%s#%d" % [String(point.get("monster_id", "")), int(point.get("ordinal", 0))])
	var expected: Array = []
	for pair in BossToken.keys_of(ARENA):
		expected.append("%s#%d" % [String(pair.get("monster_id", "")), int(pair.get("ordinal", 0))])
	check(actual == expected,
		"令牌算出的 (monster_id, ordinal) 必须与 Spawner 装配逐个一致：Spawner=%s / 令牌=%s" % [str(actual), str(expected)])
	check(actual.size() == 20, "Spawner 应装配 20 个 Boss 点，实际 %d" % actual.size())
	sp.queue_free()
	await get_tree().process_frame

# ---- 8) _map_has_monster 认 bossSpawns（G-1）----

func _test_map_has_monster() -> void:
	check(MapService._map_has_monster(ARENA, ARENA_BOSS),
		"c7_arena 的 Boss 必须被 _map_has_monster 认出来（只查 bossSpawn 时恒 false）")
	check(not MapService._map_has_monster(ARENA, "__nonexistent__"),
		"不存在的怪物不应被认成存在")
	check(MapService._map_has_monster(LEGACY_MAP, LEGACY_BOSS), "存量单点 bossSpawn 仍要认")

# ---- 9) fee_anywhere 边界 ----

func _test_fee_anywhere() -> void:
	check(MapService.fee_anywhere("camp") == 50, "camp（L1）随身车费应为下限 50，实际 %d" % MapService.fee_anywhere("camp"))
	check(MapService.fee_anywhere(LEGACY_MAP) == 1200, "c6_map05（L60）随身车费应为 1200，实际 %d" % MapService.fee_anywhere(LEGACY_MAP))
	check(MapService.fee_anywhere("__nonexistent__") == -1, "不存在的图应返回 -1")

# ---- 10) travel_anywhere 全链 ----

func _test_travel_anywhere() -> void:
	GameState.reset_to_defaults()
	var res := MapService.travel_anywhere(LEGACY_MAP)
	check(not bool(res.get("ok", false)) and not String(res.get("reason", "")).is_empty(),
		"未到访的图应被拒且给出原因")
	check(MapService.pending_travel.is_empty(), "被拒时不应建立出行事务")

	GameState.mark_visited(LEGACY_MAP)
	GameState.unlocks[LEGACY_UNLOCK] = true
	GameState.gold = 100
	res = MapService.travel_anywhere(LEGACY_MAP)
	check(not bool(res.get("ok", false)), "金币不足时应被拒")
	check(MapService.pending_travel.is_empty(), "金币不足时不应建立出行事务")
	check(GameState.gold == 100, "被拒时不应扣费，实际 %d" % GameState.gold)

	GameState.gold = 2000
	res = MapService.travel_anywhere(LEGACY_MAP)
	check(bool(res.get("ok", false)), "到访过 + 解锁 + 够钱时应能直达：%s" % String(res.get("reason", "")))
	if bool(res.get("ok", false)):
		check(GameState.gold == 800, "应精确扣 1200，实际余额 %d" % GameState.gold)
		check(GameState.current_map == LEGACY_MAP, "应已切到 %s，实际 %s" % [LEGACY_MAP, GameState.current_map])
		check(not MapService.pending_travel.is_empty(), "应建立 pending_travel 供 Game._ready 提交")
		MapService.rollback_travel()
		check(GameState.current_map == "camp", "回滚后应回到 camp，实际 %s" % GameState.current_map)
		check(GameState.gold == 2000, "回滚应退还车费，实际 %d" % GameState.gold)
	GameState.reset_to_defaults()

# ---- 11) 落地意图一次性 ----

func _test_landing_move_once() -> void:
	var target := Vector2(123.0, 456.0)
	MapService.arm_landing_move(target)
	var got: Variant = MapService.consume_landing_move()
	check(got is Vector2 and (got as Vector2) == target, "消费应返回 arm 进去的坐标，实际 %s" % str(got))
	check(MapService.consume_landing_move() == null, "第二次消费必须为空（一次性语义）")

# ---- 12) 回滚必须撤掉落地意图（R-3）----

func _test_rollback_clears_landing() -> void:
	GameState.reset_to_defaults()
	GameState.mark_visited(LEGACY_MAP)
	GameState.unlocks[LEGACY_UNLOCK] = true
	GameState.gold = 5000
	var res := MapService.travel_anywhere(LEGACY_MAP)
	# 前置失败时直接返回：那条路径由用例 10 负责报，不在这里连带制造假红。
	if not bool(res.get("ok", false)):
		check(false, "前置：直达应成功（%s）" % String(res.get("reason", "")))
		GameState.reset_to_defaults()
		return
	MapService.arm_landing_move(Vector2(9.0, 9.0))
	MapService.rollback_travel()
	check(MapService.pending_landing_move == null,
		"切图失败回滚后必须清掉落地意图（否则玩家在原图被指挥走向别的图坐标）")
	GameState.reset_to_defaults()

# ---- 辅助 ----

## 把所有「有 boss 的图」标成已到访（令牌的行集来源）。
func _visit_all_boss_maps() -> void:
	GameState.reset_to_defaults()
	for entry in DataLoader.get_table("maps"):
		if not entry is Dictionary:
			continue
		var map_data: Dictionary = entry
		var map_id := String(map_data.get("id", ""))
		if map_id.is_empty():
			continue
		var specs: Array = map_data.get("bossSpawns", [])
		if specs.is_empty() and not (map_data.get("bossSpawn", null) is Dictionary):
			continue
		GameState.mark_visited(map_id)

func _rows_of(rows: Array[Dictionary], map_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row in rows:
		if String(row.get("map_id", "")) == map_id:
			out.append(row)
	return out

func _find(rows: Array[Dictionary], map_id: String, monster_id: String, ordinal: int) -> Dictionary:
	for row in rows:
		if String(row.get("map_id", "")) == map_id \
				and String(row.get("monster_id", "")) == monster_id \
				and int(row.get("ordinal", -1)) == ordinal:
			return row
	return {}
