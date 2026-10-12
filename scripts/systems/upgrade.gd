class_name Upgrade
extends RefCounted
## 装备升星规则。当前星级是 successRate 的下标；失败保持星级但消耗金币。

static func config() -> Dictionary:
	var raw = DataLoader.get_table("upgrade")
	return raw if raw is Dictionary else {}

static func max_star() -> int:
	return int(config().get("maxStar", 0))

static func cost(star: int) -> int:
	var params: Dictionary = config().get("costParams", {})
	return int(round(float(params.get("UP_BASE", 0)) * pow(float(params.get("UP_R", 1)), star)))

static func success_rate(star: int) -> float:
	var rates: Array = config().get("successRate", [])
	return float(rates[star]) if star >= 0 and star < rates.size() else 0.0

static func final_rate(star: int, bonus_points: float = 0.0) -> float:
	return clampf(success_rate(star) + maxf(0.0, bonus_points), 0.0, 100.0)

## 先计算四格如意的总需求及从背包扣除的具体堆叠；失败时不修改背包。
static func rune_plan(inv: Array, rune_ids: Array) -> Dictionary:
	if rune_ids.size() > 4:
		return {"ok": false, "reason": "最多只能放入四枚如意"}
	var wanted := {}
	var bonus := 0.0
	for value in rune_ids:
		if not value is String:
			return {"ok": false, "reason": "如意选择无效"}
		var rune_id := String(value)
		if rune_id.is_empty():
			continue
		var template = DataLoader.get_entry("runes", rune_id)
		if not template is Dictionary:
			return {"ok": false, "reason": "如意种类无效"}
		wanted[rune_id] = int(wanted.get(rune_id, 0)) + 1
		bonus += float(template.get("successBonus", 0.0)) * 100.0
	var uses: Array[Dictionary] = []
	for rune_id in wanted:
		var remaining := int(wanted[rune_id])
		for index in range(inv.size()):
			var entry = inv[index]
			if not entry is Dictionary or String(entry.get("kind", "")) != "rune" or String(entry.get("itemId", "")) != rune_id:
				continue
			var take := mini(remaining, maxi(0, int(entry.get("count", 0))))
			if take > 0:
				uses.append({"index": index, "count": take})
				remaining -= take
			if remaining == 0:
				break
		if remaining > 0:
			return {"ok": false, "reason": "如意数量不足：%s" % String(rune_id), "bonus": bonus}
	return {"ok": true, "uses": uses, "bonus": bonus, "count": rune_ids.size() - rune_ids.count("")}

static func base_attrs(item: Dictionary) -> Dictionary:
	var original = item.get("baseAttrs", {})
	if not original is Dictionary:
		return {}
	var factor := 1.0 + float(item.get("star", 0)) * float(config().get("starMult", 0.0))
	var result := {}
	for key in original:
		result[key] = float(original[key]) * factor
	return result

static func roll_success(star: int, rng: RandomNumberGenerator = null, bonus_points: float = 0.0) -> bool:
	var rate := final_rate(star, bonus_points)
	if rate >= 100.0:
		return true
	if rate <= 0.0:
		return false
	var draw := rng.randf() if rng != null else randf()
	return draw * 100.0 < rate
