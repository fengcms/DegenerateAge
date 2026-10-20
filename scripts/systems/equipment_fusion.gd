class_name EquipmentFusion
extends RefCounted
## 铁匠合成的纯规则层；按装备实例等级判档，不持有 UI 或背包状态。
## 四金、四紫和保星交易均在 GameState 二次验证后才可扣除物品。

const GOLD_TO_PURPLE := "gold_to_purple"
const PURPLE_TARGET := "purple_target"
const PURPLE_UP_TIER := "purple_up_tier"
const STAR_TRANSFER := "star_transfer"

## 从实例穿戴等级计算十级档起点；无效等级返回 0。
## 公式与出售预设共用 `ItemFactory.suit_start`，避免两处口径各自漂移。
static func tier_start(item: Dictionary) -> int:
	return ItemFactory.suit_start(int(item.get("requiredLevel", 0)))

## 按十级档和装备类型找唯一正式型号；61+ 复用第 51 套型号。
static func template_for(tier: int, kind: String) -> String:
	if tier < 1 or kind.is_empty():
		return ""
	var base := mini(tier, ItemFactory.DYNAMIC_BASE_TIER)
	var result := ""
	for raw in DataLoader.get_table("equipments"):
		if not raw is Dictionary or String(raw.get("slot", "")) != kind:
			continue
		var bases: Variant = raw.get("tierBases", {})
		if bases is Dictionary and bases.has(str(base)):
			if not result.is_empty():
				return ""
			result = String(raw.get("id", ""))
	return result

## 生成对应档与部位的新紫装；只在全部交易前置条件通过后调用。
static func make_output(tier: int, kind: String, rng: RandomNumberGenerator = null) -> Dictionary:
	var template_id := template_for(tier, kind)
	if template_id.is_empty():
		return {}
	if tier > Balance.SOFTCAP_LEVEL:
		var required := ItemFactory.dynamic_level_for(template_id, tier)
		if required < tier or required > ItemFactory.INSTANCE_LEVEL_CAP:
			return {}
		return ItemFactory.make_equip_dynamic(template_id, tier, "legendary", rng, "fusion")
	return ItemFactory.make_equip_roll(template_id, tier, "legendary", rng, "fusion")

## 校验四件背包材料并返回输出档；目标部位仅在四紫模式使用。
static func plan_four(items: Array[Dictionary], mode: String, target_kind: String = "") -> Dictionary:
	if items.size() != 4 or mode not in [GOLD_TO_PURPLE, PURPLE_TARGET, PURPLE_UP_TIER]:
		return {"ok": false, "reason": "请选择四件合规装备"}
	var seen := {}
	var minimum := ItemFactory.INSTANCE_LEVEL_CAP
	var first_tier := 0
	for item in items:
		var id := String(item.get("instanceId", ""))
		var tier := tier_start(item)
		if id.is_empty() or seen.has(id) or String(item.get("kind", "")) != "equip" \
				or bool(item.get("favorite", false)) or tier == 0 or Equipment.item_kind(item).is_empty():
			return {"ok": false, "reason": "材料重复、已收藏或不是有效装备"}
		seen[id] = true
		var star := int(item.get("star", -1))
		if star < 0 or star > Upgrade.max_star():
			return {"ok": false, "reason": "材料星级无效"}
		if mode == GOLD_TO_PURPLE and String(item.get("quality", "")) != "epic":
			return {"ok": false, "reason": "金装合成只接受金色史诗装备"}
		if mode in [PURPLE_TARGET, PURPLE_UP_TIER]:
			if String(item.get("quality", "")) != "legendary":
				return {"ok": false, "reason": "四紫合成只接受紫色传说装备"}
			if star == Upgrade.max_star():
				return {"ok": false, "reason": "12 星紫装不能用于四紫合成"}
			if first_tier > 0 and tier != first_tier:
				return {"ok": false, "reason": "四件紫装必须属于同一等级档"}
		first_tier = tier
		minimum = mini(minimum, tier)
	if mode == PURPLE_TARGET and not Equipment.slot_kinds().has(target_kind):
		return {"ok": false, "reason": "请选择目标装备类型"}
	var output_tier := minimum + ItemFactory.TIER_SPAN if mode == PURPLE_UP_TIER else minimum
	if mode == PURPLE_UP_TIER and output_tier > transfer_max_tier():
		return {"ok": false, "reason": "目标档已超出装备等级上限"}
	var kinds := [target_kind] if mode == PURPLE_TARGET else Equipment.slot_kinds()
	for kind in kinds:
		if template_for(output_tier, String(kind)).is_empty():
			return {"ok": false, "reason": "目标等级档缺少装备型号"}
	return {"ok": true, "tier": output_tier, "target_kind": target_kind, "reason": ""}

