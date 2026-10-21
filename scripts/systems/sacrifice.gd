class_name Sacrifice
extends RefCounted
## 工程 87：紫装献祭换经验（后期紫色装备出口扩展）。规则层纯函数，不持有背包或 `GameState`。
##
## 🔑 兑换率锚在 `Balance.boss_xp(装备需求等级)`：**一件紫装 = 一只同级循环 Boss 的经验**。
##    分子分母都跟 `boss_xp` 走 ⇒ 占刷图进度的比例恒定（≈35%），不随等级漂移。
## 🔴 **必须按装备需求等级计价，不能按玩家当前等级。** 循环图 Boss 全部 `respawnTime = 600`，
##    每小时可持续击杀上限与等级无关；若按玩家等级计价，「回低档图秒杀刷紫装」立刻成为最优解
##    （L61 档一件只值 `boss_xp(61)`，玩家 80 级时按 80 级算等于白赚 87%）。
## 🔴 星级加成与卖价 `Shop.STAR_SELL_BONUS` 同构（0.08），玩家不必记第二套规则。
##
## 本类只吃一个 item 字典或一个背包数组；`GameState.sacrifice_purple` 负责重定位与扣件。

## 一件紫装换「几只同级 Boss」的经验。
const RATIO := 1.0
## 每星加成，与 `Shop.STAR_SELL_BONUS` 同值。
const STAR_BONUS := 0.08
## 低于此等级不开放：护住产品 13 D-20「一章 500—700 只 ≈ 1.5—2h」的前 60 级节奏锚点。
const OPEN_LEVEL := 61
## 单次上限：`GameState.add_xp` 内部是 while 连升，一次喂上百件会刷几十条升级提示。
const MAX_BATCH := 20

## 是否是可献祭的紫装：装备 / 传说 / 未收藏 / 星级与档位合法。
## 12★ **算合格**（允许手动选），但 `plan()` 默认不计入 —— 12★ 是保星底件。
static func eligible(item: Dictionary) -> bool:
	if item.is_empty():
		return false
	if String(item.get("kind", "")) != "equip":
		return false
	if String(item.get("quality", "")) != "legendary":
		return false
	if bool(item.get("favorite", false)):
		return false
	var star := int(item.get("star", -1))
	if star < 0 or star > Upgrade.max_star():
		return false
	if Equipment.level_req(item) <= 0 or Equipment.item_kind(item).is_empty():
		return false
	return true

## 单件经验：`round(boss_xp(需求等级) × RATIO × (1 + star × STAR_BONUS))`。
static func xp_of(item: Dictionary) -> int:
	if not eligible(item):
		return 0
	var star := int(item.get("star", 0))
	var raw := float(Balance.boss_xp(Equipment.level_req(item))) * RATIO \
		* (1.0 + float(star) * STAR_BONUS)
	return maxi(0, int(round(raw)))

## 扫描整个背包，返回一次献祭的计划。**只取前 `MAX_BATCH` 件，低档优先**
## （低档件是最没用的料，先吃它；高档件留给四紫与保星）。
##
## 返回字段：
## - `ok` / `count` / `xp` / `ids`：本次将消耗的件数、经验与实例 ID
## - `groups`：`[{tier, count, xp}]`，按档位升序，供界面分组显示
## - `star12_count` / `star12_xp`：12★ 的件数与经验（默认不计入，界面据此提示）
## - `remaining`：合格但超出单次上限的件数
static func plan(inventory: Array, include_max_star: bool = false) -> Dictionary:
	var max_star_value := Upgrade.max_star()
	var normal: Array[Dictionary] = []
	var maxed: Array[Dictionary] = []
	var maxed_xp := 0
	for entry in inventory:
		if not entry is Dictionary:
			continue
		var item: Dictionary = entry
		if not eligible(item):
			continue
		if int(item.get("star", 0)) >= max_star_value:
			maxed.append(item)
			maxed_xp += xp_of(item)
		else:
			normal.append(item)
	normal.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var la := Equipment.level_req(a)
		var lb := Equipment.level_req(b)
		if la != lb:
			return la < lb
		return int(a.get("star", 0)) < int(b.get("star", 0)))
	if include_max_star:
		maxed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var la := Equipment.level_req(a)
			var lb := Equipment.level_req(b)
			if la != lb:
				return la < lb
			return int(a.get("star", 0)) < int(b.get("star", 0)))
		normal.append_array(maxed)
	var take := mini(normal.size(), MAX_BATCH)
	var buckets := {}
	var total := 0
	var ids := PackedStringArray()
	for i in range(take):
		var item: Dictionary = normal[i]
		var tier := ItemFactory.suit_start(Equipment.level_req(item))
		var gain := xp_of(item)
		total += gain
		ids.append(String(item.get("instanceId", "")))
		if not buckets.has(tier):
			buckets[tier] = {"tier": tier, "count": 0, "xp": 0}
		var bucket: Dictionary = buckets[tier]
		bucket["count"] = int(bucket["count"]) + 1
		bucket["xp"] = int(bucket["xp"]) + gain
	var keys: Array = buckets.keys()
	keys.sort()
	var groups: Array[Dictionary] = []
	for key in keys:
		var group: Dictionary = buckets[key]
		groups.append(group)
	return {
		"ok": take > 0,
		"count": take,
		"xp": total,
		"ids": ids,
		"groups": groups,
		"star12_count": maxed.size(),
		"star12_xp": maxed_xp,
		"remaining": normal.size() - take,
	}
