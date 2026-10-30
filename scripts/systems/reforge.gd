class_name Reforge
extends RefCounted
## M10-8（产品 13 §6.2 / D-15 / D-17）：装备重铸的规则层 —— 费用、可重铸判定、回收价缩放。
##
## 与 `Balance` / `Endgame` 同规格：纯查表 + 纯计算，**不引用 `GameState`**。
## 全部参数来自 `data/endgame.json` 的 `reforge` / `resale` 两组，M10-9 可直接调数值，
## 不需要改代码。反过来 `Shop.sell_price` 引本类取回收缩放参数 —— 故本类**不得**引 `Shop`。

## 回收价缩放的兜底值（`endgame.json` 缺 `resale` 时使用）。
## 与重铸费用不同：这里**不能**失败 —— 售价算不出来会让玩家卖不出去东西，代价远大于口径偏移。
const DEFAULT_LEVEL_STEP := 0.02
const DEFAULT_FROM_LEVEL := 60

## 重铸参数：`{baseGold, levelBase, levelFactor}`；未配置 → 空字典。
static func config() -> Dictionary:
	var raw: Variant = DataLoader.get_table("endgame")
	if not raw is Dictionary:
		return {}
	var row: Variant = (raw as Dictionary).get("reforge", {})
	return row if row is Dictionary else {}

## 回收价缩放参数：`{levelStep, fromLevel}`；缺键走兜底常量。
static func resale_config() -> Dictionary:
	var raw: Variant = DataLoader.get_table("endgame")
	var row: Variant = {}
	if raw is Dictionary:
		row = (raw as Dictionary).get("resale", {})
	var cfg: Dictionary = row if row is Dictionary else {}
	return {
		"levelStep": float(cfg.get("levelStep", DEFAULT_LEVEL_STEP)),
		"fromLevel": int(cfg.get("fromLevel", DEFAULT_FROM_LEVEL)),
	}

## 重铸费用 = `round(baseGold × (levelBase + levelFactor × requiredLevel) × (1 + lockFactor × 锁定条数))`。
## 产品 D-17 口径 400 × (60 + 0.5 × L)：L60 = 36,000 / L61 = 36,200 /
## L100 = 44,000 / L1000 = 224,000（M10-9 调校后为 500 × (60 + 0.75 × L)）。
## 🔴 配置缺失返回 **-1**（调用方据此禁用按钮并报错），**不回退写死常量** ——
## 否则「改了 json 不生效」会变成静默错误，M10-9 调数值直接失效。
## 实现用单次 `round`：`levelFactor = 0.5` 与 `L × 0.5` 都是精确二进制小数，无累积误差；
## `(… ×2)/2` 那种写法一旦有人把基数改成奇数就会引入截断。
## 工程 81：`locked_count` 是**去重后**的锁定条数（见 `lock_count`），默认 0 ⇒ 乘 1.0，
## 既有五处调用（重铸 / 修理 / 两个测试）零改动即零回退；`lockFactor` 缺键按 0 处理
## （不涨价为兜底）—— 售价与修理费算不出来比口径偏移严重得多。
static func cost(required_level: int, locked_count: int = 0) -> int:
	var cfg := config()
	var base := int(cfg.get("baseGold", 0))
	if base <= 0:
		return -1
	var level_base := float(cfg.get("levelBase", 0.0))
	var factor := float(cfg.get("levelFactor", 0.0))
	var lock_factor := float(cfg.get("lockFactor", 0.0))
	var multiplier := 1.0 + lock_factor * float(maxi(0, locked_count))
	return int(round(float(base) * (level_base + factor * float(maxi(0, required_level))) * multiplier))

## 去重后的锁定条数（UI 与规则层同一口径）。
## 🔴 不能用传入数组的 `size()` 直接计价：UI 传进来的可能是脏数组（重复 / 空串），
## 「锁 1 条」与「锁 1 条写了两遍」必须算出同一个价。
static func lock_count(locked: Array) -> int:
	var seen: Array[String] = []
	for raw in locked:
		var stat := String(raw)
		if stat.is_empty() or seen.has(stat):
			continue
		seen.append(stat)
	return seen.size()

