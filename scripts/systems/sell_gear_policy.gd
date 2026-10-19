class_name SellGearPolicy
extends RefCounted
## 装备批量出售的纯筛选规则：按角色等级/档位、品质和保护状态生成本次清单。
## 不修改背包或金币；背包直卖与货郎暂存共用此预览，最终交易仍须重新校验。

const CAUTIOUS := "cautious"
const STANDARD := "standard"
const AGGRESSIVE := "aggressive"
## 暴力：跳过全部「价值判断」，背包内所有可售装备一次性打包出售（工程 61）。
## 「可售」仍是硬门槛 —— 任务物品与无价物品回收价为 0，卖了等于白扔，
## 且任务装备消失会让主线节点指向不存在的物品。收藏同样不卖（玩家亲手打的保护标记）。
const BRUTAL := "brutal"
const PRESETS := [CAUTIOUS, STANDARD, AGGRESSIVE, BRUTAL]
## 可写进存档的预设。**暴力不在其中**，两理由：
##   ① 存档里出现 `brutal` 而 `SettingsRuntime.CHOICE_VALUES` 漏登记 ⇒ 整档判损坏（M5-9c 同款事故）；
##   ② 持久化会让「下次打开面板时 40 格装备已经全部勾好」，一次手滑清空背包。
const PERSISTABLE := [CAUTIOUS, STANDARD, AGGRESSIVE]
## `level_gap` 为**可选键**：不写该键即表示该预设不设等级门槛（积极）。
## `require_older_suit` 为真时改用「旧套档」判据 —— 与「十级一套」模型对齐，见 `ItemFactory.suit_start`。
## 三个预设的品质上限：谨慎只放行普通，标准/积极放行到稀有（白/蓝/绿）。
## 暴力走 `entry()` 里的独立分支，不读本表；登记空字典只为防止误用 `RULES[preset]` 时崩。
const RULES := {
	CAUTIOUS: {"level_gap": 10, "max_quality": "common"},
	STANDARD: {"require_older_suit": true, "max_quality": "rare"},
	AGGRESSIVE: {"max_quality": "rare"},
	BRUTAL: {},
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
	# 暴力预设（工程 61）：只保留「能不能卖」这一条硬门槛，其余价值判断全部跳过。
	# 不调用 `Equipment.replacement_preview` —— 玩家已明确不看评分，算了也不展示。
	if preset == BRUTAL:
		var brutal_sellable := Shop.can_sell(item)
		var brutal_reasons: Array[String] = []
		# 理由只用于 tooltip 说明「为什么它没被勾上」；收藏与无价是仅剩的两个拦截原因。
		if bool(item.get("favorite", false)):
			brutal_reasons.append("favorite")
		elif not brutal_sellable:
			brutal_reasons.append("unsellable")
		return {"instance_id": String(item.get("instanceId", "")), "bag_index": bag_index,
			"item_snapshot": item.duplicate(true), "price": Shop.sell_price(item),
			"player_level": player_level, "preset": preset, "score_delta": 0.0,
			"default_selected": brutal_sellable, "manual_selectable": brutal_sellable,
			"reasons": brutal_reasons, "protected_upgrade": false}
	var preview := Equipment.replacement_preview(equipment, item)
	var favorite := bool(item.get("favorite", false))
	var sellable := Shop.can_sell(item)
	var reasons: Array[String] = []
	if favorite:
		reasons.append("favorite")
	if not sellable and not favorite:
		reasons.append("unsellable")
	# V1：空槽（评分基准 0）不计入保护 —— 该槽类还有空位时不再整类卖不掉。
	var stronger := not bool(preview.get("empty", true)) and bool(preview.get("score_increase", false))
	if stronger:
		reasons.append("upgrade")
	if int(item.get("star", 0)) > 0:
		reasons.append("starred")
	var quality := Shop.item_quality(item)
	var quality_rank := Shop.QUALITY_ORDER.find(quality)
	var rule: Dictionary = RULES[preset]
	if quality_rank > Shop.QUALITY_ORDER.find(String(rule.max_quality)):
		reasons.append("quality")
	if rule.has("level_gap") and Equipment.level_req(item) > player_level - int(rule.level_gap):
		reasons.append("level")
	if bool(rule.get("require_older_suit", false)):
		var suit := ItemFactory.suit_start(Equipment.level_req(item))
		if suit == 0 or suit >= ItemFactory.suit_start(player_level):
			reasons.append("suit")
	var automatic := reasons.is_empty() and bool(preview.get("ok", false))
	return {"instance_id": String(item.get("instanceId", "")), "bag_index": bag_index,
		"item_snapshot": item.duplicate(true), "price": Shop.sell_price(item),
		"player_level": player_level, "preset": preset,
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
