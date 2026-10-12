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

static func base_attrs(item: Dictionary) -> Dictionary:
	var original = item.get("baseAttrs", {})
	if not original is Dictionary:
		return {}
	var factor := 1.0 + float(item.get("star", 0)) * float(config().get("starMult", 0.0))
	var result := {}
	for key in original:
		result[key] = float(original[key]) * factor
	return result

static func roll_success(star: int, rng: RandomNumberGenerator = null) -> bool:
	var rate := success_rate(star)
	if rate >= 100.0:
		return true
	if rate <= 0.0:
		return false
	var draw := rng.randf() if rng != null else randf()
	return draw * 100.0 < rate
