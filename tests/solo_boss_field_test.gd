extends Node
## 工程 91「孤王绝域」契约：单席 / 倍率 / 双重门槛 / 布局 / 十倍件数 / **掉落 +10 级** / 回廊第四出口。
##
## 核心底线：这份配置一旦退化，游戏**能跑、能进、能打、不报错** ——
## 只是「血 20 倍」变成普通 Boss、「十倍掉落」变成一倍、装备等级还是玩家等级。
## 所以断言全部压在具体数值上，不断「有没有这张图」。

const MAP_ID := "c7_solo_boss"
const ARENA_ID := "c7_arena"
const HUB_ID := "c6_map00"
const DROP_TABLE := "DT_C7_Solo_Boss"
const ARENA_TABLE := "DT_C7_Arena_Boss"
const LAYOUT_PATH := "res://data/layouts/c7_solo_boss.json"
const ARENA_LAYOUT_PATH := "res://data/layouts/c7_arena.json"
const ENTRY_CELL := [6, 15]
const BOSS_CELL := [20, 15]

var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("[SoloBossFieldTest] " + label)

func _ready() -> void:
	_test_topology()
	_test_single_seat()
	_test_multipliers()
	_test_gate()
	_test_layout()
	_test_count_multiplier()
	_test_level_offset()
	_test_arena_exit()
	GameState.reset_to_defaults()
	if failures.is_empty():
		print("[SoloBossFieldTest] 全部通过 ✅")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("[SoloBossFieldTest] 失败 %d 项" % failures.size())
		get_tree().quit(1)

# ---- 1) 拓扑 ----

func _test_topology() -> void:
	var found: Variant = DataLoader.get_entry("maps", MAP_ID)
	check(found is Dictionary, "%s 必须登记在地图索引中" % MAP_ID)
	if not found is Dictionary:
		return
	var data: Dictionary = found
	check(String(data.get("kind", "")) == "spoke", "孤王绝域 kind 应为 spoke")
	check(String(data.get("hubId", "")) == HUB_ID, "孤王绝域 hubId 应为 %s" % HUB_ID)
	check(String(data.get("requiresUnlock", "")) == "campaign_complete",
		"孤王绝域解锁条件应为 campaign_complete（与另三张循环图同一把钥匙）")
	check(not data.has("tierRange"), "循环图**不许**写 tierRange（等级由玩家等级现算）")
	var from_player: Variant = data.get("levelFromPlayer", null)
	check(from_player is Dictionary and bool((from_player as Dictionary).get("enabled", false)),
		"孤王绝域必须配 levelFromPlayer.enabled")
	if from_player is Dictionary:
		check(int((from_player as Dictionary).get("minLevel", 0)) == 100,
			"levelFromPlayer.minLevel 应为 100")
	var size: Dictionary = data.get("size", {})
	check(int(size.get("w", 0)) == 40 and int(size.get("h", 0)) == 30,
		"孤王绝域应是 40×30 的小图，实际 %s×%s" % [size.get("w"), size.get("h")])
	check(bool(data.get("preserveUnclaimedLoot", false)),
		"孤王绝域必须 preserveUnclaimedLoot（一只爆 85 件、背包 40 格必然捡不完）")
	check(int(data.get("unclaimedLootCap", 0)) == 600,
		"未领取上限应为 600（85 件装备 + 药水如意），实际 %d" % int(data.get("unclaimedLootCap", 0)))

# ---- 2) 单席 ----

