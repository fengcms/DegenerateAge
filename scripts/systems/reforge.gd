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

## 重铸费用 = `round(baseGold × (levelBase + levelFactor × requiredLevel))`。
## 产品 D-17 口径 400 × (60 + 0.5 × L)：L60 = 36,000 / L61 = 36,200 /
## L100 = 44,000 / L1000 = 224,000。
## 🔴 配置缺失返回 **-1**（调用方据此禁用按钮并报错），**不回退写死常量** ——
## 否则「改了 json 不生效」会变成静默错误，M10-9 调数值直接失效。
## 实现用单次 `round`：`levelFactor = 0.5` 与 `L × 0.5` 都是精确二进制小数，无累积误差；
## `(… ×2)/2` 那种写法一旦有人把基数改成奇数就会引入截断。
static func cost(required_level: int) -> int:
	var cfg := config()
	var base := int(cfg.get("baseGold", 0))
	if base <= 0:
		return -1
	var level_base := float(cfg.get("levelBase", 0.0))
	var factor := float(cfg.get("levelFactor", 0.0))
	return int(round(float(base) * (level_base + factor * float(maxi(0, required_level)))))

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
	var count := affix_count_of(quality_of(item))
	if count <= 0:
		return {"ok": false, "reason": Localization.tr_key("msg.reforge.p002")}
	var fixed: Variant = item.get("affixes", [])
	var percent: Variant = item.get("pctAttrs", [])
	var actual := 0
	if fixed is Array:
		actual += (fixed as Array).size()
	if percent is Array:
		actual += (percent as Array).size()
	if actual != count:
		return {"ok": false, "reason": Localization.tr_key("msg.reforge.p003")}
	return {"ok": true, "reason": ""}

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
