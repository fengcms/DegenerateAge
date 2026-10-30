class_name GoldExchange
extends RefCounted
## 仓库兑换台：金币 ↔ 金条 ↔ 金砖（工程 109）。
##
## 职责：**只算汇率与可行性**，不写任何全局状态。真正落账只有
## `GameState.exchange()` 一个入口 —— 与 `Shop` / `Warehouse` 同构的两层切分：
## 纯逻辑可被测试单点验证，落账唯一。
##
## 🔑 汇率唯一来源是 `data/exchange.json`，四条**显式写出**而不互相推导：
## 金币→金条 1,000,000:1 ｜ 金条→金砖 10:1 ｜ 金条→金币 1:1,000,000 ｜ 金砖→金币 1:10,000,000。
## 将来要做「回收折价」，改数据即可，不会出现「砖靠条推导、条靠常量」的漂移。
##
## 🔑 `plan()` 是核心：它返回**目标状态**（扣源、加货之后的仓库副本与金币数），
## 调用方一次性赋值即可。这样「扣了钱没给货」在结构上不可能发生 ——
## 不是靠顺序小心，而是根本没有中间态。
##
## 🔴 本文件里**不允许出现 99 这个数字**：堆叠上限一律走 `ItemUtil.stack_max()`。
## 手写 99 会在有人改默认上限时变成两套口径，且没有任何断言会红。

const GOLD := "gold"
const TABLE := "exchange"

## 源物不足时的专属文案：条目 id → 本地化 key。
## 未登记的物品回落到通用失败文案（新增兑换对时补一行即可）。
const SHORT_KEYS := {
	"gold_ingot": "msg.exchange.p002",
	"gold_brick": "msg.exchange.p003",
}

# ---- 读配置 ----

## 全部兑换对（exchange.json 的 pairs 数组）。
static func pairs() -> Array:
	var cfg: Variant = DataLoader.get_table(TABLE)
	if not cfg is Dictionary:
		return []
	var rows: Variant = (cfg as Dictionary).get("pairs", [])
	return rows as Array if rows is Array else []

## 取一条兑换对，不存在返回空字典。
static func pair(pair_id: String) -> Dictionary:
	for row in pairs():
		if not row is Dictionary:
			continue
		if String((row as Dictionary).get("id", "")) == pair_id:
			return row as Dictionary
	return {}

# ---- 物品与容器探针 ----

## 兑换目标的物品实例；`gold`（不是物品）与非法 id 返回空字典。
static func stack_item(item_id: String, count: int) -> Dictionary:
	if item_id.is_empty() or item_id == GOLD or count <= 0:
		return {}
	if not (DataLoader.get_entry("miscItems", item_id) is Dictionary):
		return {}
	return {"kind": "misc", "itemId": item_id, "count": count}

## 仓库内某物品的总数量（按 itemId 汇总所有堆）。
static func count_in(store: Array, item_id: String) -> int:
	var total := 0
	for entry in store:
		if entry is Dictionary and String((entry as Dictionary).get("itemId", "")) == item_id:
			total += int((entry as Dictionary).get("count", 1))
	return total

## 仓库还能再容纳多少块该物品（现有堆的余量 + 空格）。
## 只用于「可换 N 次」的展示估算；**放不放得下由 `Inventory.add` 在副本上试算**。
static func room_in(store: Array, item_id: String) -> int:
	var probe := stack_item(item_id, 1)
	if probe.is_empty():
		return 0
	var maximum := maxi(1, ItemUtil.stack_max(probe))
	var total := 0
	for entry in store:
		if entry == null:
			total += maximum
		elif entry is Dictionary and String((entry as Dictionary).get("itemId", "")) == item_id:
			total += maxi(0, maximum - int((entry as Dictionary).get("count", 1)))
	return total

# ---- 判定 ----

