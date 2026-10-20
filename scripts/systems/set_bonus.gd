class_name SetBonus
extends RefCounted
## 套装加成（工程 66 / 产品 05 §5.14）：品质档 + 星级档，**独立判定后相加**。
##
## 判定口径：14 槽（`Equipment.SLOT_DEFS`）全部穿满，取其中**最低品质**与**最低星级**，
## 各自查表后相加。全紫全 12 星 = 0.20 + 0.20 = 0.40（加法，不是乘法）。
##
## 🔴 白装 `common` 恒 0：它是节奏基线，且 `PaceTest` 全程穿 common ——
##    给它任何加成都会让三条护栏（≤1.30 / 锯齿 ±2% / 可挨打 ≥5.5）同时变红。
##    `SetBonusTest` 有守护断言，别绕过。
##
## 本层只读槽位字典，不依赖 GameState / UI；数值全部来自 `equipmentRules.setBonus`。

## 缩放方向（语义，不放进配置）：这些键**越大越好**，乘 (1 + pct)。
const SCALED_FALLBACK := ["atk", "def", "hp", "mp", "criticalChance",
	"criticalMultiplier", "dodge", "block", "cdr", "movementSpeed"]
## 这些键**越小越好**，除 (1 + pct) 而不是乘 —— 乘 1.4 会让攻速掉 29%（负收益）。
const INVERSE_FALLBACK := ["attackInterval"]

## 配置段（`equipmentRules.json` 的 `setBonus`）。
static func config() -> Dictionary:
	var raw: Variant = DataLoader.get_table("equipmentRules")
	if not raw is Dictionary:
		return {}
	var section: Variant = (raw as Dictionary).get("setBonus", {})
	return section if section is Dictionary else {}

## 品质 → 加成。缺配置时退回内置表（保证即使配置损坏也不会静默 0）。
static func quality_table() -> Dictionary:
	var raw: Variant = config().get("quality", {})
	return raw if raw is Dictionary else {
		"common": 0.0, "uncommon": 0.02, "rare": 0.05, "epic": 0.10, "legendary": 0.20,
	}

## 星级档 → 加成（键是字符串，与 JSON 一致）。
static func star_table() -> Dictionary:
	var raw: Variant = config().get("star", {})
	return raw if raw is Dictionary else {"6": 0.03, "8": 0.05, "10": 0.10, "12": 0.20}

## 成套所需的槽数（默认 14；若产品改成「允许缺 2 件」只需改配置）。
static func required_slots() -> int:
	return int(config().get("requiredSlots", Equipment.SLOT_DEFS.size()))

## 参与缩放的键（正向）。
static func scaled_keys() -> Array:
	var raw: Variant = config().get("scaledKeys", null)
	return raw if raw is Array else SCALED_FALLBACK

## 反向缩放的键（越小越好）。
static func inverse_keys() -> Array:
	var raw: Variant = config().get("inverseKeys", null)
	return raw if raw is Array else INVERSE_FALLBACK

## 星级档位（升序整数）。配置键是字符串，这里转一次。
static func star_steps() -> Array[int]:
	var out: Array[int] = []
	for key in star_table().keys():
		out.append(int(key))
	out.sort()
	return out

## 品质阶梯顺序（`ItemUtil.QUALITIES` 是唯一来源，这里只过滤掉表里没有的）。
static func quality_steps() -> Array[String]:
	var table := quality_table()
	var out: Array[String] = []
	for q in ItemUtil.QUALITIES:
		if table.has(q):
			out.append(q)
	return out

