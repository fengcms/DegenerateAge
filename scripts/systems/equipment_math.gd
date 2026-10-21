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

## 本件**当前实际生效**的属性 —— 唯一口径入口（工程 88）。
##
## 🔴 耐久归零只砍**词条**（`affixes` / `pctAttrs`），**基底照常生效**：
##    基底 = `rawBaseAttrs × 品质倍数 × 星级`。这层必须留着 —— 玩家破损后该是
##    「打得慢、掉血快」，而不是「防御跌到 4%，被小怪两击打死」。
##    实现上直接复用 `base_attrs()`：**没有新公式，也没有第二处乘数**。
## 🔴 必须由 `Equipment.bonus()` 与 `Equipment.score()` **共用**。两边各写一遍，
##    迟早出现「面板说 65%、结算按 0%」这种只在挂机时被发现的静默分裂。
##    ⚠ 本函数依赖 `Durability` → `DataLoader`（与 `Equipment` 同，`--check-only`
##    单脚本检查的 autoload 假阳性属已知项）。
static func attrs_for_use(item: Dictionary) -> Dictionary:
	return base_attrs(item) if Durability.is_broken(item) else effective_attrs(item)

## 展示层分项（B-P3-5）：基底各属性的「原始 / 品质增量 / 升星增量」。
## 三项之和 = `base_attrs` 的合成结果，合成公式只在本文件实现一次，展示层只取数。
## 返回 { stat: { "raw": float, "quality": float, "star": float } }，键序同 rawBaseAttrs。
static func base_breakdown(item: Dictionary) -> Dictionary:
	var result := {}
	var raw: Variant = item.get("rawBaseAttrs", {})
	if not raw is Dictionary:
		return result
	var quality := float(item.get("qualityMultiplierSnapshot", 1.0))
	var star := star_factor(item)
	for stat in raw:
		var value := float(raw[stat])
		result[String(stat)] = {
			"raw": value,
			"quality": value * (quality - 1.0),
			"star": value * quality * (star - 1.0),
		}
	return result
