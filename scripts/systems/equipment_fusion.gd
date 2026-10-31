class_name EquipmentFusion
extends RefCounted
## 铁匠合成的纯规则层；按装备实例等级判档，不持有 UI 或背包状态。
## 四金、四紫和保星交易均在 GameState 二次验证后才可扣除物品。

const GOLD_TO_PURPLE := "gold_to_purple"
const PURPLE_TARGET := "purple_target"
const PURPLE_UP_TIER := "purple_up_tier"
const STAR_TRANSFER := "star_transfer"
## 工程 87：紫装献祭。**不是铁匠合成**——它不产生新装备、不吃材料格、不碰随机流，
## 只是复用 `equipment_fusion_panel` 的面板骨架；真正的规则在 `Sacrifice`。
## 放在这里是为了让铁匠菜单与面板共用同一套 mode 白名单。
const SACRIFICE := "sacrifice"

## 一次合成允许的材料件数区间（含端点）。
## 只有四紫升紫用「件数换成功率」：4 件必成、3 件 75%、2 件 50%；
## 四金与四紫定向的产物更值钱（品质跃迁 / 可指定部位），固定四件不打折。
static func material_range(mode: String) -> Vector2i:
	if mode == STAR_TRANSFER:
		return Vector2i(2, 2)
	if mode == PURPLE_UP_TIER:
		return Vector2i(2, 4)
	return Vector2i(4, 4)

## 投入件数决定成功率：4 件必成，3 件 75%，2 件 50%。
## 🔑 期望材料消耗恒为 4 件（n ÷ (n/4) ≡ 4）：件数少只是方差大，**不会更便宜**。
## 所以这个阶梯不是「打折」，是「用波动换出手速度」，界面必须写明失败全损。
static func success_rate(count: int) -> float:
	return clampf(float(count) / 4.0, 0.0, 1.0)

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

## 校验 2—4 件材料并返回输出档；目标部位仅在四紫定向使用。
## 件数区间由 `material_range()` 决定；四紫升紫额外返回 `count` 与 `rate`（成功率）。
static func plan_four(items: Array[Dictionary], mode: String, target_kind: String = "",
		checked_templates: Variant = null) -> Dictionary:
	if mode not in [GOLD_TO_PURPLE, PURPLE_TARGET, PURPLE_UP_TIER]:
		return {"ok": false, "reason": "未知的合成模式"}
	var limits := material_range(mode)
	if items.size() < limits.x or items.size() > limits.y:
		return {"ok": false, "reason": "四紫升紫需要 2—4 件同档紫装" if mode == PURPLE_UP_TIER
			else "请选择四件合规装备"}
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
				return {"ok": false, "reason": "紫装材料必须属于同一等级档"}
		first_tier = tier
		minimum = mini(minimum, tier)
	if mode == PURPLE_TARGET and not Equipment.slot_kinds().has(target_kind):
		return {"ok": false, "reason": "请选择目标装备类型"}
	var output_tier := minimum + ItemFactory.TIER_SPAN if mode == PURPLE_UP_TIER else minimum
	if mode == PURPLE_UP_TIER and output_tier > transfer_max_tier():
		return {"ok": false, "reason": "目标档已超出装备等级上限"}
	var kinds := [target_kind] if mode == PURPLE_TARGET else Equipment.slot_kinds()
	# 仅供单次批量计划复用模板校验；调用方每轮新建，禁止跨数据重载持久化。
	var cache: Dictionary = checked_templates if checked_templates is Dictionary else {}
	var cache_key := "%s:%d:%s" % [mode, output_tier, target_kind]
	if not cache.has(cache_key):
		for kind in kinds:
			if template_for(output_tier, String(kind)).is_empty():
				return {"ok": false, "reason": "目标等级档缺少装备型号"}
		cache[cache_key] = true
	return {"ok": true, "tier": output_tier, "target_kind": target_kind,
		"count": items.size(),
		"rate": success_rate(items.size()) if mode == PURPLE_UP_TIER else 1.0, "reason": ""}

## 随机放入只预选**最低合格档**的 0 星未收藏装备；不修改背包与现有合成规则。
## 🔑 严格最低档：低档料就是肥料，高档紫装要留给穿戴与保星升级，不该被「省事」按钮吃掉。
## 旧实现是「筛出够件的档再等概率抽一个」，会把背包里存着的 71 档当 51 档一起吃；
## 那条注释已作废，别再照它改回去。
static func random_materials(inventory: Array, mode: String, rng: RandomNumberGenerator = null) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if mode not in [GOLD_TO_PURPLE, PURPLE_TARGET, PURPLE_UP_TIER]:
		return result
	var limits := material_range(mode)
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
		if (groups[tier] as Array).size() >= limits.x:
			tiers.append(int(tier))
	if tiers.is_empty():
		return result
	# 最低档优先：四紫升紫最低档可能只有 2—3 件，那就只填 2—3 格（成功率由件数决定）。
	tiers.sort()
	var pool: Array = (groups[tiers[0]] as Array).duplicate()
	var take := mini(limits.y, pool.size())
	for _i in range(take):
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

## 保星产物的**实际**穿戴等级：与 `make_output` 同一条口径（`dynamic_level_for`），
## 但只查表、不造实例、不吃 RNG，所以预览里可以反复调用。
## 🔴 提示必须读这里，不能读材料等级（`new_item.requiredLevel`）：同档同部位时两者相等，
## 但旧规则的逐级实例（如 115 级武器，`suit_start` 归到 111 档）会让材料等级比产物高 4 级，
## 少报的那个方向会让玩家到手才发现穿不上。
static func transfer_output_level(tier: int, kind: String) -> int:
	var template_id := template_for(tier, kind)
	if template_id.is_empty():
		return 0
	return ItemFactory.dynamic_level_for(template_id, tier)

## 产物在当前等级下穿不上就返回它的需求等级，穿得上返回 0。
## UI 的预览行、二次确认、成功 toast 与测试**共用这一个判据**，
## 避免三处各写一遍 `<` 之后各自漂移（工程 08 第 20 条同族）。
static func transfer_locked_level(output_level: int, player_level: int) -> int:
	return output_level if output_level > player_level else 0

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
	# `required` 是**材料**等级（既有断言与旧 UI 都读它，语义不动）；
	# `outputLevel` 才是产物等级 —— 新 UI 与工程 96 的提示一律读后者。
	return {"ok": true, "tier": new_tier, "target_kind": kind, "gap": gap,
		"required": int(new_item.get("requiredLevel", 0)),
		"outputLevel": transfer_output_level(new_tier, kind),
		"cost": full_star_cost() * gap, "reason": ""}
