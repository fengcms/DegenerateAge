class_name EquipmentFusion
extends RefCounted
## 铁匠合成的纯规则层；按装备实例等级判档，不持有 UI 或背包状态。
## 四金、四紫和保星交易均在 GameState 二次验证后才可扣除物品。

const GOLD_TO_PURPLE := "gold_to_purple"
const PURPLE_TARGET := "purple_target"
const STAR_TRANSFER := "star_transfer"

## 从实例穿戴等级计算十级档起点；无效等级返回 0。
static func tier_start(item: Dictionary) -> int:
	var level := int(item.get("requiredLevel", 0))
	if level < 1 or level > ItemFactory.INSTANCE_LEVEL_CAP:
		return 0
	return floori(float(level - 1) / 10.0) * 10 + 1

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
	if items.size() != 4 or mode not in [GOLD_TO_PURPLE, PURPLE_TARGET]:
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
		if mode == PURPLE_TARGET:
			if String(item.get("quality", "")) != "legendary":
				return {"ok": false, "reason": "指定合成只接受紫色传说装备"}
			if star == Upgrade.max_star():
				return {"ok": false, "reason": "12 星紫装不能用于指定合成"}
			if first_tier > 0 and tier != first_tier:
				return {"ok": false, "reason": "四件紫装必须属于同一等级档"}
		first_tier = tier
		minimum = mini(minimum, tier)
	if mode == PURPLE_TARGET and not Equipment.slot_kinds().has(target_kind):
		return {"ok": false, "reason": "请选择目标装备类型"}
	var kinds := [target_kind] if mode == PURPLE_TARGET else Equipment.slot_kinds()
	for kind in kinds:
		if template_for(minimum, String(kind)).is_empty():
			return {"ok": false, "reason": "目标等级档缺少装备型号"}
	return {"ok": true, "tier": minimum, "target_kind": target_kind, "reason": ""}

## 返回 0→12 连续成功时的金币和；费用只读现行 Upgrade 配置。
static func full_star_cost() -> int:
	var total := 0
	for star in range(Upgrade.max_star()):
		total += Upgrade.cost(star)
	return total

## 校验低档 12 星与相邻高档 0 星紫装；两件均消耗并重随机产物词条。
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
	if old_tier == 0 or new_tier != old_tier + ItemFactory.TIER_SPAN or kind.is_empty() \
			or Equipment.item_kind(new_item) != kind:
		return {"ok": false, "reason": "只能向相邻高一档的同类型紫装保星升级"}
	if template_for(new_tier, kind).is_empty():
		return {"ok": false, "reason": "目标等级档缺少装备型号"}
	return {"ok": true, "tier": new_tier, "target_kind": kind, "cost": full_star_cost(), "reason": ""}