## 核心：试算目标状态。返回 `{ok, reason, store, gold}`。
## `ok=true` 时 `store` 是**扣源、加货之后**的仓库副本，`gold` 是兑换后的金币数；
## 调用方把这两个值一次赋回去即可，中间不存在「钱扣了货没到」的窗口。
static func plan(pair_id: String, times: int) -> Dictionary:
	var row := pair(pair_id)
	if row.is_empty() or times < 1:
		return _fail(Localization.tr_key("msg.exchange.p007"))
	var from_id := String(row.get("from", ""))
	var to_id := String(row.get("to", ""))
	var from_count := int(row.get("fromCount", 0)) * times
	var to_count := int(row.get("toCount", 0)) * times
	if from_count <= 0 or to_count <= 0 or from_id == to_id:
		return _fail(Localization.tr_key("msg.exchange.p007"))

	var gold_after := GameState.gold
	var store: Array = GameState.warehouse.duplicate(true)
	# 1) 扣源
	if from_id == GOLD:
		if gold_after < from_count:
			return _fail(Localization.tr_key("msg.exchange.p001") % from_count)
		gold_after -= from_count
	else:
		if count_in(store, from_id) < from_count:
			return _fail(_short_text(from_id) % from_count)
		store = _store_without(store, from_id, from_count)
	# 2) 加目标
	if to_id == GOLD:
		# 🔴 金币上限必须在这里拒绝：`add_gold` 的 `clampi` 会把玩家兑回却超上限的
		# 部分静默吞掉 —— 那不是"上限处理"，是把储值删掉（109 方案 §5.1）。
		if gold_after + to_count > GameState.GOLD_CAP:
			return _fail(Localization.tr_key("msg.exchange.p005"))
		gold_after += to_count
	else:
		if not Inventory.add(store, stack_item(to_id, to_count)):
			return _fail(Localization.tr_key("msg.exchange.p004"))
	return {"ok": true, "reason": "", "store": store, "gold": gold_after}

## 只判不写（UI 禁用态 / 测试用）。返回 `{ok, reason}`，`reason` 是给玩家看的中文。
static func check(pair_id: String, times: int) -> Dictionary:
	var p := plan(pair_id, times)
	return {"ok": bool(p.get("ok", false)), "reason": String(p.get("reason", ""))}

## 当前状态下这条兑换最多能做几次（源数量 / 目标容量 / 金币上限三者取小）。
## UI 用它显示「可换 N 次」，也用它实现 Shift 全换。
static func max_times(pair_id: String) -> int:
	var row := pair(pair_id)
	if row.is_empty():
		return 0
	var from_id := String(row.get("from", ""))
	var to_id := String(row.get("to", ""))
	var from_count := int(row.get("fromCount", 0))
	var to_count := int(row.get("toCount", 0))
	if from_count <= 0 or to_count <= 0:
		return 0
	var by_source := 0
	if from_id == GOLD:
		by_source = GameState.gold / from_count
	else:
		by_source = count_in(GameState.warehouse, from_id) / from_count
	if by_source <= 0:
		return 0
	if to_id == GOLD:
		return mini(by_source, maxi(0, GameState.GOLD_CAP - GameState.gold) / to_count)
	# 目标进仓库：按「源被扣掉之后」的仓库存量算余量 —— 否则「99 块条换 9 砖」
	# 会少算一格（源堆扣空后腾出的格子本就能放砖）。
	var after := _store_without(GameState.warehouse.duplicate(true), from_id, from_count * by_source)
	return mini(by_source, room_in(after, to_id) / to_count)

## 成功提示里的「得到什么」，如「金条 ×1」/「金币 1000000」。
static func got_text(pair_id: String, times: int) -> String:
	var row := pair(pair_id)
	if row.is_empty():
		return ""
	var to_id := String(row.get("to", ""))
	var count := int(row.get("toCount", 0)) * maxi(1, times)
	if to_id == GOLD:
		return ItemUtil.display_name({"kind": "coin", "gold": count})
	return ItemUtil.display_name({"kind": "misc", "itemId": to_id, "count": count})

# ---- 内部 ----

## 从仓库副本中扣除指定物品若干块（跨堆），扣空的格置 null。
static func _store_without(store: Array, item_id: String, amount: int) -> Array:
	if item_id.is_empty() or amount <= 0:
		return store
	var left := amount
	for i in range(store.size()):
		if left <= 0:
			break
		var entry: Variant = store[i]
		if not entry is Dictionary:
			continue
		if String((entry as Dictionary).get("itemId", "")) != item_id:
			continue
		var have := int((entry as Dictionary).get("count", 1))
		var take := mini(have, left)
		left -= take
		if take >= have:
			store[i] = null
		else:
			var kept := (entry as Dictionary).duplicate(true)
			kept["count"] = have - take
			store[i] = kept
	return store

static func _short_text(item_id: String) -> String:
	var key := String(SHORT_KEYS.get(item_id, "msg.exchange.p007"))
	return Localization.tr_key(key)

static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "store": [], "gold": 0}