func _test_single_seat() -> void:
	var data: Dictionary = DataLoader.get_entry("maps", MAP_ID)
	var seats: Array = data.get("bossSpawns", [])
	check(seats.size() == 1, "孤王绝域应恰好 1 条 bossSpawns，实际 %d" % seats.size())
	check(int(data.get("bossCap", 0)) == 1, "bossCap 应为 1，实际 %d" % int(data.get("bossCap", 0)))
	check(int(data.get("normalCap", -1)) == 0, "normalCap 应为 0（不许普通怪分摊预算）")
	check(int(data.get("eliteCap", -1)) == 0, "eliteCap 应为 0")
	check((data.get("spawnPoints", []) as Array).is_empty(), "不应有普通刷新区")
	if seats.size() != 1:
		return
	var seat: Dictionary = seats[0]
	var mid := String(seat.get("monsterId", ""))
	check(mid == "boss_corrupted_beast", "固定单王应为 boss_corrupted_beast，实际 %s" % mid)
	check(String(seat.get("kind", "")) == "boss", "席位 kind 必须是 boss")
	check(bool(seat.get("scaleStats", false)), "必须开 scaleStats")
	check(bool(seat.get("xpFromCurve", false)), "必须开 xpFromCurve")
	check(bool(seat.get("tombstone", false)), "必须落墓碑（跨图可见倒计时）")
	check(String(seat.get("dropTableId", "")) == DROP_TABLE,
		"dropTableId 必须指向 %s，实际 %s" % [DROP_TABLE, String(seat.get("dropTableId", ""))])

# ---- 3) 倍率 ----

func _test_multipliers() -> void:
	var data: Dictionary = DataLoader.get_entry("maps", MAP_ID)
	var seats: Array = data.get("bossSpawns", [])
	if seats.is_empty():
		check(false, "没有 bossSpawns 可验倍率")
		return
	var seat: Dictionary = seats[0]
	check(is_equal_approx(float(seat.get("hpMultiplier", 0.0)), 20.0),
		"hpMultiplier 应为 20.0（原生血量的 20 倍 = 回廊那只的 10 倍），实际 %.2f"
		% float(seat.get("hpMultiplier", 0.0)))
	check(is_equal_approx(float(seat.get("xpMultiplier", 0.0)), 5.0),
		"xpMultiplier 应为 5.0，实际 %.2f" % float(seat.get("xpMultiplier", 0.0)))
	# 🔴 重生 1800 秒是**产品定位**（半小时一只、不为刷），不是配错也不会被「优化」掉。
	# 调成 600 会让它变成另一张百首禁域；调成 120 会变成刷图。改这里必须同步工程 91 §Q4。
	check(is_equal_approx(float(seat.get("respawnTime", 0.0)), 1800.0),
		"重生应为 1800 秒（半小时一只），实际 %.0f" % float(seat.get("respawnTime", 0.0)))
	# 100 级满装防御 13,985（减伤 6,992）> Boss 攻击 420×S(40)=3,159 ⇒ 攻击倍率配了也走保底 60。
	check(not seat.has("atkMultiplier") or is_equal_approx(float(seat.get("atkMultiplier", 1.0)), 1.0),
		"孤王绝域不应叠加攻击倍率（破不了防，配了等于没配；难度落在血量与时长上）")

# ---- 4) 双重门槛：100 级 + 全身紫装 ----

func _test_gate() -> void:
	var data: Dictionary = DataLoader.get_entry("maps", MAP_ID)
	var gate: Variant = data.get("entryGate", null)
	check(gate is Dictionary, "孤王绝域必须配 entryGate")
	if not gate is Dictionary:
		return
	var g: Dictionary = gate
	check(String(g.get("walkOnlyFrom", "")) == ARENA_ID,
		"只能从无尽回廊步行进入，实际 %s" % String(g.get("walkOnlyFrom", "")))
	check(int(g.get("minLevel", 0)) == 100, "minLevel 应为 100，实际 %d" % int(g.get("minLevel", 0)))
	# 🔑 项目里「紫」= legendary（QUALITY_COLOR.legendary = #b46ae0，文案写「传说（紫色）」）。
	# 与百首禁域同一字段同一取值；写成 "epic" 会把门槛错降一档而毫无报错。
	check(String(g.get("allEquipmentQuality", "")) == "legendary",
		"必须要求全身紫装（quality == legendary），实际「%s」" % String(g.get("allEquipmentQuality", "")))

	# 99 级 + 全紫 → 被等级拦下；100 级 + 全紫 → 放行。
	_dress("legendary")
	GameState.player.level = 99
	GameState.current_map = ARENA_ID
	var low_reason := MapService.entry_gate_reason(MAP_ID, "walk", ARENA_ID)
	check(not low_reason.is_empty(), "99 级即使全身紫装也必须被拒")
	check(low_reason.contains("100"), "拒绝原因应点明需要 100 级，实际「%s」" % low_reason)
	GameState.player.level = 100
	var ok_reason := MapService.entry_gate_reason(MAP_ID, "walk", ARENA_ID)
	check(ok_reason.is_empty(), "100 级 + 全身紫装应放行，实际被拒：「%s」" % ok_reason)

	# 少一槽紫 → 被拒，且原因必须点出「是哪一槽」（只说「不满足」玩家没法修）。
	var slot_id := String((Equipment.SLOT_DEFS[0] as Dictionary).id)
	var slot_label := String((Equipment.SLOT_DEFS[0] as Dictionary).label)
	GameState.equipment[slot_id] = {"kind": "equip", "itemId": "c6_equip_sword", "quality": "epic"}
	var partial := MapService.entry_gate_reason(MAP_ID, "walk", ARENA_ID)
	check(not partial.is_empty(), "14 槽缺 1 槽紫装必须被拒")
	check(partial.contains(slot_label), "拒绝原因应点名缺的那一槽「%s」，实际「%s」" % [slot_label, partial])
	_dress("legendary")

	# 步行来源不对 → 拒（快捷旅行必须先被 walkOnlyFrom 挡住）。
	var wrong_from := MapService.entry_gate_reason(MAP_ID, "walk", HUB_ID)
	check(not wrong_from.is_empty(), "从 %s 步行直入必须被拒" % HUB_ID)
	var anywhere := MapService.travel_anywhere(MAP_ID)
	check(not bool(anywhere.get("ok", true)), "随身车夫不得直达孤王绝域")
	GameState.current_map = HUB_ID