## 最多锁实例当前条数−1；普通紫装3条，已解锁五词条紫装4条。
## 🔴 至少留一条在变，重铸才成立 —— 全锁等于花钱买「什么都没变」，比普通品质重铸更恶劣。
static func max_lock_count(item: Dictionary) -> int:
	return maxi(0, ReforgeAffixes.current_count(item) - 1)

## 品质的词条条数（读 `equipmentRules.json` 的 `qualities[品质].affixCount`）；未登记 → 0。
static func affix_count_of(quality: String) -> int:
	var qualities: Variant = ItemFactory.rules().get("qualities", {})
	if not qualities is Dictionary or not (qualities as Dictionary).has(quality):
		return 0
	return int(((qualities as Dictionary)[quality] as Dictionary).get("affixCount", 0))

## 实例品质：优先实例自带，缺失回退模板 `defaultQuality`（与 `Shop.item_quality` 同口径，
## 但**不引 `Shop`** —— 反向依赖会成环）。
static func quality_of(item: Dictionary) -> String:
	var q := String(item.get("quality", ""))
	if not q.is_empty():
		return q
	var tpl: Variant = DataLoader.get_entry("equipments", String(item.get("itemId", "")))
	if tpl is Dictionary:
		return String((tpl as Dictionary).get("defaultQuality", "common"))
	return "common"

## 能否重铸：`{ok, reason}`，四种拒绝且判据全部可测。
## 🔴 `common` 的 `affixCount = 0` 必须在这里挡下 —— 否则玩家花 36,000 金、
## 装备一点没变，这是最恶劣的「花了钱没反应」（负向 N-4）。
## 🔴 词条条数与品质不符的脏实例一律拒绝，**不猜不修**：静默截断/补齐会掩盖数据问题。
static func can_reforge(item: Dictionary) -> Dictionary:
	if String(item.get("kind", "")) != "equip":
		return {"ok": false, "reason": Localization.tr_key("msg.reforge.p001")}
	if cost(Equipment.level_req(item)) <= 0:
		return {"ok": false, "reason": Localization.tr_key("msg.reforge.p004")}
	var count := ReforgeAffixes.current_count(item)
	if count <= 0:
		return {"ok": false, "reason": Localization.tr_key("msg.reforge.p002")}
	var fixed: Variant = item.get("affixes", [])
	var percent: Variant = item.get("pctAttrs", [])
	if not fixed is Array or not percent is Array or not ReforgeAffixes.valid_state(item):
		return {"ok": false, "reason": Localization.tr_key("msg.reforge.p003")}
	var actual := 0
	if fixed is Array:
		actual += (fixed as Array).size()
	if percent is Array:
		actual += (percent as Array).size()
	if actual != count:
		return {"ok": false, "reason": Localization.tr_key("msg.reforge.p003")}
	return {"ok": true, "reason": ""}

