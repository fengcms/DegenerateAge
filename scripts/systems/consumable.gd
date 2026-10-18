class_name Consumable
extends RefCounted
## 消耗品使用（M2.5）。
## 依据：产品文档 05 §5.11（药水数值 / 冷却口径）、03 §3.14（自动喝药）、09 §9.2（背包双击"穿戴 / 使用"）。
##
## 定位：**唯一的使用入口** —— 手动（背包双击 / 快捷键 1·2）与自动（AutoBattle）
## 都经由本层，对齐 3.14「自动只调用与玩家相同的喝药接口」的原则，**不另写一套**。
##
## 冷却（5.11）：**每种药水 item_id 独立、互不阻塞、无全局公共冷却**。
## 冷却为运行态且**不落档**（与自动战斗开关同类，10.3）：重启 / 读档清零；
## `SaveManager._collect` **不得**写入冷却表（避免污染存档 schema）。
##
## 满值不浪费：当前值已达上限时**不扣药、不进冷却**，只明确提示（不静默）。
##
## Q1 选瓶策略（用户 2026-10-12 拍板）：**按缺口选"够用的最小档"** ——
## 缺口 60 → 用回 80 的小药，不用回 220 的中药；若无一档能补足缺口，则用恢复量最大者。

## 背包物品的品类（item.kind）
const KIND_CATEGORY := "potion"
## 药水的颜色档（potions.json 模板的 kind）
const KIND_RED := "red"
const KIND_BLUE := "blue"

const STAT_HP_KEY := "msg.consumable.hp"
const STAT_MP_KEY := "msg.consumable.mp"

## 药水百分比生效的**最低等级 + 1**（M10-10 / R-21）：60 级及以下一律取固定值。
## 产品原文靠「L60 的 `maxHp × pct` ≤ 固定值」来保证 1–60 不变，但那个 2390 只是
## `common` 品质满装的数 —— 实测 L60 穿 `rare` 满装 `maxHp = 5051`，20% = 1010（越界 2 倍），
## 而打过 Boss 的玩家 60 级身上至少有 2 件 `rare`。改为按等级硬切：
## 1–60 恒固定值、**与装备品质无关** —— 把「不变」从数值巧合变成逻辑保证。
const PCT_FROM_LEVEL := 60

## item_id -> 剩余冷却秒数（运行态，不落档）
static var _cd: Dictionary = {}

# ---- 恢复量公式（M10-10）----

## 药水在「上限 cap、玩家等级 level」下的**实际恢复量**。
## `level <= PCT_FROM_LEVEL` → 恒 `restoreAmount`；
## 否则 → `max(restoreAmount, round(cap × restorePercent))`。
## 纯函数（只吃参数、不读 GameState），便于逐档回归；`restorePercent` 缺省 / 非正 / `cap <= 0`
## 一律退回固定值，保证旧数据与存档行为不变。
static func restore_of(tpl: Dictionary, cap: int, level: int) -> int:
	var fixed := int(tpl.get("restoreAmount", 0))
	var pct := float(tpl.get("restorePercent", 0.0))
	if level <= PCT_FROM_LEVEL or pct <= 0.0 or cap <= 0:
		return fixed
	return maxi(fixed, int(round(float(cap) * pct)))

## 某药水在**当前**等级与当前上限下的实际恢复量（供 UI tooltip）。
## 模板不存在返回 0，让调用方能区分「没这瓶药」与「回 0 点」。
static func preview_restore(item_id: String) -> int:
	var tpl: Variant = DataLoader.get_entry("potions", item_id)
	if not (tpl is Dictionary):
		return 0
	var t: Dictionary = tpl
	var kind := String(t.get("kind", KIND_RED))
	return restore_of(t, max_of(kind), int(GameState.player.level))

# ---- 冷却 ----

## 指定药水剩余冷却（0 = 可用）。
static func cd_of(item_id: String) -> float:
	return maxf(0.0, float(_cd.get(item_id, 0.0)))

## 冷却递减心跳。由 GameState._process 驱动（挂常驻节点，避免 UI 节点销毁导致冷却停摆）。
static func tick(delta: float) -> void:
	if _cd.is_empty():
		return
	var expired: Array = []
	for id in _cd.keys():
		var left := float(_cd[id]) - delta
		if left <= 0.0:
			expired.append(id)
		else:
			_cd[id] = left
	for id in expired:
		_cd.erase(id)

## 清空冷却（重开游戏 / 读档后调用，见 GameState.reset_to_defaults）。
static func reset() -> void:
	_cd.clear()

# ---- 使用 ----

## 使用背包中 `inv_index` 处的药水。返回 {ok, reason, itemId, kind, restored, message}。
## `silent` = true 时不广播失败提示（供自动战斗的内部尝试，避免刷屏）。
static func use(inv_index: int, silent: bool = false) -> Dictionary:
	var inv: Array = GameState.inventory
	if inv_index < 0 or inv_index >= inv.size() or inv[inv_index] == null:
		return _fail(Localization.tr_key("msg.consumable.p001"), silent)
	var item: Dictionary = inv[inv_index]
	if String(item.get("kind", "")) != KIND_CATEGORY:
		return _fail(Localization.tr_key("msg.consumable.p002"), silent)

	var item_id := String(item.get("itemId", ""))
	var tpl = DataLoader.get_entry("potions", item_id)
	if not (tpl is Dictionary):
		return _fail(Localization.tr_key("msg.consumable.p003") % item_id, silent)
	var t: Dictionary = tpl
	var kind := String(t.get("kind", KIND_RED))
	var cooldown := float(t.get("cooldown", 0.0))
	var pname := String(t.get("name", item_id))

	var left := cd_of(item_id)
	if left > 0.0:
		return _fail(Localization.tr_key("msg.consumable.p004") % [pname, left], silent)

	var cur := current_of(kind)
	var cap := max_of(kind)
	if cur >= cap:
		return _fail(Localization.tr_key("msg.consumable.p005") % stat_label(kind), silent)

	# M10-10：60 级以上按上限百分比放大（60 级及以下恒固定值，1–60 逐位不变）
	var restore := restore_of(t, cap, int(GameState.player.level))
	# 恢复量按缺口截断（5.11：恢复量不超过最大 HP / MP）
	var restored := mini(restore, cap - cur)
	_apply(kind, restored)
	_cd[item_id] = cooldown
	_consume_one(inv_index)

	var msg := "%s：%s +%d" % [pname, stat_label(kind), restored]
	EventBus.toast_requested.emit(msg, "pickup")
	return {"ok": true, "reason": "", "itemId": item_id, "kind": kind,
		"restored": restored, "message": msg}

