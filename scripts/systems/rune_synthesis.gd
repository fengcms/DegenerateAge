class_name RuneSynthesis
extends RefCounted
## 三档批量计算净变化，先扣净减少量再加入净增加量；失败副本直接丢弃。
const IDS := ["rune_iron", "rune_jade", "rune_gold", "rune_diamond"]

static func validate_config(config: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var rows: Variant = config.get("runeSynthesis")
	if not rows is Array or rows.size() != IDS.size() - 1:
		return ["[warehouse] runeSynthesis 必须包含三档配方"]
	for i in range(rows.size()):
		var row: Variant = rows[i]
		if not row is Dictionary:
			errors.append("[warehouse] 如意配方必须为对象")
			continue
		if row.get("sourceId") != IDS[i] or row.get("targetId") != IDS[i + 1]:
			errors.append("[warehouse] 如意配方必须按铁、玉、金、钻石顺序升档")
		for key in ["sourceCount", "targetCount"]:
			var count: Variant = row.get(key)
			if not (count is int or count is float) or not is_finite(float(count)) or float(count) != floor(float(count)) or float(count) < 1.0 or float(count) > 1000000.0:
				errors.append("[warehouse] 如意配方数量必须为有效正整数")
		for id in [IDS[i], IDS[i + 1]]:
			if not DataLoader.get_entry("runes", id) is Dictionary:
				errors.append("[warehouse] 如意模板不存在：" + id)
	return errors

static func plan(store: Array) -> Dictionary:
	var config := Warehouse.config()
	if not validate_config(config).is_empty():
		return _fail("msg.rune_synthesis.config")
	for entry in store:
		if entry is Dictionary and entry.get("kind") == "rune" and IDS.has(entry.get("itemId")):
			var count: Variant = entry.get("count")
			if not (count is int or count is float) or not is_finite(float(count)) or float(count) != floor(float(count)) or float(count) < 1.0 or float(count) > ItemUtil.stack_max(entry):
				return _fail("msg.rune_synthesis.invalid")
	var before := RuneCharge.inventory_counts(store)
	var after := before.duplicate()
	var changed := false
	for row in config.runeSynthesis:
		var source := String(row.sourceId)
		var target := String(row.targetId)
		var times: int = int(after.get(source, 0)) / int(row.sourceCount)
		if times > 0:
			changed = true
			after[source] = int(after.get(source, 0)) - times * int(row.sourceCount)
			after[target] = int(after.get(target, 0)) + times * int(row.targetCount)
	if not changed:
		return _fail("msg.rune_synthesis.empty")
	var pending := store.duplicate(true)
	for id in IDS:
		var remove := int(before.get(id, 0)) - int(after.get(id, 0))
		for i in range(pending.size()):
			if remove <= 0:
				break
			var entry: Variant = pending[i]
			if not entry is Dictionary or entry.get("kind") != "rune" or entry.get("itemId") != id:
				continue
			var used := mini(remove, int(entry.count))
			entry.count = int(entry.count) - used
			remove -= used
			if int(entry.count) == 0:
				pending[i] = null
	for id in IDS:
		var add := int(after.get(id, 0)) - int(before.get(id, 0))
		if add > 0 and not Inventory.add(pending, ItemFactory.make_any(id, add)):
			return _fail("msg.rune_synthesis.space")
	return {"ok": true, "reason": "", "store": pending, "before": before, "after": after}

static func summary(result: Dictionary) -> String:
	var parts: Array[String] = []
	for id in IDS:
		var before := int(result.before.get(id, 0))
		var after := int(result.after.get(id, 0))
		if before != after:
			parts.append(Localization.tr_key("msg.rune_synthesis.change", [ItemUtil.display_name(ItemFactory.make_any(id)), before, after]))
	return Localization.tr_key("msg.rune_synthesis.done", ["，".join(parts)])

static func _fail(key: String) -> Dictionary:
	return {"ok": false, "reason": Localization.tr_key(key)}