# ---- 5) 布局 ----

func _test_layout() -> void:
	var parsed := _layout(LAYOUT_PATH)
	check(not parsed.is_empty(), "布局 %s 必须可解析" % LAYOUT_PATH)
	if parsed.is_empty():
		return
	var map_data: Dictionary = DataLoader.get_entry("maps", MAP_ID)
	var size_data: Dictionary = map_data.get("size", {})
	var grid: Array = parsed.get("grid_size", [])
	check(grid.size() == 2 and int(grid[0]) == int(size_data.get("w", 0))
		and int(grid[1]) == int(size_data.get("h", 0)),
		"布局 grid_size 必须与 map.json 的 size 一致（%s vs %s）" % [str(grid), str(size_data)])
	var rows: Array = parsed.get("walkable_rows", [])
	check(rows.size() == int(grid[1]), "walkable_rows 行数应等于地图高度")
	if rows.is_empty():
		return
	check(_is_walkable(rows, ENTRY_CELL), "入口 %s 必须可走" % str(ENTRY_CELL))
	check(_is_walkable(rows, BOSS_CELL), "Boss 席 %s 必须可走" % str(BOSS_CELL))
	var seats: Array = map_data.get("bossSpawns", [])
	if not seats.is_empty():
		# ⚠ JSON 里的坐标解析出来是 float（[20.0, 15.0]），直接与 [20, 15] 比会恒不相等 ——
		# 逐元素取 int 比，别用数组相等。
		check(_cell_is((seats[0] as Dictionary).get("cell", null), int(BOSS_CELL[0]), int(BOSS_CELL[1])),
			"Boss 席必须落在 %s，实际 %s" % [str(BOSS_CELL), str((seats[0] as Dictionary).get("cell", null))])
	# 全连通：有孤岛 ⇒ 玩家走不到 Boss，但配置上看不出任何异常。
	var total := _walkable_total(rows)
	var reached := _reachable_count(rows, Vector2i(int(ENTRY_CELL[0]), int(ENTRY_CELL[1])))
	check(reached == total, "可走格必须全连通：从入口只到 %d / %d" % [reached, total])

# ---- 6) 十倍件数（逐组比值，不是「总和够大」）----

