class_name ReforgeAffixes
extends RefCounted
## 实例当前条数与本次重铸目标分开，普通生成/保星取优不会提前解锁。
const FIELD := "reforgeAffixTier"

static func config() -> Dictionary:
	var rules: Variant = DataLoader.get_table("equipmentRules")
	return rules.get("fullStarReforge", {}) if rules is Dictionary else {}

static func unlocked(item: Dictionary) -> bool:
	return item.get(FIELD, 0) == 1

static func eligible(item: Dictionary) -> bool:
	var cfg := config()
	return item.get("quality", "") == cfg.get("quality", "legendary") and int(item.get("star", -1)) == int(cfg.get("requiredStar", 12))

static func current_count(item: Dictionary) -> int:
	var rules: Variant = DataLoader.get_table("equipmentRules")
	var qualities: Dictionary = rules.get("qualities", {}) if rules is Dictionary else {}
	var base := int(qualities.get(String(item.get("quality", "")), {}).get("affixCount", 0))
	return base + (int(config().get("extraCount", 1)) if unlocked(item) else 0)

static func target_count(item: Dictionary) -> int:
	if eligible(item) and not unlocked(item):
		return current_count(item) + int(config().get("extraCount", 1))
	return current_count(item)

## 只检查新增字段与扩展形态；无字段旧实例交回原存档规则，不改变历史宽容度。
static func valid_state(item: Dictionary) -> bool:
	var tier: Variant = item.get(FIELD, 0)
	if not (tier is int or tier is float) or float(tier) not in [0.0, 1.0]:
		return false
	if not item.get("affixes", []) is Array or not item.get("pctAttrs", []) is Array:
		return false
	if tier == 0:
		return (item.get("affixes", []) as Array).size() + (item.get("pctAttrs", []) as Array).size() <= 4
	if not eligible(item):
		return false
	if item.get("affixes", []).size() != 4 or item.get("pctAttrs", []).size() != 1:
		return false
	var rules: Dictionary = DataLoader.get_table("equipmentRules")
	var seen := {}
	for key in ["affixes", "pctAttrs"]:
		var allowed: Dictionary = rules.get("fixedAffixes" if key == "affixes" else "percentAffixes", {})
		for entry in item.get(key, []):
			if not entry is Dictionary or not allowed.has(entry.get("stat")) or seen.has(entry.get("stat")):
				return false
			seen[entry.stat] = true
	return true

static func validate_config(rules: Dictionary, equips: Array) -> Array[String]:
	var errors: Array[String] = []
	var cfg: Variant = rules.get("fullStarReforge")
	if not cfg is Dictionary or cfg.get("quality") != "legendary" or cfg.get("requiredStar") != 12 or cfg.get("extraCount") != 1 or cfg.get("percentCount") != 1:
		return ["[equipmentRules] fullStarReforge 必须为紫装12星额外1条、百分比1条"]
	if rules.get("qualities", {}).get("legendary", {}).get("affixCount") != 4:
		errors.append("[equipmentRules] 满星重铸要求紫装基础四词条")
	var fixed: Dictionary = rules.get("fixedAffixes", {})
	var pct: Dictionary = rules.get("percentAffixes", {})
	for tpl in equips:
		if not tpl is Dictionary:
			continue
		var fixed_ids := {}
		var pct_ids := {}
		for stat in tpl.get("affixPool", []):
			if fixed.has(stat):
				fixed_ids[stat] = true
			if pct.has(stat):
				pct_ids[stat] = true
		if fixed_ids.size() < 4 or pct_ids.is_empty():
			errors.append("[equipmentRules] 五词条候选不足：" + String(tpl.get("id", "")))
	return errors
