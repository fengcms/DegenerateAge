class_name Durability
extends RefCounted
## 装备耐久度的规则层（工程 77）—— 损耗、失效判定、修理费。
##
## 与 `Reforge` / `Balance` 同规格：纯查表 + 纯计算，**不引用 `GameState`**。
## 全部旋钮来自 `data/durability.json`，数值调优只改 JSON 不改代码。
##
## 🔴 失效语义只有**一个**卡口：`EquipmentMath.attrs_for_use()`（工程 88）——
##    耐久归零 ⇒ **只砍词条**（`affixes` / `pctAttrs`），基底（品质 × 星级）照常生效；
##    `Equipment.bonus` 与 `Equipment.score` 共用这一个入口，本类**不参与**属性计算。
##    **套装加成照常** —— `SetBonus.evaluate` 数的是槽位而非属性，破损件仍穿戴 ⇒ 仍计数。
##    ⚠ 历史：工程 77 原为「属性全清 + 评分归零」，结果挂机时被小怪两击打死（工程 88 改）。
## 🔴 存档兼容：`durability` 是**可选字段**（`favorite` 先例），缺失 = 满耐久。
##    旧档零迁移、不 bump schema；`_valid_item` 只在字段存在时校验。

## 配置缺失时的兜底上限；`_valid_item` 的宽松上界另见 `SAVE_FIELD_CAP`。
const DEFAULT_MAX := 800
## 存档字段的宽松上界。**不写死 800** —— 上限在 JSON 里可调，写死会让
## 调高上限后旧档逐件判毁档（D-21 静默毁档教训）。
const SAVE_FIELD_CAP := 10000

## 耐久配置：`{maxDurability, wearPerKill, warnThresholds, repairCost}`；缺失 → 空字典。
static func config() -> Dictionary:
	var raw: Variant = DataLoader.get_table("durability")
	return raw if raw is Dictionary else {}

## 耐久上限；配置缺失走兜底常量（修理费不同：那条链路缺配置要显式报错）。
static func max_durability() -> int:
	return maxi(1, int(config().get("maxDurability", DEFAULT_MAX)))

## 每次击杀的磨损点数：按怪物档次取值（`Monster._kind()` 产出 normal / elite / boss）。
## 未登记档次按普通怪计。分档是必须而非细节 —— 统一 1 点/杀会让循环图
## （30 Boss/h）800 点撑 26 小时，修理在后期直接消失，而后期恰是金币最需要出口（D-22）。
static func wear_per_kill(monster_kind: String) -> int:
	var table: Variant = config().get("wearPerKill", {})
	if not table is Dictionary:
		return 1
	return maxi(0, int((table as Dictionary).get(monster_kind, (table as Dictionary).get("normal", 1))))

## 预警阈值（0—1 的比例），从低到高触发一次 toast：跌破 20% 与归零各一次。
static func warn_thresholds() -> Array[float]:
	var out: Array[float] = []
	var raw: Variant = config().get("warnThresholds", [])
	if raw is Array:
		for value in (raw as Array):
			out.append(clampf(float(value), 0.0, 1.0))
	return out

## 实例当前耐久。**缺失字段 = 满耐久**（旧档语义），越界读入夹到 [0, max]。
static func current(item: Dictionary) -> int:
	if String(item.get("kind", "")) != "equip":
		return 0
	if not item.has("durability"):
		return max_durability()
	var value := int(item.get("durability", 0))
	return clampi(value, 0, max_durability())

## 破损判定：耐久归零 ⇒ **词条**失效（基底与套装加成保留，口径见 `EquipmentMath.attrs_for_use`）。
static func is_broken(item: Dictionary) -> bool:
	if String(item.get("kind", "")) != "equip":
		return false
	return current(item) <= 0

## 单件修满价（按**装备自身等级**计，与玩家等级无关）：
## L1—60 `earlyPerLevel × L`（升级期刻意压低）；L61+ `reforgeShare × 重铸费(L)`。
## 🔴 锚定原则：61 级后「全身修满（14 件）≈ 一次重铸」恒成立（两者共用同一曲线）。
## 🔴 重铸配置缺失返回 -1（调用方据此禁用按钮），**不回退写死常量** —— 否则
## 「改了 json 不生效」会变成静默错误（与 `Reforge.cost` 同口径）。
static func repair_full_price(item: Dictionary) -> int:
	if String(item.get("kind", "")) != "equip":
		return -1
	var level := int(item.get("level", item.get("requiredLevel", 1)))
	var cfg: Variant = config().get("repairCost", {})
	if not cfg is Dictionary:
		return -1
	var early_max := int((cfg as Dictionary).get("earlyMaxLevel", 60))
	if level <= early_max:
		return maxi(1, int((cfg as Dictionary).get("earlyPerLevel", 5)) * maxi(1, level))
	var share := float((cfg as Dictionary).get("reforgeShare", 0.0))
	if share <= 0.0:
		return -1
	var reforge := Reforge.cost(level)
	if reforge <= 0:
		return -1
	return maxi(1, int(round(float(reforge) * share)))

## 该件实际修理费 = `ceil(修满价 × 缺失耐久 / 上限)`，只按缺失比例收、无缺失不收。
## 单件不足 1 金按 1 金（缺失 > 0 时不可能免费）。
static func repair_cost(item: Dictionary) -> int:
	var missing := max_durability() - current(item)
	if missing <= 0:
		return 0
	var full := repair_full_price(item)
	if full < 0:
		return -1
	return maxi(1, int(ceil(float(full) * float(missing) / float(max_durability()))))

## 扣减耐久并返回实际扣点（到 0 截止）。非装备 / 已破损返回 0。
static func wear(item: Dictionary, monster_kind: String) -> int:
	if String(item.get("kind", "")) != "equip":
		return 0
	var points := wear_per_kill(monster_kind)
	if points <= 0:
		return 0
	var before := current(item)
	if before <= 0:
		return 0
	var after := maxi(0, before - points)
	item["durability"] = after
	return before - after

## 修复到满耐久并返回实际修复点数；缺失为 0 时返回 0 且不写字段。
static func repair(item: Dictionary) -> int:
	if String(item.get("kind", "")) != "equip":
		return 0
	var before := current(item)
	var maximum := max_durability()
	if before >= maximum:
		return 0
	item["durability"] = maximum
	return maximum - before