## 主入口。返回：
## `{ pct, full, worn, missing, required,
##    quality, quality_pct, next_quality, next_quality_need, quality_maxed,
##    star, star_pct, next_star, next_star_need, star_maxed }`
##
## 🔴 遍历 `Equipment.SLOT_DEFS` 而不是 `slots.keys()`：脏档可能多出非标准键，
##    遍历 keys 会漏掉「某个标准槽空着」的判定，直接让空槽白拿加成。
static func evaluate(slots: Dictionary) -> Dictionary:
	var required := required_slots()
	var total := Equipment.SLOT_DEFS.size()
	var worn := 0
	var min_rank := ItemUtil.QUALITIES.size()   # 初始高于任何合法品质
	var min_star := 0
	var star_seen := false
	for definition in Equipment.SLOT_DEFS:
		var item: Variant = slots.get(String(definition.id))
		if not (item is Dictionary):
			continue
		worn += 1
		# 非法品质（脏档）按 common 处理，不让它把加成算成负值或崩。
		min_rank = mini(min_rank, maxi(0, equipment_rank(item)))
		var star := maxi(0, int((item as Dictionary).get("star", 0)))
		min_star = star if not star_seen else mini(min_star, star)
		star_seen = true
	var full := worn >= required and required > 0

	var quality_key := "common"
	var quality_pct := 0.0
	if full:
		var steps := quality_steps()
		if not steps.is_empty() and min_rank < steps.size():
			quality_key = steps[mini(min_rank, steps.size() - 1)]
		quality_pct = float(quality_table().get(quality_key, 0.0))

	var star_step := 0
	var star_pct := 0.0
	if full:
		for step in star_steps():
			if min_star >= step:
				star_step = maxi(star_step, step)
		star_pct = float(star_table().get(str(star_step), 0.0)) if star_step > 0 else 0.0

	var next_quality := _next_quality(quality_key)
	var next_star := _next_star(star_step)
	return {
		"pct": quality_pct + star_pct,
		"full": full,
		"worn": worn,
		"missing": maxi(0, total - worn),
		"required": required,
		"quality": quality_key,
		"quality_pct": quality_pct,
		"next_quality": next_quality,
		"next_quality_need": _count_below_quality(slots, next_quality),
		"quality_maxed": next_quality.is_empty(),
		"star": star_step,
		"star_pct": star_pct,
		"next_star": next_star,
		"next_star_need": _count_below_star(slots, next_star),
		"star_maxed": next_star == 0,
	}

## 装备实例的品质序（缺少 / 非法一律 0，即 common）。
static func equipment_rank(item: Dictionary) -> int:
	var q := String(item.get("quality", "common"))
	var rank := ItemUtil.QUALITIES.find(q)
	return rank if rank >= 0 else 0

## 当前品质的上一档；已到顶返回空串。
static func _next_quality(current: String) -> String:
	var steps := quality_steps()
	var index := steps.find(current)
	if index < 0 or index + 1 >= steps.size():
		return ""
	return steps[index + 1]

## 当前星级档的上一档；已到顶返回 0。
static func _next_star(current: int) -> int:
	var steps := star_steps()
	for step in steps:
		if step > current:
			return step
	return 0

## 品质序低于 target 的件数（含空槽）：即「还要再凑几件才够这一档」。
static func _count_below_quality(slots: Dictionary, target: String) -> int:
	if target.is_empty():
		return 0
	var target_rank := ItemUtil.QUALITIES.find(target)
	if target_rank < 0:
		return 0
	var need := 0
	for definition in Equipment.SLOT_DEFS:
		var item: Variant = slots.get(String(definition.id))
		if not (item is Dictionary) or equipment_rank(item) < target_rank:
			need += 1
	return need

## 星级低于 target 的件数（含空槽）。
static func _count_below_star(slots: Dictionary, target: int) -> int:
	if target <= 0:
		return 0
	var need := 0
	for definition in Equipment.SLOT_DEFS:
		var item: Variant = slots.get(String(definition.id))
		if not (item is Dictionary) or int((item as Dictionary).get("star", 0)) < target:
			need += 1
	return need

## 反向缩放：越小越好的属性（攻击间隔）用除法 —— ×0.6 会是「提升 66.7%」而非 40%。
static func inverse_scale(value: float, pct: float) -> float:
	var factor := 1.0 + maxf(-0.99, pct)
	return value / factor