## 随机放入只预选同档四件 0 星未收藏装备；不修改背包与现有合成规则。
## 先等概率抽合格档，再在该档无放回抽四件，避免容量大的档独占选择机会。
static func random_materials(inventory: Array, mode: String, rng: RandomNumberGenerator = null) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if mode not in [GOLD_TO_PURPLE, PURPLE_TARGET, PURPLE_UP_TIER]:
		return result
	var groups := {}
	for entry in inventory:
		if not entry is Dictionary or String(entry.get("kind", "")) != "equip" \
				or bool(entry.get("favorite", false)) or int(entry.get("star", -1)) != 0 \
				or String(entry.get("instanceId", "")).is_empty():
			continue
		var quality := String(entry.get("quality", ""))
		if (mode == GOLD_TO_PURPLE and quality != "epic") \
				or (mode in [PURPLE_TARGET, PURPLE_UP_TIER] and quality != "legendary"):
			continue
		var tier := tier_start(entry)
		if tier == 0 or Equipment.item_kind(entry).is_empty() \
				or (mode == PURPLE_UP_TIER and tier + ItemFactory.TIER_SPAN > transfer_max_tier()):
			continue
		if not groups.has(tier):
			groups[tier] = []
		(groups[tier] as Array).append(entry)
	var tiers: Array[int] = []
	for tier in groups:
		if (groups[tier] as Array).size() >= 4:
			tiers.append(int(tier))
	if tiers.is_empty():
		return result
	tiers.sort()
	var tier_index := rng.randi_range(0, tiers.size() - 1) if rng != null else randi_range(0, tiers.size() - 1)
	var pool: Array = (groups[tiers[tier_index]] as Array).duplicate()
	for _i in range(4):
		var index := rng.randi_range(0, pool.size() - 1) if rng != null else randi_range(0, pool.size() - 1)
		result.append((pool[index] as Dictionary).duplicate(true))
		pool.remove_at(index)
	return result

## 返回 0→12 连续成功时的金币和；费用只读现行 Upgrade 配置。
static func full_star_cost() -> int:
	var total := 0
	for star in range(Upgrade.max_star()):
		total += Upgrade.cost(star)
	return total

## 保星跨档数：档差必须是十级的整数倍；同档、降档、非整档或旧档无效一律返回 0。
## 费用与档位无关，只按这个倍数放大「跨 1 档」的基准价。
static func transfer_gap(old_tier: int, new_tier: int) -> int:
	var diff := new_tier - old_tier
	if old_tier <= 0 or diff <= 0 or diff % ItemFactory.TIER_SPAN != 0:
		return 0
	return int(round(float(diff) / float(ItemFactory.TIER_SPAN)))

## 保星可选的最高套起点。再往上 `make_output` 会造出超过实例等级上限的产物，
## 那时只剩「目标装备生成失败」这种玩家看不懂的兜底文案。
static func transfer_max_tier() -> int:
	return ItemFactory.INSTANCE_LEVEL_CAP - (ItemFactory.TIER_SPAN - 1)

## 校验低档 12 星与更高档 0 星紫装；两件均消耗并重随机产物词条。
## 跨档数只放大金币，不改变星级 / 品质 / 部位规则。
static func plan_transfer(old_item: Dictionary, new_item: Dictionary) -> Dictionary:
	if String(old_item.get("instanceId", "")).is_empty() or String(new_item.get("instanceId", "")).is_empty() \
			or String(old_item.instanceId) == String(new_item.instanceId):
		return {"ok": false, "reason": "请选择两件不同的装备"}
	if String(old_item.get("kind", "")) != "equip" or String(new_item.get("kind", "")) != "equip" \
			or String(old_item.get("quality", "")) != "legendary" \
			or String(new_item.get("quality", "")) != "legendary" \
			or bool(old_item.get("favorite", false)) or bool(new_item.get("favorite", false)):
		return {"ok": false, "reason": "保星只接受未收藏的两件紫装"}
	if int(old_item.get("star", -1)) != Upgrade.max_star() or int(new_item.get("star", -1)) != 0:
		return {"ok": false, "reason": "旧装须为 12 星，新档装备须为 0 星"}
	var old_tier := tier_start(old_item)
	var new_tier := tier_start(new_item)
	var kind := Equipment.item_kind(old_item)
	var gap := transfer_gap(old_tier, new_tier)
	if gap == 0 or kind.is_empty() or Equipment.item_kind(new_item) != kind:
		return {"ok": false, "reason": "只能向更高档的同类型紫装保星升级"}
	if new_tier > transfer_max_tier():
		return {"ok": false, "reason": "目标档已超出装备等级上限"}
	if template_for(new_tier, kind).is_empty():
		return {"ok": false, "reason": "目标等级档缺少装备型号"}
	return {"ok": true, "tier": new_tier, "target_kind": kind, "gap": gap,
		"required": int(new_item.get("requiredLevel", 0)),
		"cost": full_star_cost() * gap, "reason": ""}
