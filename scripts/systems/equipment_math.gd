class_name EquipmentMath
extends RefCounted
## 新装备实例的唯一数值结算入口。实例只存未升星基底和原始词条。

static func star_factor(item: Dictionary) -> float:
	return 1.0 + float(item.get("star", 0)) * float(item.get("starMultiplierSnapshot", 0.0))

static func base_attrs(item: Dictionary) -> Dictionary:
	var result := {}
	var raw: Variant = item.get("rawBaseAttrs", {})
	if not raw is Dictionary:
		return result
	var factor := float(item.get("qualityMultiplierSnapshot", 1.0)) * star_factor(item)
	for stat in raw:
		result[String(stat)] = float(raw[stat]) * factor
	return result

static func effective_attrs(item: Dictionary) -> Dictionary:
	var result := base_attrs(item)
	var factor := star_factor(item)
	for key in ["affixes", "pctAttrs"]:
		var entries: Variant = item.get(key, [])
		if not entries is Array:
			continue
		for entry in entries:
			if not entry is Dictionary:
				continue
			var stat := String(entry.get("stat", ""))
			result[stat] = float(result.get(stat, 0.0)) + float(entry.get("value", 0.0)) * factor
	return result
