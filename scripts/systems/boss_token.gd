class_name BossToken
extends RefCounted
## M10-5（产品 13 §5.4）：追猎令牌的**唯一查询入口**。
##
## 三条约定的来历：
## 1. **只在面板打开时调一次** `rows()`。产品明确禁止在 `_process` 里重算 36 图 × N 条；
##    面板侧只缓存行节点、每 0.25s 刷新倒计时文字（工程 46 §6 R-4）。
## 2. 状态一律读 `GameState.spawn_remaining`，与 Boss 墓碑**同源**。两处各算一份必然分叉。
## 3. `ordinal` 必须与 Spawner 装配时分配的完全一致 —— 它和墓碑共用
##    `spawn_key(map, monster_id, ordinal)`。Spawner 的序号是**跨 `spawnPoints` → boss
##    两次装配连续累加**的，所以这里也必须先把普通点累加一遍（`_boss_ordinals`），
##    不能想当然地写 0。`DataLoader` 另有启动校验禁止 Boss 与普通点同名，
##    但规则仍按真实语义算，不依赖那条校验过关。

## 面板需要的全部行，已按「当前图置顶 → 推荐等级升序 → 数据顺序」排好。
## 字段：map_id / map_name / monster_id / monster_name / ordinal / level / drop_level /
##       remaining / alive / world_pos / is_current_map / unlocked
static func rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var player_level := int(GameState.player.level)
	var order := 0
	for entry in DataLoader.get_table("maps"):
		if not entry is Dictionary:
			continue
		var map_data: Dictionary = entry
		var map_id := String(map_data.get("id", ""))
		if map_id.is_empty():
			continue
		# 当前图强制保留：visited 漏标（旧档 / 直接切图）不该让令牌对自己脚下这张图失明。
		if not GameState.is_visited(map_id) and map_id != GameState.current_map:
			continue
		var specs := _boss_specs(map_data)
		if specs.is_empty():
			continue
		var ordinals := _boss_ordinals(map_data)
		var is_current := map_id == GameState.current_map
		for i in range(specs.size()):
			var spec: Dictionary = specs[i]
			var monster_id := String(spec.get("monsterId", ""))
			if monster_id.is_empty():
				continue
			out.append(_row(map_data, spec, monster_id, int(ordinals[i][1]), player_level, is_current, order))
			order += 1
	out.sort_custom(_compare)
	return out

## 该图全部 Boss 的 (monster_id, ordinal)，供测试与 Spawner 的真实装配逐个核对。
static func keys_of(map_id: String) -> Array:
	var map_data: Variant = DataLoader.get_entry("maps", map_id)
	if not map_data is Dictionary:
		return []
	var out: Array = []
	for pair in _boss_ordinals(map_data as Dictionary):
		out.append({"monster_id": String(pair[0]), "ordinal": int(pair[1])})
	return out

# ---- 内部 ----

## `bossSpawns` 数组优先，回退单点 `bossSpawn`（与 `MapService.current_bosses_of` 同口径）。
static func _boss_specs(map_data: Dictionary) -> Array:
	var rows_v: Variant = map_data.get("bossSpawns", null)
	if rows_v is Array and not (rows_v as Array).is_empty():
		return rows_v
	var single: Variant = map_data.get("bossSpawn", null)
	return [single] if single is Dictionary else []

## 复刻 `MonsterSpawner` 的序号分配：先按 `spawnPoints` 累加同种计数，再给 Boss 逐个取号。
## ⚠ 就算今天全库 Boss 与普通点零重叠（序号恒 0），也照真实规则算 —— 一旦将来重叠，
## 这里错了就会「令牌说存活、其实在冷却」，而那种错只会在运行期慢慢显形。
static func _boss_ordinals(map_data: Dictionary) -> Array:
	var counter := {}
	for spec in map_data.get("spawnPoints", []):
		if not spec is Dictionary:
			continue
		var mid := String((spec as Dictionary).get("monsterId", (spec as Dictionary).get("id", "")))
		if mid.is_empty():
			continue
		var count := maxi(1, int((spec as Dictionary).get("count", 1)))
		counter[mid] = int(counter.get(mid, 0)) + count
	var out: Array = []
	for spec in _boss_specs(map_data):
		if not spec is Dictionary:
			continue
		var mid := String((spec as Dictionary).get("monsterId", (spec as Dictionary).get("id", "")))
		var ordinal := int(counter.get(mid, 0))
		counter[mid] = ordinal + 1
		out.append([mid, ordinal])
	return out

static func _row(map_data: Dictionary, spec: Dictionary, monster_id: String, ordinal: int,
		player_level: int, is_current: bool, order: int) -> Dictionary:
	var map_id := String(map_data.get("id", ""))
	var level := _level_for(map_data, spec, player_level)
	var remaining := GameState.spawn_remaining(map_id, monster_id, ordinal)
	return {
		"map_id": map_id,
		"map_name": String(map_data.get("name", map_id)),
		"monster_id": monster_id,
		"monster_name": _monster_name(monster_id),
		"ordinal": ordinal,
		"level": level,
		"drop_level": level,
		"remaining": remaining,
		"alive": remaining <= 0.0,
		"world_pos": _world_pos(spec),
		"is_current_map": is_current,
		"unlocked": MapService.is_unlocked(map_id),
		"recommended_level": int(map_data.get("recommendedLevel", 1)),
		"order": order,
	}

## `levelFromPlayer` 的图（循环图）跟随玩家等级；存量图读规格 `level`，再回退推荐等级。
static func _level_for(map_data: Dictionary, spec: Dictionary, player_level: int) -> int:
	var from_player: Variant = map_data.get("levelFromPlayer", null)
	if from_player is Dictionary and bool((from_player as Dictionary).get("enabled", false)):
		return maxi(int((from_player as Dictionary).get("minLevel", 1)), player_level)
	var raw := int(spec.get("level", 0))
	if raw > 0:
		return raw
	return int(map_data.get("recommendedLevel", 1))

## 与 `MonsterSpawner` 取点规则一致：`cells[i]` 优先，回退 `cell`（Boss 的 count 恒 1 ⇒ i = 0）。
static func _world_pos(spec: Dictionary) -> Vector2:
	var cells: Variant = spec.get("cells", null)
	var cell: Variant = cells[0] if cells is Array and not (cells as Array).is_empty() else spec.get("cell", null)
	if cell is Array and (cell as Array).size() == 2:
		return Iso.grid_to_world(Vector2i(int(cell[0]), int(cell[1])))
	return Vector2.ZERO

static func _monster_name(monster_id: String) -> String:
	var tpl: Variant = DataLoader.get_entry("monsters", monster_id)
	if tpl is Dictionary:
		return String((tpl as Dictionary).get("name", monster_id))
	return monster_id

## 当前图置顶 → 推荐等级升序 → 数据顺序（最后一项让排序结果确定，不依赖不稳定排序）。
static func _compare(a: Dictionary, b: Dictionary) -> bool:
	if bool(a.get("is_current_map", false)) != bool(b.get("is_current_map", false)):
		return bool(a.get("is_current_map", false))
	if int(a.get("recommended_level", 1)) != int(b.get("recommended_level", 1)):
		return int(a.get("recommended_level", 1)) < int(b.get("recommended_level", 1))
	return int(a.get("order", 0)) < int(b.get("order", 0))