func _test_count_multiplier() -> void:
	var base := _equip_groups(ARENA_TABLE)
	var solo := _equip_groups(DROP_TABLE)
	check(base.size() == 3, "回廊掉落表应有 3 组装备，实际 %d" % base.size())
	check(solo.size() == 3, "孤王绝域掉落表应有 3 组装备，实际 %d" % solo.size())
	for key in base.keys():
		check(solo.has(key), "孤王绝域缺少品质组 %s" % String(key))
		if not solo.has(key):
			continue
		var b: Dictionary = base[key]
		var s: Dictionary = solo[key]
		var b_span: Array = b.get("count", [])
		var s_span: Array = s.get("count", [])
		var b_mid := (float(b_span[0]) + float(b_span[1])) * 0.5
		var s_mid := (float(s_span[0]) + float(s_span[1])) * 0.5
		check(is_equal_approx(s_mid, b_mid * 10.0),
			"组 %s 的件数应恰好是回廊的 10 倍：回廊 %s → 期望 %s，实际 %s"
			% [String(key), str(b_span), str(b_mid * 10.0), str(s_span)])
		# 🔴 放大的是**件数**，不是概率：回廊三组 chance 全是 1.0，改概率根本改不动。
		check(is_equal_approx(float(s.get("chance", -1.0)), float(b.get("chance", -2.0))),
			"组 %s 的 chance 必须与回廊一致（放大件数，不改概率）：%s vs %s"
			% [String(key), str(b.get("chance")), str(s.get("chance"))])
		# 等级偏移只加在装备上，且三组一致。
		check(int(s.get("levelOffset", 0)) == 10,
			"组 %s 的 levelOffset 应为 10（比玩家高 10 级），实际 %d" % [String(key), int(s.get("levelOffset", 0))])
		check(bool(s.get("levelFromBoss", false)), "组 %s 必须 levelFromBoss（等级跟随击杀目标）" % String(key))

# ---- 7) 掉落 +10 级（本需求的核心判据）----

func _test_level_offset() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 91022
	var seen := {}
	var equip_count := 0
	for _i in range(6):
		var drops: Array = Loot.roll(DROP_TABLE, rng, "boss_corrupted_beast", 100)
		for raw in drops:
			if not raw is Dictionary:
				continue
			var item: Dictionary = raw
			if String(item.get("kind", "")) != "equip":
				continue
			equip_count += 1
			seen[int(item.get("requiredLevel", 0))] = true
			# 存档硬约束：实例等级与 requiredLevel 必须相等，否则读档会被逐件剔除。
			check(int(item.get("level", -1)) == int(item.get("requiredLevel", -2)),
				"实例 level 必须等于 requiredLevel（%d vs %d）" % [
					int(item.get("level", -1)), int(item.get("requiredLevel", -2))])
	check(equip_count > 0, "孤王绝域必须产出装备，实际 0 件")
	var keys: Array = seen.keys()
	keys.sort()
	if keys.is_empty():
		return
	var low := int(keys[0])
	var high := int(keys[keys.size() - 1])
	# 🔴 必须**双向**断：只断「≥101」的话，levelOffset 写成 20 也照样绿。
	check(low == 101, "最低装备等级应为 101（武器，套起点 101），实际 %d" % low)
	check(high == 110, "最高装备等级应为 110（项链，套末），实际 %d" % high)
	for key in keys:
		check(int(key) >= 101 and int(key) <= 110,
			"装备等级 %d 越界（应落在 101—110）" % int(key))
	# 101—110 是下一套：100 级玩家一件都穿不上，这是「期货」不是 bug。
	var probe: Dictionary = {"kind": "equip", "requiredLevel": 101, "level": 101, "quality": "legendary"}
	check(not Equipment.meets_level(probe, 100),
		"101 级装备在 100 级玩家身上必须判定为「穿不上」（level == requiredLevel 硬约束）")

# ---- 8) 回廊第四出口 ----

