class_name GoldBatchFusion
extends RefCounted
## 纯分组规则：固定候选，同档先组，再按低档到高档合并余数。
static func candidates(inventory: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen := {}
	for raw in inventory:
		if not raw is Dictionary or raw.get("kind") != "equip" or raw.get("quality") != "epic" or raw.get("favorite", false):
			continue
		var id := String(raw.get("instanceId", ""))
		if id.is_empty() or seen.has(id) or not SaveManager._valid_item(raw):
			continue
		seen[id] = true
		out.append(raw.duplicate(true))
	return out

static func plan(frozen: Array, include_starred: bool = false, excluded: Array = []) -> Dictionary:
	var buckets := {}
	var eligible: Array[Dictionary] = []
	var protected_count := 0
	for item in frozen:
		if excluded.has(String(item.instanceId)):
			continue
		if not include_starred and int(item.star) > 0:
			protected_count += 1
			continue
		eligible.append(item)
		var tier := EquipmentFusion.tier_start(item)
		if not buckets.has(tier):
			buckets[tier] = []
		buckets[tier].append(item)
	var tiers := buckets.keys()
	tiers.sort()
	var groups: Array = []
	var leftovers: Array = []
	for tier in tiers:
		var rows: Array = buckets[tier]
		rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.instanceId) < String(b.instanceId))
		while rows.size() >= 4:
			groups.append(rows.slice(0, 4))
			rows = rows.slice(4)
		leftovers.append_array(rows)
	while leftovers.size() >= 4:
		groups.append(leftovers.slice(0, 4))
		leftovers = leftovers.slice(4)
	var outputs := {}
	var mixed := 0
	var downgraded := 0
	var starred := 0
	var checked_templates := {}
	for raw_group in groups:
		var group: Array[Dictionary] = []
		group.assign(raw_group)
		var check := EquipmentFusion.plan_four(group, EquipmentFusion.GOLD_TO_PURPLE, "", checked_templates)
		if not bool(check.get("ok", false)):
			return {"ok": false, "reason": String(check.get("reason", ""))}
		var tier := int(check.tier)
		outputs[tier] = int(outputs.get(tier, 0)) + 1
		var cross := false
		for item in group:
			if EquipmentFusion.tier_start(item) > tier:
				cross = true
				downgraded += 1
			if int(item.star) > 0:
				starred += 1
		mixed += int(cross)
	return {"ok": true, "reason": "", "groups": groups, "eligible": eligible.size(), "protected": protected_count,
		"remaining": leftovers.size(), "outputs": outputs, "mixed": mixed, "downgraded": downgraded, "starred": starred}
