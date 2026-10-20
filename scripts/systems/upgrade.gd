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

## 如意如意：只选择四格 ID，不修改背包。先凑满 100%，再按高等级用量最少排序；
## 凑不满时取加成最高的至多四枚。和 rune_plan 共用模板 ID、背包数量口径。
static func auto_runes(base_rate: float, inv: Array) -> Dictionary:
	var types: Array[Dictionary] = []
	var templates: Variant = DataLoader.get_table("runes")
	if templates is Array:
		for raw in templates:
			if not raw is Dictionary:
				continue
			var rune_id := String(raw.get("id", ""))
			var bonus := float(raw.get("successBonus", 0.0)) * 100.0
			if rune_id.is_empty() or bonus <= 0.0:
				continue
			var count := 0
			for entry in inv:
				if entry is Dictionary and String(entry.get("kind", "")) == "rune" \
						and String(entry.get("itemId", "")) == rune_id:
					count += maxi(0, int(entry.get("count", 0)))
			if count > 0:
				types.append({"id": rune_id, "bonus": bonus, "count": mini(count, 4)})
	types.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.bonus) < float(b.bonus) if not is_equal_approx(float(a.bonus), float(b.bonus)) \
			else String(a.id) < String(b.id))
	var empty: Array[String] = ["", "", "", ""]
	if types.is_empty() or base_rate >= 100.0 - 0.0001:
		return {"ids": empty, "rate": clampf(base_rate, 0.0, 100.0),
			"reached": base_rate >= 100.0 - 0.0001, "available": not types.is_empty()}
	var needed := 100.0 - base_rate
	var combinations: Array[Dictionary] = [{"counts": [], "bonus": 0.0, "total": 0}]
	for rune in types:
		var next: Array[Dictionary] = []
		for candidate in combinations:
			for amount in range(mini(int(rune.count), 4 - int(candidate.total)) + 1):
				var counts: Array[int] = []
				counts.assign(candidate.counts)
				counts.append(amount)
				next.append({"counts": counts, "bonus": float(candidate.bonus) + amount * float(rune.bonus),
					"total": int(candidate.total) + amount})
		combinations = next
	var best: Dictionary = {}
	for candidate in combinations:
		if float(candidate.bonus) + 0.0001 < needed:
			continue
		if best.is_empty() or _prefer_low_runes(candidate, best, types.size(), needed):
			best = candidate
	var ids: Array[String] = []
	var bonus_points := 0.0
	if not best.is_empty():
		for i in range(types.size()):
			for _j in range(int(best.counts[i])):
				ids.append(String(types[i].id))
		bonus_points = float(best.bonus)
	else:
		for i in range(types.size() - 1, -1, -1):
			for _j in range(mini(int(types[i].count), 4 - ids.size())):
				ids.append(String(types[i].id))
				bonus_points += float(types[i].bonus)
	while ids.size() < 4:
		ids.append("")
	return {"ids": ids, "rate": clampf(base_rate + bonus_points, 0.0, 100.0),
		"reached": not best.is_empty(), "available": true}

## 候选都能到 100%：高等级枚数先比较，随后比较溢出量、总枚数。
static func _prefer_low_runes(a: Dictionary, b: Dictionary, type_count: int, needed: float) -> bool:
	for i in range(type_count - 1, -1, -1):
		if int(a.counts[i]) != int(b.counts[i]):
			return int(a.counts[i]) < int(b.counts[i])
	var excess_a := float(a.bonus) - needed
	var excess_b := float(b.bonus) - needed
	if absf(excess_a - excess_b) > 0.0001:
		return excess_a < excess_b
	return int(a.total) < int(b.total)

## 仅供按钮禁用状态；不枚举组合，也不改变当前四格预选。
static func has_usable_runes(inv: Array) -> bool:
	for entry in inv:
		if entry is Dictionary and String(entry.get("kind", "")) == "rune" \
				and int(entry.get("count", 0)) > 0 \
				and DataLoader.get_entry("runes", String(entry.get("itemId", ""))) is Dictionary:
			return true
	return false

## 先计算四格如意的总需求及从背包扣除的具体堆叠；失败时不修改背包。
static func rune_plan(inv: Array, rune_ids: Array) -> Dictionary:
	if rune_ids.size() > 4:
		return {"ok": false, "reason": Localization.tr_key("msg.upgrade.p001")}
	var wanted := {}
	var bonus := 0.0
	for value in rune_ids:
		if not value is String:
			return {"ok": false, "reason": Localization.tr_key("msg.upgrade.p002")}
		var rune_id := String(value)
		if rune_id.is_empty():
			continue
		var template = DataLoader.get_entry("runes", rune_id)
		if not template is Dictionary:
			return {"ok": false, "reason": Localization.tr_key("msg.upgrade.p003")}
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
			return {"ok": false, "reason": Localization.tr_key("msg.upgrade.p004") % String(rune_id), "bonus": bonus}
	return {"ok": true, "uses": uses, "bonus": bonus, "count": rune_ids.size() - rune_ids.count("")}

static func base_attrs(item: Dictionary) -> Dictionary:
	return EquipmentMath.base_attrs(item)

static func roll_success(star: int, rng: RandomNumberGenerator = null, bonus_points: float = 0.0) -> bool:
	var rate := final_rate(star, bonus_points)
	if rate >= 100.0:
		return true
	if rate <= 0.0:
		return false
	var draw := rng.randf() if rng != null else randf()
	return draw * 100.0 < rate