func _test_arena_exit() -> void:
	var arena: Dictionary = DataLoader.get_entry("maps", ARENA_ID)
	var exits: Array = arena.get("exits", [])
	var solo_exit: Variant = null
	for raw in exits:
		if raw is Dictionary and String((raw as Dictionary).get("toMap", "")) == MAP_ID:
			solo_exit = raw
	check(solo_exit != null, "无尽回廊必须有通往 %s 的出口" % MAP_ID)
	if solo_exit is Dictionary:
		var cell: Variant = (solo_exit as Dictionary).get("cell", null)
		check(_cell_is(cell, 152, 45), "孤王绝域入口应在东侧 [152,45]，实际 %s" % str(cell))
		var entr: Variant = arena.get("entrances", {})
		check(entr is Dictionary and (entr as Dictionary).get("from_%s" % MAP_ID) == cell,
			"回廊 entrances[from_%s] 必须与东侧出口同格（否则从孤王绝域回来会卡墙）" % MAP_ID)

	var parsed := _layout(ARENA_LAYOUT_PATH)
	check(not parsed.is_empty(), "回廊布局必须可解析")
	if parsed.is_empty():
		return
	var points: Variant = parsed.get("points", {})
	check(points is Dictionary, "回廊布局必须含 points")
	if not points is Dictionary:
		return
	var pmap: Dictionary = points
	check(pmap.has("c7_arena_exit04"), "回廊布局必须登记东侧出口 c7_arena_exit04")
	# 🔴 加出口**不许**动到原有 20 席：坐标漂移会让玩家进图后面对一张陌生的回廊。
	var seats: Array = arena.get("bossSpawns", [])
	for index in range(seats.size()):
		var key := "spawn%03d" % index
		var expected: Variant = (seats[index] as Dictionary).get("cell", null)
		check(pmap.get(key) == expected,
			"回廊 %s 的坐标必须与 map.json 一致（%s vs %s）" % [key, str(pmap.get(key)), str(expected)])

# ---- 辅助 ----

## 按槽位穿上一整套 `quality` 装备（真实 100 级循环型号，不用假 dict —— 门槛验的是真链路）。
func _dress(quality: String) -> void:
	var by_kind := {}
	var table: Variant = DataLoader.get_table("equipments")
	if table is Array:
		for raw in table:
			if not raw is Dictionary:
				continue
			var tpl: Dictionary = raw
			if bool(tpl.get("debug", false)) or not bool(tpl.get("lootable", true)):
				continue
			var bases: Variant = tpl.get("tierBases", {})
			if not bases is Dictionary or not (bases as Dictionary).has(str(ItemFactory.DYNAMIC_BASE_TIER)):
				continue
			var kind := String(tpl.get("slot", ""))
			if not by_kind.has(kind):
				by_kind[kind] = String(tpl.get("id", ""))
	GameState.equipment = {}
	for slot_def in Equipment.SLOT_DEFS:
		var def: Dictionary = slot_def
		var kind := String(def.get("kind", ""))
		var item: Dictionary = {}
		if by_kind.has(kind):
			item = ItemFactory.make_equip_dynamic(String(by_kind[kind]), 100, quality)
		check(not item.is_empty(), "测试夹具：%s 槽缺少 100 级循环型号（%s）" % [kind, quality])
		GameState.equipment[String(def.get("id", ""))] = item

## 掉落表的装备组 → {品质组键: {chance, count, levelOffset, levelFromBoss}}。
## 键用 qualityWeight 的排序后 join，不依赖条目顺序（顺序变了也不该误判）。
func _equip_groups(table_id: String) -> Dictionary:
	var out := {}
	var table: Variant = DataLoader.get_entry("dropTables", table_id)
	if not table is Dictionary:
		return out
	for raw in (table as Dictionary).get("entries", []):
		if not raw is Dictionary:
			continue
		var entry: Dictionary = raw
		if String(entry.get("kind", "")) != "equip":
			continue
		var weights: Variant = entry.get("qualityWeight", {})
		if not weights is Dictionary:
			continue
		var keys: Array = (weights as Dictionary).keys()
		keys.sort()
		var parts: Array[String] = []
		for key in keys:
			parts.append(String(key))
		out["+".join(PackedStringArray(parts))] = {
			"chance": float(entry.get("chance", 0.0)),
			"count": entry.get("countRange", []),
			"levelOffset": int(entry.get("levelOffset", 0)),
			"levelFromBoss": bool(entry.get("levelFromBoss", false)),
		}
	return out

func _layout(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

## 格坐标比较：JSON 解析出的坐标是 float 数组，必须逐元素取 int 比，不能用数组相等。
func _cell_is(cell: Variant, x: int, y: int) -> bool:
	if not cell is Array or (cell as Array).size() != 2:
		return false
	return int((cell as Array)[0]) == x and int((cell as Array)[1]) == y

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