## 锁定集合是否合法：`{ok, reason}`；三条拒绝，一律在**扣费前**判定（工程 81）。
## ① 锁数超过上限 —— 含「全锁」与「该品质本就没有可锁的」两种；
## ② 锁定 stat 不在该实例的词条第 ③ stat 既不在 `fixedAffixes` 也不在 `percentAffixes`
## （无法归类 ⇒ 重掷时不知道该把它当固定值还是百分比保留）。
## 🔴 不猜不修：静默丢掉非法项会让玩家以为锁住了，实际照样被重掷。
static func validate_locks(item: Dictionary, locked: Array) -> Dictionary:
	var stats := _locked_stats(locked)
	if stats.is_empty():
		return {"ok": true, "reason": ""}
	var limit := max_lock_count(item)
	if limit <= 0:
		return {"ok": false, "reason": Localization.tr_key("msg.reforge.p008")}
	if stats.size() > limit:
		return {"ok": false, "reason": Localization.tr_key("msg.reforge.p006")}
	var present: Array[String] = []
	for key in ["affixes", "pctAttrs"]:
		var arr: Variant = item.get(String(key), [])
		if not arr is Array:
			continue
		for e in arr as Array:
			if e is Dictionary:
				present.append(String((e as Dictionary).get("stat", "")))
	var cfg := ItemFactory.rules()
	var fixed_cfg: Dictionary = cfg.get("fixedAffixes", {})
	var pct_cfg: Dictionary = cfg.get("percentAffixes", {})
	for stat in stats:
		if not present.has(stat):
			return {"ok": false, "reason": Localization.tr_key("msg.reforge.p007")}
		if not fixed_cfg.has(stat) and not pct_cfg.has(stat):
			return {"ok": false, "reason": Localization.tr_key("msg.reforge.p007")}
	return {"ok": true, "reason": ""}

## 锁定集合去重去空：规则层与 UI 共用同一份口径（UI 传来的可能是脏数组）。
static func _locked_stats(locked: Array) -> Array[String]:
	var stats: Array[String] = []
	for raw in locked:
		var stat := String(raw)
		if stat.is_empty() or stats.has(stat):
			continue
		stats.append(stat)
	return stats

## D-15 回收价轻缩放：× `(1 + levelStep × max(0, L − fromLevel))`，L ≤ fromLevel 恒 1.0。
## 🔴 只作用于**装备**（`Shop.sell_price` 里按 `kind` 分岔）：药水 / 杂项 / 如意没有
## 「装备等级」概念，套上去会把 20 金药水放大 20 倍（负向 N-7）。
## 🔴 `max(0, …)` 不能省：L1 装备会算出 0.02 倍，售价直接变 0（负向 N-8）。
static func resale_scale(level: int) -> float:
	var cfg := resale_config()
	var step := float(cfg.levelStep)
	var from := int(cfg.fromLevel)
	var over := maxi(0, level - from)
	if over <= 0 or step <= 0.0:
		return 1.0
	return 1.0 + step * float(over)

## ---- 工程 86：重铸精炼（紫装当材料，抬高本次未锁定词条的数值下限）----

## 单次最多计入 4 件有效材料；每件抬 15%，封顶 60% 分位。
## 三个数一起定义：改上限就会连带改满投时的下限，不能拆开调。
const REFINE_MAX_EFFECTIVE := 4.0
const REFINE_STEP := 0.15
const REFINE_CAP := 0.60
## 只有传说（界面紫）能当材料。
const REFINE_QUALITY := "legendary"

## 十级档序号：同档 → 差 0，高一档 → 差 1。`suit_start` 是唯一套档口径（1—10 → 0，51 → 5，61 → 6）。
static func tier_index(level: int) -> int:
	var start := ItemFactory.suit_start(level)
	if start <= 0:
		return -1
	return (start - 1) / 10

## 一件材料折算多少「有效件数」：同档 1 / 高 1 档及以上 2 / 低 1 档 0.5 / 低 2 档及以下 0.25；
## 12★ 额外 +1（强化投入的沉没成本，避免喂满的旧件只能穿/卖/仓）。
## 🔴 只影响下限，不改变材料件数：投入 4 件低 2 档也只算 1 件有效，防止低档料按件数平替同档料。
static func refine_value(material: Dictionary, target: Dictionary) -> float:
	var mt := tier_index(Equipment.level_req(material))
	var tt := tier_index(Equipment.level_req(target))
	if mt < 0 or tt < 0:
		return 0.0
	var value := 1.0
	if mt > tt:
		value = 2.0
	elif mt == tt - 1:
		value = 0.5
	elif mt < tt - 1:
		value = 0.25
	if int(material.get("star", 0)) >= Upgrade.max_star():
		value += 1.0
	return value