## 选出当前应使用的药水格下标（-1 = 无可用：没有该颜色药水 / 全在冷却 / 值已满）。
## 按 Q1 策略在**未冷却**的候选里挑选。
## M10-10：候选的「恢复量」必须取**实际量**（`restore_of`），不能再用模板固定值 ——
## 高等级下小药的回量远超模板的 80，按固定值挑会一直选中大药，"够用的最小档"策略失效。
static func pick_index(kind: String) -> int:
	var cap := max_of(kind)
	var need := cap - current_of(kind)
	if need <= 0:
		return -1
	var level := int(GameState.player.level)
	var inv: Array = GameState.inventory
	var candidates: Array = []
	for i in range(inv.size()):
		var it = inv[i]
		if not (it is Dictionary):
			continue
		if String((it as Dictionary).get("kind", "")) != KIND_CATEGORY:
			continue
		var item_id := String((it as Dictionary).get("itemId", ""))
		if cd_of(item_id) > 0.0:
			continue
		var tpl = DataLoader.get_entry("potions", item_id)
		if not (tpl is Dictionary):
			continue
		var t: Dictionary = tpl
		if String(t.get("kind", "")).is_empty() or String(t.get("kind", "")) != kind:
			continue
		var amount := restore_of(t, cap, level)
		if amount <= 0:
			continue
		candidates.append({"index": i, "amount": amount})
	return choose_candidate(need, candidates)

## 纯函数：按 Q1 策略从候选 `[{index, amount}]` 中选一格。
## 优先「恢复量 ≥ 缺口」中**最小**者；若均不足缺口，取**恢复量最大**者。无候选返回 -1。
## 独立成纯函数便于无头回归（不依赖 GameState / 场景）。
static func choose_candidate(need: int, candidates: Array) -> int:
	if candidates.is_empty():
		return -1
	var best_small := -1
	var best_small_amount := 1 << 30
	var best_large := -1
	var best_large_amount := -1
	for c in candidates:
		if not (c is Dictionary):
			continue
		var amount := int((c as Dictionary).get("amount", 0))
		var idx := int((c as Dictionary).get("index", -1))
		if idx < 0 or amount <= 0:
			continue
		if amount >= need and amount < best_small_amount:
			best_small_amount = amount
			best_small = idx
		if amount > best_large_amount:
			best_large_amount = amount
			best_large = idx
	return best_small if best_small >= 0 else best_large

## 背包中该颜色药水的首个下标（**忽略冷却与满值**），无则 -1。
## 供快捷键在"挑不出可用瓶"时交给 `use()` 给出精确原因（已满 / 冷却中）。
static func first_index_of_kind(kind: String) -> int:
	var inv: Array = GameState.inventory
	for i in range(inv.size()):
		var it = inv[i]
		if not (it is Dictionary):
			continue
		if String((it as Dictionary).get("kind", "")) != KIND_CATEGORY:
			continue
		var tpl = DataLoader.get_entry("potions", String((it as Dictionary).get("itemId", "")))
		if tpl is Dictionary and String((tpl as Dictionary).get("kind", "")) == kind:
			return i
	return -1

# ---- 查询（供 UI / 回归）----

## 红 / 蓝药水的当前值与上限。
static func current_of(kind: String) -> int:
	return int(GameState.player.hp) if kind == KIND_RED else int(GameState.player.mp)

static func max_of(kind: String) -> int:
	return GameState.max_hp() if kind == KIND_RED else GameState.max_mp()

static func stat_label(kind: String) -> String:
	return Localization.tr_key(STAT_HP_KEY if kind == KIND_RED else STAT_MP_KEY)

## 某药水是否正处冷却（供 tooltip）。
static func is_cooling(item_id: String) -> bool:
	return cd_of(item_id) > 0.0

# ---- 内部 ----

static func _apply(kind: String, amount: int) -> void:
	if kind == KIND_RED:
		GameState.heal_player(amount)
	else:
		GameState.restore_mp(amount)

## 消耗一瓶：堆叠数 > 1 时减一，否则移除该格（两者都广播 inventory_changed）。
static func _consume_one(inv_index: int) -> void:
	var inv: Array = GameState.inventory
	var it = inv[inv_index]
	if it is Dictionary and int((it as Dictionary).get("count", 1)) > 1:
		(it as Dictionary)["count"] = int((it as Dictionary).get("count", 1)) - 1
		EventBus.inventory_changed.emit()
	else:
		GameState.remove_item_at(inv_index)

static func _fail(reason: String, silent: bool) -> Dictionary:
	if not silent:
		EventBus.toast_requested.emit(reason, "danger")
	return {"ok": false, "reason": reason, "itemId": "", "kind": "",
		"restored": 0, "message": reason}
