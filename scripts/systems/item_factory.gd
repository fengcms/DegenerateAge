class_name ItemFactory
extends RefCounted
## 物品实例工厂（M2；工程文档 11 §4.3 F1 去重）。
##
## 背景：装备实例构造原先散在 4 处（`Loot._roll_equip` / `Shop.make_item` /
## 任务奖励 / 已移除的开发期测试装备），重复且容易漂移。本层收敛为**一处**「模板 → 实例」的
## 朴素构造：品质 / 等级 / 属性**原样取自模板**，不做缩放与随机。
##
## 边界（R-g）：随机品质权重 / 随机词条 / 等级缩放**仍归 `Loot._roll_equip`**，本层不碰。
## 用途：任务奖励发放（`Quest`）、货郎构造商品（`Shop`）。

static var _seq: int = 0

## 依模板构造一件装备实例（属性原样取自模板，不做缩放与随机）。
## level ≤ 0 时取模板的 levelReq。模板不存在返回空字典（不静默凭空造物）。
## instance_prefix：实例 id 前缀（调用方自定义，便于辨识来源，如任务 / 商店）。
static func make_equip(item_id: String, level: int = 0, instance_prefix: String = "inst") -> Dictionary:
	var tpl = DataLoader.get_entry("equipments", item_id)
	if not (tpl is Dictionary):
		return {}
	var lv := level if level > 0 else int(tpl.get("levelReq", 1))
	_seq += 1
	return {
		"kind": "equip",
		"itemId": item_id,
		"instanceId": "%s_%d_%d" % [instance_prefix, Time.get_ticks_msec(), _seq],
		"quality": String(tpl.get("quality", "common")),
		"level": lv,
		"baseAttrs": _dup_dict(tpl.get("baseAttrs", {})),
		"affixes": _dup_arr(tpl.get("affixes", [])),
		"pctAttrs": _dup_arr(tpl.get("pctAttrs", [])),
		"star": 0,
		"count": 1,
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

static func _dup_dict(v: Variant) -> Dictionary:
	return (v as Dictionary).duplicate(true) if v is Dictionary else {}

static func _dup_arr(v: Variant) -> Array:
	return (v as Array).duplicate(true) if v is Array else []
