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
## 低耐久兜底线（比例）。`warnThresholds` 缺失或全 0 时，自动修复阈值退回这个数。
## ⚠ `GameState._warn_durability` 里的 0.2 是**既有写死值**，本次不动它；
##    两处当前同数（都等于 `warnThresholds` 的 0.2），调阈值时必须一起看。
const DEFAULT_LOW_WARN := 0.2
## 存档字段的宽松上界。**不写死 800** —— 上限在 JSON 里可调，写死会让
## 调高上限后旧档逐件判毁档（D-21 静默毁档教训）。
const SAVE_FIELD_CAP := 10000

## 耐久配置：`{maxDurability, wearPerKill, warnThresholds, repairCost}`；缺失 → 空字典。
static func config() -> Dictionary:
	var raw: Variant = DataLoader.get_table("durability")
	return raw if raw is Dictionary else {}

## 工程 95：挂机自动维护的两块配置。数值同样只从 JSON 读，代码里只留兜底值。
## 🔑 自动修复的触发阈值**不在这里** —— 它复用 `warnThresholds` 的 0.2（见 `auto_repair_threshold`），
##    否则「预警线」和「自动修线」会各自漂移成两个数字。
static func auto_repair_config() -> Dictionary:
	var raw: Variant = config().get("autoRepair", {})
	return raw if raw is Dictionary else {}

static func auto_forge_config() -> Dictionary:
	var raw: Variant = config().get("autoForge", {})
	return raw if raw is Dictionary else {}

## 自动修复倍率（相对铁匠 1.0×）。下限 1.0：便利费**不能比回城更便宜**，
## 否则挂机自动修就成了「免费优化」，铁匠的修理出口会直接作废。
static func auto_repair_fee_rate() -> float:
	return maxf(1.0, float(auto_repair_config().get("feeRate", 1.5)))

## 自动合成的便利费占「同档单件修满价」的比例（工程 95 Q2 拍板 0.5）。
static func auto_forge_fee_share() -> float:
	return maxf(0.0, float(auto_forge_config().get("feeShare", 0.5)))

## 自动合成的最小间隔（s）：同时是「一次只合一组」的天然限速。
static func auto_forge_interval() -> float:
	return maxf(0.5, float(auto_forge_config().get("interval", 2.0)))

## 自动修复触发阈值（比例）。与预警线取同一个数：`warnThresholds` 里**最高的正数档**。
## 配置缺失或全为 0 时退回 0.2（`DEFAULT_LOW_WARN`，与 `_warn_durability` 同源口径）。
static func auto_repair_threshold() -> float:
	var best := 0.0
	for value in warn_thresholds():
		if value > 0.0:
			best = maxf(best, value)
	return best if best > 0.0 else DEFAULT_LOW_WARN

## 自动维护提示节流（s）。修复与合成**各一份**，避免一个功能的失败提示盖住另一个。
static func auto_repair_warn_cooldown() -> float:
	return maxf(1.0, float(auto_repair_config().get("warnCooldown", 60.0)))

static func auto_forge_warn_cooldown() -> float:
	return maxf(1.0, float(auto_forge_config().get("warnCooldown", 60.0)))

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
