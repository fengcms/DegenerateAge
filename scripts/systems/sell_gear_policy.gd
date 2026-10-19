class_name SellGearPolicy
extends RefCounted
## 装备批量出售的纯筛选规则：按角色等级、品质和保护状态生成本次清单。
## 不修改背包或金币；背包直卖与货郎暂存共用此预览，最终交易仍须重新校验。

const CAUTIOUS := "cautious"
const STANDARD := "standard"
const AGGRESSIVE := "aggressive"
const PRESETS := [CAUTIOUS, STANDARD, AGGRESSIVE]
const RULES := {
	CAUTIOUS: {"level_gap": 10, "max_quality": "common"},
	STANDARD: {"level_gap": 10, "max_quality": "uncommon"},
	AGGRESSIVE: {"level_gap": 5, "max_quality": "uncommon"},
}

## 返回预设是否合法，供设置入口和存档校验共用。
static func valid_preset(preset: String) -> bool:
	return PRESETS.has(preset)

## 给一件背包装备生成稳定的预览条目；非装备返回空字典。
## `bag_index` 只用于展示，成交按 instanceId 重定位；实例快照供确认时防止误卖。
static func entry(item: Dictionary, bag_index: int, player_level: int,
		equipment: Dictionary, preset: String) -> Dictionary:
	if String(item.get("kind", "")) != "equip" or not valid_preset(preset):
		return {}
	var preview := Equipment.replacement_preview(equipment, item)
	var favorite := bool(item.get("favorite", false))
	var sellable := Shop.can_sell(item)
	var reasons: Array[String] = []
	if favorite:
		reasons.append("favorite")
	if not sellable and not favorite:
		reasons.append("unsellable")
	var stronger := bool(preview.get("score_increase", false))
	if stronger:
		reasons.append("upgrade")
	if int(item.get("star", 0)) > 0:
		reasons.append("starred")
	var quality := Shop.item_quality(item)
	var quality_rank := Shop.QUALITY_ORDER.find(quality)
	var rule: Dictionary = RULES[preset]
	if quality_rank > Shop.QUALITY_ORDER.find(String(rule.max_quality)):
		reasons.append("quality")
	if Equipment.level_req(item) > player_level - int(rule.level_gap):
		reasons.append("level")
	var automatic := reasons.is_empty() and bool(preview.get("ok", false))
	return {"instance_id": String(item.get("instanceId", "")), "bag_index": bag_index,
		"item_snapshot": item.duplicate(true), "price": Shop.sell_price(item),
		"score_delta": float(preview.get("score_delta", 0.0)),
		"default_selected": automatic, "manual_selectable": sellable and not favorite,
		"reasons": reasons, "protected_upgrade": stronger}

## 按当前背包格顺序构建一次性清单；最多扫描背包容量，不在逐帧入口调用。
static func build_preview(inventory: Array, player_level: int,
		equipment: Dictionary, preset: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if not valid_preset(preset):
		return rows
	for i in range(inventory.size()):
		if inventory[i] is Dictionary:
			var row := entry(inventory[i], i, player_level, equipment, preset)
			if not row.is_empty():
				rows.append(row)
	return rows
