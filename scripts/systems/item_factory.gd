class_name ItemFactory
extends RefCounted
## 装备实例唯一生成入口；任务、商店与怪物掉落共用档位/品质/词条规则。

## 返回装备规则；生成、掉落和售价共同读取这一份配置。
static func rules() -> Dictionary:
	var raw: Variant = DataLoader.get_table("equipmentRules")
	return raw if raw is Dictionary else {}

## 将来源等级映射到所属套的起点；当前 1—10 为第一套、11—20 为第二套。
static func tier_for_level(source_level: int) -> int:
	var chosen := 1
	for value in rules().get("tiers", []):
		var tier := int(value)
		if tier <= source_level and tier > chosen:
			chosen = tier
	return chosen

## 取得型号所属套的起点；实际穿戴等级由模板单独定义。
static func tier_start_for_template(item_id: String) -> int:
	var tpl: Variant = DataLoader.get_entry("equipments", item_id)
	if not tpl is Dictionary:
		return 0
	var bases: Variant = tpl.get("tierBases", {})
	return int(bases.keys()[0]) if bases is Dictionary and bases.size() == 1 else 0

## level 参数兼容来源等级调用；未指定时使用该型号所属套。
static func make_equip(item_id: String, level: int = 0, instance_prefix: String = "inst") -> Dictionary:
	var tpl: Variant = DataLoader.get_entry("equipments", item_id)
	if not tpl is Dictionary:
		return {}
	var bases: Variant = tpl.get("tierBases", {})
	if not bases is Dictionary or bases.size() != 1:
		return {}
	var tier_start := tier_for_level(level) if level > 0 else int(bases.keys()[0])
	return make_equip_roll(item_id, tier_start, String(tpl.get("defaultQuality", "common")), null, instance_prefix)

## 按型号所属套生成实例；传入其他套起点时显式失败。
static func make_equip_roll(item_id: String, tier_start: int, quality: String,
		rng: RandomNumberGenerator = null, instance_prefix: String = "inst") -> Dictionary:
	var tpl: Variant = DataLoader.get_entry("equipments", item_id)
	var cfg := rules()
	var qualities: Variant = cfg.get("qualities", {})
	if not tpl is Dictionary or not qualities is Dictionary or not qualities.has(quality):
		return {}
	var raw_bases: Variant = tpl.get("tierBases", {})
	if not raw_bases is Dictionary or not raw_bases.get(str(tier_start)) is Dictionary:
		push_error("[ItemFactory] %s 缺少第 %d 套装备基底" % [item_id, tier_start])
		return {}
	var required_level := int(tpl.get("requiredLevel", 0))
	if required_level < tier_start or required_level >= tier_start + 10:
		push_error("[ItemFactory] %s 穿戴等级与所属套不符" % item_id)
		return {}
	var scale_values: Variant = cfg.get("affixTierScale", {})
	if not scale_values is Dictionary or not scale_values.has(str(tier_start)):
		push_error("[ItemFactory] 缺少第 %d 套词条倍率" % tier_start)
		return {}
	var q: Dictionary = qualities[quality]
	var r := rng if rng != null else _default_rng()
	var affix_count := int(q.get("affixCount", 0))
	var pool: Array = tpl.get("affixPool", [])
	var fixed_cfg: Dictionary = cfg.get("fixedAffixes", {})
	var pct_cfg: Dictionary = cfg.get("percentAffixes", {})
	var fixed: Array = []
	var percent: Array = []
	var available: Array = []
	for stat in pool:
		if fixed_cfg.has(String(stat)):
			available.append(String(stat))
	if affix_count > 0 and float(q.get("percentChance", 0.0)) > 0.0 and r.randf() < float(q.percentChance):
		var pct_available: Array = []
		for stat in pool:
			if pct_cfg.has(String(stat)):
				pct_available.append(String(stat))
		if not pct_available.is_empty():
			var stat: String = pct_available[r.randi_range(0, pct_available.size() - 1)]
			var bounds: Dictionary = pct_cfg[stat]
			percent.append({"stat": stat, "value": snappedf(r.randf_range(float(bounds.min), float(bounds.max)), 0.001)})
	while fixed.size() + percent.size() < affix_count and not available.is_empty():
		var index := r.randi_range(0, available.size() - 1)
		var stat: String = available[index]
		available.remove_at(index)
		var bounds: Dictionary = fixed_cfg[stat]
		var scale := float(scale_values[str(tier_start)])
		var lo := maxi(1, int(round(float(bounds.min) * scale)))
		var hi := maxi(lo, int(round(float(bounds.max) * scale)))
		fixed.append({"stat": stat, "value": r.randi_range(lo, hi)})
	if fixed.size() + percent.size() != affix_count:
		push_error("[ItemFactory] %s 的 %s 品质词条池不足" % [item_id, quality])
		return {}
	return {
		"kind": "equip", "itemId": item_id,
		"instanceId": "%s_%s" % [instance_prefix, Crypto.new().generate_random_bytes(16).hex_encode()],
		"equipmentRuleVersion": 4, "requiredLevel": required_level, "level": required_level,
		"quality": quality, "star": 0,
		"rawBaseAttrs": (raw_bases[str(tier_start)] as Dictionary).duplicate(true),
		"qualityMultiplierSnapshot": float(q.get("baseMultiplier", 1.0)),
		"starMultiplierSnapshot": float(cfg.get("starMult", 0.1)),
		"affixes": fixed, "pctAttrs": percent, "count": 1,
	}

## 依 id 自动判类构造（装备 / 药水 / 杂项 / 如意）。找不到返回空字典。
## 装备不参与堆叠，count 被忽略（5.8）。
static func make_any(item_id: String, count: int = 1) -> Dictionary:
	if item_id.is_empty():
		return {}
	if DataLoader.get_entry("equipments", item_id) is Dictionary:
		return make_equip(item_id)
	if DataLoader.get_entry("potions", item_id) is Dictionary:
		return {"kind": "potion", "itemId": item_id, "count": count}
	if DataLoader.get_entry("miscItems", item_id) is Dictionary:
		return {"kind": "misc", "itemId": item_id, "count": count}
	if DataLoader.get_entry("runes", item_id) is Dictionary:
		return {"kind": "rune", "itemId": item_id, "count": count}
	return {}

## 为正常游戏生成随机词条；测试可传入带固定种子的随机数发生器。
static func _default_rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.randomize()
	return r