## 一件材料能否投：`{ok, reason}`。判据与铁匠合成同口径 —— 收藏件、非紫装、脏实例一律不可投。
## 🔴 不在背包（穿戴中 / 仓库）由调用方按 `find_owned_item` 的落点挡下，这里只管物品本身。
static func can_refine(material: Dictionary, target: Dictionary) -> Dictionary:
	if String(material.get("kind", "")) != "equip":
		return {"ok": false, "reason": Localization.tr_key("msg.reforge.p010")}
	if quality_of(material) != REFINE_QUALITY:
		return {"ok": false, "reason": Localization.tr_key("msg.reforge.p010")}
	if bool(material.get("favorite", false)):
		return {"ok": false, "reason": Localization.tr_key("msg.reforge.p011")}
	if String(material.get("instanceId", "")).is_empty() \
			or String(material.get("instanceId", "")) == String(target.get("instanceId", "")):
		return {"ok": false, "reason": Localization.tr_key("msg.reforge.p012")}
	if tier_index(Equipment.level_req(material)) < 0:
		return {"ok": false, "reason": Localization.tr_key("msg.reforge.p012")}
	return {"ok": true, "reason": ""}

## 材料列表的**有效件数**（封顶 4）。非法件不计入、也不报错 ——
## 合法性由 `can_refine` 在扣费前逐件把关，这里只负责计价。
static func refine_count(materials: Array, target: Dictionary) -> float:
	var total := 0.0
	for raw in materials:
		if raw is Dictionary:
			total += refine_value(raw as Dictionary, target)
			if total >= REFINE_MAX_EFFECTIVE:
				return REFINE_MAX_EFFECTIVE
	return total

## 未锁定词条的数值下限比例：`min(0.60, 0.15 × 有效件数)`；0 件即 0（完整区间随机）。
## 🔴 锁定的词条**不参与**抬升 —— 否则「锁 3 条 + 投满 4 件」等于最后一条必高，重铸退化成按按钮。
static func floor_ratio(effective: float) -> float:
	return minf(REFINE_CAP, REFINE_STEP * maxf(0.0, effective))

## 工程 87：随机放入的材料快照（只读背包，不修改任何物品）。
## 自动池比手动投放更保守，三条额外红线：
## 1. **只取 0 星** —— 升星件是金币成果，不能被「省事」按钮一键烧掉；
## 2. **只取目标同档或更低档** —— 更高档紫装留给穿戴与四紫升档，手动拖入才是明确决策；
## 3. **同档优先、低档兜底** —— 低 2 档折算仅 0.25，若从最低档开始填，4 件只值 15%，按钮会显得坑玩家。
## 🔴 顺序是「同档 → 低 1 档 → 低 2 档及以下」，档内随机无放回；返回空数组表示没有可自动投入的材料。
static func random_refine_materials(inventory: Array, target: Dictionary,
		slots: int = 4, rng: RandomNumberGenerator = null) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if slots <= 0 or target.is_empty():
		return result
	var target_tier := tier_index(Equipment.level_req(target))
	if target_tier < 0:
		return result
	var groups := {}
	for entry in inventory:
		if not entry is Dictionary:
			continue
		var item: Dictionary = entry
		if int(item.get("star", 0)) != 0:
			continue
		if not bool(can_refine(item, target).get("ok", false)):
			continue
		var tier := tier_index(Equipment.level_req(item))
		if tier < 0 or tier > target_tier:
			continue
		if not groups.has(tier):
			groups[tier] = [] as Array
		(groups[tier] as Array).append(item.duplicate(true))
	for tier in range(target_tier, -1, -1):
		if result.size() >= slots:
			break
		var pool: Array = groups.get(tier, [])
		while result.size() < slots and not pool.is_empty():
			var index := rng.randi_range(0, pool.size() - 1) if rng != null else randi_range(0, pool.size() - 1)
			result.append((pool[index] as Dictionary).duplicate(true))
			pool.remove_at(index)
	return result
